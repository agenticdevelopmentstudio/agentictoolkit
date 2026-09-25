import AgenticDeveloperHubClient
import Foundation
import OpenAPIRuntime
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class SignInViewModelTests: XCTestCase {
    // `nonisolated`: plain immutable `String` literals, safe to read from the
    // `@Sendable` route-handler closures below as well as from the main actor.
    private nonisolated static let userJSON =
        #"{"id":"u1","email":"a@b.c","name":"Ada","avatarUrl":"","slug":"ada","publicProfileEnabled":false,"# +
        #""profileVisibility":"public","capabilities":[]}"#
    private nonisolated static let authJSON = #"{"token":"jwt-1","refreshToken":"r-1","user":\#(userJSON)}"#
    private nonisolated static let mfaJSON =
        #"{"mfaRequired":true,"token":"mfa-tok","methods":["totp","sms","webauthn","recovery"]}"#
    private static let ada = HubUser(id: "u1", email: "a@b.c", name: "Ada", slug: "ada", avatarURL: nil)

    private static func passkeyOptionsJSON(token: String) -> String {
        #"{"token":"\#(token)","options":{"challenge":"AAEC","rpId":"agenticdeveloperhub.com"}}"#
    }

    private var isolated: IsolatedDefaults!

    // The synchronous `XCTestCase.setUp()`/`tearDown()` override points are
    // nonisolated (they come from XCTest's Objective-C `XCTestCase`, not a
    // `@MainActor`-annotated Swift declaration), even though this class is
    // `@MainActor`. The `async throws` override points are `@MainActor`, so
    // using them lets setUp/tearDown touch `isolated` directly with real,
    // compiler-checked isolation instead of a lie like `nonisolated(unsafe)`.
    override func setUp() async throws {
        try await super.setUp()
        isolated = IsolatedDefaults()
    }

    override func tearDown() async throws {
        isolated.tearDown()
        try await super.tearDown()
    }

    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [T] = []
        func append(_ value: T) { lock.withLock { stored.append(value) } }
        var values: [T] { lock.withLock { stored } }
    }

    private struct FakePasskey: PasskeyAssertionProvider {
        enum Outcome { case respond, cancel }
        let outcome: Outcome
        let calls: Box<Int>
        func assert(options: OpenAPIObjectContainer) async throws -> OpenAPIObjectContainer {
            calls.append(1)
            switch outcome {
            case .cancel: throw CancellationError()
            case .respond:
                let value: [String: (any Sendable)?] = ["id": "cred-1", "rawId": "cred-1", "type": "public-key"]
                return try OpenAPIObjectContainer(unvalidatedValue: value)
            }
        }
    }

    private struct FakeSocial: SocialSignInProvider {
        enum Outcome { case code(String), noCode, cancel }
        let outcome: Outcome
        func authenticate(_ request: SocialSignInRequest) async throws -> SocialSignInResult {
            switch outcome {
            case .cancel: throw CancellationError()
            case .noCode: throw SessionControllerError.missingOAuthCode
            case .code(let code): return SocialSignInResult(code: code, userAgent: "TestBrowser/1.0")
            }
        }
    }

    private struct Harness {
        let viewModel: SignInViewModel
        let stub: StubClientTransport
        let signedIn: Box<HubUser>
        let states: Box<SignInViewModel.State>
        let passkeyCalls: Box<Int>
    }

    private func makeHarness(passkey: FakePasskey.Outcome = .respond, social: FakeSocial.Outcome = .cancel) -> Harness {
        let stub = StubClientTransport()
        let environment = HubEnvironment(
            sessionStore: InMemorySessionStore(nil),
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let session = SessionController(
            environment: environment,
            configuration: SignInConfiguration(
                clientID: "adh-cli",
                backendURL: URL(string: "https://api.example.com")!
            ),
            defaults: isolated.defaults
        )
        let passkeyCalls = Box<Int>()
        let viewModel = SignInViewModel(
            session: session,
            passkeys: FakePasskey(outcome: passkey, calls: passkeyCalls),
            social: FakeSocial(outcome: social)
        )
        let signedIn = Box<HubUser>()
        let states = Box<SignInViewModel.State>()
        viewModel.onSignedIn = { signedIn.append($0) }
        viewModel.onChange = { states.append($0) }
        return Harness(viewModel: viewModel, stub: stub, signedIn: signedIn, states: states, passkeyCalls: passkeyCalls)
    }

    // MARK: credentials

    func testInitialStateIsCredentialsAndCannotSubmit() {
        let harness = makeHarness()
        XCTAssertEqual(harness.viewModel.state.mode, .credentials)
        XCTAssertFalse(harness.viewModel.state.canSubmitCredentials)
        XCTAssertEqual(harness.viewModel.state.availableMethods, [])
        XCTAssertFalse(harness.viewModel.state.showsCodeField)
    }

    func testCanSubmitCredentialsNeedsEmailAndPassword() {
        let harness = makeHarness()
        harness.viewModel.setEmail("  ")
        harness.viewModel.setPassword("pw")
        XCTAssertFalse(harness.viewModel.state.canSubmitCredentials)
        harness.viewModel.setEmail("a@b.c")
        XCTAssertTrue(harness.viewModel.state.canSubmitCredentials)
        harness.viewModel.setPassword("")
        XCTAssertFalse(harness.viewModel.state.canSubmitCredentials)
    }

    func testSubmitCredentialsSignsInAndFiresOnSignedIn() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login", status: 200, json: Self.authJSON)
        harness.viewModel.setEmail("a@b.c")
        harness.viewModel.setPassword("pw")
        await harness.viewModel.submitCredentials()
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        XCTAssertFalse(harness.viewModel.state.isBusy)
        XCTAssertNil(harness.viewModel.state.errorMessage)
        XCTAssertTrue(harness.states.values.contains { $0.isBusy })     // busy was observable mid-flight
    }

    func testSubmitCredentialsWithBadPasswordShowsTheMessage() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login", status: 401, json: #"{"error":{"message":"bad"}}"#)
        harness.viewModel.setEmail("a@b.c")
        harness.viewModel.setPassword("wrong")
        await harness.viewModel.submitCredentials()
        XCTAssertEqual(harness.viewModel.state.errorMessage, "Invalid email or password.")
        XCTAssertEqual(harness.viewModel.state.mode, .credentials)
        XCTAssertFalse(harness.viewModel.state.isBusy)
        XCTAssertEqual(harness.signedIn.values, [])
    }

    func testTransportFailureShowsTheOfflineMessage() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login") { _, _ in throw URLError(.notConnectedToInternet) }
        harness.viewModel.setEmail("a@b.c")
        harness.viewModel.setPassword("pw")
        await harness.viewModel.submitCredentials()
        let offlineMessage = "Could not reach the server. Check your connection and try again."
        XCTAssertEqual(harness.viewModel.state.errorMessage, offlineMessage)
    }

    func testSubmitCredentialsIgnoredWhenNotSubmittable() async {
        let harness = makeHarness()
        await harness.viewModel.submitCredentials()
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/login"), 0)
    }

    func testSecondSubmitWhileBusyDoesNotFireASecondRequest() async {
        let harness = makeHarness()
        harness.stub.on(.post, "/auth/login") { _, _ in .init(status: 200, json: Self.authJSON) }
        harness.viewModel.setEmail("a@b.c")
        harness.viewModel.setPassword("pw")
        async let first: Void = harness.viewModel.submitCredentials()
        async let second: Void = harness.viewModel.submitCredentials()
        _ = await (first, second)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/login"), 1)
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
    }

    // MARK: MFA

    private func enterMfa(_ harness: Harness) async {
        harness.stub.on(.post, "/auth/login", status: 202, json: Self.mfaJSON)
        harness.viewModel.setEmail("a@b.c")
        harness.viewModel.setPassword("pw")
        await harness.viewModel.submitCredentials()
    }

    func testMfaChallengeSwitchesModeAndSelectsTheFirstMethod() async {
        let harness = makeHarness()
        await enterMfa(harness)
        let expectedChallenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp, .sms, .webauthn, .recovery])
        XCTAssertEqual(harness.viewModel.state.mode, .mfa(expectedChallenge))
        XCTAssertEqual(harness.viewModel.state.availableMethods, [.totp, .sms, .webauthn, .recovery])
        XCTAssertEqual(harness.viewModel.state.selectedMethod, .totp)
        XCTAssertEqual(harness.viewModel.state.password, "")
        XCTAssertEqual(harness.viewModel.state.email, "a@b.c")
        XCTAssertTrue(harness.viewModel.state.showsCodeField)
        XCTAssertFalse(harness.viewModel.state.showsSendCode)
        XCTAssertFalse(harness.viewModel.state.showsUsePasskey)
    }

    func testMethodSelectionDrivesTheVisibleControls() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.viewModel.selectMethod(.sms)
        XCTAssertTrue(harness.viewModel.state.showsCodeField)
        XCTAssertTrue(harness.viewModel.state.showsSendCode)
        harness.viewModel.selectMethod(.webauthn)
        XCTAssertFalse(harness.viewModel.state.showsCodeField)
        XCTAssertTrue(harness.viewModel.state.showsUsePasskey)
        XCTAssertFalse(harness.viewModel.state.canSubmitCode)
        harness.viewModel.selectMethod(.recovery)
        harness.viewModel.setCode("abcd-efgh")
        XCTAssertTrue(harness.viewModel.state.canSubmitCode)
    }

    // MARK: methodMenu (crash regression: UIKit throws if `changesSelectionAsPrimaryAction`
    // is true and the assigned menu has zero `.on` elements — see ios-launch-crash-brief.md)

    func testMethodMenuIsEmptyInCredentialsMode() {
        let state = SignInViewModel.State()
        XCTAssertTrue(state.methodMenu.items.isEmpty)
        XCTAssertEqual(state.methodMenu.title, "Method")
    }

    func testMethodMenuSelectsFirstWhenNoMethodChosen() {
        var state = SignInViewModel.State()
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp, .sms, .webauthn, .recovery])
        state.mode = .mfa(challenge)
        state.selectedMethod = nil
        let menu = state.methodMenu
        XCTAssertEqual(menu.items.filter(\.isSelected).count, 1)
        XCTAssertTrue(menu.items[0].isSelected)
        XCTAssertEqual(menu.title, MfaChallengeMethod.totp.label)
    }

    func testMethodMenuHonorsChosenMethod() {
        var state = SignInViewModel.State()
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp, .sms, .webauthn, .recovery])
        state.mode = .mfa(challenge)
        state.selectedMethod = .webauthn
        let menu = state.methodMenu
        XCTAssertEqual(menu.items.filter(\.isSelected).count, 1)
        XCTAssertEqual(menu.items.first(where: \.isSelected)?.method, .webauthn)
        XCTAssertEqual(menu.title, MfaChallengeMethod.webauthn.label)
    }

    func testMethodMenuFallsBackWhenChosenMethodIsUnavailable() {
        var state = SignInViewModel.State()
        let challenge = MfaChallengeInfo(token: "mfa-tok", methods: [.totp, .sms])
        state.mode = .mfa(challenge)
        state.selectedMethod = .webauthn
        let menu = state.methodMenu
        XCTAssertEqual(menu.items.filter(\.isSelected).count, 1)
        XCTAssertTrue(menu.items[0].isSelected)
        XCTAssertEqual(menu.items[0].method, .totp)
    }

    func testCanSubmitCodeIsFalseOnBlankCode() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.viewModel.selectMethod(.totp)
        harness.viewModel.setCode("   ")
        XCTAssertFalse(harness.viewModel.state.canSubmitCode)
        harness.viewModel.setCode("123456")
        XCTAssertTrue(harness.viewModel.state.canSubmitCode)
    }

    func testSecondSubmitCodeWhileBusyDoesNotFireASecondRequest() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.stub.on(.post, "/auth/login/mfa") { _, _ in .init(status: 200, json: Self.authJSON) }
        harness.viewModel.setCode("123456")
        async let first: Void = harness.viewModel.submitCode()
        async let second: Void = harness.viewModel.submitCode()
        _ = await (first, second)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/login/mfa"), 1)
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
    }

    func testSubmitCodeCompletesMfa() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.stub.on(.post, "/auth/login/mfa", status: 200, json: Self.authJSON)
        harness.viewModel.setCode("123456")
        await harness.viewModel.submitCode()
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        let body = harness.stub.lastBody(.post, "/auth/login/mfa") ?? [:]
        XCTAssertEqual(body["token"] as? String, "mfa-tok")
        XCTAssertEqual(body["method"] as? String, "totp")
        XCTAssertEqual(body["code"] as? String, "123456")
    }

    func testWrongCodeShowsMessageAndStaysInMfa() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.stub.on(.post, "/auth/login/mfa", status: 401, json: #"{"error":{"message":"bad code"}}"#)
        harness.viewModel.setCode("000000")
        await harness.viewModel.submitCode()
        XCTAssertEqual(harness.viewModel.state.errorMessage, "Invalid email or password.")
        if case .mfa = harness.viewModel.state.mode {} else { XCTFail("expected to stay in MFA") }
        XCTAssertFalse(harness.viewModel.state.isBusy)
    }

    func testSendCodeShowsCodeSent() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.stub.on(.post, "/auth/login/mfa/sms/send", status: 202, json: #"{"ok":true}"#)
        harness.viewModel.selectMethod(.sms)
        await harness.viewModel.sendCode()
        XCTAssertEqual(harness.viewModel.state.infoMessage, SignInViewModel.codeSentMessage)
        XCTAssertNil(harness.viewModel.state.errorMessage)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/login/mfa/sms/send"), 1)
    }

    func testSuccessfulRetryClearsStaleMessages() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.viewModel.selectMethod(.sms)
        harness.stub.on(.post, "/auth/login/mfa/sms/send", status: 202, json: #"{"ok":true}"#)
        await harness.viewModel.sendCode()
        XCTAssertEqual(harness.viewModel.state.infoMessage, SignInViewModel.codeSentMessage)

        harness.stub.on(.post, "/auth/login/mfa", status: 401, json: #"{"error":{"message":"bad code"}}"#)
        harness.viewModel.setCode("000000")
        await harness.viewModel.submitCode()
        XCTAssertEqual(harness.viewModel.state.errorMessage, "Invalid email or password.")

        // A later successful call must not leave the stale error message
        // behind, even though the success path itself never touches
        // `errorMessage` — pins `run()`'s `state.errorMessage = nil`.
        await harness.viewModel.sendCode()
        XCTAssertNil(harness.viewModel.state.errorMessage)
        XCTAssertEqual(harness.viewModel.state.infoMessage, SignInViewModel.codeSentMessage)

        // Nor must a later successful call leave a stale info message
        // behind, even though the success path itself never touches
        // `infoMessage` — pins `run()`'s `state.infoMessage = nil`.
        harness.stub.on(.post, "/auth/login/mfa", status: 200, json: Self.authJSON)
        harness.viewModel.setCode("123456")
        await harness.viewModel.submitCode()
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        XCTAssertNil(harness.viewModel.state.infoMessage)
    }

    func testSecondSendCodeWhileBusyDoesNotFireASecondRequest() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.stub.on(.post, "/auth/login/mfa/sms/send") { _, _ in .init(status: 202, json: #"{"ok":true}"#) }
        harness.viewModel.selectMethod(.sms)
        async let first: Void = harness.viewModel.sendCode()
        async let second: Void = harness.viewModel.sendCode()
        _ = await (first, second)
        XCTAssertEqual(harness.stub.requestCount(.post, "/auth/login/mfa/sms/send"), 1)
    }

    func testMfaPasskeyCompletesSignIn() async {
        let harness = makeHarness()
        await enterMfa(harness)
        let mfaWebauthnPath = "/auth/login/mfa/webauthn/options"
        harness.stub.on(.post, mfaWebauthnPath, status: 200, json: Self.passkeyOptionsJSON(token: "mfa-tok"))
        harness.stub.on(.post, "/auth/login/mfa/webauthn", status: 200, json: Self.authJSON)
        harness.viewModel.selectMethod(.webauthn)
        await harness.viewModel.usePasskey()
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        XCTAssertEqual(harness.passkeyCalls.values.count, 1)
    }

    func testCancelMfaReturnsToCredentialsKeepingEmail() async {
        let harness = makeHarness()
        await enterMfa(harness)
        harness.viewModel.setCode("12")
        harness.viewModel.cancelMfa()
        XCTAssertEqual(harness.viewModel.state.mode, .credentials)
        XCTAssertEqual(harness.viewModel.state.email, "a@b.c")
        XCTAssertEqual(harness.viewModel.state.code, "")
        XCTAssertNil(harness.viewModel.state.selectedMethod)
        XCTAssertNil(harness.viewModel.state.errorMessage)
    }

    // MARK: passkey (credentials mode)

    func testUsePasskeyNeedsAnEmail() async {
        let harness = makeHarness()
        await harness.viewModel.usePasskey()
        XCTAssertEqual(harness.viewModel.state.errorMessage, SignInViewModel.passkeyNeedsEmailMessage)
        XCTAssertEqual(harness.passkeyCalls.values.count, 0)
    }

    func testUsePasskeySignsIn() async {
        let harness = makeHarness()
        let webauthnOptionsPath = "/auth/login/webauthn/options"
        harness.stub.on(.post, webauthnOptionsPath, status: 200, json: Self.passkeyOptionsJSON(token: "pk-tok"))
        harness.stub.on(.post, "/auth/login/webauthn", status: 200, json: Self.authJSON)
        harness.viewModel.setEmail("a@b.c")
        await harness.viewModel.usePasskey()
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        let optionsBody = harness.stub.lastBody(.post, "/auth/login/webauthn/options") ?? [:]
        XCTAssertEqual(optionsBody["identifier"] as? String, "a@b.c")
    }

    func testSecondUsePasskeyWhileBusyDoesNotFireASecondRequest() async {
        let harness = makeHarness()
        let webauthnOptionsPath = "/auth/login/webauthn/options"
        let optionsJSON = Self.passkeyOptionsJSON(token: "pk-tok")
        harness.stub.on(.post, webauthnOptionsPath) { _, _ in .init(status: 200, json: optionsJSON) }
        harness.stub.on(.post, "/auth/login/webauthn") { _, _ in .init(status: 200, json: Self.authJSON) }
        harness.viewModel.setEmail("a@b.c")
        async let first: Void = harness.viewModel.usePasskey()
        async let second: Void = harness.viewModel.usePasskey()
        _ = await (first, second)
        XCTAssertEqual(harness.stub.requestCount(.post, webauthnOptionsPath), 1)
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
    }

    func testPasskeyCancelIsSilent() async {
        let harness = makeHarness(passkey: .cancel)
        let webauthnOptionsPath = "/auth/login/webauthn/options"
        harness.stub.on(.post, webauthnOptionsPath, status: 200, json: Self.passkeyOptionsJSON(token: "pk-tok"))
        harness.viewModel.setEmail("a@b.c")
        await harness.viewModel.usePasskey()
        XCTAssertNil(harness.viewModel.state.errorMessage)
        XCTAssertFalse(harness.viewModel.state.isBusy)
        XCTAssertEqual(harness.signedIn.values, [])
    }

    // MARK: social

    func testSocialSignInExchangesTheCode() async {
        let harness = makeHarness(social: .code("abc123"))
        harness.stub.on(.post, "/oauth/signin/exchange", status: 200, json: Self.authJSON)
        await harness.viewModel.signInWithSocial(.github)
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
        XCTAssertEqual((harness.stub.lastBody(.post, "/oauth/signin/exchange") ?? [:])["code"] as? String, "abc123")
    }

    func testSecondSignInWithSocialWhileBusyDoesNotFireASecondRequest() async {
        let harness = makeHarness(social: .code("abc123"))
        harness.stub.on(.post, "/oauth/signin/exchange") { _, _ in .init(status: 200, json: Self.authJSON) }
        async let first: Void = harness.viewModel.signInWithSocial(.github)
        async let second: Void = harness.viewModel.signInWithSocial(.github)
        _ = await (first, second)
        XCTAssertEqual(harness.stub.requestCount(.post, "/oauth/signin/exchange"), 1)
        XCTAssertEqual(harness.signedIn.values, [Self.ada])
    }

    func testSocialCancelIsSilent() async {
        let harness = makeHarness(social: .cancel)
        await harness.viewModel.signInWithSocial(.google)
        XCTAssertNil(harness.viewModel.state.errorMessage)
        XCTAssertFalse(harness.viewModel.state.isBusy)
        XCTAssertEqual(harness.stub.requestCount(.post, "/oauth/signin/exchange"), 0)
    }

    func testSocialCallbackWithoutCodeShowsTheMessage() async {
        let harness = makeHarness(social: .noCode)
        await harness.viewModel.signInWithSocial(.apple)
        XCTAssertEqual(harness.viewModel.state.errorMessage, "The sign-in response did not include a code.")
    }

    func testSocialProvidersAreAllFive() {
        XCTAssertEqual(SignInViewModel.socialProviders, [.google, .github, .gitlab, .bitbucket, .apple])
    }
}
