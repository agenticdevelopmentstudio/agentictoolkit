import AgenticToolkitCore
import Foundation

/// One saved Claude credential, as the table draws it.
///
/// A flattened, display-ready view of a `ClaudeSavedAccount` plus the two facts
/// that come from outside it: which keychain it was found in, and whether it is
/// the login this Mac is currently running as.
///
/// One row is one credential, never an account's two credentials folded
/// together — so an email with both a login and a setup token draws two rows,
/// and each carries its own usage, its own expiry and its own delete.
public struct ClaudeAccountRecord: Sendable, Equatable, Identifiable {

    /// The account name, which is the email the account itself reports.
    public let name: String
    /// Which credential this row is.
    public let kind: ClaudeCredentialKind
    /// The keychain item it lives in — the row's real identity, and what a
    /// delete has to name.
    public let itemKey: String
    /// When the app first saved it, epoch seconds.
    public let addedAt: Double?
    /// The saved login's own identity label, "" for a token typed in by hand.
    public let identity: String
    public let accountUUID: String
    /// Access-token expiry, epoch seconds — OAuth accounts only.
    public let expiresAt: Double?
    /// Refresh-token expiry, epoch seconds — OAuth accounts only.
    public let refreshExpiresAt: Double?
    /// This saved login IS the machine-wide login `~/.claude.json` names.
    public let isCurrentLogin: Bool
    /// Which keychain holds it. Per-record rather than read off the setting,
    /// because the list spans both and the setting says only where the *next*
    /// save goes.
    public let location: ClaudeKeychainLocation
    /// How many characters the revealable token has, so the details pane can
    /// obscure it one bullet per character instead of a fixed run of dots that
    /// tells you the wrong length. A count is not the secret — the listing is
    /// already holding the string it counted, and this is the only thing about
    /// it that leaves `ClaudeAuthStore`.
    public let tokenLength: Int

    /// Keyed by the item, not the name: two rows can share a name, and a table
    /// whose ids collided would select and redraw the wrong one.
    public var id: String { itemKey }

    /// What the table's "type" column shows.
    public var typeLabel: String { kind.title }

    public init(_ located: ClaudeAccountKeychainStore.Located, isCurrentLogin: Bool) {
        let account = located.account
        name = account.name
        kind = account.kind
        itemKey = located.itemKey
        addedAt = account.addedAt
        identity = account.identity
        accountUUID = account.accountUUID
        expiresAt = account.oauth?.expirySeconds
        refreshExpiresAt = account.oauth?.refreshExpirySeconds
        self.isCurrentLogin = isCurrentLogin
        location = located.location
        tokenLength = account.revealableToken?.count ?? 0
    }
}

/// Every account the app has saved, plus who is logged in right now.
public struct ClaudeAccountListing: Sendable {

    public struct CurrentLogin: Sendable, Equatable {
        public let email: String
        public let uuid: String

        public static let none = CurrentLogin(email: "", uuid: "")
    }

    public let accounts: [ClaudeAccountRecord]
    public let currentLogin: CurrentLogin

    public static let empty = ClaudeAccountListing(accounts: [], currentLogin: .none)

    public init(accounts: [ClaudeAccountRecord], currentLogin: CurrentLogin) {
        self.accounts = accounts
        self.currentLogin = currentLogin
    }

    /// The saved OAuth logins, by name — the accounts the app can rotate to,
    /// and so the only ones the Auth menu and the gear popover list. A
    /// long-lived token is something for `claude` to bill against, not a login
    /// this Mac can be switched to.
    public var oauthAccountNames: [String] {
        accounts.filter { $0.kind == .oauth }.map(\.name).sorted()
    }

    /// Whether the machine-wide login is already saved — what makes "Save
    /// current oauth token" worth offering.
    public var currentLoginIsSaved: Bool {
        accounts.contains(where: \.isCurrentLogin)
    }
}
