<!-- leaf: implement-git-client/projects-user-settings-projects · source: git-client-projects-user-settings-projects.md -->

**Rules** (cite as `implement-git-client/projects-user-settings-projects#<slug>`):

- `skip-patterns-key` MUST
- `skip-patterns-default` MUST
- `highlight-active-pane-key` MUST
- `highlight-active-pane-default` MUST
- `follows-mouse-key` MUST
- `follows-mouse-default` MUST
- `main-actor-isolation` MUST
- `value-round-trip` MUST
- `removal-reverts-to-default` MUST
- `existence-check` MUST
- `array-setting-json-encoded` MUST
- `bool-settings-natively-stored` MUST
- `not-secure` MUST
- `corrupt-data-falls-back-to-default` MUST
- `change-notification` MUST
- `no-pattern-validation` MUST
- `highlight-active-pane-override` MUST

# UserSettings+Projects

## Overview

`UserSettings+Projects.swift` (`packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift`) is an extension on `UserSettings` that declares three persisted settings for the Projects feature: `projectScanSkipPatterns`, a `UserSetting<[String]>` keyed `"projectScanSkipPatterns"` that defaults to `GitRepoScanner.defaultRootSkipPatterns`; `highlightActivePane`, a `UserSetting<Bool>` keyed `"highlight_active_pane"` that defaults to `true`; and `activePaneFollowsMouse`, a `UserSetting<Bool>` keyed `"active_pane_follows_mouse"` that defaults to `false`. Each is a plain property declaration with no logic of its own — no validation, no side effect beyond what `UserSetting` and its underlying store already provide.

The file declares no read, write, remove, or observe mechanics of its own. `UserSetting<Value>` (`Core/SettingStorage/UserSetting.swift`), `StorableSetting` (`Core/SettingStorage/StorableSetting.swift`), and `SettingsStore`/`UserSettings` (`Core/SettingStorage/SettingsStore.swift`, `Core/SettingStorage/UserSettings.swift`) supply that behavior; `UserDefaultsSettingsStorageProvider` (`Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift`) supplies the persistence mechanics. This recipe covers those collaborators only for the contract they give these three properties — their own general contract belongs to a collaborator's own recipe (the GitRepoScanner recipe already covers the scanner that consumes `projectScanSkipPatterns`). The code that reads `projectScanSkipPatterns` and constructs a scanner from it (`ProjectsCoordinator.swift`), the settings panel that edits all three (`ProjectsSettingsPanelViewController.swift`), and the per-project override that can supersede `highlightActivePane` (`ThemeProjectOptions`, consumed in `ComposableTabsActivePane.swift`) are likewise collaborators' own contracts, out of scope here except where this file's own doc comments make a claim about them.

## Behavioral Requirements

- **skip-patterns-key**: `UserSettings.projectScanSkipPatterns.name` MUST equal the string `"projectScanSkipPatterns"` (`UserSettings+Projects.swift`).
- **skip-patterns-default**: `UserSettings.projectScanSkipPatterns.defaultValue` MUST equal `GitRepoScanner.defaultRootSkipPatterns` — the literal array `["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox", "Google Drive"]` (`UserSettings+Projects.swift`; `GitRepoScanner.swift`).
- **highlight-active-pane-key**: `UserSettings.highlightActivePane.name` MUST equal the string `"highlight_active_pane"` (`UserSettings+Projects.swift`).
- **highlight-active-pane-default**: `UserSettings.highlightActivePane.defaultValue` MUST equal `true` (`UserSettings+Projects.swift`).
- **follows-mouse-key**: `UserSettings.activePaneFollowsMouse.name` MUST equal the string `"active_pane_follows_mouse"` (`UserSettings+Projects.swift`).
- **follows-mouse-default**: `UserSettings.activePaneFollowsMouse.defaultValue` MUST equal `false` (`UserSettings+Projects.swift`).
- **main-actor-isolation**: All three settings MUST be read and written only on the main actor. `UserSettings+Projects.swift` adds these static properties to `UserSettings` with no `@MainActor` attribute of its own, but `UserSettings` carries that attribute at its primary declaration (`UserSettings.swift`), and `UserSetting<Value>` is itself a `@MainActor`-isolated class (`UserSetting.swift`); the isolation reaches these three properties by inheritance from the extended type rather than by an attribute repeated in this file.
- **value-round-trip**: For each of the three settings, reading `.value` MUST return the most recently written value for that key, and writing `.value = newValue` MUST persist `newValue` so a later read returns it — via the `StorableSetting.value` getter/setter (`UserSettings.swift`), routed through `UserSettings.shared.get`/`set` (`SettingsStore.swift`, `35-38`).
- **removal-reverts-to-default**: Calling `.remove()` on any of the three settings MUST cause a subsequent read of `.value` to return that property's own `defaultValue` — via `StorableSetting.remove()` (`UserSettings.swift`), routed to `SettingsStore.remove` (`SettingsStore.swift`) and the storage provider's own removal.
- **existence-check**: `.existsInStore()` MUST return `true` only once a value has been explicitly stored for that setting's key, and `false` before any write and again after `.remove()` — via `StorableSetting.existsInStore()` (`UserSettings.swift`).
- **array-setting-json-encoded**: Because `[String]` is not one of the types `UserDefaultsSettingsStorageProvider` stores natively — `Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, `Date` (`UserDefaultsSettingsStorageProvider.swift`) — a write to `projectScanSkipPatterns` MUST be JSON-encoded and stored as `Data` under the key `"projectScanSkipPatterns"`, and a read MUST JSON-decode that `Data` back into a `[String]` (`UserDefaultsSettingsStorageProvider.swift`, `44-53`).
- **bool-settings-natively-stored**: Because `Bool` is one of the types `UserDefaultsSettingsStorageProvider` stores natively, a write to `highlightActivePane` or `activePaneFollowsMouse` MUST be stored directly as a native `Bool` object under that setting's key, with no JSON encoding (`UserDefaultsSettingsStorageProvider.swift`, `44-46`, `65-69`).
- **not-secure**: All three settings MUST be stored through the non-secure `UserDefaultsSettingsStorageProvider`, never the Keychain-backed secure provider. None of the three `UserSetting.init` calls passes an `isSecure` argument, so `isSecure` defaults to `false` for each (`UserSettings+Projects.swift`; `UserSetting.swift`), and `SettingsStore` dispatches on `key.isSecure` to choose the provider (`SettingsStore.swift`).
- **corrupt-data-falls-back-to-default**: If the stored value for any of the three keys cannot be read back as that setting's `Value` type — undecodable `Data` for `projectScanSkipPatterns`, or an object that fails an `as? Bool` cast for the other two — a read MUST return that setting's `defaultValue` rather than throwing or crashing, via `UserDefaultsSettingsStorageProvider.get`'s fallthrough to `key.defaultValue` (`UserDefaultsSettingsStorageProvider.swift`).
- **change-notification**: A write to any of the three settings' `.value` MUST update that `UserSetting`'s `currentValue` (and its `@Published` projection) synchronously, within the same call, before the write's assignment statement returns. `UserDefaultsSettingsStorageProvider.set` stores the value, then sends the key name on a `PassthroughSubject`, delivered synchronously; `UserSetting.init`'s subscription filters for its own name and immediately re-reads and assigns `currentValue`, with no queue hop (`UserDefaultsSettingsStorageProvider.swift`; `UserSetting.swift`).
- **no-pattern-validation**: `projectScanSkipPatterns` MUST accept and store any `[String]` as its value, including empty strings, duplicate entries, and strings that are not valid `fnmatch` glob syntax. The declaration performs no check of its own on the strings it stores (`UserSettings+Projects.swift`); the doc comment states the scanner is handed this list as a plain parameter specifically so its own walk logic — not this setting — can be tested independently of a settings store.
- **highlight-active-pane-override**: `highlightActivePane`'s own doc comment states that a per-project `ThemeProjectOptions.highlightActivePane` overrides it (`UserSettings+Projects.swift`); the consumer that implements this precedence reads `overrides?.highlightActivePane ?? UserSettings.highlightActivePane.value` (`ComposableTabsActivePane.swift`), confirming that, when present, the override MUST take precedence over this setting's value.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `projectScanSkipPatterns` storage key | `String` (fixed) | `"projectScanSkipPatterns"` | The literal name `UserSetting.init` is constructed with; pinned per `skip-patterns-key` (`UserSettings+Projects.swift`). |
| `projectScanSkipPatterns` default | `[String]` (fixed) | `GitRepoScanner.defaultRootSkipPatterns` | Returned whenever no value has been stored or a stored value cannot be decoded (`UserSettings+Projects.swift`). |
| `highlightActivePane` storage key | `String` (fixed) | `"highlight_active_pane"` | Pinned per `highlight-active-pane-key` (`UserSettings+Projects.swift`). |
| `highlightActivePane` default | `Bool` (fixed) | `true` | Returned whenever no value has been stored (`UserSettings+Projects.swift`). |
| `activePaneFollowsMouse` storage key | `String` (fixed) | `"active_pane_follows_mouse"` | Pinned per `follows-mouse-key` (`UserSettings+Projects.swift`). |
| `activePaneFollowsMouse` default | `Bool` (fixed) | `false` | Returned whenever no value has been stored (`UserSettings+Projects.swift`). |
| `isSecure` (all three) | `Bool` (fixed) | `false` | Not passed explicitly at any of the three call sites, so `UserSetting.init`'s parameter default applies, routing all three through `UserDefaultsSettingsStorageProvider` rather than the Keychain-backed provider (`UserSettings+Projects.swift`; `UserSetting.swift`). |
| `UserSettings.shared` | `UserSettings` (a `SettingsStore`) | a fresh `UserSettings()`, itself defaulting to `UserDefaultsSettingsStorageProvider(defaults: .standard)` and `KeychainSecureSettingsStorageProvider()` | The store all three settings read and write through. The client app may replace `UserSettings.shared` before first access (`UserSettings.swift`; `SettingsStore.swift`). |

No environment variable is read by this file — it is three plain property declarations with no parameters of their own; `ProjectsCoordinator.swift` is the one caller that reads `UserSettings.projectScanSkipPatterns.currentValue` and passes it into `GitRepoScanner`'s own `rootSkipPatterns` initializer parameter, but that wiring lives outside this component's own file and is not part of its contract.

## Privacy

- **Data collected**: `projectScanSkipPatterns` stores folder-name and glob-pattern strings the user has typed or accepted, which can reveal something about how the user organizes their home directory; `highlightActivePane` and `activePaneFollowsMouse` store two boolean UI preferences with no descriptive content of their own (`UserSettings+Projects.swift`).
- **Storage**: all three values live in local `UserDefaults` storage only. `isSecure` is not set at any of the three call sites and defaults to `false` (`UserSetting.swift`), so none of the three is routed to the Keychain (`not-secure`).
- **Transmission**: none — `UserSettings+Projects.swift` makes no network call and transmits nothing.
- **Retention**: each value persists until explicitly overwritten, removed with `.remove()`, or the app's `UserDefaults` domain is deleted; the file itself defines no expiry or automatic cleanup.

