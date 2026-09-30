import Foundation

/// The OAuth credential Claude Code keeps for one account — the `claudeAiOauth`
/// object inside the `Claude Code-credentials` keychain item.
///
/// "The token" is four things, not one: two tokens with two separate expiries.
/// Rotating an account means replacing all four together, which is why they
/// travel as a struct rather than as a string passed around.
///
/// **It lives in Core because every process that touches a login needs it and
/// none of them owns it.** An app has custody (it reads and writes the keychain
/// item), a daemon evaluates it (is the access token still worth sending, and
/// if not, spend the refresh token), and both halves of that conversation cross
/// an XPC boundary — so the one definition has to sit under both. Putting it in
/// either end would make the other end depend upward.
public struct ClaudeOAuthCredential: Codable, Sendable, Equatable {

    public var accessToken: String
    public var refreshToken: String
    /// Unix milliseconds, as Claude Code writes them.
    public var expiresAt: Double?
    public var refreshTokenExpiresAt: Double?
    public var scopes: [String]
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Double? = nil,
        refreshTokenExpiresAt: Double? = nil,
        scopes: [String] = [],
        subscriptionType: String? = nil,
        rateLimitTier: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// Seconds, for anything that wants a `Date` rather than Claude Code's
    /// milliseconds.
    public var expirySeconds: Double? { expiresAt.map { $0 / 1000 } }
    public var refreshExpirySeconds: Double? { refreshTokenExpiresAt.map { $0 / 1000 } }
}
