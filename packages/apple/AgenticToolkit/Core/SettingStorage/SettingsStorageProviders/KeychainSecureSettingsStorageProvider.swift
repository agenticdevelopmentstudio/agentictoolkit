//
//  KeychainSecureSettingsStorageProvider.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/27/26.
//
import Foundation
import Combine
import os

/// A `SecureSettingsStorageProvider` backed by the macOS Keychain via `KeychainHelper`.
///
/// Values are JSON-encoded and stored as a UTF-8 String in the Keychain.
/// `String`-typed values take a fast path that stores the raw string (no JSON quoting)
/// to keep keychain entries human-readable for cases like API keys.
///
/// Reads are memoized. Every `get` is a synchronous XPC round-trip to `securityd`,
/// and a *miss* is the expensive case: `KeychainHelper.get` tries the access-group
/// query, then the legacy no-group query, then both variants of every retired
/// service. Callers resolve settings in bulk — `AIProviderConfigStore.configValues`
/// builds a fresh `UserSetting` per field and `UserSetting.init` reads storage in its
/// initializer — so resolving a handful of AI configurations costs dozens of
/// round-trips on the main thread. Repeat that per daemon reconnect and the app sits
/// pinned above 100% CPU inside `SecItemCopyMatching`. This provider owns every write
/// to the keys it serves, so the memo is maintained exactly rather than expired on a
/// timer.
@MainActor
public final class KeychainSecureSettingsStorageProvider: SecureSettingsStorageProvider {

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let changeSubject = PassthroughSubject<String, Never>()

    /// Memoized raw keychain strings, by key name. The value is itself optional so an
    /// *absence* is cached too — an unset secret is both the common case and the
    /// costliest read. Only `set` and `remove` below reach the keys this provider
    /// serves, so every entry stays exact.
    private var cache: [String: String?] = [:]

    public var changes: AnyPublisher<String, Never> {
        changeSubject.eraseToAnyPublisher()
    }

    /// Creates a Keychain-backed secure settings provider.
    /// - Parameters:
    ///   - service: Optional service identifier override. Sets `KeychainHelper.service`
    ///     when non-nil. Pass `nil` (the default) to use the bundle identifier.
    ///   - accessGroup: Optional shared Keychain access group, assigned to
    ///     `KeychainHelper.accessGroup` (including `nil`, which clears any group a
    ///     prior provider set) so a co-signed binary (e.g. a daemon) carrying the
    ///     matching entitlement can read the same items.
    public init(
        service: String? = nil,
        accessGroup: String? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        if let service {
            KeychainHelper.service = service
        }
        // Assign unconditionally: the default is `nil` (no group), so passing `nil`
        // must CLEAR any group a previously-constructed provider left on the global —
        // otherwise a later app-local provider silently inherits a shared group.
        // (`service` keeps its conditional form because its default is the bundle id,
        // which must not be clobbered with `nil`.)
        KeychainHelper.accessGroup = accessGroup
        self.encoder = encoder
        self.decoder = decoder
    }

    // MARK: - SettingsStorageProvider

    public func get<Value: Codable & Sendable>(_ key: any StorableSetting<Value>) -> Value {
        guard let stored = storedString(forKey: key.name) else {
            return key.defaultValue
        }
        // Fast path: bare string passes through without JSON quoting.
        if Value.self == String.self, let bridged = stored as? Value {
            return bridged
        }
        // General path: decode the stored UTF-8 string as JSON.
        guard
            let data = stored.data(using: .utf8),
            let value = try? decoder.decode(Value.self, from: data)
        else {
            return key.defaultValue
        }
        return value
    }

    public func set<Value: Codable & Sendable>(_ value: Value, for key: any StorableSetting<Value>) {
        let stringToStore: String?
        if Value.self == String.self, let raw = value as? String {
            stringToStore = raw
        } else if let data = try? encoder.encode(value), let utf8 = String(data: data, encoding: .utf8) {
            stringToStore = utf8
        } else {
            stringToStore = nil
        }
        guard let stringToStore else {
            Self.logger.error("Failed to encode value for secure key '\(key.name, privacy: .public)'")
            return
        }
        guard KeychainHelper.set(stringToStore, forKey: key.name) else {
            // A failed write must not leave a stale memo standing: forget the key so
            // the next read goes back to the keychain for the truth.
            cache.removeValue(forKey: key.name)
            // KeychainHelper already logs the OSStatus.
            return
        }
        // Memoize what was just written. Every live `UserSetting` re-reads on the
        // change emitted below — this is the read that would otherwise go straight
        // back to securityd for a value we already hold.
        cache[key.name] = stringToStore
        changeSubject.send(key.name)
    }

    public func remove<Value: Codable & Sendable>(_ key: any StorableSetting<Value>) {
        guard KeychainHelper.delete(forKey: key.name) else {
            cache.removeValue(forKey: key.name)
            return
        }
        // `updateValue`, not `cache[name] = nil`: the subscript form would erase the
        // entry rather than record the absence, sending the next read back to securityd.
        cache.updateValue(nil, forKey: key.name)
        changeSubject.send(key.name)
    }

    public func contains<Value: Codable & Sendable>(_ key: any StorableSetting<Value>) -> Bool {
        KeychainHelper.exists(forKey: key.name)
    }

    /// The memoized raw keychain string for a key, reading through on the first ask.
    private func storedString(forKey name: String) -> String? {
        if let memoized = cache[name] {
            return memoized
        }
        let stored = KeychainHelper.get(forKey: name)
        cache.updateValue(stored, forKey: name)
        return stored
    }
}

extension KeychainSecureSettingsStorageProvider: Loggable {
    public static nonisolated let logger = makeLogger()
}
