import AgenticToolkitCore
import Foundation

/// Who Claude Code itself is logged in as, read from `~/.claude.json`'s
/// `oauthAccount` block — the machine-wide identity every `claude` runs as
/// unless that terminal carries a credential of its own in its environment.
///
/// This file is the app's single answer to "which account is current", shared
/// by the quotas window (which draws the person icon beside it), the auth
/// panel (which prepopulates a name with it and marks the saved copy of it) and
/// the autosave watcher (which acts when it *changes*). It is read rather than
/// remembered because the block is Claude Code's own answer to the question,
/// and a copy kept here would be a label that can fall out of date.
///
/// Deliberately a *file* read and not `claude auth status`: this is called on
/// every quota redraw and every watcher tick, and spawning a process for it
/// would put a subprocess on a drawing path. `ClaudeAuthStore` runs the CLI
/// once per reload for the things only it can answer (whether the login is
/// live at all), and this for the identity.
public struct ClaudeLoginIdentity: Sendable, Equatable {

    /// The logged-in account's email, or "" when `~/.claude.json` names none.
    public var email: String = ""
    /// The account uuid, which outlives an email change and is what the OAuth
    /// store matches on first.
    public var uuid: String = ""

    public var isEmpty: Bool { email.isEmpty && uuid.isEmpty }

    /// The best name to show for this identity — the email, falling back to the
    /// uuid, which is what a saved login is filed under when the email is
    /// missing.
    public var displayName: String { email.isEmpty ? uuid : email }

    public static let configURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")

    /// The identity `~/.claude.json` currently names. An unreadable or
    /// unparseable file is an empty identity, never a crash: this is read on
    /// drawing paths, and a half-written config (claude rewrites the file
    /// wholesale) must degrade to "unknown" for one tick rather than take a
    /// window down.
    public nonisolated static func current() -> ClaudeLoginIdentity {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any]
        else { return ClaudeLoginIdentity() }
        return ClaudeLoginIdentity(
            email: account["emailAddress"] as? String ?? "",
            uuid: account["accountUuid"] as? String ?? ""
        )
    }

    /// When `~/.claude.json` was last written — the cheap half of the watcher's
    /// tick, so an 800KB file is parsed only when it has actually changed.
    public nonisolated static func configModified() -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: configURL.path)
        return attributes?[.modificationDate] as? Date
    }

    /// The whole `oauthAccount` block, serialized, for storing alongside a saved
    /// login.
    ///
    /// The block is twenty-odd fields — organization, billing type, seat tier,
    /// onboarding flags — and only two of them are the identity. Rotating an
    /// account by editing `emailAddress` and `accountUuid` in place would leave
    /// the *previous* account's organization and plan attached to the new one,
    /// so the block travels whole and is restored whole.
    public nonisolated static func currentAccountBlock() -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"],
              let encoded = try? JSONSerialization.data(withJSONObject: account, options: [.sortedKeys])
        else { return nil }
        return String(bytes: encoded, encoding: .utf8)
    }

    /// Puts `block` back into `~/.claude.json` as the logged-in account,
    /// leaving every other key in the file untouched.
    ///
    /// `~/.claude.json` is the user's whole Claude Code state — project history,
    /// MCP servers, onboarding — so this reads, edits one key, and writes back,
    /// keeping a backup (`ClaudeAccountsConfiguration.backupExtension`) beside it. The write is atomic because
    /// `claude` may be reading the file at any moment, and a half-written config
    /// is one it starts from scratch with.
    public nonisolated static func installAccountBlock(_ block: String) throws {
        let data = try Data(contentsOf: configURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = try JSONSerialization.jsonObject(with: Data(block.utf8))
                as? [String: Any]
        else { throw ConfigError.unreadable }
        root["oauthAccount"] = account

        let backup = configURL.appendingPathExtension(ClaudeAccounts.configuration.backupExtension)
        try? FileManager.default.removeItem(at: backup)
        try? data.write(to: backup)

        let updated = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try updated.write(to: configURL, options: .atomic)
    }

    public enum ConfigError: Error, LocalizedError {
        case unreadable

        public var errorDescription: String? {
            "Couldn't read ~/.claude.json — Claude Code's own settings file isn't "
                + "in the format \(ClaudeAccounts.appName) expects."
        }
    }
}
