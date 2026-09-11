import Foundation

/// Teardown work that was started without anyone waiting for it, held so that
/// a later shutdown can wait for it after all.
///
/// **The invariant, stated once:** *no shutdown is complete while a teardown
/// this owns is still in flight.* That is the whole type. Everything else here
/// is bookkeeping in service of it.
///
/// Two call sites had the same near-miss independently, which is why this is
/// an extraction rather than two patches. `LanguageServerRegistry.reconcile`
/// retired a superseded session with `Task { await stopAll(retired) }` and
/// dropped the handle; `ProjectWindowManager`'s window-close observer removed
/// the controller from its dictionary and *then* fired
/// `Task { await services.shutdown() }`. In both cases the app-level quit path
/// — `shutdown()` in one, `shutdownAllLanguageServices()` in the other —
/// enumerated a collection the work had already left, found nothing to wait
/// for, and returned. Quitting inside `SubprocessChannel.terminate()`'s ~2.5 s
/// budget then killed the detached task with the process, leaving an orphaned
/// `sourcekit-lsp` or `tsserver` behind.
///
/// **Why not simply await at the call site.** Neither site can. A window close
/// runs on the main actor inside a notification block and must not block the
/// UI on a subprocess exiting; `reconcile` is synchronous by construction. The
/// work genuinely has to outlive the call that starts it. What was missing was
/// not the await but the *handle*.
///
/// **Why not `TaskGroup`.** A task group's lifetime is the scope that creates
/// it, and the whole difficulty here is work that outlives its scope. The
/// teardowns joined here are started at unrelated moments by unrelated callers
/// and are awaited, if at all, by a third.
///
/// `@MainActor` and Foundation-only, like `KeyedDebouncer` next door and like
/// both call sites: the work closures read main-actor state (a registry's
/// session list, a project's services) to decide what to tear down. The
/// closure is `async`, so the teardown itself is free to leave the main actor,
/// and both current callers do.
@MainActor
public final class PendingTeardowns {

    /// One unit of teardown work. Non-throwing on purpose: a teardown that
    /// fails still happened, and there is no caller left to hand an error to.
    /// Work that needs to report a failure should log it itself.
    public typealias Teardown = @MainActor () async -> Void

    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextToken = 0

    public init() {}

    /// How many teardowns are in flight. Internal, for tests: "started and
    /// tracked" and "started and dropped" are otherwise indistinguishable from
    /// outside, which is exactly the bug this type exists to make impossible.
    var inFlightCount: Int { tasks.count }

    /// Starts `teardown` and keeps its handle. Returns immediately — the point
    /// is that the caller does not wait.
    ///
    /// The task removes its own entry when it finishes. That removal is
    /// main-actor-isolated, like this method, so it cannot interleave with the
    /// insertion below: a teardown that completes instantly still leaves no
    /// stale handle behind.
    public func add(_ teardown: @escaping Teardown) {
        nextToken += 1
        let token = nextToken
        tasks[token] = Task { [weak self] in
            await teardown()
            self?.tasks.removeValue(forKey: token)
        }
    }

    /// Waits for every teardown currently in flight, and for any that those
    /// teardowns start in turn.
    ///
    /// The loop is not decoration. A teardown may itself `add` another — a
    /// window closing during a quit sweep is the live case — and a single pass
    /// would return while that one was still running, which is the exact shape
    /// of the bug being fixed. Draining until the collection stays empty is
    /// what makes "shutdown is complete" true rather than likely.
    ///
    /// Entries are taken out before being awaited so a teardown removing its
    /// own entry on completion finds nothing to remove, rather than mutating a
    /// collection this is iterating.
    public func drain() async {
        while !tasks.isEmpty {
            let inFlight = Array(tasks.values)
            tasks.removeAll()
            for task in inFlight {
                await task.value
            }
        }
    }
}
