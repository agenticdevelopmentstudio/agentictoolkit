import AgenticDeveloperHubClient
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class HubEnvironmentTests: XCTestCase {
    private static let userJSON = #"""
    {"id":"u1","email":"a@b.c","name":"Ada","avatarUrl":"","slug":"ada","publicProfileEnabled":false,
    "profileVisibility":"public","capabilities":[]}
    """#

    func testBootstrapTakesTheSourceTransportKind() async {
        let stub = StubClientTransport()
        let source = StaticTransportSource(.daemon(port: 1, transport: stub))
        let env = await HubEnvironment.bootstrap(sessionStore: InMemorySessionStore(), transportSource: source)
        XCTAssertEqual(env.transportKind, .daemon)
        XCTAssertEqual(env.client.transportKind, .daemon)
        XCTAssertFalse(env.servedFromCache)
    }

    func testRefreshTransportRebuildsClientOnlyWhenKindChanges() async {
        let stub = StubClientTransport()
        let source = SwitchingTransportSource(initial: .daemon(port: 1, transport: stub))
        let env = await HubEnvironment.bootstrap(sessionStore: InMemorySessionStore(), transportSource: source)
        var changes = 0
        env.onChange = { _ in changes += 1 }

        let unchanged = await env.refreshTransport()
        XCTAssertFalse(unchanged)
        XCTAssertEqual(changes, 0)

        source.transport = .direct(transport: stub)
        let changed = await env.refreshTransport()
        XCTAssertTrue(changed)
        XCTAssertEqual(env.transportKind, .direct)
        XCTAssertEqual(env.client.transportKind, .direct)
        XCTAssertEqual(changes, 1)
    }

    func testDaemonNoStoreSuccessMarksServedFromCacheAndClearsOnFreshResponse() async throws {
        let stub = StubClientTransport()
        stub.on(.get, "/auth/me", headers: ["cache-control": "no-store"], json: Self.userJSON)
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt)))
        let env = await HubEnvironment.bootstrap(
            sessionStore: store,
            transportSource: StaticTransportSource(.daemon(port: 1, transport: stub))
        )
        var changes = 0
        env.onChange = { _ in changes += 1 }

        _ = try await env.client.currentUser()
        let marked = await waitUntil { env.servedFromCache }
        XCTAssertTrue(marked)
        XCTAssertEqual(changes, 1)

        stub.on(.get, "/auth/me", json: Self.userJSON)
        _ = try await env.client.currentUser()
        let cleared = await waitUntil { !env.servedFromCache }
        XCTAssertTrue(cleared)
        XCTAssertEqual(changes, 2)
    }

    func testDirectNoStoreNeverMarksServedFromCache() async throws {
        let stub = StubClientTransport()
        stub.on(.get, "/auth/me", headers: ["cache-control": "no-store"], json: Self.userJSON)
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt)))
        let env = await HubEnvironment.bootstrap(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub))
        )
        _ = try await env.client.currentUser()
        let marked = await waitUntil(timeout: .milliseconds(200)) { env.servedFromCache }
        XCTAssertFalse(marked)
    }

    func testIsServedFromCacheRules() {
        func response(_ code: Int, cacheControl: String?) -> HTTPResponse {
            var fields = HTTPFields()
            if let cacheControl { fields[.cacheControl] = cacheControl }
            return HTTPResponse(status: .init(code: code), headerFields: fields)
        }
        XCTAssertEqual(HubEnvironment.isServedFromCache(response(200, cacheControl: "no-store"), kind: .daemon), true)
        XCTAssertEqual(
            HubEnvironment.isServedFromCache(response(200, cacheControl: "No-Store, max-age=0"), kind: .daemon),
            true
        )
        XCTAssertEqual(HubEnvironment.isServedFromCache(response(200, cacheControl: nil), kind: .daemon), false)
        XCTAssertEqual(
            HubEnvironment.isServedFromCache(response(200, cacheControl: "max-age=60"), kind: .daemon),
            false
        )
        XCTAssertNil(HubEnvironment.isServedFromCache(response(503, cacheControl: "no-store"), kind: .daemon))
        XCTAssertNil(HubEnvironment.isServedFromCache(response(401, cacheControl: nil), kind: .daemon))
        XCTAssertNil(HubEnvironment.isServedFromCache(response(200, cacheControl: "no-store"), kind: .direct))
    }

    func testSessionExpiryFromMiddlewareReachesTheMainActorCallback() async {
        let stub = StubClientTransport()
        stub.on(.get, "/auth/me", status: 401, json: #"{"error":{"message":"expired"}}"#)
        stub.on(.post, "/auth/refresh", status: 401, json: #"{"error":"refresh rejected"}"#)
        let store = InMemorySessionStore(
            Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r1")
        )
        let env = await HubEnvironment.bootstrap(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub))
        )
        var expired = 0
        env.onSessionExpired = { expired += 1 }

        do {
            _ = try await env.client.currentUser()
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        let called = await waitUntil { expired == 1 }
        XCTAssertTrue(called)
        XCTAssertNil(store.currentSession())
        XCTAssertEqual(stub.requestCount(.post, "/auth/refresh"), 1)
    }

    /// Regression (launch hang): `bootstrap` is the first `await` the macOS
    /// launch path takes, and the window cannot show real content until it
    /// returns. A transport source that never answers — no daemon listening,
    /// no network to fall through to — must not be able to park it forever.
    /// Bootstrap has to give up on its deadline and take the transport that
    /// needs nothing local.
    func testBootstrapFallsBackToDirectWhenTheTransportSourceNeverAnswers() async {
        let started = ContinuousClock.now
        let env = await HubEnvironment.bootstrap(
            sessionStore: InMemorySessionStore(),
            transportSource: NeverAnsweringTransportSource(),
            deadline: .milliseconds(100)
        )
        let elapsed = ContinuousClock.now - started

        XCTAssertEqual(env.transportKind, .direct)
        XCTAssertEqual(env.client.transportKind, .direct)
        XCTAssertLessThan(elapsed, NeverAnsweringTransportSource.park)
    }

    /// The same bound on the foreground path: `refreshTransport()` runs on
    /// every activation, and an unanswered probe there would wedge
    /// `applicationDidBecomeActive` instead of launch.
    func testRefreshTransportGivesUpOnAnUnansweredProbe() async {
        let env = await HubEnvironment.bootstrap(
            sessionStore: InMemorySessionStore(),
            transportSource: NeverAnsweringTransportSource(),
            deadline: .milliseconds(100)
        )
        let started = ContinuousClock.now
        let changed = await env.refreshTransport()
        let elapsed = ContinuousClock.now - started

        XCTAssertFalse(changed)
        XCTAssertEqual(env.transportKind, .direct)
        XCTAssertLessThan(elapsed, NeverAnsweringTransportSource.park)
    }
}

/// A source that parks far longer than any deadline under test and ignores
/// cancellation, exactly as a URL load with no timeout of its own would.
///
/// It eventually answers `.daemon` rather than hanging outright, so a
/// regression turns into a failed `.direct` assertion — a named test going red
/// with a line number — instead of a test run that hangs and has to be killed.
private struct NeverAnsweringTransportSource: HubTransportSource {
    static let park: Duration = .seconds(5)

    func makeTransport() async -> APITransport {
        let until = ContinuousClock.now + Self.park
        while ContinuousClock.now < until {
            try? await Task.sleep(for: .milliseconds(25))
        }
        return .daemon(port: 1)
    }
}

/// A transport source whose answer can be swapped between calls.
private final class SwitchingTransportSource: HubTransportSource, @unchecked Sendable {
    private let lock = NSLock()
    private var current: APITransport

    var transport: APITransport {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    init(initial: APITransport) {
        current = initial
    }

    func makeTransport() async -> APITransport {
        transport
    }
}
