<!-- leaf: implement-settings/storage--edge-cases · source: settings-storage.md -->

# Settings Storage

**Rules** (cite as `implement-settings/storage--edge-cases#<slug>`):

- `empty-collection-vs-absent` MUST
- `key-name-collision-across-types` SHOULD
- `inmemory-untyped-seed` MUST
- `boundary-int64-on-64-bit` MUST
- `concurrent-inmemory-access` MUST
- `concurrent-sqlite-access` MUST
- `sqlite-open-failure` MUST
- `keychain-write-or-delete-failure` MUST

## Edge Cases

- **empty-collection-vs-absent**: Setting an empty array for a key MUST be distinguishable from never having set it: `contains` MUST return `true` after storing an empty array even though `get` also returns an empty array for an absent key whose `defaultValue` happens to be empty — traced to `testEmptyArrayRoundTrip`.
- **key-name-collision-across-types**: No provider detects or rejects two `StorableSetting`s that share the same `name` but declare different `Value` types; each key's `get` still returns that key's own `defaultValue` when the stored representation cannot be cast or decoded as its `Value`, so a collision surfaces as "always reads as freshly defaulted" rather than as a crash or a visible error. SHOULD — callers are responsible for giving every key a process-unique `name`; traced to `SettingsKeyTests.testKeysWithDifferentValueTypesAreDistinctTypes` and every provider's cast-or-decode-else-default `get` path.
- **inmemory-untyped-seed**: `InMemorySettingsStorageProvider.init(initial:)` accepts an untyped dictionary; seeding a key with a value of the wrong runtime type for that key MUST behave exactly like an absent key on the next typed `get` — the cast fails and `defaultValue` is returned — never a crash.
- **boundary-int64-on-64-bit**: `Int` and `Int64` are the same width on macOS, so `iCloudSettingsStorageProvider`'s bridge from a stored `Int64` back to `Int` MUST always succeed for a value this component itself ever wrote; the source defines no behavior for a stored `Int64` outside `Int`'s range, because nothing here can produce one.
- **concurrent-inmemory-access**: Concurrent `get`/`set`/`remove`/`contains` calls on one `InMemorySettingsStorageProvider` instance MUST NOT corrupt or lose a write: reads run on the provider's concurrent queue without the barrier flag and writes run with it, so readers see a consistent snapshot against any single writer.
- **concurrent-sqlite-access**: Concurrent calls on one `SqliteStorageProvider` instance MUST be serialized through its private serial queue, so two `set` calls for different keys never interleave their SQL statements on the same handle.
- **concurrent-userdefaults-keychain-icloud**: `UserDefaultsSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, and `iCloudSettingsStorageProvider` add no locking of their own around the system store each wraps; concurrent access is left to whatever thread-safety `UserDefaults`, the Keychain, and `NSUbiquitousKeyValueStore` provide, and to these types' isolation to the main actor (see Behavioral Requirements, Swift concurrency).
- **sqlite-open-failure**: If opening the database or creating the schema fails, `SqliteStorageProvider.init` MUST throw `SqliteSettingsError.cannotOpen` or `.schemaFailed` respectively, leaving no provider instance constructed.
- **keychain-write-or-delete-failure**: If the underlying keychain write or delete fails, `set`/`remove` MUST leave the previously-stored value observably unchanged from the caller's perspective on the next `get`/`contains` — the memo is invalidated, forcing a fresh read-through — and MUST NOT publish on `changes`.
- **usersettings-shared-reassignment**: `UserSettings.shared`'s doc comment ("Client apps should create and set this") makes setting it at startup the caller's job. Replacing it after a `UserSetting` exists leaves that `UserSetting` subscribed to the old instance's `changes` publisher, captured once in `init`, while its `value` accessor and the subscription's re-read target the current `shared`; there is no way to re-subscribe an existing `UserSetting`.
- **offline-icloud-sync**: `iCloudSettingsStorageProvider` does not itself detect or report connectivity loss; `NSUbiquitousKeyValueStore` is responsible for queuing local writes and syncing them once connectivity returns, and this component's `changes` publisher fires only for a local `set`/`remove` or an externally-delivered change notification — never to report a sync attempt, a sync failure, or a reconnection.
