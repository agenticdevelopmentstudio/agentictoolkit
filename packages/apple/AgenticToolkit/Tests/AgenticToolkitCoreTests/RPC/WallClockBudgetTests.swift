import Foundation
import Testing
@testable import AgenticToolkitCore

/// `withWallClockBudget` resumes one continuation from a race between two
/// unstructured tasks, so its whole correctness surface is "exactly once,
/// across all three outcomes". All three are covered here: the operation
/// wins, the budget wins, and the caller cancels.
@Suite("WallClockBudget")
struct WallClockBudgetTests {

    /// Work that ignores cancellation entirely, so the budget cannot be
    /// passing by accident because the operation cooperated. `Thread.sleep`
    /// on a detached thread rather than `Task.sleep`, which is cancellable.
    private func uncancellableWork(seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                Thread.sleep(forTimeInterval: seconds)
                continuation.resume()
            }
            thread.start()
        }
    }

    @Test("the operation winning returns its value, well inside the budget")
    func operationWinningReturnsItsValue() async throws {
        let started = Date()
        let value = try await withWallClockBudget(10) { 42 }
        #expect(value == 42)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test("the budget winning throws immediately, without awaiting uncancellable work")
    func budgetWinningThrowsWithoutAwaitingTheLoser() async throws {
        let started = Date()
        await #expect(throws: WallClockBudgetExceeded(seconds: 0.5)) {
            try await withWallClockBudget(0.5) {
                await self.uncancellableWork(seconds: 5)
            }
        }
        // The loser is abandoned, not awaited: this must be ~0.5s, not ~5s.
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 2, "budget returned after \(elapsed)s; it should not await the loser")
    }

    @Test("cancelling the awaiting task propagates into the budget instead of waiting it out")
    func cancellingTheAwaitingTaskPropagates() async throws {
        // `Task.init` does not inherit cancellation, so without an explicit
        // cancellation handler this returns only when the 5s operation
        // finishes on its own — "cancel me" silently becoming "wait for me".
        let started = Date()
        let task = Task<TimeInterval, Never> {
            do {
                try await withWallClockBudget(10) {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                }
                return -1
            } catch is CancellationError {
                return Date().timeIntervalSince(started)
            } catch {
                return -2
            }
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()

        let elapsed = await task.value
        #expect(elapsed >= 0, "expected CancellationError, got a different outcome (\(elapsed))")
        #expect(elapsed < 2, "cancellation took \(elapsed)s; it should be near-immediate")
    }
}
