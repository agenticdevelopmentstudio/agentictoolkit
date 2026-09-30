<!-- leaf: implement-window-management/recents · source: window-management-recents.md -->

**Rules** (cite as `implement-window-management/recents#<slug>`):

- `policy-cases` MUST
- `policy-raw-values` MUST
- `policy-case-iterable` MUST
- `policy-codable` MUST
- `policy-sendable` MUST
- `policy-equatable` MUST
- `use-system-follows-default` MUST
- `always-reopens` MUST
- `never-reopens` MUST
- `reopen-decision-pure` MUST
- `display-name-use-system` MUST
- `display-name-always` MUST
- `display-name-never` MUST
- `system-default-key` MUST
- `system-default-absent` MUST
- `system-default-inverted-label` MUST
- `system-default-uncached` MUST
- `system-default-read-only` MUST
- `recent-count-key` MUST
- `recent-count-default` MUST
- `recent-count-storage-form` MUST
- `policy-setting-key` MUST
- `policy-setting-default` MUST
- `policy-setting-storage-form` MUST
- `policy-setting-decode-fallback` MUST
- `settings-not-secure` MUST
- `settings-main-actor` MUST
- `settings-observable` MUST
- `settings-lazy-binding` MUST
- `recent-count-mirror` MUST
- `recent-count-mirror-live` MUST
- `policy-consumed-for-documents-only` MUST
- `no-network-no-files` MUST
- `no-errors` MUST

# Window Management Recents

## Overview

The recents slice of the AgenticToolkit window manager is two small files under `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/Recents/`:

- `ReopenOnLaunchPolicy.swift` declares `ReopenOnLaunchPolicy`, a `String`-backed, `Codable`, `Sendable`, `CaseIterable`, `Equatable` enum with three cases (`useSystem`, `always`, `never`) that decides whether previously-open windows reopen at launch. Its doc comment models it on "Xcode's 'Restore open projects and workspaces' preference." It resolves to a `Bool` through `shouldReopen(systemDefault:)`, exposes an English `displayName` per case, and reads the macOS-wide `NSQuitAlwaysKeepsWindows` preference through the static `systemDefault`.
- `UserSettings+Recents.swift` declares two persisted settings on `UserSettings`: `recentWindowsCount` (`UserSetting<Int>`, key `"recentWindowsCount"`, default `10`), the "Maximum number of recent documents shown in File → Open Recent", and `reopenOnLaunchPolicy` (`UserSetting<ReopenOnLaunchPolicy>`, key `"reopenOnLaunchPolicy"`, default `.useSystem`).

These files hold the model and the stored preferences only. Behavior that acts on them lives in the consumers: `WindowManager.applyRecentDocumentCountFromSettings()` mirrors `recentWindowsCount` into AppKit's `NSRecentDocumentsLimit` user default, `WindowManager.reopenRecentsOnLaunch()` evaluates `reopenOnLaunchPolicy`, and `GeneralSettingsPanelViewController.createWindowBehaviorGroup()` presents both settings to the user. Use this ingredient when an app needs a user-selectable "restore windows on launch" policy that can defer to the OS-wide setting, plus a user-adjustable cap on the recent-documents list.

## Behavioral Requirements

### ReopenOnLaunchPolicy

- **policy-cases**: `ReopenOnLaunchPolicy` MUST declare exactly three cases, in this order: `useSystem`, `always`, `never`.
- **policy-raw-values**: Each case MUST use its case name as its `String` raw value: `"useSystem"`, `"always"`, `"never"`.
- **policy-case-iterable**: `ReopenOnLaunchPolicy.allCases` MUST contain exactly 3 elements, in declaration order (`useSystem`, `always`, `never`).
- **policy-codable**: `ReopenOnLaunchPolicy` MUST encode and decode as its raw `String` value (the compiler-synthesized `Codable` conformance for a `String`-backed enum), so a stored value round-trips only for the three raw values listed in policy-raw-values.
- **policy-sendable**: `ReopenOnLaunchPolicy` MUST conform to `Sendable`; as a payload-free enum the compiler enforces this, so a value MAY cross any concurrency-domain boundary without synchronization.
- **policy-equatable**: `ReopenOnLaunchPolicy` MUST conform to `Equatable`, with two values equal if and only if they are the same case.
- **use-system-follows-default**: `shouldReopen(systemDefault:)` on `useSystem` MUST return the `systemDefault` argument unchanged (`true` → `true`, `false` → `false`).
- **always-reopens**: `shouldReopen(systemDefault:)` on `always` MUST return `true` for either value of `systemDefault`.
- **never-reopens**: `shouldReopen(systemDefault:)` on `never` MUST return `false` for either value of `systemDefault`.
- **reopen-decision-pure**: `shouldReopen(systemDefault:)` MUST be a pure function of the receiver and its argument; it MUST NOT read any preference, including `NSQuitAlwaysKeepsWindows`, itself. The caller supplies the system value (in the source, `WindowManager.reopenRecentsOnLaunch()` passes `ReopenOnLaunchPolicy.systemDefault`).
- **display-name-use-system**: `displayName` on `useSystem` MUST return `"Use System Setting"`.
- **display-name-always**: `displayName` on `always` MUST return `"Always"`.
- **display-name-never**: `displayName` on `never` MUST return `"Never"`.
- **system-default-key**: `ReopenOnLaunchPolicy.systemDefault` MUST return the Boolean value of the `NSQuitAlwaysKeepsWindows` key read from the standard user defaults, which search the app's domain and then the global domain.
- **system-default-absent**: `ReopenOnLaunchPolicy.systemDefault` MUST return `false` when `NSQuitAlwaysKeepsWindows` is absent from every searched domain (the standard `bool(forKey:)` result for a missing key).
- **system-default-inverted-label**: `systemDefault` MUST report the stored key, not the System Settings checkbox: per the source doc comment, checking "Close windows when quitting an application" sets `NSQuitAlwaysKeepsWindows = false`, so a checked box yields `systemDefault == false`.
- **system-default-uncached**: `systemDefault` MUST be a computed property that re-reads the preference on every access; it MUST NOT cache the value.
- **system-default-read-only**: `ReopenOnLaunchPolicy` MUST NOT write `NSQuitAlwaysKeepsWindows` or any other preference; its only side effect is the read in `systemDefault`.

### Persisted settings

- **recent-count-key**: `UserSettings.recentWindowsCount` MUST persist under the key `"recentWindowsCount"`.
- **recent-count-default**: `UserSettings.recentWindowsCount` MUST read as `10` when no value is stored under its key.
- **recent-count-storage-form**: Because the value type is `Int`, the default `UserDefaultsSettingsStorageProvider` MUST store `recentWindowsCount` as a native integer, not JSON-encoded data.
- **recent-count-range**: A count in the settings UI's range is a caller precondition. `recentWindowsCount` accepts any `Int`, including negative values; the only bound is the settings UI stepper (`minValue: 0`, `maxValue: 50` in `GeneralSettingsPanelViewController`), so a programmatic write of a negative or very large count reaches `NSRecentDocumentsLimit` unchanged.
- **policy-setting-key**: `UserSettings.reopenOnLaunchPolicy` MUST persist under the key `"reopenOnLaunchPolicy"`.
- **policy-setting-default**: `UserSettings.reopenOnLaunchPolicy` MUST read as `.useSystem` when no value is stored under its key.
- **policy-setting-storage-form**: Because `ReopenOnLaunchPolicy` is not a natively stored primitive, the default `UserDefaultsSettingsStorageProvider` MUST store `reopenOnLaunchPolicy` as JSON-encoded data of its raw `String` value.
- **policy-setting-decode-fallback**: When the data stored under `"reopenOnLaunchPolicy"` fails to decode as a `ReopenOnLaunchPolicy`, reading the setting MUST return the default `.useSystem`; the storage provider discards the decode failure without logging it (behavior owned by `UserDefaultsSettingsStorageProvider.get`, not by these files).
- **settings-not-secure**: Both settings MUST be declared non-secure (`isSecure` defaults to `false`), so they route to the store's ordinary settings provider, never the Keychain provider.
- **settings-main-actor**: Both settings MUST be accessed on the main actor: `UserSettings` and `UserSetting` are both declared `@MainActor`, so the compiler rejects reads or writes from any other isolation domain.
- **settings-observable**: Each setting MUST publish its current value through `UserSetting.currentValue` (`@Published`), updating whenever the backing store emits a change for the setting's key.
- **settings-lazy-binding**: Each setting MUST bind to `UserSettings.shared` when the static property is first accessed; the `UserSetting` initializer reads the current value from, and subscribes to changes on, the store that is `UserSettings.shared` at that moment.

### Consumer contract declared by the source

- **recent-count-mirror**: Per the `recentWindowsCount` doc comment ("Mirrored to `NSDocumentController.maximumRecentDocumentCount` by `WindowManager.applyRecentDocumentCountFromSettings()`"), calling `applyRecentDocumentCountFromSettings()` MUST write the current `recentWindowsCount` value to the `NSRecentDocumentsLimit` key in the standard user defaults.
- **recent-count-mirror-live**: After `WindowManager` is constructed, a change to `recentWindowsCount` MUST be mirrored to `NSRecentDocumentsLimit` on a later main-run-loop turn with no explicit call (the manager subscribes to `currentValue` and receives on `RunLoop.main`).
- **policy-consumed-for-documents-only**: `reopenOnLaunchPolicy` MUST govern only the reopen of recent document windows in `WindowManager.reopenRecentsOnLaunch()`; per `ProjectWindowManager.restoreOpenProjects()`'s doc comment, project windows "not consult `reopenOnLaunchPolicy`".
- **no-network-no-files**: Neither file MUST perform network access, file I/O beyond the user-defaults reads and writes described above, process launches, or notification posting.
- **no-errors**: No operation in either file MUST throw or return an error; every read yields a value (stored, or the default).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `UserSettings.recentWindowsCount` (key `recentWindowsCount`) | `Int` | `10` | Maximum number of recent documents shown in File → Open Recent; mirrored to `NSRecentDocumentsLimit` by `WindowManager`. |
| `UserSettings.reopenOnLaunchPolicy` (key `reopenOnLaunchPolicy`) | `ReopenOnLaunchPolicy` | `.useSystem` | Whether windows reopen at launch: follow the OS, always, or never. |
| `NSQuitAlwaysKeepsWindows` (system preference, read-only here) | `Bool` | `false` when absent | macOS-wide "keep windows on quit" value that `useSystem` defers to; set by the inverted System Settings checkbox "Close windows when quitting an application". |
| `NSRecentDocumentsLimit` (AppKit preference, written by the consumer) | `Int` | AppKit's own default until first mirrored | Written by `WindowManager.applyRecentDocumentCountFromSettings()`; not written by these files. |
| `UserSettings.shared` | `UserSettings` | `UserSettings()` backed by `UserDefaultsSettingsStorageProvider` over `UserDefaults.standard` | Injected store both settings bind to at first access. |

## Localization

`ReopenOnLaunchPolicy.displayName` returns hardcoded English literals with no string-catalog lookup; the settings panel shows them as the popup's choice labels.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Use System Setting` | `displayName` for `useSystem`, a choice label in the "Restore windows on launch:" popup |
| (none; literal) | `Always` | `displayName` for `always` |
| (none; literal) | `Never` | `displayName` for `never` |

The popup title "Restore windows on launch:" and the stepper title "Number of recent documents:" are literals in `GeneralSettingsPanelViewController`, not in these files.

