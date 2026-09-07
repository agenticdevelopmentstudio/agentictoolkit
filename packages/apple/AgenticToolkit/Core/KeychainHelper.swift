import Foundation
import Security
import os

/// Provides simple CRUD operations for storing secrets in the macOS Keychain.
/// Uses generic password items scoped to a configurable service identifier.
public enum KeychainHelper {

    /// The Keychain service identifier. Defaults to the main bundle identifier.
    nonisolated(unsafe) public static var service: String = Bundle.main.bundleIdentifier ?? "com.agentictoolkit"

    /// Optional shared Keychain access group. When set, items are scoped to this
    /// group so multiple signed binaries (e.g. an app and its daemon) carrying the
    /// matching `keychain-access-groups` entitlement can share them. `nil` (the
    /// default) preserves the original per-binary behavior.
    nonisolated(unsafe) public static var accessGroup: String?

    /// Service identifiers this app used to write under, newest first.
    ///
    /// The service defaults to the bundle identifier, so changing the bundle
    /// identifier — a rename, a new reverse-DNS prefix — orphans every secret
    /// the app has ever stored. Nothing surfaces: `get` returns `nil` and the
    /// feature behaves as though the user never entered the key. Listing the
    /// retired identifiers here lets `get` find one and re-store it under the
    /// current service, the same shape as the access-group recovery below.
    ///
    /// The legacy item is read and never deleted. It belongs to the old
    /// identity, another install may still be using it, and a secret is not
    /// something to destroy on a guess.
    nonisolated(unsafe) public static var legacyServices: [String] = []

    /// Builds the base generic-password query for an account key. When an access
    /// group is in play, scopes the item to it and forces the macOS data-protection
    /// keychain (required for access groups on macOS).
    static func makeQuery(
        account: String,
        accessGroup: String? = KeychainHelper.accessGroup,
        service: String = KeychainHelper.service
    ) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }

    /// Stores a value in the Keychain for the given account key.
    /// Overwrites any existing value for the same key.
    @discardableResult
    public static func set(_ value: String, forKey key: String) -> Bool {
        let data = Data(value.utf8)
        delete(forKey: key)

        var query = makeQuery(account: key)
        query[kSecValueData as String] = data
        if accessGroup != nil {
            // Data-protection items default to `WhenUnlocked`. A co-signed daemon may
            // run before first unlock or while the screen is locked, so make shared
            // secrets readable after first unlock. `ThisDeviceOnly`: local app↔daemon
            // secrets must never sync to iCloud or migrate off this machine.
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain set failed for '\(key, privacy: .public)': \(status)")
        }
        return status == errSecSuccess
    }

    /// Retrieves a value from the Keychain for the given account key.
    public static func get(forKey key: String) -> String? {
        if let value = copyValue(forKey: key, accessGroup: accessGroup) {
            return value
        }
        // Legacy migration: secrets written before an access group was configured live
        // in the default keychain and are invisible to access-group / data-protection
        // queries (and to a co-signed daemon). Recover one if present and re-store it
        // under the current group so future reads — including the daemon's — succeed.
        if accessGroup != nil, let legacy = copyValue(forKey: key, accessGroup: nil) {
            set(legacy, forKey: key)
            return legacy
        }
        // Retired-service migration: the service defaults to the bundle
        // identifier, so a bundle-identifier change leaves every secret behind
        // under the old one. Recover the newest and re-store it under the
        // current service. The old item is left where it is.
        for legacyService in legacyServices {
            if let legacy = copyValue(forKey: key, accessGroup: accessGroup, service: legacyService)
                ?? (accessGroup != nil
                    ? copyValue(forKey: key, accessGroup: nil, service: legacyService)
                    : nil) {
                logger.info("Recovered '\(key, privacy: .public)' from retired Keychain service")
                set(legacy, forKey: key)
                return legacy
            }
        }
        return nil
    }

    /// Copies the stored string for an account, scoped to the given access group.
    private static func copyValue(
        forKey key: String,
        accessGroup: String?,
        service: String = KeychainHelper.service
    ) -> String? {
        var query = makeQuery(account: key, accessGroup: accessGroup, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain get failed for '\(key, privacy: .public)': \(status)")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    /// Deletes the Keychain item for the given account key.
    @discardableResult
    public static func delete(forKey key: String) -> Bool {
        let query = makeQuery(account: key)

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns whether a value exists in the Keychain for the given key.
    ///
    /// Retired services count. An item `get` would recover is present as far
    /// as any caller is concerned, and answering `false` here would have a
    /// settings pane render an empty field over a stored secret. This probe
    /// does not migrate — the first `get` does that.
    public static func exists(forKey key: String) -> Bool {
        var query = makeQuery(account: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return true
        }
        return legacyServices.contains { legacyService in
            var legacyQuery = makeQuery(account: key, service: legacyService)
            legacyQuery[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(legacyQuery as CFDictionary, nil) == errSecSuccess
        }
    }
}

extension KeychainHelper: Loggable {
    public static nonisolated let logger = makeLogger()
}
