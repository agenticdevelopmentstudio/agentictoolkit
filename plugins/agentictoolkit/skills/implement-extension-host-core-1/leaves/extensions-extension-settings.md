<!-- leaf: implement-extension-host-core-1/extensions-extension-settings · source: extension-host-core-extensions-extension-settings.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-settings#<slug>`):

- `disabled-identifiers-key` MUST
- `disabled-identifiers-default` MUST
- `enabled-by-default` MUST
- `main-actor-isolation` MUST
- `value-round-trip` MUST
- `removal-reverts-to-default` MUST
- `existence-check` MUST
- `json-encoded-persistence` MUST
- `not-secure` MUST
- `corrupt-data-falls-back-to-default` MUST
- `change-notification` MUST
- `no-identifier-validation` MUST
- `case-sensitive-storage` MUST

# ExtensionSettings

## Overview

`ExtensionSettings.swift` (`packages/apple/AgenticToolkit/Core/Extensions/ExtensionSettings.swift`) is a `@MainActor` extension on `UserSettings` that declares exactly one static property, `disabledExtensionIdentifiers`: a `UserSetting<Set<String>>` keyed `"extensions.disabledIdentifiers"`, defaulting to an empty set. It is the extension host's sole persisted setting — every identifier the set holds names an extension a person has switched off; an identifier the set has never held is enabled, so a freshly installed extension runs with no migration needed.

The file declares no logic of its own. `UserSetting<Value>` (`Core/SettingStorage/UserSetting.swift`), `StorableSetting` (`Core/SettingStorage/StorableSetting.swift`), and `SettingsStore`/`UserSettings` (`Core/SettingStorage/SettingsStore.swift`, `Core/SettingStorage/UserSettings.swift`) supply the read, write, remove, existence-check, and change-notification behavior this property inherits; `UserDefaultsSettingsStorageProvider` (`Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift`) supplies the persistence mechanics. Those files are consulted below only for the contract they give this one property — this recipe covers `ExtensionSettings.swift` alone; the general contract of `UserSetting`, `SettingsStore`, and `UserDefaultsSettingsStorageProvider` is a collaborator's own recipe to write. The enablement logic that reads and writes this set — `ExtensionRegistry.isEnabled`, `setEnabled`, and `uninstall` (`Core/Extensions/ExtensionRegistry.swift`) — is likewise a collaborator's contract, out of scope here.

## Behavioral Requirements

- **disabled-identifiers-key**: `UserSettings.disabledExtensionIdentifiers.name` MUST equal the string `"extensions.disabledIdentifiers"` (`ExtensionSettings.swift`; asserted by `ExtensionSettingsTests.theStorageKeyIsPinned`, `ExtensionSettingsTests.swift`).
- **disabled-identifiers-default**: `UserSettings.disabledExtensionIdentifiers.defaultValue` MUST be an empty `Set<String>` (`ExtensionSettings.swift`; asserted by `ExtensionSettingsTests.nothingIsDisabledByDefault`, `ExtensionSettingsTests.swift`).
- **enabled-by-default**: An identifier that has never been added to the stored value MUST be treated as enabled, because the set records disabled identifiers rather than enabled ones — the doc comment states this is deliberate, so a newly added extension needs no migration (`ExtensionSettings.swift`).
- **main-actor-isolation**: `disabledExtensionIdentifiers` MUST be read and written only on the main actor. The enclosing `extension UserSettings` is declared `@MainActor` (`ExtensionSettings.swift`), and `UserSetting<Value>` is itself a `@MainActor`-isolated class (`UserSetting.swift`), so every access is confined and serialized by construction.
- **value-round-trip**: Reading `UserSettings.disabledExtensionIdentifiers.value` MUST return the most recently written `Set<String>` for that key, and writing `.value = newValue` MUST persist `newValue` so a later read returns it — via the `StorableSetting.value` getter/setter (`UserSettings.swift`), routed through `UserSettings.shared.get`/`set` (`SettingsStore.swift`, `35-38`).
- **removal-reverts-to-default**: Calling `UserSettings.disabledExtensionIdentifiers.remove()` MUST cause a subsequent read of `.value` to return `defaultValue` (an empty set) — via `StorableSetting.remove()` (`UserSettings.swift`), routed to `SettingsStore.remove` (`SettingsStore.swift`) and `UserDefaultsSettingsStorageProvider.remove`, which deletes the stored `UserDefaults` object (`UserDefaultsSettingsStorageProvider.swift`).
- **existence-check**: `UserSettings.disabledExtensionIdentifiers.existsInStore()` MUST return `true` only once a value has been explicitly stored for `"extensions.disabledIdentifiers"`, and `false` before any write and again after `remove()` — via `StorableSetting.existsInStore()` (`UserSettings.swift`), routed to `UserDefaultsSettingsStorageProvider.contains`, which checks whether `UserDefaults.object(forKey:)` is non-nil (`UserDefaultsSettingsStorageProvider.swift`).
- **json-encoded-persistence**: Because `Set<String>` is not one of the types `UserDefaultsSettingsStorageProvider` stores natively — `Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, `Date` (`UserDefaultsSettingsStorageProvider.swift`) — a write to `disabledExtensionIdentifiers` MUST be JSON-encoded with `JSONEncoder` and stored as `Data` under the key `"extensions.disabledIdentifiers"`, and a read MUST JSON-decode that `Data` back into a `Set<String>` (`UserDefaultsSettingsStorageProvider.swift`, `44-53`).
- **not-secure**: `disabledExtensionIdentifiers` MUST be stored through the non-secure `UserDefaultsSettingsStorageProvider`, never the Keychain-backed secure provider. `UserSetting.init` is called with no `isSecure` argument, so `isSecure` defaults to `false` (`ExtensionSettings.swift`; `UserSetting.swift`), and `SettingsStore` dispatches on `key.isSecure` to choose the provider (`SettingsStore.swift`).
- **corrupt-data-falls-back-to-default**: If the `Data` stored under `"extensions.disabledIdentifiers"` cannot be decoded as `Set<String>`, a read MUST return `defaultValue` (an empty set) rather than throwing or crashing. The decode uses `try?` and falls through to `key.defaultValue` on failure (`UserDefaultsSettingsStorageProvider.swift`); this fallback is a declared, tested contract of the storage layer itself (`UserDefaultsSettingsStoreTests.testCodableStructFallsBackToDefaultOnCorruptedData`), not a gap particular to this file.
- **change-notification**: A write to `disabledExtensionIdentifiers.value` MUST update `UserSetting.currentValue` (and its `@Published` projection) synchronously, within the same call, before the write's assignment statement returns. `UserDefaultsSettingsStorageProvider.set` stores the value, then sends the key name on a `PassthroughSubject`, which delivers to subscribers synchronously (`UserDefaultsSettingsStorageProvider.swift`); `UserSetting.init`'s subscription filters for its own name and immediately re-reads and assigns `currentValue`, with no queue hop (`UserSetting.swift`). This differs from `UserSettingObserver`, whose `onChange` callback explicitly redispatches to `DispatchQueue.main` (`UserSetting.swift`) — a detail belonging to that collaborator, named here so a port does not assume the same delay applies to `currentValue` itself.
- **no-identifier-validation**: `disabledExtensionIdentifiers` MUST accept and store any `String` as a member of the set. The declaration performs no check that a stored identifier names an installed or known extension (`ExtensionSettings.swift`); validating and reconciling identifiers against installed extensions is a caller's responsibility, not this property's.
- **case-sensitive-storage**: The set MUST store identifier strings exactly as given, applying no case-folding of its own. `Set<String>` equality is exact-string equality, so a differently-cased spelling of the same identifier is a distinct member unless a caller folds it before writing (`ExtensionSettings.swift`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| storage key | `String` (fixed) | `"extensions.disabledIdentifiers"` | The literal name `UserSetting.init` is constructed with; pinned per `disabled-identifiers-key`, never derived at runtime (`ExtensionSettings.swift`). |
| default value | `Set<String>` (fixed) | `[]` | The literal default `UserSetting.init` is constructed with; returned whenever no value has been stored or a stored value cannot be decoded (`ExtensionSettings.swift`). |
| `isSecure` | `Bool` (fixed) | `false` | Not passed explicitly at the call site, so `UserSetting.init`'s parameter default applies, routing storage to `UserDefaultsSettingsStorageProvider` rather than the Keychain-backed provider (`ExtensionSettings.swift`; `UserSetting.swift`). |
| `UserSettings.shared` | `UserSettings` (a `SettingsStore`) | a fresh `UserSettings()`, itself defaulting to `UserDefaultsSettingsStorageProvider(defaults: .standard)` and `KeychainSecureSettingsStorageProvider()` | The store `disabledExtensionIdentifiers` reads and writes through. The client app may replace `UserSettings.shared` before first access; the doc comment on `UserSettings.swift` states client apps should create and set it (`UserSettings.swift`; `SettingsStore.swift`). |

No environment variable is read by this file — it is a plain property declaration with no parameters of its own; the table above lists the fixed values baked into that declaration and the one injected dependency (`UserSettings.shared`) it relies on.

