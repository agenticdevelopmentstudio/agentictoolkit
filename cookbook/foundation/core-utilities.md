---
id: cf3a3dc9-6fed-47ba-a699-71ff806dcedd
title: Core Utilities
domain: agentictoolkit://cookbook/foundation/core-utilities
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Six foundation-tier utilities: secret storage in the system credential
  store, an encoding-skip wrapper, a structured-logging factory, floating-point
  clamping, semantic-version parsing, and text folding.'
platforms:
- swift
- macos
tags:
- credential-storage
- secrets
- semantic-versioning
- logging
- text-normalization
- value-types
depends-on: []
related:
- agentictoolkit://cookbook/ai/plugins/secret-storing
- agentictoolkit://cookbook/workspace/extensions/manifest/vs-code-engine-range
references:
- packages/apple/AgenticToolkit/Core/CodableIgnored.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/KeychainHelper.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/MathUtils.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SemanticVersion.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/TextFolding.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/KeychainHelperTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/SemanticVersionTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/TextFoldingTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/CGFloatClampedTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Core Utilities

## Overview

This recipe covers six independent foundation-tier utilities. Each has no
dependency on anything else in this recipe or on any other part of the
package; together they form the lowest tier of the toolkit — the tier every
other logic and UI component is built on top of.

- **An encoding-skip wrapper** — removes a field from a model's standard
  structured encoding and decoding entirely, so a value can exist on a model
  without ever appearing in its JSON representation.
- **Secret storage** — a static, namespace-style API over the system
  credential store's generic-password items, with built-in migration across
  a configurable access group and a list of retired service identifiers.
  Consumed directly by a secure-settings storage provider and by the AI
  plugin kit's secret-storing component.
- **A logger factory contract** — a contract that gives any conforming type
  a structured logger derived from the app's bundle identifier and the
  type's own name, with no boilerplate at each call site beyond a single
  factory-backed property declaration.
- **Float clamping** — a single clamp-to-range extension method; pure
  arithmetic, no state.
- **Semantic version parsing** — a `major.minor.patch` parser and comparable
  value type with an explicit upper bound on each component, guarding
  arithmetic callers (such as an extension manifest's engine-range caret
  ceiling) against integer overflow traps.
- **Text folding** — a single case-and-diacritic folding helper for
  locale-independent text matching, used by a command-palette model and an
  extension quick-pick model.

None of the six utilities depends on any UI framework; none renders
anything, holds view state, or performs networking.

## Behavioral Requirements

### Encoding-skip wrapper

- **encoding-skip-shape**: The wrapper MUST be a generic value type holding
  a single mutable optional wrapped value, and MUST provide a way to
  construct it directly from that optional value.
- **encoding-skip-decode-yields-nothing**: The wrapper's decoding behavior
  MUST initialize the wrapped value to nothing unconditionally, regardless
  of whether the corresponding key is present or absent in the decoded
  input.
- **encoding-skip-encode-noop**: The wrapper's encoding behavior MUST be a
  no-op — it MUST NOT write anything to the target encoding.
- **decode-integration-skips-key**: the decoding-side integration
  specialized for the wrapper MUST return a wrapper holding nothing,
  without attempting to read the source at that key at all.
- **encode-integration-skips-key**: the encoding-side integration
  specialized for the wrapper MUST return without writing a null, a value,
  or anything else — the key MUST NOT appear in the encoded output at all.
- **encoding-skip-round-trip-loses-value**: encoding a model whose wrapped
  field holds a non-nothing value and then decoding the result back MUST
  yield a nothing wrapped value on the decoded copy — the original value
  MUST NOT survive an encode/decode round trip.
- **encoding-skip-concurrency**: The wrapper MUST NOT claim to be safe to
  share across concurrent contexts; its wrapped value is mutable, so a
  caller sharing one instance across concurrency domains MUST supply its
  own synchronization.

### Secret storage

- **keychain-service-default**: the store's `service` identifier MUST
  default to the app's bundle identifier, or `"com.agentictoolkit"` when
  none is available, and MUST be reassignable by a caller at any time.
- **keychain-access-group-default**: the store's `accessGroup` MUST default
  to nothing.
- **keychain-legacy-services-default**: the store's `legacyServices` MUST
  default to an empty list, ordered newest-retired-first.
- **keychain-query-shape**: building a query for an account MUST identify
  the item as a generic password (`kSecClass` = `kSecClassGenericPassword`),
  scoped to the store's current `service` (`kSecAttrService`) and the given
  account (`kSecAttrAccount`).
- **keychain-query-access-group-forces-data-protection**: when a query is
  built with a non-nothing access group, it MUST additionally scope to that
  group (`kSecAttrAccessGroup`) and require data-protection-keychain
  semantics (`kSecUseDataProtectionKeychain` = true); when the access group
  is nothing, neither key MUST be present.
- **keychain-set-overwrites**: setting a value that hits a duplicate-item
  status on its first attempt MUST fall back to an update for the same
  query, so a second `set` call for the same key MUST overwrite the first
  value rather than fail.
- **keychain-set-access-group-accessibility**: when the store's access
  group is non-nothing at the time `set` runs, the item's accessibility
  attribute (`kSecAttrAccessible`) MUST be set to after-first-unlock,
  this-device-only.
- **keychain-set-returns-status**: `set` MUST return true only when the
  underlying add/update call reports success, and MUST return false for
  any other status.
- **keychain-get-primary-lookup**: `get` MUST first query under the current
  `service`/`accessGroup` scope and MUST return the stored string directly
  when that query succeeds.
- **keychain-get-access-group-migration**: when the primary lookup fails
  and the store's access group is non-nothing, `get` MUST retry the query
  with no access group; on success it MUST re-store the recovered value
  under the current `service`/`accessGroup` scope via `set` before
  returning it.
- **keychain-get-legacy-service-migration**: when the access-group retry
  also fails (or does not apply), `get` MUST iterate `legacyServices` in
  order and, for the first retired service under which the key is found,
  MUST re-store the recovered value under the current `service` before
  returning it.
- **keychain-get-exhausted-returns-nothing**: when the primary lookup, the
  access-group retry, and every entry in `legacyServices` all fail to
  locate the key, `get` MUST return nothing.
- **keychain-legacy-item-not-deleted**: when `get` recovers a value from a
  legacy access-group scope or a retired service, it MUST NOT delete the
  original item under that legacy scope — only a new copy is written under
  the current scope.
- **keychain-copy-value-single-match**: the lookup helper MUST limit the
  match to a single item (`kSecMatchLimit` = `kSecMatchLimitOne`) and
  request the data back (`kSecReturnData` = true), and MUST decode the
  returned data as UTF-8 text.
- **keychain-copy-value-logs-unexpected-errors-only**: the lookup helper
  MUST log an error when the underlying lookup call returns a status other
  than success and other than item-not-found; it MUST NOT log anything when
  the status is item-not-found.
- **keychain-delete-idempotent**: `delete` MUST return true when the
  underlying delete call reports success or item-not-found, and MUST
  return false for any other status — deleting an already-absent key is
  therefore never an error.
- **keychain-exists-checks-current-scope**: `exists` MUST return true when
  a query under the current `service`/`accessGroup` scope locates the key.
- **keychain-exists-checks-legacy-scopes**: when the current-scope check
  fails, `exists` MUST check `legacyServices` in order and MUST return true
  if any retired service holds the key.
- **keychain-exists-does-not-migrate**: unlike `get`, `exists` MUST NOT call
  `set` when it locates a key under a legacy scope — it only reports
  presence, it never re-stores.
- **keychain-global-state-not-isolated**: `service`, `accessGroup`, and
  `legacyServices` are shared mutable global state with no concurrency
  confinement of their own; the store performs no locking around reads or
  writes of these three values, so a caller that mutates one of them from
  more than one concurrent context without external synchronization MUST
  accept the resulting data race as the type's documented behavior, not a
  defect to report.
- **keychain-get-error-ambiguity**: `get`'s optional-string return cannot
  distinguish "no secret was ever stored for this key" from "a lookup
  failed for a reason other than not-found" (for example, an
  interaction-not-allowed status while the device is locked, or a missing
  entitlement); the lookup helper logs the status in that second case, but
  `get` still returns nothing either way, so no caller can tell the two
  outcomes apart from the return value alone.

### Security

- **keychain-secret-storage-mechanism**: every value `set` writes MUST go
  into the system credential store as a generic-password item — the store
  MUST NOT write a secret to a plain settings store, a file, or any other
  unencrypted store.
- **keychain-secret-value-not-logged**: every log call inside the
  secret-storage component MUST interpolate only the account key and a
  status/error value — none MUST interpolate the secret string passed to
  `set` or returned by `get`.
- **keychain-secret-no-transmission**: the store MUST perform no networking
  of any kind — it MUST NOT transmit a stored or retrieved secret
  off-device.
- **keychain-secret-lifetime-caller-controlled**: the store MUST define no
  TTL, expiry timer, or automatic-eviction policy for a stored item — a
  secret MUST persist until a caller calls `delete` or the OS/user removes
  it independently.

### Logger factory contract

- **loggable-requirement**: the contract's sole requirement MUST be a
  type-level `logger` value, obtainable without regard to any particular
  concurrency context.
- **loggable-default-subsystem**: the default `subsystem` MUST equal the
  app's bundle identifier, or the literal string `"nil"` when none is
  available.
- **loggable-default-category**: the default `category` MUST equal the
  conforming type's own name, with any trailing type-metadata suffix
  removed.
- **loggable-instance-forwarding**: the default instance-level `logger`
  MUST forward to the type-level `logger` — an instance and its type MUST
  expose the identical logger value.
- **loggable-factory**: the factory MUST return a structured logger
  constructed from `subsystem` and `category`.
- **loggable-default-members-isolation**: only the contract's `logger`
  requirement carries an explicit concurrency-context annotation; the
  default `subsystem`, `category`, instance `logger`, and factory members
  carry no isolation annotation of their own and so inherit whatever
  isolation, if any, applies at each call site.

### Float clamping

- **float-clamped-shape**: clamping a floating-point value to a closed
  range MUST return the value unchanged when it already lies within the
  range, MUST return the range's lower bound when it is below it, and MUST
  return the range's upper bound when it is above it.
- **float-clamped-degenerate-range**: when the range's lower and upper
  bounds are equal, clamping MUST return that single value for every
  possible input.
- **float-clamped-pure**: clamping MUST have no side effects and MUST
  depend only on the input value and the range — it MUST NOT read or
  mutate any external state.

### Semantic version parsing

- **semver-shape**: a semantic version MUST be a value type holding
  `major`, `minor`, and `patch` integer components, and MUST support
  equality, hashing, ordering comparison, and a human-readable description.
- **semver-parse-forms**: parsing MUST accept a string of one, two, or
  three dot-separated numeric components (`"1"`, `"1.74"`, `"1.74.0"`),
  MUST accept an optional leading `"v"`, and MUST default any component
  missing from a short form to `0`.
- **semver-parse-rejects-invalid**: parsing MUST return nothing for a
  string carrying a prerelease suffix (`"1.74.0-rc.1"`), build metadata
  (`"1.74.0+build"`), non-numeric text (`"abc"`), the empty string, or a
  non-numeric component (`"1.x.0"`).
- **semver-component-bound**: parsing MUST return nothing when any parsed
  component exceeds 2,147,483,647 (the largest 32-bit signed integer), and
  MUST accept a component exactly equal to that ceiling.
- **semver-ordering**: ordering comparison MUST order strictly by `major`,
  then `minor`, then `patch`, as numeric integer comparisons — it MUST NOT
  compare components as strings (`"9"` MUST sort before `"10"`).
- **semver-description-round-trip**: the description MUST render as
  `"major.minor.patch"`, and parsing that description MUST equal the
  original value for every value the type can represent.

### Text folding

- **text-folding-normalization**: folding a string MUST fold both case and
  diacritics, so that two strings differing only in letter case or in
  diacritical marks MUST fold to the same result (`folded("CAFÉ") ==
  folded("cafe")`).
- **text-folding-locale-independence**: folding MUST be locale-independent
  rather than using the current locale, so its result MUST NOT vary with
  the current locale (for example, it MUST fold identically whether the
  current locale is Turkish or U.S. English).
- **text-folding-empty-input**: folding `""` MUST return `""`.
- **text-folding-pure**: folding MUST have no side effects and MUST depend
  only on its input string.

## Appearance

Not applicable: none of the six utilities in this recipe renders a view,
draws, or has any visual representation.

## States

Not applicable: none of the six utilities models UI state (loading, error,
selected, disabled, or similar) — each is a stateless pure function or a
static data-access API.

## Accessibility

Not applicable: none of the six utilities has a UI surface for an
accessibility label, trait, or focus order to attach to.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| fc-001 | encoding-skip-shape, encoding-skip-decode-yields-nothing, decode-integration-skips-key | decode `{"a": 1, "b": 2}` into a model with a plain integer field `a` and an encoding-skip-wrapped optional integer field `b` | `b`'s stored value is nothing; the `2` in the input is discarded |
| fc-002 | encoding-skip-encode-noop, encode-integration-skips-key, encoding-skip-round-trip-loses-value | encode a model with an encoding-skip-wrapped optional integer field `b` set to 42, then decode the result | encoded JSON has no `"b"` key at all; the decoded field's stored value is nothing |
| fc-003 | encoding-skip-concurrency | one wrapper instance's stored value mutated from two concurrent tasks with no external synchronization | undefined/racy result; the type provides no protection of its own (no concurrency-safety guarantee, mutable storage) |
| fc-004 | keychain-service-default | read the store's `service` in a process where no bundle identifier is available | `"com.agentictoolkit"` |
| fc-005 | keychain-set-returns-status, keychain-get-primary-lookup | `set("hello-world", forKey: key)` then `get(forKey: key)` | `set` returns `true`; `get` returns `"hello-world"` |
| fc-006 | keychain-get-exhausted-returns-nothing | `get(forKey:)` for a key never set | nothing |
| fc-007 | keychain-exists-checks-current-scope, keychain-delete-idempotent | set a key, check `exists` (`true`), `delete` it, check `exists` again (`false`), `delete` it a second time | first `exists` is `true`, second is `false`, second `delete` still returns `true` |
| fc-008 | keychain-set-overwrites | `set("first", forKey: key)`, then `set("second", forKey: key)`, then `get(forKey: key)` | `"second"` |
| fc-009 | keychain-set-returns-status | `set("", forKey: key)`, then `get(forKey: key)`, then `exists(forKey: key)` | `set` returns `true`; `get` returns `""`; `exists` returns `true` |
| fc-010 | keychain-copy-value-single-match | set a string containing multibyte Unicode and control characters, then `get` it back | the identical string, byte-for-byte |
| fc-011 | keychain-query-shape, keychain-query-access-group-forces-data-protection | build a query for account `"acct"` with access group `"ABCDE12345.example.shared"` | dictionary has `kSecAttrAccessGroup` equal to that group, `kSecUseDataProtectionKeychain` true, `kSecAttrAccount` equal to `"acct"` |
| fc-012 | keychain-query-shape | build a query for account `"acct"` with no access group | no `kSecAttrAccessGroup`/`kSecUseDataProtectionKeychain` keys present, `kSecAttrAccount` equal to `"acct"` |
| fc-013 | keychain-exists-checks-current-scope | set `keyA` and `keyB`, delete `keyA` | `get(keyA)` returns nothing; `get(keyB)` unaffected |
| fc-014 | keychain-get-access-group-migration, keychain-set-access-group-accessibility | a secret stored while the access group is nothing; the access group is then set to a group and `get(forKey:)` is called for the same key | `get` locates the item under the no-group scope, re-stores it under the new group with `kSecAttrAccessible` set to after-first-unlock-this-device-only, and returns the value (traced to source, no dedicated test) |
| fc-015 | keychain-get-legacy-service-migration, keychain-legacy-item-not-deleted | a secret stored under a service later listed in `legacyServices`; `service` now points elsewhere | `get(forKey:)` finds the value under the retired service, re-stores it under the current `service`, returns it, and leaves the original item under the retired service untouched (traced to source, no dedicated test) |
| fc-016 | keychain-exists-checks-legacy-scopes, keychain-exists-does-not-migrate | a secret present only under a retired service listed in `legacyServices` | `exists(forKey:)` returns `true` without re-storing anything under the current service (traced to source, no dedicated test) |
| fc-017 | keychain-copy-value-logs-unexpected-errors-only | `copyValue` for a key that has never existed (item-not-found status) | no error is logged (traced to source, no dedicated test) |
| fc-018 | keychain-secret-value-not-logged | review every error/info log call site in the secret-storage component's source | each interpolates only the account key and a status/message, never the secret string itself (traced to source, no dedicated test) |
| fc-019 | keychain-access-group-default, keychain-legacy-services-default | read the store's `accessGroup` and `legacyServices` before any caller assigns them | `accessGroup` is nothing; `legacyServices` is `[]` (traced to source declaration, no dedicated test) |
| fc-020 | keychain-global-state-not-isolated | thread A sets the store's `service` while thread B concurrently reads it, with no external synchronization | undefined/racy result; the store performs no locking of its own around these shared values (traced to source declaration, no dedicated test) |
| fc-021 | keychain-secret-storage-mechanism, keychain-secret-no-transmission, keychain-secret-lifetime-caller-controlled | review every code path in the secret-storage component's source | every write goes through the underlying add/update call against a generic-password item, no path constructs a network call, and no path schedules a deletion or expiry timer (traced to source, whole-file review) |
| fc-022 | semver-parse-forms | parse `"1.74.0"`, `"1.74"`, `"1"` | all equal the corresponding value with missing components defaulted to `0` |
| fc-023 | semver-parse-forms | parse `"v1.74.0"` | equals major 1, minor 74, patch 0 |
| fc-024 | semver-parse-rejects-invalid | parse `"1.74.0-rc.1"`, `"1.74.0+build"`, `"abc"`, `""`, `"1.x.0"` | nothing for every input |
| fc-025 | semver-component-bound | parse a string with a component equal to the largest 64-bit integer (in the major, then minor, then patch position), `"2147483648"`, and `"v2147483648.0.0"` | nothing for every input |
| fc-026 | semver-component-bound | parse `"2147483647.2147483647.2147483647"` vs. `"2147483648"` | the first equals major 2147483647, minor 2147483647, patch 2147483647; the second is nothing |
| fc-027 | semver-ordering | four ordering comparisons across `major`/`minor`/`patch`, including `minor: 9` vs. `minor: 10` | numeric ordering holds throughout; the `9`/`10` pair does not sort as strings would |
| fc-028 | semver-shape, semver-description-round-trip | describe `"1.74.2"`, then re-parse that description | description equals `"1.74.2"`; re-parsing it equals the original value |
| fc-029 | text-folding-normalization | fold `"CAFÉ"` vs. fold `"cafe"` | equal |
| fc-030 | text-folding-empty-input, text-folding-pure | fold `""` | `""` |
| fc-031 | text-folding-locale-independence | fold `"İstanbul"` evaluated with the current locale set to Turkish (`tr`) and separately to U.S. English (`en_US`) | identical result in both cases, because folding is explicitly locale-independent rather than using the current locale (traced to source, no dedicated test) |
| fc-032 | float-clamped-shape, float-clamped-pure | clamp `5`, `-3`, `42`, `0`, `10` to the range `0...10` | `5`, `0`, `10`, `0`, `10` respectively |
| fc-033 | float-clamped-degenerate-range | clamp `-100`, `100`, `5` to the range `5...5` | `5` in every case |
| fc-034 | float-clamped-shape | clamp `-100`, `100`, `-7` to the range `-10...-5` | `-10`, `-5`, `-7` respectively |
| fc-035 | loggable-requirement, loggable-default-subsystem, loggable-default-category, loggable-factory | a type `Foo` conforms to the logger factory contract via a single factory-backed static logger property, running in a process where the bundle identifier is `"com.example.app"` | `Foo`'s logger's subsystem is `"com.example.app"`; its category is `"Foo"` (traced to source, no dedicated test) |
| fc-036 | loggable-instance-forwarding | an instance's `logger` on a type conforming to the logger factory contract | identical to the type-level value (traced to source, no dedicated test) |
| fc-037 | loggable-default-members-isolation | inspect the declarations of `subsystem`, `category`, the instance `logger`, and the factory method in the contract's default implementations | none carries its own explicit isolation annotation; only the contract's `logger` requirement declares one (traced to source, no dedicated test) |

## Edge Cases

- **Empty string as a stored secret**: `set("", forKey:)` MUST succeed, and
  a subsequent `get(forKey:)` MUST return `""`, not nothing — an empty
  string is a valid, distinct value from "absent."
- **Empty string as a version or a fold target**: parsing `""` as a version
  MUST return nothing (empty is not a valid version), while folding `""`
  MUST return `""` (empty is a valid, if trivial, fold result) — the two
  MUST NOT be conflated.
- **Version component at the arithmetic ceiling**: a component equal to the
  32-bit signed integer ceiling (2,147,483,647) MUST parse; a component one
  greater MUST NOT — the boundary is exact, not approximate.
- **Degenerate clamp range**: clamping with equal lower and upper bounds
  MUST collapse every input to that single value, never trap or produce an
  unrelated result.
- **Concurrent mutation of the secret store's global state**: `service`,
  `accessGroup`, and `legacyServices` are shared mutable state with no
  concurrency confinement of their own; concurrent mutation from more than
  one execution context without external synchronization is a documented
  data race, not a crash the type guards against.
- **Concurrent mutation of a shared encoding-skip wrapper instance**: the
  wrapper provides no concurrency-safety guarantee; sharing one instance's
  mutable stored value across concurrent contexts without synchronization
  is the caller's responsibility, not something the wrapper prevents.
- **Credential-store lookup failure that is not "not found"**: the lookup
  helper logs any status other than success and item-not-found, but `get`
  still returns nothing for that case exactly as it does for a genuine
  absence — see `keychain-get-error-ambiguity` above.
- **Secret recovered from a legacy or access-group scope**: `get` re-stores
  the recovered value under the current scope but MUST NOT delete the
  original — a second install still pointed at the old scope MUST continue
  to find its copy.
- **Unicode and control characters in a stored secret**: the secret store
  MUST round-trip a value containing multibyte Unicode, emoji, and control
  characters (newline, tab) exactly, since `set`/`get` encode/decode as raw
  UTF-8 text with no transformation.
- **Offline or disconnected operation**: not applicable — none of the six
  utilities performs networking, so there is no offline/disconnected state
  to define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `service` (of the secret store) | string (mutable, shared) | app's bundle identifier, or `"com.agentictoolkit"` when none is available | Credential-store service identifier that scopes every query, set, and delete. |
| `accessGroup` (of the secret store) | optional string (mutable, shared) | nothing | Optional shared credential-store access group; when set, forces data-protection-keychain semantics and after-first-unlock-this-device-only accessibility on new writes. |
| `legacyServices` (of the secret store) | list of strings (mutable, shared) | empty list | Retired service identifiers `get`/`exists` fall back to, newest-retired-first, for migrating secrets forward. |
| the semantic-version component ceiling | integer constant | `2,147,483,647` | Fixed plausibility bound on `major`/`minor`/`patch`; not caller-configurable. |

The encoding-skip wrapper, the logger factory contract, float clamping, and
text folding take no static or environment configuration — every input
they act on is a per-call argument.

## Deep Linking

Not applicable: none of the six utilities defines a URL scheme, a route, or
any other navigable destination.

## Localization

Not applicable: none of the six utilities constructs a user-facing string.
The secret store's and the logger factory contract's only string output is
diagnostic log text (see Logging below), never text displayed to a user;
semantic-version parsing and text folding operate on caller-supplied data,
not on any string this recipe itself presents to a user.

## Accessibility Options

Not applicable: none of the six utilities has a visual or interactive
surface for a system accessibility display option to affect.

## Feature Flags

Not applicable: none of the six utilities checks a feature flag, a build
configuration, or a remote-config value.

## Analytics

Not applicable: none of the six utilities emits an analytics or telemetry
event.

## Privacy

The secret store is the one utility in this recipe that handles sensitive
data; the other five collect, store, and transmit nothing.

- **Data handled**: the secret string values a caller passes to `set` —
  arbitrary caller-supplied text such as an API key or credential. The
  store never inspects, parses, or transforms the value itself.
- **Storage**: the system's credential store, scoped by `service` and
  optionally `accessGroup`. An access-group item is additionally marked
  accessible only after the device's first unlock, and never synced
  off-device.
- **Transmission**: none. The store performs no networking; a caller that
  later transmits a retrieved secret does so outside this component's
  boundary.
- **Retention**: indefinite. A stored item persists until a caller calls
  `delete` or the OS/user removes it independently — the store defines no
  TTL or automatic expiry (see `keychain-secret-lifetime-caller-controlled`
  above).

## Logging

The secret store conforms to the logger factory contract. Subsystem: the
app's bundle identifier — Category: the store's own type name.

| Event | Level | Message shape |
|-------|-------|----------------|
| the underlying add/update call did not report success in `set` | error | interpolates the account key and the resulting status |
| the underlying lookup call reported a status other than success or item-not-found in `copyValue` | error | interpolates the account key and the resulting status |
| a secret was recovered from a legacy access-group scope or a retired service and re-stored under the current scope | info | interpolates the account key and the scope it was recovered from |

No log call in the secret store interpolates the secret value itself (see
`keychain-secret-value-not-logged` above). The other five utilities in this
recipe produce no log output at all; the logger factory contract only
provides the factory the secret store and other conforming types build
their logger from.

## Platform Notes

- **SwiftUI (source platform)**: all six files (`CodableIgnored.swift`,
  `KeychainHelper.swift`, `Loggable.swift`, `MathUtils.swift`,
  `SemanticVersion.swift`, `TextFolding.swift`) depend only on `Foundation`,
  `Security`, and `os` (`OSLog`) — none imports `SwiftUI`, so they are
  usable unchanged from any SwiftUI view model or view.
- **Compose (Kotlin/Android)**: `CodableIgnored` maps to a `kotlinx
  .serialization` field marked `@Transient` (or a custom `SerialDescriptor`
  override) so the field never serializes and always deserializes to its
  default. `KeychainHelper` maps to Android Keystore-backed
  `EncryptedSharedPreferences`, keyed the same way `service`/`account`
  scope a Keychain query. `Loggable` maps to a `Timber` tree, or plain
  `android.util.Log`, tagged with the conforming class's simple name.
  `clamped(to:)` maps directly to Kotlin's `coerceIn(range)`.
  `SemanticVersion` maps to a small `data class` with a hand-written parser
  (matching this type's short-form leniency, since a general semver
  library would reject `"1.74"`), guarded by the same `Int.MAX_VALUE`-scale
  bound. `TextFolding` maps to Java/Kotlin's `java.text.Normalizer`
  (`NFD`) with combining marks stripped, followed by
  `.lowercase(Locale.ROOT)` to keep the fold locale-independent.
- **React/Web**: `CodableIgnored` maps to a `class-transformer`
  `@Exclude()` decorator, or simply omitting the field from both the
  serializer and the deserializer's output type. `KeychainHelper` has no
  direct browser analog — there is no OS keychain in a browser sandbox; a
  Node.js backend's closest equivalent is a native keytar-style module
  wrapping the host OS's credential store. `Loggable` maps to a per-module
  logger factory (for example `pino().child({ category: name })`) keyed by
  module or class name. `clamped(to:)` maps to `Math.min(Math.max(value,
  lower), upper)` — JavaScript has no built-in clamp. `SemanticVersion`
  should still be hand-parsed rather than delegated to the npm `semver`
  package, to preserve this type's short-form leniency and its explicit
  `Number.MAX_SAFE_INTEGER`-scale bound check, since JavaScript numbers do
  not trap on overflow the way `Int` arithmetic does. `TextFolding` maps to
  `string.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()`,
  with no locale argument, matching this type's `locale: nil`.
- **AppKit/UIKit**: identical to the SwiftUI note — none of the six files
  imports `AppKit` or `UIKit`, so an AppKit- or UIKit-hosted app consumes
  the same `AgenticToolkitCore` types unchanged. One platform-specific
  nuance carries forward regardless of UI framework: `KeychainHelper`'s
  `kSecUseDataProtectionKeychain` flag (set only when `accessGroup` is
  non-nil) is required for access-group Keychain sharing on macOS
  specifically, per the type's own source comment.
- **WinUI 3**: the reason this recipe exists — none of these six types has
  a direct Windows App SDK equivalent, so each needs a concrete port.
  `CodableIgnored` maps to `System.Text.Json`'s `[JsonIgnore]` attribute
  directly (the BCL already provides this exact "never encode, always
  null/default on decode" contract — no wrapper type is needed).
  `KeychainHelper` maps to `Windows.Security.Credentials.PasswordVault`
  (`PasswordCredential`), resourced by the same string `service` scopes a
  Keychain query with; Windows has no access-group concept, so the
  access-group migration path (`accessGroup`, and the migration branch of
  `get(forKey:)`) has no analog and should be dropped, while the
  `legacyServices` migration path still applies (a `PasswordVault` resource
  rename). `Loggable` maps to `Microsoft.Extensions.Logging`'s
  `ILogger<T>`, resolved per type the same way `makeLogger()` derives a
  category from the conforming type's own name. `clamped(to:)` maps
  directly to .NET's `Math.Clamp(value, min, max)` — no port needed.
  `SemanticVersion` maps to a `readonly struct` with `int major`, `int
  minor`, `int patch` implementing `IComparable`, guarding each parsed
  component against `int.MaxValue` explicitly, mirroring
  `SemanticVersion.maximumComponent`. `TextFolding` maps to `string
  .Normalize(NormalizationForm.FormD)` with combining marks stripped by
  Unicode category, followed by `ToUpperInvariant()`/`ToLowerInvariant()`
  (never the current-culture `ToLower()`) to preserve `locale: nil`'s
  locale independence. `Task`, `HttpClient`, and `Windows.Storage` have no
  role in any of the six ports: every operation here is synchronous, with
  at most one credential-vault round trip.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/CodableIgnored.swift` |
| apple | `packages/apple/AgenticToolkit/Core/KeychainHelper.swift` |
| apple | `packages/apple/AgenticToolkit/Core/Loggable.swift` |
| apple | `packages/apple/AgenticToolkit/Core/MathUtils.swift` |
| apple | `packages/apple/AgenticToolkit/Core/SemanticVersion.swift` |
| apple | `packages/apple/AgenticToolkit/Core/TextFolding.swift` |

## Design Decisions

- **Decision**: `get(forKey:)` re-stores a secret recovered from a legacy
  access-group scope or a retired service, but never deletes the original
  copy.
  **Rationale**: `KeychainHelper.swift`'s own doc comment states this
  directly — another install may still be reading the old item, and "a
  secret is not something to destroy on a guess."
  **Approved**: pending

- **Decision**: `SemanticVersion` rejects any component greater than
  `Int32.max` rather than accepting arbitrarily large numeric strings.
  **Rationale**: the source's doc comment explains that a version
  component is arithmetic, not just a label — `VSCodeEngineRange` computes
  a caret ceiling as `major + 1`, a trapping `Int` operation, and the guard
  is placed here so every consumer inherits it rather than each caller
  re-deriving its own bound.
  **Approved**: pending

- **Decision**: `SemanticVersion` parses only `major.minor.patch`, with no
  prerelease or build-metadata precedence.
  **Rationale**: the source's doc comment states that nothing in this
  toolkit currently needs prerelease/build-metadata comparison, and "half
  a precedence table is worse than an honest nil."
  **Approved**: pending

- **Decision**: `TextFolding.folded(_:)` passes `locale: nil` to `String
  .folding(options:locale:)` rather than `Locale.current`.
  **Rationale**: the source's doc comment cites the Turkish dotless-i
  problem — a case fold under `Locale.current` can vary by the user's
  system locale, which is wrong for matching against identifiers or titles
  that are not themselves localized.
  **Approved**: pending

- **Decision**: `KeychainHelper` marks access-group items
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than a
  synchronizable accessibility class.
  **Rationale**: the source's doc comment explains a daemon consuming a
  shared access-group item may run before the user's first unlock of a
  session, and `ThisDeviceOnly` avoids iCloud Keychain sync/migration for
  material that should stay pinned to one device.
  **Approved**: pending

- **Decision**: `CodableIgnored`'s `encode(to:)` is a true no-op — the key
  is omitted from output entirely, rather than being written as `null`.
  **Rationale**: the source's inline comments state this directly: the
  key must never appear in encoded output, and decoding intentionally
  discards whatever was present, so an ignored field's contract is
  "invisible," not "present but nulled."
  **Approved**: pending

- **Decision**: `Loggable.swift` retains a large `#if false` block of
  authoring notes and usage examples after its real declarations.
  **Rationale**: this is a documented fact about the file's actual
  contents, not a convention to imitate — the block never compiles and has
  zero runtime effect; it is preserved here for source fidelity rather than
  silently dropped or treated as executable guidance.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |

`separation-of-concerns` passes because each of the six files owns exactly
one concern (Codable-field exclusion, Keychain access, logger
construction, a math clamp, version parsing, text folding) with no
cross-file coupling — none imports another file in this recipe.

`unit-test-coverage` is `partial`: `KeychainHelper`, `SemanticVersion`,
`TextFolding`, and `MathUtils`'s `CGFloat.clamped(to:)` each have a
dedicated test file with meaningful assertions (`KeychainHelperTests
.swift`, `SemanticVersionTests.swift`, `TextFoldingTests.swift`,
`CGFloatClampedTests.swift`), but `CodableIgnored` and `Loggable` have no
test file anywhere in the repository.

`explicit-error-handling` passes because every fallible operation reports
its outcome through its return value — `KeychainHelper.set`/`.delete`
return `Bool`, `.get` returns `String?`, `SemanticVersion.init?` returns an
optional — none swallows a failure silently without any signal reaching
the caller (see `keychain-get-error-ambiguity` above for the one place
that signal is coarser than it could be).

`secure-storage` passes because `KeychainHelper` is the only file in this
recipe that stores sensitive material, and it stores it exclusively as
macOS Keychain generic-password items via `SecItemAdd`/`SecItemUpdate` —
never in `UserDefaults`, a file, or any other unencrypted location.

`secure-log-output` passes because every log call site in
`KeychainHelper.swift` interpolates only the account key and a status or
scope, never the secret string itself.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | | Initial recipe covering `CodableIgnored`, `KeychainHelper`, `Loggable`, `MathUtils` (`CGFloat.clamped(to:)`), `SemanticVersion`, and `TextFolding`. |
