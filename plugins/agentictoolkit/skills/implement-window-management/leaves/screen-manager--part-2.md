<!-- leaf: implement-window-management/screen-manager--part-2 · source: window-management-screen-manager.md -->

# ScreenManager — continued (part 2)

**Rules** (cite as `implement-window-management/screen-manager--part-2#<slug>`):

- `upsert-existing` MUST
- `upsert-new` MUST
- `upsert-prune-on-persist` MUST
- `upsert-no-prune-without-persist` MUST
- `returning-set-keeps-first-seen` MUST
- `storage-settings-blob` MUST
- `log-on-change` MUST
- `no-other-side-effects` MUST
- `no-cancellation-or-timeout` MUST

### Set upsert, aging and persistence

- **upsert-existing**: Upserting a set already in `knownSets` MUST replace its `screens` with the current snapshots and set `lastSeen` to `now()`, leaving `id` and `firstSeen` unchanged.
- **upsert-new**: Upserting a set not in `knownSets` MUST append a `ScreenSet` with `firstSeen` and `lastSeen` both equal to `now()` and add its id to `knownSetIDs`.
- **upsert-prune-on-persist**: A persisting upsert MUST drop every set whose `now() - lastSeen` exceeds `maxSetAge` (a set exactly `maxSetAge` old is kept), rebuild `knownSetIDs` if any set was dropped, sort by `lastSeen` descending, then call `storage.saveSets(_:)` with the whole list.
- **upsert-no-prune-without-persist**: A non-persisting upsert MUST NOT prune, sort or rebuild `knownSetIDs`.
- **returning-set-keeps-first-seen**: Returning to a previously seen set MUST keep its original `firstSeen` and bump only `lastSeen`.
- **storage-settings-blob**: `SettingsStoreScreenSetStorage` MUST store the whole `[ScreenSet]` list as one Codable value under a single key (default `ScreenSets`) through the `SettingsStore` non-secure provider, with `[]` as the default when nothing is stored.
- **storage-failure-signal**: NEEDS REVIEW: Not implemented in source. `ScreenSetStorage` has no error channel; with the default `UserDefaultsSettingsStorageProvider`, an undecodable stored blob loads as `[]` and an unencodable list is silently not written, so a corrupt blob silently erases every known set (and every per-set placement keyed to it) at the next persist. Settle by deciding whether load/save failures must be logged or surfaced to the caller.

### Side effects

- **log-on-change**: Each delivered change MUST log exactly one info-level line of the form `ScreenManager: <change> → set '<currentSetID>'`, with both values marked public.
- **no-other-side-effects**: `ScreenManager` MUST have no side effects beyond the notification registration, `storage` calls, the change log line and observer calls: no network, no files of its own, no timers.
- **no-cancellation-or-timeout**: Every operation MUST run synchronously to completion on the main actor; there is no cancellation, timeout or retry.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens (`NSScreen.screens` in production). |
| `storage` | `ScreenSetStorage` | `SettingsStoreScreenSetStorage(settings: UserSettings.shared)` | Persistence for the known-set list. |
| `maxSetAge` | `TimeInterval` | `180 * 24 * 60 * 60` (180 days) | Sets unseen longer than this are dropped on load and on each persist. |
| `now` | `() -> Date` | `{ Date() }` | Injected clock for timestamps, aging and the touch throttle. |
| `SettingsStoreScreenSetStorage.key` | `String` | `"ScreenSets"` | Settings key holding the encoded `[ScreenSet]`. |
| `touchPersistInterval` | `TimeInterval` (private constant) | `60` | Minimum seconds between persists triggered by `touchCurrentSet()`. |

## Privacy

- **Data collected**: Per screen set, the member displays' UUIDs, system localized names, frames, visible frames, scale factors and `isMain`, plus `firstSeen` / `lastSeen` timestamps.
- **Storage**: One JSON-encoded blob under the `ScreenSets` key in the settings store's non-secure provider (UserDefaults by default).
- **Transmission**: None; nothing leaves the device (the log line goes to the unified log).
- **Retention**: Each set is kept until it has gone unseen for `maxSetAge` (180 days by default), then dropped at the next persist.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. A SwiftUI app would still host this `@MainActor` class (or an `@Observable` wrapper exposing `currentSetID` / `knownSets`) and pass it through the environment; SwiftUI offers no screen-parameters notification of its own, so the AppKit notification stays.
- **Compose**: Android has one display per activity in the common case; start from `DisplayManager` with `registerDisplayListener` (`onDisplayAdded` / `onDisplayRemoved` / `onDisplayChanged`) and `Display.getRealMetrics`, use `Display.getName` or unique ids for identity, persist with DataStore plus `kotlinx.serialization`, and run on `Dispatchers.Main`. Arrangement changes have no direct analogue.
- **React/Web**: Start from the Window Management API (`window.getScreenDetails()`, its `screenschange` event, and `ScreenDetailed.label` / `left` / `top` / `width` / `height` / `availWidth`), falling back to `window.screen` plus `resize`; persist with `localStorage` and `JSON.stringify`. Browsers expose no display UUIDs, so identity falls back to label plus geometry.
- **AppKit / UIKit**: Source files: `ScreenManager.swift` (AppKit `NSApplication.didChangeScreenParametersNotification`, selector-based `NotificationCenter` registration, `os.Logger`), `ScreenSnapshot.swift` (`CGRect` geometry, built from `ScreenInfo` whose real form wraps `NSScreen` and reads the UUID via `CGDisplayCreateUUIDFromDisplayID`), `ScreenSet.swift`, `ScreenChange.swift`, `ScreenSetStorage.swift` (`SettingsStore` backing). UIKit would use `UIScreen.didConnectNotification` / `didDisconnectNotification` or `UIWindowScene` screen changes; there is no desktop arrangement on iOS.
- **WinUI 3**: Enumerate displays with `Microsoft.UI.Windowing.DisplayArea.FindAll()` (`OuterBounds` for `frame`, `WorkArea` for `visibleFrame`, `DisplayId` for identity) and use the Win32 `EnumDisplayDevices` device-interface path when a stable monitor id is needed across reboots. Subscribe to screen changes via `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE` (`SPI_SETWORKAREA`) in the window procedure or `Windows.Devices.Display.DisplayMonitor` watchers with `DeviceWatcher`. Keep the manager on the UI thread (`DispatcherQueue`), expose `KnownSets` as an `ObservableCollection<ScreenSet>` and `CurrentSetId` through `INotifyPropertyChanged`, and replace observer tokens with a C# `event EventHandler<ScreenChange>`. Persist with `System.Text.Json` into `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value limit; use a `LocalFolder` file for large lists). Windows coordinates are top-left-origin, unlike AppKit's bottom-left; the classification logic is unaffected because it compares multisets only.

## Design Decisions

**Decision**: Set identity is display membership only (sorted UUIDs, name fallback), never resolution or position.
**Rationale**: A location is defined by which displays are attached; resolution and arrangement changes on the same desk must keep the same placements, and `identityComponent`'s doc comment makes a UUID-less display's resolution change a resolution change, not a set change.
**Approved**: pending

**Decision**: Geometry is compared as unordered multisets of size and origin keys instead of pairing screens.
**Rationale**: Per the `classifyChange` comment, two indistinguishable UUID-less displays would collide on an identity key and mis-pair, producing spurious classifications. The pooled frame/visible-frame multiset can in theory mask a swap (see Edge Cases); the source accepts that.
**Approved**: pending

**Decision**: The classification baseline (`lastNotifiedSnapshots`) is kept separate from the current snapshots.
**Rationale**: `touchCurrentSet()` may refresh the current snapshots before the notification arrives; diffing against those would report "nothing moved" and no window would be repositioned.
**Approved**: pending

**Decision**: `touchCurrentSet()` reconciles `currentSetID` with the live screens but never classifies or notifies.
**Rationale**: AppKit repositions windows during a reconfiguration and fires `saveFrame` before the notification; without reconciling, a placement lands under the wrong set's key. Notifying there would re-enter `saveFrame` through the reposition handlers.
**Approved**: pending

**Decision**: Touch persistence is throttled to once per 60 seconds, and prune/sort run only on persisting upserts.
**Rationale**: `touchCurrentSet()` runs on every window-drag tick; the in-memory record updates every call, while the 180-day aging scale and array order matter only for what is written.
**Approved**: pending

**Decision**: `knownSetIDs` is maintained alongside `knownSets`.
**Rationale**: `WindowFrameManager.saveFrame` reads it on every drag tick and needs an O(1) membership check without rebuilding a `Set`.
**Approved**: pending

**Decision**: `startObservingScreenChanges()` removes before adding.
**Rationale**: Selector-based `addObserver` adds a second registration instead of replacing the first, which would double-fire; removing first makes re-arming idempotent.
**Approved**: pending
