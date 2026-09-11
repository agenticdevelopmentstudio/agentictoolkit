import Foundation
import Testing
@testable import AgenticToolkitCore

/// The invariant under test is one sentence: *no shutdown is complete while a
/// teardown this owns is still in flight.* Everything here is that sentence
/// from a different angle.
@MainActor
@Suite("PendingTeardowns")
struct PendingTeardownsTests {

    /// Records completion order and lets a test hold a teardown open.
    private final class Journal {
        private(set) var finished: [String] = []
        func record(_ name: String) { finished.append(name) }
    }

    @Test("drain() waits for a teardown that is still running")
    func drainWaitsForWorkInFlight() async {
        let teardowns = PendingTeardowns()
        let journal = Journal()

        teardowns.add {
            try? await Task.sleep(nanoseconds: 150_000_000)
            journal.record("slow")
        }
        #expect(journal.finished.isEmpty, "add() must not wait")

        await teardowns.drain()
        #expect(journal.finished == ["slow"], "drain() returned while the teardown was still running")
    }

    @Test("drain() waits for every teardown, not just the first")
    func drainWaitsForAllOfThem() async {
        let teardowns = PendingTeardowns()
        let journal = Journal()

        for index in 0..<5 {
            teardowns.add {
                try? await Task.sleep(nanoseconds: UInt64(20_000_000 * (5 - index)))
                journal.record("teardown-\(index)")
            }
        }

        await teardowns.drain()
        #expect(journal.finished.count == 5)
    }

    @Test("a teardown that starts another is waited for too")
    func drainWaitsForTeardownsStartedByTeardowns() async {
        // The live shape: a quit sweep closes windows, and a window closing
        // schedules its own shutdown. A single pass would return while the
        // second one was still running.
        let teardowns = PendingTeardowns()
        let journal = Journal()

        teardowns.add {
            try? await Task.sleep(nanoseconds: 50_000_000)
            journal.record("outer")
            teardowns.add {
                try? await Task.sleep(nanoseconds: 50_000_000)
                journal.record("inner")
            }
        }

        await teardowns.drain()
        #expect(journal.finished == ["outer", "inner"], "the teardown started by a teardown was not awaited")
    }

    @Test("a finished teardown leaves no handle behind")
    func finishedTeardownsAreForgotten() async {
        let teardowns = PendingTeardowns()
        teardowns.add {}
        await teardowns.drain()
        #expect(teardowns.inFlightCount == 0)

        // And an instant teardown that completes before anyone drains must
        // not accumulate either.
        teardowns.add {}
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(teardowns.inFlightCount == 0)
    }

    @Test("drain() on an empty collection returns without suspending indefinitely")
    func drainOnEmptyReturns() async {
        let teardowns = PendingTeardowns()
        await teardowns.drain()
        #expect(teardowns.inFlightCount == 0)
    }
}
