<!-- leaf: implement-git-client/projects-user-settings-projects--edge-cases · source: git-client-projects-user-settings-projects.md -->

# UserSettings+Projects

**Rules** (cite as `implement-git-client/projects-user-settings-projects--edge-cases#<slug>`):

- `null-and-empty-input` MUST — setting projectScanSkipPatterns.value = [] (an explicit empty array) leaves a later read of .value returning []; …
- `boundary-values` MUST — the source imposes no maximum on the number of entries in projectScanSkipPatterns or on the length of any one entry; a …
- `concurrent-access` MUST — every read, write, and remove on all three settings is confined to the main actor (main-actor-isolation), so two calls …
- `error-states` SHOULD — a JSONEncoder.encode failure during a write to projectScanSkipPatterns is swallowed — …

## Edge Cases

- **Null and empty input**: setting `projectScanSkipPatterns.value = []` (an explicit empty array) leaves a later read of `.value` returning `[]`; calling `.remove()` instead leaves a later read returning the non-empty `GitRepoScanner.defaultRootSkipPatterns` list, because `removal-reverts-to-default` reverts to whatever `defaultValue` is, not to an empty array (`UserSettings+Projects.swift`). The empty string is also accepted as an ordinary member of the list, with no special-case rejection (`no-pattern-validation`). MUST behave this way.
- **Boundary values**: the source imposes no maximum on the number of entries in `projectScanSkipPatterns` or on the length of any one entry; a list with hundreds of patterns is JSON-encoded and stored as one `Data` blob the same way a single-entry list is (`array-setting-json-encoded`). MUST behave this way.
- **Concurrent access**: every read, write, and remove on all three settings is confined to the main actor (`main-actor-isolation`), so two calls issued from different `Task`s MUST execute in some serialized order with no interleaving of the underlying `UserDefaults` access — the actor, not this file, is what rules out a data race. MUST behave this way.
- **Error states**: a `JSONEncoder.encode` failure during a write to `projectScanSkipPatterns` is swallowed — `UserDefaultsSettingsStorageProvider.set` uses `try? encoder.encode(value)` and simply returns, sending no change notification, if encoding fails (`UserDefaultsSettingsStorageProvider.swift`). Encoding a `[String]` of ordinary Swift strings does not fail in practice, so this path is unreachable for this specific setting; it is documented here because it is a real, inherited behavior of the storage layer this property depends on, not because it is expected to occur. SHOULD be understood as inherited, unreachable-for-this-type behavior, not a gap in `UserSettings+Projects.swift`.
- **Offline or disconnected state**: not applicable — `UserSettings+Projects.swift` performs no network call of any kind; `UserDefaults` is local, on-device storage with no connectivity dependency.
