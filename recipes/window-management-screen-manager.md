---
id: 1e58add7-d85d-4e62-b857-c5e3203795be
title: ScreenManager
domain: agentictoolkit://recipes/window-management-screen-manager
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: macOS main-actor service that tracks the attached screen set, persists every
  set seen with timestamps, and classifies live screen changes.
platforms:
- swift
- macos
tags:
- window-management
- screens
- persistence
- macos
depends-on:
- agentictoolkit://recipes/settings-storage
related: []
references: []
approved-by: ''
approved-date: ''
---

# ScreenManager

## Overview

`ScreenManager` (in `ScreenManager.swift`, with its value types `ScreenChange`,
`ScreenSet`, `ScreenSnapshot` and the `ScreenSetStorage` protocol) owns
everything screen-related for the toolkit's window management on macOS:

- the identity of the set of displays attached right now (`currentSetID`);
- a persisted list of every screen set the machine has been attached to
  (`knownSets`), each with `firstSeen` / `lastSeen` timestamps, aged out after
  `maxSetAge` (default 180 days);
- classification of live screen-parameter changes into a `ScreenChange`
  (`resolutionChanged`, `arrangementChanged`, `screenSetChanged`) that it
  delivers to registered observers.

A "screen set" is the group of displays connected at one location: a laptop
that travels between home and office produces one set per desk.
`WindowFrameManager` keys window placements by `currentSetID`, so each window
remembers one position per location. Use `ScreenManager.shared` in production;
inject an isolated instance (mock `ScreenProvider`, in-memory
`ScreenSetStorage`, fixed clock) in tests.

## Behavioral Requirements

### Data shapes

- **screen-change-cases**: `ScreenChange` MUST be an `Equatable`, `Sendable` enum with exactly three cases: `resolutionChanged`, `arrangementChanged`, and `screenSetChanged(previousSetID: String, currentSetID: String)`.
- **screen-snapshot-fields**: `ScreenSnapshot` MUST be a `Codable`, `Equatable`, `Sendable` value holding `fingerprint` (`ScreenFingerprint`), `frame` and `visibleFrame` (`CGRect`, global bottom-left-origin desktop coordinates), and `backingScaleFactor` (`CGFloat`).
- **screen-snapshot-derived**: `ScreenSnapshot` MUST expose `displayUUID`, `localizedName` and `isMain` read straight from its `fingerprint`, so screen identity rules live only in `ScreenFingerprint`.
- **snapshot-from-screen-info**: `ScreenSnapshot.init(_ screen: ScreenInfo)` MUST copy the screen's `fingerprint`, `frame`, `visibleFrame` and `backingScaleFactor` unchanged.
- **identity-component-uuid**: A snapshot's `identityComponent` MUST be its `displayUUID` when one is present.
- **identity-component-name-fallback**: A snapshot without a `displayUUID` MUST use its `localizedName` as `identityComponent`, and the literal `unnamed-display` when the name is also absent.
- **identity-resolution-independent**: `identityComponent` MUST NOT include resolution, geometry or `isMain`, so a resolution change on a UUID-less display keeps the same set id.
- **screen-set-fields**: `ScreenSet` MUST be a `Codable`, `Equatable`, `Sendable` value with an immutable `id: String` and mutable `screens: [ScreenSnapshot]` (provider order), `firstSeen: Date` and `lastSeen: Date`.
- **set-identity-derivation**: `ScreenSet.identity(of:)` MUST return every snapshot's `identityComponent`, sorted ascending, joined with `+`.
- **set-identity-order-independent**: `ScreenSet.identity(of:)` MUST return the same string for the same snapshots in any enumeration order.
- **set-identity-empty**: `ScreenSet.identity(of:)` MUST return the empty string for an empty snapshot list.

### Isolation and ownership

- **main-actor-isolation**: `ScreenManager`, `ScreenSetStorage` and `SettingsStoreScreenSetStorage` MUST be `@MainActor`-isolated; every public operation and every observer handler runs on the main actor.
- **observer-handler-isolation**: Observer handlers MUST be typed `@MainActor (ScreenChange) -> Void`.
- **shared-instance**: `ScreenManager` MUST provide a process-wide `shared` instance built with the default initializer arguments.
- **single-owner-precondition**: Callers MUST NOT create a second `ScreenManager` on the same storage key in production; per the `WindowManager` authoring comment, a second instance "would clobber the real one's state and double-register the notification observer". `ScreenManager` itself does not detect or prevent a second instance.

### Initialization

- **init-snapshots**: `init` MUST snapshot `screenProvider.screens` once and use that list as both the current snapshots and the classification baseline.
- **init-current-set-id**: `init` MUST set `currentSetID` to `ScreenSet.identity(of:)` of the initial snapshots.
- **init-load-and-prune**: `init` MUST load the stored sets via `storage.loadSets()` and drop every set whose `lastSeen` is more than `maxSetAge` seconds before `now()`.
- **init-upsert-persist**: `init` MUST insert or refresh the current set (see set-upsert rules) and persist the list via `storage.saveSets(_:)` exactly as a persisting upsert does.
- **init-starts-observing**: `init` MUST register for `NSApplication.didChangeScreenParametersNotification` before returning.

### Queries

- **known-sets-order**: After every persisting upsert, `knownSets` MUST be sorted by `lastSeen`, most recent first.
- **known-set-ids-mirror**: `knownSetIDs` MUST contain exactly the ids in `knownSets`, readable in O(1) without rebuilding a set on each read.
- **current-set-lookup**: `currentSet` MUST return the `knownSets` entry whose `id` equals `currentSetID`, or `nil` when there is none.
- **read-only-state**: `knownSets`, `knownSetIDs` and `currentSetID` MUST be publicly readable and writable only by `ScreenManager`.

### Observers

- **add-observer-token**: `addObserver(_:)` MUST store the handler under a fresh `UUID` and return that token; the result MAY be discarded.
- **remove-observer**: `removeObserver(_:)` MUST stop delivery to the handler registered under the token; removing an unknown token MUST be a no-op.
- **observer-delivery-after-update**: Observers MUST be called only after `currentSetID` and the persisted set list have been updated for the change being delivered.
- **observer-delivery-order**: Observers MUST each be called once per delivered change; the order among observers is unspecified (dictionary iteration order).

### Change processing

- **notification-rearm-idempotent**: `startObservingScreenChanges()` MUST remove any existing registration of this instance for `NSApplication.didChangeScreenParametersNotification` before adding one, so calling it repeatedly leaves exactly one registration.
- **notification-drives-processing**: Each `NSApplication.didChangeScreenParametersNotification` MUST run `processScreenChange()`.
- **process-diff-baseline**: `processScreenChange()` MUST classify the live snapshots against the snapshots of the last processed notification (`lastNotifiedSnapshots`), not against snapshots refreshed by `touchCurrentSet()`.
- **process-updates-state-always**: `processScreenChange()` MUST update the current snapshots, `currentSetID` and the classification baseline to the live screens even when the classification is `nil`.
- **process-spurious-silent**: When classification returns `nil`, `processScreenChange()` MUST NOT upsert, persist, log or notify.
- **process-real-change**: When classification returns a change, `processScreenChange()` MUST perform a persisting upsert of the current set, log one info line, then call every observer with that change.

### Classification

- **classify-set-change-first**: `classifyChange(from:to:)` MUST return `screenSetChanged(previousSetID:currentSetID:)` carrying the old and new identities whenever `ScreenSet.identity(of:)` differs between the two lists, regardless of geometry.
- **classify-resolution**: With equal identities, `classifyChange` MUST return `resolutionChanged` when the multiset of sizes differs, where the multiset pools every snapshot's `frame.size` and `visibleFrame.size` keyed as `"<width>x<height>"`.
- **classify-arrangement**: With equal identities and equal size multisets, `classifyChange` MUST return `arrangementChanged` when the multiset of origins differs, where the multiset pools every `frame.origin` and `visibleFrame.origin` keyed as `"<x>,<y>"`.
- **classify-no-change**: `classifyChange` MUST return `nil` when identities, size multisets and origin multisets are all equal.
- **classify-no-pairing**: `classifyChange` MUST compare geometry as unordered multisets and MUST NOT pair individual screens between the two lists, so indistinguishable displays cannot be mis-paired.
- **classify-visible-frame-counts**: A change to only a screen's `visibleFrame` size (for example the Dock growing) MUST classify as `resolutionChanged`.

### Touch and reconcile

- **touch-reconcile-first**: `touchCurrentSet()` MUST first reconcile `currentSetID` with the live screens, then upsert the current set.
- **reconcile-cheap-guard**: Reconcile MUST return without rebuilding snapshots when the live screen count equals the current snapshot count and every live `frame` equals the current snapshot's `frame` in order; `visibleFrame` is excluded from this comparison.
- **reconcile-refresh**: When the frame lists differ, reconcile MUST rebuild the current snapshots from the live screens and recompute `currentSetID`.
- **reconcile-no-notify**: Reconcile MUST NOT classify, notify observers, or move the classification baseline, so a later `processScreenChange()` still classifies against the pre-reconcile baseline.
- **touch-in-memory-every-call**: Every `touchCurrentSet()` call MUST update the current set's `screens` and `lastSeen` in memory.
- **touch-persist-throttle**: `touchCurrentSet()` MUST persist only when no touch has persisted yet or at least 60 seconds have passed since the last persisting touch; the first touch after `init` always persists.
- **touch-throttle-independent**: The touch throttle MUST track only persists made by `touchCurrentSet()`; persists from `init` and `processScreenChange()` MUST NOT reset it.

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

## Appearance

Not applicable — this is a main-actor screen-tracking and persistence service, not a visual component.

## States

Not applicable — this is a main-actor screen-tracking and persistence service, not a visual component.

## Accessibility

Not applicable — this is a main-actor screen-tracking and persistence service, not a visual component.

## Conformance Test Vectors

Derived from `ScreenManagerTests.swift`. Screens: B = uuid `BUILTIN`, name `Built-in`, frame (0,0,1920,1080), main; E = uuid `EXTERNAL`, name `LG Monitor`, frame (1920,0,2560,1440).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| screen-manager-001 | set-identity-order-independent, set-identity-derivation | `identity(of: [B, E])` vs `identity(of: [E, B])` | Equal strings (`BUILTIN+EXTERNAL`) |
| screen-manager-002 | identity-resolution-independent, identity-component-uuid | `identity(of: [B])` vs same uuid at 2560×1440 | Equal |
| screen-manager-003 | set-identity-derivation | `identity(of: [B])` vs `identity(of: [B, E])` | Not equal |
| screen-manager-004 | init-current-set-id, init-upsert-persist, upsert-new, current-set-lookup | Init with [B], clock fixed at t=1,000,000 | `knownSets.count == 1`; `currentSet.id == currentSetID`; `firstSeen == lastSeen == t`; one snapshot with `displayUUID == "BUILTIN"`; storage holds exactly that id |
| screen-manager-005 | touch-in-memory-every-call, upsert-existing | Init at t; clock → t+3600; `touchCurrentSet()` | `firstSeen == t`; `lastSeen == t+3600` |
| screen-manager-006 | init-load-and-prune | Storage has `STALE` (lastSeen now−200 days) and `FRESH` (lastSeen now−1 day); default `maxSetAge`; init with [B] | `knownSetIDs` lacks `STALE`, contains `FRESH` and `currentSetID` |
| screen-manager-007 | classify-no-change | `classifyChange(from: [B,E], to: [B,E])` | `nil` |
| screen-manager-008 | classify-resolution | [B] → B at 2560×1440 | `resolutionChanged` |
| screen-manager-009 | classify-arrangement | [B,E] → [B, E at x = −2560] | `arrangementChanged` |
| screen-manager-010 | classify-set-change-first | [B] → [B,E] | `screenSetChanged(previousSetID: identity([B]), currentSetID: identity([B,E]))` |
| screen-manager-011 | identity-component-name-fallback, classify-resolution | UUID-less `Dock HDMI` 1920×1080 → 2560×1440 | Identities equal; `resolutionChanged` |
| screen-manager-012 | classify-no-pairing, classify-no-change | Two UUID-less `Twin` screens at x=0 and x=1920, unchanged | `nil` |
| screen-manager-013 | classify-no-pairing, classify-arrangement | Twins: second moves from x=1920 to x=3840 | `arrangementChanged` |
| screen-manager-014 | process-real-change, observer-delivery-after-update, known-sets-order | Init [B]; add observer; provider → [B,E]; `processScreenChange()` | Observer receives exactly one `screenSetChanged(solo, docked)`; `currentSetID` read inside the handler equals docked; storage ids = {solo, docked}; `knownSets.first.id == docked` |
| screen-manager-015 | process-spurious-silent | Init [B]; add observer; `processScreenChange()` with no screen change | Observer not called |
| screen-manager-016 | remove-observer | Add then remove observer; provider → [B,E]; `processScreenChange()` | Observer not called |
| screen-manager-017 | reconcile-refresh, touch-persist-throttle | Init [B]; provider → [B,E]; `touchCurrentSet()` (no notification) | `currentSetID == identity([B,E])`; storage contains the docked set |
| screen-manager-018 | reconcile-no-notify, process-diff-baseline | Vector 017 with an observer, then `processScreenChange()` | No call after the touch; after processing, exactly one `screenSetChanged(solo, docked)` |
| screen-manager-019 | reconcile-cheap-guard, upsert-existing | Init [B,E]; call `touchCurrentSet()` 5 times | `currentSetID` unchanged; exactly one `knownSets` entry with that id |
| screen-manager-020 | returning-set-keeps-first-seen | Init [B] at t; t+3600 → [B,E] processed; t+7200 → [B] processed | `currentSetID == solo`; `firstSeen == t`; `lastSeen == t+7200` |
| screen-manager-021 | touch-persist-throttle | Init at t; `touchCurrentSet()` at t (persists); change screens so `screens` differ; `touchCurrentSet()` at t+30 | Second touch updates memory but makes no `saveSets` call; a touch at t+60 calls `saveSets` |
| screen-manager-022 | notification-rearm-idempotent | Call `startObservingScreenChanges()` three times; post `didChangeScreenParametersNotification` after a set change | Observer called exactly once |
| screen-manager-023 | upsert-prune-on-persist | Storage set lastSeen exactly `maxSetAge` before `now()`; init | Set is kept |
| screen-manager-024 | classify-visible-frame-counts | Same frames; one screen's `visibleFrame` height drops by 80 | `resolutionChanged` |
| screen-manager-025 | storage-settings-blob | `SettingsStoreScreenSetStorage` over an empty store; `loadSets()` | `[]` |

Vectors 021–025 are not in `ScreenManagerTests.swift`; they are derived from `touchCurrentSet()`, `startObservingScreenChanges()`, `pruned(_:olderThan:now:)`, `classifyChange(from:to:)` and `ScreenSetsSetting.defaultValue` respectively.

## Edge Cases

- **No screens attached**: The provider returns `[]` (MUST): the set id is the empty string and a `ScreenSet` with id `""` and no screens is recorded and persisted like any other.
- **UUID-less and unnamed display**: A snapshot with neither `displayUUID` nor `localizedName` (MUST) contributes `unnamed-display`; two such displays yield `unnamed-display+unnamed-display`.
- **Indistinguishable displays**: Two displays with the same identity component (MUST) share one component each in the id and are never paired individually; only the multiset of geometry matters.
- **Frame/visible-frame pooling**: Because `frame` and `visibleFrame` sizes (and origins) share one multiset (MUST), a change in which one screen's frame size equals another's former visible-frame size and vice versa cancels out and classifies as `nil`.
- **Spurious notification**: A notification with no geometry or membership change (MUST) produces no persist, log or observer call, but still refreshes the baseline and `currentSetID`.
- **Change seen first by touch**: A screen change observed by `touchCurrentSet()` before the notification (MUST) updates `currentSetID` and records the new set, and the following notification still delivers the change.
- **Membership change with identical frames**: Reconcile's guard (MUST) treats an identical frame list as an identical set; the source asserts membership cannot change without the frame list changing, so a swap between displays with identical frames is not reconciled until the notification arrives.
- **Dock-only change during touch**: A `visibleFrame`-only change (MUST) does not trigger reconcile's snapshot rebuild; the snapshots are refreshed on the next notification.
- **Aging boundary**: A set exactly `maxSetAge` old (MUST) is kept; one second older is dropped at the next persist.
- **Non-persisting aging**: Between persists (MUST) aged-out sets remain in `knownSets` and `knownSetIDs`; they are dropped only at the next persisting upsert.
- **Zero or negative `maxSetAge`**: `maxSetAge` is not validated (MUST): with 0, every set other than the current one is dropped at each persist; with a negative value, the current set is also dropped, leaving `currentSet` `nil`.
- **Corrupt or unwritable storage**: See the open question on storage-failure-signal: load yields `[]` and save is skipped with no signal.
- **Second instance**: A second `ScreenManager` on the same key (MUST NOT be created) overwrites the first's persisted list on every persist; nothing in the source detects it.
- **Observer mutating observers**: A handler that adds or removes observers during delivery (MUST) does not affect the current delivery, which iterates a copy of the handler collection.
- **Concurrent access**: Not applicable as a race: the type is `@MainActor`, so all calls are serialized on the main actor.
- **Offline / network**: Not applicable: the component performs no network I/O.
- **Cancellation and timeouts**: Not applicable: every operation is synchronous and bounded by the number of screens and known sets.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `screenProvider` | `ScreenProvider` | `RealScreenProvider()` | Source of live screens (`NSScreen.screens` in production). |
| `storage` | `ScreenSetStorage` | `SettingsStoreScreenSetStorage(settings: UserSettings.shared)` | Persistence for the known-set list. |
| `maxSetAge` | `TimeInterval` | `180 * 24 * 60 * 60` (180 days) | Sets unseen longer than this are dropped on load and on each persist. |
| `now` | `() -> Date` | `{ Date() }` | Injected clock for timestamps, aging and the touch throttle. |
| `SettingsStoreScreenSetStorage.key` | `String` | `"ScreenSets"` | Settings key holding the encoded `[ScreenSet]`. |
| `touchPersistInterval` | `TimeInterval` (private constant) | `60` | Minimum seconds between persists triggered by `touchCurrentSet()`. |

## Deep Linking

Not applicable: `ScreenManager` exposes no routes or URL handling; it is driven only by screen notifications and direct calls.

## Localization

Not applicable: the component produces no user-facing strings; its only text is the developer log line and identity strings built from display UUIDs and system-provided localized display names.

## Accessibility Options

Not applicable: `ScreenManager` renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; screen tracking starts unconditionally in `init`.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per screen set, the member displays' UUIDs, system localized names, frames, visible frames, scale factors and `isMain`, plus `firstSeen` / `lastSeen` timestamps.
- **Storage**: One JSON-encoded blob under the `ScreenSets` key in the settings store's non-secure provider (UserDefaults by default).
- **Transmission**: None; nothing leaves the device (the log line goes to the unified log).
- **Retention**: Each set is kept until it has gone unseen for `maxSetAge` (180 days by default), then dropped at the next persist.

## Logging

Subsystem: main bundle identifier (via `Loggable`) | Category: `ScreenManager`

| Event | Level | Message |
|-------|-------|---------|
| Delivered screen change | info | `ScreenManager: <change> → set '<currentSetID>'` (both values public) |

Spurious notifications, touches, reconciles, loads and saves are not logged.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | Performance |
| [data-retention-policy](agenticdevelopercookbook://compliance/privacy-and-data#data-retention-policy) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

separation-of-concerns passes because screen enumeration (`ScreenProvider`), persistence (`ScreenSetStorage`), identity (`ScreenFingerprint` / `identityComponent`) and classification (`classifyChange`) each sit behind their own type or pure function. unit-test-coverage is partial: `ScreenManagerTests.swift` covers identity, init persistence, aging on load, all classification outcomes, observer delivery and removal, and reconcile, but not the 60-second touch throttle, notification re-arm idempotence or the exact aging boundary. explicit-error-handling fails because storage load/save failures are absorbed without a signal (the open question on storage-failure-signal). data-integrity is partial for the same reason: a corrupt blob is replaced by the current set on the next persist. idempotent-operations passes because re-arming observation and repeated touches with unchanged screens leave state unchanged. state-recovery passes because the known-set list is reloaded and pruned on every launch. main-thread-freedom passes because the main-actor work is bounded by the screen and set counts, and the drag-tick hot path short-circuits on an unchanged frame list without sorting, pruning or persisting. resource-efficiency passes for the same throttle and guard. data-retention-policy passes because sets age out after `maxSetAge`. no-pii-in-logs passes because the single log line carries only the change kind and a set id built from display UUIDs or display names.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from `ScreenManager.swift`, `ScreenChange.swift`, `ScreenSet.swift`, `ScreenSetStorage.swift`, `ScreenSnapshot.swift` and `ScreenManagerTests.swift` |
