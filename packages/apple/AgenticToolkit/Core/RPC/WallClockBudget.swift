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

/// Races `operation` against a wall-clock timer: on expiry the operation is
/// cancelled and `WallClockBudgetExceeded` is thrown.
///
/// This is generic over the return value (rather than pinned to `Void`) so an
/// HTTP call and a subprocess run can both use it, and the timeout error is
/// its own type so a caller can map it onto its own domain error without this
/// module knowing about that type.
public func withWallClockBudget<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            throw WallClockBudgetExceeded(seconds: seconds)
        }
        defer { group.cancelAll() }
        // The first finisher wins; the loser is cancelled and its outcome
        // (typically CancellationError) discarded by the group.
        guard let result = try await group.next() else {
            // Unreachable: two tasks were added above, so `next()` always
            // yields at least one result before returning nil.
            throw WallClockBudgetExceeded(seconds: seconds)
        }
        return result
    }
}
