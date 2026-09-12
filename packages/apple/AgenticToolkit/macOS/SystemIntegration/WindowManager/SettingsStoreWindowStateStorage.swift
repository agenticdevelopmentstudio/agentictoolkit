import Foundation
import AgenticToolkitCore

/// `WindowStateStorage` backed by a `SettingsStore`. Lets window frames
/// share the toolkit's general settings persistence — provider
/// pluggability (UserDefaults / iCloud / SQLite), a Combine `changes`
/// publisher, and the same secure-vs-default routing — without
/// `WindowFrameManager` knowing anything about it.
///
/// The on-disk key formats (`"WindowState_<id>"`, `"WindowVisible_<id>"`)
/// match `UserDefaultsWindowStateStorage`'s defaults, so swapping this in
/// over a UserDefaults-backed `SettingsStore` reads existing state without
/// migration.
@MainActor
public struct SettingsStoreWindowStateStorage: WindowStateStorage {

    private let settings: SettingsStore
    private let keyPrefix: String
    private let visibilityKeyPrefix: String

    public init(
        settings: SettingsStore,
        keyPrefix: String = "WindowState_",
        visibilityKeyPrefix: String = "WindowVisible_"
    ) {
        self.settings = settings
        self.keyPrefix = keyPrefix
        self.visibilityKeyPrefix = visibilityKeyPrefix
    }

    public func loadState(for id: String) -> PersistedWindowState? {
        settings.get(stateSetting(for: id))
    }

    public func saveState(_ state: PersistedWindowState, for id: String) {
        settings.set(state, for: stateSetting(for: id))
    }

    public func removeState(for id: String) {
        settings.remove(stateSetting(for: id))
    }

    public func loadVisibility(for id: String) -> Bool? {
        let setting = visibilitySetting(for: id)
        // `contains` distinguishes "never set" (nil) from "explicitly false",
        // matching `UserDefaultsWindowStateStorage`'s contract. We store the
        // raw `Bool` natively (not wrapped in `Optional`) so an existing
        // UserDefaults boolean written by either backing reads back here.
        guard settings.contains(setting) else { return nil }
        return settings.get(setting)
    }

    public func saveVisibility(_ visible: Bool, for id: String) {
        settings.set(visible, for: visibilitySetting(for: id))
    }

    public func removeVisibility(for id: String) {
        settings.remove(visibilitySetting(for: id))
    }

    private func stateSetting(for id: String) -> WindowStateSetting {
        WindowStateSetting(name: WindowStateNamespace.qualify(keyPrefix + id))
    }

    private func visibilitySetting(for id: String) -> WindowVisibilitySetting {
        WindowVisibilitySetting(name: WindowStateNamespace.qualify(visibilityKeyPrefix + id))
    }
}

/// One-key-per-window-id `StorableSetting`. The name is fully resolved
/// at construction time; `SettingsStore` routes via the non-secure
/// provider (matching the original UserDefaults behaviour).
@MainActor
private struct WindowStateSetting: StorableSetting {
    let name: String
    let isSecure: Bool = false
    let defaultValue: PersistedWindowState? = nil
}

/// Visibility lives on a separate key so frame + visibility opt-ins are
/// independent. Stored as a native `Bool` so the on-disk representation
/// matches `UserDefaultsWindowStateStorage` (no JSON wrapping). The
/// caller uses `SettingsStore.contains` to distinguish "never been
/// shown" from "explicitly hidden."
@MainActor
private struct WindowVisibilitySetting: StorableSetting {
    let name: String
    let isSecure: Bool = false
    let defaultValue: Bool = false
}
