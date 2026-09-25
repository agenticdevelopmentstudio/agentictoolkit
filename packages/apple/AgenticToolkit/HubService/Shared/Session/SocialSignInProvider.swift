import Foundation

/// What a completed browser round-trip yields.
///
/// `userAgent` travels with the code because the backend's exchange store
/// binds one to the other: the code is redeemable only by a request whose
/// `User-Agent` matches the browser's, byte for byte. It is captured from the
/// capture page's own request to the loopback listener, not guessed.
public struct SocialSignInResult: Sendable, Equatable {
    public let code: String
    public let userAgent: String

    public init(code: String, userAgent: String) {
        self.code = code
        self.userAgent = userAgent
    }
}

/// Everything the browser round-trip needs that only the session layer knows.
///
/// `makeStartURL` is a function rather than a URL because the `return` origin
/// is not known until the loopback listener has actually bound a port — the
/// provider owns that, so the provider finishes the URL.
public struct SocialSignInRequest: Sendable {
    /// Loopback return URL → the backend's `/oauth/signin/start` URL.
    public let makeStartURL: @Sendable (URL) -> URL
    /// The scheme whose appearance ends the browser session (`adh`).
    public let callbackScheme: String
    /// The URL the capture page's final hop navigates to, so the browser
    /// session dismisses itself once the code has been delivered.
    public let dismissURL: URL

    public init(
        makeStartURL: @escaping @Sendable (URL) -> URL,
        callbackScheme: String,
        dismissURL: URL
    ) {
        self.makeStartURL = makeStartURL
        self.callbackScheme = callbackScheme
        self.dismissURL = dismissURL
    }
}

/// Runs the whole browser sign-in round-trip and resolves with the exchange
/// code. `WebAuthSocialSignIn` pairs `ASWebAuthenticationSession` with a
/// `LoopbackAuthServer`; tests return a canned result.
///
/// The seam is the *whole* round-trip rather than "open this URL" because the
/// two halves are inseparable: the return URL cannot be built before the
/// listener binds, and the code never passes through the browser session's own
/// callback at all.
///
/// A user who closes the browser throws `CancellationError`; a provider that
/// reported a failure instead of a code throws
/// `SessionControllerError.missingOAuthCode`.
public protocol SocialSignInProvider: Sendable {
    func authenticate(_ request: SocialSignInRequest) async throws -> SocialSignInResult
}
