---
id: 6363b5ff-f511-4e21-9ba7-6850787dba62
title: Settings Storage
domain: agentictoolkit://cookbook/foundation/settings-storage
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Typed key/value settings contract with in-memory, plain persistent, secure
  persistent, embedded-database, and cloud-synced backends.
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

`settings-storage` is the toolkit's typed key/value persistence layer for user preferences and secrets. A setting key is a typed descriptor: a stable name, a default value, and an is-secure flag. A storage provider is the pluggable backend contract — get/set/remove/contains plus a change stream that names which key changed, with a per-key live view and a per-key value stream derived from it. Six concrete backends implement the contract: an in-memory backend and its secure variant (for tests and previews), a plain persistent backend, a secure persistent backend, an embedded-database backend (SQLite), and a cloud-synced backend. A settings store — and its process-wide shared instance — routes each key to a secure or plain backend by the key's is-secure flag and merges both backends' change streams into one. Call sites almost never touch a provider directly: they declare a static observable setting (a live mirror of the store's value for that key) and read/write it through a value accessor, or wrap it in a setting-observer/observed-setting wrapper for a plain callback outside the reactive UI layer. A color setting is an observable setting whose value type is a color value.

## Behavioral Requirements

### Setting keys

- **key-name**: Each setting key MUST supply a stable name (a string) that every backend uses as its storage key.
- **key-default-value**: Each setting key MUST supply a default value of its own value type, returned whenever no value has been stored, or a stored value cannot be decoded, for its name.
- **key-secure-routing**: Each setting key MUST supply an is-secure flag, and the settings store MUST route a key with is-secure == true to its secure backing provider and every other key to its plain provider.

### Storage provider contract

- **provider-get-fallback**: get MUST return the key's default value when the backend holds no value, or holds a value that cannot be decoded as the key's value type, for that key's name.
- **provider-set-persists**: set MUST make the new value readable by a subsequent get for the same key on the same provider instance once set returns.
- **provider-remove-restores-default**: remove MUST cause a subsequent get for that key to return the default value and contains to return false.
- **provider-contains**: contains MUST return true only when a value has been explicitly stored for that key's name and has not since been removed.
- **provider-change-notification-on-set**: set MUST publish the key's name on the change stream after the new value becomes readable through get.
- **provider-change-notification-on-remove**: remove MUST publish the key's name on the change stream.
- **provider-publisher-replay**: The default per-key live view MUST emit the provider's current value for that key immediately upon subscription, then emit an updated value each time the change stream names that key.
- **provider-publisher-ignores-other-keys**: The per-key live view MUST NOT emit when the change stream names a different key.
- **provider-values-stream**: The per-key value stream MUST expose the same replay-then-live sequence as the live view, through an asynchronous sequence, cancelling its underlying subscription when the stream terminates.
- **provider-plain-not-secure**: A storage provider MUST report is-secure == false unless it also identifies itself as a secure storage provider.
- **secure-provider-is-secure**: A secure storage provider MUST report is-secure == true.

### In-memory provider / in-memory secure provider

- **inmemory-concurrent-access**: The in-memory provider MUST serialize set/remove against every get/contains, so a concurrent read never observes a partially-written value.
- **inmemory-seeded-initial-values**: The in-memory provider's seed-values constructor MUST seed its backing storage directly from the untyped initial-values argument, without validating that a seeded value matches the value type of any key that will later read it.
- **inmemory-secure-delegates**: The in-memory secure provider MUST delegate every operation and its change stream to an internally-held, private in-memory provider, differing from it only in also identifying itself as a secure storage provider.

### Plain persistent provider

- **plain-provider-native-fast-path**: The plain persistent provider MUST store and read integer, floating-point, boolean, string, binary, URL, and date values through the backing store's native object storage rather than JSON encoding.
- **plain-provider-json-fallback**: For any value type outside that native set — arrays, dictionaries, and other structured values — the plain persistent provider MUST JSON-encode the value and store it as binary data.
- **plain-provider-corrupted-decode-fallback**: When previously-stored data for a key fails to decode as the key's value type, get MUST return the default value rather than throwing or crashing.
- **plain-provider-encode-failure**: NEEDS REVIEW: Not implemented in source. When JSON encoding fails for a non-natively-supported value, set returns without writing, without logging, and without publishing on the change stream, so the caller has no way to learn the write did not happen.

### Secure persistent provider

- **secure-provider-string-fast-path**: For a string-valued key, get and set MUST read and write the raw string directly, without JSON quoting, so the secure store's entry holds the literal secret rather than a JSON string literal.
- **secure-provider-codable-path**: For any other structured, serializable value, set MUST JSON-encode the value to a UTF-8 string before writing, and get MUST JSON-decode the stored string back to the value type, returning the default value if decoding fails.
- **secure-provider-encode-failure-logged**: When encoding a non-string value fails, set MUST log an error and return without writing to the secure store or publishing on the change stream.
- **secure-provider-write-failure-invalidates-memo**: When the underlying secure-store write fails, set MUST remove any cached memo entry for that key and MUST NOT publish on the change stream.
- **secure-provider-remove-failure-invalidates-memo**: When the underlying secure-store delete fails, remove MUST remove any cached memo entry for that key and MUST NOT publish on the change stream.
- **secure-provider-read-memoization**: get MUST memoize the raw secure-store string for a key — including a confirmed absence — the first time it is read, and MUST answer every subsequent get for that key from the memo rather than re-querying the secure store, until set or remove updates the memo.
- **secure-provider-memo-per-instance**: The read memo MUST be private, per-instance state; a second secure persistent provider constructed for the same service MUST start with an empty memo.
- **secure-provider-contains-bypasses-memo**: contains MUST query the secure store directly, never through the read memo.
- **secure-provider-global-service-override**: Constructing a secure persistent provider with a non-nil service argument MUST assign it to the process-wide secure-store service identifier, and MUST unconditionally assign its access-group argument — including "none" — to the process-wide secure-store access group, so constructing an instance changes secure-store routing for every secure-store-backed caller in the process, not only for the new instance.

### Embedded-database provider

- **sqlite-schema-creation**: Constructing the embedded-database provider with a path MUST open, creating if absent, a database at that path, and MUST create a `settings_kv` table (`key TEXT PRIMARY KEY, value BLOB NOT NULL`) if it does not already exist, throwing an open error or a schema error if either step fails.
- **sqlite-json-storage**: set MUST JSON-encode every value and store it as the row's value blob via an upsert statement, so a key never occupies more than one row.
- **sqlite-serialized-access**: Every get, set, remove, and contains MUST run serialized against the same database handle, so concurrent calls on one instance are never interleaved.
- **sqlite-transient-binding**: Bound text and binary parameters MUST be copied by the database engine rather than referenced from caller-owned memory that may be freed before the statement executes.
- **sqlite-close-on-deinit**: The instance MUST close its database handle when it is deallocated.
- **sqlite-encode-failure-logged**: When JSON encoding fails, set MUST log an error and return without writing a row or publishing on the change stream.
- **sqlite-write-failure-no-notification**: When the prepare, bind, or step of the upsert statement fails, set MUST NOT publish on the change stream; the failure is logged by the layer that detected it.

### Cloud-synced provider

- **cloudsync-provider-native-fast-path**: The cloud-synced provider MUST store and read integer, 64-bit integer, floating-point, boolean, and string/binary values through the backing cloud key-value store's native storage; URL and date values are not natively supported and MUST go through the JSON-encoded binary path.
- **cloudsync-provider-int-promotion**: For a plain-integer-valued key, set MUST store the value as a 64-bit integer (the backing store has no native plain-integer accessor), and get MUST bridge a stored 64-bit integer back to a plain integer.
- **cloudsync-provider-explicit-synchronize**: set and remove MUST call the backing store's synchronize operation after mutating it, in addition to publishing on the change stream.
- **cloudsync-provider-external-change-forwarding**: The provider MUST forward every key named in the backing store's external-change notification payload onto its own change stream, so a change made on another device is observable through the same stream as a local set.
- **cloudsync-provider-encode-failure**: NEEDS REVIEW: Not implemented in source. When JSON encoding fails for a non-natively-supported value, set returns without writing, without logging, and without publishing on the change stream, identically to the plain persistent provider.

### Settings store / shared instance

- **store-routing**: The settings store's get/set/remove/contains MUST dispatch to its secure provider when the key's is-secure flag is true and to its plain provider otherwise.
- **store-merged-changes**: The settings store's change stream MUST be the merge of both backing providers' change streams, so a single subscription observes changes from either provider.
- **store-default-providers**: Constructing a settings store with no arguments MUST default to the plain persistent provider for the plain provider and the secure persistent provider for the secure provider.
- **usersettings-shared-singleton**: The shared settings store instance MUST be a single, mutable, process-wide instance that every setting key's value/remove/exists accessor and every observable setting reads and writes through by default.
- **usersettings-shared-replacement-timing**: A host app SHOULD replace the shared settings store instance only before constructing any observable setting; see Design Decisions for the rationale and usersettings-shared-reassignment in Edge Cases for what happens otherwise.

### Observable setting / setting observer / observed-setting wrapper / color setting

- **usersetting-construction-reads-through**: Constructing an observable setting MUST synchronously read the current value for its key from the shared settings store instance before returning, so its current value reflects any already-stored value rather than always starting at the default value.
- **usersetting-value-mirror**: An observable setting's current value MUST update whenever the shared settings store instance's change stream names this instance's key, re-reading the value from the shared instance at that point.
- **usersetting-write-through**: Writing a new value to an observable setting MUST write through the shared settings store instance's set, so a subsequent read from any caller observes the new value.
- **observer-deferred-callback**: A setting observer's change callback MUST fire on the main thread on the turn after the current value changes, not synchronously inside the write that caused the change, and MUST NOT fire for the value a setting observer was constructed with.
- **observedsetting-wraps-observer**: An observed-setting wrapper MUST forward its wrapped value get/set to an internally-held setting observer and expose the underlying observable setting as its projected value.
- **colorsetting-alias**: A color setting MUST be an observable setting whose value type is a color value.
- **secure-provider-service-override-timing**: A caller SHOULD construct at most one secure persistent provider per process with a non-default service/access-group, or construct every instance with the same override; see Design Decisions.

## Appearance

Not applicable — this is a settings persistence layer (typed keys and pluggable key/value backends), not a visual component.

## States

Not applicable — this is a settings persistence layer, not a visual component; its runtime states (constructed, subscribed, memoized, read-through) are covered under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a settings persistence layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-storage-001 | key-name, key-default-value | A setting key of integer type named `"launchCount"` with default `0` | `.name == "launchCount"`, `.defaultValue == 0` — `SettingsKeyTests.testKeyStoresNameAndDefault` |
| settings-storage-002 | key-secure-routing, store-routing | Set a plain key and a secure key through the shared settings store instance | Plain key's value is only readable from the plain persistent provider; secure key's only from the secure persistent provider — traced to the provider-selection logic |
| settings-storage-003 | provider-get-fallback | Fresh in-memory provider, `get(launchCount)` | `0` — `testReturnsDefaultValueWhenEmpty` |
| settings-storage-004 | provider-set-persists, provider-change-notification-on-set | `store.set(1, for: launchCount)`, then `store.set("hi", for: displayName)` while subscribed to the change stream | `get` returns `1`/`"hi"`; the change stream emits `["test.launchCount", "test.displayName"]` in order — `testSetEmitsChange` |
| settings-storage-005 | provider-remove-restores-default, provider-change-notification-on-remove, provider-contains | `store.set(99, for: launchCount)`, then `store.remove(launchCount)` | `contains == false`, `get == 0`, one change-stream emission of `"test.launchCount"` — `testRemoveClearsValueAndReturnsDefault` |
| settings-storage-006 | provider-publisher-replay, provider-publisher-ignores-other-keys | `store.set(5, for: launchCount)`; subscribe to its live view; `set("ignored", for: displayName)`; `set(99, for: launchCount)` | Received `[5, 99]`; no emission for the `displayName` write — `testPublisherIgnoresOtherKeys` |
| settings-storage-007 | provider-values-stream | `store.set(10, for: launchCount)`; iterate its value stream; concurrently `set(11, ...)` | Yields `10` then `11` — `testAsyncStreamYieldsValues` |
| settings-storage-008 | provider-plain-not-secure, secure-provider-is-secure | `isSecure` of a freshly constructed in-memory provider; `isSecure` of a freshly constructed secure persistent provider | `false`; `true` — `testProviderReportsSecure` |
| settings-storage-009 | inmemory-concurrent-access | Many concurrent `set` calls for distinct keys against one in-memory provider | Every key reads back its own written value afterward, none dropped or corrupted — traced to the serialized-access implementation; not exercised by a test in the given suite |
| settings-storage-010 | inmemory-seeded-initial-values | In-memory provider constructed with seed value `7` for `launchCount`, then `.get(launchCount)` | `7` — `testInitialValuesArePreserved` |
| settings-storage-011 | inmemory-secure-delegates | `isSecure` of the in-memory secure provider, delegating storage to its private in-memory provider | `isSecure == true`; get/set/remove/contains behave exactly like the wrapped in-memory provider — traced to its delegation; not exercised by a test in the given suite |
| settings-storage-012 | plain-provider-native-fast-path | Plain persistent provider `set(true, for: hasCompletedOnboarding)` | The backing store holds a non-nil native boolean for that key — `testBoolRoundTrip` |
| settings-storage-013 | plain-provider-json-fallback | `set(["alpha", "beta", "gamma"], for: recentSearches)` | The backing store holds non-nil binary data for that key and `get` round-trips the array — `testStringArrayRoundTrip` |
| settings-storage-014 | plain-provider-corrupted-decode-fallback | Inject garbage data under the `userPreferences` key, then `get(userPreferences)` | Returns `userPreferences`'s default value — `testCodableStructFallsBackToDefaultOnCorruptedData` |
| settings-storage-015 | secure-provider-string-fast-path | `store.set("hello", for: displayName)`; read the raw secure-store entry for that key | Raw string is `hello`, not a JSON-quoted string — `testStringValueIsStoredRawNotJSONQuoted` |
| settings-storage-016 | secure-provider-codable-path | `store.set(a structured preferences value, for: userPreferences)` | `get` round-trips an equal value — `testCodableStructRoundTrip` |
| settings-storage-017 | secure-provider-encode-failure-logged, secure-provider-write-failure-invalidates-memo | A value whose encoding fails during `set` | An error is logged; `set` returns without writing or notifying the change stream — traced to the encode-failure branch; not exercised by a test in the given suite |
| settings-storage-018 | secure-provider-remove-failure-invalidates-memo | A forced secure-store delete failure inside `remove` | Memo entry is dropped; no change-stream emission — traced to `remove`'s failure branch; not exercised by a test in the given suite |
| settings-storage-019 | secure-provider-read-memoization | `store.set("first", for: displayName)`; delete the item behind the provider directly in the secure store; `store.get(displayName)` | `"first"` — `testRepeatReadsAreServedFromTheMemoNotTheKeychain` |
| settings-storage-020 | secure-provider-memo-per-instance | Provider A sets `"owned"` for `displayName`; construct provider B on the same service; `B.get(displayName)` | `"owned"`, read through B's own empty memo — `testMemoizedValuesAreScopedToTheProviderInstance` |
| settings-storage-021 | secure-provider-contains-bypasses-memo | `store.get(displayName)` memoizes absence; a value is written behind the provider directly into the secure store; `store.contains(displayName)` | `true` — reflects live secure-store state, not the memo — traced to `contains` and `testAnAbsentKeyIsMemoizedToo` |
| settings-storage-022 | secure-provider-global-service-override, secure-provider-service-override-timing | Construct a provider with service `"A"`, then a second with service `"B"` | The process-wide secure-store service identifier becomes `"B"` for both instances' subsequent calls — traced to the constructor's unconditional assignment |
| settings-storage-023 | sqlite-schema-creation, sqlite-json-storage, sqlite-close-on-deinit | Embedded-database provider opened on a temp file, `set(42, for: launchCount)`; drop the instance; open a second provider on the same file; `.get(launchCount)` | `42` — `testValuesPersistAcrossInstances` |
| settings-storage-024 | sqlite-serialized-access | `set(true, ...)`, `set(42, ...)`, `set("Hello, world!", ...)` issued back-to-back on one instance | All three round-trip correctly with no cross-contamination — `testBoolRoundTrip`/`testIntRoundTrip`/`testStringRoundTrip` |
| settings-storage-025 | sqlite-transient-binding | `set("Hello, world!", for: displayName)` where the bound string is a temporary value | The stored value survives after the temporary is deallocated, verified indirectly by every round-trip test succeeding |
| settings-storage-026 | sqlite-encode-failure-logged, sqlite-write-failure-no-notification | An encode-failing value, or a forced SQL prepare/step failure | An error is logged and the change stream does not fire — traced to the write path's failure branches; not exercised by a test in the given suite |
| settings-storage-027 | cloudsync-provider-native-fast-path, cloudsync-provider-int-promotion | Cloud-synced provider `set(5, for: anIntKey)` | Stored as a 64-bit integer, not a native plain integer — traced to the promotion step; no test file exists for this provider (see Compliance) |
| settings-storage-028 | cloudsync-provider-explicit-synchronize | `set("v", for: aKey)` | The backing store's synchronize operation is called before the change stream fires — traced to `set`'s body |
| settings-storage-029 | cloudsync-provider-external-change-forwarding | Post the backing store's external-change notification with a changed-keys payload of `["someKey"]` | The provider's own change stream emits `"someKey"` — traced to the notification observer set up at construction |
| settings-storage-030 | store-merged-changes, usersettings-shared-singleton | Subscribe to the shared settings store instance's change stream; set a plain key then a secure key | Both keys' names are observed on the one subscription — traced to the merged-stream implementation |
| settings-storage-031 | store-default-providers | A settings store constructed with no arguments | A plain key round-trips through the plain persistent provider; a secure key round-trips through the secure persistent provider — traced to the constructor's default arguments |
| settings-storage-032 | usersetting-construction-reads-through, usersetting-value-mirror | The shared settings store instance is set to `7` via one observable setting, then construct a second, independent observable setting for the same name/default | The second instance's current value is `7` immediately on construction, not its own default value — traced to its constructor |
| settings-storage-033 | usersetting-write-through | `mySetting`'s value is set to a new value | A subsequent read of that key from any reader returns the new value — traced to the value accessor's setter |
| settings-storage-034 | observer-deferred-callback | Construct a setting observer on a setting with a change callback, then write a new value to that setting | The callback has still not fired synchronously after the write, and fires only after the next main-thread turn — traced to the deferred-dispatch implementation |
| settings-storage-035 | observedsetting-wraps-observer, colorsetting-alias | An observed-setting wrapper around a setting; read its wrapped and projected values; a color setting used as an observable setting over a color value | Wrapped value proxies the observer's value, projected value is the underlying observable setting; the color setting type-checks as an observable setting over a color value — traced to the wrapper and the color-setting alias |
| settings-storage-036 | usersettings-shared-replacement-timing | Replace the shared settings store instance before constructing any observable setting | Every subsequently-constructed observable setting reads and subscribes against the new instance consistently, contrasting with the open question in Edge Cases — traced to the shared instance's declaration as a mutable, replaceable reference |

## Edge Cases

- **empty-collection-vs-absent**: Setting an empty array for a key MUST be distinguishable from never having set it: `contains` MUST return `true` after storing an empty array even though `get` also returns an empty array for an absent key whose `defaultValue` happens to be empty — traced to `testEmptyArrayRoundTrip`.
- **key-name-collision-across-types**: No provider detects or rejects two setting keys that share the same name but declare different value types; each key's `get` still returns that key's own default value when the stored representation cannot be cast or decoded as its value type, so a collision surfaces as "always reads as freshly defaulted" rather than as a crash or a visible error. SHOULD — callers are responsible for giving every key a process-unique name; traced to `SettingsKeyTests.testKeysWithDifferentValueTypesAreDistinctTypes` and every provider's cast-or-decode-else-default `get` path.
- **inmemory-untyped-seed**: The in-memory provider's seed-values constructor accepts an untyped map; seeding a key with a value of the wrong runtime type for that key MUST behave exactly like an absent key on the next typed `get` — the cast fails and the default value is returned — never a crash.
- **boundary-int64-on-64-bit**: A plain integer and a 64-bit integer share the same width on the platform this component ships to, so the cloud-synced provider's bridge from a stored 64-bit integer back to a plain integer MUST always succeed for a value this component itself ever wrote; the source defines no behavior for a stored 64-bit integer outside a plain integer's range, because nothing here can produce one.
- **concurrent-inmemory-access**: Concurrent `get`/`set`/`remove`/`contains` calls on one in-memory provider instance MUST NOT corrupt or lose a write: reads run without exclusive access and writes run with it, so readers see a consistent snapshot against any single writer.
- **concurrent-sqlite-access**: Concurrent calls on one embedded-database provider instance MUST be serialized, so two `set` calls for different keys never interleave their SQL statements against the same handle.
- **concurrent-system-backed-providers**: The plain persistent, secure persistent, and cloud-synced providers add no locking of their own around the system store each wraps; concurrent access is left to whatever thread-safety the underlying system stores provide, and to these types' isolation to the platform's UI-thread actor (see Platform Notes).
- **sqlite-open-failure**: If opening the database or creating the schema fails, constructing the embedded-database provider MUST throw an open error or a schema error respectively, leaving no provider instance constructed.
- **secure-provider-write-or-delete-failure**: If the underlying secure-store write or delete fails, `set`/`remove` MUST leave the previously-stored value observably unchanged from the caller's perspective on the next `get`/`contains` — the memo is invalidated, forcing a fresh read-through — and MUST NOT publish on the change stream.
- **usersettings-shared-reassignment**: The shared settings store instance's documentation ("client apps should create and set this") makes setting it at startup the caller's job. Replacing it after an observable setting exists leaves that observable setting subscribed to the old instance's change stream, captured once at construction, while its value accessor and the subscription's re-read target the current shared instance; there is no way to re-subscribe an existing observable setting.
- **offline-cloud-sync**: The cloud-synced provider does not itself detect or report connectivity loss; the backing cloud key-value store is responsible for queuing local writes and syncing them once connectivity returns, and this component's change stream fires only for a local `set`/`remove` or an externally-delivered change notification — never to report a sync attempt, a sync failure, or a reconnection.

## Configuration

Constructor parameters (dependency injection) per backend:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Settings store's plain-provider override | provider | the plain persistent provider | Backend for keys with `isSecure == false` |
| Settings store's secure-provider override | provider | the secure persistent provider | Backend for keys with `isSecure == true` |
| In-memory provider's seed values | key/value map | empty | Seed values for tests/previews |
| In-memory secure provider's seed values | key/value map | empty | Seed values, forwarded to its internal in-memory provider |
| Plain persistent provider's backing store | system store | the platform default | Backing store selection |
| Secure persistent provider's service identifier | text or none | none (keeps the default service, the app's bundle identifier) | Secure-store service identifier override |
| Secure persistent provider's access group | text or none | none | Shared secure-store access group |
| Embedded-database provider's path | text | none (required) | Filesystem path of the embedded database |
| Cloud-synced provider's backing store | system store | the platform default | Backing key-value store |
| JSON encoder/decoder (plain persistent, secure persistent, embedded-database, and cloud-synced providers) | encoder/decoder | the default encoder/decoder | Injected for testability |

Setting keys declared on the shared settings store in the given sources:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `editor.show_line_numbers` | boolean | `true` | Show line numbers in the editor |
| `editor.show_overview` | boolean | `true` | Show the overview strip in the editor |
| `editor.show_invisibles` | boolean | `false` | Show invisible characters in the editor |
| `git.executable_path` | text | `/usr/bin/git` | Path to the git executable |
| `git.status_timeout_seconds` | integer | `5` | Timeout, in seconds, for a git status query |
| `git.status_includes_submodules` | boolean | `false` | Whether a git status query includes submodules |
| `theme.active_theme_id` | text | the toolkit's default built-in theme identifier | Active theme identifier; built-in themes are never stored under this key |
| `theme.custom_themes` | array of color themes | empty | User-defined custom themes |
| `launchAtLogin` | boolean | `false` | Whether the app launches at login |
| `launchAtLoginPromptShown` | boolean | `false` | Whether the launch-at-login prompt has been shown |
| `launchAtLoginHintDismissed` | boolean | `false` | Whether the launch-at-login hint has been dismissed |

## Deep Linking

Not applicable: this component exposes no URL scheme or route; it is a storage layer with no navigable surface of its own.

## Localization

The embedded-database provider's own error type supplies two hardcoded English description strings: one describing the failed-open case with the path and the underlying error message, and one describing the failed-schema case with the underlying error message. Neither is looked up from a localization table, so every consumer sees the same English text regardless of locale. No other user-facing string originates from the given sources.

## Accessibility Options

Not applicable: no UI; nothing in the given sources reads Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: no flag lookup gates any behavior in the given sources — every provider and every observable setting is unconditionally active once constructed.

## Analytics

Not applicable: the given sources call a logging facility for diagnostics (see Logging) but never an analytics or event-tracking API.

## Privacy

- **Data collected**: None of the given sources collect data on their own; they persist values a caller supplies for its own keys — including, for a key with `isSecure == true`, secrets such as the API keys the secure persistent provider's own documentation cites as a target use case.
- **Storage**: A plain key (`isSecure == false`) is stored, by default, in the platform's plain preferences store (a property list on local disk, by default) or, if the caller supplies the embedded-database provider, in a SQLite file at a caller-chosen path — neither encrypted by this component. A secure key is stored in the platform's secure credential store, which the OS encrypts at rest and which can be scoped to a shared access group for a co-signed daemon. The in-memory provider and in-memory secure provider never touch disk and are ephemeral for the life of the process. The given sources treat a failed secure-store read/write as an ordinary error — logged, memo invalidated — rather than a detected security violation; there is no lockout, alert, or revocation behavior for repeated secure-store failures.
- **Transmission**: Every backend except the cloud-synced provider is local-device-only. The cloud-synced provider syncs its values off-device through the platform's cloud key-value store to the user's cloud account and back down to their other devices; it is used only for plain (non-secure) settings in the given sources — nothing routes a secure key through it.
- **Retention**: A value set through any backend persists until explicitly removed or the underlying store is cleared (app-data reset, secure-store item deletion, or an uninstall — secure-store items can outlive an uninstall on some platforms); the in-memory backends retain nothing past the process's lifetime. The cloud-synced provider resolves a conflicting concurrent edit from two devices last-write-wins, per its own documentation, with the cloud store performing the resolution.

## Logging

Subsystem: the app's bundle identifier (falls back to the literal string `nil` if absent) | Category: the conforming provider's role name (e.g. the secure persistent provider, the embedded-database provider)

| Event | Level | Message |
|-------|-------|---------|
| Secure-store non-string encode failure | error | Failed to encode value for secure key, naming the key |
| Embedded-database encode failure | error | Failed to encode value for key, naming the key |
| Embedded-database `SELECT` prepare failure | error | prepare SELECT failed, with the underlying error message |
| Embedded-database `UPSERT` prepare failure | error | prepare UPSERT failed, with the underlying error message |
| Embedded-database blob bind failure | error | bind blob failed, with the underlying error message |
| Embedded-database `UPSERT` step failure | error | UPSERT step failed, with the underlying error message |

The in-memory provider, in-memory secure provider, plain persistent provider, and cloud-synced provider emit no log lines in the given sources.

## Platform Notes

- **SwiftUI**: `UserSetting` is already an `ObservableObject`, so a SwiftUI view binds directly to `currentValue` with `@ObservedObject`/`@StateObject` on an instance the view (or its model) holds. The retired `StoredSetting` property wrapper in `StoredSettingPropertyWrapper.swift` sketched a `@propertyWrapper`/`DynamicProperty` alternative, but the whole file is compiled out with `#if false` and is not the live surface.
- **Compose**: Translate `SettingsStorageProvider` to a small Kotlin interface backed by Jetpack `DataStore<Preferences>` for plain keys and `EncryptedSharedPreferences`/Android Keystore for secure keys; `changes: AnyPublisher<String, Never>` becomes a `SharedFlow<String>`; `UserSetting` becomes a `MutableStateFlow`-backed delegate collected with `collectAsState()`, mirroring the eager, read-on-construction behavior of `UserSetting.init`.
- **React/Web**: Translate `SettingsStorageProvider` to a small interface backed by `localStorage`/`IndexedDB` for plain keys and a platform credential store (or a server-side secret proxy) for secure keys; `changes` becomes an `EventTarget`, or an observable keyed by name; `UserSetting` becomes a hook built on `useSyncExternalStore` over the same store.
- **AppKit / UIKit**: This is the source's own consumer story. `AppearanceManager`, `LaunchAtLoginManager`, and the `ComposableSettingsWindow` view models (`ChoiceViewModel`, `ColorViewModel`, `FontViewModel`, `RangeViewModel`) all bind to `UserSetting`/`UserSettingObserver` rather than to any storage provider directly, and `UserSettingObserver` deliberately hops to `DispatchQueue.main` — not `RunLoop.main` — so it still fires while AppKit is running a mouse-tracking loop in `.eventTracking` mode. Every settings-storage type is `@MainActor`-isolated by declaration or by conforming to the `@MainActor` `SettingsStorageProvider`/`StorableSetting` protocols, except `InMemorySettingsStorageProvider` and `UserDefaultsSettingsStorageProvider`, which carry no `@MainActor` annotation of their own and instead serialize their own internal state (a concurrent `DispatchQueue` with a barrier flag on writes, and thread-safe `UserDefaults`, respectively) so they remain safe to call from contexts that are not already on the main actor. `SqliteStorageProvider`'s `database` pointer is declared `nonisolated(unsafe)` so `deinit` — which runs outside actor isolation — can close it synchronously without an `await`. `SqliteStorageProvider` itself serializes access on a private serial `DispatchQueue`; `UserDefaultsSettingsStorageProvider`, `KeychainSecureSettingsStorageProvider`, and `iCloudSettingsStorageProvider` add no locking of their own, relying on `UserDefaults`, the Keychain, and `NSUbiquitousKeyValueStore`'s own thread-safety plus their `@MainActor` isolation. Swift's `Int` is 64 bits wide on every Apple platform this ships to, which is what makes `iCloudSettingsStorageProvider`'s bridge from a stored `Int64` back to `Int` lossless (see `boundary-int64-on-64-bit` in Edge Cases). The Configuration constructor parameters map to `SettingsStore.settingsProvider`/`.secureSettingsProvider`; `InMemorySettingsStorageProvider.initial`/`InMemorySecureSettingsStorageProvider.initial` (`[String: Any]`); `UserDefaultsSettingsStorageProvider.defaults` (`UserDefaults`, default `.standard`); `KeychainSecureSettingsStorageProvider.service`/`.accessGroup` (`String?`); `SqliteStorageProvider.path` (`String`, required); `iCloudSettingsStorageProvider.store` (`NSUbiquitousKeyValueStore`, default `.default`); and `encoder`/`decoder` (`JSONEncoder`/`JSONDecoder`) on every backend with a JSON fallback. Each persisted key in Configuration is exposed as a camelCase static accessor on `UserSettings` (e.g. `editor.show_line_numbers` → `UserSettings.editorShowLineNumbers`).
- **WinUI 3**: `StorableSetting`/`SettingsStorageProvider` map to a small C# interface with `Get<T>`/`Set<T>`/`Remove<T>`/`Contains<T>` plus a `changes` event, backed by `Windows.Storage.ApplicationData.Current.LocalSettings` (an `ApplicationDataContainer`, natives stored directly and complex types JSON-encoded via `System.Text.Json`, mirroring the native/JSON split here) for plain keys and the Windows Credential Locker (`Windows.Security.Credentials.PasswordVault`) in place of the Keychain for secure keys. `SqliteStorageProvider`'s hand-rolled `sqlite3` calls map to `Microsoft.Data.Sqlite`. `changes` becomes a plain `event Action<string>` or `IObservable<string>`. `UserSetting<T>` becomes an `ObservableObject`/`INotifyPropertyChanged` wrapper exposing a `T Value` property, and `UserSettingObserver`'s main-queue hop becomes `DispatcherQueue.TryEnqueue` from the setting's change handler, so an update still lands on the UI thread while WinUI is inside a modal input loop — the same reason the source hops to a dispatch queue rather than a run loop.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/ColorSetting.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/InMemorySecureSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/InMemorySettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/KeychainSecureSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/SecureStoredSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/SqliteStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/UserDefaultsSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStorageProviders/iCloudSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/SettingsStore.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/StorableSetting.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/StoredSettingPropertyWrapper.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/StoredSettingsStorageProvider.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings+Editor.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings+Git.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings+Theme.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/CommandPalette/CommandPaletteCoordinator.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/Features/CommandPalette/CommandPaletteModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/Appearance/AppearanceManager.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/AbstractViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ButtonViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ChoiceViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ColorViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/FontViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ProgressViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/RangeViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ThemeChoiceViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewModels/ViewModel.swift` |
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/LaunchAtLogin/LaunchAtLoginManager.swift` |

## Design Decisions

**Decision**: Replace `UserSettings.shared` — if a host app needs a different provider configuration at all — only before constructing any `UserSetting`. (Apple/Swift implementation.)
**Rationale**: `UserSetting.init` captures `UserSettings.shared` once, to read the initial value and subscribe to its `changes`; replacing `shared` afterward leaves that instance's subscription pinned to the old store while its `value` accessor and the subscription's own re-read both target whichever instance is current — an inconsistency the source leaves to the caller's setup order (see `usersettings-shared-reassignment` in Edge Cases).
**Approved**: pending

**Decision**: Construct at most one `KeychainSecureSettingsStorageProvider` per process with a non-default `service`/`accessGroup`, or construct every instance with the same override. (Apple platform — Keychain-backed secure provider.)
**Rationale**: `init` assigns its `service` and `accessGroup` arguments to the process-wide statics `KeychainHelper.service`/`KeychainHelper.accessGroup`, including assigning `nil` unconditionally, so a later default-argument instance silently clears an override an earlier instance made intentionally; this is documented inline in `init`'s own comment, and a second, differently-configured instance changes keychain routing for every existing instance too, not only the new one.
**Approved**: pending

**Decision**: `KeychainSecureSettingsStorageProvider` memoizes every read — a hit or a confirmed miss — for the life of the instance rather than reading through on every `get`. (Apple platform — Keychain-backed secure provider.)
**Rationale**: the type's own documentation traces this to a measured cost — a keychain miss walks the access-group query, the legacy no-group query, and every retired service before returning, and bulk-resolving many AI-provider settings on the main thread pinned the app above 100% CPU inside the keychain query call. The provider owns every write to the keys it serves, so the memo can be exact rather than time-based.
**Approved**: pending

**Decision**: `UserSettingObserver` defers `onChange` to the next `DispatchQueue.main` turn rather than calling it synchronously or scheduling through `RunLoop.main`. (AppKit / Apple platform.)
**Rationale**: `@Published` publishes before the new value is assigned, so a synchronous observer would see the property's old value; and `RunLoop.main` schedules in the default run-loop mode only, which AppKit does not service while a mouse-down or a slider drag runs the run loop in its event-tracking mode. The main dispatch queue is drained in every run-loop mode, so this is the scheduling choice that keeps a live-dragging preview working, documented in source as the same fix an earlier observer needed for an identical failure.
**Approved**: pending

**Decision**: Treat `StoredSetting` and its `Observer`, in `StoredSettingPropertyWrapper.swift`, as excluded from this recipe's contract. (Swift implementation.)
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | | Initial creation |
