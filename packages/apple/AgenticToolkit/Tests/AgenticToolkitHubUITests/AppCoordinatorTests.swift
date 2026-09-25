import AgenticDeveloperHubClient
import AgenticToolkitHub
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private static let userJSON =
        #"{"id":"u1","email":"a@b.c","name":"Ada","avatarUrl":"","slug":"ada","#
        + #""publicProfileEnabled":false,"profileVisibility":"public","capabilities":[]}"#
    private static let workspacesJSON =
        #"[{"slug":"ada","name":"Ada","type":"individual"},"#
        + #"{"slug":"acme","name":"Acme","type":"organization"}]"#
    private static let ada = HubWorkspace(slug: "ada", name: "Ada", type: .individual)
    private static let acme = HubWorkspace(slug: "acme", name: "Acme", type: .organization)

    private var isolated: IsolatedDefaults!

    // `setUp()`/`tearDown()` are `nonisolated` on `XCTestCase` (they come from
    // XCTest's Objective-C base, not a `@MainActor`-annotated Swift
    // declaration), even though this class is `@MainActor`. The `async
    // throws` override points are `@MainActor`, so using them lets
    // setUp/tearDown touch `isolated` directly.
    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        isolated.tearDown()
        try await super.tearDown()
    }

    private struct Harness {
        let coordinator: AppCoordinator
        let stub: StubClientTransport
        let environment: HubEnvironment
        let store: InMemorySessionStore
        let phases: PhaseLog
    }

    private final class PhaseLog {
        var values: [AppCoordinator.Phase] = []
    }

    /// A `WorkspacesProviding` whose `listWorkspaces()` parks open until
    /// `release()` is called, so a test can force `WorkspaceController.load()`
    /// to still be in flight at a chosen moment (e.g. after sign-out) instead
    /// of racing on scheduling order. `@MainActor`-isolated like
    /// `WorkspaceControllerTests`'s `FakeWorkspaces`, so `isWaiting` is safe
    /// to poll synchronously from `waitUntil` without any unchecked-Sendable
    /// escape hatch.
    @MainActor
    private final class GatedWorkspacesProvider: WorkspacesProviding {
        private let workspace: HubWorkspace
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var isWaiting = false

        init(workspace: HubWorkspace) {
            self.workspace = workspace
        }

        func listWorkspaces() async throws -> [HubWorkspace] {
            isWaiting = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.continuation = continuation
            }
            isWaiting = false
            return [workspace]
        }

        func preferredSlug() async throws -> String? { nil }
        func setPreferredSlug(_ slug: String) async throws {}

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func makeHarness(session: Session? = nil) -> Harness {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(session)
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let sessionController = SessionController(
            environment: environment,
            configuration: SignInConfiguration(
                clientID: "adh-cli",
                backendURL: URL(string: "https://api.example.com")!
            ),
            defaults: isolated.defaults
        )
        let workspaces = WorkspaceController(
            provider: WorkspacesAdapter(environment: environment),
            defaults: isolated.defaults
        )
        let coordinator = AppCoordinator(
            environment: environment,
            session: sessionController,
            workspaces: workspaces,
            registry: FeatureModuleRegistry(),
            appearance: AppearanceController(environment: environment)
        )
        let phases = PhaseLog()
        coordinator.onChange = { phases.values.append($0) }
        return Harness(coordinator: coordinator, stub: stub, environment: environment, store: store, phases: phases)
    }

    private func signedInHarness() -> Harness {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me", status: 200, json: Self.userJSON)
        harness.stub.on(.get, "/workspaces", status: 200, json: Self.workspacesJSON)
        harness.stub.on(.get, "/me/workspace-prefs", status: 200, json: #"{"prefs":{}}"#)
        harness.stub.on(.get, "/me/appearance", status: 200, json: #"{"prefs":{"colorMode":"dark"}}"#)
        return harness
    }

    // MARK: launch

    func testNoSessionGoesToSignIn() async {
        let harness = makeHarness()
        await harness.coordinator.start()
        XCTAssertEqual(harness.coordinator.phase, .signIn)
        XCTAssertEqual(harness.stub.requestCount(.get, "/auth/me"), 0)
    }

    func testSessionLoadsTheWorkspaceAndBecomesReady() async {
        let harness = signedInHarness()
        await harness.coordinator.start()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
        XCTAssertEqual(harness.phases.values, [.loadingWorkspace, .ready(Self.ada)])
        XCTAssertEqual(harness.coordinator.user?.email, "a@b.c")
        let isDark = await waitUntil { harness.coordinator.appearance.colorMode == .dark }
        XCTAssertTrue(isDark)
    }

    func testRejectedSessionGoesToSignIn() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: nil)
        )
        harness.stub.on(.get, "/auth/me", status: 401, json: #"{"error":{"message":"expired"}}"#)
        await harness.coordinator.start()
        XCTAssertEqual(harness.coordinator.phase, .signIn)
    }

    func testUnreachableServerWithoutCacheIsAnErrorAndRetryRecovers() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me") { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.coordinator.start()
        guard case .error(let message) = harness.coordinator.phase else {
            return XCTFail("expected error, got \(harness.coordinator.phase)")
        }
        XCTAssertEqual(message, "Could not reach the server. Check your connection and try again.")

        harness.stub.on(.get, "/auth/me", status: 200, json: Self.userJSON)
        harness.stub.on(.get, "/workspaces", status: 200, json: Self.workspacesJSON)
        harness.stub.on(.get, "/me/workspace-prefs", status: 200, json: #"{"prefs":{}}"#)
        await harness.coordinator.retry()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
    }

    func testWorkspaceListFailureIsAnErrorAndRetryRecovers() async {
        let harness = signedInHarness()
        harness.stub.on(.get, "/workspaces", status: 500, json: #"{"error":"boom"}"#)
        await harness.coordinator.start()
        let hasError = await waitUntil {
            if case .error = harness.coordinator.phase { return true } else { return false }
        }
        XCTAssertTrue(hasError)
        harness.stub.on(.get, "/workspaces", status: 200, json: Self.workspacesJSON)
        await harness.coordinator.retry()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
    }

    // MARK: workspace switching

    func testSelectWorkspaceSwitchesAndUnknownSlugIsNotMember() async {
        let harness = signedInHarness()
        harness.stub.on(.put, "/me/workspace-prefs", status: 200, json: #"{"prefs":{"slug":"acme"}}"#)
        await harness.coordinator.start()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
        await harness.coordinator.selectWorkspace(slug: "acme")
        XCTAssertEqual(harness.coordinator.phase, .ready(Self.acme))
        await harness.coordinator.selectWorkspace(slug: "nope")
        XCTAssertEqual(harness.coordinator.phase, .notMember("nope"))
        await harness.coordinator.selectWorkspace(slug: "ada")
        XCTAssertEqual(harness.coordinator.phase, .ready(Self.ada))
    }

    func testSelectWorkspaceHonoursTheDirtyCheck() async {
        let harness = signedInHarness()
        await harness.coordinator.start()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
        harness.coordinator.confirmDiscard = { false }
        await harness.coordinator.selectWorkspace(slug: "acme")
        XCTAssertEqual(harness.coordinator.phase, .ready(Self.ada))
    }

    // MARK: sign-out and expiry

    func testLogOutClearsEverythingAndGoesToSignIn() async {
        let harness = signedInHarness()
        harness.stub.on(.post, "/auth/revoke", status: 200, json: "{}")
        await harness.coordinator.start()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
        isolated.defaults.set(["ada"], forKey: SessionController.recentsKey)

        harness.coordinator.confirmDiscard = { false }
        await harness.coordinator.logOut()
        XCTAssertEqual(harness.coordinator.phase, .ready(Self.ada))
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/revoke"), 0)

        harness.coordinator.confirmDiscard = { true }
        await harness.coordinator.logOut()
        XCTAssertEqual(harness.coordinator.phase, .signIn)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/revoke"), 1)
        XCTAssertNil(isolated.defaults.array(forKey: SessionController.recentsKey))
        XCTAssertNil(harness.store.currentSession())
        XCTAssertEqual(harness.coordinator.workspaces.state, .idle)
        XCTAssertEqual(harness.coordinator.appearance.colorMode, .auto)
    }

    func testSessionExpiryReturnsToSignIn() async {
        let harness = signedInHarness()
        await harness.coordinator.start()
        let isReady = await waitUntil { harness.coordinator.phase == .ready(Self.ada) }
        XCTAssertTrue(isReady)
        harness.store.clear()
        harness.environment.onSessionExpired()
        XCTAssertEqual(harness.coordinator.phase, .signIn)
        XCTAssertEqual(harness.coordinator.workspaces.state, .idle)
    }

    // MARK: foreground

    func testDidBecomeActiveRunsThePlatformHook() async {
        let harness = makeHarness()
        var calls = 0
        harness.coordinator.onResume = { calls += 1 }
        await harness.coordinator.applicationDidBecomeActive()
        XCTAssertEqual(calls, 1)
    }

    // MARK: workspace-load races

    /// `workspaceChanged`'s `guard case .signedIn = session.state else { return }`
    /// is the only thing stopping a `workspaces.load()` that resolves *after*
    /// sign-out from driving `phase` off `.signIn` back onto a stale
    /// `.ready(workspace)`. This parks `listWorkspaces()` open across a
    /// `logOut()`, then releases it, and asserts `phase` stays `.signIn` even
    /// though `WorkspaceController`'s own (unguarded) state does resolve to
    /// `.loaded` — proving the coordinator-level guard, not the workspace
    /// controller, is what keeps `phase` from being resurrected.
    func testWorkspaceLoadResolvingAfterSignOutDoesNotResurrectPhase() async {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(
            Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        stub.on(.get, "/auth/me", status: 200, json: Self.userJSON)
        stub.on(.post, "/auth/revoke", status: 200, json: "{}")
        let sessionController = SessionController(
            environment: environment,
            configuration: SignInConfiguration(
                clientID: "adh-cli",
                backendURL: URL(string: "https://api.example.com")!
            ),
            defaults: isolated.defaults
        )
        let provider = GatedWorkspacesProvider(workspace: Self.ada)
        let workspaces = WorkspaceController(provider: provider, defaults: isolated.defaults)
        let coordinator = AppCoordinator(
            environment: environment,
            session: sessionController,
            workspaces: workspaces,
            registry: FeatureModuleRegistry(),
            appearance: AppearanceController(environment: environment)
        )
        coordinator.confirmDiscard = { true }

        await coordinator.start()
        let isWaiting = await waitUntil { provider.isWaiting }
        XCTAssertTrue(isWaiting)

        await coordinator.logOut()
        XCTAssertEqual(coordinator.phase, .signIn)

        provider.release()
        let workspaceLoaded = await waitUntil { workspaces.state == .loaded(Self.ada) }
        XCTAssertTrue(workspaceLoaded)
        XCTAssertEqual(coordinator.phase, .signIn)
    }
}
