<!-- leaf: implement-settings/storage--part-3 · source: settings-storage.md -->

# Settings Storage — continued (part 3)

**Rules** (cite as `implement-settings/storage--part-3#<slug>`):

- `usersetting-construction-reads-through` MUST
- `usersetting-published-mirror` MUST
- `usersetting-write-through` MUST
- `observer-deferred-callback` MUST
- `observedsetting-wraps-observer` MUST
- `colorsetting-alias` MUST
- `keychain-service-override-timing` SHOULD
- `sqlite-nonisolated-handle` MUST

### UserSetting / UserSettingObserver / ObservedSetting / ColorSetting

- **usersetting-construction-reads-through**: Constructing a `UserSetting` MUST synchronously read the current value for its key from `UserSettings.shared` before returning, so `currentValue` reflects any already-stored value rather than always starting at `defaultValue`.
- **usersetting-published-mirror**: `UserSetting.currentValue` MUST update, through its `@Published` storage, whenever `UserSettings.shared.changes` publishes this instance's `name`, re-reading the value from `UserSettings.shared` at that point.
- **usersetting-write-through**: Writing `storableSetting.value = newValue` MUST write through `UserSettings.shared.set`, so a subsequent read from any caller observes the new value.
- **observer-deferred-callback**: `UserSettingObserver.onChange` MUST fire on the main dispatch queue on the turn after `currentValue` changes, not synchronously inside the write that caused the change, and MUST NOT fire for the value a `UserSettingObserver` was constructed with.
- **observedsetting-wraps-observer**: `ObservedSetting` MUST forward its `wrappedValue` get/set to an internally-held `UserSettingObserver` and expose the underlying `UserSetting` as `projectedValue`.
- **colorsetting-alias**: `ColorSetting` MUST be a type alias for `UserSetting<RGBAColor>`.
- **keychain-service-override-timing**: A caller SHOULD construct at most one `KeychainSecureSettingsStorageProvider` per process with a non-default `service`/`accessGroup`, or construct every instance with the same override; see Design Decisions.

### Swift concurrency

- **isolation-by-declaration**: `StorableSetting`, `SettingsStorageProvider`, `UserSetting`, `UserSettingObserver`, `ObservedSetting`, `SettingsStore`/`UserSettings`, `InMemorySecureSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`, and `iCloudSettingsStorageProvider` are all `@MainActor`-isolated by declaration or by conforming to the `@MainActor` `SettingsStorageProvider`/`StorableSetting` protocols; `InMemorySettingsStorageProvider` and `UserDefaultsSettingsStorageProvider` carry no `@MainActor` annotation of their own and instead serialize their own internal state (a concurrent queue with a barrier, and thread-safe `UserDefaults`, respectively) so they remain safe to call from contexts that are not already on the main actor.
- **sqlite-nonisolated-handle**: `SqliteStorageProvider`'s `database` pointer MUST be declared `nonisolated(unsafe)` so `deinit` — which runs outside actor isolation — can close it synchronously without an `await`.

## Configuration

Constructor parameters (dependency injection) per backend:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SettingsStore.settingsProvider` | `SettingsStorageProvider` | `UserDefaultsSettingsStorageProvider()` | Backend for keys with `isSecure == false` |
| `SettingsStore.secureSettingsProvider` | `SecureSettingsStorageProvider` | `KeychainSecureSettingsStorageProvider()` | Backend for keys with `isSecure == true` |
| `InMemorySettingsStorageProvider.initial` | `[String: Any]` | `[:]` | Seed values for tests/previews |
| `InMemorySecureSettingsStorageProvider.initial` | `[String: Any]` | `[:]` | Seed values, forwarded to its internal in-memory provider |
| `UserDefaultsSettingsStorageProvider.defaults` | `UserDefaults` | `.standard` | Backing defaults suite |
| `KeychainSecureSettingsStorageProvider.service` | `String?` | `nil` (keeps `KeychainHelper.service`, itself the bundle identifier) | Keychain service identifier override |
| `KeychainSecureSettingsStorageProvider.accessGroup` | `String?` | `nil` | Shared keychain access group |
| `SqliteStorageProvider.path` | `String` | none (required) | Filesystem path of the SQLite database |
| `iCloudSettingsStorageProvider.store` | `NSUbiquitousKeyValueStore` | `.default` | Backing key-value store |
| `UserDefaultsSettingsStorageProvider`/`KeychainSecureSettingsStorageProvider`/`SqliteStorageProvider`/`iCloudSettingsStorageProvider`.`encoder`/`decoder` | `JSONEncoder`/`JSONDecoder` | `JSONEncoder()`/`JSONDecoder()` | Injected for testability |

Setting keys declared on `UserSettings` in the given sources:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `editor.show_line_numbers` | `Bool` | `true` | `UserSettings.editorShowLineNumbers` |
| `editor.show_overview` | `Bool` | `true` | `UserSettings.editorShowOverview` |
| `editor.show_invisibles` | `Bool` | `false` | `UserSettings.editorShowInvisibles` |
| `git.executable_path` | `String` | `/usr/bin/git` | `UserSettings.gitExecutablePath` |
| `git.status_timeout_seconds` | `Int` | `5` | `UserSettings.gitStatusTimeoutSeconds` |
| `git.status_includes_submodules` | `Bool` | `false` | `UserSettings.gitStatusIncludesSubmodules` |
| `theme.active_theme_id` | `String` | `BuiltInThemes.defaultID` | `UserSettings.activeThemeID`; built-in themes are never stored under this key |
| `theme.custom_themes` | `[ColorTheme]` | `[]` | `UserSettings.customThemes` |
| `launchAtLogin` | `Bool` | `false` | `UserSettings.launchAtLogin` |
| `launchAtLoginPromptShown` | `Bool` | `false` | `UserSettings.launchAtLoginPromptShown` |
| `launchAtLoginHintDismissed` | `Bool` | `false` | `UserSettings.launchAtLoginHintDismissed` |

## Localization

`SqliteSettingsError` conforms to `LocalizedError` and returns two hardcoded English strings from `errorDescription`: one describing the failed-open case with the path and the underlying SQLite message, and one describing the failed-schema case with the underlying SQLite message. Neither is looked up from a localization table, so every consumer sees the same English text regardless of locale. No other user-facing string originates from the given sources.

## Privacy

- **Data collected**: None of the given sources collect data on their own; they persist values a caller supplies for its own keys — including, for a key with `isSecure == true`, secrets such as the API keys `KeychainSecureSettingsStorageProvider`'s own documentation cites as a target use case.
- **Storage**: A plain key (`isSecure == false`) is stored, by default, in `UserDefaults` (a property list on local disk) or, if the caller supplies `SqliteStorageProvider`, in a SQLite file at a caller-chosen path — neither encrypted by this component. A secure key is stored in the macOS Keychain via `KeychainHelper`, which the OS encrypts at rest and which `init` can scope to a shared access group for a co-signed daemon. `InMemorySettingsStorageProvider`/`InMemorySecureSettingsStorageProvider` never touch disk and are ephemeral for the life of the process. The given sources treat a failed keychain read/write as an ordinary error — logged, memo invalidated — rather than a detected security violation; there is no lockout, alert, or revocation behavior for repeated keychain failures.
- **Transmission**: Every backend except `iCloudSettingsStorageProvider` is local-device-only. `iCloudSettingsStorageProvider` syncs its values off-device through `NSUbiquitousKeyValueStore` to the user's iCloud account and back down to their other devices; it is used only for plain (non-secure) settings in the given sources — nothing routes a secure key through it.
- **Retention**: A value set through any backend persists until explicitly removed or the underlying store is cleared (app-data reset, keychain item deletion, or an uninstall — Keychain items can outlive an uninstall on macOS); the in-memory backends retain nothing past the process's lifetime. `iCloudSettingsStorageProvider` resolves a conflicting concurrent edit from two devices last-write-wins, per its own documentation, with iCloud performing the resolution.

