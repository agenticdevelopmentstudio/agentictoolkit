import Foundation

/// Which kind of Claude credential an app has saved, and which one a quota
/// reading measured.
///
/// The two are **not** two halves of one account. A `claude setup-token` token
/// and an OAuth login bill against different rate-limit buckets, so the same
/// email can read 100% on one and 8% on the other at the same instant. Merging
/// them under one name meant one row, one usage number and one delete for two
/// things that measure, expire and revoke independently.
///
/// It lives in Core rather than beside the keychain record because every layer
/// names the same fact: the keychain item a credential is stored in, a settings
/// table's type column, a reading an app pushes over XPC, and the quota section
/// a daemon builds out of that reading.
public enum ClaudeCredentialKind: String, Codable, Sendable, CaseIterable {
    /// A full Claude Code login, rotatable onto this Mac.
    case oauth
    /// A `claude setup-token` token — something to bill against, not a login.
    case longLived = "long-lived"

    /// What a type column, a details pane and a quota card's header show.
    public var title: String {
        switch self {
        case .oauth: return "OAuth"
        case .longLived: return "Long-lived"
        }
    }

    /// The one spelling of "this kind of credential, for this account".
    ///
    /// One definition, because three things written by one layer and read by
    /// another have to agree on it: the keychain item a credential is stored
    /// under, the per-credential "Show in Quota Window" preference, and the
    /// quota section a daemon ships. A second spelling anywhere is a
    /// preference that silently stops matching the card it was set on.
    public func key(for name: String) -> String {
        Self.key(account: name, kindRawValue: rawValue)
    }

    /// `key(for:)` from a raw value that may be missing or unrecognized — the
    /// wire form, where a kind this build has never heard of is still a
    /// distinct credential and still has to get a distinct key.
    public static func key(account: String, kindRawValue: String?) -> String {
        guard let kindRawValue, !kindRawValue.isEmpty else { return account }
        return "\(kindRawValue):\(account)"
    }

    /// Splits a key back into the kind and the account name, or nil for a
    /// legacy key that is a bare account name.
    ///
    /// An account name is an email, so it cannot contain a colon — and even a
    /// name that did would have to begin with one of these rawValues to be
    /// mistaken for a kind-keyed one.
    public static func parse(itemKey: String) -> (kind: ClaudeCredentialKind, name: String)? {
        guard let colon = itemKey.firstIndex(of: ":"),
              let kind = ClaudeCredentialKind(rawValue: String(itemKey[itemKey.startIndex..<colon]))
        else { return nil }
        return (kind, String(itemKey[itemKey.index(after: colon)...]))
    }
}
