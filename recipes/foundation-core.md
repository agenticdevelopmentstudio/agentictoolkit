---
id: cf3a3dc9-6fed-47ba-a699-71ff806dcedd
title: Foundation Core
domain: agentictoolkit://recipes/foundation-core
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Six foundation-tier utilities: Keychain secret storage, a Codable-skip wrapper,
  an OSLog factory, CGFloat clamping, semver parsing, and text folding.'
platforms:
- swift
- macos
tags:
- keychain
- credential-storage
- secrets
- semantic-versioning
- logging
- text-normalization
- codable
- value-types
depends-on: []
related:
- agentictoolkit://recipes/ai-plugin-runtime-ai-plugin-kit-secret-storing
- agentictoolkit://recipes/extension-host-core-extensions-vs-code-engine-range
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

# Foundation Core

## Overview

`foundation-core` covers six top-level files in `AgenticToolkitCore`'s `Core/`
directory. Each file has no dependency on anything else in this recipe or on
any other part of the package; together they form the lowest tier of the
toolkit — the tier every other logic and UI component in `AgenticToolkitCore`
is built on top of.

- **`CodableIgnored`** — a property wrapper that removes a field from
  `Codable` encoding and decoding entirely, so a value can exist on a model
  without ever appearing in its JSON representation.
- **`KeychainHelper`** — a static, namespace-style API over macOS Keychain
  generic-password items, with built-in migration across a configurable
  access group and a list of retired service identifiers. Consumed directly
  by `KeychainSecureSettingsStorageProvider` and by the AI Plugin Kit's
  secret-storing component.
- **`Loggable`** — a protocol that gives any conforming type a
  `Logger` derived from the app's bundle identifier and the type's own name,
  with no boilerplate at each call site beyond a single `static nonisolated
  let logger = makeLogger()` line.
- **`MathUtils`** — a single `CGFloat.clamped(to:)` extension method; pure
  arithmetic, no state.
- **`SemanticVersion`** — a `major.minor.patch` parser and comparable value
  type with an explicit upper bound on each component, guarding arithmetic
  callers (such as `VSCodeEngineRange`'s caret-range ceiling) against
  `Int` overflow traps.
- **`TextFolding`** — a single `String` case-and-diacritic folding helper for
  locale-independent text matching, used by `CommandPaletteModel` and
  `ExtensionQuickPickModel`.

None of the six files import `SwiftUI`, `AppKit`, or `UIKit`; none renders
anything, holds view state, or performs networking.

## Behavioral Requirements

### CodableIgnored

- **codable-ignored-shape**: `CodableIgnored<T>` MUST be declared as
  `@propertyWrapper public struct CodableIgnored<T>` with a single mutable
  `public var wrappedValue: T?`, and MUST provide `public init(wrappedValue:
  T?)`.
- **codable-ignored-decode-yields-nil**: `CodableIgnored<T>`'s
  `Decodable` conformance MUST initialize `wrappedValue` to `nil`
  unconditionally, regardless of whether the corresponding key is present or
  absent in the decoded input.
- **codable-ignored-encode-noop**: `CodableIgnored<T>`'s `Encodable`
  conformance's `encode(to:)` MUST be a no-op — it MUST NOT write anything
  to the given encoder.
- **keyed-decoding-container-ignored-decode**: the
  `KeyedDecodingContainer` extension's `decode(_:forKey:)` overload
  specialized for `CodableIgnored<T>` MUST return `CodableIgnored(wrappedValue:
  nil)` without attempting to read the container at `key` at all.
- **keyed-encoding-container-ignored-encode**: the
  `KeyedEncodingContainer` extension's `encode(_:forKey:)` overload
  specialized for `CodableIgnored<T>` MUST return without calling
  `encodeNil`, `encode`, or any other container-mutating method — the key
  MUST NOT appear in the encoded output at all.
- **codable-ignored-round-trip-loses-value**: encoding a model whose
  `@CodableIgnored` property holds a non-nil value and then decoding the
  result back MUST yield `wrappedValue == nil` on the decoded copy — the
  original value MUST NOT survive an encode/decode round trip.
- **codable-ignored-concurrency**: `CodableIgnored<T>` MUST NOT declare
  `Sendable` conformance; its `wrappedValue` is a mutable `var`, so a caller
  sharing one instance across concurrency domains MUST supply its own
  synchronization.

### KeychainHelper

- **keychain-service-default**: `KeychainHelper.service` MUST default to
  `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` and MUST be
  reassignable by a caller at any time (`nonisolated(unsafe) public static
  var service`).
- **keychain-access-group-default**: `KeychainHelper.accessGroup` MUST
  default to `nil` (`nonisolated(unsafe) public static var accessGroup:
  String?`).
- **keychain-legacy-services-default**: `KeychainHelper.legacyServices`
  MUST default to `[]` (`nonisolated(unsafe) public static var
  legacyServices: [String]`), ordered newest-retired-first.
- **keychain-query-shape**: `makeQuery(account:accessGroup:)` MUST return a
  dictionary with `kSecClass == kSecClassGenericPassword`, `kSecAttrService
  == KeychainHelper.service`, and `kSecAttrAccount == account`.
- **keychain-query-access-group-forces-data-protection**: when
  `makeQuery(account:accessGroup:)` is called with a non-nil `accessGroup`,
  the returned dictionary MUST additionally include `kSecAttrAccessGroup ==
  accessGroup` and `kSecUseDataProtectionKeychain == true`; when
  `accessGroup` is `nil`, neither key MUST be present.
- **keychain-set-overwrites**: `set(_:forKey:)` calling `SecItemAdd` and
  receiving `errSecDuplicateItem` MUST fall back to `SecItemUpdate` for the
  same query, so a second `set` call for the same key MUST overwrite the
  first value rather than fail.
- **keychain-set-access-group-accessibility**: when `KeychainHelper
  .accessGroup` is non-nil at the time `set(_:forKey:)` runs, the item's
  `kSecAttrAccessible` attribute MUST be set to
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **keychain-set-returns-status**: `set(_:forKey:)` MUST return `true` only
  when the underlying `SecItemAdd`/`SecItemUpdate` call reports
  `errSecSuccess`, and MUST return `false` for any other status.
- **keychain-get-primary-lookup**: `get(forKey:)` MUST first query under the
  current `service`/`accessGroup` scope and MUST return the stored string
  directly when that query succeeds.
- **keychain-get-access-group-migration**: when the primary lookup fails
  and `KeychainHelper.accessGroup` is non-nil, `get(forKey:)` MUST retry the
  query with `accessGroup: nil`; on success it MUST re-store the recovered
  value under the current `service`/`accessGroup` scope via `set(_:forKey:)`
  before returning it.
- **keychain-get-legacy-service-migration**: when the access-group retry
  also fails (or does not apply), `get(forKey:)` MUST iterate
  `KeychainHelper.legacyServices` in order and, for the first retired
  service under which the key is found, MUST re-store the recovered value
  under the current `service` before returning it.
- **keychain-get-exhausted-returns-nil**: when the primary lookup, the
  access-group retry, and every entry in `legacyServices` all fail to
  locate the key, `get(forKey:)` MUST return `nil`.
- **keychain-legacy-item-not-deleted**: when `get(forKey:)` recovers a
  value from a legacy access-group scope or a retired service, it MUST NOT
  delete the original item under that legacy scope — only a new copy is
  written under the current scope.
- **keychain-copy-value-single-match**: `copyValue(query:)` MUST set
  `kSecMatchLimit` to `kSecMatchLimitOne` and `kSecReturnData` to `true`, and
  MUST decode the returned `Data` as UTF-8 into the `String` it returns.
- **keychain-copy-value-logs-unexpected-errors-only**: `copyValue(query:)`
  MUST log an error via `Loggable`'s logger when `SecItemCopyMatching`
  returns a status other than `errSecSuccess` and other than
  `errSecItemNotFound`; it MUST NOT log anything when the status is
  `errSecItemNotFound`.
- **keychain-delete-idempotent**: `delete(forKey:)` MUST return `true` when
  the underlying `SecItemDelete` reports `errSecSuccess` or
  `errSecItemNotFound`, and MUST return `false` for any other status —
  deleting an already-absent key is therefore never an error.
- **keychain-exists-checks-current-scope**: `exists(forKey:)` MUST return
  `true` when a query under the current `service`/`accessGroup` scope
  locates the key.
- **keychain-exists-checks-legacy-scopes**: when the current-scope check
  fails, `exists(forKey:)` MUST check `KeychainHelper.legacyServices` in
  order and MUST return `true` if any retired service holds the key.
- **keychain-exists-does-not-migrate**: unlike `get(forKey:)`,
  `exists(forKey:)` MUST NOT call `set(_:forKey:)` when it locates a key
  under a legacy scope — it only reports presence, it never re-stores.
- **keychain-global-state-not-isolated**: `service`, `accessGroup`, and
  `legacyServices` are declared `nonisolated(unsafe)`; `KeychainHelper`
  itself performs no locking around reads or writes of these three statics,
  so a caller that mutates one of them from more than one concurrency
  domain without external synchronization MUST accept the resulting data
  race as the type's documented behavior, not a defect to report.
- **keychain-get-error-ambiguity**: `get(forKey:)`'s `String?` return cannot distinguish "no secret was ever stored for this key" from "a Keychain query failed for a reason other than not-found" (for example `errSecInteractionNotAllowed` while the device is locked, or a missing entitlement); `copyValue` logs the status in that second case, but `get` still returns `nil` either way, so no caller can tell the two outcomes apart from the return value alone.

### Security

- **keychain-secret-storage-mechanism**: every value `KeychainHelper.set`
  writes MUST go into a macOS Keychain generic-password item via
  `SecItemAdd`/`SecItemUpdate` — `KeychainHelper` MUST NOT write a secret to
  `UserDefaults`, a file, or any other unencrypted store.
- **keychain-secret-value-not-logged**: every `Loggable` log call inside
  `KeychainHelper.swift` MUST interpolate only the account `key` and a
  status/error value — none MUST interpolate the secret string passed to
  `set(_:forKey:)` or returned by `get(forKey:)`.
- **keychain-secret-no-transmission**: `KeychainHelper` MUST perform no
  networking of any kind — it MUST NOT transmit a stored or retrieved
  secret off-device.
- **keychain-secret-lifetime-caller-controlled**: `KeychainHelper` MUST
  define no TTL, expiry timer, or automatic-eviction policy for a stored
  item — a secret MUST persist until a caller calls `delete(forKey:)` or
  the OS/user removes it independently.

### Loggable

- **loggable-requirement**: `Loggable`'s sole protocol requirement MUST be
  `static nonisolated var logger: Logger { get }`.
- **loggable-default-subsystem**: the default `subsystem` extension member
  MUST equal `Bundle.main.bundleIdentifier ?? "nil"`.
- **loggable-default-category**: the default `category` extension member
  MUST equal `"\(type(of: self))"` with the substring `".Type"` removed via
  `replacingOccurrences(of:with:)`.
- **loggable-instance-forwarding**: the default instance-level `logger`
  extension member MUST forward to `Self.logger` — an instance and its type
  MUST expose the identical `Logger` value.
- **loggable-factory**: `makeLogger()` MUST return `Logger(subsystem:
  self.subsystem, category: self.category)`.
- **loggable-default-members-isolation**: only the protocol's `logger`
  requirement carries an explicit `nonisolated` annotation; the default
  `subsystem`, `category`, instance `logger`, and `makeLogger()` extension
  members carry no isolation annotation of their own and so inherit
  whatever global-actor isolation, if any, applies at each call site.

### MathUtils

- **cgfloat-clamped-shape**: `CGFloat.clamped(to range: ClosedRange<CGFloat>)
  -> CGFloat` MUST return `self` unchanged when `self` already lies within
  `range`, MUST return `range.lowerBound` when `self` is below it, and MUST
  return `range.upperBound` when `self` is above it.
- **cgfloat-clamped-degenerate-range**: when `range.lowerBound ==
  range.upperBound`, `clamped(to:)` MUST return that single value for every
  possible `self`.
- **cgfloat-clamped-pure**: `clamped(to:)` MUST have no side effects and
  MUST depend only on `self` and `range` — it MUST NOT read or mutate any
  external state.

### SemanticVersion

- **semver-shape**: `SemanticVersion` MUST be a value type with `let major:
  Int`, `let minor: Int`, `let patch: Int`, and MUST conform to `Sendable`,
  `Hashable`, `Comparable`, and `CustomStringConvertible`.
- **semver-parse-forms**: `SemanticVersion.init?(_ string: String)` MUST
  accept a string of one, two, or three dot-separated numeric components
  (`"1"`, `"1.74"`, `"1.74.0"`), MUST accept an optional leading `"v"`, and
  MUST default any component missing from a short form to `0`.
- **semver-parse-rejects-invalid**: `init?(_:)` MUST return `nil` for a
  string carrying a prerelease suffix (`"1.74.0-rc.1"`), build metadata
  (`"1.74.0+build"`), non-numeric text (`"abc"`), the empty string, or a
  non-numeric component (`"1.x.0"`).
- **semver-component-bound**: `init?(_:)` MUST return `nil` when any parsed
  component exceeds `Int32.max` (`2_147_483_647`), and MUST accept a
  component exactly equal to `Int32.max`.
- **semver-ordering**: `SemanticVersion`'s `Comparable` conformance MUST
  order strictly by `major`, then `minor`, then `patch`, as numeric integer
  comparisons — it MUST NOT compare components as strings (`"9"` MUST sort
  before `"10"`).
- **semver-description-round-trip**: `description` MUST render as
  `"\(major).\(minor).\(patch)"`, and `SemanticVersion(description)` MUST
  equal the original value for every value the type can represent.

### TextFolding

- **text-folding-normalization**: `TextFolding.folded(_ string: String) ->
  String` MUST fold both case and diacritics, so that two strings differing
  only in letter case or in diacritical marks MUST fold to the same result
  (`folded("CAFÉ") == folded("cafe")`).
- **text-folding-locale-independence**: `folded(_:)` MUST call `String
  .folding(options:locale:)` with `locale: nil` rather than
  `Locale.current`, so its result MUST NOT vary with the current locale
  (for example, it MUST fold identically whether the current locale is
  Turkish or U.S. English).
- **text-folding-empty-input**: `folded("")` MUST return `""`.
- **text-folding-pure**: `folded(_:)` MUST have no side effects and MUST
  depend only on its input string.

## Appearance

Not applicable: none of the six types in this recipe renders a view, draws,
or has any visual representation.

## States

Not applicable: none of the six types models UI state (loading, error,
selected, disabled, or similar) — each is a stateless pure function or a
static data-access API.

## Accessibility

Not applicable: none of the six types has a UI surface for an accessibility
label, trait, or focus order to attach to.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| fc-001 | codable-ignored-shape, codable-ignored-decode-yields-nil, keyed-decoding-container-ignored-decode | decode `{"a": 1, "b": 2}` into a model with a plain `a: Int` and `@CodableIgnored var b: Int?` | `b.wrappedValue == nil`; the `2` in the input is discarded |
| fc-002 | codable-ignored-encode-noop, keyed-encoding-container-ignored-encode, codable-ignored-round-trip-loses-value | encode a model with `@CodableIgnored var b: Int? = 42`, then decode the result | encoded JSON has no `"b"` key at all; decoded `b.wrappedValue == nil` |
| fc-003 | codable-ignored-concurrency | one `CodableIgnored<Int>` instance's `wrappedValue` mutated from two concurrent tasks with no external synchronization | undefined/racy result; the type provides no protection of its own (no `Sendable`, mutable `var`) |
| fc-004 | keychain-service-default | read `KeychainHelper.service` in a process where `Bundle.main.bundleIdentifier == nil` | `"com.agentictoolkit"` |
| fc-005 | keychain-set-returns-status, keychain-get-primary-lookup | `set("hello-world", forKey: key)` then `get(forKey: key)` | `set` returns `true`; `get` returns `"hello-world"` (`KeychainHelperTests.setGetRoundTrip`) |
| fc-006 | keychain-get-exhausted-returns-nil | `get(forKey:)` for a key never set | `nil` (`KeychainHelperTests.getMissing`) |
| fc-007 | keychain-exists-checks-current-scope, keychain-delete-idempotent | set a key, check `exists` (`true`), `delete` it, check `exists` again (`false`), `delete` it a second time | first `exists` is `true`, second is `false`, second `delete` still returns `true` (`KeychainHelperTests.existsLifecycle`, `.deleteMissingReturnsTrue`) |
| fc-008 | keychain-set-overwrites | `set("first", forKey: key)`, then `set("second", forKey: key)`, then `get(forKey: key)` | `"second"` (`KeychainHelperTests.setOverwrites`) |
| fc-009 | keychain-set-returns-status | `set("", forKey: key)`, then `get(forKey: key)`, then `exists(forKey: key)` | `set` returns `true`; `get` returns `""`; `exists` returns `true` (`KeychainHelperTests.emptyStringRoundTrip`) |
| fc-010 | keychain-copy-value-single-match | `set` a string containing multibyte Unicode and control characters, then `get` it back | the identical string, byte-for-byte (`KeychainHelperTests.unicodeRoundTrip`) |
| fc-011 | keychain-query-shape, keychain-query-access-group-forces-data-protection | `makeQuery(account: "acct", accessGroup: "ABCDE12345.example.shared")` | dictionary has `kSecAttrAccessGroup` equal to that group, `kSecUseDataProtectionKeychain == true`, `kSecAttrAccount == "acct"` (`KeychainHelperTests.queryWithAccessGroup`) |
| fc-012 | keychain-query-shape | `makeQuery(account: "acct", accessGroup: nil)` | no `kSecAttrAccessGroup`/`kSecUseDataProtectionKeychain` keys present, `kSecAttrAccount == "acct"` (`KeychainHelperTests.queryWithoutAccessGroup`) |
| fc-013 | keychain-exists-checks-current-scope | set `keyA` and `keyB`, delete `keyA` | `get(keyA) == nil`; `get(keyB)` unaffected (`KeychainHelperTests.keyIsolation`) |
| fc-014 | keychain-get-access-group-migration, keychain-set-access-group-accessibility | a secret stored while `accessGroup == nil`; `accessGroup` is then set to a group and `get(forKey:)` is called for the same key | `get` locates the item under the no-group scope, re-stores it under the new group with `kSecAttrAccessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and returns the value (traced to source, no dedicated test) |
| fc-015 | keychain-get-legacy-service-migration, keychain-legacy-item-not-deleted | a secret stored under a service later listed in `legacyServices`; `service` now points elsewhere | `get(forKey:)` finds the value under the retired service, re-stores it under the current `service`, returns it, and leaves the original item under the retired service untouched (traced to source, no dedicated test) |
| fc-016 | keychain-exists-checks-legacy-scopes, keychain-exists-does-not-migrate | a secret present only under a retired service listed in `legacyServices` | `exists(forKey:)` returns `true` without re-storing anything under the current service (traced to source, no dedicated test) |
| fc-017 | keychain-copy-value-logs-unexpected-errors-only | `copyValue` for a key that has never existed (`errSecItemNotFound`) | no error is logged (traced to source, no dedicated test) |
| fc-018 | keychain-secret-value-not-logged | review every `logger.error`/`logger.info` call site in `KeychainHelper.swift` | each interpolates only the account `key` and a status/message, never the secret string itself (traced to source, no dedicated test) |
| fc-019 | keychain-access-group-default, keychain-legacy-services-default | read `KeychainHelper.accessGroup` and `.legacyServices` before any caller assigns them | `accessGroup == nil`; `legacyServices == []` (traced to source declaration, no dedicated test) |
| fc-020 | keychain-global-state-not-isolated | thread A sets `KeychainHelper.service` while thread B concurrently reads it, with no external synchronization | undefined/racy result; `KeychainHelper` performs no locking of its own around these `nonisolated(unsafe)` statics (traced to source declaration, no dedicated test) |
| fc-021 | keychain-secret-storage-mechanism, keychain-secret-no-transmission, keychain-secret-lifetime-caller-controlled | review every code path in `KeychainHelper.swift` | every write goes through `SecItemAdd`/`SecItemUpdate` against a generic-password item, no path constructs a network call, and no path schedules a deletion or expiry timer (traced to source, whole-file review) |
| fc-022 | semver-parse-forms | `SemanticVersion("1.74.0")`, `SemanticVersion("1.74")`, `SemanticVersion("1")` | all equal the corresponding `SemanticVersion(major:minor:patch:)` with missing components defaulted to `0` (`SemanticVersionTests.parsesShortForms`) |
| fc-023 | semver-parse-forms | `SemanticVersion("v1.74.0")` | `== SemanticVersion(major: 1, minor: 74, patch: 0)` (`SemanticVersionTests.parsesLeadingV`) |
| fc-024 | semver-parse-rejects-invalid | `SemanticVersion(_:)` for `"1.74.0-rc.1"`, `"1.74.0+build"`, `"abc"`, `""`, `"1.x.0"` | `nil` for every input (`SemanticVersionTests.rejectsInvalid`) |
| fc-025 | semver-component-bound | `SemanticVersion(_:)` for `"\(Int.max)"`, `"1.\(Int.max)"`, `"1.74.\(Int.max)"`, `"2147483648"`, `"v2147483648.0.0"` | `nil` for every input (`SemanticVersionTests.rejectsImplausiblyLargeComponents`) |
| fc-026 | semver-component-bound | `SemanticVersion("2147483647.2147483647.2147483647")` vs. `SemanticVersion("2147483648")` | the first equals `SemanticVersion(major: 2147483647, minor: 2147483647, patch: 2147483647)`; the second is `nil` (`SemanticVersionTests.acceptsTheCeilingItself`) |
| fc-027 | semver-ordering | four ordering comparisons across `major`/`minor`/`patch`, including `minor: 9` vs. `minor: 10` | numeric ordering holds throughout; the `9`/`10` pair does not sort as strings would (`SemanticVersionTests.ordering`) |
| fc-028 | semver-shape, semver-description-round-trip | `SemanticVersion("1.74.2")!.description`, then `SemanticVersion(that description)` | description equals `"1.74.2"`; re-parsing it equals the original value (`SemanticVersionTests.descriptionRoundTrips`) |
| fc-029 | text-folding-normalization | `TextFolding.folded("CAFÉ")` vs. `TextFolding.folded("cafe")` | equal (`TextFoldingTests.foldsCaseAndDiacritic`) |
| fc-030 | text-folding-empty-input, text-folding-pure | `TextFolding.folded("")` | `""` (`TextFoldingTests.foldsEmptyString`) |
| fc-031 | text-folding-locale-independence | `TextFolding.folded("İstanbul")` evaluated with the current locale set to Turkish (`tr`) and separately to U.S. English (`en_US`) | identical result in both cases, because `locale: nil` is passed explicitly rather than `Locale.current` (traced to source, no dedicated test) |
| fc-032 | cgfloat-clamped-shape, cgfloat-clamped-pure | `CGFloat(5).clamped(to: 0...10)`, `CGFloat(-3).clamped(to: 0...10)`, `CGFloat(42).clamped(to: 0...10)`, `CGFloat(0).clamped(to: 0...10)`, `CGFloat(10).clamped(to: 0...10)` | `5`, `0`, `10`, `0`, `10` respectively (`CGFloatClampedTests.insideRange`, `.belowLower`, `.aboveUpper`, `.equalLower`, `.equalUpper`) |
| fc-033 | cgfloat-clamped-degenerate-range | `CGFloat(-100).clamped(to: 5...5)`, `CGFloat(100).clamped(to: 5...5)`, `CGFloat(5).clamped(to: 5...5)` | `5` in every case (`CGFloatClampedTests.degenerateRange`) |
| fc-034 | cgfloat-clamped-shape | `CGFloat(-100).clamped(to: -10 ... -5)`, `CGFloat(100).clamped(to: -10 ... -5)`, `CGFloat(-7).clamped(to: -10 ... -5)` | `-10`, `-5`, `-7` respectively (`CGFloatClampedTests.negativeRange`) |
| fc-035 | loggable-requirement, loggable-default-subsystem, loggable-default-category, loggable-factory | a type `Foo` conforms to `Loggable` via `static nonisolated let logger = makeLogger()`, running in a process where `Bundle.main.bundleIdentifier == "com.example.app"` | `Foo.logger`'s subsystem is `"com.example.app"`; its category is `"Foo"` (traced to source, no dedicated test) |
| fc-036 | loggable-instance-forwarding | `Foo().logger` on an instance of a `Loggable`-conforming type | identical to `Foo.logger`, the static value (traced to source, no dedicated test) |
| fc-037 | loggable-default-members-isolation | inspect the declarations of `subsystem`, `category`, the instance `logger`, and `makeLogger()` in `Loggable.swift`'s extension | none carries its own `nonisolated` keyword; only the protocol's `logger` requirement is declared `static nonisolated` (traced to source, no dedicated test) |

## Edge Cases

- **Empty string as a stored secret**: `KeychainHelper.set("", forKey:)`
  MUST succeed, and a subsequent `get(forKey:)` MUST return `""`, not
  `nil` — an empty string is a valid, distinct value from "absent."
- **Empty string as a version or a fold target**: `SemanticVersion("")`
  MUST return `nil` (empty is not a valid version), while
  `TextFolding.folded("")` MUST return `""` (empty is a valid, if trivial,
  fold result) — the two types MUST NOT be conflated.
- **Version component at the arithmetic ceiling**: a component equal to
  `Int32.max` MUST parse; a component one greater MUST NOT — the boundary
  is exact, not approximate.
- **Degenerate clamp range**: `clamped(to:)` with `range.lowerBound ==
  range.upperBound` MUST collapse every input to that single value, never
  trap or produce an unrelated result.
- **Concurrent mutation of `KeychainHelper`'s global statics**: `service`,
  `accessGroup`, and `legacyServices` are `nonisolated(unsafe)`; concurrent
  mutation from more than one isolation domain without external
  synchronization is a documented data race, not a crash the type guards
  against.
- **Concurrent mutation of a shared `CodableIgnored` instance**: the
  wrapper is not `Sendable`; sharing one instance's mutable `wrappedValue`
  across concurrency domains without synchronization is the caller's
  responsibility, not something the wrapper prevents.
- **Keychain query failure that is not "not found"**: `copyValue` logs any
  `SecItemCopyMatching` status other than `errSecSuccess` and
  `errSecItemNotFound`, but `get(forKey:)` still returns `nil` for that
  case exactly as it does for a genuine absence — see
  `keychain-get-error-ambiguity` above.
- **Secret recovered from a legacy or access-group scope**: `get(forKey:)`
  re-stores the recovered value under the current scope but MUST NOT
  delete the original — a second install still pointed at the old scope
  MUST continue to find its copy.
- **Unicode and control characters in a stored secret**: `KeychainHelper`
  MUST round-trip a value containing multibyte Unicode, emoji, and control
  characters (newline, tab) exactly, since `set`/`get` encode/decode as raw
  UTF-8 `Data` with no transformation.
- **Offline or disconnected operation**: not applicable — none of the six
  files performs networking, so there is no offline/disconnected state to
  define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `KeychainHelper.service` | `String` (static var) | `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` | Keychain service identifier that scopes every query, set, and delete. |
| `KeychainHelper.accessGroup` | `String?` (static var) | `nil` | Optional shared Keychain access group; when non-nil, forces `kSecUseDataProtectionKeychain` and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on new writes. |
| `KeychainHelper.legacyServices` | `[String]` (static var) | `[]` | Retired service identifiers `get`/`exists` fall back to, newest-retired-first, for migrating secrets forward. |
| `SemanticVersion`'s component ceiling | `Int` (private static constant, `Int32.max`) | `2_147_483_647` | Fixed plausibility bound on `major`/`minor`/`patch`; not caller-configurable. |

`CodableIgnored`, `Loggable`, `MathUtils`'s `CGFloat.clamped(to:)`, and
`TextFolding` take no static or environment configuration — every input
they act on is a per-call argument.

## Deep Linking

Not applicable: none of the six files defines a URL scheme, a route, or any
other navigable destination.

## Localization

Not applicable: none of the six files constructs a user-facing string.
`KeychainHelper`'s and `Loggable`'s only string output is diagnostic log
text (see Logging below), never text displayed to a user; `SemanticVersion`
and `TextFolding` operate on caller-supplied data, not on any string this
recipe itself presents to a user.

## Accessibility Options

Not applicable: none of the six files has a visual or interactive surface
for a system accessibility display option to affect.

## Feature Flags

Not applicable: none of the six files checks a feature flag, a build
configuration, or a remote-config value.

## Analytics

Not applicable: none of the six files emits an analytics or telemetry
event.

## Privacy

`KeychainHelper` is the one file in this recipe that handles sensitive
data; the other five collect, store, and transmit nothing.

- **Data handled**: the secret string values a caller passes to
  `KeychainHelper.set(_:forKey:)` — arbitrary caller-supplied text such as
  an API key or credential. `KeychainHelper` never inspects, parses, or
  transforms the value itself.
- **Storage**: macOS Keychain generic-password items, scoped by `service`
  and optionally `accessGroup`. An access-group item is additionally
  marked `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable
  only after the device's first unlock, and never synced off-device.
- **Transmission**: none. `KeychainHelper` performs no networking; a
  caller that later transmits a retrieved secret does so outside this
  component's boundary.
- **Retention**: indefinite. A stored item persists until a caller calls
  `delete(forKey:)` or the OS/user removes it independently —
  `KeychainHelper` defines no TTL or automatic expiry (see
  `keychain-secret-lifetime-caller-controlled` above).

## Logging

`KeychainHelper` conforms to `Loggable`. Subsystem: `Bundle.main
.bundleIdentifier` (via `Loggable.subsystem`) — Category: `KeychainHelper`
(via `Loggable.category`, the conforming type's own name).

| Event | Level | Message shape |
|-------|-------|----------------|
| `SecItemAdd`/`SecItemUpdate` did not report `errSecSuccess` in `set(_:forKey:)` | error | interpolates the account key and the resulting `OSStatus` |
| `SecItemCopyMatching` reported a status other than `errSecSuccess` or `errSecItemNotFound` in `copyValue` | error | interpolates the account key and the resulting `OSStatus` |
| a secret was recovered from a legacy access-group scope or a retired service and re-stored under the current scope | info | interpolates the account key and the scope it was recovered from |

No log call in `KeychainHelper.swift` interpolates the secret value itself
(see `keychain-secret-value-not-logged` above). The other five files in
this recipe produce no log output at all; `Loggable` only provides the
factory `KeychainHelper` and other conforming types build their logger
from.

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
| 1.0.0 | 2026-09-24 | | Initial recipe covering `CodableIgnored`, `KeychainHelper`, `Loggable`, `MathUtils` (`CGFloat.clamped(to:)`), `SemanticVersion`, and `TextFolding`. |
