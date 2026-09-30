import AgenticToolkitCore
import Foundation
import os

/// What makes one app's saved Claude accounts that app's own: the name its
/// prompts and keychain items carry, and the identifiers its items and caches
/// are filed under.
///
/// The keychain service is the one value that must never change once an app
/// has shipped: it is how the app finds the accounts it saved last week. A
/// second app that wants to share the same accounts passes the same service.
public struct ClaudeAccountsConfiguration: Sendable, Equatable {

    /// The app's display name, as the permission dialogs and alerts say it.
    public var appName: String
    /// A reverse-DNS name for the app's own files — the availability probe's
    /// keychain service and the Caches directory the login script lives in.
    public var identifier: String
    /// The keychain service every saved account is stored under.
    public var savedAccountsService: String

    public init(appName: String, identifier: String, savedAccountsService: String? = nil) {
        self.appName = appName
        self.identifier = identifier
        self.savedAccountsService = savedAccountsService ?? "\(appName) Claude Accounts"
    }

    /// A service nothing stores under, read to learn whether a keychain is
    /// usable at all (`ClaudeKeychain.isAvailable`).
    public var availabilityProbeService: String { "\(identifier).availability-probe" }

    /// The extension of the copy of `~/.claude.json` kept beside it before an
    /// account switch rewrites it.
    public var backupExtension: String { "\(appName.lowercased())-backup" }

    /// What Keychain Access and the permission dialog call a saved account.
    public func itemLabel(name: String, kind: ClaudeCredentialKind) -> String {
        "\(appName) — \(name) (\(kind.title))"
    }
}

/// The process-wide `ClaudeAccountsConfiguration`.
///
/// Set once, at launch, before anything reads a saved account. Global rather
/// than passed down because the keychain helpers are static entry points
/// called from every layer, and threading one value through all of them would
/// put it in every signature for a fact that never changes while the app runs.
public enum ClaudeAccounts {

    private static let stored = OSAllocatedUnfairLock<ClaudeAccountsConfiguration?>(initialState: nil)

    /// Installs the configuration. Call it before the first keychain access.
    public static func configure(_ configuration: ClaudeAccountsConfiguration) {
        stored.withLock { $0 = configuration }
    }

    /// The installed configuration. Reading it before `configure(_:)` is a
    /// programming error, and fails immediately rather than filing accounts
    /// under a made-up name the app will never look for again.
    public static var configuration: ClaudeAccountsConfiguration {
        guard let configuration = stored.withLock({ $0 }) else {
            preconditionFailure("ClaudeAccounts.configure(_:) must run before any saved-account access")
        }
        return configuration
    }

    /// `configuration.appName`, for the messages that say it.
    public static var appName: String { configuration.appName }
}
