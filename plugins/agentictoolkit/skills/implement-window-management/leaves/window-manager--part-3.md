<!-- leaf: implement-window-management/window-manager--part-3 · source: window-management-window-manager.md -->

# WindowManager — continued (part 3)

**Rules** (cite as `implement-window-management/window-manager--part-3#<slug>`):

- `storage-protocol` MUST
- `storage-independent-keys` MUST
- `storage-key-format` MUST
- `storage-key-defaults` MUST
- `storage-namespace-late-binding` MUST
- `storage-state-json` MUST
- `storage-visibility-native` MUST
- `storage-visibility-tristate` MUST
- `storage-remove` MUST
- `userdefaults-target` MUST
- `userdefaults-visible-ids` MUST
- `settings-store-target` MUST
- `settings-store-change-signal` MUST
- `settings-store-non-bool-visibility` MUST
- `namespace-default` MUST
- `namespace-qualify` MUST
- `namespace-token` MUST
- `namespace-stable` MUST
- `namespace-no-raw-path` MUST
- `namespace-bundle` MUST
- `namespace-reset` MUST
- `namespace-host-timing` MUST
- `screenshot-capture` MUST
- `screenshot-symbol-missing` MUST
- `screenshot-symbol-once` MUST
- `screenshot-no-permission` MUST
- `screenshot-png-offscreen` MUST
- `screenshot-png-failure` MUST
- `screenshot-png-success` MUST

### Window state storage

- **storage-protocol**: `WindowStateStorage` MUST provide `loadState(for:)`, `saveState(_:for:)`, `removeState(for:)`, `loadVisibility(for:)`, `saveVisibility(_:for:)`, `removeVisibility(for:)` and `visibleWindowIDs()`, all keyed by window ID string.
- **storage-independent-keys**: Frame state and visibility MUST be stored under separate keys so a window can persist one without the other.
- **storage-key-format**: The frame key MUST be `WindowStateNamespace.current + keyPrefix + id` and the visibility key MUST be `WindowStateNamespace.current + visibilityKeyPrefix + id`.
- **storage-key-defaults**: `keyPrefix` MUST default to `WindowState_` and `visibilityKeyPrefix` MUST default to `WindowVisible_` in both implementations.
- **storage-namespace-late-binding**: Both implementations MUST read the namespace when composing each key, not at construction, so a namespace set after a storage was created applies to it.
- **storage-state-json**: `PersistedWindowState` MUST be stored as JSON-encoded `Data` in both implementations, so either implementation reads state the other wrote over the same defaults domain.
- **storage-visibility-native**: Visibility MUST be stored as a native boolean (not JSON) in both implementations.
- **storage-visibility-tristate**: `loadVisibility(for:)` MUST return `nil` when the key has never been written, and the stored boolean otherwise, so "never shown" is distinct from "explicitly hidden".
- **storage-remove**: `removeState(for:)` and `removeVisibility(for:)` MUST delete the key, after which the matching load returns `nil`.
- **userdefaults-target**: `UserDefaultsWindowStateStorage` MUST read and write `UserDefaults.standard`.
- **userdefaults-visible-ids**: `UserDefaultsWindowStateStorage.visibleWindowIDs()` MUST return, in unspecified order, the ID suffix of every standard-defaults key that starts with `WindowStateNamespace.current + visibilityKeyPrefix` and whose value is the boolean `true`.
- **settings-store-target**: `SettingsStoreWindowStateStorage` MUST route every key through its injected `SettingsStore` with `isSecure == false`, so values land in the store's non-secure provider.
- **settings-store-change-signal**: Writes and removals through `SettingsStoreWindowStateStorage` MUST emit the key name on the store's `changes` publisher when the provider emits (the UserDefaults provider does); `UserDefaultsWindowStateStorage` emits nothing.
- **settings-store-non-bool-visibility**: When a visibility key exists but does not hold a boolean, `SettingsStoreWindowStateStorage.loadVisibility(for:)` MUST return `false` (the setting's default), whereas `UserDefaultsWindowStateStorage` returns `nil`.
- **storage-codec-failure**: NEEDS REVIEW: Not implemented in source. In both implementations a `PersistedWindowState` that fails to encode is silently not written, and stored data that fails to decode reads as `nil` (never saved), with no log or error to the caller; settling it needs a decision on whether codec failures are logged or surfaced.

### Namespace

- **namespace-default**: `WindowStateNamespace.current` MUST be the empty string until a host sets a namespace, so un-namespaced keys match the existing on-disk format.
- **namespace-qualify**: `qualify(_:)` MUST return `current + key`.
- **namespace-token**: `isolate(toPath:)` MUST set `current` to `Instance` + the lowercase hex of the first 4 bytes of the SHA-256 of the path's UTF-8 bytes + `_` (8 hex characters).
- **namespace-stable**: `isolate(toPath:)` MUST produce the same prefix for the same path on every call and launch.
- **namespace-no-raw-path**: The prefix MUST NOT contain any substring of the path.
- **namespace-bundle**: `isolateToRunningBundle(_:)` MUST call `isolate(toPath:)` with the bundle's standardized bundle-URL path, defaulting to the main bundle.
- **namespace-reset**: `reset()` MUST set `current` back to the empty string.
- **namespace-host-timing**: A host that wants isolation MUST call `isolateToRunningBundle()` before it first touches `WindowManager` (per the type's doc comment); keys written earlier stay under the previous prefix.

### Window screenshot

- **screenshot-capture**: `captureOwnWindow(_:)` MUST return a `CGImage` of the given window captured with `optionIncludingWindow`, `boundsIgnoreFraming` and `bestResolution` over a null rectangle, or `nil` when the capture fails.
- **screenshot-symbol-missing**: When the `CGWindowListCreateImage` symbol cannot be resolved at runtime, `captureOwnWindow(_:)` MUST return `nil` rather than crash.
- **screenshot-symbol-once**: The symbol MUST be resolved at most once per process.
- **screenshot-no-permission**: Own-window capture MUST NOT require or request Screen Recording permission.
- **screenshot-png-offscreen**: `writePNG(of:to:)` MUST return `false` and write nothing when the window's `windowNumber` is not positive.
- **screenshot-png-failure**: `writePNG(of:to:)` MUST return `false` when capture, PNG encoding or the file write fails.
- **screenshot-png-success**: `writePNG(of:to:)` MUST write PNG data to the URL and return `true` when every step succeeds.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens, passed to `WindowFrameManager`. |
| `storage` | `WindowStateStorage` | `SettingsStoreWindowStateStorage(settings: UserSettings.shared)` | Persistence for frames and visibility. |
| `screenManager` | `ScreenManager?` | `nil` (resolved to `ScreenManager.shared`) | Owner of the screen-set list and screen-change observer. |
| `keyPrefix` | `String` | `"WindowState_"` | Frame-state key prefix (both storage implementations). |
| `visibilityKeyPrefix` | `String` | `"WindowVisible_"` | Visibility key prefix (both storage implementations). |
| `settings` | `SettingsStore` | none (required) | Store backing `SettingsStoreWindowStateStorage`. |
| `UserSettings.recentWindowsCount` | `UserSetting<Int>` (`recentWindowsCount`) | `10` | Mirrored into `NSRecentDocumentsLimit`. |
| `UserSettings.reopenOnLaunchPolicy` | `UserSetting<ReopenOnLaunchPolicy>` (`reopenOnLaunchPolicy`) | `.useSystem` | Whether recent documents reopen at launch. |
| `NSQuitAlwaysKeepsWindows` | system user default (`Bool`) | `false` when absent | System default consulted by `.useSystem`. |
| `NSRecentDocumentsLimit` | user default (`Int`) | written by the manager | AppKit's recent-documents cap. |
| `WindowStateNamespace` | process-wide prefix | `""` | Set by `isolateToRunningBundle(_:)` / `isolate(toPath:)`, cleared by `reset()`. |
| restorable factories | `[String: @MainActor () -> Void]` | empty | Registered by the host via `registerRestorable(id:make:)`. |

## Privacy

- **Data collected**: Per window ID, a `PersistedWindowState` (frame placements per screen set, including display UUID and localized display name fingerprints) and a visibility boolean; document URLs passed to the system recent-documents list.
- **Storage**: Window state and visibility in the settings store's non-secure provider (UserDefaults by default) or directly in `UserDefaults.standard`; recents in AppKit's recent-documents store. The namespace prefix is a hash, so a build path never reaches the preferences file.
- **Transmission**: None from this component; a `SettingsStore` backed by the iCloud provider syncs these keys through that provider.
- **Retention**: Until removed by `removeState(for:)` / `removeVisibility(for:)` or the preferences domain is deleted; recents are capped by `NSRecentDocumentsLimit`.

