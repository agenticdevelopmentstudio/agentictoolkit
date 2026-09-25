import AgenticToolkitHubService
import Foundation

/// Sequences the daemon lifecycle work a scene's platform callbacks produce,
/// and holds the last foreground/background intent that arrives *before* the
/// app has finished bootstrapping so it is applied rather than dropped.
///
/// Two jobs, both of them "put the scene's lifecycle callbacks in the right
/// order", which is why they live in one type:
///
/// 1. **Ordering.** UIKit delivers scene callbacks on the main actor, strictly
///    ordered (`willEnterForeground` before `didBecomeActive`;
///    `didEnterBackground` before the next `willEnterForeground`). Spawning a
///    bare `Task { await daemon.stop() }` per callback throws that ordering
///    away: each task is scheduled independently, so a rapid
///    background/foreground flap can deliver the `stop()` to the actor *after*
///    the `start()` that was supposed to follow it, leaving the daemon paused
///    while the app sits in the foreground — sync silently dead until the next
///    flap. Chaining each new task onto the previous one's `value` restores the
///    delivery order.
/// 2. **Bootstrap deferral.** Nothing can run until the composition that owns
///    the daemon exists. Before `ready(_:)`, a scene transition is *recorded*
///    rather than discarded: a scene that backgrounds while bootstrap is still
///    in flight gets its `stop()` once bootstrap lands, instead of leaving the
///    daemon syncing in the background indefinitely.
///
/// Notes on the two hazards the chain can have:
///
/// - **No unbounded growth.** The chain is a linked list of *pending* work,
///   not a history: once `tail` is replaced, the only reference to the previous
///   task is the one captured in the new one, released as soon as its
///   `await previous.value` returns. In the steady state (a callback arriving
///   after the last one finished) the predecessor is already complete and the
///   chain is one deep.
/// - **No deadlock.** The operations only touch the embedded daemon, which never
///   calls back into the main actor, so nothing downstream can wait on this
///   chain while the chain waits on it. `await` here also never blocks the main
///   thread; the chain delays lifecycle work only, never UI.
@MainActor
public final class SceneLifecycleQueue {
    /// A scene transition. There are exactly two, they are mutually exclusive,
    /// and only the most recent one is true — which is what makes
    /// last-intent-wins the correct replay policy for the bootstrap window: a
    /// background followed by a foreground means the app is in the foreground,
    /// and replaying both in order would end in the same place while doing
    /// pointless work against a daemon that was never started in between.
    public enum Intent: Sendable, Equatable {
        case foreground
        case background
    }

    private var tail: Task<Void, Never>?
    private var pending: Intent?
    private var perform: (@Sendable @MainActor (Intent) async -> Void)?

    public init() {}

    /// Whether `ready(_:)` has installed a handler.
    public var isReady: Bool { perform != nil }

    /// The intent held for replay, if bootstrap has not finished yet.
    /// Internal, `@testable`-visible seam: "was the intent remembered" is a
    /// different question from "was it applied", and the dropped-callback bug
    /// this type exists to fix is invisible if a test can only ask the second.
    var pendingIntent: Intent? { pending }

    /// Records a scene transition, applying it now if the app is ready and
    /// remembering it for replay if it is not. Replacing (not queueing) an
    /// already-pending intent is deliberate — see `Intent`.
    public func record(_ intent: Intent) {
        guard let perform else {
            pending = intent
            return
        }
        enqueue { await perform(intent) }
    }

    /// Runs `operation` after every operation enqueued before it has finished.
    ///
    /// For lifecycle work that is *not* a scene transition (a foreground sync
    /// kick, terminal shutdown). Whether such work is safe to run at all is the
    /// caller's decision — this only orders what it is handed.
    public func enqueue(_ operation: @escaping @Sendable @MainActor () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
    }

    /// Bootstrap finished: `handler` becomes the way transitions are applied,
    /// and any intent recorded during bootstrap is replayed onto the chain
    /// immediately — ahead of anything a later callback enqueues, preserving
    /// the arrival order the chain exists to guarantee.
    public func ready(_ handler: @escaping @Sendable @MainActor (Intent) async -> Void) {
        perform = handler
        guard let intent = pending else { return }
        pending = nil
        enqueue { await handler(intent) }
    }

    /// Waits for everything currently queued. Internal, `@testable`-visible
    /// seam: the chain is the only handle on work this type has already
    /// started, and a test asserting on that work's effects has to be able to
    /// wait for it without sleeping.
    func drain() async {
        await tail?.value
    }
}
