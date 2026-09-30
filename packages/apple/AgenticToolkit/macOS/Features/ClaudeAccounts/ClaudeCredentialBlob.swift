import AgenticToolkitCore
import Foundation

/// The whole `Claude Code-credentials` blob, read and written **field-preserving**.
///
/// The blob holds more than the login: alongside `claudeAiOauth` sits `mcpOAuth`,
/// a dictionary of per-MCP-server authorizations keyed by server name. Those have
/// nothing to do with which Claude account is signed in, and a switch that wrote
/// a freshly-built blob would silently sign the user out of every MCP server they
/// had connected. So this type keeps the parsed JSON object whole and swaps one
/// key inside it — and the same applies to any key Claude Code adds later that
/// this app has never heard of.
///
/// **The blob is the keychain item's format, so it lives with the custody.** The
/// app is the only process macOS will let near that item, so it is the only
/// process that ever holds these bytes; what crosses to the daemon is the parsed
/// ``ClaudeOAuthCredential``, which the protocol tier defines and both ends name.
/// Nothing in the daemon or the CLI reads this type, and compiling it into them
/// would have advertised a format they have no way to obtain.
///
/// Deliberately **not** `Sendable`: it holds a `[String: Any]`, which no amount
/// of annotation makes safe to hand between isolation domains. It never needs
/// to be — it is built, edited and serialized inside one `async` function, and
/// what crosses the boundary either side of it is `Data` going in and
/// `ClaudeOAuthCredential` coming out, both of which are.
public struct ClaudeCredentialBlob {

    /// Everything the blob contained, as decoded JSON.
    private var object: [String: Any]

    private static let oauthKey = "claudeAiOauth"

    public init(data: Data) throws {
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCredentialBlobError.notAnObject
        }
        object = parsed
    }

    /// The signed-in account's OAuth credential, if the blob has one.
    public func oauth() throws -> ClaudeOAuthCredential? {
        guard let raw = object[Self.oauthKey] else { return nil }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try JSONDecoder().decode(ClaudeOAuthCredential.self, from: data)
    }

    /// Replaces the login, leaving every other key — `mcpOAuth` above all —
    /// exactly as it was.
    public mutating func setOAuth(_ oauth: ClaudeOAuthCredential) throws {
        let data = try JSONEncoder().encode(oauth)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeCredentialBlobError.notAnObject
        }
        object[Self.oauthKey] = dictionary
    }

    /// The bytes to store. Written compactly and with sorted keys so that
    /// re-saving an unchanged blob produces identical bytes — a diff in the
    /// keychain should mean a real change.
    public func serialized() throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

public enum ClaudeCredentialBlobError: Error, LocalizedError {

    case notAnObject
    case noLogin

    public var errorDescription: String? {
        switch self {
        case .notAnObject:
            return "Claude Code's keychain item isn't in the format \(ClaudeAccounts.appName) expects."
        case .noLogin:
            return "Claude Code's keychain item has no signed-in account in it."
        }
    }
}
