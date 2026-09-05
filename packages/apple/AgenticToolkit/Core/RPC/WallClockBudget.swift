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

/// Guards a single `CheckedContinuation` so it is resumed exactly once no
/// matter which of two racing tasks gets there first. `Process`-adjacent code
/// races a lot of things (a wait against a timer, a `terminate()` grace
/// period against exit), so this is shared rather than reinvented per call
/// site — it is `@unchecked Sendable` because the lock, not the compiler, is
/// what makes the single-resume guarantee hold.
final class SingleResumeContinuation<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = continuation
        continuation = nil
        return pending
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
/// detached tasks against a single `CheckedContinuation`, resumed exactly
/// once by whichever finishes first, has no such implicit join.
///
/// This is generic over the return value (rather than pinned to `Void`) so an
/// HTTP call and a subprocess run can both use it, and the timeout error is
/// its own type so a caller can map it onto its own domain error without this
/// module knowing about that type.
public func withWallClockBudget<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { rawContinuation in
        let resumer = SingleResumeContinuation<T>(rawContinuation)

        let operationTask = Task<Void, Never> {
            do {
                let value = try await operation()
                resumer.resume(returning: value)
            } catch {
                resumer.resume(throwing: error)
            }
        }

        let timeoutTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            resumer.resume(throwing: WallClockBudgetExceeded(seconds: seconds))
            // Cancel, but do not await, the loser: cancellation is a
            // best-effort request, and a budget that waited for it to take
            // effect would be exactly the bug this function exists to avoid.
            operationTask.cancel()
        }

        // If `operation` wins the race, the timer becomes the loser and is
        // cancelled here rather than left to fire uselessly later.
        Task {
            _ = await operationTask.value
            timeoutTask.cancel()
        }
    }
}
