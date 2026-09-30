import AgenticToolkitCore
import Foundation
import Security

/// Where a saved credential is kept.
///
/// The two cases are two different keychains, not two folders in one:
///
/// - `.login` is the **file-based login keychain** — the same one `claude`,
///   `security(1)` and Keychain Access work in. Items there are guarded by an
///   ACL, which is what makes macOS put up *"the app wants to use your
///   confidential information…"* the first time this app reads one. That prompt
///   is the permission grant, and it names the app, so the user always knows
///   who asked.
/// - `.shared` is the **data-protection keychain with `kSecAttrSynchronizable`
///   set** — iCloud Keychain. Apple's own sync machinery copies those items to
///   every Mac signed into the same Apple Account, so a second machine running
///   The app finds the accounts already there. It is guarded by the app's
///   keychain access group rather than by an ACL, so it needs the
///   `keychain-access-groups` entitlement and a provisioning profile that grants
///   it — see the app's entitlements.
public enum ClaudeKeychainLocation: String, CaseIterable, Sendable, Codable {

    case login
    case shared

    /// What the storage popup calls it — and what the details pane calls the
    /// keychain a saved account actually turned out to be in.
    ///
    /// Named for the *consequence* rather than for the API: "login keychain"
    /// and "data-protection keychain" are the true names and tell the user
    /// nothing about the only thing they are choosing between, which is whether
    /// a credential leaves this Mac.
    public var title: String {
        switch self {
        case .login: return "This Mac only (login keychain)"
        case .shared: return "All my Macs (iCloud Keychain)"
        }
    }
}

/// Reading and writing the Keychain directly, with `SecItem*`.
///
/// **This is the door to the app's OWN items — nothing here shells out.**
/// Items this app creates carry its team in their partition list and its
/// identity in their ACL, so an in-process call reaches them without a dialog.
/// Claude Code's login item is the opposite case and never comes through here:
/// see `ClaudeCodeKeychainItem` for why it has to go through `security(1)`.
///
/// Every entry point is `nonisolated` and hops to a utility queue, because a
/// `SecItem*` call can put up a modal dialog and block until it is answered.
public enum ClaudeKeychain {

    /// The app's own saved accounts — one keychain item per account, named
    /// by the account, holding a `ClaudeSavedAccount` as JSON.
    public static var savedAccountsService: String { ClaudeAccounts.configuration.savedAccountsService }

    // MARK: - Errors

    public struct KeychainError: Error, LocalizedError, Sendable {

        public let status: OSStatus
        public let operation: String
        public let location: ClaudeKeychainLocation?

        public var errorDescription: String? {
            let detail = (SecCopyErrorMessageString(status, nil) as String?)
                ?? "OSStatus \(status)"
            if status == errSecMissingEntitlement, location == .shared {
                return "iCloud Keychain isn't available to this build of \(ClaudeAccounts.appName). "
                    + "Storing tokens on all your Macs needs the Keychain Sharing "
                    + "entitlement, which is granted by the provisioning profile the app "
                    + "was signed with. Switch storage back to this Mac, or rebuild "
                    + "\(ClaudeAccounts.appName) with a profile from your developer team."
            }
            if status == errSecUserCanceled || status == errSecAuthFailed {
                return "You didn't allow \(ClaudeAccounts.appName) to use the keychain, so \(operation) "
                    + "didn't happen. Try again and choose Allow — or Always Allow, to stop "
                    + "being asked."
            }
            return "Couldn't \(operation): \(detail)"
        }

        /// The user said no, rather than anything being broken. Worth telling
        /// apart: a refusal is a decision, and re-reporting it as a fault is
        /// how an app nags.
        public var isRefusal: Bool {
            status == errSecUserCanceled || status == errSecAuthFailed
        }
    }

    // MARK: - Queries

    /// The attributes that *identify* one item — the same dictionary for a
    /// read, a write and a delete, so the three can never disagree about which
    /// item they mean.
    private static func query(
        service: String, account: String?, location: ClaudeKeychainLocation
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let account { query[kSecAttrAccount as String] = account }
        switch location {
        case .login:
            // Legacy, file-based, ACL-guarded. `false` rather than absent: an
            // absent `synchronizable` matches BOTH kinds, and a delete that
            // matched both would take the iCloud copy with it.
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        case .shared:
            query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
            query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        }
        return query
    }

    // MARK: - Reading

    /// The bytes stored for one item, or nil when there is no such item.
    ///
    /// A missing item is **not** an error: "this account isn't saved" is an
    /// ordinary answer, and making the caller pattern-match an `OSStatus` to
    /// learn it would put a Security-framework constant in the UI layer.
    public static func read(
        service: String, account: String, location: ClaudeKeychainLocation
    ) async throws -> Data? {
        try await off {
            var lookup = query(service: service, account: account, location: location)
            lookup[kSecReturnData as String] = kCFBooleanTrue
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else {
                throw KeychainError(
                    status: status, operation: "read “\(account)” from the keychain",
                    location: location)
            }
            return item as? Data
        }
    }

    /// Every item this app stores under `service`, as (account, bytes) pairs.
    ///
    /// Two steps, and the split is forced: the **legacy login keychain refuses
    /// `kSecReturnData` together with `kSecMatchLimitAll`** outright, with
    /// `errSecParam` — "one or more parameters passed to a function were not
    /// valid" — so the obvious single query that asks for every item's bytes at
    /// once cannot work there. It enumerates names first, then fetches each
    /// item's bytes by name.
    ///
    /// Doing it per item is safe *here* and would not be everywhere: these are
    /// items the app wrote itself, so their ACL already trusts it and no
    /// dialog appears. The item Claude Code owns is a different matter, and is
    /// never read here at all — see `ClaudeCodeKeychainItem`.
    ///
    /// The whole batch runs inside one `off` hop rather than one per item, so a
    /// panel listing ten accounts still crosses to the background queue once.
    public static func readAll(
        service: String, location: ClaudeKeychainLocation
    ) async throws -> [(account: String, data: Data)] {
        try await off {
            var lookup = query(service: service, account: nil, location: location)
            lookup[kSecReturnAttributes as String] = kCFBooleanTrue
            lookup[kSecMatchLimit as String] = kSecMatchLimitAll

            var items: CFTypeRef?
            let status = SecItemCopyMatching(lookup as CFDictionary, &items)
            if status == errSecItemNotFound { return [] }
            guard status == errSecSuccess else {
                throw KeychainError(
                    status: status, operation: "read the saved accounts",
                    location: location)
            }
            let names = (items as? [[String: Any]] ?? []).compactMap {
                $0[kSecAttrAccount as String] as? String
            }

            return try names.compactMap { account in
                var one = query(service: service, account: account, location: location)
                one[kSecReturnData as String] = kCFBooleanTrue
                one[kSecMatchLimit as String] = kSecMatchLimitOne

                var value: CFTypeRef?
                let found = SecItemCopyMatching(one as CFDictionary, &value)
                // Deleted between the two calls: the account simply isn't there
                // any more, which is the same answer the enumeration would have
                // given a moment later.
                if found == errSecItemNotFound { return nil }
                guard found == errSecSuccess, let data = value as? Data else {
                    throw KeychainError(
                        status: found, operation: "read “\(account)” from the keychain",
                        location: location)
                }
                return (account: account, data: data)
            }
        }
    }

    // MARK: - Writing

    /// Stores `data`, replacing whatever was there.
    ///
    /// An existing item is **updated**, never deleted and re-added. That is the
    /// whole difference between this and `security add-generic-password`
    /// without `-U`: an update keeps the item's ACL, so every program already
    /// trusted with it — `claude` above all — goes on reading it without a
    /// prompt. Delete-then-add mints a fresh ACL trusting only the writer, and
    /// the next reader stops to ask for permission it used to have.
    public static func write(
        service: String, account: String, location: ClaudeKeychainLocation,
        label: String, data: Data
    ) async throws {
        try await off {
            let identity = query(service: service, account: account, location: location)
            // The label rides along on the update as well as on the create. It is
            // what the permission dialog and Keychain Access call the item, and an
            // item created before this app named its prompts would otherwise keep
            // the old wording for as long as it is never recreated.
            let changes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrLabel as String: label
            ]
            let updated = SecItemUpdate(identity as CFDictionary, changes as CFDictionary)
            if updated == errSecSuccess { return }
            guard updated == errSecItemNotFound else {
                throw KeychainError(
                    status: updated, operation: "update “\(account)” in the keychain",
                    location: location)
            }

            var insert = identity
            insert[kSecValueData as String] = data
            insert[kSecAttrLabel as String] = label
            // Readable while the machine is locked but after the first unlock:
            // the daemon and the widget refresh on a schedule, and an item that
            // needs the screen unlocked would simply be missing on a Mac left
            // running at a login window.
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(insert as CFDictionary, nil)
            guard added == errSecSuccess else {
                throw KeychainError(
                    status: added, operation: "save “\(account)” to the keychain",
                    location: location)
            }
        }
    }

    /// Removes one item. A missing item is a success — the caller asked for it
    /// to be gone, and it is.
    public static func delete(
        service: String, account: String, location: ClaudeKeychainLocation
    ) async throws {
        try await off {
            let status = SecItemDelete(
                query(service: service, account: account, location: location) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(
                    status: status, operation: "delete “\(account)” from the keychain",
                    location: location)
            }
        }
    }

    // MARK: - Availability

    /// Whether this build can actually use `location`, asked without writing
    /// anything the user did not ask for.
    ///
    /// A read against a service nothing stores under answers it: `errSecItemNotFound`
    /// means the keychain took the question, `errSecMissingEntitlement` means it
    /// refused to look. That distinction is the whole point — it is how the
    /// panel can grey out iCloud storage instead of offering a switch that
    /// fails the first time it is used.
    public static func isAvailable(_ location: ClaudeKeychainLocation) async -> Bool {
        let probe = ClaudeAccounts.configuration.availabilityProbeService
        do {
            _ = try await read(service: probe, account: probe, location: location)
            return true
        } catch let error as KeychainError {
            return error.status != errSecMissingEntitlement
        } catch {
            return false
        }
    }

    // MARK: - Plumbing

    /// Runs `body` off the main actor.
    ///
    /// Mandatory rather than tidy: a `SecItem*` call against an ACL-guarded item
    /// can put up the system's permission dialog and block until it is answered,
    /// and blocking the main actor for that means an app frozen behind the very
    /// dialog it is waiting on.
    private static func off<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
