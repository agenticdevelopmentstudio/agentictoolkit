<!-- leaf: implement-window-matching/system-windows-contexts--test-vectors · source: window-matching-system-windows-contexts.md -->

# Window Matching System Windows Contexts

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
