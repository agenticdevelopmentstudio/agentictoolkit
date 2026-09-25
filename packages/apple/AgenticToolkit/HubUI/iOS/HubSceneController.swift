import AgenticDeveloperHubClient
import AgenticToolkitHub
import AgenticToolkitHubService
import UIKit

/// The iOS half of the hub, as one component a host's `UIWindowSceneDelegate`
/// owns and forwards to. It owns the daemon lifecycle end to end: building it
/// via the host's factory, starting/stopping/kicking it in step with scene
/// transitions, and shutting it down at termination (spec §4.2, §4.3).
///
/// Not a `UIWindowSceneDelegate` itself — UIKit demands the conforming type
/// live in the host's own scene configuration, so this stays a plain class a
/// host's `SceneDelegate` owns and forwards every lifecycle call to in one
/// line. It is `@MainActor` because every method it exposes runs on the main
/// actor already, the way UIKit's own scene callbacks do.
@MainActor
public final class HubSceneController {
    private let makeDaemon: (any SessionStore) throws -> any EmbeddedDaemon
    private var composition: HubAppComposition?
    private var root: RootViewController?

    /// Orders the daemon lifecycle work below, and holds a scene transition
    /// that lands before `bootstrap` finishes.
    private let lifecycle = SceneLifecycleQueue()

    public init(makeDaemon: @escaping (any SessionStore) throws -> any EmbeddedDaemon) {
        self.makeDaemon = makeDaemon
    }

    /// Everything the host's `scene(_:willConnectTo:options:)` does once it
    /// has built the window from the incoming `UIWindowScene` and assigned it
    /// to its own `window` property.
    public func connect(window: UIWindow) {
        let launch = LaunchViewController()
        window.rootViewController = UINavigationController(rootViewController: launch)
        window.makeKeyAndVisible()
        bootstrap(window: window, launch: launch)
    }

    /// Builds the composition (starts the embedded daemon); on failure the
    /// launch screen shows the error with a Retry that runs this again.
    ///
    /// Deliberately **not** on the lifecycle chain. `HubAppComposition.iOS()`
    /// performs its own `await daemon.start()` internally, and nothing reaches
    /// the chain until `lifecycle.ready` runs below — so the initial `start()`
    /// is always complete before any lifecycle work is enqueued. The ordering
    /// is enforced by readiness, not by the chain; putting this on the chain
    /// would add nothing and would couple retry-after-failure to daemon
    /// lifecycle work.
    ///
    /// `lifecycle.ready` also replays a scene transition that arrived *during*
    /// bootstrap. Before it existed, a scene that backgrounded mid-bootstrap
    /// hit `guard let composition else { return }` and its `stop()` was
    /// discarded outright, leaving the embedded daemon syncing in the
    /// background until the next lifecycle event.
    private func bootstrap(window: UIWindow, launch: LaunchViewController) {
        launch.showLoading()
        Task { @MainActor in
            do {
                let composition = try await HubAppComposition.iOS(makeDaemon: makeDaemon)
                self.composition = composition
                self.lifecycle.ready { intent in
                    switch intent {
                    case .foreground: await composition.daemon?.start()
                    case .background: await composition.daemon?.stop()
                    }
                }
                let root = RootViewController(composition: composition)
                self.root = root
                window.rootViewController = UINavigationController(rootViewController: root)
                root.start()
            } catch {
                self.presentBootstrapFailure(error, window: window, launch: launch)
            }
        }
    }

    /// The retry affordance, lifted out of `bootstrap`'s `Task` on purpose.
    ///
    /// Inline, `[weak self]` sat inside a closure that already captures `self`
    /// strongly (it assigns `self.composition`), which Swift 6.3 rejects
    /// outright: `'weak' ownership of capture 'self' differs from
    /// implicitly-captured strong reference in outer scope`. Weak is the right
    /// answer for a retry the error view holds indefinitely — the alternative,
    /// capturing strongly, keeps this controller alive behind a failed launch
    /// screen — so the closure moves to where nothing captures `self` around
    /// it rather than changing its ownership.
    private func presentBootstrapFailure(_ error: Error, window: UIWindow, launch: LaunchViewController) {
        launch.showError(HubError.from(error).message) { [weak self] in
            self?.bootstrap(window: window, launch: launch)
        }
    }

    /// Forward from the host's `sceneDidBecomeActive(_:)`. On iOS
    /// `applicationDidBecomeActive()` is exactly `daemon.kickSync()` (see
    /// `HubAppComposition.iOS`), a daemon lifecycle call like the others, and
    /// `kickSync()` no-ops unless the daemon is started. Running it unordered
    /// meant the kick could reach the actor before `sceneWillEnterForeground`'s
    /// `start()` and be silently dropped — self-healing (the periodic loop
    /// syncs within `syncInterval`) but a real lost foreground sync. Chained,
    /// it always lands after the `start()` UIKit delivered before it, so the
    /// kick actually happens.
    ///
    /// Not a scene *transition*, so it is enqueued rather than recorded: a
    /// kick that arrives during bootstrap has nothing to replay against
    /// (bootstrap's own `start()` arms the periodic loop, which syncs within
    /// `syncInterval` regardless), and only the transition pair carries state
    /// worth remembering.
    public func sceneDidBecomeActive() {
        guard let composition else { return }
        lifecycle.enqueue { await composition.coordinator.applicationDidBecomeActive() }
    }

    /// Forward from the host's `sceneDidEnterBackground(_:)`. Resumable pause
    /// (spec §4.3): the embedded daemon's periodic sync loop is torn down, but
    /// the sync engine itself stays alive so `sceneWillEnterForeground`'s
    /// `start()` genuinely resumes it.
    ///
    /// Recorded, not enqueued — so a backgrounding that lands mid-bootstrap is
    /// applied when bootstrap finishes instead of being dropped.
    public func sceneDidEnterBackground() {
        lifecycle.record(.background)
    }

    /// Forward from the host's `sceneWillEnterForeground(_:)`.
    public func sceneWillEnterForeground() {
        lifecycle.record(.foreground)
    }

    /// Terminal teardown, called by the host's
    /// `applicationWillTerminate`/`sceneDidDisconnect`. That hook is
    /// unreliable in practice, not merely time-constrained: under the normal
    /// background -> suspend -> jetsam-or-swipe-kill path it is never
    /// delivered at all; it reliably fires only for a foreground force-quit
    /// and a handful of restart/logout flows. This is harmless here — by the
    /// time any termination path could run, backgrounding has already called
    /// `stop()` (the periodic loop is torn down), and `shutdown()`'s only
    /// extra step beyond that — finishing the sync engine's event stream —
    /// has no data-safety implication if it never gets to run.
    ///
    /// On the lifecycle chain too, and for a stronger reason than ordering:
    /// a `shutdown()` running concurrently with an in-flight `start()` is the
    /// one interleaving that can leave a freshly armed periodic loop kicking
    /// an engine `shutdown()` has already finished. `LocalDaemon.shutdown()`
    /// defends against that itself, but keeping the two ordered means the
    /// situation never arises. The cost — `shutdown()` waiting on whatever
    /// is ahead of it in a termination window of a few seconds — is
    /// negligible, because everything on this chain is a single short daemon
    /// call (`start`/`stop`/`kickSync`), not user-visible or network-bound
    /// work.
    public func terminate() {
        guard let composition else { return }
        lifecycle.enqueue { await composition.daemon?.shutdown() }
    }
}
