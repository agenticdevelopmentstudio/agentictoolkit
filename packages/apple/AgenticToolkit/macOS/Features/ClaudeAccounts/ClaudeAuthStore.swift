import AgenticToolkitCore
import AppKit
import Combine
import Foundation
import os

/// The app's view of the Claude accounts it has saved, and the one place that
/// changes them.
///
/// **The Keychain is the store.** The app's own saved accounts are read and
/// written in-process (`ClaudeKeychain`); Claude Code's login item goes through
/// `security(1)`, exactly as `claude` reaches it, because an in-process access
/// to that item asks for the password on every call and "Always Allow" cannot
/// make it stop (`ClaudeCodeKeychainItem` has the why).
///
/// Two questions still belong to `claude` itself and are still asked of it:
/// whether a login is live at all (`claude auth status`), and the interactive
/// login and logout flows. Those are Claude Code's own business, not a
/// credential read.
///
/// A singleton because the things that need it are scattered across the app and
/// must agree: the settings panel, both Claude menus, and the quotas window's
/// gear popover all draw the same list, and all three would otherwise each run
/// their own `list --json`.
///
/// What is the host app's to decide — where saves go, whether logins autosave,
/// holding background rounds during a switch, and renewing the target login —
/// it asks of the `ClaudeAuthStoreDelegate` handed to `start(delegate:)`.
@MainActor
public final class ClaudeAuthStore {

    public static let shared = ClaudeAuthStore()

    /// Every saved account, from both keychains, plus who is logged in.
    public private(set) var listing: ClaudeAccountListing = .empty
    /// Whether `listing` has been read at all. Before the first reload lands it
    /// is `.empty` because nothing has looked, not because there is nothing —
    /// and the quotas window must not tell anyone to go and add an account on
    /// the strength of a list nobody has read yet.
    public private(set) var hasListed = false
    /// Whether `claude` reports a live login at all — the one question
    /// `~/.claude.json` cannot answer, since it keeps naming the last account
    /// after a logout. Gates the Logout controls.
    public private(set) var isLoggedIn = false
    /// The identity `~/.claude.json` names, refreshed by the watcher.
    public private(set) var identity = ClaudeLoginIdentity()
    /// What went wrong in the last operation, for a panel to show.
    public private(set) var lastError: String?
    /// An operation is in flight; the panel disables its buttons on this.
    public var isBusy: Bool { busyCount > 0 }
    /// Operations in flight. A count, not a flag: an autosave can start and
    /// finish in the middle of a switch, and a flag it cleared would report the
    /// switch done while it was still writing.
    private var busyCount = 0

    /// Where the next save goes. Reads always span both keychains, so this
    /// governs new writes and nothing the user can already see.
    public var location: ClaudeKeychainLocation {
        host.saveLocation
    }

    /// Fires whenever any of the above changed. A view subscribes to it with
    /// Combine.
    public let changes = PassthroughSubject<Void, Never>()
    /// Fires with the new identity the moment the machine-wide login becomes
    /// someone else — the one change a view ordering accounts by "who is logged
    /// in" has to hear about, and which `changes` (busy flags, errors, reloads)
    /// would bury.
    public let identityChanges = PassthroughSubject<ClaudeLoginIdentity, Never>()

    /// A machine-wide login is expected shortly, because the user chose Login
    /// from the Auth menu. The watcher then offers to save the credentials it
    /// sees arrive, which an ambient identity change must not do.
    private var isAwaitingLogin = false
    private var watcher: Timer?
    private var lastConfigWrite: Date?
    private var lastSeenIdentity = ClaudeLoginIdentity()
    private var delegate: (any ClaudeAuthStoreDelegate)?

    private init() {}

    /// The delegate, which `start(delegate:)` must have installed: a store
    /// asked to save or switch before the app said how is a launch-order bug.
    private var host: any ClaudeAuthStoreDelegate {
        guard let delegate else {
            preconditionFailure("ClaudeAuthStore.start(delegate:) must run before the store is used")
        }
        return delegate
    }

    // MARK: - Lifecycle

    /// Begins watching `~/.claude.json` and loads the first listing. Safe to
    /// call more than once; the store keeps the first delegate.
    public func start(delegate: any ClaudeAuthStoreDelegate) {
        guard watcher == nil else { return }
        self.delegate = delegate
        lastSeenIdentity = ClaudeLoginIdentity.current()
        identity = lastSeenIdentity
        lastConfigWrite = ClaudeLoginIdentity.configModified()
        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            MainActor.assumeIsolated { ClaudeAuthStore.shared.tick() }
        }
        timer.tolerance = 1.0
        watcher = timer
        Task { await reload() }
    }

    /// One watcher tick. The mtime is checked first because `~/.claude.json` is
    /// most of a megabyte and `claude` rewrites it wholesale — parsing it every
    /// three seconds to learn nothing would be the whole cost of this feature.
    private func tick() {
        let written = ClaudeLoginIdentity.configModified()
        guard written != lastConfigWrite else { return }
        lastConfigWrite = written
        noticeIdentity(ClaudeLoginIdentity.current())
    }

    /// Acts on `current` if it is a different login from the last one seen —
    /// from the watcher, or from a reload after this app switched accounts
    /// itself, which must reorder everything at once rather than wait for a tick
    /// that would then find nothing new.
    private func noticeIdentity(_ current: ClaudeLoginIdentity) {
        identity = current
        guard current != lastSeenIdentity else { return }
        let previous = lastSeenIdentity
        lastSeenIdentity = current
        changes.send()
        identityChanges.send(current)
        Task { await loginChanged(from: previous, to: current) }
    }

    /// The machine-wide login became someone else.
    ///
    /// Autosave is deliberately unconditional about *how* the change happened:
    /// a `/login` in a terminal, an `oauth switch` from this app, someone else's
    /// script — all of them leave a credential in the Keychain that exists
    /// nowhere else until it is captured, and the point of the setting is that
    /// the user stops having to notice. `oauth save` is idempotent for a login
    /// already filed under that name, so the switch case costs a no-op.
    private func loginChanged(from previous: ClaudeLoginIdentity, to current: ClaudeLoginIdentity) async {
        await reload()
        guard !current.isEmpty else { return }
        let wasAwaited = isAwaitingLogin
        isAwaitingLogin = false
        if host.autoSavesLogins {
            await saveCurrentLogin(silentIfAlreadySaved: true)
            return
        }
        guard wasAwaited || previous.isEmpty else { return }
        // A login the user asked for, with autosave off: offer to keep it,
        // because the credential now in the Keychain is replaced by the next
        // login and recoverable after that by nothing short of a browser flow.
        guard !listing.currentLoginIsSaved else { return }
        let save = ClaudeAuthPrompts.confirmSaveLogin(named: current.displayName)
        if save { await saveCurrentLogin(silentIfAlreadySaved: false) }
    }

    // MARK: - Reading

    /// Re-reads both keychains and the login state.
    ///
    /// This reads only the app's OWN keychain items, never Claude Code's:
    /// drawing a list of accounts has no use for a credential. Who is logged in
    /// comes from `~/.claude.json`, which is a file read. (Claude Code's item is
    /// read on each publisher round, through `security(1)` so it never prompts —
    /// see the app's `holdingCredentialRounds`.)
    ///
    /// A login that changed since the last look is announced from here too, so
    /// an in-app switch reorders every view the moment its reload lands.
    public func reload() async {
        do {
            let located = try await ClaudeAccountKeychainStore.all()
            let current = ClaudeLoginIdentity.current()
            listing = ClaudeAccountListing(
                accounts: located.map {
                    ClaudeAccountRecord($0, isCurrentLogin: $0.account.isLogin(of: current))
                },
                currentLogin: .init(email: current.email, uuid: current.uuid))
            lastError = nil
        } catch {
            listing = .empty
            lastError = error.localizedDescription
        }
        hasListed = true
        isLoggedIn = await readLoginState()
        lastConfigWrite = ClaudeLoginIdentity.configModified()
        noticeIdentity(ClaudeLoginIdentity.current())
        // The saved account matching the login, not the login's email: the two
        // are usually the same string and occasionally are not, and it is the
        // saved *name* the menus draw a checkmark beside.
        let currentName = listing.accounts.first(where: { $0.isCurrentLogin })?.name
        ClaudeAuthSnapshot.publish(ClaudeAuthSnapshot(
            oauthAccountNames: listing.oauthAccountNames,
            currentAccountName: currentName ?? identity.displayName,
            isLoggedIn: isLoggedIn))
        changes.send()
    }

    /// `claude auth status --json` — the only cheap, read-only answer to "is
    /// there a login at all". `~/.claude.json` goes on naming the last account
    /// after a logout, so it cannot be asked this.
    private func readLoginState() async -> Bool {
        guard let output = try? await ClaudeAuthCLI.claude(["auth", "status", "--json"], timeout: 30),
              let json = try? JSONSerialization.jsonObject(with: Data(output.stdout.utf8))
                as? [String: Any]
        else { return false }
        return json["loggedIn"] as? Bool ?? false
    }

    /// The token stored in one keychain item, fetched only when someone asks to
    /// see or copy it. The table's own read never carries a secret.
    ///
    /// Addressed by item rather than by account name, because a name can have
    /// both a login and a setup token saved under it and the eye button is on
    /// one row, not on the name.
    public func revealToken(forItem itemKey: String) async -> String? {
        do {
            return try await ClaudeAccountKeychainStore.find(itemKey: itemKey)?
                .account.revealableToken
        } catch {
            lastError = error.localizedDescription
            changes.send()
            return nil
        }
    }

    // MARK: - Writing

    /// Stores a long-lived token the user pasted, under `name`.
    ///
    /// Its own record, never merged with a login saved under the same name: the
    /// two bill against different rate-limit buckets, so folding them together
    /// would mean one row and one usage number for two different measurements.
    /// A setup token already saved for this name is replaced — that is the same
    /// credential being re-pasted.
    @discardableResult
    public func saveLongLivedToken(name: String, token: String) async -> Bool {
        let current = identity
        return await perform { [location] in
            var account = try await ClaudeAccountKeychainStore
                .find(name: name, kind: .longLived)?.account
                ?? ClaudeSavedAccount(name: name, kind: .longLived)
            account.longLivedToken = token
            if account.identity.isEmpty, current.displayName == name {
                account.identity = current.email
                account.accountUUID = current.uuid
            }
            try await ClaudeAccountKeychainStore.save(account, to: location)
        }
    }

    /// Copies the machine-wide login into the app's store, under the name
    /// the account itself reports.
    ///
    /// It opens Claude Code's own keychain item, through `security(1)`, so no
    /// permission dialog appears.
    ///
    /// Saved as a login record and nothing else. A setup token stored under the
    /// same name is a separate record and is left exactly as it was.
    @discardableResult
    public func saveCurrentLogin(silentIfAlreadySaved: Bool) async -> Bool {
        if silentIfAlreadySaved && listing.currentLoginIsSaved { return true }
        let current = identity
        return await perform { [location] in
            guard let oauth = try await ClaudeAccountKeychainStore.currentLogin() else {
                throw ClaudeCredentialBlobError.noLogin
            }
            let name = current.displayName.isEmpty ? NSUserName() : current.displayName
            var account = try await ClaudeAccountKeychainStore
                .find(name: name, kind: .oauth)?.account
                ?? ClaudeSavedAccount(name: name, kind: .oauth)
            account.oauth = oauth
            account.identity = current.email
            account.accountUUID = current.uuid
            account.configAccount = ClaudeLoginIdentity.currentAccountBlock()
            try await ClaudeAccountKeychainStore.save(account, to: location)
        }
    }

    /// Moves a saved account into the other keychain.
    ///
    /// One `save`, not a hand-rolled read/write/delete: `save(_:to:)` already
    /// writes the account to the location asked for and then drops it from the
    /// other, in that order — so a move that fails halfway leaves the credential
    /// where it was rather than nowhere. Doing it here a second way would be a
    /// second answer to "how does an account change keychains".
    ///
    /// The account is re-read rather than rebuilt from the record the table
    /// drew: a `ClaudeAccountRecord` is a display view that carries no secret,
    /// and writing one back would move an account by emptying it.
    @discardableResult
    public func move(_ record: ClaudeAccountRecord, to location: ClaudeKeychainLocation) async -> Bool {
        guard record.location != location else { return true }
        return await perform {
            guard let located = try await ClaudeAccountKeychainStore
                .find(itemKey: record.itemKey)
            else { throw ClaudeAuthStoreError.noSavedAccount(record.name) }
            try await ClaudeAccountKeychainStore.save(located.account, to: location)
        }
    }

    /// Drops one saved credential, from whichever keychain it is in. The other
    /// kind saved under the same name stays, and it never touches the credential
    /// Claude Code itself is using.
    @discardableResult
    public func forget(_ record: ClaudeAccountRecord) async -> Bool {
        await perform {
            try await ClaudeAccountKeychainStore.delete(itemKey: record.itemKey)
        }
    }

    /// Installs saved account `name` as the machine-wide login.
    ///
    /// Two writes, because a login is two things: the credential goes into
    /// Claude Code's keychain item (edited in place, so the MCP-server
    /// authorizations beside it survive), and the account's profile block goes
    /// back into `~/.claude.json`, so every reader of "who is logged in" — this
    /// app, the status line, `claude` itself — agrees immediately rather than at
    /// the next `claude` run. The two land together or not at all
    /// (`switchLiveLogin`).
    ///
    /// In order:
    /// 1. **Refused outright** while another switch is running — two switches
    ///    interleaving their keychain writes leave one account's credential under
    ///    the other's identity — and a no-op for the account already logged in.
    /// 2. **The target is renewed** by the delegate (`renewed(_:)`), which proves
    ///    its refresh token is alive before anything is overwritten.
    /// 3. **The outgoing login is filed, then the target installed**, from one
    ///    read of Claude Code's item. Installing overwrites that item, which holds
    ///    the only copy of the outgoing account's current refresh token — Claude
    ///    Code has been refreshing it since the account was saved — so a failure
    ///    to file it stops the switch ("login expired" on the way back, 2.159.2).
    ///
    /// No publisher round runs meanwhile: one could be refreshing the very login
    /// this switch is renewing, and a refresh token spent twice leaves one side
    /// holding a dead login.
    @discardableResult
    public func switchTo(account name: String) async -> Bool {
        guard !isBusy else {
            lastError = "Another account change is still finishing — try again in a moment."
            changes.send()
            return false
        }
        return await perform {
            try await host.holdingCredentialRounds {
                let located = try await ClaudeAccountKeychainStore.all()
                guard let target = located.first(where: {
                          $0.account.name == name && $0.account.kind == .oauth
                      }), target.account.oauth != nil
                else { throw ClaudeAuthStoreError.noSavedLogin(name) }
                // Read now, not from `identity`: the watcher may not have ticked
                // since `claude` last changed the login.
                let outgoing = ClaudeLoginIdentity.current()
                if target.account.isLogin(of: outgoing) { return }
                // Without its profile block, `~/.claude.json` would go on naming
                // the outgoing account over this one's credential, and the next
                // round would file this login under that account's record.
                guard let block = target.account.configAccount else {
                    throw ClaudeAuthStoreError.noSavedProfile(name)
                }
                let oauth = try await renewed(target)
                try await ClaudeAccountKeychainStore.switchLiveLogin(
                    from: outgoing, in: located, to: oauth, accountBlock: block)
            }
        }
    }

    /// `target`'s login renewed by the delegate and stored back into its saved
    /// record — or the saved login as it is, when the attempt certainly left it
    /// untouched.
    ///
    /// Renewing gives `claude` a full eight hours instead of whatever was left of
    /// the saved access token, and it tests the refresh token before installing
    /// rather than after: a spent one throws here, and the switch stops with the
    /// current login still in place, instead of `claude` reporting "login expired"
    /// on its next request.
    ///
    /// The saved pair is installed unrenewed only when the refresh token is known
    /// to be unspent — a rate limit, a request that never left the Mac, a renewer
    /// that could not be reached or is too old to renew. A timeout or a 5xx may
    /// have rotated it server-side and lost the answer, and installing the old
    /// pair then would hand `claude` a dead login; the switch stops instead.
    ///
    /// A fresh pair is stored before it is returned, because the renewer has
    /// already voided the saved one. If that store fails the pair is still
    /// returned: installed, it lives on in Claude Code's item, and the next round
    /// files it back into the record.
    private func renewed(
        _ target: ClaudeAccountKeychainStore.Located
    ) async throws -> ClaudeOAuthCredential {
        let name = target.account.name
        guard let saved = target.account.oauth else { throw ClaudeAuthStoreError.noSavedLogin(name) }
        switch await host.renewLogin(saved) {
        case .unreached:
            Self.logger.error("accounts: renewer unreachable; installing \(name, privacy: .public) as saved")
            return saved
        case .lost(let reason):
            throw ClaudeAuthStoreError.renewalUncertain(name, reason)
        case .refreshed(let fresh):
            guard let fresh else {
                throw ClaudeAuthStoreError.renewalUncertain(name, "the renewal came back with no login")
            }
            var account = target.account
            account.oauth = fresh
            do {
                try await ClaudeAccountKeychainStore.save(account, to: target.location)
            } catch {
                Self.logger.error("""
                    accounts: renewed \(name, privacy: .public) but couldn't store it \
                    (\(error.localizedDescription, privacy: .public)); installing it anyway
                    """)
            }
            return fresh
        case .spent:
            throw ClaudeAuthStoreError.savedLoginSpent(name)
        case .failed(let reason, let leftTokenUntouched):
            guard leftTokenUntouched else {
                throw ClaudeAuthStoreError.renewalUncertain(name, reason)
            }
            Self.logger.error("""
                accounts: couldn't renew \(name, privacy: .public) \
                (\(reason, privacy: .public)); installing it as saved
                """)
            return saved
        }
    }

    /// Logs Claude Code out machine-wide.
    @discardableResult
    public func logout() async -> Bool {
        await perform { try await ClaudeAuthCLI.claude(["auth", "logout"]) }
    }

    /// Mints a long-lived token via `claude setup-token` and returns it,
    /// unsaved — the caller shows it, and saves it when the user dismisses.
    public func mintLongLivedToken() async -> String? {
        busyCount += 1
        changes.send()
        defer {
            busyCount -= 1
            changes.send()
        }
        do {
            return try await ClaudeSetupTokenMinter.mint()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Opens a terminal running `claude auth login`, and arms the watcher to
    /// offer to save whatever login comes back.
    ///
    /// A terminal and not a subprocess: the flow is interactive, and its output
    /// is a browser handshake the user has to see. The watcher is how the app
    /// learns it finished — there is no process here to await.
    public func beginLogin() {
        isAwaitingLogin = true
        do {
            guard let binary = ClaudeAuthCLI.claudeBinary() else {
                throw ClaudeAuthCLI.CLIError.binaryNotFound("claude")
            }
            // The absolute path, because a `.command` file runs under `sh` with
            // the system PATH and never sees the user's ~/.local/bin.
            try ClaudeAuthTerminal.run(command: "\(binary) auth login")
        } catch {
            isAwaitingLogin = false
            lastError = error.localizedDescription
            changes.send()
        }
    }

    /// Runs one mutation, reloading afterwards either way — a failed `oauth
    /// switch` still leaves a store worth re-reading, and a stale panel after a
    /// refusal is how a user deletes the wrong row next.
    private func perform(_ body: () async throws -> Void) async -> Bool {
        busyCount += 1
        lastError = nil
        changes.send()
        var succeeded = true
        do {
            try await body()
        } catch {
            lastError = error.localizedDescription
            succeeded = false
        }
        busyCount -= 1
        let failure = lastError
        await reload()
        // The reload is a fresh read, and it reports its own health — including
        // clearing `lastError` when it goes well. Left alone, a successful read
        // after a refused mutation erased the refusal before anything could
        // draw it, which is a mutation that silently does nothing.
        if let failure {
            lastError = failure
            changes.send()
        }
        return succeeded
    }
}

public enum ClaudeAuthStoreError: Error, LocalizedError {

    case noSavedLogin(String)
    case noSavedAccount(String)
    case savedLoginSpent(String)
    case noSavedProfile(String)
    case renewalUncertain(String, String)

    public var errorDescription: String? {
        switch self {
        case .noSavedProfile(let name):
            return "“\(name)” was saved without its Claude Code profile, so switching to it "
                + "would leave Claude Code naming the wrong account. Log in as \(name) with "
                + "`claude` once to save it again; you're still logged in as before."
        case .renewalUncertain(let name, let reason):
            return "Couldn't confirm the saved login for “\(name)” still works (\(reason)). "
                + "You're still logged in as before — try the switch again."
        case .savedLoginSpent(let name):
            return "The saved login for “\(name)” no longer works — it was signed out or "
                + "refreshed elsewhere. Log in as \(name) with `claude` to save it again; "
                + "you're still logged in as before."
        case .noSavedLogin(let name):
            return "“\(name)” has no saved login to switch to — only a long-lived "
                + "token, which bills against the account but can't sign this Mac in as it."
        case .noSavedAccount(let name):
            return "“\(name)” isn't in either keychain any more, so there was nothing to "
                + "move. It may have been deleted on this Mac or on another one."
        }
    }
}

/// What the menus need from `ClaudeAuthStore`, readable from anywhere.
///
/// `MenuSection.items(snapshot:)` is `nonisolated` and `Sendable`, so the
/// global menu builds its items outside the main actor and cannot ask a
/// `@MainActor` store anything. This is the small, immutable answer the store
/// publishes on every reload for it — no menu ever runs a CLI to draw itself.
public struct ClaudeAuthSnapshot: Sendable, Equatable {

    public var oauthAccountNames: [String] = []
    /// The account `~/.claude.json` names, for the checkmark in the menu.
    public var currentAccountName: String = ""
    public var isLoggedIn = false

    private static let box = Box()

    public static var current: ClaudeAuthSnapshot { box.value }

    public static func publish(_ snapshot: ClaudeAuthSnapshot) { box.value = snapshot }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = ClaudeAuthSnapshot()
        var value: ClaudeAuthSnapshot {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
}

extension ClaudeAuthStore: Loggable {
    public static nonisolated let logger = makeLogger()
}
