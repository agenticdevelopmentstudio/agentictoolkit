import AgenticToolkitHubService
import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation

/// Builds the object graph once per process. macOS talks to the running
/// adh-daemon (falling back to direct HTTPS); iOS embeds the daemon (any
/// `EmbeddedDaemon`, built by the host) and always routes through it (spec
/// §4.2, §4.3).
@MainActor
public final class HubAppComposition {
    public let coordinator: AppCoordinator
    public let daemon: (any EmbeddedDaemon)?
    public let expectsDaemon: Bool

    private init(
        coordinator: AppCoordinator,
        daemon: (any EmbeddedDaemon)?,
        expectsDaemon: Bool
    ) {
        self.coordinator = coordinator
        self.daemon = daemon
        self.expectsDaemon = expectsDaemon
    }

    public func makeSignInViewModel() -> SignInViewModel {
        SignInViewModel(session: coordinator.session, passkeys: PasskeyAssertion(), social: WebAuthSocialSignIn())
    }

    public static func macOS(
        sessionStore: any SessionStore = KeychainSessionStore(keyPrefix: "adh.api")
    ) async -> HubAppComposition {
        let environment = await HubEnvironment.bootstrap(
            sessionStore: sessionStore,
            transportSource: ResolvedTransportSource()
        )
        let composition = assemble(environment: environment, daemon: nil, expectsDaemon: true)
        composition.coordinator.onResume = { [environment] in
            await environment.refreshTransport()
        }
        return composition
    }

    /// iOS embeds the daemon and routes every request through it. The daemon
    /// is built by the host's factory: this module sees only `EmbeddedDaemon`,
    /// and the host is the one place that links the concrete daemon.
    public static func iOS(
        sessionStore: any SessionStore = KeychainSessionStore(keyPrefix: "adh.api"),
        makeDaemon: (any SessionStore) throws -> any EmbeddedDaemon
    ) async throws -> HubAppComposition {
        let daemon = try makeDaemon(sessionStore)
        await daemon.start()
        let environment = await HubEnvironment.bootstrap(
            sessionStore: sessionStore,
            transportSource: EmbeddedDaemonTransportSource(daemon: daemon)
        )
        let composition = assemble(environment: environment, daemon: daemon, expectsDaemon: false)
        composition.coordinator.onResume = { [daemon] in
            await daemon.kickSync()
        }
        return composition
    }

    private static func assemble(
        environment: HubEnvironment,
        daemon: (any EmbeddedDaemon)?,
        expectsDaemon: Bool
    ) -> HubAppComposition {
        let configuration = SignInConfiguration.fromBundle()
        let session = SessionController(environment: environment, configuration: configuration)
        let workspaces = WorkspaceController(provider: WorkspacesAdapter(environment: environment))
        let registry = FeatureModuleRegistry()
        FeatureModules.registerAll(in: registry, environment: environment)
        let coordinator = AppCoordinator(
            environment: environment,
            session: session,
            workspaces: workspaces,
            registry: registry,
            appearance: AppearanceController(environment: environment)
        )
        return HubAppComposition(
            coordinator: coordinator,
            daemon: daemon,
            expectsDaemon: expectsDaemon
        )
    }
}
