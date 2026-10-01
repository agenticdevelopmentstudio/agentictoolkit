---
id: 1e58add7-d85d-4e62-b857-c5e3203795be
title: Screen Manager
domain: agentictoolkit://cookbook/ui/windows/screen-manager
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A service that tracks the attached screen set, persists every set seen
  with timestamps, and classifies live screen changes.
platforms:
- swift
- macos
tags:
- window-management
- screens
- persistence
depends-on:
- agentictoolkit://cookbook/foundation/settings-storage
related: []
references: []
approved-by: ''
approved-date: ''
---

# Screen Manager

## Overview

This service owns everything screen-related for the toolkit's window
management:

- the identity of the set of displays attached right now;
- a persisted list of every screen set the machine has been attached to,
  each with first-seen and last-seen timestamps, aged out after a
  configurable maximum age (default 180 days);
- classification of live screen-parameter changes into one of three change
  kinds — a resolution change, an arrangement change, or a screen-set
  change — that it delivers to registered observers.

A "screen set" is the group of displays connected at one location: a laptop
that travels between home and office produces one set per desk. The window
frame manager keys window placements by the current set's identity, so each
window remembers one position per location. Use the shared instance in
production; inject an isolated instance (a mock screen provider, in-memory
set storage, a fixed clock) in tests.

## Behavioral Requirements

### Data shapes

- **screen-change-cases**: A screen change MUST be a value type, safe to compare for equality and pass across concurrency boundaries, with exactly three cases: a resolution change, an arrangement change, and a screen-set change carrying a previous set identity and a current set identity.
- **screen-snapshot-fields**: A screen snapshot MUST be a value type, encodable and comparable for equality, holding a fingerprint (the display's identity information), a frame and a visible frame (global, bottom-left-origin desktop coordinates), and a backing scale factor.
- **screen-snapshot-derived**: A screen snapshot MUST expose a display UUID, a localized name and a main-display flag read straight from its fingerprint, so screen identity rules live only in that fingerprint.
- **snapshot-from-screen-info**: Constructing a snapshot from a live screen description MUST copy that screen's fingerprint, frame, visible frame and backing scale factor unchanged.
- **identity-component-uuid**: A snapshot's identity component MUST be its display UUID when one is present.
- **identity-component-name-fallback**: A snapshot without a display UUID MUST use its localized name as its identity component, and the literal `unnamed-display` when the name is also absent.
- **identity-resolution-independent**: A snapshot's identity component MUST NOT include resolution, geometry or main-display status, so a resolution change on a UUID-less display keeps the same set id.
- **screen-set-fields**: A screen set MUST be a value type, encodable and comparable for equality, with an immutable id, a mutable list of screen snapshots (provider order), a first-seen timestamp and a last-seen timestamp.
- **set-identity-derivation**: Computing a set's identity MUST join every member snapshot's identity component, sorted ascending, with `+`.
- **set-identity-order-independent**: Computing a set's identity MUST return the same string for the same snapshots in any enumeration order.
- **set-identity-empty**: Computing a set's identity MUST return the empty string for an empty snapshot list.

### Isolation and ownership

- **single-thread-isolation**: The manager and its storage seam MUST be confined to a single designated thread; every public operation and every observer handler runs there.
- **observer-handler-isolation**: Observer handlers MUST be invoked on that same single designated thread.
- **shared-instance**: The manager MUST provide a process-wide shared instance built with the default initialization arguments.
- **single-owner-precondition**: Callers MUST NOT create a second manager instance on the same storage key in production; a second instance would clobber the real one's state and double-register the change-notification observer. The manager itself does not detect or prevent a second instance.

### Initialization

- **init-snapshots**: Constructing the manager MUST capture the live screen list once and use that list as both the current snapshots and the classification baseline.
- **init-current-set-id**: Constructing the manager MUST set the current set identity to the computed identity of the initial snapshots.
- **init-load-and-prune**: Constructing the manager MUST load the stored sets and drop every set whose last-seen timestamp is more than the maximum age before the current time.
- **init-upsert-persist**: Constructing the manager MUST insert or refresh the current set (see set-upsert rules) and persist the list exactly as a persisting upsert does.
- **init-starts-observing**: Constructing the manager MUST register to observe screen-parameter changes before returning.

### Queries

- **known-sets-order**: After every persisting upsert, the known-sets list MUST be sorted by last-seen, most recent first.
- **known-set-ids-mirror**: The known-set-ids collection MUST contain exactly the ids in the known-sets list, readable in constant time without rebuilding a set on each read.
- **current-set-lookup**: The current-set query MUST return the known-sets entry whose id equals the current set identity, or nothing when there is none.
- **read-only-state**: The known-sets list, the known-set-ids collection and the current set identity MUST be publicly readable and writable only by the manager itself.

### Observers

- **add-observer-token**: Adding an observer MUST store the handler under a freshly generated token and return that token; the caller MAY discard the result.
- **remove-observer**: Removing an observer MUST stop delivery to the handler registered under the token; removing an unknown token MUST be a no-op.
- **observer-delivery-after-update**: Observers MUST be called only after the current set identity and the persisted set list have been updated for the change being delivered.
- **observer-delivery-order**: Observers MUST each be called once per delivered change; the order among observers is unspecified.

### Change processing

- **notification-rearm-idempotent**: Starting to observe screen changes MUST remove any existing registration for this instance before adding one, so calling it repeatedly leaves exactly one registration.
- **notification-drives-processing**: Each screen-parameter-change notification MUST trigger processing of the screen change.
- **process-diff-baseline**: Processing a screen change MUST classify the live snapshots against the snapshots of the last processed notification, not against snapshots refreshed by a touch (see Touch and reconcile).
- **process-updates-state-always**: Processing a screen change MUST update the current snapshots, the current set identity and the classification baseline to the live screens even when classification finds no change.
- **process-spurious-silent**: When classification finds no change, processing MUST NOT upsert, persist, log or notify.
- **process-real-change**: When classification finds a change, processing MUST perform a persisting upsert of the current set, log one info line, then call every observer with that change.

### Classification

- **classify-set-change-first**: Classifying a change MUST return a screen-set change carrying the old and new identities whenever the computed set identity differs between the two lists, regardless of geometry.
- **classify-resolution**: With equal identities, classification MUST return a resolution change when the multiset of sizes differs, where the multiset pools every snapshot's frame size and visible-frame size keyed as `"<width>x<height>"`.
- **classify-arrangement**: With equal identities and equal size multisets, classification MUST return an arrangement change when the multiset of origins differs, where the multiset pools every frame origin and visible-frame origin keyed as `"<x>,<y>"`.
- **classify-no-change**: Classification MUST return no change when identities, size multisets and origin multisets are all equal.
- **classify-no-pairing**: Classification MUST compare geometry as unordered multisets and MUST NOT pair individual screens between the two lists, so indistinguishable displays cannot be mis-paired.
- **classify-visible-frame-counts**: A change to only a screen's visible-frame size (for example a system-reserved area growing) MUST classify as a resolution change.

### Touch and reconcile

- **touch-reconcile-first**: Touching the current set MUST first reconcile the current set identity with the live screens, then upsert the current set.
- **reconcile-cheap-guard**: Reconciling MUST return without rebuilding snapshots when the live screen count equals the current snapshot count and every live frame equals the current snapshot's frame in order; the visible frame is excluded from this comparison.
- **reconcile-refresh**: When the frame lists differ, reconciling MUST rebuild the current snapshots from the live screens and recompute the current set identity.
- **reconcile-no-notify**: Reconciling MUST NOT classify, notify observers, or move the classification baseline, so a later processing pass still classifies against the pre-reconcile baseline.
- **touch-in-memory-every-call**: Every touch MUST update the current set's screens and last-seen timestamp in memory.
- **touch-persist-throttle**: Touching MUST persist only when no touch has persisted yet or at least 60 seconds have passed since the last persisting touch; the first touch after construction always persists.
- **touch-throttle-independent**: The touch throttle MUST track only persists made by touching; persists made during construction and during change processing MUST NOT reset it.

### Set upsert, aging and persistence

- **upsert-existing**: Upserting a set already in the known-sets list MUST replace its screens with the current snapshots and set its last-seen timestamp to the current time, leaving its id and first-seen timestamp unchanged.
- **upsert-new**: Upserting a set not in the known-sets list MUST append a new set with first-seen and last-seen both equal to the current time and add its id to the known-set-ids collection.
- **upsert-prune-on-persist**: A persisting upsert MUST drop every set whose age (current time minus last-seen) exceeds the maximum age (a set exactly the maximum age old is kept), rebuild the known-set-ids collection if any set was dropped, sort by last-seen descending, then persist the whole list.
- **upsert-no-prune-without-persist**: A non-persisting upsert MUST NOT prune, sort or rebuild the known-set-ids collection.
- **returning-set-keeps-first-seen**: Returning to a previously seen set MUST keep its original first-seen timestamp and bump only its last-seen timestamp.
- **storage-settings-blob**: The settings-backed storage MUST store the whole set list as one encoded value under a single key (default `ScreenSets`) in the settings store's non-secure provider, with an empty list as the default when nothing is stored.
- **storage-failure-signal**: NEEDS REVIEW: Not implemented in source. The storage seam has no error channel; with the default settings provider, an undecodable stored blob loads as an empty list and an unencodable list is silently not written, so a corrupt blob silently erases every known set (and every per-set placement keyed to it) at the next persist. Settle by deciding whether load/save failures must be logged or surfaced to the caller.

### Side effects

- **log-on-change**: Each delivered change MUST log exactly one info-level line of the form `ScreenManager: <change> → set '<currentSetID>'`, with both values marked public.
- **no-other-side-effects**: The manager MUST have no side effects beyond the change-notification registration, storage calls, the change log line and observer calls: no network, no files of its own, no timers.
- **no-cancellation-or-timeout**: Every operation MUST run synchronously to completion on that single designated thread; there is no cancellation, timeout or retry.

## Appearance

Not applicable — this is a screen-tracking and persistence service, not a visual component.

## States

Not applicable — this is a screen-tracking and persistence service, not a visual component.

## Accessibility

Not applicable — this is a screen-tracking and persistence service, not a visual component.

## Conformance Test Vectors

Derived from the reference test suite. Screens: B = uuid `BUILTIN`, name
`Built-in`, frame (0,0,1920,1080), main; E = uuid `EXTERNAL`, name `LG
Monitor`, frame (1920,0,2560,1440).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| screen-manager-001 | set-identity-order-independent, set-identity-derivation | Compute the set identity of [B, E] and of [E, B] | Equal strings (`BUILTIN+EXTERNAL`) |
| screen-manager-002 | identity-resolution-independent, identity-component-uuid | Compute the set identity of [B] and of B at 2560×1440 (same UUID) | Equal |
| screen-manager-003 | set-identity-derivation | Compute the set identity of [B] and of [B, E] | Not equal |
| screen-manager-004 | init-current-set-id, init-upsert-persist, upsert-new, current-set-lookup | Init with [B], clock fixed at t=1,000,000 | Known-sets count is 1; the current set's id equals the current set identity; first-seen equals last-seen equals t; one snapshot with display UUID `BUILTIN`; storage holds exactly that id |
| screen-manager-005 | touch-in-memory-every-call, upsert-existing | Init at t; clock → t+3600; touch the current set | First-seen equals t; last-seen equals t+3600 |
| screen-manager-006 | init-load-and-prune | Storage has `STALE` (last-seen now−200 days) and `FRESH` (last-seen now−1 day); default maximum age; init with [B] | Known-set-ids lacks `STALE`, contains `FRESH` and the current set identity |
| screen-manager-007 | classify-no-change | Classify from [B,E] to [B,E] | No change |
| screen-manager-008 | classify-resolution | [B] → B at 2560×1440 | A resolution change |
| screen-manager-009 | classify-arrangement | [B,E] → [B, E at x = −2560] | An arrangement change |
| screen-manager-010 | classify-set-change-first | [B] → [B,E] | A screen-set change carrying the previous identity (identity of [B]) and current identity (identity of [B,E]) |
| screen-manager-011 | identity-component-name-fallback, classify-resolution | UUID-less `Dock HDMI` 1920×1080 → 2560×1440 | Identities equal; a resolution change |
| screen-manager-012 | classify-no-pairing, classify-no-change | Two UUID-less `Twin` screens at x=0 and x=1920, unchanged | No change |
| screen-manager-013 | classify-no-pairing, classify-arrangement | Twins: second moves from x=1920 to x=3840 | An arrangement change |
| screen-manager-014 | process-real-change, observer-delivery-after-update, known-sets-order | Init [B]; add observer; provider → [B,E]; process the screen change | Observer receives exactly one screen-set change (solo to docked); the current set identity read inside the handler equals docked; storage ids = {solo, docked}; the most recent known-sets entry's id equals docked |
| screen-manager-015 | process-spurious-silent | Init [B]; add observer; process a notification with no screen change | Observer not called |
| screen-manager-016 | remove-observer | Add then remove observer; provider → [B,E]; process the screen change | Observer not called |
| screen-manager-017 | reconcile-refresh, touch-persist-throttle | Init [B]; provider → [B,E]; touch the current set (no notification) | Current set identity equals identity of [B,E]; storage contains the docked set |
| screen-manager-018 | reconcile-no-notify, process-diff-baseline | Vector 017 with an observer, then process the screen change | No call after the touch; after processing, exactly one screen-set change (solo to docked) |
| screen-manager-019 | reconcile-cheap-guard, upsert-existing | Init [B,E]; touch the current set 5 times | Current set identity unchanged; exactly one known-sets entry with that id |
| screen-manager-020 | returning-set-keeps-first-seen | Init [B] at t; t+3600 → [B,E] processed; t+7200 → [B] processed | Current set identity equals solo; first-seen equals t; last-seen equals t+7200 |
| screen-manager-021 | touch-persist-throttle | Init at t; touch at t (persists); change screens so screens differ; touch at t+30 | Second touch updates memory but makes no persist call; a touch at t+60 persists |
| screen-manager-022 | notification-rearm-idempotent | Call start-observing three times; post a screen-parameter-change notification after a set change | Observer called exactly once |
| screen-manager-023 | upsert-prune-on-persist | Storage set last-seen exactly the maximum age before the current time; init | Set is kept |
| screen-manager-024 | classify-visible-frame-counts | Same frames; one screen's visible frame height drops by 80 | A resolution change |
| screen-manager-025 | storage-settings-blob | The settings-backed storage over an empty store; load the sets | `[]` |

Vectors 021–025 are not in the reference test suite; they are derived from
the touch operation, the observation-start operation, the pruning function,
the classification function and the storage default value respectively.

## Edge Cases

- **No screens attached**: The provider returns `[]` (MUST): the set id is the empty string and a set with id `""` and no screens is recorded and persisted like any other.
- **UUID-less and unnamed display**: A snapshot with neither a display UUID nor a localized name (MUST) contributes `unnamed-display`; two such displays yield `unnamed-display+unnamed-display`.
- **Indistinguishable displays**: Two displays with the same identity component (MUST) share one component each in the id and are never paired individually; only the multiset of geometry matters.
- **Frame/visible-frame pooling**: Because frame and visible-frame sizes (and origins) share one multiset (MUST), a change in which one screen's frame size equals another's former visible-frame size and vice versa cancels out and classifies as no change.
- **Spurious notification**: A notification with no geometry or membership change (MUST) produces no persist, log or observer call, but still refreshes the baseline and the current set identity.
- **Change seen first by touch**: A screen change observed by a touch before the notification (MUST) updates the current set identity and records the new set, and the following notification still delivers the change.
- **Membership change with identical frames**: Reconcile's guard (MUST) treats an identical frame list as an identical set; the source asserts membership cannot change without the frame list changing, so a swap between displays with identical frames is not reconciled until the notification arrives.
- **Dock-only change during touch**: A visible-frame-only change (MUST) does not trigger reconcile's snapshot rebuild; the snapshots are refreshed on the next notification.
- **Aging boundary**: A set exactly the maximum age old (MUST) is kept; one second older is dropped at the next persist.
- **Non-persisting aging**: Between persists (MUST) aged-out sets remain in the known-sets list and the known-set-ids collection; they are dropped only at the next persisting upsert.
- **Zero or negative maximum age**: The maximum age is not validated (MUST): with zero, every set other than the current one is dropped at each persist; with a negative value, the current set is also dropped, leaving the current-set query with nothing to return.
- **Corrupt or unwritable storage**: See the open question on storage-failure-signal: load yields `[]` and save is skipped with no signal.
- **Second instance**: A second manager instance on the same storage key (MUST NOT be created) overwrites the first's persisted list on every persist; nothing in the source detects it.
- **Observer mutating observers**: A handler that adds or removes observers during delivery (MUST) does not affect the current delivery, which iterates a copy of the handler collection.
- **Concurrent access**: Not applicable as a race: the manager is confined to a single designated thread, so all calls are serialized.
- **Offline / network**: Not applicable: the component performs no network I/O.
- **Cancellation and timeouts**: Not applicable: every operation is synchronous and bounded by the number of screens and known sets.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Screen provider | Injected provider | the platform's live-screen provider | Source of live screens. |
| Storage | Injected provider | the settings-backed storage, over the shared settings store | Persistence for the known-set list. |
| Maximum set age | Duration | 180 days | Sets unseen longer than this are dropped on load and on each persist. |
| Clock | Injected clock | the system clock | Injected clock for timestamps, aging and the touch throttle. |
| Settings key | Text (private constant) | `"ScreenSets"` | Settings key holding the encoded set list. |
| Touch persist interval | Duration (private constant) | 60 seconds | Minimum time between persists triggered by a touch. |

## Deep Linking

Not applicable: the manager exposes no routes or URL handling; it is driven only by screen notifications and direct calls.

## Localization

Not applicable: the component produces no user-facing strings; its only text is the developer log line and identity strings built from display UUIDs and system-provided localized display names.

## Accessibility Options

Not applicable: the manager renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; screen tracking starts unconditionally when the manager is constructed.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

- **Data collected**: Per screen set, the member displays' UUIDs, system localized names, frames, visible frames, scale factors and main-display flags, plus first-seen / last-seen timestamps.
- **Storage**: One JSON-encoded blob under the `ScreenSets` key in the settings store's non-secure provider (the platform's standard preferences store by default).
- **Transmission**: None; nothing leaves the device (the log line goes to the unified log).
- **Retention**: Each set is kept until it has gone unseen for the maximum age (180 days by default), then dropped at the next persist.

## Logging

Subsystem: main bundle identifier | Category: `ScreenManager`

| Event | Level | Message |
|-------|-------|---------|
| Delivered screen change | info | `ScreenManager: <change> → set '<currentSetID>'` (both values public) |

Spurious notifications, touches, reconciles, loads and saves are not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI in the source. A SwiftUI app would still host this `@MainActor` class (or an `@Observable` wrapper exposing `currentSetID` / `knownSets`) and pass it through the environment; SwiftUI offers no screen-parameters notification of its own, so the AppKit notification stays.
- **Compose**: Android has one display per activity in the common case; start from `DisplayManager` with `registerDisplayListener` (`onDisplayAdded` / `onDisplayRemoved` / `onDisplayChanged`) and `Display.getRealMetrics`, use `Display.getName` or unique ids for identity, persist with DataStore plus `kotlinx.serialization`, and run on `Dispatchers.Main`. Arrangement changes have no direct analogue.
- **React/Web**: Start from the Window Management API (`window.getScreenDetails()`, its `screenschange` event, and `ScreenDetailed.label` / `left` / `top` / `width` / `height` / `availWidth`), falling back to `window.screen` plus `resize`; persist with `localStorage` and `JSON.stringify`. Browsers expose no display UUIDs, so identity falls back to label plus geometry.
- **AppKit / UIKit**: This is the source's own platform, and Swift throughout: `ScreenManager` (`ScreenManager.swift`), `ScreenChange`, `ScreenSet`, `ScreenSnapshot` and the `ScreenSetStorage` protocol, with `SettingsStoreScreenSetStorage` as its production implementation (`ScreenSetStorage.swift`, backed by `SettingsStore`, default key `"ScreenSets"`) and `ScreenProvider` / `RealScreenProvider` (wrapping `NSScreen.screens`) as the live-screen seam. `ScreenManager`, `ScreenSetStorage` and `SettingsStoreScreenSetStorage` are `@MainActor`-isolated (single-thread-isolation), and observer handlers are typed `@MainActor (ScreenChange) -> Void`. Screen-parameter changes arrive via AppKit's `NSApplication.didChangeScreenParametersNotification`, registered selector-based through `NotificationCenter`. `ScreenSnapshot.swift` uses `CGRect` geometry (bottom-left-origin, unlike Windows) and is built from `ScreenInfo`, whose real form wraps `NSScreen` and reads the UUID via `CGDisplayCreateUUIDFromDisplayID`. The single log line goes through `os.Logger` via the `Loggable` protocol, subsystem the main bundle identifier, category `ScreenManager`. `maxSetAge` and the touch-persist interval are `TimeInterval` constants. With the default `UserDefaultsSettingsStorageProvider`, an undecodable stored blob loads as `[]` and an unencodable list is silently not written (storage-failure-signal). Per `WindowManager`'s authoring comment, a second `ScreenManager` on the same storage key "would clobber the real one's state and double-register the notification observer" (single-owner-precondition); nothing in the source detects it. UIKit would use `UIScreen.didConnectNotification` / `didDisconnectNotification` or `UIWindowScene` screen changes; there is no desktop arrangement on iOS.
- **WinUI 3**: Enumerate displays with `Microsoft.UI.Windowing.DisplayArea.FindAll()` (`OuterBounds` for `frame`, `WorkArea` for `visibleFrame`, `DisplayId` for identity) and use the Win32 `EnumDisplayDevices` device-interface path when a stable monitor id is needed across reboots. Subscribe to screen changes via `WM_DISPLAYCHANGE` / `WM_SETTINGCHANGE` (`SPI_SETWORKAREA`) in the window procedure or `Windows.Devices.Display.DisplayMonitor` watchers with `DeviceWatcher`. Keep the manager on the UI thread (`DispatcherQueue`), expose `KnownSets` as an `ObservableCollection<ScreenSet>` and `CurrentSetId` through `INotifyPropertyChanged`, and replace observer tokens with a C# `event EventHandler<ScreenChange>`. Persist with `System.Text.Json` into `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value limit; use a `LocalFolder` file for large lists). Windows coordinates are top-left-origin, unlike AppKit's bottom-left; the classification logic is unaffected because it compares multisets only.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/ScreenManager/` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `ScreenManager.swift`, `ScreenChange.swift`, `ScreenSet.swift`, `ScreenSetStorage.swift`, `ScreenSnapshot.swift` and `ScreenManagerTests.swift` |
