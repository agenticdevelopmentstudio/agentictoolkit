<!-- leaf: implement-git-client/projects-user-settings-projects--test-vectors · source: git-client-projects-user-settings-projects.md -->

# UserSettings+Projects

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-user-settings-projects-001 | skip-patterns-key | Read `UserSettings.projectScanSkipPatterns.name` | equals the string `"projectScanSkipPatterns"` |
| git-client-projects-user-settings-projects-002 | skip-patterns-default | Read `UserSettings.projectScanSkipPatterns.defaultValue` | equals `["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox", "Google Drive"]` |
| git-client-projects-user-settings-projects-003 | highlight-active-pane-key, highlight-active-pane-default | Read `UserSettings.highlightActivePane.name` and `.defaultValue` | `name` equals `"highlight_active_pane"`; `defaultValue` equals `true` |
| git-client-projects-user-settings-projects-004 | follows-mouse-key, follows-mouse-default | Read `UserSettings.activePaneFollowsMouse.name` and `.defaultValue` | `name` equals `"active_pane_follows_mouse"`; `defaultValue` equals `false` |
| git-client-projects-user-settings-projects-005 | value-round-trip | Set `UserSettings.projectScanSkipPatterns.value = ["Archive*"]`, then read `.value` | equals `["Archive*"]` |
| git-client-projects-user-settings-projects-006 | value-round-trip | Set `UserSettings.highlightActivePane.value = false`, then read `.value` | equals `false` |
| git-client-projects-user-settings-projects-007 | array-setting-json-encoded | Set `UserSettings.projectScanSkipPatterns.value = ["Foo"]`, then inspect the raw object `UserDefaults.standard` holds under `"projectScanSkipPatterns"` | the stored object is `Data`, not a native array; JSON-decoding that `Data` as `[String]` yields `["Foo"]` |
| git-client-projects-user-settings-projects-008 | bool-settings-natively-stored | Set `UserSettings.highlightActivePane.value = false`, then inspect the raw object `UserDefaults.standard` holds under `"highlight_active_pane"` | the stored object casts directly to `Bool` (`false`), not `Data` |
| git-client-projects-user-settings-projects-009 | removal-reverts-to-default | Set `UserSettings.activePaneFollowsMouse.value = true`, call `.remove()`, then read `.value` | equals `false` (`defaultValue`) |
| git-client-projects-user-settings-projects-010 | existence-check | Before any write, call `UserSettings.highlightActivePane.existsInStore()`; then set `.value = false` and call it again | first call returns `false`; second call returns `true` |
| git-client-projects-user-settings-projects-011 | not-secure | Read `.isSecure` on all three settings | each equals `false` |
| git-client-projects-user-settings-projects-012 | corrupt-data-falls-back-to-default | Store a JSON payload that does not decode as `[String]` (for example an encoded object, not an array) directly under `"projectScanSkipPatterns"` in the backing `UserDefaults`, then read `.value` | returns `GitRepoScanner.defaultRootSkipPatterns` (`defaultValue`), with no thrown error |
| git-client-projects-user-settings-projects-013 | change-notification | Subscribe to `UserSettings.highlightActivePane.$currentValue`, then set `.value = false` | the subscriber observes `false` synchronously, before the statement that performed the write returns |
| git-client-projects-user-settings-projects-014 | no-pattern-validation | Set `UserSettings.projectScanSkipPatterns.value = ["", "not [a valid glob", "dup", "dup"]` | all four entries are accepted and persisted verbatim, in order, with no filtering or deduplication |
| git-client-projects-user-settings-projects-015 | main-actor-isolation | From Swift code compiled with strict concurrency checking, attempt to read `UserSettings.highlightActivePane.value` from a `nonisolated` context with no `await` | fails to compile, because a `@MainActor`-isolated member cannot be accessed synchronously off the main actor — traced to `UserSettings.swift` and `UserSetting.swift` |
