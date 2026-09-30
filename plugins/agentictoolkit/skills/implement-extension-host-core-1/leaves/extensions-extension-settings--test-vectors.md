<!-- leaf: implement-extension-host-core-1/extensions-extension-settings--test-vectors · source: extension-host-core-extensions-extension-settings.md -->

# ExtensionSettings

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| extension-settings-001 | disabled-identifiers-key | Read `UserSettings.disabledExtensionIdentifiers.name` | equals the string `"extensions.disabledIdentifiers"` — mirrors `ExtensionSettingsTests.theStorageKeyIsPinned`, `ExtensionSettingsTests.swift` |
| extension-settings-002 | disabled-identifiers-default | Read `UserSettings.disabledExtensionIdentifiers.defaultValue` | `.isEmpty == true` — mirrors `ExtensionSettingsTests.nothingIsDisabledByDefault`, `ExtensionSettingsTests.swift` |
| extension-settings-003 | enabled-by-default, value-round-trip | With no prior write in this run, read `UserSettings.disabledExtensionIdentifiers.value` | equals the empty set, since nothing has been stored yet and `get` falls back to `defaultValue` |
| extension-settings-004 | value-round-trip | Set `.value = ["acme.foo"]`, then read `.value` | equals `{"acme.foo"}` |
| extension-settings-005 | value-round-trip | Set `.value = ["acme.foo", "acme.bar"]`, then set `.value = ["acme.bar"]`, then read `.value` | equals `{"acme.bar"}` — the second write replaces the stored set rather than merging into it |
| extension-settings-006 | removal-reverts-to-default | Set `.value = ["acme.foo"]`, call `.remove()`, then read `.value` | equals the empty set (`defaultValue`) |
| extension-settings-007 | existence-check | Before any write, call `.existsInStore()`; then set `.value = ["acme.foo"]` and call `.existsInStore()` again | first call returns `false`; second call returns `true` |
| extension-settings-008 | existence-check, removal-reverts-to-default | Set `.value = ["acme.foo"]`, call `.remove()`, then call `.existsInStore()` | returns `false` |
| extension-settings-009 | json-encoded-persistence | Set `.value = ["acme.foo", "acme.bar"]`, then inspect the raw object `UserDefaults.standard` holds under the key `"extensions.disabledIdentifiers"` | the stored object is `Data`, not a native array or string; JSON-decoding that `Data` as `Set<String>` yields `{"acme.foo", "acme.bar"}` |
| extension-settings-010 | not-secure | Read `UserSettings.disabledExtensionIdentifiers.isSecure` | equals `false`, confirming writes route through `UserDefaultsSettingsStorageProvider` and never the Keychain-backed provider |
| extension-settings-011 | corrupt-data-falls-back-to-default | Store a JSON payload that does not decode as `Set<String>` (for example the object `{"not":"a set"}`, encoded to `Data`) directly under `"extensions.disabledIdentifiers"` in the backing `UserDefaults`, then read `.value` | returns the empty set (`defaultValue`), with no thrown error — mirrors the storage layer's own `testCodableStructFallsBackToDefaultOnCorruptedData` |
| extension-settings-012 | change-notification | Subscribe to `UserSettings.disabledExtensionIdentifiers.$currentValue`, then set `.value = ["acme.foo"]` | the subscriber observes `{"acme.foo"}` synchronously, before the statement that performed the write returns |
| extension-settings-013 | no-identifier-validation | Set `.value = ["not-a-real-extension-id", ""]` (an unregistered identifier and an empty string) | both are accepted and persisted verbatim; a subsequent read returns exactly `{"not-a-real-extension-id", ""}`, with no error and no filtering |
| extension-settings-014 | case-sensitive-storage | Set `.value = ["Acme.Foo"]`, then evaluate `.value.contains("acme.foo")` | returns `false` — the differently-cased spelling is not treated as the same member |
| extension-settings-015 | main-actor-isolation | From Swift code compiled with strict concurrency checking, attempt to read `.value` from a `nonisolated` context with no `await` | fails to compile, because a `@MainActor`-isolated member cannot be accessed synchronously off the main actor — traced to `ExtensionSettings.swift` and `UserSetting.swift` |
