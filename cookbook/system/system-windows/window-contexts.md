---
id: aaf56f9b-896b-4f74-9e18-1ef4116270a9
title: Window Contexts
domain: agentictoolkit://cookbook/system/system-windows/window-contexts
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Named window contexts: a persisted store, a manager that parks and
  restores windows, fingerprint re-matching, and an observable model for
  switching between groups of windows.'
platforms:
- swift
- macos
tags:
- window-management
- system-windows
- window-matching
- persistence
depends-on: []
related:
- agentictoolkit://cookbook/system/system-windows/window-context-model
- agentictoolkit://cookbook/system/system-windows/system-windows-engine
- agentictoolkit://cookbook/system/system-windows/matching/title-heuristics
references:
- https://developer.apple.com/documentation/coregraphics/cgwindowid
- https://man7.org/linux/man-pages/man2/flock.2.html
approved-by: ''
approved-date: ''
---

# Window Contexts

## Overview

The contexts slice of the system-window feature groups other applications' windows into named **contexts** (workspaces such as "iOS App" or "Docs") and switches between them by moving every window that does not belong to the target context off-screen ("parking") and moving the target context's windows back to their saved frames. It consists of:

- **The contexts state** is the persisted top-level record (active context ID and ordered context IDs).
- **The context store** reads and writes that state and one JSON file per context under a caller-supplied root directory, serializing writes with a file lock. It also declares its own error type.
- **The contexts settings** are user-facing settings persisted by the host, together with the reconcile-behavior set of values.
- **The reconcile models** are value types — a reconcile item and a reconcile candidate — that a reconcile view lists after relaunch.
- **The context error** is the manager's error type.
- **The context manager** is the engine, confined to a single coordination context, that owns the contexts, parks and restores windows through an injected window-control contract, re-matches dormant window snapshots by fingerprint through the window matcher, manages custom heuristic rules through a custom-heuristic store, and persists after every mutation.
- **The contexts model** is an observable wrapper around the manager for a reactive UI layer: it turns thrown errors into a `lastError` string, drives launch reconciliation, receives window-lifecycle events as the window observer's delegate, and persists settings. It also declares the contexts configuration, the host's injected branding and defaults.

The data types these operate on — a window context and a window snapshot — the window matcher (whose auto-assign threshold is `80`), and the window-control contract live outside this slice and are referenced by role. A window is **live** when its snapshot's `windowID` is present and **dormant** when it is absent; a dormant snapshot keeps its fingerprint so it can be re-attached. Use this ingredient when an app needs persistent, switchable groups of third-party windows that survive the app quitting, the owning apps quitting, and a reboot that recycles window IDs.

## Behavioral Requirements

### Data shapes

- **state-shape**: The contexts state MUST hold `activeContextID` (optional) and `contextIDs` (a list), both defaulting to empty (absent, `[]`), and MUST be serializable, comparable for equality, and safe to use across concurrent execution contexts.
- **state-order-meaning**: `contextIDs` order MUST be the display order of contexts, where index 0 corresponds to keyboard shortcut 1.
- **state-excludes-settings**: The contexts state MUST NOT carry application settings; hosts persist the contexts settings separately.
- **settings-shape**: The contexts settings MUST hold `launchAtLogin` (default `false`), `reconcileBehavior` (default `prompt`), `hiddenApps` (default `[]`), and `showAppInDock` (default `false`), and MUST be serializable, comparable for equality, and safe to use across concurrent execution contexts.
- **settings-lenient-decode**: Decoding the contexts settings MUST substitute the default for each missing key, so `{}` decodes to the all-defaults value.
- **settings-typed-decode**: Decoding MUST fail when a present key holds the wrong type (for example `"launchAtLogin": "yes"`); only absence falls back to the default.
- **reconcile-behavior-cases**: The reconcile-behavior value MUST declare exactly `prompt`, `auto`, `ignore`, in that order, each with its name as its string raw value, and MUST support enumerating the complete list of values, serialization, equality comparison, and safe use across concurrent execution contexts.
- **reconcile-behavior-not-consumed**: The model MUST only store `reconcileBehavior` through its reconcile-behavior setter, and launch reconciliation always auto-applies matches and opens the reconcile UI for the rest, whatever the stored value.
- **reconcile-item-shape**: A reconcile item MUST carry `id` (the dormant snapshot's ID), `contextID`, `contextName`, `contextColor`, `app`, `titlePattern` (the fingerprint's title pattern), and `candidates` (a list of reconcile candidates), and MUST have a stable identity and support equality comparison.
- **reconcile-candidate-shape**: A reconcile candidate MUST carry `windowID`, `app`, `windowTitle`, and `score`, and its `id` MUST equal `windowID`.
- **reconcile-models-single-context**: A reconcile item and a reconcile candidate MUST NOT be usable across concurrency boundaries; they are confined to the single coordination context that creates them (the model's).
- **configuration-shape**: The contexts configuration MUST be safe to use across concurrent execution contexts and hold `selfAppName` (optional, default absent), `settingsKey` (required), `contextNoun` (default `"context"`), `contextNounPlural` (default the noun plus `"s"`), `notificationTitle` and `notificationIdentifier` (required), `defaultContexts` (a list, default `[]`), and `managesAppActivationPolicy` (default `true`).
- **error-descriptions-store**: Each context-store error case MUST produce its fixed English description: `directoryCreationFailed`, `encodingFailed`, `decodingFailed`, `writeFailed`, `readFailed` include the path (where present) and the underlying error's description; `lockAcquisitionFailed` reads "Failed to acquire file lock at <path>"; `contextNotFound` reads "Context not found: <uuid>".
- **error-descriptions-manager**: Each context error case MUST produce its fixed English description (for example `windowAlreadyAssigned` reads "Window <id> is already assigned to context '<name>'", `persistenceFailed` reads "Failed to persist state: <underlying>").
- **unraised-error-cases**: Callers MUST treat the context error's `alreadyActiveContext` and `noActiveContext` cases as declared but unraised: no operation raises either case.

### Store: layout and I/O

- **store-layout**: Constructing the context store with a root directory MUST place the state at `<root>/state.json`, one file per context at `<root>/contexts/<UUID uppercase string>.json`, and the lock file at `<root>/.lock`.
- **store-json-format**: The store MUST encode JSON pretty-printed with sorted keys and dates as ISO 8601, and MUST decode dates as ISO 8601.
- **store-ensure-directories**: Ensuring the directory structure MUST create `<root>` and `<root>/contexts` with intermediate directories, and MUST throw `directoryCreationFailed(path: <root>, underlying:)` when either creation fails.
- **store-load-state-missing**: Loading state MUST return an empty contexts state (no active context, no IDs) when `state.json` does not exist.
- **store-load-state-errors**: Loading state MUST throw `readFailed` when `state.json` exists but cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-load-context-missing**: Loading a context by `id` MUST throw `contextNotFound(id:)` when the context file does not exist, `readFailed` when it cannot be read, and `decodingFailed` when it cannot be decoded.
- **store-save-context**: Saving a context MUST write the encoded context to its file with an atomic (write-then-replace) file write while holding the lock, throwing `encodingFailed` or `writeFailed` on failure.
- **store-delete-context**: Deleting a context by `id` MUST remove the context file under the lock when it exists, and MUST succeed without effect when it does not; a removal failure propagates the underlying file-system error unwrapped.
- **store-load-all-order**: Loading all contexts MUST return them in the state's `contextIDs` order.
- **store-load-all-skips**: Loading all contexts MUST skip any context whose file is missing, unreadable, or undecodable, logging "Skipping context <id>: <error>" at error level, rather than failing the whole load.
- **store-load-all-state-error**: Loading all contexts MUST propagate the error when `state.json` itself cannot be read or decoded.
- **store-save-all-content**: Saving all contexts MUST, under one lock, write every context's file and then write `state.json` with `activeContextID` and `contextIDs` equal to the contexts' IDs in the given order.
- **save-all-not-atomic**: NEEDS REVIEW: Not implemented in source. The documentation says saving all contexts "updates the contexts state atomically", but each file is written independently; a failure on the Nth context throws after earlier context files are already replaced and before `state.json` is written, leaving disk partially updated. No rollback or journal exists; evidence that would settle it is whether the "atomically" contract is intended across files (a temp-directory swap) or only per file.
- **store-save-all-no-prune**: Saving all contexts MUST NOT delete context files for IDs absent from the given list; orphan removal happens only through deleting a context by `id`.
- **store-list-files**: Listing context files MUST return `[]` when `<root>/contexts` is absent, MUST return the UUIDs parsed from every `*.json` filename whose stem is a valid UUID (ignoring other files), and MUST throw `readFailed` when the directory cannot be listed. The order MUST be treated as unspecified (directory listing order).
- **store-remove-all**: Removing everything MUST delete `<root>` recursively when it exists, without taking the lock, and propagate the underlying error unwrapped.
- **store-lock**: Every write operation (saving a context, deleting a context, saving all contexts) MUST first ensure the directory structure, open or create `<root>/.lock` with mode `0644`, take an exclusive file lock, run the write, then release the lock and close the file exactly once.
- **store-lock-failure**: When the lock file cannot be opened, or the exclusive lock cannot be taken, the operation MUST throw `lockAcquisitionFailed(path:)` without running the write; on a failed lock the file MUST be closed once.
- **store-lock-blocking**: The lock MUST block until acquired; there is no timeout and no non-blocking attempt.
- **store-reads-unlocked**: Loading state, loading a context, loading all contexts, and listing context files MUST NOT take the lock.
- **store-concurrency-safe**: The context store MUST be usable from any thread; its safety rests on the write lock and on encoder and decoder instances that are configured once and never mutated.

### Manager: lifecycle and load

- **manager-single-context**: The context manager MUST be confined to a single coordination context; every operation runs there and its state has no internal locking.
- **manager-init**: Constructing the context manager MUST start with no contexts and no active context, and MUST default the custom-heuristic store to one rooted at the state store's root directory.
- **manager-load-state**: Loading state MUST read the active context ID and the contexts from the store, then invalidate stale window IDs, then load custom heuristic rules, and MUST propagate store read or decode errors on `state.json` unwrapped.
- **manager-load-no-active-check**: Loading state MUST keep a persisted `activeContextID` even when no loaded context has that ID (for example its file was skipped); looking up the active context then returns no value.
- **reconcile-stale-recycled**: On load, a snapshot whose `windowID` belongs to a live window of a different app (compared case-insensitively) MUST have its `windowID` cleared.
- **reconcile-stale-missing**: On load, a snapshot whose `windowID` is not in the live window list MUST have its `windowID` cleared only when its app has at least one live window; when its app has no live windows the `windowID` MUST be kept.
- **reconcile-stale-persist**: When at least one ID was cleared on load, the manager MUST log "Invalidated <n> stale window ID(s) on load" and persist; a persistence failure there MUST be logged and not thrown.
- **manager-root-directory**: `rootDirectory` MUST return the state store's root directory.

### Manager: context CRUD

- **create-context**: Creating a context MUST append a new context (new unique identifier, color default `"#007AFF"`, no snapshots), persist, and return it; it MUST NOT validate the name (empty and duplicate names are accepted) or the color string.
- **delete-context-missing**: Deleting, renaming, recoloring, or switching to a context MUST throw `contextNotFound(id:)` for an unknown ID without changing state.
- **delete-active-context**: Deleting the active context MUST clear `activeContextID` and restore every context's live windows to their saved frames (not only the deleted context's).
- **delete-inactive-context**: Deleting an inactive context MUST restore only that context's live windows to their saved frames.
- **delete-context-disk**: Deleting a context MUST remove it from memory, then delete its file via the store, then persist the remaining state.
- **rename-and-color**: Renaming a context and updating its color MUST set the field and persist, without validation.

### Manager: window assignment

- **add-window-duplicate**: Adding a window to a context MUST throw `windowAlreadyAssigned(windowID:contextName:)` when the window ID is on a snapshot in a different context.
- **add-window-refresh**: When the window ID is already in the target context, adding a window MUST refresh that snapshot's `savedFrame`, `title`, and `lastSeen` from the live window, persist, and return it instead of adding a second snapshot.
- **add-window-errors**: Adding a window MUST throw `contextNotFound` for an unknown context and `windowNotFound(windowID:)` when the ID is not among all live windows.
- **add-window-snapshot**: Adding a window MUST create a snapshot with the matcher's fingerprint for the window and the live window's frame, display, app, and title, append it to the context, persist, and return it.
- **park-on-attach**: Every operation that attaches a window to a context (add-window-snapshot, apply-matches, assign-to-snapshot, assign-batch, rematch-app, new-window-autoassign, custom-rule-autoassign) MUST park that window when there is an active context and the owning context is not it, and MUST NOT park it when no context is active.
- **remove-window**: Removing a window by `windowID` MUST remove the first snapshot carrying that window ID, move the window back to its saved frame when its context is not the active one, persist, and return the removed snapshot; it MUST throw `windowNotInAnyContext(windowID:)` when no snapshot carries the ID.
- **remove-clears-last-focused**: Removing a snapshot MUST clear the context's `lastFocusedWindowID` when it pointed at that snapshot.
- **set-last-focused**: Setting the last-focused window MUST record the snapshot ID of the matching window as the active context's `lastFocusedWindowID` and persist; it MUST do nothing, without error, when no context is active or the window is not in the active context.
- **context-lookup**: Looking up the context for a window ID MUST return the first context (in display order) with a snapshot carrying it, or no value.

### Manager: switching

- **switch-same-context**: Switching to the already-active context MUST restore its live windows to their saved frames and persist, and MUST NOT park any other context or throw.
- **switch-save-active**: Switching to a different context MUST, for each live window of the previously active context, capture its current frame into `savedFrame` (and update `lastSeen`) only when the frame overlaps some display horizontally, then park it.
- **switch-park-others**: Switching MUST park every live window of every other non-target context, first capturing any on-screen frame the same way.
- **switch-restore-target**: Switching MUST set every live window of the target context to its `savedFrame`.
- **switch-focus**: Switching MUST focus the target context's last-focused window when that snapshot exists and is live, else the first live window in the context, else nothing.
- **switch-commit**: Switching MUST set `activeContextID` to the target after parking, restoring, and focusing, then persist.
- **parking-position**: Parking MUST move a window's origin to x = (the minimum `minX` across all screens, or 0 when there are none) − `parkingMargin` (`30000`), keeping y equal to the snapshot's saved-frame y.
- **frame-capture-guard**: A window whose live frame does not overlap any screen horizontally MUST NOT have that frame saved, so a parked or clamped position never becomes a restore target.
- **window-ops-best-effort**: Park (move), restore (set frame), and focus calls to the window controller MUST NOT throw out of the manager; their failures are discarded — parking is declared best-effort, and accessibility failures are swallowed.
- **restore-failure-silent**: NEEDS REVIEW: Not implemented in source. A failed restore or un-park (setting a window's frame) when restoring windows to their saved positions or when removing a window is discarded with no log, return value, or error, so a window can stay parked 30000 points off every screen with no signal to the caller or user; parking's best-effort guarantee (window-ops-best-effort) covers only parking. Settled by deciding whether restore failures should be logged, counted, or surfaced.

### Manager: re-matching

- **has-stale-windows**: The has-stale-windows flag MUST be `true` exactly when some snapshot in some context has an absent `windowID`.
- **run-rematching**: Running re-matching MUST pass all contexts and all live windows to the window matcher's match operation and return its match result without mutating state.
- **apply-matches**: Applying matches MUST, for each matched pair whose context and snapshot still exist, set the snapshot's `windowID` and `title` from the matched window and `lastSeen` to now, park when required (park-on-attach), and return the count applied; pairs whose context or snapshot is gone MUST be skipped silently.
- **apply-matches-unconditional**: Applying matches MUST NOT re-check scores; every pair given to it has already cleared the matcher's threshold.
- **apply-matches-persist**: Applying matches MUST persist only when at least one pair was applied, and MUST throw `persistenceFailed` when that persist fails.
- **launch-rematching**: Performing launch re-matching MUST return no value without enumerating windows when the has-stale-windows flag is false, and otherwise run re-matching, apply the result, and return it.
- **assign-to-snapshot**: Assigning a window to a snapshot MUST set the snapshot's `windowID`, `title` (the live window's title, or `""` when the ID is not live), and `lastSeen`, park when required, and persist; it MUST throw `contextNotFound` for an unknown context and `windowNotInAnyContext(windowID:)` when the snapshot ID is not in that context.
- **assign-batch**: Assigning windows to snapshots in a batch MUST return 0 for an empty list without enumerating windows; otherwise enumerate windows once, apply each resolvable assignment as assign-to-snapshot does, skip unresolvable ones silently, persist once when at least one applied (a persistence failure is logged, not thrown), and return the count applied.
- **assignment-window-unvalidated**: NEEDS REVIEW: Not implemented in source. Assign-to-snapshot and assign-batch never check that the window ID is live or not already on another snapshot, unlike the check add-window-snapshot performs; auto-assigning all remaining matches builds each assignment from an item's top candidate independently, so two dormant snapshots sharing a top candidate both receive the same window ID. Settled by deciding whether a window may back two snapshots and, if not, which assignment wins.
- **remove-dormant**: Removing a dormant snapshot MUST remove the snapshot by its stable ID (whether dormant or live) and persist; it MUST throw `contextNotFound` for an unknown context and MUST succeed without change when the snapshot ID is absent.
- **dormant-snapshots**: Listing dormant snapshots MUST return every snapshot with an absent `windowID`, with its context's ID, name, and color, in context order then snapshot order.
- **score-window**: Scoring a window against a fingerprint MUST return the window matcher's score unchanged.

### Manager: window lifecycle events

- **mark-window-dormant**: Marking a window dormant MUST clear the `windowID` of the first snapshot carrying it, persist (failure logged, not thrown), and return the updated snapshot, or return no value when no snapshot carries it.
- **mark-app-dormant**: Marking an app's windows dormant MUST clear `windowID` on every live snapshot whose `app` equals the given name exactly (case-sensitive), persist when any changed, and return the count.
- **update-title**: Updating a window's title MUST set `title` and `lastSeen` on the first snapshot carrying the ID, persist, and return `true`, or return `false` when none carries it.
- **rematch-app**: Re-matching an app's dormant windows MUST consider only live windows of that app (case-insensitive) that are not already on any snapshot, and for each dormant snapshot of that app (in context then snapshot order) assign the highest-scoring remaining candidate whose score is at least the matcher's auto-assign threshold (80), first-seen winning ties; each window MUST be assigned at most once per call. It MUST persist when any matched and return the count.
- **new-window-autoassign**: Checking a new window for auto-assignment MUST return no value when the window is already on a snapshot; otherwise it MUST assign the window to the single dormant snapshot (across all contexts and apps) with the highest score of at least 80, first-seen winning ties, persist, and return that context's ID, or return no value when none qualifies.
- **custom-rule-autoassign**: Checking custom rules for auto-assignment MUST return no value when the window is already on a snapshot; otherwise it MUST take the first rule (in stored order) with `autoAssign` true, an `appName` equal to the window's app case-insensitively, a title that the rule's title match accepts, and a `targetContextName` equal case-insensitively to some context's name, add a new snapshot for the window to the first such context, persist, and return that context's ID; rules whose target name matches no context MUST be skipped.
- **event-persist-logged**: Lifecycle-event operations (mark-window-dormant, mark-app-dormant, update-title, rematch-app, new-window-autoassign, custom-rule-autoassign) MUST NOT throw; a persistence failure is logged at error level by the persist step and the in-memory change stands.

### Manager: persistence and custom rules

- **persist-after-mutation**: Every mutating manager operation MUST persist the whole state by saving all contexts after changing memory.
- **persist-error-wrap**: A persistence failure MUST be logged ("Failed to persist state: ...") and rethrown as the context error's `persistenceFailed(underlying:)` case by throwing operations.
- **memory-ahead-of-disk**: When persistence fails, the in-memory change MUST remain applied; context operations mutate memory before writing and do not roll back.
- **rules-load**: Loading custom heuristic rules MUST load them from the custom-heuristic store and register them with the matcher's registry; on failure it MUST log the error and set `customHeuristicRules` to `[]` without touching the registry.
- **rules-write-first**: Adding, updating, and deleting a custom heuristic rule MUST save the new rule list to disk before changing `customHeuristicRules` or the registry, so a failed write leaves memory, disk, and registry unchanged, and MUST propagate the save error.
- **rules-update-unknown**: Updating a custom heuristic rule MUST return without writing or throwing when no rule has the given ID.
- **rules-delete-unknown**: Deleting a custom heuristic rule MUST rewrite the unchanged list and succeed when no rule has the given ID.

### Model

- **model-single-context**: The contexts model MUST be confined to a single coordination context and publish `contexts`, `activeContextID`, `lastError`, `showReconcileWindow`, `showContextPicker`, `showHelp`, `showDiscovery`, `unmatchedItems`, `customHeuristicRules`, and `settings` as observable properties, so a reactive UI layer updates when any of them changes.
- **model-test-environment**: When `isTestEnvironment` is true (default: detected by the presence of the platform's test-framework class), the model MUST disable notifications, window observation, and default-context seeding.
- **model-settings-init**: The model MUST read its initial `settings` from persisted user settings keyed by `configuration.settingsKey`, defaulting to the all-defaults contexts settings value.
- **model-errors-to-string**: Every model operation that calls a throwing manager operation MUST catch the error, set `lastError` to "<English prefix>: <description>", log it at error level, and not rethrow.
- **model-sync**: After every successful manager mutation the model MUST copy `contexts`, `activeContextID`, and `customHeuristicRules` from the manager.
- **model-load-state**: Loading state MUST load the manager's state and, when no contexts exist and seeding is enabled, create each default-context entry from configuration in order, logging and continuing past any that fails; a load failure MUST set `lastError` to "Failed to load state: ..." and skip seeding.
- **model-launch-reconciliation**: Performing launch reconciliation MUST do nothing further when the manager reports no stale windows; otherwise it MUST apply auto-matches, rebuild `unmatchedItems`, and, when any remain, set `showReconcileWindow` to `true` and send the reconcile notification.
- **model-unmatched-items**: Refreshing unmatched items MUST produce one reconcile item per dormant snapshot, whose candidates are every live window not on any snapshot with a score above 0, sorted by score descending.
- **model-assign**: Assigning a candidate window to an unmatched item MUST set `lastError` to "Unmatched item not found." when the item ID is not in `unmatchedItems`, and otherwise assign and refresh.
- **model-skip**: Skipping an unmatched item MUST remove the item's dormant snapshot and refresh, and MUST do nothing when the item ID is unknown.
- **model-auto-assign-all**: Auto-assigning all remaining matches MUST assign each unmatched item that has candidates to its first (highest-scoring) candidate in one manager batch, and refresh only when at least one applied.
- **model-notification**: The reconcile notification MUST be sent only when notifications are enabled and the app's bundle identifier is present and not the platform test-runner's own identifier; it MUST request alert authorization and, only if granted, post an immediate, silent request with `configuration.notificationTitle`, identifier `configuration.notificationIdentifier`, and body "1 window needs assignment" or "<n> windows need assignment".
- **model-own-windows**: The model MUST exclude windows whose owner process ID equals its own from listing all windows, adding the frontmost window, and removing the frontmost window.
- **model-add-frontmost**: Adding the frontmost window MUST set `lastError` to "No active context. Switch to a context first." and return `false` when no context is active, set "No window found to add." and return `false` when no foreign on-screen window exists, and otherwise add the frontmost foreign window from the window list to the active context and return `true`.
- **model-remove-frontmost**: Removing the frontmost window MUST set `lastError` to "No window found to remove." or "This window is not assigned to any context." and return `false` in those cases, and otherwise remove the window and return `true`.
- **model-batch-add**: Adding windows in a batch MUST add each window independently, log a skipped window at debug level without setting `lastError`, and return the number added.
- **model-cycle**: Switching to the next or previous context MUST do nothing with fewer than 2 contexts, MUST wrap around, and with no active context MUST switch to the first (next) or last (previous) context.
- **model-settings-write**: Each settings setter MUST update the observable `settings` and write the whole value to persisted user settings in one step; setting Dock visibility MUST NOT change the application's activation policy.
- **model-hidden-apps**: Adding a hidden app MUST ignore a name already present (exact match) and otherwise append it and sort the list; removing a hidden app MUST remove every exact match.
- **model-observer-events**: The model's window-observer delegate callbacks arrive off the model's coordination context and MUST each hop back onto it before calling the manager: a window-destroyed event marks the window dormant, a window-created event tries dormant-snapshot matching and then custom rules, a window-title-changed event updates the title, an app-terminated event marks the app's windows dormant, and an app-launched event re-matches the app's dormant windows.
- **observer-event-ordering**: NEEDS REVIEW: Not implemented in source. Each delegate callback spawns an independent unit of work on the model's coordination context, and the source states no ordering between them, so a rapid app-terminated then app-launched event (or window-destroyed then window-created for a recycled ID) has no ordering guarantee beyond the scheduler's behavior. Settled by confirming the observer delivers events on a single thread and that work enqueued there is relied on to run in first-in-first-out order, or by serializing events through one queue.
- **model-observation-start**: Starting window observation MUST do nothing when observation is disabled, and otherwise create a window observer over the window manager, make the model its delegate, and start it; stopping window observation MUST stop and release it.

## Appearance

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## States

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## Accessibility

Not applicable — this is a window-context persistence store, switching engine, and observable model, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| contexts-001 | park-on-attach | Windows 1 (Xcode) and 2 (Warp); create "Active" and "Inactive"; switch to "Active"; reset the mock; add window 2 to the inactive context | The mock records a move of window 2 |
| contexts-002 | park-on-attach | Window 1; create one context, no switch; reset; add window 1 to the context | No move recorded |
| contexts-003 | delete-active-context | Window 1 in "Active", window 2 in "Other"; switch to "Active"; reset; delete the active context | `activeContextID` is absent; set-frame recorded for window 1 and window 2 |
| contexts-004 | reconcile-stale-missing, has-stale-windows | Persist a snapshot with window 99 (Xcode); reload with live windows = [7 (Xcode)]; load state | The has-stale-windows flag is `true` |
| contexts-005 | reconcile-stale-recycled | Persist a snapshot with window 42 (Xcode); reload with live windows = [42 (Finder)]; load state | The has-stale-windows flag is `true` |
| contexts-006 | reconcile-stale-missing | Persist a snapshot with window 99 (Xcode); reload with live windows = [5 (Warp)]; load state | The has-stale-windows flag is `false`; the snapshot keeps `windowID` `99` |
| contexts-007 | store-load-state-missing | Fresh empty root; load state | A contexts state with `activeContextID` absent and `contextIDs` empty |
| contexts-008 | store-layout, store-save-all-content, store-json-format | Save all contexts `[A, B]` with active context `B.id`, into an empty root | `<root>/contexts/<A.id>.json` and `<B.id>.json` exist; `state.json` decodes to `activeContextID == B.id`, `contextIDs == [A.id, B.id]`; the JSON keys appear sorted; `<root>/.lock` exists |
| contexts-009 | store-load-all-skips, store-load-all-order | After contexts-008, overwrite `<A.id>.json` with `not json`; load all contexts | Returns `[B]`; no error thrown |
| contexts-010 | store-load-state-errors | Write `{` to `state.json`; load state | Throws `decodingFailed` with the `state.json` path |
| contexts-011 | store-load-context-missing | Load a context with a freshly generated `id`, on an empty root | Throws `contextNotFound(id:)` with that ID |
| contexts-012 | store-list-files | List context files where `contexts/` holds `<valid uuid>.json`, `notes.txt`, `bad.json` | Returns exactly the one valid UUID |
| contexts-013 | store-delete-context | Delete a context with a freshly generated `id`, for a file that does not exist | Succeeds with no error |
| contexts-014 | store-save-all-no-prune | Save all contexts `[A, B]` with no active context, then save all contexts `[B]` with no active context | `<A.id>.json` still exists; `state.json` lists only `B.id` |
| contexts-015 | settings-lenient-decode | Decode `{}` as the contexts settings | `launchAtLogin == false`, `reconcileBehavior == prompt`, `hiddenApps == []`, `showAppInDock == false` |
| contexts-016 | settings-typed-decode | Decode `{"launchAtLogin": "yes"}` | Throws a decoding error |
| contexts-017 | reconcile-behavior-cases | The raw values of the complete reconcile-behavior list, in order | `["prompt", "auto", "ignore"]` |
| contexts-018 | add-window-duplicate | Window 1 in context A; add window 1 to context B | Throws `windowAlreadyAssigned(windowID: 1, contextName: "A")` |
| contexts-019 | add-window-refresh | Window 1 in A; change the mock's frame for window 1; add window 1 to context A | A still has one snapshot; its `savedFrame` equals the new frame |
| contexts-020 | add-window-errors | Add window 555 to context A, with no window 555 live | Throws `windowNotFound(windowID: 555)` |
| contexts-021 | delete-context-missing | Switch to a context with a freshly generated `id` | Throws `contextNotFound`; no move or set-frame recorded |
| contexts-022 | switch-same-context | Active A holding window 1; reset; switch to context A | Set-frame recorded for window 1; no move recorded; no error |
| contexts-023 | switch-restore-target, switch-focus, switch-commit | A holds window 1, B holds window 2, A active; switch to context B | Window 1 moved; window 2 set to its saved frame; focus recorded for window 2; `activeContextID == B.id` |
| contexts-024 | parking-position | Single screen with `minX == 0`; park window 1 whose saved frame y is 50 | Move to (−30000, 50) |
| contexts-025 | frame-capture-guard | Active A with window 1 whose live frame x is −30000 (off every screen); switch to context B | Window 1's `savedFrame` is unchanged |
| contexts-026 | remove-window | Window 2 in inactive B while A is active; remove window 2 | Returns the snapshot; set-frame recorded for window 2 to its saved frame |
| contexts-027 | remove-window | Remove window 777, with no snapshot carrying it | Throws `windowNotInAnyContext(windowID: 777)` |
| contexts-028 | set-last-focused | No active context; set the last-focused window to 1 | Returns without error; no persist |
| contexts-029 | launch-rematching | All snapshots live; perform launch re-matching | Returns no value |
| contexts-030 | assign-to-snapshot | Assign window 1 to a snapshot with a freshly generated `id` in context A | Throws `windowNotInAnyContext(windowID: 1)` |
| contexts-031 | assign-batch | Assign windows to snapshots in a batch, with an empty list | Returns 0; no windows enumerated |
| contexts-032 | mark-app-dormant | Live snapshot with `app == "Xcode"`; mark app "xcode"'s windows dormant | Returns 0; snapshot still live |
| contexts-033 | rematch-app | Dormant Xcode snapshot; live Xcode window scoring 80 against it; re-match dormant windows for app "XCODE" | Returns 1; snapshot's `windowID` is the window's ID |
| contexts-034 | new-window-autoassign | Dormant snapshot; new window scoring 79 | Checking the new window for auto-assignment returns no value; snapshot stays dormant |
| contexts-035 | custom-rule-autoassign | Rule `autoAssign: true`, app "Safari", target "docs"; context named "Docs"; new Safari window whose title the rule matches | Returns the "Docs" context ID; the context gains a snapshot for the window |
| contexts-036 | rules-write-first | Custom heuristic store whose save throws; add custom heuristic rule `r` | Throws; `customHeuristicRules` unchanged |
| contexts-037 | model-add-frontmost | Model with no active context; add the frontmost window | Returns `false`; `lastError == "No active context. Switch to a context first."` |
| contexts-038 | model-cycle | Contexts [A, B, C], active C; switch to the next context | Active becomes A |
| contexts-039 | model-hidden-apps | `hiddenApps` is `["Zed"]`; add hidden app "Arc"; add hidden app "Arc" again | `hiddenApps == ["Arc", "Zed"]` |
| contexts-040 | model-unmatched-items | One dormant snapshot; live unassigned windows scoring 30, 0, 90 | One item; candidates scored `[90, 30]` |
| contexts-041 | persist-error-wrap, memory-ahead-of-disk | Make `<root>/contexts` read-only; rename context A to "X" | Throws `persistenceFailed`; `contexts` shows A named "X" |
| contexts-042 | model-test-environment | Construct the model with `isTestEnvironment: true` | `notificationsEnabled == false`; `observationEnabled == false`; loading state on an empty store leaves `contexts` empty |

## Edge Cases

- **Empty root directory**: first launch — loading state MUST yield no contexts and no active context; the model then seeds `defaultContexts` unless in a test environment.
- **Missing context file referenced by state**: loading all contexts MUST skip it with an error log; the ID drops out of `contextIDs` on the next persist, and the orphan never reappears.
- **Orphan context file not referenced by state**: it MUST stay on disk untouched; the manager never reads the context-file listing.
- **Active ID points at a skipped context**: `activeContextID` MUST keep the dangling ID and looking up the active context MUST return no value; switching to the next context then switches to the first context.
- **Corrupt `state.json`**: loading state MUST throw `decodingFailed`; the model sets `lastError` and does not seed defaults, so existing context files are not overwritten on that launch.
- **Empty or duplicate context names**: accepted (create-context); custom-rule auto-assignment picks the first context in display order whose name matches case-insensitively.
- **Malformed color string**: stored unchanged; a `#`-prefixed hex string is only the caller's documented precondition.
- **Owning app mid-launch at load**: a persisted window ID whose app has zero live windows MUST be kept, so the window is not orphaned; re-matching reconciles it later.
- **Recycled window ID**: a persisted ID now owned by another app MUST be cleared on load (reconcile-stale-recycled).
- **No screens**: no displays are available — the parking x MUST be −30000, and no frame is captured because nothing overlaps a screen.
- **Window already off-screen when its context is deactivated**: its saved frame MUST NOT be overwritten (frame-capture-guard).
- **Window-controller failure**: move, set-frame, and focus errors are discarded; parking failures are declared best-effort, and the open question on restore-failure-silent covers restores.
- **Persistence failure**: throwing operations MUST throw `persistenceFailed` with memory left ahead of disk; event operations and batch assignment MUST log and continue. A mid-save-all failure leaves disk partially updated (the open question on save-all-not-atomic).
- **Lock contention**: a second process writing the same root MUST block on the file lock until the first finishes; there is no timeout.
- **Reads during a write**: unlocked reads MUST see either the old or the new version of each file, because each file is replaced with an atomic write; they MAY see a new context file alongside an old `state.json` mid-save-all.
- **Same window assigned twice**: the batch and single assignment APIs do not reject it (the open question on assignment-window-unvalidated).
- **Assign to a window that is no longer live**: the snapshot MUST still receive the ID and an empty title.
- **Case mismatch in app names**: marking an app's windows dormant compares exactly, while re-matching an app's dormant windows, load-time invalidation, and custom rules compare case-insensitively.
- **Unknown rule ID on update**: silent no-op (rules-update-unknown).
- **Notification authorization denied**: no notification is posted and nothing is logged; the Reconcile window flag is still set.
- **Running outside an app bundle**: the notification step MUST return before touching the system notification center, which crashes without a bundle identifier.
- **`reconcileBehavior` set to `ignore` or `auto`**: launch reconciliation still runs the `prompt` behavior (reconcile-behavior-not-consumed).
- **Concurrent access**: the manager and model are confined to a single coordination context, so their operations are serialized and cannot interleave; the store is safe to use from any thread, with writes serialized by an inter-process file lock. Observer events arrive as independent units of work on that same coordination context (the open question on observer-event-ordering).
- **Cancellation and timeouts**: no operation supports cancellation or has a timeout; all work is synchronous on the calling coordination context except the notification authorization callback.
- **Offline or disconnected state**: not applicable; the component performs no network access.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Context store: root directory | file-system location | none (required) | Root holding `state.json`, `contexts/`, `.lock`, and (by default) the custom rules file `heuristics.json`. |
| Window manager | window-control contract | none (required) | Lists windows and moves, resizes, focuses, and frames them; injected into both manager and model. |
| Window matcher | window matcher | a default window matcher | Fingerprinting, scoring, and batch matching; auto-assign threshold is `80`. |
| Custom heuristic store | optional custom-heuristic store | store at the state root | Persists user-defined heuristic rules. |
| Context manager: parking margin | number | `30000` | Distance left of the leftmost screen where inactive windows are parked. |
| Creating a context: `color` | string | `"#007AFF"` | Context color hex string. |
| Configuration: `selfAppName` | optional string | absent | Host app name exposed to views; own windows are excluded by process ID, not by this name. |
| Configuration: `settingsKey` | string | none (required) | Persisted-settings key for the contexts settings. |
| Configuration: `contextNoun` / `contextNounPlural` | string | `"context"` / noun + `"s"` | Nouns used in create-failure messages and exposed to views. |
| Configuration: `notificationTitle` / `notificationIdentifier` | string | none (required) | Reconcile notification title and request identifier. |
| Configuration: `defaultContexts` | list of default contexts | `[]` | Contexts seeded on first launch. |
| Configuration: `managesAppActivationPolicy` | boolean | `true` | Tells the settings UI whether to show the Dock toggle. |
| `isTestEnvironment` | boolean | detected by the presence of the platform's test-framework class | Disables notifications, observation, and seeding. |
| `notificationsEnabled` / `observationEnabled` | boolean | `true` (false in tests) | Runtime switches on the model. |
| Contexts settings fields | see settings-shape | see settings-shape | Launch at login, reconcile behavior, hidden apps, Dock visibility. |

## Deep Linking

Not applicable: none of these components registers a URL scheme, route, or navigation entry point; contexts are switched only by direct calls.

## Localization

Every user-facing string in these components is a hardcoded English literal with no string-catalog lookup: the description of both error types, the model's `lastError` prefixes, and the notification body.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `Failed to load state: <error>` | `lastError` when loading state fails |
| (none; literal) | `Failed to create <contextNoun>: <error>` | `lastError` on create; the noun comes from configuration |
| (none; literal) | `Failed to delete context: <error>` / `Failed to rename context: <error>` / `Failed to update context color: <error>` / `Failed to switch context: <error>` | `lastError` on those operations |
| (none; literal) | `Failed to add window: <error>` / `Failed to remove window: <error>` / `Failed to assign window: <error>` / `Failed to skip item: <error>` | `lastError` on window operations |
| (none; literal) | `Failed to add heuristic rule: <error>` / `Failed to update heuristic rule: <error>` / `Failed to delete heuristic rule: <error>` | `lastError` on rule operations |
| (none; literal) | `Re-matching failed: <error>` | `lastError` from launch reconciliation |
| (none; literal) | `Unmatched item not found.` | `lastError` from assigning a window |
| (none; literal) | `No active context. Switch to a context first.` | `lastError` from adding the frontmost window |
| (none; literal) | `No window found to add.` / `No window found to remove.` | `lastError` from the frontmost-window actions |
| (none; literal) | `This window is not assigned to any context.` | `lastError` from removing the frontmost window |
| (none; literal) | `<n> window needs assignment` / `<n> windows need assignment` | Notification body, pluralized by an English-only `count == 1` test |
| (none; literal) | `Context not found: <uuid>`, `Window <id> is already assigned to context '<name>'`, `Failed to persist state: <error>`, and the other error descriptions | Surfaced through `lastError` via the underlying error's description |

Only `contextNoun` is host-configurable; the other messages say "context" regardless of the configured noun.

## Accessibility Options

Not applicable: the component has no visual surface, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: the source reads no feature-flag key; `notificationsEnabled`, `observationEnabled`, and `isTestEnvironment` are test switches, not flags.

## Analytics

Not applicable: none of the components emits analytics events.

## Privacy

- **Data collected**: application names, window titles, window frames, and display IDs of other applications' windows, plus user-chosen context names and colors and custom rule definitions.
- **Storage**: plain, unencrypted, pretty-printed JSON files under the caller-supplied root (`state.json`, `contexts/<uuid>.json`, `heuristics.json`), written with mode defaults except the `.lock` file (`0644`); settings go to persisted user settings under `settingsKey`.
- **Transmission**: nothing leaves the device; the only outbound effect is a local user notification whose body carries a count, not titles.
- **Retention**: files persist until the context is deleted (its file is removed), everything is removed, or the user deletes the directory; skipped or orphaned context files are never cleaned up automatically.
- **Logs**: log messages interpolate context names, app names, and window IDs (for example "Created context '<name>'"); logged values are private by default, so those values are redacted in release logs unless marked public.

## Logging

Subsystem: the app's main bundle identifier | Category: the component's role name (the context store, the context manager, the contexts model)

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
- **AppKit / UIKit**: This is the source (macOS only). `SystemWindowContextStore`, `SystemWindowContextsState`, `SystemWindowContextsSettings`, and the reconcile models live in the platform-neutral `Core` target and depend only on Foundation and `flock`. `SystemWindowContextManager`, `SystemWindowContextError`, and `SystemWindowContextsModel` live in `CoreMacOS` because they use `NSScreen.screens` for the parking x and the on-screen test, `CGWindowID`-valued `UInt32` IDs, Accessibility-backed `SystemWindowControlling` moves, `UNUserNotificationCenter`, and a PID from `ProcessInfo`. UIKit cannot manage other apps' windows, so only the `Core` files port to iOS. `SystemWindowContextManager` and `SystemWindowContextsModel` are both `@MainActor`; the model is also an `ObservableObject` publishing its properties with `@Published`, which is what a SwiftUI view observes. `SystemWindowContextStore` is `@unchecked Sendable`, asserting to the compiler that its lock-guarded writes and immutable coder configuration make it safe to call from any thread. `ReconcileItem` and `ReconcileCandidate` are plain public structs without a `Sendable` conformance, so the compiler confines them to the isolation domain that creates them (the model's main-actor context); the model's `SystemWindowObserverDelegate` callbacks are declared `nonisolated` and each hop onto the main actor in a new unstructured `Task` before calling into the manager, which is the source of the open ordering question. `isTestEnvironment` defaults to whether `NSClassFromString("XCTestCase")` resolves to a class, and the reconcile notification additionally checks that the main bundle identifier is not `com.apple.dt.xctest.tool` before calling `UNUserNotificationCenter`. Logging subsystem and category come from a `Loggable` protocol keyed by the main bundle identifier and the Swift type name, and `Logger` string interpolation is private by default, which is why logged values need an explicit public marker to appear in release logs.
- **WinUI 3**: Enumerate top-level windows with `EnumWindows` plus `GetWindowThreadProcessId` and `GetWindowText` (P/Invoke), and use `HWND` values in place of `CGWindowID`; HWNDs are also recycled, so keep the load-time invalidation. Park with `SetWindowPos(hwnd, IntPtr.Zero, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)` using x = `SystemInformation.VirtualScreen.Left` (or `GetSystemMetrics(SM_XVIRTUALSCREEN)`) minus 30000, restore with `SetWindowPlacement` or `SetWindowPos` and the saved `RECT`, and focus with `SetForegroundWindow` (subject to foreground-lock rules, so a failure is common and SHOULD be checked). Persist with `System.Text.Json` (`WriteIndented = true`) into `ApplicationData.Current.LocalFolder` for packaged apps or `Environment.SpecialFolder.LocalApplicationData` otherwise; write each file to a temp name and `File.Replace` or `File.Move(overwrite: true)` for atomic replace, and take the cross-process write lock with a named `Mutex` or a `FileStream` opened with `FileShare.None` on the `.lock` file. Model the manager as a class used only from the UI thread (`DispatcherQueue.HasThreadAccess` checks) to match `@MainActor`, and the model as a view model implementing `INotifyPropertyChanged` with `ObservableCollection<SystemWindowContext>` for `contexts` and `unmatchedItems`. Window lifecycle events come from `SetWinEventHook` with `EVENT_OBJECT_CREATE`, `EVENT_OBJECT_DESTROY`, and `EVENT_OBJECT_NAMECHANGE`, delivered on the thread that installed the hook, which gives the ordering the Swift source leaves open. Show the reconcile prompt with `AppNotificationManager` from the Windows App SDK, and put the `lastError` strings in `.resw` resources.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/Contexts/ReconcileModels.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/Contexts/SystemWindowContextStore.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/Contexts/SystemWindowContextsSettings.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SystemWindows/Contexts/SystemWindowContextsState.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/Contexts/SystemWindowContextError.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/Contexts/SystemWindowContextManager.swift` |
| apple | `packages/apple/AgenticToolkit/CoreMacOS/SystemWindows/Contexts/SystemWindowContextsModel.swift` |

## Design Decisions

**Decision**: Inactive windows are parked 30,000 points left of the leftmost screen instead of being minimized or hidden.
**Rationale**: Per the `parkingMargin` doc comment, a parked window "can never land on a real screen (even on multi-monitor layouts)", and moving keeps the window's app, Space, and size intact, so restoring is a single set-frame; y is kept so a window restores in place.
**Approved**: pending

**Decision** (Apple platforms): A live frame is captured into `savedFrame` only while it overlaps a screen horizontally.
**Rationale**: Per `captureFrameIfOnScreen`, a parked position or an OS-clamped park move "can never be persisted as the restore target"; the horizontal-only test avoids mixing CoreGraphics top-left y with AppKit bottom-left y.
**Approved**: pending

**Decision** (Apple platforms): On load, a persisted window ID is invalidated when it is missing only if its app has a live window, and always when it now belongs to another app.
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

**Decision** (Apple platforms): Writes are serialized with an inter-process `flock` on `<root>/.lock`, reads are unlocked, and each file is replaced atomically.
**Rationale**: The store's doc comment names concurrent write corruption as the risk and keeps reads unlocked "for performance"; per-file atomic replace keeps each file whole for a concurrent reader.
**Approved**: pending

**Decision**: Own windows are excluded by process ID rather than by `selfAppName`.
**Rationale**: Per `isOwnWindow`, matching the owner name "silently fails when a host's display name differs from its process name"; the PID is host-name-independent.
**Approved**: pending

**Decision** (Apple platforms): Test environments disable notifications, observation, and seeding, and the notification step checks the bundle identifier first.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to system/system-windows/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | | Initial creation |
