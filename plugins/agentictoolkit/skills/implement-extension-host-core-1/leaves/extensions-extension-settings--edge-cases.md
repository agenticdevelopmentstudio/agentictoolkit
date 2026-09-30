<!-- leaf: implement-extension-host-core-1/extensions-extension-settings--edge-cases · source: extension-host-core-extensions-extension-settings.md -->

# ExtensionSettings

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-settings--edge-cases#<slug>`):

- `null-and-empty-input` MUST — writing .value = [] (an explicit empty set) and calling .remove() both leave a later read of .value returning the empty …
- `null-and-empty-input-the-empty-string-as-a-member` MUST — .value = [""] is accepted; the empty string is a member like any other, with no special-case rejection …
- `boundary-values` MUST — the source imposes no maximum on the number of identifiers the set may hold; a set with hundreds of entries is …
- `concurrent-access` MUST — every read, write, and remove is confined to the main actor (main-actor-isolation), so two calls issued from different …
- `error-states` SHOULD — a JSONEncoder.encode failure during a write is swallowed — UserDefaultsSettingsStorageProvider.set uses try? …

## Edge Cases

- **Null and empty input**: writing `.value = []` (an explicit empty set) and calling `.remove()` both leave a later read of `.value` returning the empty set; only `.existsInStore()` distinguishes "explicitly emptied" from "never written," because `get` cannot tell the two apart (`no-identifier-validation`'s `get` path, `UserDefaultsSettingsStorageProvider.swift`). MUST behave this way.
- **Null and empty input — the empty string as a member**: `.value = [""]` is accepted; the empty string is a member like any other, with no special-case rejection (`no-identifier-validation`). MUST behave this way.
- **Boundary values**: the source imposes no maximum on the number of identifiers the set may hold; a set with hundreds of entries is JSON-encoded and stored as one `Data` blob the same way a set with one entry is, because `UserDefaultsSettingsStorageProvider` performs no size check on this path (`UserDefaultsSettingsStorageProvider.swift`). MUST behave this way.
- **Concurrent access**: every read, write, and remove is confined to the main actor (`main-actor-isolation`), so two calls issued from different `Task`s MUST execute in some serialized order with no interleaving of the underlying `UserDefaults` write — the actor, not this file, is what rules out a data race. MUST behave this way.
- **Error states**: a `JSONEncoder.encode` failure during a write is swallowed — `UserDefaultsSettingsStorageProvider.set` uses `try? encoder.encode(value)` and simply returns, sending no change notification, if encoding fails (`UserDefaultsSettingsStorageProvider.swift`). For `Set<String>`, encoding a collection of Swift strings does not fail in practice, so this path is unreachable for this specific setting; it is documented here because it is a real behavior of the storage layer this property depends on, not because it is expected to occur. SHOULD be understood as inherited, unreachable-for-this-type behavior, not a gap in `ExtensionSettings.swift`.
- **Offline or disconnected state**: not applicable — `ExtensionSettings.swift` performs no network call of any kind; `UserDefaults` is local, on-device storage with no connectivity dependency.
