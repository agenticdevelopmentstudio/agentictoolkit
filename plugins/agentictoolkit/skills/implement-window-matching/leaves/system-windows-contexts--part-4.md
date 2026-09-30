<!-- leaf: implement-window-matching/system-windows-contexts--part-4 · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts — continued (part 4)

**Rules** (cite as `implement-window-matching/system-windows-contexts--part-4#<slug>`):

- `mark-window-dormant` MUST
- `mark-app-dormant` MUST
- `update-title` MUST
- `rematch-app` MUST
- `new-window-autoassign` MUST
- `custom-rule-autoassign` MUST
- `event-persist-logged` MUST
- `persist-after-mutation` MUST
- `persist-error-wrap` MUST
- `memory-ahead-of-disk` MUST
- `rules-load` MUST
- `rules-write-first` MUST
- `rules-update-unknown` MUST
- `rules-delete-unknown` MUST
- `model-main-actor` MUST
- `model-test-environment` MUST
- `model-settings-init` MUST
- `model-errors-to-string` MUST
- `model-sync` MUST
- `model-load-state` MUST
- `model-launch-reconciliation` MUST
- `model-unmatched-items` MUST
- `model-assign` MUST
- `model-skip` MUST
- `model-auto-assign-all` MUST
- `model-notification` MUST
- `model-own-windows` MUST
- `model-add-frontmost` MUST
- `model-remove-frontmost` MUST
- `model-batch-add` MUST
- `model-cycle` MUST
- `model-settings-write` MUST
- `model-hidden-apps` MUST
- `model-observer-events` MUST
- `model-observation-start` MUST

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

