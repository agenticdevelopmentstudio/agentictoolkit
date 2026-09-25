import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class SessionControllerTests: XCTestCase {
    // `nonisolated`: plain immutable `String` literals, safe to read from the
    // `@Sendable` stub handler closure in `testSocialExchangeRetriesOnceOnTransportFailure`.
    private nonisolated static let userJSON = """
    {"id":"u1","email":"a@b.c","name":"Ada","avatarUrl":"","slug":"ada",\
    "publicProfileEnabled":false,"profileVisibility":"public","capabilities":[]}
    """
    private nonisolated static let authJSON = #"{"token":"jwt-1","refreshToken":"r-1","user":\#(userJSON)}"#
    private static let mfaJSON = #"{"mfaRequired":true,"token":"mfa-tok","methods":["totp","sms"]}"#
    private static let ada = HubUser(id: "u1", email: "a@b.c", name: "Ada", slug: "ada", avatarURL: nil)

    private var isolated: IsolatedDefaults!

    // The synchronous `XCTestCase.setUp()`/`tearDown()` override points are
    // nonisolated (they come from XCTest's Objective-C `XCTestCase`, not a
    // `@MainActor`-annotated Swift declaration), even though this class is
    // `@MainActor`. The `async throws` override points are `@MainActor`, so
    // using them lets setUp/tearDown touch `isolated` directly with real,
    // checked isolation instead of an unchecked escape hatch.
    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        isolated.tearDown()
        try await super.tearDown()
    }

    private struct Harness {
        let controller: SessionController
        let stub: StubClientTransport
        let store: InMemorySessionStore
        let environment: HubEnvironment
    }

    private func makeHarness(session: Session? = nil) -> Harness {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(session)
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let controller = SessionController(
            environment: environment,
            configuration: SignInConfiguration(
                clientID: "adh-cli",
                backendURL: URL(string: "https://api.example.com")!
            ),
            defaults: isolated.defaults
        )
        return Harness(controller: controller, stub: stub, store: store, environment: environment)
    }

    private struct CannedPasskey: PasskeyAssertionProvider {
        let seen: Seen
        func assert(options: OpenAPIObjectContainer) async throws -> OpenAPIObjectContainer {
            seen.record(options)
            return try OpenAPIObjectContainer(
                unvalidatedValue: ["id": "cred-1", "rawId": "cred-1", "type": "public-key"]
            )
        }
    }

    /// Stands in for the browser round-trip. `failure` models the two ways
    /// the real provider ends without a code: the user closed the sheet, or
    /// the provider came back with `error=` instead.
    private struct CannedSocial: SocialSignInProvider {
        var code = "code-1"
        var userAgent = "Mozilla/5.0 (Macintosh) TestBrowser/1.0"
        var failure: (any Error & Sendable)?
        var startURLs: StartURLs?

        func authenticate(_ request: SocialSignInRequest) async throws -> SocialSignInResult {
            startURLs?.record(request.makeStartURL(URL(string: "http://127.0.0.1:8517/cb?n=nonce-1")!))
            if let failure { throw failure }
            return SocialSignInResult(code: code, userAgent: userAgent)
        }
    }

    private final class StartURLs: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URL] = []
        func record(_ url: URL) { lock.withLock { stored.append(url) } }
        var last: URL? { lock.withLock { stored.last } }
    }

    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [OpenAPIObjectContainer] = []
        func record(_ value: OpenAPIObjectContainer) { lock.withLock { stored.append(value) } }
        var values: [OpenAPIObjectContainer] { lock.withLock { stored } }
    }

    // MARK: restore

    func testRestoreWithoutASessionIsSignedOutAndMakesNoRequest() async {
        let harness = makeHarness()
        CachedUserStore(defaults: isolated.defaults).save(Self.ada)
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedOut)
        XCTAssertTrue(harness.stub.requests.isEmpty)
        XCTAssertNil(CachedUserStore(defaults: isolated.defaults).load())
    }

    func testRestoreWithAValidSessionSignsInAndCachesTheUser() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me", json: Self.userJSON)
        var observed: [SessionState] = []
        harness.controller.onChange = { observed.append($0) }
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        XCTAssertEqual(observed, [.signedIn(Self.ada)])
        XCTAssertEqual(CachedUserStore(defaults: isolated.defaults).load(), Self.ada)
    }

    func testRestoreWhenTheRefreshIsRejectedSignsOut() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        CachedUserStore(defaults: isolated.defaults).save(Self.ada)
        harness.stub.on(.get, "/auth/me", status: 401, json: #"{"error":{"message":"expired"}}"#)
        harness.stub.on(.post, "/auth/refresh", status: 401, json: #"{"error":"revoked"}"#)
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedOut)
        XCTAssertNil(harness.store.currentSession())
        XCTAssertNil(CachedUserStore(defaults: isolated.defaults).load())
    }

    func testRestoreOfflineFallsBackToTheCachedUser() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        CachedUserStore(defaults: isolated.defaults).save(Self.ada)
        harness.stub.on(.get, "/auth/me") { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        XCTAssertNotNil(harness.store.currentSession())
    }

    func testRestoreOfflineWithoutACacheIsAnError() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me") { _, _ in throw URLError(.notConnectedToInternet) }
        await harness.controller.restore()
        XCTAssertEqual(
            harness.controller.state,
            .error("Could not reach the server. Check your connection and try again.")
        )
    }

    /// Finding 2 regression: a 401 must sign out unconditionally, even when a
    /// refresh mid-flight rotated the store so it is no longer `nil` by the
    /// time `restore()`'s catch runs — the exact condition the old
    /// `where environment.sessionStore.currentSession() == nil` clause
    /// depended on. Here the refresh itself succeeds (leaving the store
    /// populated with a rotated session), but the retried `/auth/me` still
    /// 401s, so the server has explicitly rejected this session. That must
    /// never fall through to the cached-user offline path.
    func testRestoreOn401SignsOutAndClearsStoreAndCacheEvenWhenARefreshRotatedTheStore() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        CachedUserStore(defaults: isolated.defaults).save(Self.ada)
        harness.stub.on(.get, "/auth/me", status: 401, json: #"{"error":{"message":"unauthorized"}}"#)
        harness.stub.on(.post, "/auth/refresh", json: #"{"token":"jwt-2","refreshToken":"r-2"}"#)
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedOut)
        XCTAssertNil(harness.store.currentSession())
        XCTAssertNil(CachedUserStore(defaults: isolated.defaults).load())
    }

    // MARK: password + MFA

    func testPasswordSignInCompletes() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login", json: Self.authJSON)
        let step = try await harness.controller.signIn(email: "a@b.c", password: "pw")
        XCTAssertEqual(step, .done(Self.ada))
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        XCTAssertEqual(harness.store.currentSession()?.credentials.token, "jwt-1")
        XCTAssertEqual(CachedUserStore(defaults: isolated.defaults).load(), Self.ada)
    }

    func testPasswordSignInReturnsTheMfaChallengeAndTotpCompletesIt() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login", status: 202, json: Self.mfaJSON)
        harness.stub.on(.post, "/auth/login/mfa", json: Self.authJSON)
        let step = try await harness.controller.signIn(email: "a@b.c", password: "pw")
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp, .sms])
        XCTAssertEqual(step, .mfa(challenge))
        XCTAssertEqual(harness.controller.state, .signedOut)

        let user = try await harness.controller.completeMfa(challenge: challenge, method: .totp, code: "123456")
        XCTAssertEqual(user, Self.ada)
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        let body = harness.stub.lastBody(.post, "/auth/login/mfa")
        XCTAssertEqual(body?["token"] as? String, "mfa-tok")
        XCTAssertEqual(body?["method"] as? String, "totp")
        XCTAssertEqual(body?["code"] as? String, "123456")
    }

    func testCompleteMfaWithWebauthnMethodNeedsThePasskeyFlow() async {
        let harness = makeHarness()
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.webauthn])
        do {
            _ = try await harness.controller.completeMfa(challenge: challenge, method: .webauthn, code: "")
            XCTFail("expected passkeyRequired")
        } catch {
            XCTAssertEqual(error as? SessionControllerError, .passkeyRequired)
        }
        XCTAssertTrue(harness.stub.requests.isEmpty)
    }

    func testSendMfaSmsPostsTheChallengeToken() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login/mfa/sms/send", status: 202, json: #"{"ok":true}"#)
        try await harness.controller.sendMfaSms(challenge: MfaChallengeInfo(token: "mfa-tok", methods: [.sms]))
        XCTAssertEqual(harness.stub.lastBody(.post, "/auth/login/mfa/sms/send")?["token"] as? String, "mfa-tok")
    }

    func testInvalidPasswordSurfacesInvalidCredentials() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login", status: 401, json: #"{"error":{"message":"invalid credentials"}}"#)
        do {
            _ = try await harness.controller.signIn(email: "a@b.c", password: "nope")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
            XCTAssertEqual(SessionController.userMessage(for: error), "Invalid email or password.")
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    // MARK: passkeys

    func testPasskeySignInFetchesOptionsAssertsAndCompletes() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login/webauthn/options",
                  json: #"{"token":"pk-tok","options":{"challenge":"AQID","rpId":"example.com"}}"#)
        harness.stub.on(.post, "/auth/login/webauthn", json: Self.authJSON)
        let seen = Seen()
        let user = try await harness.controller.signInWithPasskey(
            identifier: "a@b.c",
            provider: CannedPasskey(seen: seen)
        )
        XCTAssertEqual(user, Self.ada)
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        XCTAssertEqual(seen.values.first?.value["rpId"] as? String, "example.com")
        XCTAssertEqual(harness.stub.lastBody(.post, "/auth/login/webauthn/options")?["identifier"] as? String, "a@b.c")
        let body = harness.stub.lastBody(.post, "/auth/login/webauthn")
        XCTAssertEqual(body?["token"] as? String, "pk-tok")
        XCTAssertEqual((body?["response"] as? [String: Any])?["id"] as? String, "cred-1")
    }

    func testMfaPasskeyUsesTheMfaEndpoints() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login/mfa/webauthn/options",
                  json: #"{"token":"pk-tok-2","options":{"challenge":"AQID","rpId":"example.com"}}"#)
        harness.stub.on(.post, "/auth/login/mfa/webauthn", json: Self.authJSON)
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.webauthn, .totp])
        let user = try await harness.controller.completeMfaWithPasskey(
            challenge: challenge,
            provider: CannedPasskey(seen: Seen())
        )
        XCTAssertEqual(user, Self.ada)
        XCTAssertEqual(harness.stub.lastBody(.post, "/auth/login/mfa/webauthn/options")?["token"] as? String, "mfa-tok")
        XCTAssertEqual(harness.stub.lastBody(.post, "/auth/login/mfa/webauthn")?["token"] as? String, "pk-tok-2")
    }

    // MARK: social

    func testSocialSignInExchangesTheCallbackCode() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/oauth/signin/exchange", json: Self.authJSON)
        let social = CannedSocial()
        let user = try await harness.controller.signInWithSocial(.github, using: social)
        XCTAssertEqual(user, Self.ada)
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
        XCTAssertEqual(harness.stub.lastBody(.post, "/oauth/signin/exchange")?["code"] as? String, "code-1")
    }

    /// The exchange code is bound to the browser's `User-Agent` by the
    /// backend's exchange store, so the app has to present the browser's
    /// header rather than its own — this is the whole reason the result
    /// carries one.
    func testSocialSignInForwardsTheBrowserUserAgentOnTheExchange() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/oauth/signin/exchange", json: Self.authJSON)
        let social = CannedSocial(userAgent: "Mozilla/5.0 (Macintosh) Safari/605.1.15")
        _ = try await harness.controller.signInWithSocial(.github, using: social)
        let request = harness.stub.lastRequest(.post, "/oauth/signin/exchange")
        XCTAssertEqual(request?.headerFields[.userAgent], "Mozilla/5.0 (Macintosh) Safari/605.1.15")
    }

    /// The `return` the backend is handed must be the loopback listener's —
    /// `/oauth/signin/start` rejects the custom scheme outright.
    func testSocialSignInStartsAtTheLoopbackReturnURL() async throws {
        let harness = makeHarness()
        harness.stub.on(.post, "/oauth/signin/exchange", json: Self.authJSON)
        let starts = StartURLs()
        let social = CannedSocial(startURLs: starts)
        _ = try await harness.controller.signInWithSocial(.gitlab, using: social)
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(starts.last), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/oauth/signin/start")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["providerId"], "gitlab")
        XCTAssertEqual(items["return"], "http://127.0.0.1:8517/cb?n=nonce-1")
    }

    func testSocialSignInWithoutACodeFails() async {
        let harness = makeHarness()
        let social = CannedSocial(failure: SessionControllerError.missingOAuthCode)
        do {
            _ = try await harness.controller.signInWithSocial(.google, using: social)
            XCTFail("expected missingOAuthCode")
        } catch {
            XCTAssertEqual(error as? SessionControllerError, .missingOAuthCode)
        }
        XCTAssertEqual(harness.stub.requestCount(.post, "/oauth/signin/exchange"), 0)
    }

    func testSocialExchangeRetriesOnceOnTransportFailure() async throws {
        let harness = makeHarness()
        let attempts = Counter()
        harness.stub.on(.post, "/oauth/signin/exchange") { _, _ in
            if attempts.next() == 1 { throw URLError(.networkConnectionLost) }
            return StubClientTransport.Response(json: Self.authJSON)
        }
        let social = CannedSocial()
        let user = try await harness.controller.signInWithSocial(.gitlab, using: social)
        XCTAssertEqual(user, Self.ada)
        XCTAssertEqual(harness.stub.requestCount(.post, "/oauth/signin/exchange"), 2)
    }

    func testSocialExchangeDoesNotRetryARejectedCode() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/oauth/signin/exchange", status: 401, json: #"{"error":{"message":"bad code"}}"#)
        let social = CannedSocial(code: "stale")
        do {
            _ = try await harness.controller.signInWithSocial(.bitbucket, using: social)
            XCTFail("expected invalidCredentials")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.stub.requestCount(.post, "/oauth/signin/exchange"), 1)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
    }

    // MARK: attemptingSignIn normalizes state on every path (Finding 1)

    /// Puts the controller into `.error(...)` — what `restore()` leaves
    /// standing after an unrecognized failure — so each test below proves
    /// its path normalizes state away from whatever was there before, not
    /// merely away from `.restoring`.
    private func makeHarnessStuckInError() async -> Harness {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        // A 500 on `/auth/me` is an undocumented status, which the generated
        // client surfaces as `SessionError.unexpectedResponse("HTTP 500")`,
        // mapped to `HubError.unexpected` and, per
        // `testUnexpectedErrorDetailDoesNotReachSignInCopy`, rendered as the
        // generic fallback rather than that detail — any error not already
        // `.signedOut` demonstrates the point of this precondition.
        harness.stub.on(.get, "/auth/me", status: 500, json: #"{"error":"boom"}"#)
        await harness.controller.restore()
        XCTAssertEqual(
            harness.controller.state,
            .error("Something went wrong and we couldn't finish that. Please try again.")
        )
        return harness
    }

    func testSignInFailureNormalizesStateFromError() async {
        let harness = await makeHarnessStuckInError()
        harness.stub.on(.post, "/auth/login", status: 401, json: #"{"error":{"message":"invalid credentials"}}"#)
        do {
            _ = try await harness.controller.signIn(email: "a@b.c", password: "nope")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    func testCompleteMfaFailureNormalizesStateFromError() async {
        let harness = await makeHarnessStuckInError()
        harness.stub.on(.post, "/auth/login/mfa", status: 401, json: #"{"error":{"message":"bad code"}}"#)
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp])
        do {
            _ = try await harness.controller.completeMfa(challenge: challenge, method: .totp, code: "000000")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    func testSignInWithPasskeyFailureNormalizesStateFromError() async {
        let harness = await makeHarnessStuckInError()
        harness.stub.on(.post, "/auth/login/webauthn/options", status: 401, json: #"{"error":{"message":"nope"}}"#)
        do {
            _ = try await harness.controller.signInWithPasskey(
                identifier: "a@b.c",
                provider: CannedPasskey(seen: Seen())
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    func testCompleteMfaWithPasskeyFailureNormalizesStateFromError() async {
        let harness = await makeHarnessStuckInError()
        harness.stub.on(.post, "/auth/login/mfa/webauthn/options", status: 401, json: #"{"error":{"message":"nope"}}"#)
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.webauthn])
        do {
            _ = try await harness.controller.completeMfaWithPasskey(
                challenge: challenge,
                provider: CannedPasskey(seen: Seen())
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    func testSignInWithSocialFailureNormalizesStateFromError() async {
        let harness = await makeHarnessStuckInError()
        harness.stub.on(.post, "/oauth/signin/exchange", status: 401, json: #"{"error":{"message":"bad code"}}"#)
        let social = CannedSocial(code: "stale")
        do {
            _ = try await harness.controller.signInWithSocial(.github, using: social)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedOut)
    }

    /// The other branch of `attemptingSignIn`'s guard: a live `.signedIn`
    /// session must never be demoted by a subsequent failing attempt (e.g. a
    /// stale retry). Every test above starts from `.error(...)`, where an
    /// unconditional `state = .signedOut` in the catch block would be
    /// indistinguishable from the guarded version — this one starts from
    /// `.signedIn` specifically so it fails if that guard is removed.
    func testAttemptingSignInNeverDemotesAnAlreadySignedInSession() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me", json: Self.userJSON)
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))

        harness.stub.on(.post, "/auth/login", status: 401, json: #"{"error":{"message":"invalid credentials"}}"#)
        do {
            _ = try await harness.controller.signIn(email: "a@b.c", password: "nope")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SessionError, .invalidCredentials)
        }
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))
    }

    // MARK: sign-out and expiry

    func testSignOutClearsRecentsCacheAndSessionAfterRevoking() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me", json: Self.userJSON)
        harness.stub.on(.post, "/auth/revoke", status: 204, json: "")
        isolated.defaults.set(["acme", "ada"], forKey: "hub.recents")
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))

        await harness.controller.signOut()

        XCTAssertEqual(harness.controller.state, .signedOut)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/revoke"), 1)
        XCTAssertNil(isolated.defaults.object(forKey: "hub.recents"))
        XCTAssertNil(CachedUserStore(defaults: isolated.defaults).load())
        XCTAssertNil(harness.store.currentSession())
    }

    func testSessionExpiryFromTheEnvironmentSignsOut() async {
        let harness = makeHarness(
            session: Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        harness.stub.on(.get, "/auth/me", json: Self.userJSON)
        await harness.controller.restore()
        XCTAssertEqual(harness.controller.state, .signedIn(Self.ada))

        harness.stub.on(.get, "/auth/me", status: 401, json: #"{"error":{"message":"expired"}}"#)
        harness.stub.on(.post, "/auth/refresh", status: 401, json: #"{"error":"revoked"}"#)
        _ = try? await harness.environment.client.currentUser()
        let signedOut = await waitUntil { harness.controller.state == .signedOut }
        XCTAssertTrue(signedOut)
        XCTAssertNil(CachedUserStore(defaults: isolated.defaults).load())
    }

    /// Finding 4: a wholly unrecognized error (neither a `SessionError`, a
    /// `SessionControllerError`, `CancellationError`, nor a `URLError`,
    /// directly or `ClientError`-wrapped).
    private struct UnrecognizedTestError: Error {}

    func testUserMessages() {
        XCTAssertEqual(
            SessionController.userMessage(for: SessionError.invalidCredentials),
            "Invalid email or password."
        )
        // `.unexpected` must not surface its detail text on this sign-in
        // surface — see `testUnexpectedErrorDetailDoesNotReachSignInCopy`.
        XCTAssertEqual(
            SessionController.userMessage(for: SessionError.unexpectedResponse("HTTP 503")),
            "Something went wrong and we couldn't finish that. Please try again."
        )
        // The `URLError` branch: connectivity wording, both direct and
        // `ClientError`-wrapped. Asserted separately from the fallback below
        // so deleting this branch (falling through to the fallback's
        // distinct string) fails this assertion.
        XCTAssertEqual(
            SessionController.userMessage(for: URLError(.notConnectedToInternet)),
            "Could not reach the server. Check your connection and try again."
        )
        XCTAssertEqual(
            SessionController.userMessage(for: ClientError(
                operationID: "getAuthMe", operationInput: "", causeDescription: "", underlyingError: URLError(.timedOut)
            )),
            "Could not reach the server. Check your connection and try again."
        )
        // The fallback: a distinct, honest "unexpected failure" message —
        // asserted separately so deleting the fallback (e.g. reverting to
        // the `URLError` branch's connectivity wording) fails this
        // assertion instead of being masked by the branch above.
        XCTAssertEqual(
            SessionController.userMessage(for: UnrecognizedTestError()),
            "Something went wrong and we couldn't finish that. Please try again."
        )
        XCTAssertEqual(SessionController.userMessage(for: CancellationError()), "Sign-in was cancelled.")
        XCTAssertEqual(
            SessionController.userMessage(for: SessionControllerError.missingOAuthCode),
            "The sign-in response did not include a code."
        )
        XCTAssertEqual(
            SessionController.userMessage(for: SessionControllerError.passkeyRequired),
            "This MFA method needs a passkey. Choose Use passkey."
        )
    }

    /// A `HubError.unexpected` can carry raw, server-supplied detail text
    /// (see `HubError.message`'s `"Something went wrong: \(detail)"`). No
    /// current sign-in call site actually reaches this arm with untrusted
    /// text, but `userMessage(for:)` is a sign-in-form surface, so the arm
    /// must not render that detail regardless of who calls it today.
    func testUnexpectedErrorDetailDoesNotReachSignInCopy() {
        let message = SessionController.userMessage(for: HubError.unexpected("<script>server says hi</script>"))
        XCTAssertFalse(message.contains("server says hi"))
        XCTAssertEqual(message, "Something went wrong and we couldn't finish that. Please try again.")
    }
}
