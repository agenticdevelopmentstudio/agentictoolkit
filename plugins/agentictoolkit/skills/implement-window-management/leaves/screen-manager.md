<!-- leaf: implement-window-management/screen-manager · source: window-management-screen-manager.md -->

**Rules** (cite as `implement-window-management/screen-manager#<slug>`):

- `screen-change-cases` MUST
- `screen-snapshot-fields` MUST
- `screen-snapshot-derived` MUST
- `snapshot-from-screen-info` MUST
- `identity-component-uuid` MUST
- `identity-component-name-fallback` MUST
- `identity-resolution-independent` MUST
- `screen-set-fields` MUST
- `set-identity-derivation` MUST
- `set-identity-order-independent` MUST
- `set-identity-empty` MUST
- `main-actor-isolation` MUST
- `observer-handler-isolation` MUST
- `shared-instance` MUST
- `single-owner-precondition` MUST
- `init-snapshots` MUST
- `init-current-set-id` MUST
- `init-load-and-prune` MUST
- `init-upsert-persist` MUST
- `init-starts-observing` MUST
- `known-sets-order` MUST
- `known-set-ids-mirror` MUST
- `current-set-lookup` MUST
- `read-only-state` MUST
- `add-observer-token` MUST
- `remove-observer` MUST
- `observer-delivery-after-update` MUST
- `observer-delivery-order` MUST
- `notification-rearm-idempotent` MUST
- `notification-drives-processing` MUST
- `process-diff-baseline` MUST
- `process-updates-state-always` MUST
- `process-spurious-silent` MUST
- `process-real-change` MUST
- `classify-set-change-first` MUST
- `classify-resolution` MUST
- `classify-arrangement` MUST
- `classify-no-change` MUST
- `classify-no-pairing` MUST
- `classify-visible-frame-counts` MUST
- `touch-reconcile-first` MUST
- `reconcile-cheap-guard` MUST
- `reconcile-refresh` MUST
- `reconcile-no-notify` MUST
- `touch-in-memory-every-call` MUST
- `touch-persist-throttle` MUST
- `touch-throttle-independent` MUST

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

