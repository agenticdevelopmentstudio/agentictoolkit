---
id: aaf56f9b-896b-4f74-9e18-1ef4116270a9
title: Window Matching System Windows Contexts
domain: agentictoolkit://recipes/window-matching-system-windows-contexts
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Named window contexts for macOS: persisted JSON store, main-actor manager
  that parks and restores windows, fingerprint re-matching, and an observable model.'
platforms:
- swift
- macos
tags:
- window-management
- system-windows
- window-matching
- persistence
- foundation
depends-on: []
related:
- agentictoolkit://recipes/window-matching-core-system-windows
- agentictoolkit://recipes/window-matching-core-mac-os-system-windows
- agentictoolkit://recipes/window-matching-heuristics
references:
- https://developer.apple.com/documentation/coregraphics/cgwindowid
- https://man7.org/linux/man-pages/man2/flock.2.html
approved-by: ''
approved-date: ''
---

# Window Matching System Windows Contexts

## Overview

The contexts slice of AgenticToolkit's system-window feature groups other applications' windows into named **contexts** (workspaces such as "iOS App" or "Docs") and switches between them by moving every window that does not belong to the target context off-screen ("parking") and moving the target context's windows back to their saved frames. It is seven files:

- `Core/SystemWindows/Contexts/SystemWindowContextsState.swift`: `SystemWindowContextsState`, the persisted top-level record (active context ID and ordered context IDs).
- `Core/SystemWindows/Contexts/SystemWindowContextStore.swift`: `SystemWindowContextStore`, which reads and writes that state and one JSON file per `SystemWindowContext` under a caller-supplied root directory, serializing writes with an `flock(2)` lock file. It also declares `SystemWindowContextStoreError`.
- `Core/SystemWindows/Contexts/SystemWindowContextsSettings.swift`: `SystemWindowContextsSettings` (user-facing settings persisted by the host through `UserSettings`) and the `ReconcileBehavior` enum.
- `Core/SystemWindows/Contexts/ReconcileModels.swift`: `ReconcileItem` and `ReconcileCandidate`, value types a Reconcile UI lists after relaunch.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextError.swift`: `SystemWindowContextError`, the manager's error enum.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextManager.swift`: `SystemWindowContextManager`, the `@MainActor` engine that owns the contexts, parks and restores windows through an injected `SystemWindowControlling`, re-matches dormant window snapshots by fingerprint through `SystemWindowMatcher`, manages custom heuristic rules through `CustomHeuristicStore`, and persists after every mutation.
- `CoreMacOS/SystemWindows/Contexts/SystemWindowContextsModel.swift`: `SystemWindowContextsModel`, an `@MainActor` `ObservableObject` that wraps the manager for SwiftUI, turns thrown errors into a `lastError` string, drives launch reconciliation, receives window-lifecycle events as the `SystemWindowObserverDelegate`, and persists settings. It also declares `SystemWindowContextsConfiguration`, the host's injected branding and defaults.

The data types these files operate on, `SystemWindowContext` and `SystemWindowSnapshot` (in `Core/SystemWindows/`), the matcher `SystemWindowMatcher` (whose `autoAssignThreshold` is `80`), and the window controller protocol `SystemWindowControlling` live outside this slice and are referenced by name. A window is **live** when its snapshot's `windowID` is non-nil and **dormant** when it is nil (`SystemWindowSnapshot.isLive`); a dormant snapshot keeps its fingerprint so it can be re-attached. Use this ingredient when an app needs persistent, switchable groups of third-party windows that survive the app quitting, the owning apps quitting, and a reboot that recycles window IDs.

## Behavioral Requirements

### Data shapes

- **state-shape**: `SystemWindowContextsState` MUST hold `activeContextID: UUID?` and `contextIDs: [UUID]`, both defaulting to empty (`nil`, `[]`), and MUST be `Codable`, `Equatable`, and `Sendable`.
- **state-order-meaning**: `contextIDs` order MUST be the display order of contexts, where index 0 corresponds to keyboard shortcut 1 (per its doc comment).
- **state-excludes-settings**: `SystemWindowContextsState` MUST NOT carry application settings; hosts persist `SystemWindowContextsSettings` separately.
- **settings-shape**: `SystemWindowContextsSettings` MUST hold `launchAtLogin: Bool` (default `false`), `reconcileBehavior: ReconcileBehavior` (default `.prompt`), `hiddenApps: [String]` (default `[]`), and `showAppInDock: Bool` (default `false`), and MUST be `Codable`, `Equatable`, and `Sendable`.
- **settings-lenient-decode**: Decoding `SystemWindowContextsSettings` MUST substitute the default for each missing key, so `{}` decodes to the all-defaults value.
- **settings-typed-decode**: Decoding MUST throw when a present key holds the wrong type (for example `"launchAtLogin": "yes"`); only absence falls back to the default.
- **reconcile-behavior-cases**: `ReconcileBehavior` MUST declare exactly `prompt`, `auto`, `ignore`, in that order, each with its case name as its `String` raw value, and MUST be `CaseIterable`, `Codable`, `Equatable`, and `Sendable`.
- **reconcile-behavior-not-consumed**: The model MUST only store `reconcileBehavior` through `setReconcileBehavior(_:)`, and `performLaunchReconciliation()` always auto-applies matches and opens the Reconcile UI for the rest, whatever the stored value.
- **reconcile-item-shape**: `ReconcileItem` MUST carry `id` (the dormant snapshot's ID), `contextID`, `contextName`, `contextColor`, `app`, `titlePattern` (the fingerprint's title pattern), and `candidates: [ReconcileCandidate]`, and MUST be `Identifiable` and `Equatable`.
- **reconcile-candidate-shape**: `ReconcileCandidate` MUST carry `windowID: UInt32`, `app`, `windowTitle`, and `score: Int`, and its `id` MUST equal `windowID`.
- **reconcile-models-not-sendable**: `ReconcileItem` and `ReconcileCandidate` MUST NOT be declared `Sendable`; they are public structs without the conformance, so the compiler keeps them in the isolation domain that created them (the main actor, in `SystemWindowContextsModel`).
- **configuration-shape**: `SystemWindowContextsConfiguration` MUST be `Sendable` and hold `selfAppName: String?` (default `nil`), `settingsKey: String` (required), `contextNoun` (default `"context"`), `contextNounPlural` (default `contextNoun + "s"`), `notificationTitle` and `notificationIdentifier` (required), `defaultContexts: [DefaultContext]` (default `[]`), and `managesAppActivationPolicy: Bool` (default `true`).
- **error-descriptions-store**: Each `SystemWindowContextStoreError` case MUST produce its fixed English `errorDescription`: `directoryCreationFailed`, `encodingFailed`, `decodingFailed`, `writeFailed`, `readFailed` include the path (where present) and the underlying error's `localizedDescription`; `lockAcquisitionFailed` reads "Failed to acquire file lock at <path>"; `contextNotFound` reads "Context not found: <uuid>".
- **error-descriptions-manager**: Each `SystemWindowContextError` case MUST produce its fixed English `errorDescription` (for example `windowAlreadyAssigned` reads "Window <id> is already assigned to context '<name>'", `persistenceFailed` reads "Failed to persist state: <underlying>").
- **unraised-error-cases**: Callers MUST treat `SystemWindowContextError.alreadyActiveContext` and `.noActiveContext` as declared but unraised: no operation in these sources throws either case.

### Store: layout and I/O

- **store-layout**: `SystemWindowContextStore(rootDirectory:)` MUST place the state at `<root>/state.json`, one file per context at `<root>/contexts/<UUID uppercase string>.json`, and the lock file at `<root>/.lock`.
- **store-json-format**: The store MUST encode JSON pretty-printed with sorted keys and dates as ISO 8601, and MUST decode dates as ISO 8601.
- **store-ensure-directories**: `ensureDirectoryStructure()` MUST create `<root>` and `<root>/contexts` with intermediate directories, and MUST throw `directoryCreationFailed(path: <root>, underlying:)` when either creation fails.
- **store-load-state-missing**: `loadState()` MUST return `SystemWindowContextsState()` (no active context, no IDs) when `state.json` does not exist.
- **store-load-state-errors**: `loadState()` MUST throw `readFailed` when `state.json` exists but cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-load-context-missing**: `loadContext(id:)` MUST throw `contextNotFound(id:)` when the context file does not exist, `readFailed` when it cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-save-context**: `saveContext(_:)` MUST write the encoded context to its file with an atomic (write-then-replace) file write while holding the lock, throwing `encodingFailed` or `writeFailed` on failure.
- **store-delete-context**: `deleteContext(id:)` MUST remove the context file under the lock when it exists, and MUST succeed without effect when it does not; a removal failure propagates the underlying file-system error unwrapped.
- **store-load-all-order**: `loadAllContexts()` MUST return contexts in `state.contextIDs` order.
- **store-load-all-skips**: `loadAllContexts()` MUST skip any context whose file is missing, unreadable, or undecodable, logging "Skipping context <id>: <error>" at error level, rather than failing the whole load.
- **store-load-all-state-error**: `loadAllContexts()` MUST propagate the error when `state.json` itself cannot be read or decoded.
- **store-save-all-content**: `saveAll(contexts:activeContextID:)` MUST, under one lock, write every context's file and then write `state.json` with `activeContextID` and `contextIDs` equal to the contexts' IDs in the given order.
- **save-all-not-atomic**: NEEDS REVIEW: Not implemented in source. The doc comment says `saveAll` "updates the contexts state atomically", but each file is written independently; an encode or write failure on the Nth context throws after earlier context files are already replaced and before `state.json` is written, leaving disk partially updated. No rollback or journal exists; evidence that would settle it is whether the "atomically" contract is intended across files (a temp-directory swap) or only per file.
- **store-save-all-no-prune**: `saveAll` MUST NOT delete context files for IDs absent from `contexts`; orphan removal happens only through `deleteContext(id:)`.
- **store-list-files**: `listContextFiles()` MUST return `[]` when `<root>/contexts` is absent, MUST return the UUIDs parsed from every `*.json` filename whose stem is a valid UUID (ignoring other files), and MUST throw `readFailed` when the directory cannot be listed. The order MUST be treated as unspecified (directory listing order).
- **store-remove-all**: `removeAll()` MUST delete `<root>` recursively when it exists, without taking the lock, and propagate the underlying error unwrapped.
- **store-lock**: Every write operation (`saveContext`, `deleteContext`, `saveAll`) MUST first ensure the directory structure, open or create `<root>/.lock` with mode `0644`, take an exclusive `flock`, run the write, then unlock and close the descriptor exactly once.
- **store-lock-failure**: When the lock file cannot be opened, or the exclusive lock cannot be taken, the operation MUST throw `lockAcquisitionFailed(path:)` without running the write; on a failed lock the descriptor MUST be closed once.
- **store-lock-blocking**: The lock MUST block until acquired; there is no timeout and no non-blocking attempt.
- **store-reads-unlocked**: `loadState`, `loadContext`, `loadAllContexts`, and `listContextFiles` MUST NOT take the lock.
- **store-sendable**: `SystemWindowContextStore` MUST be usable from any thread (`@unchecked Sendable`); its safety rests on the write lock and on encoder and decoder instances that are configured once and never mutated.

### Manager: lifecycle and load

- **manager-main-actor**: `SystemWindowContextManager` MUST be confined to the main actor (`@MainActor`); every operation runs there and its state has no internal locking.
- **manager-init**: `init(windowManager:stateStore:windowMatcher:customHeuristicStore:)` MUST start with no contexts and no active context, and MUST default `customHeuristicStore` to a `CustomHeuristicStore` rooted at the state store's `rootDirectory`.
- **manager-load-state**: `loadState()` MUST read the active context ID and the contexts from the store, then invalidate stale window IDs, then load custom heuristic rules, and MUST propagate store read or decode errors on `state.json` unwrapped.
- **manager-load-no-active-check**: `loadState()` MUST keep a persisted `activeContextID` even when no loaded context has that ID (for example its file was skipped); `activeContext` then returns `nil`.
- **reconcile-stale-recycled**: On load, a snapshot whose `windowID` belongs to a live window of a different app (compared case-insensitively) MUST have its `windowID` cleared.
- **reconcile-stale-missing**: On load, a snapshot whose `windowID` is not in the live window list MUST have its `windowID` cleared only when its app has at least one live window; when its app has no live windows the `windowID` MUST be kept.
- **reconcile-stale-persist**: When at least one ID was cleared on load, the manager MUST log "Invalidated <n> stale window ID(s) on load" and persist; a persistence failure there MUST be logged and not thrown.
- **manager-root-directory**: `rootDirectory` MUST return the state store's root directory.

### Manager: context CRUD

- **create-context**: `createContext(name:color:)` MUST append a new context (new UUID, color default `"#007AFF"`, no snapshots), persist, and return it; it MUST NOT validate the name (empty and duplicate names are accepted) or the color string.
- **delete-context-missing**: `deleteContext(id:)`, `renameContext(id:to:)`, `updateContextColor(id:to:)`, and `switchContext(to:)` MUST throw `SystemWindowContextError.contextNotFound(id:)` for an unknown ID without changing state.
- **delete-active-context**: Deleting the active context MUST clear `activeContextID` and restore every context's live windows to their saved frames (not only the deleted context's).
- **delete-inactive-context**: Deleting an inactive context MUST restore only that context's live windows to their saved frames.
- **delete-context-disk**: `deleteContext(id:)` MUST remove the context from memory, then delete its file via the store, then persist the remaining state.
- **rename-and-color**: `renameContext` and `updateContextColor` MUST set the field and persist, without validation.

### Manager: window assignment

- **add-window-duplicate**: `addWindow(windowID:to:)` MUST throw `windowAlreadyAssigned(windowID:contextName:)` when the window ID is on a snapshot in a different context.
- **add-window-refresh**: When the window ID is already in the target context, `addWindow` MUST refresh that snapshot's `savedFrame`, `title`, and `lastSeen` from the live window, persist, and return it instead of adding a second snapshot.
- **add-window-errors**: `addWindow` MUST throw `contextNotFound` for an unknown context and `windowNotFound(windowID:)` when the ID is not in `listAllWindows()`.
- **add-window-snapshot**: `addWindow` MUST create a snapshot with the matcher's fingerprint for the window and the live window's frame, display, app, and title, append it to the context, persist, and return it.
- **park-on-attach**: Every operation that attaches a window to a context (`addWindow`, `applyMatches`, `assignWindowToSnapshot`, `assignWindowsToSnapshots`, `reMatchDormantWindowsForApp`, `checkNewWindowForAutoAssignment`, `checkCustomRulesForAutoAssignment`) MUST park that window when there is an active context and the owning context is not it, and MUST NOT park it when no context is active.
- **remove-window**: `removeWindow(windowID:)` MUST remove the first snapshot carrying that window ID, move the window back to its saved frame when its context is not the active one, persist, and return the removed snapshot; it MUST throw `windowNotInAnyContext(windowID:)` when no snapshot carries the ID.
- **remove-clears-last-focused**: Removing a snapshot MUST clear the context's `lastFocusedWindowID` when it pointed at that snapshot.
- **set-last-focused**: `setLastFocusedWindow(windowID:)` MUST record the snapshot ID of the matching window as the active context's `lastFocusedWindowID` and persist; it MUST do nothing, without error, when no context is active or the window is not in the active context.
- **context-lookup**: `context(for:)` MUST return the first context (in display order) with a snapshot carrying the window ID, or `nil`.

### Manager: switching

- **switch-same-context**: `switchContext(to:)` with the already-active ID MUST restore that context's live windows to their saved frames and persist, and MUST NOT park any other context or throw.
- **switch-save-active**: Switching to a different context MUST, for each live window of the previously active context, capture its current frame into `savedFrame` (and update `lastSeen`) only when the frame overlaps some display horizontally, then park it.
- **switch-park-others**: Switching MUST park every live window of every other non-target context, first capturing any on-screen frame the same way.
- **switch-restore-target**: Switching MUST set every live window of the target context to its `savedFrame`.
- **switch-focus**: Switching MUST focus the target context's last-focused window when that snapshot exists and is live, else the first live window in the context, else nothing.
- **switch-commit**: Switching MUST set `activeContextID` to the target after parking, restoring, and focusing, then persist.
- **parking-position**: Parking MUST move a window's origin to x = (the minimum `minX` across all screens, or 0 when there are none) − `parkingMargin` (`30_000`), keeping y equal to the snapshot's saved-frame y.
- **frame-capture-guard**: A window whose live frame does not overlap any screen horizontally MUST NOT have that frame saved, so a parked or clamped position never becomes a restore target.
- **window-ops-best-effort**: Park (move), restore (set frame), and focus calls to the window controller MUST NOT throw out of the manager; their failures are discarded, as the `parkWindow` doc comment declares ("Best-effort: AX failures are swallowed").
- **restore-failure-silent**: NEEDS REVIEW: Not implemented in source. A failed restore or un-park (`setFrame`) in `restoreWindowsToSavedPositions` or `removeWindow` is discarded with no log, return value, or error, so a window can stay parked 30,000 points off every screen with no signal to the caller or user; the doc comment covers only parking. Settled by deciding whether restore failures should be logged, counted, or surfaced.

### Manager: re-matching

- **has-stale-windows**: `hasStaleWindows` MUST be `true` exactly when some snapshot in some context has a nil `windowID`.
- **run-rematching**: `runReMatching()` MUST pass all contexts and `listAllWindows()` to `SystemWindowMatcher.matchWindows(contexts:liveWindows:)` and return its `MatchResult` without mutating state.
- **apply-matches**: `applyMatches(_:)` MUST, for each matched pair whose context and snapshot still exist, set the snapshot's `windowID` and `title` from the matched window and `lastSeen` to now, park when required (park-on-attach), and return the count applied; pairs whose context or snapshot is gone MUST be skipped silently.
- **apply-matches-unconditional**: `applyMatches` MUST NOT re-check scores; every pair in `matched` has already cleared the matcher's threshold.
- **apply-matches-persist**: `applyMatches` MUST persist only when at least one pair was applied, and MUST throw `persistenceFailed` when that persist fails.
- **launch-rematching**: `performLaunchReMatching()` MUST return `nil` without enumerating windows when `hasStaleWindows` is false, and otherwise run re-matching, apply the result, and return it.
- **assign-to-snapshot**: `assignWindowToSnapshot(windowID:snapshotID:contextID:)` MUST set the snapshot's `windowID`, `title` (the live window's title, or `""` when the ID is not live), and `lastSeen`, park when required, and persist; it MUST throw `contextNotFound` for an unknown context and `windowNotInAnyContext(windowID:)` when the snapshot ID is not in that context.
- **assign-batch**: `assignWindowsToSnapshots(_:)` MUST return 0 for an empty list without enumerating windows; otherwise enumerate windows once, apply each resolvable assignment as assign-to-snapshot does, skip unresolvable ones silently, persist once when at least one applied (a persistence failure is logged, not thrown), and return the count applied.
- **assignment-window-unvalidated**: NEEDS REVIEW: Not implemented in source. `assignWindowToSnapshot` and `assignWindowsToSnapshots` never check that the window ID is live or not already on another snapshot, unlike `addWindow`'s `windowAlreadyAssigned` check; `autoAssignAllRemainingMatches()` builds each assignment from an item's top candidate independently, so two dormant snapshots sharing a top candidate both receive the same window ID. Settled by deciding whether a window may back two snapshots and, if not, which assignment wins.
- **remove-dormant**: `removeDormantSnapshot(snapshotID:contextID:)` MUST remove the snapshot by its stable ID (whether dormant or live) and persist; it MUST throw `contextNotFound` for an unknown context and MUST succeed without change when the snapshot ID is absent.
- **dormant-snapshots**: `dormantSnapshots()` MUST return every snapshot with a nil `windowID`, with its context's ID, name, and color, in context order then snapshot order.
- **score-window**: `scoreWindow(_:against:)` MUST return `SystemWindowMatcher.score(window:against:)` unchanged.

### Manager: window lifecycle events

- **mark-window-dormant**: `markWindowDormant(windowID:)` MUST clear the `windowID` of the first snapshot carrying it, persist (failure logged, not thrown), and return the updated snapshot, or return `nil` when no snapshot carries it.
- **mark-app-dormant**: `markAppWindowsDormant(appName:)` MUST clear `windowID` on every live snapshot whose `app` equals `appName` exactly (case-sensitive), persist when any changed, and return the count.
- **update-title**: `updateWindowTitle(windowID:newTitle:)` MUST set `title` and `lastSeen` on the first snapshot carrying the ID, persist, and return `true`, or return `false` when none carries it.
- **rematch-app**: `reMatchDormantWindowsForApp(appName:)` MUST consider only live windows of that app (case-insensitive) that are not already on any snapshot, and for each dormant snapshot of that app (in context then snapshot order) assign the highest-scoring remaining candidate whose score is at least `SystemWindowMatcher.autoAssignThreshold` (80), first-seen winning ties; each window MUST be assigned at most once per call. It MUST persist when any matched and return the count.
- **new-window-autoassign**: `checkNewWindowForAutoAssignment(_:)` MUST return `nil` when the window is already on a snapshot; otherwise it MUST assign the window to the single dormant snapshot (across all contexts and apps) with the highest score of at least 80, first-seen winning ties, persist, and return that context's ID, or return `nil` when none qualifies.
- **custom-rule-autoassign**: `checkCustomRulesForAutoAssignment(_:)` MUST return `nil` when the window is already on a snapshot; otherwise it MUST take the first rule (in stored order) with `autoAssign` true, an `appName` equal to the window's app case-insensitively, a title that `matchTitle` accepts, and a `targetContextName` equal case-insensitively to some context's name, add a new snapshot for the window to the first such context, persist, and return that context's ID; rules whose target name matches no context MUST be skipped.
- **event-persist-logged**: Lifecycle-event operations (`markWindowDormant`, `markAppWindowsDormant`, `updateWindowTitle`, `reMatchDormantWindowsForApp`, `checkNewWindowForAutoAssignment`, `checkCustomRulesForAutoAssignment`) MUST NOT throw; a persistence failure is logged at error level by the persist step and the in-memory change stands.

### Manager: persistence and custom rules

- **persist-after-mutation**: Every mutating manager operation MUST persist the whole state through `saveAll(contexts:activeContextID:)` after changing memory.
- **persist-error-wrap**: A persistence failure MUST be logged ("Failed to persist state: ...") and rethrown as `SystemWindowContextError.persistenceFailed(underlying:)` by throwing operations.
- **memory-ahead-of-disk**: When persistence fails, the in-memory change MUST remain applied; context operations mutate memory before writing and do not roll back.
- **rules-load**: `loadCustomHeuristicRules()` MUST load rules from the custom heuristic store and register them with the matcher's registry; on failure it MUST log the error and set `customHeuristicRules` to `[]` without touching the registry.
- **rules-write-first**: `addCustomHeuristicRule`, `updateCustomHeuristicRule`, and `deleteCustomHeuristicRule` MUST save the new rule list to disk before changing `customHeuristicRules` or the registry, so a failed write leaves memory, disk, and registry unchanged, and MUST propagate the save error.
- **rules-update-unknown**: `updateCustomHeuristicRule` MUST return without writing or throwing when no rule has the given ID.
- **rules-delete-unknown**: `deleteCustomHeuristicRule(id:)` MUST rewrite the unchanged list and succeed when no rule has the given ID.

### Model

- **model-main-actor**: `SystemWindowContextsModel` MUST be confined to the main actor and publish `contexts`, `activeContextID`, `lastError`, `showReconcileWindow`, `showContextPicker`, `showHelp`, `showDiscovery`, `unmatchedItems`, `customHeuristicRules`, and `settings` as `@Published` properties.
- **model-test-environment**: When `isTestEnvironment` is true (default: an `XCTestCase` class is loadable), the model MUST disable notifications, window observation, and default-context seeding.
- **model-settings-init**: The model MUST read its initial `settings` from a `UserSetting` keyed by `configuration.settingsKey`, defaulting to `SystemWindowContextsSettings()`.
- **model-errors-to-string**: Every model operation that calls a throwing manager method MUST catch the error, set `lastError` to "<English prefix>: <localizedDescription>", log it at error level, and not rethrow.
- **model-sync**: After every successful manager mutation the model MUST copy `contexts`, `activeContextID`, and `customHeuristicRules` from the manager.
- **model-load-state**: `loadState()` MUST load the manager's state and, when no contexts exist and seeding is enabled, create each `configuration.defaultContexts` entry in order, logging and continuing past any that fails; a load failure MUST set `lastError` to "Failed to load state: ..." and skip seeding.
- **model-launch-reconciliation**: `performLaunchReconciliation()` MUST do nothing further when the manager reports no stale windows; otherwise it MUST apply auto-matches, rebuild `unmatchedItems`, and, when any remain, set `showReconcileWindow = true` and send the reconcile notification.
- **model-unmatched-items**: `refreshUnmatchedItems()` MUST produce one `ReconcileItem` per dormant snapshot, whose candidates are every live window not on any snapshot with a score above 0, sorted by score descending.
- **model-assign**: `assignWindow(candidateWindowID:toUnmatchedItem:)` MUST set `lastError = "Unmatched item not found."` when the item ID is not in `unmatchedItems`, and otherwise assign and refresh.
- **model-skip**: `skipUnmatchedItem(_:)` MUST remove the item's dormant snapshot and refresh, and MUST do nothing when the item ID is unknown.
- **model-auto-assign-all**: `autoAssignAllRemainingMatches()` MUST assign each unmatched item that has candidates to its first (highest-scoring) candidate in one manager batch, and refresh only when at least one applied.
- **model-notification**: The reconcile notification MUST be sent only when notifications are enabled and the main bundle identifier is non-nil and not `com.apple.dt.xctest.tool`; it MUST request alert authorization and, only if granted, post an immediate, silent request with `configuration.notificationTitle`, identifier `configuration.notificationIdentifier`, and body "1 window needs assignment" or "<n> windows need assignment".
- **model-own-windows**: The model MUST exclude windows whose owner PID equals its own process ID from `listAllWindows()`, `addFrontmostWindow()`, and `removeFrontmostWindow()`.
- **model-add-frontmost**: `addFrontmostWindow()` MUST set `lastError = "No active context. Switch to a context first."` and return `false` when no context is active, set "No window found to add." and return `false` when no foreign on-screen window exists, and otherwise add the frontmost foreign window from `listWindows()` to the active context and return `true`.
- **model-remove-frontmost**: `removeFrontmostWindow()` MUST set "No window found to remove." or "This window is not assigned to any context." and return `false` in those cases, and otherwise remove the window and return `true`.
- **model-batch-add**: `addWindows(windowIDs:to:)` MUST add each window independently, log a skipped window at debug level without setting `lastError`, and return the number added.
- **model-cycle**: `switchToNextContext()` and `switchToPreviousContext()` MUST do nothing with fewer than 2 contexts, MUST wrap around, and with no active context MUST switch to the first (next) or last (previous) context.
- **model-settings-write**: Each settings setter MUST update the published `settings` and write the whole value to the `UserSetting` in one step; `setShowAppInDock(_:)` MUST NOT change the application's activation policy.
- **model-hidden-apps**: `addHiddenApp(_:)` MUST ignore a name already present (exact match) and otherwise append it and sort the list; `removeHiddenApp(_:)` MUST remove every exact match.
- **model-observer-events**: The model's `SystemWindowObserverDelegate` callbacks are `nonisolated` and MUST each hop to the main actor in a new task before calling the manager: `windowDestroyed` marks the window dormant, `windowCreated` tries dormant-snapshot matching and then custom rules, `windowTitleChanged` updates the title, `appTerminated` marks the app's windows dormant, and `appLaunched` re-matches the app's dormant windows.
- **observer-event-ordering**: NEEDS REVIEW: Not implemented in source. Each delegate callback spawns an independent unstructured main-actor `Task`, and the source states no ordering between them, so a rapid `appTerminated` then `appLaunched` (or `windowDestroyed` then `windowCreated` for a recycled ID) has no ordering guarantee beyond the executor's scheduling. Settled by confirming the observer delivers on the main thread and that tasks enqueued there are relied on to run in FIFO order, or by serializing events through one queue.
- **model-observation-start**: `startWindowObservation()` MUST do nothing when observation is disabled, and otherwise create a `SystemWindowObserver` over the window manager, make the model its delegate, and start it; `stopWindowObservation()` MUST stop and release it.

## Appearance

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## States

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## Accessibility

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contexts-001 | park-on-attach | Windows 1 (Xcode) and 2 (Warp); create "Active" and "Inactive"; switch to "Active"; reset the mock; `addWindow(windowID: 2, to: inactive.id)` | The mock records a move of window 2 (`SystemWindowContextManagerTests.addToInactiveParks`) |
| contexts-002 | park-on-attach | Window 1; create one context, no switch; reset; `addWindow(windowID: 1, to: context.id)` | No move recorded (`addWithNoActiveContextDoesNotPark`) |
| contexts-003 | delete-active-context | Window 1 in "Active", window 2 in "Other"; switch to "Active"; reset; `deleteContext(id: active.id)` | `activeContextID == nil`; set-frame recorded for window 1 and window 2 (`deleteActiveRestoresAll`) |
| contexts-004 | reconcile-stale-missing, has-stale-windows | Persist a snapshot with window 99 (Xcode); reload with live windows = [7 (Xcode)]; `loadState()` | `hasStaleWindows == true` (`reconcileStaleIDsOnLoad`) |
| contexts-005 | reconcile-stale-recycled | Persist a snapshot with window 42 (Xcode); reload with live windows = [42 (Finder)]; `loadState()` | `hasStaleWindows == true` (`reconcileRecycledIDOnLoad`) |
| contexts-006 | reconcile-stale-missing | Persist a snapshot with window 99 (Xcode); reload with live windows = [5 (Warp)]; `loadState()` | `hasStaleWindows == false`; the snapshot keeps `windowID == 99` |
| contexts-007 | store-load-state-missing | Fresh empty root; `loadState()` | `SystemWindowContextsState(activeContextID: nil, contextIDs: [])` |
| contexts-008 | store-layout, store-save-all-content, store-json-format | `saveAll(contexts: [A, B], activeContextID: B.id)` into an empty root | `<root>/contexts/<A.id>.json` and `<B.id>.json` exist; `state.json` decodes to `activeContextID == B.id`, `contextIDs == [A.id, B.id]`; the JSON keys appear sorted; `<root>/.lock` exists |
| contexts-009 | store-load-all-skips, store-load-all-order | After contexts-008, overwrite `<A.id>.json` with `not json`; `loadAllContexts()` | Returns `[B]`; no error thrown |
| contexts-010 | store-load-state-errors | Write `{` to `state.json`; `loadState()` | Throws `SystemWindowContextStoreError.decodingFailed` with the `state.json` path |
| contexts-011 | store-load-context-missing | `loadContext(id: UUID())` on an empty root | Throws `contextNotFound(id:)` with that ID |
| contexts-012 | store-list-files | `contexts/` holds `<valid uuid>.json`, `notes.txt`, `bad.json` | Returns exactly the one valid UUID |
| contexts-013 | store-delete-context | `deleteContext(id: UUID())` for a file that does not exist | Succeeds with no error |
| contexts-014 | store-save-all-no-prune | `saveAll([A, B], nil)` then `saveAll([B], nil)` | `<A.id>.json` still exists; `state.json` lists only `B.id` |
| contexts-015 | settings-lenient-decode | Decode `{}` as `SystemWindowContextsSettings` | `launchAtLogin == false`, `reconcileBehavior == .prompt`, `hiddenApps == []`, `showAppInDock == false` |
| contexts-016 | settings-typed-decode | Decode `{"launchAtLogin": "yes"}` | Throws a decoding error |
| contexts-017 | reconcile-behavior-cases | `ReconcileBehavior.allCases.map(\.rawValue)` | `["prompt", "auto", "ignore"]` |
| contexts-018 | add-window-duplicate | Window 1 in context A; `addWindow(windowID: 1, to: B.id)` | Throws `windowAlreadyAssigned(windowID: 1, contextName: "A")` |
| contexts-019 | add-window-refresh | Window 1 in A; change the mock's frame for window 1; `addWindow(windowID: 1, to: A.id)` | A still has one snapshot; its `savedFrame` equals the new frame |
| contexts-020 | add-window-errors | `addWindow(windowID: 555, to: A.id)` with no window 555 live | Throws `windowNotFound(windowID: 555)` |
| contexts-021 | delete-context-missing | `switchContext(to: UUID())` | Throws `contextNotFound`; no move or set-frame recorded |
| contexts-022 | switch-same-context | Active A holding window 1; reset; `switchContext(to: A.id)` | Set-frame recorded for window 1; no move recorded; no error |
| contexts-023 | switch-restore-target, switch-focus, switch-commit | A holds window 1, B holds window 2, A active; `switchContext(to: B.id)` | Window 1 moved; window 2 set to its saved frame; focus recorded for window 2; `activeContextID == B.id` |
| contexts-024 | parking-position | Single screen with `minX == 0`; park window 1 whose saved frame y is 50 | Move to (−30000, 50) |
| contexts-025 | frame-capture-guard | Active A with window 1 whose live frame x is −30000 (off every screen); `switchContext(to: B.id)` | Window 1's `savedFrame` is unchanged |
| contexts-026 | remove-window | Window 2 in inactive B while A is active; `removeWindow(windowID: 2)` | Returns the snapshot; set-frame recorded for window 2 to its saved frame |
| contexts-027 | remove-window | `removeWindow(windowID: 777)` with no snapshot carrying it | Throws `windowNotInAnyContext(windowID: 777)` |
| contexts-028 | set-last-focused | No active context; `setLastFocusedWindow(windowID: 1)` | Returns without error; no persist |
| contexts-029 | launch-rematching | All snapshots live; `performLaunchReMatching()` | Returns `nil` |
| contexts-030 | assign-to-snapshot | `assignWindowToSnapshot(windowID: 1, snapshotID: UUID(), contextID: A.id)` | Throws `windowNotInAnyContext(windowID: 1)` |
| contexts-031 | assign-batch | `assignWindowsToSnapshots([])` | Returns 0; `listAllWindows()` not called |
| contexts-032 | mark-app-dormant | Live snapshot with `app == "Xcode"`; `markAppWindowsDormant(appName: "xcode")` | Returns 0; snapshot still live |
| contexts-033 | rematch-app | Dormant Xcode snapshot; live Xcode window scoring 80 against it; `reMatchDormantWindowsForApp(appName: "XCODE")` | Returns 1; snapshot's `windowID` is the window's ID |
| contexts-034 | new-window-autoassign | Dormant snapshot; new window scoring 79 | `checkNewWindowForAutoAssignment` returns `nil`; snapshot stays dormant |
| contexts-035 | custom-rule-autoassign | Rule `autoAssign: true`, app "Safari", target "docs"; context named "Docs"; new Safari window whose title the rule matches | Returns the "Docs" context ID; the context gains a snapshot for the window |
| contexts-036 | rules-write-first | Custom heuristic store whose save throws; `addCustomHeuristicRule(r)` | Throws; `customHeuristicRules` unchanged |
| contexts-037 | model-add-frontmost | Model with no active context; `addFrontmostWindow()` | Returns `false`; `lastError == "No active context. Switch to a context first."` |
| contexts-038 | model-cycle | Contexts [A, B, C], active C; `switchToNextContext()` | Active becomes A |
| contexts-039 | model-hidden-apps | `hiddenApps == ["Zed"]`; `addHiddenApp("Arc")`; `addHiddenApp("Arc")` | `hiddenApps == ["Arc", "Zed"]` |
| contexts-040 | model-unmatched-items | One dormant snapshot; live unassigned windows scoring 30, 0, 90 | One item; candidates scored `[90, 30]` |
| contexts-041 | persist-error-wrap, memory-ahead-of-disk | Make `<root>/contexts` read-only; `renameContext(id: A.id, to: "X")` | Throws `persistenceFailed`; `contexts` shows A named "X" |
| contexts-042 | model-test-environment | Construct the model with `isTestEnvironment: true` | `notificationsEnabled == false`; `observationEnabled == false`; `loadState()` on an empty store leaves `contexts` empty |

## Edge Cases

- **Empty root directory**: first launch — `loadState()` MUST yield no contexts and no active context; the model then seeds `defaultContexts` unless in a test environment.
- **Missing context file referenced by state**: `loadAllContexts()` MUST skip it with an error log; the ID drops out of `contextIDs` on the next persist, and the orphan never reappears.
- **Orphan context file not referenced by state**: it MUST stay on disk untouched; the manager never reads `listContextFiles()`.
- **Active ID points at a skipped context**: `activeContextID` MUST keep the dangling ID and `activeContext` MUST return `nil`; `switchToNextContext()` then switches to the first context.
- **Corrupt `state.json`**: `loadState()` MUST throw `decodingFailed`; the model sets `lastError` and does not seed defaults, so existing context files are not overwritten on that launch.
- **Empty or duplicate context names**: accepted (create-context); custom-rule auto-assignment picks the first context in display order whose name matches case-insensitively.
- **Malformed color string**: stored unchanged; the doc comment on `SystemWindowContext.color` documents the caller precondition of a `#`-prefixed hex string.
- **Owning app mid-launch at load**: a persisted window ID whose app has zero live windows MUST be kept, per the `reconcilePersistedWindowIDs` comment, so the window is not orphaned; re-matching reconciles it later.
- **Recycled window ID**: a persisted ID now owned by another app MUST be cleared on load (reconcile-stale-recycled).
- **No screens**: `NSScreen.screens` empty — the parking x MUST be −30000, and no frame is captured because nothing overlaps a screen.
- **Window already off-screen when its context is deactivated**: its saved frame MUST NOT be overwritten (frame-capture-guard).
- **Window-controller failure**: move, set-frame, and focus errors are discarded; parking failures are declared best-effort, and the open question on restore-failure-silent covers restores.
- **Persistence failure**: throwing operations MUST throw `persistenceFailed` with memory left ahead of disk; event operations and batch assignment MUST log and continue. A mid-`saveAll` failure leaves disk partially updated (the open question on save-all-not-atomic).
- **Lock contention**: a second process writing the same root MUST block on `flock` until the first finishes; there is no timeout.
- **Reads during a write**: unlocked reads MUST see either the old or the new version of each file, because each file is replaced with an atomic write; they MAY see a new context file alongside an old `state.json` mid-`saveAll`.
- **Same window assigned twice**: the batch and single assignment APIs do not reject it (the open question on assignment-window-unvalidated).
- **Assign to a window that is no longer live**: the snapshot MUST still receive the ID and an empty title.
- **Case mismatch in app names**: `markAppWindowsDormant` compares exactly, while `reMatchDormantWindowsForApp`, load-time invalidation, and custom rules compare case-insensitively.
- **Unknown rule ID on update**: silent no-op (rules-update-unknown).
- **Notification authorization denied**: no notification is posted and nothing is logged; the Reconcile window flag is still set.
- **Running outside an app bundle**: the notification step MUST return before touching `UNUserNotificationCenter`, which the source notes crashes without a bundle identifier.
- **`reconcileBehavior` set to `ignore` or `auto`**: launch reconciliation still runs the `prompt` behavior (reconcile-behavior-not-consumed).
- **Concurrent access**: the manager and model are `@MainActor`, so their operations are serialized and cannot interleave; the store is `@unchecked Sendable` with writes serialized by an inter-process `flock`. Observer events arrive on independent main-actor tasks (the open question on observer-event-ordering).
- **Cancellation and timeouts**: no operation supports cancellation or has a timeout; all work is synchronous on the calling actor except the notification authorization callback.
- **Offline or disconnected state**: not applicable; the component performs no network access.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SystemWindowContextStore(rootDirectory:)` | `URL` | none (required) | Root holding `state.json`, `contexts/`, `.lock`, and (by default) the custom rules file `heuristics.json`. |
| `windowManager` | `SystemWindowControlling` | none (required) | Lists windows and moves, resizes, focuses, and frames them; injected into both manager and model. |
| `windowMatcher` | `SystemWindowMatcher` | `SystemWindowMatcher()` | Fingerprinting, scoring, and batch matching; `autoAssignThreshold` is `80`. |
| `customHeuristicStore` | `CustomHeuristicStore?` | store at the state root | Persists user-defined heuristic rules. |
| `SystemWindowContextManager.parkingMargin` | `CGFloat` | `30_000` | Distance left of the leftmost screen where inactive windows are parked. |
| `createContext(name:color:)` color | `String` | `"#007AFF"` | Context color hex string. |
| `configuration.selfAppName` | `String?` | `nil` | Host app name exposed to views; own windows are excluded by PID, not by this name. |
| `configuration.settingsKey` | `String` | none (required) | `UserSettings` key for `SystemWindowContextsSettings`. |
| `configuration.contextNoun` / `contextNounPlural` | `String` | `"context"` / noun + `"s"` | Nouns used in create-failure messages and exposed to views. |
| `configuration.notificationTitle` / `notificationIdentifier` | `String` | none (required) | Reconcile notification title and request identifier. |
| `configuration.defaultContexts` | `[DefaultContext]` | `[]` | Contexts seeded on first launch. |
| `configuration.managesAppActivationPolicy` | `Bool` | `true` | Tells the settings UI whether to show the Dock toggle. |
| `isTestEnvironment` | `Bool` | `NSClassFromString("XCTestCase") != nil` | Disables notifications, observation, and seeding. |
| `notificationsEnabled` / `observationEnabled` | `Bool` | `true` (false in tests) | Runtime switches on the model. |
| `SystemWindowContextsSettings` fields | see settings-shape | see settings-shape | Launch at login, reconcile behavior, hidden apps, Dock visibility. |

## Deep Linking

Not applicable: none of the seven files registers a URL scheme, route, or navigation entry point; contexts are switched only by method calls.

## Localization

Every user-facing string in these files is a hardcoded English literal with no string-catalog lookup: the `errorDescription` of both error enums, the model's `lastError` prefixes, and the notification body.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Failed to load state: <error>` | `lastError` when `loadState()` fails |
| (none; literal) | `Failed to create <contextNoun>: <error>` | `lastError` on create; the noun comes from configuration |
| (none; literal) | `Failed to delete context: <error>` / `Failed to rename context: <error>` / `Failed to update context color: <error>` / `Failed to switch context: <error>` | `lastError` on those operations |
| (none; literal) | `Failed to add window: <error>` / `Failed to remove window: <error>` / `Failed to assign window: <error>` / `Failed to skip item: <error>` | `lastError` on window operations |
| (none; literal) | `Failed to add heuristic rule: <error>` / `Failed to update heuristic rule: <error>` / `Failed to delete heuristic rule: <error>` | `lastError` on rule operations |
| (none; literal) | `Re-matching failed: <error>` | `lastError` from launch reconciliation |
| (none; literal) | `Unmatched item not found.` | `lastError` from `assignWindow` |
| (none; literal) | `No active context. Switch to a context first.` | `lastError` from `addFrontmostWindow` |
| (none; literal) | `No window found to add.` / `No window found to remove.` | `lastError` from the frontmost-window actions |
| (none; literal) | `This window is not assigned to any context.` | `lastError` from `removeFrontmostWindow` |
| (none; literal) | `<n> window needs assignment` / `<n> windows need assignment` | Notification body, pluralized by an English-only `count == 1` test |
| (none; literal) | `Context not found: <uuid>`, `Window <id> is already assigned to context '<name>'`, `Failed to persist state: <error>`, and the other `errorDescription` values | Surfaced through `lastError` via `localizedDescription` |

Only `contextNoun` is host-configurable; the other messages say "context" regardless of the configured noun.

## Accessibility Options

Not applicable: the component has no visual surface, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source reads no feature-flag key; `notificationsEnabled`, `observationEnabled`, and `isTestEnvironment` are test switches, not flags.

## Analytics

Not applicable: none of the files emits analytics events.

## Privacy

- **Data collected**: application names, window titles, window frames, and display IDs of other applications' windows, plus user-chosen context names and colors and custom rule definitions.
- **Storage**: plain, unencrypted, pretty-printed JSON files under the caller-supplied root (`state.json`, `contexts/<uuid>.json`, `heuristics.json`), written with mode defaults except the `.lock` file (`0644`); settings go to `UserSettings` under `settingsKey`.
- **Transmission**: nothing leaves the device; the only outbound effect is a local user notification whose body carries a count, not titles.
- **Retention**: files persist until the context is deleted (its file is removed), `removeAll()` is called, or the user deletes the directory; skipped or orphaned context files are never cleaned up automatically.
- **Logs**: log messages interpolate context names, app names, and window IDs (for example "Created context '<name>'"); `Logger` string interpolation is private by default, so those values are redacted in release logs unless marked public.

## Logging

Subsystem: main bundle identifier (`Loggable.subsystem`) | Category: the type name (`SystemWindowContextStore`, `SystemWindowContextManager`, `SystemWindowContextsModel`)

| Event | Level | Message |
|-------|-------|---------|
| Store created | info | `SystemWindowContextStore initialized at <path>` |
| Context file skipped on load | error | `Skipping context <id>: <error>` |
| Manager load start / end | info | `Loading state from disk` / `Loaded <n> contexts, active: <uuid or none>` |
| Stale IDs cleared | info | `Invalidated <n> stale window ID(s) on load` |
| Context created / deleting / deleted | info | `Created context '<name>' (<id>)` / `Deleting context '<name>' (<n> windows)` / `Deleted context '<name>'` |
| Window added | info | `Added window <id> to '<name>'` |
| Switch | info | `Switching context: '<from>' -> '<to>'` / `Switch complete -> '<to>'` |
| Window dormant / app terminated | info | `Window <id> marked dormant in '<name>'` / `App '<app>' terminated, <n> windows marked dormant` |
| App re-matched / auto-assigned | info | `App '<app>' launched, re-matched <n> dormant windows` / `Auto-assigned <id> to '<name>' (score <n>)` |
| Rules load failed | error | `Failed to load custom heuristic rules: <error>` |
| Persist failed | error | `Failed to persist state: <error>` |
| Model operation failed | error | the same text as `lastError` |
| Default contexts | info / error | `Created <n> default contexts` / `Failed to create default context '<name>': <error>` |
| Reconciliation | info | `No stale windows detected, skipping reconciliation.` / `<n> unmatched windows need assignment.` / `All stale windows auto-matched successfully.` |
| Batch add skip / summary | debug / info | `Skipped window <id> during batch add: <error>` / `Batch-added <n>/<m> windows to context` |
| Hidden apps | debug | `Added '<app>' to hidden apps filter.` / `Removed '<app>' from hidden apps filter.` |
| Observation disabled | debug | `Window observation disabled (test environment).` |

Window-controller failures (move, set frame, focus) and notification authorization results are not logged.

## Platform Notes

- **SwiftUI**: `SystemWindowContextsModel` is already the SwiftUI bridge: observe it with `@StateObject` or `@ObservedObject` and bind sheets to `showReconcileWindow`, `showContextPicker`, `showHelp`, and `showDiscovery`. A port to the Observation framework would swap `ObservableObject` and `@Published` for `@Observable`; the manager needs no change since it is already `@MainActor`.
- **Compose**: Android does not let one app move another app's windows, so parking and restoring have no equivalent; the portable part is the store (Kotlin `kotlinx.serialization` JSON files under `Context.filesDir`, `FileChannel.lock()` in place of `flock`) and the matcher. Expose model state as `StateFlow` from a `ViewModel` and run the manager on `Dispatchers.Main`.
- **React/Web**: Browsers cannot enumerate or move other applications' windows. An Electron port would keep the model and store in the main process (`fs.writeFileSync` to a temp file plus `fs.renameSync` for atomic replace, `proper-lockfile` for the lock) and move windows through a native module; renderer state would come over IPC into a store such as Zustand in place of `@Published`.
- **AppKit / UIKit**: This is the source (macOS only). `SystemWindowContextStore`, `SystemWindowContextsState`, `SystemWindowContextsSettings`, and the reconcile models live in the platform-neutral `Core` target and depend only on Foundation and `flock`. `SystemWindowContextManager`, `SystemWindowContextError`, and `SystemWindowContextsModel` live in `CoreMacOS` because they use `NSScreen.screens` for the parking x and the on-screen test, `CGWindowID`-valued `UInt32` IDs, Accessibility-backed `SystemWindowControlling` moves, `UNUserNotificationCenter`, and a PID from `ProcessInfo`. UIKit cannot manage other apps' windows, so only the `Core` files port to iOS.
- **WinUI 3**: Enumerate top-level windows with `EnumWindows` plus `GetWindowThreadProcessId` and `GetWindowText` (P/Invoke), and use `HWND` values in place of `CGWindowID`; HWNDs are also recycled, so keep the load-time invalidation. Park with `SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)` using x = `SystemInformation.VirtualScreen.Left` (or `GetSystemMetrics(SM_XVIRTUALSCREEN)`) minus 30000, restore with `SetWindowPlacement` or `SetWindowPos` and the saved `RECT`, and focus with `SetForegroundWindow` (subject to foreground-lock rules, so a failure is common and SHOULD be checked). Persist with `System.Text.Json` (`WriteIndented = true`) into `ApplicationData.Current.LocalFolder` for packaged apps or `Environment.SpecialFolder.LocalApplicationData` otherwise; write each file to a temp name and `File.Replace` or `File.Move(overwrite: true)` for atomic replace, and take the cross-process write lock with a named `Mutex` or a `FileStream` opened with `FileShare.None` on the `.lock` file. Model the manager as a class used only from the UI thread (`DispatcherQueue.HasThreadAccess` checks) to match `@MainActor`, and the model as a view model implementing `INotifyPropertyChanged` with `ObservableCollection<SystemWindowContext>` for `contexts` and `unmatchedItems`. Window lifecycle events come from `SetWinEventHook` with `EVENT_OBJECT_CREATE`, `EVENT_OBJECT_DESTROY`, and `EVENT_OBJECT_NAMECHANGE`, delivered on the thread that installed the hook, which gives the ordering the Swift source leaves open. Show the reconcile prompt with `AppNotificationManager` from the Windows App SDK, and put the `lastError` strings in `.resw` resources.

## Design Decisions

**Decision**: Inactive windows are parked 30,000 points left of the leftmost screen instead of being minimized or hidden.
**Rationale**: Per the `parkingMargin` doc comment, a parked window "can never land on a real screen (even on multi-monitor layouts)", and moving keeps the window's app, Space, and size intact, so restoring is a single set-frame; y is kept so a window restores in place.
**Approved**: pending

**Decision**: A live frame is captured into `savedFrame` only while it overlaps a screen horizontally.
**Rationale**: Per `captureFrameIfOnScreen`, a parked position or an OS-clamped park move "can never be persisted as the restore target"; the horizontal-only test avoids mixing CoreGraphics top-left y with AppKit bottom-left y.
**Approved**: pending

**Decision**: On load, a persisted window ID is invalidated when it is missing only if its app has a live window, and always when it now belongs to another app.
**Rationale**: `CGWindowID`s are not stable across restarts; the comment in `reconcilePersistedWindowIDs` explains that an app with zero live windows "may still be mid-launch", and clearing its IDs would orphan valid windows.
**Approved**: pending

**Decision**: Deleting the active context restores every context's windows, not just the deleted one's.
**Rationale**: With no active context nothing should stay parked; the comment in `deleteContext` notes that otherwise "the other contexts' windows are stranded off-screen with no way back."
**Approved**: pending

**Decision**: Switching to the already-active context re-shows its windows rather than throwing `alreadyActiveContext`.
**Rationale**: The source treats a repeat switch as a request to make the context's windows visible; `alreadyActiveContext` and `noActiveContext` remain in the error enum but nothing raises them.
**Approved**: pending

**Decision**: Custom heuristic rule changes write to disk before updating memory and the registry, while context changes update memory first and then persist.
**Rationale**: The `addCustomHeuristicRule` doc comment calls out "no phantom rule" after a failed write; context operations instead keep the in-memory change and surface `persistenceFailed`, so a failed write leaves memory ahead of disk until the next successful persist.
**Approved**: pending

**Decision**: Writes are serialized with an inter-process `flock` on `<root>/.lock`, reads are unlocked, and each file is replaced atomically.
**Rationale**: The store's doc comment names concurrent write corruption as the risk and keeps reads unlocked "for performance"; per-file atomic replace keeps each file whole for a concurrent reader.
**Approved**: pending

**Decision**: Own windows are excluded by process ID rather than by `selfAppName`.
**Rationale**: Per `isOwnWindow`, matching the owner name "silently fails when a host's display name differs from its process name"; the PID is host-name-independent.
**Approved**: pending

**Decision**: Test environments disable notifications, observation, and seeding, and the notification step checks the bundle identifier first.
**Rationale**: The source notes `UNUserNotificationCenter.current()` "crashes outside of a bundled app"; each switch is separate so a host can disable one without the others.
**Approved**: pending

**Decision**: `reconcileBehavior` is stored but not consulted by launch reconciliation.
**Rationale**: The model persists the setting for a host's settings UI; `performLaunchReconciliation()` implements the `prompt` behavior unconditionally, so honoring `auto` or `ignore` is the host's responsibility.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [encryption-at-rest](agenticdevelopercookbook://compliance/privacy-and-data#encryption-at-rest) | failed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`separation-of-concerns` passes: persistence is in the store, window and context logic in the `@MainActor` manager, SwiftUI publishing and user-facing messages in the model, and host branding in an injected configuration, with the window controller and matcher injected. `unit-test-coverage` is partial because `SystemWindowContextManagerTests` covers parking on attach, the no-active-context case, active-context deletion, and both load-time invalidation paths, but nothing tests the store, the settings decoder, the model, switching, or event re-matching. `explicit-error-handling` is partial: store and manager errors are typed and surfaced, but window-controller failures are discarded without a log (the open question on restore-failure-silent) and event operations log rather than surface persistence failures. `data-integrity` is partial because `saveAll` is atomic per file but not across files, and batch assignment can give one window to two snapshots. `state-recovery` passes because a corrupt context file is skipped rather than failing the load, and dormant snapshots keep fingerprints so windows re-attach after relaunch. `graceful-degradation` passes because a missing state file yields an empty state and a failed rules load yields an empty rule list. `no-hardcoded-strings` fails because every error and notification string is an English literal. `encryption-at-rest` fails because window titles and app names are stored in plain JSON. `no-pii-in-logs` passes because logged names and titles go through `Logger` interpolation, which is private by default.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | | Initial creation |
