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

    // MARK: - Budgets that are not bounds

    /// A budget that cannot be expressed as a `UInt64` nanosecond count is not
    /// a budget, and must not be a trap.
    ///
    /// `UInt64(seconds * 1_000_000_000)` is a *trapping* conversion: it fires
    /// on `.infinity`, on `.greatestFiniteMagnitude`, and on any finite value
    /// above roughly 1.8e10 seconds. `max(0, seconds)` guarded only the low
    /// end. `AIRequestSpec.timeout` is a public unvalidated `var` that reaches
    /// here through `PluginTransport.run(spec:)`, so a plugin spelling "no
    /// timeout" the idiomatic way used to kill the host process.
    ///
    /// A regression here is process-fatal rather than a recorded failure: the
    /// trap takes the whole test bundle down. Surviving the call is the
    /// assertion; the `#expect` is the cheap part.
    @Test(
        "a budget too large to express is no budget at all, not a trap",
        arguments: [TimeInterval.infinity, .greatestFiniteMagnitude, 1e18]
    )
    func unexpressibleBudgetIsNoBudget(_ seconds: TimeInterval) async throws {
        let started = Date()
        let value = try await withWallClockBudget(seconds) { 42 }
        #expect(value == 42)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    /// `max(0, .nan)` evaluates to `0` in Swift, because every comparison
    /// against NaN is false — so a NaN budget used to mean "expire
    /// immediately", racing the operation for a result. NaN is not a deadline
    /// in either direction; it is treated as no budget, deterministically.
    @Test("a NaN budget does not become a zero-second one")
    func nanBudgetIsNotAnImmediateExpiry() async throws {
        let value = try await withWallClockBudget(.nan) { 42 }
        #expect(value == 42)
    }

    /// Skipping the timeout racer must not skip the cancellation handler with
    /// it: an unbounded budget still has to answer `cancel()` promptly, or
    /// "no timeout" quietly becomes "not cancellable either".
    @Test("an unbounded budget still propagates the caller's cancellation")
    func unboundedBudgetStillCancels() async throws {
        let started = Date()
        let task = Task<TimeInterval, Never> {
            do {
                try await withWallClockBudget(.infinity) {
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

    /// A budget just under the ceiling is still a real budget: it is honoured
    /// as a bound rather than folded into the "no budget" case.
    @Test("a large but expressible budget still bounds the operation")
    func largeExpressibleBudgetStillBounds() async throws {
        let started = Date()
        let value = try await withWallClockBudget(31_536_000) { 42 }
        #expect(value == 42)
        #expect(Date().timeIntervalSince(started) < 2)
    }
}
