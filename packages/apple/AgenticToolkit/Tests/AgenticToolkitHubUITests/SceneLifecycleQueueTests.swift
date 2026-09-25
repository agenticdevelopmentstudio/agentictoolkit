import Foundation
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class SceneLifecycleQueueTests: XCTestCase {
    /// Records what the queue actually applied, in order. A plain array is
    /// enough: everything here is `@MainActor`-isolated.
    private final class Applied {
        var intents: [SceneLifecycleQueue.Intent] = []
        var operations: [String] = []
    }

    /// The finding: a scene transition arriving while bootstrap is still in
    /// flight used to hit `guard let composition else { return }` and be
    /// discarded, so an app that backgrounded mid-bootstrap kept syncing in
    /// the background until the next lifecycle event.
    ///
    /// Asserted as "the intent was applied", not merely "the intent was
    /// remembered" — a fix that stored it and never replayed it would leave
    /// the daemon just as wrongly started.
    func testIntentRecordedBeforeReadyIsAppliedWhenReady() async {
        let queue = SceneLifecycleQueue()
        let applied = Applied()
        XCTAssertFalse(queue.isReady)

        queue.record(.background)
        XCTAssertEqual(applied.intents, [])
        XCTAssertEqual(queue.pendingIntent, .background)

        queue.ready { intent in applied.intents.append(intent) }
        await queue.drain()

        XCTAssertEqual(applied.intents, [.background])
        XCTAssertNil(queue.pendingIntent)
        XCTAssertTrue(queue.isReady)
    }

    /// Last-intent-wins: the two states are mutually exclusive and only the
    /// final one is true, so a background followed by a foreground during
    /// bootstrap must replay as a foreground *alone*. Replaying both in order
    /// would end in the same place while stopping a daemon that bootstrap had
    /// just started and starting it again — work with no corresponding real
    /// transition behind it.
    func testOnlyTheLastIntentBeforeReadyIsReplayed() async {
        let queue = SceneLifecycleQueue()
        let applied = Applied()

        queue.record(.background)
        queue.record(.foreground)
        queue.record(.background)
        queue.record(.foreground)
        XCTAssertEqual(queue.pendingIntent, .foreground)

        queue.ready { intent in applied.intents.append(intent) }
        await queue.drain()

        XCTAssertEqual(applied.intents, [.foreground])
    }

    /// Nothing to replay must stay nothing: a bootstrap no transition
    /// interrupted must not synthesize one.
    func testReadyWithNoRecordedIntentAppliesNothing() async {
        let queue = SceneLifecycleQueue()
        let applied = Applied()

        queue.ready { intent in applied.intents.append(intent) }
        await queue.drain()

        XCTAssertEqual(applied.intents, [])
    }

    /// After `ready`, a transition is applied straight away rather than held.
    func testIntentRecordedAfterReadyIsAppliedImmediately() async {
        let queue = SceneLifecycleQueue()
        let applied = Applied()
        queue.ready { intent in applied.intents.append(intent) }

        queue.record(.foreground)
        await queue.drain()

        XCTAssertEqual(applied.intents, [.foreground])
        XCTAssertNil(queue.pendingIntent)
    }

    /// The ordering guarantee the chain exists for, including the replayed
    /// intent: a deferred transition runs *before* work enqueued after
    /// `ready`, and each operation only starts once its predecessor has
    /// finished. Each body awaits a yield before recording, so an
    /// unsequenced implementation (a bare `Task` per callback) would be free
    /// to interleave them and produce a different order.
    func testReplayedIntentRunsBeforeLaterWorkAndOrderIsPreserved() async {
        let queue = SceneLifecycleQueue()
        let applied = Applied()

        queue.record(.background)
        queue.ready { intent in
            await Task.yield()
            applied.intents.append(intent)
            applied.operations.append("intent:\(intent)")
        }
        queue.enqueue {
            await Task.yield()
            applied.operations.append("kick")
        }
        queue.enqueue {
            applied.operations.append("shutdown")
        }
        await queue.drain()

        XCTAssertEqual(applied.operations, ["intent:background", "kick", "shutdown"])
    }
}
