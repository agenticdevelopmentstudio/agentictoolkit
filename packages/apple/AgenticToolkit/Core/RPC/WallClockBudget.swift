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

            let timeoutTask = Task<Void, Never> {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                race.finish(throwing: WallClockBudgetExceeded(seconds: seconds))
            }
            race.track(timeoutTask)
        }
    } onCancel: {
        race.cancel()
    }
}
