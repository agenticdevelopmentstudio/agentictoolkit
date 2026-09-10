import Foundation

/// Thrown by `withWallClockBudget` when `operation` did not finish within its
/// allotted time.
public struct WallClockBudgetExceeded: Error, LocalizedError, Equatable {
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public var errorDescription: String? {
        "The operation exceeded its \(String(format: "%g", seconds))s budget."
    }
}

/// The mutable state of one `withWallClockBudget` call: the single
/// `CheckedContinuation` the race resumes exactly once, and the two
/// unstructured tasks racing for it. Kept in one lock-protected object rather
/// than as three captured locals because the cancellation handler runs
/// concurrently with the continuation body and has to reach all three — it
/// must be able to cancel tasks that have not been created yet, and to resume
/// a continuation that has not been installed yet.
///
/// `@unchecked Sendable` because the lock, not the compiler, is what makes the
/// exactly-once resume and the cancel-before-create ordering hold.
private final class WallClockBudgetRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var isCancelled = false

    /// Hands the race its continuation. If the enclosing task was already
    /// cancelled before the continuation body ran, this resumes immediately
    /// with `CancellationError` rather than storing a continuation that
    /// nothing would ever resume.
    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Registers a racer so the winner (or the caller's cancellation) can
    /// cancel it. A task handed over after the race has already been decided
    /// is cancelled on the spot instead of being retained.
    func track(_ task: Task<Void, Never>) {
        lock.lock()
        let alreadySettled = isCancelled || continuation == nil
        if !alreadySettled { tasks.append(task) }
        lock.unlock()
        if alreadySettled { task.cancel() }
    }

    func finish(returning value: T) {
        settle { $0.resume(returning: value) }
    }

    func finish(throwing error: Error) {
        settle { $0.resume(throwing: error) }
    }

    /// The enclosing task was cancelled. Cancels both racers and resumes the
    /// continuation with `CancellationError` — `Task.init` does not inherit
    /// cancellation, so without this the racers would run to completion and
    /// "cancel me" would silently mean "wait for me".
    func cancel() {
        lock.lock()
        isCancelled = true
        lock.unlock()
        settle { $0.resume(throwing: CancellationError()) }
    }

    /// Resumes the continuation if it is still pending — at most one caller
    /// ever sees it — and then cancels every racer, winner included. The
    /// loser is *cancelled, never awaited*: cancellation is a best-effort
    /// request, and a budget that waited for it to take effect would be
    /// exactly the bug this function exists to avoid.
    private func settle(_ resume: (CheckedContinuation<T, Error>) -> Void) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let racers = tasks
        tasks.removeAll()
        lock.unlock()

        if let pending { resume(pending) }
        for task in racers { task.cancel() }
    }
}

/// The largest budget that is still a bound, in seconds — one year.
///
/// Above this a budget stops meaning "finish by then" and starts meaning "no
/// deadline", and the conversion to nanoseconds is where saying so matters:
/// `UInt64(seconds * 1_000_000_000)` is a *trapping* conversion that fires on
/// `.infinity`, on `.greatestFiniteMagnitude`, and on any finite value above
/// roughly 1.8e10 seconds. The value reaching this function is not always the
/// caller's own — `PluginTransport.run(spec:)` passes `AIRequestSpec.timeout`,
/// a public unvalidated `var` a third-party plugin bundle sets — so "a plugin
/// spelled *no timeout* the idiomatic way" must not be a way to kill the host
/// process.
///
/// A year rather than the true conversion limit (~584 years of nanoseconds)
/// because the point is plausibility, not arithmetic: no operation this
/// function wraps is legitimately bounded at a decade, and a caller that meant
/// "no deadline" is better served by getting exactly that than by a timer
/// nothing will outlive.
private let maximumWallClockBudgetSeconds: TimeInterval = 60 * 60 * 24 * 365

/// The nanosecond sleep a budget asks for, or `nil` when the budget is not a
/// bound at all and no timer should be started.
///
/// Three cases, and each is a decision rather than a fallout of the
/// arithmetic:
///
/// - **NaN → no budget.** `max(0, .nan)` evaluates to `0` in Swift, because
///   every comparison against NaN is false, so the obvious guard silently
///   turned a NaN into an *immediate* expiry — a budget that raced the
///   operation for a result. NaN is not a deadline in either direction, and
///   inventing the harshest possible one from it is the least defensible
///   reading.
/// - **At or above the ceiling (`.infinity` included) → no budget.** Returning
///   `nil` is what lets the caller skip creating the timer task entirely,
///   rather than parking one on a sleep that would outlive the process.
/// - **At or below zero (`-.infinity` included) → expire immediately.** Zero
///   is a legitimate budget meaning exactly that, and a negative one is a
///   deadline already past.
private func wallClockBudgetNanoseconds(_ seconds: TimeInterval) -> UInt64? {
    guard !seconds.isNaN else { return nil }
    guard seconds < maximumWallClockBudgetSeconds else { return nil }
    guard seconds > 0 else { return 0 }
    return UInt64(seconds * 1_000_000_000)
}

/// Races `operation` against a wall-clock timer: on expiry
/// `WallClockBudgetExceeded` is thrown immediately — the timed-out operation
/// is cancelled but **not awaited**, so a budget genuinely bounds wall-clock
/// time even when the work it wraps ignores cancellation (blocking I/O,
/// a `Process` wait that predates `SubprocessChannel`'s own cancellable
/// waits, etc). `withThrowingTaskGroup` cannot do this: leaving the group's
/// scope implicitly awaits every child task, including the loser, so the
/// timeout task's throw is not observable until the slow operation actually
/// finishes — which is not a timeout at all. Racing two independent
/// unstructured tasks against a single `CheckedContinuation`, resumed exactly
/// once by whichever finishes first, has no such implicit join.
///
/// The price of unstructured tasks is that they do **not** inherit the
/// caller's cancellation, so the race is wrapped in
/// `withTaskCancellationHandler`: cancelling the task that awaits a budget
/// cancels both racers and rethrows `CancellationError` promptly, instead of
/// waiting out the operation or the full budget. The continuation is resumed
/// exactly once across all three outcomes — operation wins, budget wins,
/// caller cancels.
///
/// **A budget that is not a bound is honoured as such, not as a trap.** A
/// `seconds` of `.infinity`, `.greatestFiniteMagnitude`, anything at or above
/// `maximumWallClockBudgetSeconds`, or `NaN` starts no timer at all: the
/// operation runs to completion or to the caller's cancellation, and nothing
/// throws `WallClockBudgetExceeded`. That is a real loss of bounding, and it
/// is the *caller's* to avoid by not asking for it — the alternative was
/// `UInt64(_:)` trapping on the conversion, which killed the whole process
/// over a number a third-party plugin bundle chose.
///
/// This is generic over the return value (rather than pinned to `Void`) so an
/// HTTP call and a subprocess run can both use it, and the timeout error is
/// its own type so a caller can map it onto its own domain error without this
/// module knowing about that type.
public func withWallClockBudget<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = WallClockBudgetRace<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { rawContinuation in
            race.install(rawContinuation)

            let operationTask = Task<Void, Never> {
                do {
                    let value = try await operation()
                    race.finish(returning: value)
                } catch {
                    race.finish(throwing: error)
                }
            }
            race.track(operationTask)

            // No timer at all for a budget that is not a bound — see
            // `wallClockBudgetNanoseconds`. The operation racer and the
            // cancellation handler both stand: "no deadline" must not quietly
            // become "not cancellable either", which is why this skips only
            // the timer and not the race.
            if let nanoseconds = wallClockBudgetNanoseconds(seconds) {
                let timeoutTask = Task<Void, Never> {
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard !Task.isCancelled else { return }
                    race.finish(throwing: WallClockBudgetExceeded(seconds: seconds))
                }
                race.track(timeoutTask)
            }
        }
    } onCancel: {
        race.cancel()
    }
}
