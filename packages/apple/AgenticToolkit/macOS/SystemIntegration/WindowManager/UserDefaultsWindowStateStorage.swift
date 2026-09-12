import Foundation

/// Stores window state in UserDefaults as JSON.
public struct UserDefaultsWindowStateStorage: WindowStateStorage {
    public let keyPrefix: String
    public let visibilityKeyPrefix: String

    public init(
        keyPrefix: String = "WindowState_",
        visibilityKeyPrefix: String = "WindowVisible_"
    ) {
        self.keyPrefix = keyPrefix
        self.visibilityKeyPrefix = visibilityKeyPrefix
    }

    /// Both key families run through `WindowStateNamespace`, so a second copy
    /// of an app reads and writes its own layout instead of the shared one.
    private func stateKey(_ id: String) -> String {
        WindowStateNamespace.qualify(keyPrefix + id)
    }

    private func visibilityKey(_ id: String) -> String {
        WindowStateNamespace.qualify(visibilityKeyPrefix + id)
    }

    public func loadState(for id: String) -> PersistedWindowState? {
        guard let data = UserDefaults.standard.data(forKey: stateKey(id)) else { return nil }
        return try? JSONDecoder().decode(PersistedWindowState.self, from: data)
    }

    public func saveState(_ state: PersistedWindowState, for id: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateKey(id))
    }

    public func removeState(for id: String) {
        UserDefaults.standard.removeObject(forKey: stateKey(id))
    }

    public func loadVisibility(for id: String) -> Bool? {
        // `object(forKey:)` distinguishes absent (nil) from explicit false,
        // so a window that's never been shown stays nil rather than
        // misreporting "saved hidden."
        UserDefaults.standard.object(forKey: visibilityKey(id)) as? Bool
    }

    public func saveVisibility(_ visible: Bool, for id: String) {
        UserDefaults.standard.set(visible, forKey: visibilityKey(id))
    }

    public func removeVisibility(for id: String) {
        UserDefaults.standard.removeObject(forKey: visibilityKey(id))
    }

    public func visibleWindowIDs() -> [String] {
        let prefix = WindowStateNamespace.qualify(visibilityKeyPrefix)
        return UserDefaults.standard.dictionaryRepresentation().compactMap { key, value in
            guard key.hasPrefix(prefix), (value as? Bool) == true else { return nil }
            return String(key.dropFirst(prefix.count))
        }
    }
}
