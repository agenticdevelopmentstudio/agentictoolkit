<!-- leaf: implement-settings/storage--part-2 · source: settings-storage.md -->

# Settings Storage — continued (part 2)

**Rules** (cite as `implement-settings/storage--part-2#<slug>`):

- `key-name` MUST
- `key-default-value` MUST
- `key-secure-routing` MUST
- `provider-get-fallback` MUST
- `provider-set-persists` MUST
- `provider-remove-restores-default` MUST
- `provider-contains` MUST
- `provider-change-notification-on-set` MUST
- `provider-change-notification-on-remove` MUST
- `provider-publisher-replay` MUST
- `provider-publisher-ignores-other-keys` MUST
- `provider-values-stream` MUST
- `provider-plain-not-secure` MUST
- `secure-provider-is-secure` MUST
- `inmemory-concurrent-access` MUST
- `inmemory-seeded-initial-values` MUST
- `inmemory-secure-delegates` MUST
- `userdefaults-native-fast-path` MUST
- `userdefaults-json-fallback` MUST
- `userdefaults-corrupted-decode-fallback` MUST
- `keychain-string-fast-path` MUST
- `keychain-codable-path` MUST
- `keychain-encode-failure-logged` MUST
- `keychain-write-failure-invalidates-memo` MUST
- `keychain-remove-failure-invalidates-memo` MUST
- `keychain-read-memoization` MUST
- `keychain-memo-per-instance` MUST
- `keychain-contains-bypasses-memo` MUST
- `keychain-global-service-override` MUST
- `sqlite-schema-creation` MUST
- `sqlite-json-storage` MUST
- `sqlite-serialized-access` MUST
- `sqlite-transient-binding` MUST
- `sqlite-close-on-deinit` MUST
- `sqlite-encode-failure-logged` MUST
- `sqlite-write-failure-no-notification` MUST
- `icloud-native-fast-path` MUST
- `icloud-int-promotion` MUST
- `icloud-explicit-synchronize` MUST
- `icloud-external-change-forwarding` MUST
- `store-routing` MUST
- `store-merged-changes` MUST
- `store-default-providers` MUST
- `usersettings-shared-singleton` MUST
- `usersettings-shared-replacement-timing` SHOULD

## Behavioral Requirements

### StorableSetting

- **key-name**: Each `StorableSetting` MUST supply a stable `name` (a `String`) that every backend uses as its storage key.
- **key-default-value**: Each `StorableSetting` MUST supply a `defaultValue` of its own `Value` type, returned whenever no value has been stored, or a stored value cannot be decoded, for its `name`.
- **key-secure-routing**: Each `StorableSetting` MUST supply `isSecure: Bool`, and a `SettingsStore` MUST route a key with `isSecure == true` to its secure backing provider and every other key to its plain provider.

### SettingsStorageProvider contract

- **provider-get-fallback**: `get` MUST return the key's `defaultValue` when the backend holds no value, or holds a value that cannot be decoded as `Value`, for that key's `name`.
- **provider-set-persists**: `set` MUST make the new value readable by a subsequent `get` for the same key on the same provider instance once `set` returns.
- **provider-remove-restores-default**: `remove` MUST cause a subsequent `get` for that key to return `defaultValue` and `contains` to return `false`.
- **provider-contains**: `contains` MUST return `true` only when a value has been explicitly stored for that key's name and has not since been removed.
- **provider-change-notification-on-set**: `set` MUST publish the key's `name` on `changes` after the new value becomes readable through `get`.
- **provider-change-notification-on-remove**: `remove` MUST publish the key's `name` on `changes`.
- **provider-publisher-replay**: The default `publisher(for:)` MUST emit the provider's current value for that key immediately upon subscription, then emit an updated value each time `changes` publishes that key's name.
- **provider-publisher-ignores-other-keys**: `publisher(for:)` MUST NOT emit when `changes` publishes a different key's name.
- **provider-values-stream**: `values(for:)` MUST expose the same replay-then-live sequence as `publisher(for:)` through an `AsyncStream`, cancelling its underlying subscription when the stream terminates.
- **provider-plain-not-secure**: A `SettingsStorageProvider` MUST report `isSecure == false` unless it also conforms to `SecureSettingsStorageProvider`.
- **secure-provider-is-secure**: A `SecureSettingsStorageProvider` MUST report `isSecure == true`.

### InMemorySettingsStorageProvider / InMemorySecureSettingsStorageProvider

- **inmemory-concurrent-access**: `InMemorySettingsStorageProvider` MUST serialize `set`/`remove` against every `get`/`contains` through a concurrent `DispatchQueue`, using the barrier flag on writes, so a concurrent read never observes a partially-written value.
- **inmemory-seeded-initial-values**: `InMemorySettingsStorageProvider.init(initial:)` MUST seed its backing dictionary directly from the untyped `[String: Any]` argument, without validating that a seeded value matches the `Value` type of any key that will later read it.
- **inmemory-secure-delegates**: `InMemorySecureSettingsStorageProvider` MUST delegate every operation and its `changes` publisher to an internally-held, private `InMemorySettingsStorageProvider`, differing from it only in also conforming to `SecureSettingsStorageProvider`.

### UserDefaultsSettingsStorageProvider

- **userdefaults-native-fast-path**: `UserDefaultsSettingsStorageProvider` MUST store and read `Int`, `Double`, `Float`, `Bool`, `String`, `Data`, `URL`, and `Date` values through `UserDefaults`'s native object storage rather than JSON encoding.
- **userdefaults-json-fallback**: For any `Value` type outside that native set — arrays, dictionaries, and other `Codable` structs — `UserDefaultsSettingsStorageProvider` MUST JSON-encode the value and store it as `Data`.
- **userdefaults-corrupted-decode-fallback**: When previously-stored `Data` for a key fails to decode as `Value`, `get` MUST return `defaultValue` rather than throwing or crashing.
- **userdefaults-encode-failure**: NEEDS REVIEW: Not implemented in source. When `JSONEncoder.encode` fails for a non-natively-supported `Value`, `set` returns without writing, without logging, and without publishing on `changes`, so the caller has no way to learn the write did not happen.

### KeychainSecureSettingsStorageProvider

- **keychain-string-fast-path**: For `Value == String`, `get` and `set` MUST read and write the raw string directly, without JSON quoting, so the keychain entry holds the literal secret rather than a JSON string literal.
- **keychain-codable-path**: For any other `Codable & Sendable` `Value`, `set` MUST JSON-encode the value to a UTF-8 string before writing, and `get` MUST JSON-decode the stored string back to `Value`, returning `defaultValue` if decoding fails.
- **keychain-encode-failure-logged**: When encoding a non-`String` value fails, `set` MUST log an error and return without writing to the keychain or publishing on `changes`.
- **keychain-write-failure-invalidates-memo**: When the underlying keychain write fails, `set` MUST remove any cached memo entry for that key and MUST NOT publish on `changes`.
- **keychain-remove-failure-invalidates-memo**: When the underlying keychain delete fails, `remove` MUST remove any cached memo entry for that key and MUST NOT publish on `changes`.
- **keychain-read-memoization**: `get` MUST memoize the raw keychain string for a key — including a confirmed absence — the first time it is read, and MUST answer every subsequent `get` for that key from the memo rather than re-querying the keychain, until `set` or `remove` updates the memo.
- **keychain-memo-per-instance**: The read memo MUST be private, per-instance state; a second `KeychainSecureSettingsStorageProvider` constructed for the same service MUST start with an empty memo.
- **keychain-contains-bypasses-memo**: `contains` MUST query the keychain directly through `KeychainHelper.exists`, never through the read memo.
- **keychain-global-service-override**: `init(service:accessGroup:)` MUST assign a non-nil `service` argument to the process-wide `KeychainHelper.service`, and MUST unconditionally assign its `accessGroup` argument — including `nil` — to the process-wide `KeychainHelper.accessGroup`, so constructing an instance changes keychain routing for every `KeychainHelper`-backed caller in the process, not only for the new instance.

### SqliteStorageProvider

- **sqlite-schema-creation**: `init(path:)` MUST open, creating if absent, a SQLite database at `path`, and MUST create a `settings_kv` table (`key TEXT PRIMARY KEY, value BLOB NOT NULL`) if it does not already exist, throwing `SqliteSettingsError.cannotOpen` or `.schemaFailed` if either step fails.
- **sqlite-json-storage**: `set` MUST JSON-encode every value and store it as the row's `value` blob via an upsert statement, so a key never occupies more than one row.
- **sqlite-serialized-access**: Every `get`, `set`, `remove`, and `contains` MUST run inside a private serial `DispatchQueue`, so concurrent calls on one instance are serialized against the same `sqlite3` handle.
- **sqlite-transient-binding**: Bound text and blob parameters MUST use SQLite's transient destructor, so SQLite copies the bytes rather than referencing Swift-owned memory that may be freed before the statement executes.
- **sqlite-close-on-deinit**: The instance MUST close its `sqlite3` handle in `deinit`.
- **sqlite-encode-failure-logged**: When `JSONEncoder.encode` fails, `set` MUST log an error and return without writing a row or publishing on `changes`.
- **sqlite-write-failure-no-notification**: When the prepare, bind, or step of the upsert statement fails, `set` MUST NOT publish on `changes`; the failure is logged by the SQL helper that detected it.

### iCloudSettingsStorageProvider

- **icloud-native-fast-path**: `iCloudSettingsStorageProvider` MUST store and read `Int`, `Int64`, `Double`, `Bool`, and `String`/`Data` through `NSUbiquitousKeyValueStore`'s native storage; `URL` and `Date` are not natively supported and MUST go through the JSON-encoded `Data` path.
- **icloud-int-promotion**: For `Value == Int`, `set` MUST store the value as `Int64` (`NSUbiquitousKeyValueStore` has no native `Int` accessor), and `get` MUST bridge a stored `Int64` back to `Int`.
- **icloud-explicit-synchronize**: `set` and `remove` MUST call the store's synchronize operation after mutating it, in addition to publishing on `changes`.
- **icloud-external-change-forwarding**: The provider MUST forward every key named in the store's external-change notification payload onto its own `changes` publisher, so a change made on another device is observable through the same publisher as a local `set`.
- **icloud-encode-failure**: NEEDS REVIEW: Not implemented in source. When `JSONEncoder.encode` fails for a non-natively-supported `Value`, `set` returns without writing, without logging, and without publishing on `changes`, identically to `UserDefaultsSettingsStorageProvider`.

### SettingsStore / UserSettings

- **store-routing**: `SettingsStore`'s `get`/`set`/`remove`/`contains` MUST dispatch to its secure provider when `key.isSecure` is `true` and to its plain provider otherwise.
- **store-merged-changes**: `SettingsStore.changes` MUST be the merge of both backing providers' `changes` publishers, so a single subscription observes changes from either provider.
- **store-default-providers**: `SettingsStore.init` MUST default to `UserDefaultsSettingsStorageProvider` for the plain provider and `KeychainSecureSettingsStorageProvider` for the secure provider when no providers are supplied.
- **usersettings-shared-singleton**: `UserSettings.shared` MUST be a single, mutable, process-wide instance that every `StorableSetting.value`/`.remove()`/`.existsInStore()` accessor and every `UserSetting` reads and writes through by default.
- **usersettings-shared-replacement-timing**: A host app SHOULD replace `UserSettings.shared` only before constructing any `UserSetting`; see Design Decisions for the rationale and `usersettings-shared-reassignment` in Edge Cases for what happens otherwise.

