import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import OpenAPIRuntime

public enum SessionState: Equatable, Sendable {
    case restoring
    case signedOut
    case signedIn(HubUser)
    case error(String)
}

public enum MfaChallengeMethod: String, Sendable, CaseIterable {
    case sms, totp, webauthn, recovery

    public var label: String {
        switch self {
        case .sms: "Text message"
        case .totp: "Authenticator app"
        case .webauthn: "Passkey"
        case .recovery: "Recovery code"
        }
    }

    init(_ generated: Components.Schemas.MfaChallenge.MethodsPayloadPayload) {
        switch generated {
        case .sms: self = .sms
        case .totp: self = .totp
        case .webauthn: self = .webauthn
        case .recovery: self = .recovery
        }
    }
}

public struct MfaChallengeInfo: Equatable, Sendable {
    public let token: String
    public let methods: [MfaChallengeMethod]

    public init(token: String, methods: [MfaChallengeMethod]) {
        self.token = token
        self.methods = methods
    }

    init(_ challenge: Components.Schemas.MfaChallenge) {
        self.init(token: challenge.token, methods: challenge.methods.map(MfaChallengeMethod.init))
    }
}

public enum SignInStep: Equatable, Sendable {
    case done(HubUser)
    case mfa(MfaChallengeInfo)
}

public enum SessionControllerError: Error, Equatable, Sendable {
    case passkeyRequired
    case missingOAuthCode
}

/// Owns the signed-in/out state for the shell (spec §5.1–§5.2, §5.5).
/// Every API call goes through `environment.client` at call time — the
/// client is rebuilt when the transport kind changes, so never cache it.
@MainActor
public final class SessionController {
    /// Alias for `WorkspaceController.recentsKey`: `signOut()` clears the
    /// recents list on the same key the picker reads, and Task 9's shell
    /// tests reach for this name rather than reaching across into
    /// `WorkspaceController` for what is, from the session's point of view,
    /// just "the recents key".
    public static let recentsKey = WorkspaceController.recentsKey

    public private(set) var state: SessionState = .restoring {
        didSet { if state != oldValue { onChange(state) } }
    }
    public var onChange: @MainActor (SessionState) -> Void = { _ in }
    public let configuration: SignInConfiguration

    private let environment: HubEnvironment
    private let cache: CachedUserStore
    private let defaults: UserDefaults

    public init(environment: HubEnvironment, configuration: SignInConfiguration, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.configuration = configuration
        self.defaults = defaults
        self.cache = CachedUserStore(defaults: defaults)
        environment.onSessionExpired = { [weak self] in self?.sessionExpired() }
    }

    public var user: HubUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    // MARK: Launch

    /// Spec §5.1 launch sequence: no session → sign-in; `/auth/me` → home;
    /// a rejected refresh → sign-in; unreachable backend → the cached user
    /// (offline launch) or an error when there is none.
    public func restore() async {
        guard environment.sessionStore.currentSession() != nil else {
            cache.clear()
            state = .signedOut
            return
        }
        do {
            let user = HubUser(try await environment.client.currentUser())
            cache.save(user)
            state = .signedIn(user)
        } catch SessionError.invalidCredentials {
            // The server said no outright. That is unconditional: never let a
            // sibling component's side effect (whether the refresh middleware
            // has already cleared the store) decide whether this signs out,
            // and never fall back to a cached user for an explicit rejection
            // — the cache fallback below is for the backend being unreachable,
            // not for a response that said no.
            environment.sessionStore.clear()
            cache.clear()
            state = .signedOut
        } catch let error where Self.isTransportFailure(error) {
            if let cached = cache.load() {
                state = .signedIn(cached)
            } else {
                state = .error(Self.userMessage(for: error))
            }
        } catch {
            state = .error(Self.userMessage(for: error))
        }
    }

    /// A `ClientError` is the generated client's envelope, not a failure in
    /// its own right: the error worth classifying is always the one it wraps,
    /// however many layers deep. This is the single place in this type that
    /// knows that — `isTransportFailure` and `userMessage(for:)` both start
    /// here instead of each recursing through `underlyingError` themselves.
    private static func unwrapped(_ error: any Error) -> any Error {
        guard let clientError = error as? ClientError else { return error }
        return unwrapped(clientError.underlyingError)
    }

    /// `true` only when the backend was never reached at all — a `URLError`,
    /// directly or wrapped in a `ClientError`. Any error that means the
    /// server actually answered (an explicit rejection, an unmapped status, a
    /// malformed body) is not a transport failure and must not fall back to
    /// a cached user.
    private static func isTransportFailure(_ error: any Error) -> Bool {
        unwrapped(error) is URLError
    }

    // MARK: Password + MFA

    public func signIn(email: String, password: String) async throws -> SignInStep {
        try await attemptingSignIn {
            switch try await environment.client.signIn(email: email, password: password) {
            case .signedIn(let generated):
                return .done(finishSignIn(generated))
            case .mfaRequired(let challenge):
                state = .signedOut
                return .mfa(MfaChallengeInfo(challenge))
            }
        }
    }

    public func completeMfa(
        challenge: MfaChallengeInfo,
        method: MfaChallengeMethod,
        code: String
    ) async throws -> HubUser {
        try await attemptingSignIn {
            let apiMethod: MfaMethod
            switch method {
            case .sms: apiMethod = .sms
            case .totp: apiMethod = .totp
            case .recovery: apiMethod = .recovery
            case .webauthn: throw SessionControllerError.passkeyRequired
            }
            let generated = try await environment.client.completeMfa(
                challengeToken: challenge.token,
                method: apiMethod,
                code: code
            )
            return finishSignIn(generated)
        }
    }

    public func sendMfaSms(challenge: MfaChallengeInfo) async throws {
        try await environment.client.sendMfaSms(challengeToken: challenge.token)
    }

    // MARK: Passkeys

    public func signInWithPasskey(identifier: String, provider: any PasskeyAssertionProvider) async throws -> HubUser {
        try await attemptingSignIn {
            let options = try await environment.client.passkeyOptions(identifier: identifier)
            let assertion = try await provider.assert(options: options.options)
            let generated = try await environment.client.completePasskey(
                challengeToken: options.token,
                response: assertion
            )
            return finishSignIn(generated)
        }
    }

    public func completeMfaWithPasskey(
        challenge: MfaChallengeInfo,
        provider: any PasskeyAssertionProvider
    ) async throws -> HubUser {
        try await attemptingSignIn {
            let options = try await environment.client.mfaPasskeyOptions(challengeToken: challenge.token)
            let assertion = try await provider.assert(options: options.options)
            let generated = try await environment.client.completeMfaPasskey(
                challengeToken: options.token,
                response: assertion
            )
            return finishSignIn(generated)
        }
    }

    // MARK: Social

    /// Runs the browser round-trip and redeems the code it yields.
    ///
    /// The `userAgent` that comes back with the code is not decoration: the
    /// backend binds the code to whoever received it, so the exchange must
    /// present the *browser's* header rather than the app's (see
    /// ``SignInConfiguration`` and ``LoopbackAuthServer``).
    ///
    /// The exchange is retried once, and only when the failure was the
    /// transport — a `SessionError` means the backend answered, and a stale or
    /// rejected code will not improve on retry. The code is single-use even on
    /// a rejection, so a retry after an answer would burn it for nothing.
    public func signInWithSocial(
        _ provider: SocialProvider,
        using session: any SocialSignInProvider
    ) async throws -> HubUser {
        try await attemptingSignIn {
            let configuration = self.configuration
            let result = try await session.authenticate(
                SocialSignInRequest(
                    makeStartURL: { returnURL in
                        configuration.socialStartURL(provider: provider, returnURL: returnURL)
                    },
                    callbackScheme: configuration.callbackScheme,
                    dismissURL: configuration.callbackURL
                )
            )
            let generated: Components.Schemas.User
            do {
                generated = try await environment.client.exchangeOAuthCode(
                    result.code,
                    userAgent: result.userAgent
                )
            } catch let error as SessionError {
                throw error
            } catch {
                generated = try await environment.client.exchangeOAuthCode(
                    result.code,
                    userAgent: result.userAgent
                )
            }
            return finishSignIn(generated)
        }
    }

    // There is deliberately **no** entry point here for a system-delivered
    // `adh://auth-callback` URL. That URL carries no code — it is only the
    // capture page's last hop, there to dismiss the browser sheet — so there
    // is nothing for a handler to deliver. The code reaches the app over the
    // loopback listener instead, gated on a per-attempt nonce that only this
    // attempt and the browser it opened know (see `LoopbackAuthServer`).
    //
    // An earlier revision had a `handleExternalCallback(_:)` guarded by an
    // app-wide `pendingSocialAttempt` Bool. Nothing ever called it — there is
    // no `scene(_:openURLContexts:)`, no `application(_:open:options:)` and no
    // macOS URL Apple Event handler in this app — and the gate it offered was
    // not one worth inheriting: a single process-wide flag held open for the
    // whole browser interaction accepts *any* callback that arrives during a
    // legitimate attempt, which is exactly authorization-code injection. The
    // loopback nonce is the per-attempt token that gate needed, and it is
    // checked on the only path a code can travel.

    // MARK: Sign-out

    /// Spec §5.5: forget recents, revoke best-effort, clear the session.
    public func signOut() async {
        defaults.removeObject(forKey: WorkspaceController.recentsKey)
        cache.clear()
        await environment.client.signOut()
        state = .signedOut
    }

    // MARK: Messages

    /// Sign-in-screen copy for a failure. Deliberately a *different*
    /// vocabulary from `HubError.message`, which speaks to a signed-in data
    /// surface: the same 401 means "the password you just typed is wrong"
    /// here and "your session expired" there, so the two cannot collapse into
    /// one authority. What they must not each own is the *unwrapping* —
    /// recursing through `ClientError`, enumerating `SessionError` — so this
    /// keeps only the cases whose copy is genuinely sign-in-specific and
    /// hands everything else to `HubError.from(_:)`, reading the resulting
    /// case rather than re-deriving it.
    ///
    /// The four overrides, and why each cannot be expressed as a `HubError`:
    /// `SessionControllerError` never reaches a data surface at all;
    /// cancellation and an unreachable backend both map to `HubError.transport`,
    /// which cannot tell them apart or tell either from a wholly unrecognized
    /// failure; and `.unauthorized` is the one case whose wording differs by
    /// screen.
    public static func userMessage(for error: any Error) -> String {
        let error = unwrapped(error)
        if let controllerError = error as? SessionControllerError {
            switch controllerError {
            case .passkeyRequired: return "This MFA method needs a passkey. Choose Use passkey."
            case .missingOAuthCode: return "The sign-in response did not include a code."
            }
        }
        if error is CancellationError { return "Sign-in was cancelled." }
        if error is URLError { return "Could not reach the server. Check your connection and try again." }
        switch HubError.from(error) {
        case .unauthorized: return "Invalid email or password."
        // Deliberately does not delegate to `HubError.from(_:).message`: that
        // message interpolates server-supplied detail text, and this is a
        // sign-in surface — rendering attacker-influenced text into a
        // sign-in form is not a risk worth taking just because no current
        // call site happens to reach this arm with untrusted input.
        case .unexpected: return "Something went wrong and we couldn't finish that. Please try again."
        default: return "Something went wrong and we couldn't finish that. Please try again."
        }
    }

    // MARK: Private

    /// The shared failure policy for every sign-in entry point: on a thrown
    /// error, normalize to `.signedOut` so the caller lands on the sign-in
    /// screen rather than stuck wherever `state` happened to be (in
    /// particular, `.error(...)` left standing by a failed `restore()`) —
    /// except when `state` is already `.signedIn`, which a failing secondary
    /// operation (e.g. a stale retry) must never demote.
    private func attemptingSignIn<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            if case .signedIn = state {} else { state = .signedOut }   // never demote a live session
            throw error
        }
    }

    private func finishSignIn(_ generated: Components.Schemas.User) -> HubUser {
        let user = HubUser(generated)
        cache.save(user)
        state = .signedIn(user)
        return user
    }

    private func sessionExpired() {
        cache.clear()
        state = .signedOut
    }
}
