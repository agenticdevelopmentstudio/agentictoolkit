<!-- leaf: implement-window-management/window-manager--test-vectors · source: window-management-window-manager.md -->

# WindowManager

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wm-001 | terminating-default, terminating-latch | Fresh manager; post `NSApplication.willTerminateNotification` | `isTerminating` is `false` before, `true` after (`WindowManagerTerminationTests`) |
| wm-002 | terminating-consumer | Visibility-persisting controller shown (visibility `true`); `isTerminating = true`; call `windowWillClose(_:)` | Persisted visibility stays `true` |
| wm-003 | terminating-consumer | Same, `isTerminating == false`; call `windowWillClose(_:)` | Persisted visibility becomes `false` |
| wm-004 | recent-limit-write | `recentWindowsCount = 7`, call `applyRecentDocumentCountFromSettings()`; then `3` and call again | `NSRecentDocumentsLimit` reads `7`, then `3` (`WindowManagerRecentsTests`) |
| wm-005 | recent-limit-mirror, recent-limit-on-init | Touch `WindowManager.shared`; set `recentWindowsCount = 12`; wait one main-queue turn | `NSRecentDocumentsLimit` reads `12` |
| wm-006 | register-restorable, restore-builds-all | Register factories `alpha` and `beta`; call `restoreOnLaunch()` | Both factories ran; built set is `{alpha, beta}` (`WindowManagerSimulatedRelaunchTests`) |
| wm-007 | register-restorable | Call `registerRestorable(id:make:)` without calling `restoreOnLaunch()` | Factory has not run |
| wm-008 | register-restorable | Register two factories under the same ID; call `restoreOnLaunch()` | Only the second factory runs |
| wm-009 | restore-visibility-pass, restore-visibility-rule | Registered visibility-persisting controller with persisted visibility `true`; `restoreOnLaunch()` | Window is shown |
| wm-010 | restore-visibility-rule | Same with persisted `false`, and again with no persisted value | Window stays closed in both cases |
| wm-011 | restore-missing-factory-log | `UserDefaultsWindowStateStorage` with visibility `true` for `ghost`; no factory, no controller; `restoreOnLaunch()` | One error log naming `ghost` |
| wm-012 | reopen-no-app | Headless process with no `NSApplication`; `reopenRecentsOnLaunch()` | Returns; no crash; nothing opened |
| wm-013 | reopen-policy | `shouldReopen(systemDefault:)` for `useSystem`/`always`/`never` with `true` and `false` | `true`/`false`; `true`/`true`; `false`/`false` |
| wm-014 | reopen-disabled-closes, reopen-disabled-keeps-others | Policy `never`; one document window and one non-document window open; `reopenRecentsOnLaunch()` | Document window's controller closed; non-document window still open |
| wm-015 | reopen-enabled-opens-recents | Policy `always`; recents `[A, B]`; `A` already open | One open request, for `B`, with `display: true` |
| wm-016 | close-ignored | `windowDidInteract(controller, kind: .close)` with an `.includeInRecents` document controller | No recent URL noted |
| wm-017 | spec-gate | `.show` for a document controller whose spec lacks `.includeInRecents` (and one with no spec) | No recent URL noted |
| wm-018 | document-recent | `.show` for a controller with default behavior and document URL `U` | `noteNewRecentDocumentURL(U)` called once |
| wm-019 | registry-register, registry-lookup | Register controller `a`; look up `a` and `b` | Returns the controller for `a`, `nil` for `b` |
| wm-020 | registry-empty-id | Register a controller with `windowID == ""` | `registeredIDs` is empty |
| wm-021 | registry-registered-ids, registry-has-visible | Register a controller without showing it | `registeredIDs` contains it; `hasVisibleWindow` is `false` (`WindowRegistryVisibilityTests`) |
| wm-022 | registry-visible-ids, registry-has-visible | Register and show a controller | `visibleIDs` contains it; `hasVisibleWindow` is `true` |
| wm-023 | registry-has-visible | Show then `dismiss()` the only controller | `hasVisibleWindow` is `false` |
| wm-024 | registry-has-visible | One closed and one shown controller | `hasVisibleWindow` is `true` |
| wm-025 | registry-lookup, registry-no-pruning | Register, show, dismiss, release the only strong reference | `controller(forID:)` is `nil`; `hasVisibleWindow` is `false` |
| wm-026 | storage-visibility-tristate | Fresh key; load; save `false`; load | `nil`, then `false` |
| wm-027 | storage-remove | Save state and visibility for `w`; remove both; load both | Both `nil` |
| wm-028 | storage-key-format, namespace-default | Namespace empty; save visibility for `log` with default prefixes | Defaults key is `WindowVisible_log` |
| wm-029 | namespace-default, namespace-qualify | `qualify("WindowState_log")` with no namespace set | `WindowState_log` (`WindowStateNamespaceTests`) |
| wm-030 | namespace-token, namespace-stable | `isolate(toPath: "/a/worktree/Stenographer.app")` | `current == "Instance2e03b243_"`; same value on a repeat call |
| wm-031 | namespace-token | `isolate(toPath: "/another/worktree/Stenographer.app")` | `current == "Instance30aace28_"`, differs from wm-030 |
| wm-032 | namespace-no-raw-path | `isolate(toPath: "/Users/someone/secret-project/Stenographer.app")` | `current` contains neither `someone` nor `secret-project` |
| wm-033 | storage-namespace-late-binding, userdefaults-visible-ids | Save state and visibility `true` for `log` un-namespaced; isolate; load both and list visible IDs; save visibility `false`; reset; load | Namespaced loads are `nil` and `log` is not listed; after reset visibility is `true` and `log` is listed |
| wm-034 | namespace-reset | Isolate to any path, then `reset()` | `current == ""` |
| wm-035 | storage-state-json | Save a state through `SettingsStoreWindowStateStorage` over a UserDefaults-backed store; load through `UserDefaultsWindowStateStorage` | Equal state returned |
| wm-036 | settings-store-non-bool-visibility | Write the string `"x"` under `WindowVisible_w`; load via each implementation | `SettingsStoreWindowStateStorage` returns `false`; `UserDefaultsWindowStateStorage` returns `nil` |
| wm-037 | visible-ids-default | Storage double that omits `visibleWindowIDs()` | Returns `[]` |
| wm-038 | screenshot-capture | `captureOwnWindow(0)` | `nil` (`WindowScreenshotTests`) |
| wm-039 | screenshot-png-offscreen | `writePNG(of:to:)` on a never-ordered-in window | Returns `false`; no file at the URL |
| wm-040 | screenshot-png-success | `writePNG(of:to:)` on an on-screen window owned by the process, writable URL | Returns `true`; file holds PNG data |
| wm-041 | screenshot-png-failure | On-screen window; URL in a non-existent directory | Returns `false` |
| wm-042 | single-screen-manager | `WindowManager(screenProvider:storage:)` with no `screenManager` | `frames` uses `ScreenManager.shared` |
