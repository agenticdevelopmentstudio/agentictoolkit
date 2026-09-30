<!-- leaf: implement-window-matching/system-windows-contexts--part-3 · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts — continued (part 3)

**Rules** (cite as `implement-window-matching/system-windows-contexts--part-3#<slug>`):

- `create-context` MUST
- `delete-context-missing` MUST
- `delete-active-context` MUST
- `delete-inactive-context` MUST
- `delete-context-disk` MUST
- `rename-and-color` MUST
- `add-window-duplicate` MUST
- `add-window-refresh` MUST
- `add-window-errors` MUST
- `add-window-snapshot` MUST
- `park-on-attach` MUST
- `remove-window` MUST
- `remove-clears-last-focused` MUST
- `set-last-focused` MUST
- `context-lookup` MUST
- `switch-same-context` MUST
- `switch-save-active` MUST
- `switch-park-others` MUST
- `switch-restore-target` MUST
- `switch-focus` MUST
- `switch-commit` MUST
- `parking-position` MUST
- `frame-capture-guard` MUST
- `window-ops-best-effort` MUST
- `has-stale-windows` MUST
- `run-rematching` MUST
- `apply-matches` MUST
- `apply-matches-unconditional` MUST
- `apply-matches-persist` MUST
- `launch-rematching` MUST
- `assign-to-snapshot` MUST
- `assign-batch` MUST
- `remove-dormant` MUST
- `dormant-snapshots` MUST
- `score-window` MUST

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

