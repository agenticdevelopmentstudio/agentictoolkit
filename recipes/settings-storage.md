---
id: 6363b5ff-f511-4e21-9ba7-6850787dba62
title: Settings Storage
domain: agentictoolkit://recipes/settings-storage
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Typed key/value settings contract (StorableSetting, SettingsStorageProvider)
  with in-memory, UserDefaults, Keychain, SQLite, and iCloud backends.
platforms:
- swift
- macos
tags:
- settings
- persistence
- storage
- logic
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Settings Storage

## Overview

`settings-storage` is the toolkit's typed key/value persistence layer for user preferences and secrets. A `StorableSetting<Value>` is a typed key: a stable `name`, a `defaultValue`, and an `isSecure` flag. A `SettingsStorageProvider` is the pluggable backend contract — `get`/`set`/`remove`/`contains` plus a `changes: AnyPublisher<String, Never>` that names which key changed, with `publisher(for:)` and `values(for:)` derived from it in a protocol extension. Six concrete backends implement the contract: `InMemorySettingsStorageProvider` and `InMemorySecureSettingsStorageProvider` (tests and previews), `UserDefaultsSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`, and `iCloudSettingsStorageProvider`. `SettingsStore` — and its process-wide subclass singleton `UserSettings` — routes each key to a secure or plain backend by `key.isSecure` and merges both backends' `changes` into one publisher. Call sites almost never touch a provider directly: they declare a `static var` `UserSetting<Value>` (an `ObservableObject` that mirrors the store's live value for that key, as `UserSettings+Editor.swift`, `+Git.swift`, and `+Theme.swift` do) and read/write it through the `StorableSetting.value` accessor, or wrap it in a `UserSettingObserver`/`ObservedSetting` for a plain callback outside SwiftUI. `ColorSetting` is a `UserSetting<RGBAColor>` type alias for stored color settings, reaching `RGBAColor` through `Core/Theme/ThemeReExports.swift`.

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

### UserSetting / UserSettingObserver / ObservedSetting / ColorSetting

- **usersetting-construction-reads-through**: Constructing a `UserSetting` MUST synchronously read the current value for its key from `UserSettings.shared` before returning, so `currentValue` reflects any already-stored value rather than always starting at `defaultValue`.
- **usersetting-published-mirror**: `UserSetting.currentValue` MUST update, through its `@Published` storage, whenever `UserSettings.shared.changes` publishes this instance's `name`, re-reading the value from `UserSettings.shared` at that point.
- **usersetting-write-through**: Writing `storableSetting.value = newValue` MUST write through `UserSettings.shared.set`, so a subsequent read from any caller observes the new value.
- **observer-deferred-callback**: `UserSettingObserver.onChange` MUST fire on the main dispatch queue on the turn after `currentValue` changes, not synchronously inside the write that caused the change, and MUST NOT fire for the value a `UserSettingObserver` was constructed with.
- **observedsetting-wraps-observer**: `ObservedSetting` MUST forward its `wrappedValue` get/set to an internally-held `UserSettingObserver` and expose the underlying `UserSetting` as `projectedValue`.
- **colorsetting-alias**: `ColorSetting` MUST be a type alias for `UserSetting<RGBAColor>`.
- **keychain-service-override-timing**: A caller SHOULD construct at most one `KeychainSecureSettingsStorageProvider` per process with a non-default `service`/`accessGroup`, or construct every instance with the same override; see Design Decisions.

### Swift concurrency

- **isolation-by-declaration**: `StorableSetting`, `SettingsStorageProvider`, `UserSetting`, `UserSettingObserver`, `ObservedSetting`, `SettingsStore`/`UserSettings`, `InMemorySecureSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`, and `iCloudSettingsStorageProvider` are all `@MainActor`-isolated by declaration or by conforming to the `@MainActor` `SettingsStorageProvider`/`StorableSetting` protocols; `InMemorySettingsStorageProvider` and `UserDefaultsSettingsStorageProvider` carry no `@MainActor` annotation of their own and instead serialize their own internal state (a concurrent queue with a barrier, and thread-safe `UserDefaults`, respectively) so they remain safe to call from contexts that are not already on the main actor.
- **sqlite-nonisolated-handle**: `SqliteStorageProvider`'s `database` pointer MUST be declared `nonisolated(unsafe)` so `deinit` — which runs outside actor isolation — can close it synchronously without an `await`.

## Appearance

Not applicable — this is a settings persistence layer (typed keys and pluggable key/value backends), not a visual component.

## States

Not applicable — this is a settings persistence layer, not a visual component; its runtime states (constructed, subscribed, memoized, read-through) are covered under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a settings persistence layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-storage-001 | key-name, key-default-value | `UserSetting<Int>("launchCount", default: 0)` | `.name == "launchCount"`, `.defaultValue == 0` — `SettingsKeyTests.testKeyStoresNameAndDefault` |
| settings-storage-002 | key-secure-routing, store-routing | Set a plain key and a secure key through `UserSettings.shared` | Plain key's value is only readable from the `UserDefaults`-backed provider; secure key's only from the Keychain-backed provider — traced to `storageProvider(for:)` |
| settings-storage-003 | provider-get-fallback | Fresh `InMemorySettingsStorageProvider`, `get(UserSettings.launchCount)` | `0` — `testReturnsDefaultValueWhenEmpty` |
| settings-storage-004 | provider-set-persists, provider-change-notification-on-set | `store.set(1, for: launchCount)`, then `store.set("hi", for: displayName)` while subscribed to `changes` | `get` returns `1`/`"hi"`; `changes` emits `["test.launchCount", "test.displayName"]` in order — `testSetEmitsChange` |
| settings-storage-005 | provider-remove-restores-default, provider-change-notification-on-remove, provider-contains | `store.set(99, for: launchCount)`, then `store.remove(launchCount)` | `contains == false`, `get == 0`, one `changes` emission of `"test.launchCount"` — `testRemoveClearsValueAndReturnsDefault` |
| settings-storage-006 | provider-publisher-replay, provider-publisher-ignores-other-keys | `store.set(5, for: launchCount)`; subscribe `publisher(for: launchCount)`; `set("ignored", for: displayName)`; `set(99, for: launchCount)` | Received `[5, 99]`; no emission for the `displayName` write — `testPublisherIgnoresOtherKeys` |
| settings-storage-007 | provider-values-stream | `store.set(10, for: launchCount)`; iterate `values(for: launchCount)`; concurrently `set(11, ...)` | Yields `10` then `11` — `testAsyncStreamYieldsValues` |
| settings-storage-008 | provider-plain-not-secure, secure-provider-is-secure | `InMemorySettingsStorageProvider().isSecure`; `KeychainSecureSettingsStorageProvider(...).isSecure` | `false`; `true` — `testProviderReportsSecure` |
| settings-storage-009 | inmemory-concurrent-access | Many concurrent `set` calls for distinct keys against one `InMemorySettingsStorageProvider` | Every key reads back its own written value afterward, none dropped or corrupted — traced to the concurrent-queue-with-barrier implementation; not exercised by a test in the given suite |
| settings-storage-010 | inmemory-seeded-initial-values | `InMemorySettingsStorageProvider(initial: ["test.launchCount": 7])`, then `.get(launchCount)` | `7` — `testInitialValuesArePreserved` |
| settings-storage-011 | inmemory-secure-delegates | `InMemorySecureSettingsStorageProvider().isSecure`, delegating storage to its private `InMemorySettingsStorageProvider` | `isSecure == true`; get/set/remove/contains behave exactly like the wrapped `InMemorySettingsStorageProvider` — traced to the `inner` property; not exercised by a test in the given suite |
| settings-storage-012 | userdefaults-native-fast-path | `UserDefaultsSettingsStorageProvider.set(true, for: hasCompletedOnboarding)` | `defaults.object(forKey: "test.hasCompletedOnboarding") as? Bool` is non-nil — `testBoolRoundTrip` |
| settings-storage-013 | userdefaults-json-fallback | `set(["alpha", "beta", "gamma"], for: recentSearches)` | `defaults.data(forKey: "test.recentSearches")` is non-nil and `get` round-trips the array — `testStringArrayRoundTrip` |
| settings-storage-014 | userdefaults-corrupted-decode-fallback | Inject garbage `Data` under `"test.userPreferences"`, then `get(userPreferences)` | Returns `UserSettings.userPreferences.defaultValue` — `testCodableStructFallsBackToDefaultOnCorruptedData` |
| settings-storage-015 | keychain-string-fast-path | `store.set("hello", for: displayName)`; read raw via `KeychainHelper.get(forKey: "test.displayName")` | Raw string is `hello`, not a JSON-quoted string — `testStringValueIsStoredRawNotJSONQuoted` |
| settings-storage-016 | keychain-codable-path | `store.set(UserPreferences(...), for: userPreferences)` | `get` round-trips an equal struct — `testCodableStructRoundTrip` |
| settings-storage-017 | keychain-encode-failure-logged, keychain-write-failure-invalidates-memo | A value whose encoding fails during `set` | An error is logged; `set` returns without writing or notifying `changes` — traced to the encode-failure branch; not exercised by a test in the given suite |
| settings-storage-018 | keychain-remove-failure-invalidates-memo | A forced keychain delete failure inside `remove` | Memo entry is dropped; no `changes` emission — traced to `remove`'s failure branch; not exercised by a test in the given suite |
| settings-storage-019 | keychain-read-memoization | `store.set("first", for: displayName)`; delete the item behind the provider via `KeychainHelper.delete`; `store.get(displayName)` | `"first"` — `testRepeatReadsAreServedFromTheMemoNotTheKeychain` |
| settings-storage-020 | keychain-memo-per-instance | Provider A sets `"owned"` for `displayName`; construct provider B on the same service; `B.get(displayName)` | `"owned"`, read through B's own empty memo — `testMemoizedValuesAreScopedToTheProviderInstance` |
| settings-storage-021 | keychain-contains-bypasses-memo | `store.get(displayName)` memoizes absence; `KeychainHelper.set("written-behind-the-provider", forKey: "test.displayName")`; `store.contains(displayName)` | `true` — reflects live keychain state, not the memo — traced to `contains` and `testAnAbsentKeyIsMemoizedToo` |
| settings-storage-022 | keychain-global-service-override, keychain-service-override-timing | Construct a provider with `service: "A"`, then a second with `service: "B"` | `KeychainHelper.service` becomes `"B"` for both instances' subsequent keychain calls — traced to `init`'s unconditional assignment |
| settings-storage-023 | sqlite-schema-creation, sqlite-json-storage, sqlite-close-on-deinit | `SqliteStorageProvider(path: tmpFile).set(42, for: launchCount)`; drop the instance; open a second provider on the same file; `.get(launchCount)` | `42` — `testValuesPersistAcrossInstances` |
| settings-storage-024 | sqlite-serialized-access | `set(true, ...)`, `set(42, ...)`, `set("Hello, world!", ...)` issued back-to-back on one instance | All three round-trip correctly with no cross-contamination — `testBoolRoundTrip`/`testIntRoundTrip`/`testStringRoundTrip` |
| settings-storage-025 | sqlite-transient-binding | `set("Hello, world!", for: displayName)` where the bound `String` is a temporary | The stored value survives after the temporary is deallocated, verified indirectly by every round-trip test succeeding |
| settings-storage-026 | sqlite-encode-failure-logged, sqlite-write-failure-no-notification | An encode-failing value, or a forced SQL prepare/step failure | An error is logged and `changes` does not fire — traced to `writeData`'s and `set`'s failure branches; not exercised by a test in the given suite |
| settings-storage-027 | icloud-native-fast-path, icloud-int-promotion | `iCloudSettingsStorageProvider.set(5, for: anIntKey)` | Stored as `Int64`, not a native `Int` — traced to the `Int64(intValue)` promotion; no test file exists for this provider (see Compliance) |
| settings-storage-028 | icloud-explicit-synchronize | `set("v", for: aKey)` | The store's synchronize operation is called before `changes` fires — traced to `set`'s body |
| settings-storage-029 | icloud-external-change-forwarding | Post the store's external-change notification with a changed-keys payload of `["someKey"]` | The provider's own `changes` publisher emits `"someKey"` — traced to the `NotificationCenter` observer in `init` |
| settings-storage-030 | store-merged-changes, usersettings-shared-singleton | Subscribe to `UserSettings.shared.changes`; set a plain key then a secure key | Both keys' names are observed on the one subscription — traced to the `Publishers.Merge` in `changes` |
| settings-storage-031 | store-default-providers | `SettingsStore()` constructed with no arguments | A plain key round-trips through `UserDefaults`; a secure key round-trips through the Keychain — traced to `init`'s default arguments |
| settings-storage-032 | usersetting-construction-reads-through, usersetting-published-mirror | `UserSettings.shared.set(7, ...)` via one `UserSetting`, then construct a second, independent `UserSetting` for the same name/default | The second instance's `currentValue` is `7` immediately on construction, not its own `defaultValue` — traced to `UserSetting.init` |
| settings-storage-033 | usersetting-write-through | `mySetting.value = newValue` | A subsequent `UserSettings.shared.get(mySetting)` from any reader returns `newValue` — traced to `StorableSetting.value`'s setter |
| settings-storage-034 | observer-deferred-callback | Construct `UserSettingObserver(setting) { onChangeCalled = true }`, then `setting.value = newValue` | `onChangeCalled` is still `false` synchronously after the assignment, and becomes `true` only after the next main-queue turn — traced to the `dropFirst`/`receive(on:)` chain |
| settings-storage-035 | observedsetting-wraps-observer, colorsetting-alias | `@ObservedSetting` wraps a setting; read the wrapped and projected values; `ColorSetting` used as a `UserSetting<RGBAColor>` | Wrapped value proxies the observer's value, projected value is the underlying `UserSetting`; `ColorSetting` type-checks as `UserSetting<RGBAColor>` — traced to `ObservedSetting` and the `ColorSetting` typealias |
| settings-storage-036 | usersettings-shared-replacement-timing | Replace `UserSettings.shared` before constructing any `UserSetting` | Every subsequently-constructed `UserSetting` reads and subscribes against the new instance consistently, contrasting with the open question in Edge Cases — traced to `UserSettings.shared`'s declaration as a mutable `static var` |

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

## Configuration

Constructor parameters (dependency injection) per backend:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `SettingsStore.settingsProvider` | `SettingsStorageProvider` | `UserDefaultsSettingsStorageProvider()` | Backend for keys with `isSecure == false` |
| `SettingsStore.secureSettingsProvider` | `SecureSettingsStorageProvider` | `KeychainSecureSettingsStorageProvider()` | Backend for keys with `isSecure == true` |
| `InMemorySettingsStorageProvider.initial` | `[String: Any]` | `[:]` | Seed values for tests/previews |
| `InMemorySecureSettingsStorageProvider.initial` | `[String: Any]` | `[:]` | Seed values, forwarded to its internal in-memory provider |
| `UserDefaultsSettingsStorageProvider.defaults` | `UserDefaults` | `.standard` | Backing defaults suite |
| `KeychainSecureSettingsStorageProvider.service` | `String?` | `nil` (keeps `KeychainHelper.service`, itself the bundle identifier) | Keychain service identifier override |
| `KeychainSecureSettingsStorageProvider.accessGroup` | `String?` | `nil` | Shared keychain access group |
| `SqliteStorageProvider.path` | `String` | none (required) | Filesystem path of the SQLite database |
| `iCloudSettingsStorageProvider.store` | `NSUbiquitousKeyValueStore` | `.default` | Backing key-value store |
| `UserDefaultsSettingsStorageProvider`/`KeychainSecureSettingsStorageProvider`/`SqliteStorageProvider`/`iCloudSettingsStorageProvider`.`encoder`/`decoder` | `JSONEncoder`/`JSONDecoder` | `JSONEncoder()`/`JSONDecoder()` | Injected for testability |

Setting keys declared on `UserSettings` in the given sources:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `editor.show_line_numbers` | `Bool` | `true` | `UserSettings.editorShowLineNumbers` |
| `editor.show_overview` | `Bool` | `true` | `UserSettings.editorShowOverview` |
| `editor.show_invisibles` | `Bool` | `false` | `UserSettings.editorShowInvisibles` |
| `git.executable_path` | `String` | `/usr/bin/git` | `UserSettings.gitExecutablePath` |
| `git.status_timeout_seconds` | `Int` | `5` | `UserSettings.gitStatusTimeoutSeconds` |
| `git.status_includes_submodules` | `Bool` | `false` | `UserSettings.gitStatusIncludesSubmodules` |
| `theme.active_theme_id` | `String` | `BuiltInThemes.defaultID` | `UserSettings.activeThemeID`; built-in themes are never stored under this key |
| `theme.custom_themes` | `[ColorTheme]` | `[]` | `UserSettings.customThemes` |
| `launchAtLogin` | `Bool` | `false` | `UserSettings.launchAtLogin` |
| `launchAtLoginPromptShown` | `Bool` | `false` | `UserSettings.launchAtLoginPromptShown` |
| `launchAtLoginHintDismissed` | `Bool` | `false` | `UserSettings.launchAtLoginHintDismissed` |

## Deep Linking

Not applicable: this component exposes no URL scheme or route; it is a storage layer with no navigable surface of its own.

## Localization

`SqliteSettingsError` conforms to `LocalizedError` and returns two hardcoded English strings from `errorDescription`: one describing the failed-open case with the path and the underlying SQLite message, and one describing the failed-schema case with the underlying SQLite message. Neither is looked up from a localization table, so every consumer sees the same English text regardless of locale. No other user-facing string originates from the given sources.

## Accessibility Options

Not applicable: no UI; nothing in the given sources reads Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: no flag lookup gates any behavior in the given sources — every provider and every `UserSetting` is unconditionally active once constructed.

## Analytics

Not applicable: the given sources call `Loggable`/`os.Logger` for diagnostics (see Logging) but never an analytics or event-tracking API.

## Privacy

- **Data collected**: None of the given sources collect data on their own; they persist values a caller supplies for its own keys — including, for a key with `isSecure == true`, secrets such as the API keys `KeychainSecureSettingsStorageProvider`'s own documentation cites as a target use case.
- **Storage**: A plain key (`isSecure == false`) is stored, by default, in `UserDefaults` (a property list on local disk) or, if the caller supplies `SqliteStorageProvider`, in a SQLite file at a caller-chosen path — neither encrypted by this component. A secure key is stored in the macOS Keychain via `KeychainHelper`, which the OS encrypts at rest and which `init` can scope to a shared access group for a co-signed daemon. `InMemorySettingsStorageProvider`/`InMemorySecureSettingsStorageProvider` never touch disk and are ephemeral for the life of the process. The given sources treat a failed keychain read/write as an ordinary error — logged, memo invalidated — rather than a detected security violation; there is no lockout, alert, or revocation behavior for repeated keychain failures.
- **Transmission**: Every backend except `iCloudSettingsStorageProvider` is local-device-only. `iCloudSettingsStorageProvider` syncs its values off-device through `NSUbiquitousKeyValueStore` to the user's iCloud account and back down to their other devices; it is used only for plain (non-secure) settings in the given sources — nothing routes a secure key through it.
- **Retention**: A value set through any backend persists until explicitly removed or the underlying store is cleared (app-data reset, keychain item deletion, or an uninstall — Keychain items can outlive an uninstall on macOS); the in-memory backends retain nothing past the process's lifetime. `iCloudSettingsStorageProvider` resolves a conflicting concurrent edit from two devices last-write-wins, per its own documentation, with iCloud performing the resolution.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (falls back to the literal string `nil` if absent) | Category: the conforming type's name (e.g. `KeychainSecureSettingsStorageProvider`, `SqliteStorageProvider`)

| Event | Level | Message |
|-------|-------|---------|
| Keychain non-`String` encode failure | error | Failed to encode value for secure key, naming the key |
| SQLite encode failure | error | Failed to encode value for key, naming the key |
| SQLite `SELECT` prepare failure | error | prepare SELECT failed, with the SQLite error message |
| SQLite `UPSERT` prepare failure | error | prepare UPSERT failed, with the SQLite error message |
| SQLite blob bind failure | error | bind blob failed, with the SQLite error message |
| SQLite `UPSERT` step failure | error | UPSERT step failed, with the SQLite error message |

`InMemorySettingsStorageProvider`, `InMemorySecureSettingsStorageProvider`, `UserDefaultsSettingsStorageProvider`, and `iCloudSettingsStorageProvider` conform to no `Loggable` and emit no log lines in the given sources.

## Platform Notes

- **SwiftUI**: `UserSetting` is already an `ObservableObject`, so a SwiftUI view binds directly to `currentValue` with `@ObservedObject`/`@StateObject` on an instance the view (or its model) holds. The retired `StoredSetting` property wrapper in `StoredSettingPropertyWrapper.swift` sketched a `@propertyWrapper`/`DynamicProperty` alternative, but the whole file is compiled out with `#if false` and is not the live surface.
- **Compose**: Translate `SettingsStorageProvider` to a small Kotlin interface backed by Jetpack `DataStore<Preferences>` for plain keys and `EncryptedSharedPreferences`/Android Keystore for secure keys; `changes: AnyPublisher<String, Never>` becomes a `SharedFlow<String>`; `UserSetting` becomes a `MutableStateFlow`-backed delegate collected with `collectAsState()`, mirroring the eager, read-on-construction behavior of `UserSetting.init`.
- **React/Web**: Translate `SettingsStorageProvider` to a small interface backed by `localStorage`/`IndexedDB` for plain keys and a platform credential store (or a server-side secret proxy) for secure keys; `changes` becomes an `EventTarget`, or an observable keyed by name; `UserSetting` becomes a hook built on `useSyncExternalStore` over the same store.
- **AppKit / UIKit**: This is the source's own consumer story. `AppearanceManager`, `LaunchAtLoginManager`, and the `ComposableSettingsWindow` view models (`ChoiceViewModel`, `ColorViewModel`, `FontViewModel`, `RangeViewModel`) all bind to `UserSetting`/`UserSettingObserver` rather than to any storage provider directly, and `UserSettingObserver` deliberately hops to `DispatchQueue.main` — not `RunLoop.main` — so it still fires while AppKit is running a mouse-tracking loop in `.eventTracking` mode.
- **WinUI 3**: `StorableSetting`/`SettingsStorageProvider` map to a small C# interface with `Get<T>`/`Set<T>`/`Remove<T>`/`Contains<T>` plus a `changes` event, backed by `Windows.Storage.ApplicationData.Current.LocalSettings` (an `ApplicationDataContainer`, natives stored directly and complex types JSON-encoded via `System.Text.Json`, mirroring the native/JSON split here) for plain keys and the Windows Credential Locker (`Windows.Security.Credentials.PasswordVault`) in place of the Keychain for secure keys. `SqliteStorageProvider`'s hand-rolled `sqlite3` calls map to `Microsoft.Data.Sqlite`. `changes` becomes a plain `event Action<string>` or `IObservable<string>`. `UserSetting<T>` becomes an `ObservableObject`/`INotifyPropertyChanged` wrapper exposing a `T Value` property, and `UserSettingObserver`'s main-queue hop becomes `DispatcherQueue.TryEnqueue` from the setting's change handler, so an update still lands on the UI thread while WinUI is inside a modal input loop — the same reason the source hops to a dispatch queue rather than a run loop.

## Design Decisions

**Decision**: Replace `UserSettings.shared` — if a host app needs a different provider configuration at all — only before constructing any `UserSetting`.
**Rationale**: `UserSetting.init` captures `UserSettings.shared` once, to read the initial value and subscribe to its `changes`; replacing `shared` afterward leaves that instance's subscription pinned to the old store while its `value` accessor and the subscription's own re-read both target whichever instance is current — an inconsistency the source leaves to the caller's setup order (see `usersettings-shared-reassignment` in Edge Cases).
**Approved**: pending

**Decision**: Construct at most one `KeychainSecureSettingsStorageProvider` per process with a non-default `service`/`accessGroup`, or construct every instance with the same override.
**Rationale**: `init` assigns its `service` and `accessGroup` arguments to the process-wide statics `KeychainHelper.service`/`KeychainHelper.accessGroup`, including assigning `nil` unconditionally, so a later default-argument instance silently clears an override an earlier instance made intentionally; this is documented inline in `init`'s own comment, and a second, differently-configured instance changes keychain routing for every existing instance too, not only the new one.
**Approved**: pending

**Decision**: `KeychainSecureSettingsStorageProvider` memoizes every read — a hit or a confirmed miss — for the life of the instance rather than reading through on every `get`.
**Rationale**: the type's own documentation traces this to a measured cost — a keychain miss walks the access-group query, the legacy no-group query, and every retired service before returning, and bulk-resolving many AI-provider settings on the main thread pinned the app above 100% CPU inside the keychain query call. The provider owns every write to the keys it serves, so the memo can be exact rather than time-based.
**Approved**: pending

**Decision**: `UserSettingObserver` defers `onChange` to the next `DispatchQueue.main` turn rather than calling it synchronously or scheduling through `RunLoop.main`.
**Rationale**: `@Published` publishes before the new value is assigned, so a synchronous observer would see the property's old value; and `RunLoop.main` schedules in the default run-loop mode only, which AppKit does not service while a mouse-down or a slider drag runs the run loop in its event-tracking mode. The main dispatch queue is drained in every run-loop mode, so this is the scheduling choice that keeps a live-dragging preview working, documented in source as the same fix an earlier observer needed for an identical failure.
**Approved**: pending

**Decision**: Treat `StoredSetting` and its `Observer`, in `StoredSettingPropertyWrapper.swift`, as excluded from this recipe's contract.
**Rationale**: the entire file is wrapped in a disabled compile-time condition and does not build into the product; the live property-observation surface for a `UserSetting` is `UserSettingObserver`/`ObservedSetting` in `UserSetting.swift`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | Performance |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

The `SettingsStorageProvider` contract cleanly separates the key/value contract from six independent backends, and `SettingsStore`/`UserSettings` route by `key.isSecure` with no backend-specific branching in the router (separation-of-concerns: passed). `InMemorySettingsStorageProvider`, `UserDefaultsSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, and `SqliteStorageProvider` each have a dedicated XCTest file covering defaults, round trips, contains/remove, and change notifications, but no test file exists for `iCloudSettingsStorageProvider` under the same test directory (unit-test-coverage: partial). Secrets route exclusively through `KeychainSecureSettingsStorageProvider`, which stores them in the OS-encrypted Keychain rather than plain `UserDefaults` or SQLite (secure-storage: passed). The same provider memoizes every keychain read, hit or confirmed miss, to avoid repeat round-trips to the keychain daemon (caching-strategy: passed). `KeychainSecureSettingsStorageProvider` and `SqliteStorageProvider` log every encode/SQL failure through `Loggable`, but `UserDefaultsSettingsStorageProvider.set` and `iCloudSettingsStorageProvider.set` return silently with no log call when JSON encoding fails, which this recipe records as open questions rather than passing requirements (explicit-error-handling: partial). `SqliteStorageProvider`'s `settings_kv` table declares a primary-key `key` column and a `NOT NULL` `value` column, and every write goes through one upsert statement, so a key can never end up with more than one row or a null value (data-integrity: passed).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | | Initial creation |
