---
id: 639bf7b5-011e-4dc0-9c4e-bc704957cf97
title: JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger
domain: agentictoolkit://recipes/foundation-diagnostics
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: JIT-entitlement diagnosis read from the process code signature, plus a catalogue
  and thread-safe ledger of deliberate VS Code behavior narrowings.
platforms:
- swift
- macos
tags:
- diagnostics
- foundation
- code-signing
- entitlements
- singleton
- combine
- logging
depends-on:
- agenticdevelopercookbook://guidelines/implementing/observability/logging
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related:
- agentictoolkit://recipes/extension-host-extensions-host
references:
- packages/apple/AgenticToolkit/Core/Diagnostics/JITAvailability.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Diagnostics/UpstreamDivergence.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Diagnostics/UpstreamDivergenceLedger.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Diagnostics/JITAvailabilityTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Diagnostics/UpstreamDivergenceLedgerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger

## Overview

Three types in `packages/apple/AgenticToolkit/Core/Diagnostics/`, part of the
`AgenticToolkitCore` framework target (per `@testable import
AgenticToolkitCore` in both test files), that make two otherwise-invisible
facts about a running build observable. `JITAvailability`
(`JITAvailability.swift`) is a value type that reads this process's own code
signature to answer whether a JavaScript engine in this process will compile
code or silently fall back to its interpreter — a degradation JavaScriptCore
never surfaces on its own. `UpstreamDivergence` (`UpstreamDivergence.swift`)
is a fixed, compiled-in catalogue of six places this app deliberately does
less than VS Code, each carrying what upstream does, what this app does
instead, why, and whether it can be observed happening at runtime.
`UpstreamDivergenceLedger` (`UpstreamDivergenceLedger.swift`, alongside the
`UpstreamDivergenceHit` value type it produces) is the process-wide,
thread-safe tally of which catalogue entries a real extension session
actually trips, published live to a Combine subscriber such as the Language
Servers settings panel. All three exist so that a narrowing recorded only in
a source comment — or a degradation with no symptom at all — becomes
something a person or a panel can actually see.

## Behavioral Requirements

- **jit-value-shape**: `JITAvailability` MUST be a `Sendable`, `Hashable`
  struct with exactly two stored properties, `isHardenedRuntime: Bool` and
  `hasJITEntitlement: Bool`, and its public initializer MUST assign both
  parameters directly with no validation (`JITAvailability.swift`).
- **jit-degraded-definition**: `JITAvailability.isDegraded` MUST return
  `isHardenedRuntime && !hasJITEntitlement` — true only when the hardened
  runtime is enforcing and the JIT entitlement is absent, and false in every
  other combination, including the unhardened case where the entitlement is
  irrelevant.
- **jit-diagnosis-nil-when-healthy**: `JITAvailability.diagnosis` MUST return
  `nil` whenever `isDegraded` is false.
- **jit-diagnosis-content**: When `isDegraded` is true, `diagnosis` MUST
  return a fixed, non-nil sentence naming
  `com.apple.security.cs.allow-jit` as the missing entitlement, stating that
  extensions will run but every one of them interpreted, and naming
  `App.entitlements` as where the fix belongs.
- **jit-current-memoized-once**: `JITAvailability.current` MUST be a
  `static let` whose value is computed by calling `probe()` exactly once for
  the process, and MUST return that same value on every later read for the
  rest of the process's lifetime (doc comment).
- **jit-probe-live-each-call**: `JITAvailability.probe()` MUST perform a
  fresh call to `readHardenedRuntimeFlag()` and `readJITEntitlement()` on
  every invocation, independent of whatever `current` has already memoized.
- **jit-hardened-flag-read**: `readHardenedRuntimeFlag()` MUST derive its
  answer from this process's own code object — `SecCodeCopySelf`, then
  `SecCodeCopyStaticCode`, then `SecCodeCopySigningInformation` with the
  `kSecCSSigningInformation` flag — read the `kSecCodeInfoFlags` entry of the
  resulting dictionary as a `UInt32`, and test it against the literal mask
  `0x0001_0000` (`kSecCodeSignatureRuntime`, not exposed to Swift).
- **jit-hardened-read-failure-is-false**: `readHardenedRuntimeFlag()` MUST
  return `false`, never throw or crash, when any step of that chain fails —
  a non-success `OSStatus`, a nil code object, a signing-information
  dictionary that fails to cast, or a missing or mistyped flags entry (each a `guard ... else { return false }`).
- **jit-entitlement-read**: `readJITEntitlement()` MUST read
  `com.apple.security.cs.allow-jit` off this process's own task via
  `SecTaskCreateFromSelf(nil)` and `SecTaskCopyValueForEntitlement`, and MUST
  return `false` when `SecTaskCreateFromSelf` returns `nil` or the
  entitlement value does not cast to `Bool`.
- **jit-log-once-per-process**: `JITAvailability.logIfDegraded()` MUST cause
  the process to write `current.diagnosis` to the OSLog error level at most
  once for the process's entire lifetime, however many times or from however
  many call sites it is invoked, by forcing evaluation of the private
  `static let hasLogged` closure — a Swift static stored property that runs
  its initializer exactly once regardless of concurrent first callers.
- **jit-no-log-when-healthy**: `logIfDegraded()` MUST NOT write anything to
  the log when `current.diagnosis` is `nil` — `hasLogged`'s closure returns
  `true` immediately in that case without calling `logger.error`.
- **jit-log-privacy**: The one log line `logIfDegraded()` can produce MUST
  mark the diagnosis string `privacy: .public` in the `OSLog` call.
- **jit-logging-category**: `extension JITAvailability: Loggable` MUST
  obtain its logger through `Loggable`'s default `makeLogger()`, which gives
  it OSLog category `"JITAvailability"` (the conforming type's own name) and
  subsystem `Bundle.main.bundleIdentifier` (`JITAvailability.swift`; `Loggable.swift`).
- **divergence-value-shape**: `UpstreamDivergence` MUST be a `Sendable`,
  `Hashable`, `Identifiable`, `Codable` struct with exactly the six stored
  properties `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, `rationale`,
  and `detection: Detection` (`UpstreamDivergence.swift`).
- **divergence-detection-cases**: `UpstreamDivergence.Detection` MUST be a
  `String`-backed, `Sendable`, `Hashable`, `Codable` enum with exactly two
  cases, `counted` and `declared`.
- **divergence-public-init**: `UpstreamDivergence.init(id:area:
  upstreamBehaviour:ourBehaviour:rationale:detection:)` MUST be public and
  MUST assign every one of the six parameters directly, with no validation,
  normalization, or default value.
- **divergence-known-catalogue**: `UpstreamDivergence.known` MUST be the
  single list a consumer iterates to enumerate "every divergence this app
  knows about" — a `static let` divergence defined elsewhere in the file but
  omitted from `known` MUST remain individually addressable but MUST NOT
  appear to any caller that iterates `known` (doc comment).
- **divergence-known-fixed-membership**: `UpstreamDivergence.known` MUST
  contain exactly six entries in this fixed order: `documentOutsideWorkspaceScope`,
  `semanticTokenLineOutOfRange`, `semanticTokenModifiersIgnored`,
  `semanticTokenMultilineUnsupported`, `semanticTokenOverlapDropped`,
  `semanticTokenTypeUnmapped`.
- **divergence-ids-unique**: Every entry in `UpstreamDivergence.known` MUST
  have a distinct `id` string (confirmed by
  `UpstreamDivergenceCatalogueTests.idsAreUnique`).
- **divergence-fields-nonempty**: Every entry in `UpstreamDivergence.known`
  MUST have a non-empty `id`, `area`, `upstreamBehaviour`, `ourBehaviour`,
  and `rationale` (confirmed by
  `UpstreamDivergenceCatalogueTests.everyEntryIsDescribed`).
- **divergence-detection-mix**: `UpstreamDivergence.known` MUST contain at
  least one entry of each `Detection` case, and the number of `.counted`
  entries MUST be greater than or equal to the number of `.declared` entries
  (221 give five `.counted` entries
  and one `.declared` entry; confirmed by
  `UpstreamDivergenceCatalogueTests.bothDetectionKindsArePresent`).
- **hit-value-shape**: `UpstreamDivergenceHit` MUST be a `Sendable`,
  `Hashable`, `Identifiable` struct with exactly the five stored properties
  `divergence: UpstreamDivergence`, `detail: String`, `firstSeen: Date`,
  `lastSeen: Date`, and `count: Int` (`UpstreamDivergenceLedger.swift`).
- **hit-identity-key**: `UpstreamDivergenceHit.id` MUST be computed as
  `divergence.id` and `detail` joined by the ASCII unit-separator character
  `\u{1F}` — never a UUID or other synthesized identifier.
- **ledger-unchecked-sendable-shared**: `UpstreamDivergenceLedger` MUST be
  declared `final class UpstreamDivergenceLedger: @unchecked Sendable`, MUST
  expose one process-wide `static let shared` instance, and MUST also leave
  its own `public init()` available so a caller (a test, or another host)
  MAY construct an independent ledger instead of using `shared`.
- **ledger-record-noop-nonpositive**: `record(_:detail:count:)` MUST perform
  no row write, no log write, and no publish when `count <= 0` (confirmed by
  `UpstreamDivergenceLedgerTests.nonPositiveCountsAreIgnored`).
- **ledger-record-default-count-one**: `record(_:detail:)` called with
  `count` omitted MUST record exactly one occurrence, per the parameter's
  `count: Int = 1` default.
- **ledger-row-key-by-detail**: A ledger row MUST be keyed by the pair of
  the divergence's `id` and the caller-supplied `detail` string — two
  `record` calls for the same divergence but different `detail` values MUST
  produce two independent rows, never merged into one (confirmed by `UpstreamDivergenceLedgerTests.detailsAreSeparateRows`).
- **ledger-row-accumulates**: A second `record(_:detail:count:)` call for a
  key that already has a row MUST add its `count` to the existing row's
  `count`, MUST replace `lastSeen` with the current time, and MUST leave
  `firstSeen` unchanged from the row's original creation (confirmed by `UpstreamDivergenceLedgerTests.secondRecordAccumulates` and
  `.firstSeenIsPinnedAndLastSeenMoves`).
- **ledger-write-serialization**: Every read and every write of the ledger's
  `rows` dictionary MUST occur while holding `lock` (an `NSLock`), so that
  concurrent `record`, `clear`, `hits`, and `hits(for:)` calls from different
  threads MUST NOT corrupt the dictionary or lose an update (confirmed by
  `UpstreamDivergenceLedgerTests.concurrentRecordingIsTotalled`, which
  records 200 concurrent hits for one key and observes all 200 counted).
- **ledger-first-hit-logs-once**: `record(_:detail:count:)` MUST write an
  OSLog info-level line containing the divergence's `id` and its
  `ourBehaviour` text, marked `privacy: .public`, only on the call where
  `existing == nil` (the key's first-ever hit); every later `record` call
  for that same key MUST NOT log again.
- **ledger-hits-sorted**: Both `hits` and `hits(for:)` MUST return their
  rows sorted by the tuple `(divergence.id, detail)`, never in insertion or
  arrival order (confirmed by
  `UpstreamDivergenceLedgerTests.rowsAreSortedForReading`).
- **ledger-hits-for-filters**: `hits(for:)` MUST return only the rows whose
  key's `divergenceID` equals the given divergence's `id` (confirmed by `UpstreamDivergenceLedgerTests.hitsForOneSite`).
- **ledger-publisher-current-value**: `hitsPublisher` MUST be backed by a
  `CurrentValueSubject`, so a subscriber MUST receive the ledger's rows as
  they stand at the moment of subscription, even if no `record` or `clear`
  call happens afterward (confirmed by
  `UpstreamDivergenceLedgerTests.publisherCarriesTheRows`).
- **ledger-every-mutation-publishes**: Both `record(_:detail:count:)` (when
  `count > 0`) and `clear()` MUST call `publish()` exactly once per call,
  each sending a fresh snapshot of the current rows to every subscriber.
- **ledger-clear-empties**: `clear()` MUST remove every row from the ledger
  and then publish an empty array to subscribers; it MUST NOT touch
  `firstSeen`/`lastSeen` bookkeeping for any row, because it discards the
  rows themselves rather than resetting a per-row field (confirmed by `UpstreamDivergenceLedgerTests.clearEmptiesAndPublishes`).
- **ledger-publish-lock-ordering**: `publish()` MUST take a second lock,
  `publishLock`, around taking its rows snapshot and sending it, so that two
  `publish()` calls racing on different threads MUST deliver to subscribers
  in the same order their respective row mutations actually committed, and
  MUST NOT deliver a stale snapshot after a newer one (per
  the type's own doc comment; not exercised by a dedicated
  ordering test — inferred from the documented purpose of the second lock).
- **ledger-logging-category**: `extension UpstreamDivergenceLedger:
  Loggable` MUST obtain its logger through `Loggable`'s default
  `makeLogger()`, giving it OSLog category `"UpstreamDivergenceLedger"`.

## Appearance

Not applicable — this is a code-signature diagnostic and an in-memory
divergence ledger, not a visual component.

## States

Not applicable — this is a code-signature diagnostic and an in-memory
divergence ledger, not a visual component.

## Accessibility

Not applicable — this is a code-signature diagnostic and an in-memory
divergence ledger, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| foundation-diagnostics-001 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | `JITAvailability(isHardenedRuntime: true, hasJITEntitlement: true)` (`JITAvailabilityTests.hardenedAndEntitledIsSilent`). | `isDegraded == false`, `diagnosis == nil`. |
| foundation-diagnostics-002 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | `JITAvailability(isHardenedRuntime: false, hasJITEntitlement: false)` (`.unhardenedIsSilent`). | `isDegraded == false`, `diagnosis == nil`. |
| foundation-diagnostics-003 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | `JITAvailability(isHardenedRuntime: false, hasJITEntitlement: true)` (`.unhardenedButEntitledIsSilent`). | `isDegraded == false`, `diagnosis == nil`. |
| foundation-diagnostics-004 | jit-degraded-definition, jit-diagnosis-content | `JITAvailability(isHardenedRuntime: true, hasJITEntitlement: false)` (`.hardenedWithoutEntitlementIsTheDefect`). | `isDegraded == true`; `diagnosis` contains `com.apple.security.cs.allow-jit`, contains "slow" case-insensitively, and contains `App.entitlements`. |
| foundation-diagnostics-005 | jit-diagnosis-content | Read `.diagnosis` from `JITAvailability(isHardenedRuntime: true, hasJITEntitlement: false)` (`.diagnosisIsProse`). | `diagnosis.count > 60` and `diagnosis.hasSuffix(".")`. |
| foundation-diagnostics-006 | jit-probe-live-each-call | Call `JITAvailability.probe()` twice in the same process (`.probeIsStable`). | Both calls return the same `isHardenedRuntime` and the same `hasJITEntitlement` as each other. |
| foundation-diagnostics-007 | jit-current-memoized-once | Compare `JITAvailability.current` to a fresh `JITAvailability.probe()` call (`.currentMatchesAProbe`). | `current.isHardenedRuntime == probed.isHardenedRuntime` and `current.hasJITEntitlement == probed.hasJITEntitlement`. |
| foundation-diagnostics-008 | jit-value-shape, jit-hardened-flag-read, jit-entitlement-read | Inspect `JITAvailability`'s declaration and `readHardenedRuntimeFlag()`/`readJITEntitlement()` bodies (not exercised by a value-level unit test since both readings depend on how the test runner itself was signed). | Struct conforms to `Sendable, Hashable` with exactly the two documented properties; both private readers follow the `SecCode`/`SecTask` chain described and return `false` on any failure step. |
| foundation-diagnostics-009 | divergence-ids-unique | `UpstreamDivergence.known.map(\.id)` (`UpstreamDivergenceCatalogueTests.idsAreUnique`). | `Set(ids).count == ids.count`. |
| foundation-diagnostics-010 | divergence-fields-nonempty | Every entry in `UpstreamDivergence.known` (`.everyEntryIsDescribed`). | `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, and `rationale` are all non-empty for every entry. |
| foundation-diagnostics-011 | divergence-detection-mix | Partition `UpstreamDivergence.known` by `detection` (`.bothDetectionKindsArePresent`). | Neither partition is empty, and `counted.count >= declared.count`. |
| foundation-diagnostics-012 | divergence-known-fixed-membership | Read `UpstreamDivergence.known` (not directly asserted by any given test, derived from the array literal itself). | Exactly six entries, in the order `documentOutsideWorkspaceScope`, `semanticTokenLineOutOfRange`, `semanticTokenModifiersIgnored`, `semanticTokenMultilineUnsupported`, `semanticTokenOverlapDropped`, `semanticTokenTypeUnmapped`. |
| foundation-diagnostics-013 | ledger-row-key-by-detail | `ledger.record(.semanticTokenOverlapDropped, detail: "file:///a.swift", count: 3)` on a fresh `UpstreamDivergenceLedger()` (`UpstreamDivergenceLedgerTests.firstRecordStartsARow`). | `ledger.hits.count == 1`; that row's `divergence == overlap`, `detail == "file:///a.swift"`, `count == 3`. |
| foundation-diagnostics-014 | ledger-row-accumulates | `ledger.record(overlap, detail: "file:///a.swift", count: 2)` then `ledger.record(overlap, detail: "file:///a.swift")` (`.secondRecordAccumulates`). | `ledger.hits.count == 1`; that row's `count == 3`. |
| foundation-diagnostics-015 | ledger-row-key-by-detail | `ledger.record(overlap, detail: "file:///a.swift")` then `ledger.record(overlap, detail: "file:///b.swift")` (`.detailsAreSeparateRows`). | `ledger.hits.count == 2`; `ledger.hits(for: overlap).count == 2`; the two rows' `detail` values are exactly `{"file:///a.swift", "file:///b.swift"}`. |
| foundation-diagnostics-016 | ledger-row-accumulates | Record `overlap` for detail `"x"` twice, capturing `hits[0]` after each call (`.firstSeenIsPinnedAndLastSeenMoves`). | The second reading's `firstSeen` equals the first reading's `firstSeen`; the second reading's `lastSeen >=` the first reading's `lastSeen`. |
| foundation-diagnostics-017 | ledger-hits-sorted | Record `unmapped` detail `"z"`, then `overlap` detail `"b"`, then `overlap` detail `"a"` (`.rowsAreSortedForReading`). | `ledger.hits.map { "\(divergence.id)/\(detail)" }` equals that same array already sorted ascending. |
| foundation-diagnostics-018 | ledger-hits-for-filters | Record `overlap` detail `"a"` and `unmapped` detail `"a"` (`.hitsForOneSite`). | `ledger.hits(for: unmapped).map(\.divergence) == [unmapped]`. |
| foundation-diagnostics-019 | ledger-publisher-current-value, ledger-every-mutation-publishes | Subscribe to `hitsPublisher` after one `record` call, then record a second, different divergence (`.publisherCarriesTheRows`). | The subscriber's first delivered array has count 1 immediately on subscribe; after the second `record`, a second delivery arrives with count 2. |
| foundation-diagnostics-020 | ledger-clear-empties | `ledger.record(overlap, detail: "a")`, subscribe, then `ledger.clear()` (`.clearEmptiesAndPublishes`). | `ledger.hits.isEmpty == true`; the last value delivered to the subscriber is an empty array. |
| foundation-diagnostics-021 | ledger-record-noop-nonpositive | `ledger.record(overlap, detail: "a", count: 0)` then `ledger.record(overlap, detail: "a", count: -4)` (`.nonPositiveCountsAreIgnored`). | `ledger.hits.isEmpty == true`. |
| foundation-diagnostics-022 | ledger-write-serialization | 200 concurrent tasks each call `ledger.record(.semanticTokenOverlapDropped, detail: "shared")` (`.concurrentRecordingIsTotalled`). | `ledger.hits.count == 1`; that row's `count == 200` — no increment lost to the race. |
| foundation-diagnostics-023 | ledger-unchecked-sendable-shared | Read `UpstreamDivergenceLedger.shared` from two call sites, and separately construct `UpstreamDivergenceLedger()` directly (not exercised by a dedicated identity test — every ledger test in the suite deliberately constructs its own instance instead of using `.shared`, per the test file's own doc comment). | `UpstreamDivergenceLedger.shared` is reachable and constructible exactly once as a `static let`; `UpstreamDivergenceLedger()` succeeds and yields an independent, empty ledger. |

## Edge Cases

- **Null and empty input**: Neither `JITAvailability.init` parameter is
  optional, so there is no null case for `JITAvailability`. `UpstreamDivergence.init`
  and `record(_:detail:count:)` both accept `detail`/`area`/etc. as plain,
  unvalidated `String`s — an empty string (`detail: ""`) MUST be accepted
  and treated as an ordinary, distinct row key exactly like any other string
  (`UpstreamDivergenceLedger.swift`; no length or
  content check exists in either file).
- **Boundary values**: `UpstreamDivergenceHit.count` is an `Int` with no
  upper bound enforced by `record(_:detail:count:)` — repeated accumulation
  (`(existing?.count ?? 0) + count`) MUST eventually trap on
  signed-integer overflow rather than saturate or wrap, since Swift's `+`
  operator traps by default and the source performs no `addingReportingOverflow`
  or clamping of its own; reaching that boundary requires on the order of
  `Int.max` accumulated occurrences, which no known call site can produce
  in a single process's lifetime. `record`'s `count <= 0` boundary (`count == 0`
  exactly, and any negative value) MUST be a no-op, per `ledger-record-noop-nonpositive`.
- **Concurrent access**: `UpstreamDivergenceLedger.rows` MUST be read and
  written only under `lock`, and `publish()`'s snapshot-and-send MUST run
  under the separate `publishLock`, so `record`, `clear`, `hits`, and
  `hits(for:)` called concurrently from different threads MUST NOT corrupt
  state or misorder subscriber deliveries relative to the mutations that
  produced them (MUST, see `ledger-write-serialization` and
  `ledger-publish-lock-ordering`). Two independently constructed
  `UpstreamDivergenceLedger` instances (for example `.shared` and one built
  by a test) each own their own `rows`, `lock`, `publishLock`, and `subject`;
  a `record` call on one MUST have no effect on the other's `hits`. `JITAvailability.current` and the private `hasLogged` static
  are both lazily initialized `static let` bindings, which Swift's runtime
  guarantees run their initializer exactly once even when first read from
  several threads at once — for example, several `JSVirtualMachine`s created
  concurrently by `ExtensionHost` all calling `logIfDegraded()` — so no additional locking is needed or present in either type
  for this case. `JITAvailability.probe()` itself holds no lock and no
  shared mutable state, so concurrent calls to it MUST run independently
  with no coordination between them.
- **Error states**: `readHardenedRuntimeFlag()` and `readJITEntitlement()`
  each depend on Security-framework calls
  (`SecCodeCopySelf`/`SecCodeCopyStaticCode`/`SecCodeCopySigningInformation`,
  `SecTaskCreateFromSelf`/`SecTaskCopyValueForEntitlement`) that can fail for
  reasons outside this component's control (an unsigned binary, a signature
  the OS cannot parse); per the source's own doc comment, an unreadable
  signature MUST answer `false` rather than throw, because "this type may
  not invent a problem it cannot demonstrate".
  Neither `UpstreamDivergence` nor `UpstreamDivergenceLedger` declares a
  `throws` function or has any dependency capable of failing; `record`,
  `clear`, `hits`, and `hits(for:)` all complete unconditionally.
- **Offline or disconnected state**: Not applicable — none of the three
  files opens a network connection, reads a file path, or depends on any
  connectivity state; `JITAvailability`'s only external dependency is the
  Security framework's read of this process's own in-memory code object, and
  `UpstreamDivergenceLedger`'s only dependencies are an in-process `OSLog`
  handle and a Combine `CurrentValueSubject`.
- **Unbounded ledger growth**: `UpstreamDivergenceLedger` provides no
  automatic eviction, expiry, or row limit — every distinct
  `(divergence.id, detail)` pair recorded for the life of the process
  occupies one row until an explicit `clear()` call, per the type's own doc
  comment describing itself as "deliberately cheap: an in-memory dictionary
  behind a lock, no persistence, cleared when the app quits".
  A session that opens many distinct documents that each trip
  `documentOutsideWorkspaceScope` or a semantic-token divergence MUST
  therefore grow the dictionary by one row per distinct document URI, with
  no bound other than an explicit `clear()` (see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `JITAvailability.init(isHardenedRuntime:hasJITEntitlement:)` parameters | `Bool`, `Bool` | none — both required | Used directly only by `JITAvailabilityTests.swift`; production code reads `.current` or calls `.probe()` rather than constructing a value by hand. |
| `UpstreamDivergence.init(id:area:upstreamBehaviour:ourBehaviour:rationale:detection:)` parameters | `String` ×4, `Detection` | none — all six required | Used only to define the six `static let` catalogue entries in `UpstreamDivergence.swift`; the initializer is public, so an external caller MAY build an additional divergence, but no call site in this codebase does. |
| `UpstreamDivergenceLedger.record(_:detail:count:)` `count` | `Int` | `1` | The only defaulted parameter across either file; every other parameter in both types is required with no default. |
| `UpstreamDivergenceLedger` instance (injection seam) | `UpstreamDivergenceLedger` | `.shared`, at each consumer's own call site | Consumers depend on the concrete class rather than a protocol, but its `public init()` lets a test or an alternate host substitute an independent ledger, as `LanguageServerDocumentSync.init(ledger:)`'s `= .shared` default parameter does. |

Neither `JITAvailability.swift`, `UpstreamDivergence.swift`, nor
`UpstreamDivergenceLedger.swift` reads an environment variable or a settings
key of its own.

## Deep Linking

Not applicable: none of the three files defines a URL scheme, a route, or a
navigation destination — `JITAvailability`, `UpstreamDivergence`, and
`UpstreamDivergenceLedger` are process-internal data sources, not app
navigation.

## Localization

`JITAvailability.diagnosis` and every `UpstreamDivergence`
entry's `area`, `upstreamBehaviour`, `ourBehaviour`, and `rationale` text are hardcoded English prose with no localization mechanism —
no `String(localized:)`, no string-catalog key, no `Bundle` lookup. Both
surfaces are read by a person: `diagnosis`'s own doc comment says it is
written as prose because it reaches "the log and the Extensions settings
panel," and `UpstreamDivergence`'s fields are rendered by the Language
Servers settings panel (`LanguageServersPanelViewController.swift`, outside
this recipe's sources). Neither file offers a second language.

## Accessibility Options

Not applicable: neither `JITAvailability`, `UpstreamDivergence`, nor
`UpstreamDivergenceLedger` presents any UI of its own, so none of them
responds to Reduce Motion, Increase Contrast, or Differentiate Without
Color — those settings are the concern of whatever view renders the strings
and rows these types produce.

## Feature Flags

Not applicable: none of the three files defines or checks a feature-flag or
on/off settings key; `JITAvailability`'s reading and `UpstreamDivergence`'s
catalogue are both unconditional.

## Analytics

Not applicable: none of the three files contains an analytics or
event-tracking call; the OSLog calls in `JITAvailability.logIfDegraded()`
and `UpstreamDivergenceLedger.record(_:detail:count:)` are diagnostic
logging, covered under Logging below, not analytics instrumentation.

## Privacy

- **Data collected**: Neither type collects data on its own initiative.
  `UpstreamDivergenceLedger.record(_:detail:count:)` accepts a
  caller-supplied `detail: String` that becomes part of a logged and
  published row; the type's own doc comment states the constraint on that
  string explicitly: "a document URI or a server name is the useful thing,
  never anything drawn from the file's contents" (`UpstreamDivergenceHit`
  doc comment). Enforcing that constraint is the caller's
  responsibility — every current call site passes a document URI or a
  token-type name (`SemanticTokenHighlightProvider.swift`,
  `LanguageServerDocumentSync.swift`, outside this recipe's sources), never
  document text.
- **Storage**: In-memory only. `UpstreamDivergenceLedger.rows` is a plain
  Swift dictionary with no disk, database, or `UserDefaults` persistence of
  any kind.
- **Transmission**: None. Neither type makes a network call; `hitsPublisher`
  delivers rows only to in-process Combine subscribers.
- **Retention**: A row persists only until the process exits or an explicit
  `clear()` call empties the ledger; nothing in either file
  writes a row to persistent storage, so no data survives a relaunch.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default,
`Loggable.swift`) | Category: `JITAvailability` and
`UpstreamDivergenceLedger` respectively (`Loggable`'s default per-type
category).

| Event | Level | Message |
|-------|-------|---------|
| Degraded JIT availability, first detection in the process | error | The full `diagnosis` sentence (`JITAvailability.swift`), marked `privacy: .public`. |
| Healthy JIT availability | — | No log line is written (`jit-no-log-when-healthy`). |
| A divergence's first-ever hit for a given key | info | `"Divergence from VS Code first seen: \(divergence.id) — \(divergence.ourBehaviour)"` (`UpstreamDivergenceLedger.swift`), marked `privacy: .public`. |
| A repeat hit for a key already recorded | — | No log line is written (`ledger-first-hit-logs-once`). |

## Platform Notes

- **SwiftUI**: The sources are
  `packages/apple/AgenticToolkit/Core/Diagnostics/JITAvailability.swift`,
  `UpstreamDivergence.swift`, and `UpstreamDivergenceLedger.swift`, part of
  the `AgenticToolkitCore` target. `JITAvailability` uses `Security`
  framework APIs (`SecCode`, `SecTask`) to read this process's own
  code-signing flags and entitlements; `UpstreamDivergence` is a plain
  `Codable` value catalogue; `UpstreamDivergenceLedger` uses `NSLock` for
  mutual exclusion and `Combine`'s `CurrentValueSubject` for its live
  publisher. Nothing here is SwiftUI-specific — any host consumes it
  identically.
- **Compose**: There is no Android analogue to macOS's hardened runtime or
  to a per-entitlement JIT gate — ART's own JIT/AOT compilation strategy is
  a system-level decision, not an app-declared capability, so
  `JITAvailability` has no Kotlin equivalent to port; a port would document
  the absence rather than translate it. `UpstreamDivergence` and
  `UpstreamDivergenceHit` translate directly to Kotlin `data class`es. For
  `UpstreamDivergenceLedger`, a `synchronized` block or `kotlinx.atomicfu`
  lock stands in for `NSLock`, `kotlinx.coroutines.flow.MutableStateFlow`
  stands in for `CurrentValueSubject` (both deliver their current value
  immediately to a new collector), and a plain Kotlin `object` singleton
  stands in for `UpstreamDivergenceLedger.shared`.
- **React/Web**: Browsers need no entitlement to let a JavaScript engine
  compile code, so `JITAvailability` has no web equivalent to port; the
  nearest analogous gate is a page's Content-Security-Policy
  `script-src` directive controlling `unsafe-eval`/WebAssembly compilation,
  which is a page-level policy, not a per-process code-signature reading, so
  it does not map onto this type's contract. `UpstreamDivergence` translates
  to a `readonly` TypeScript interface array; `UpstreamDivergenceLedger`
  translates to a class wrapping a `Map` (in place of the `Key`-keyed
  dictionary) and an RxJS `BehaviorSubject` (the direct analogue of
  `CurrentValueSubject`, since both replay their latest value to a new
  subscriber) in place of manual lock-guarded state, since JavaScript's
  single-threaded event loop needs no `NSLock` equivalent at all.
- **AppKit / UIKit**: Identical to the SwiftUI note — none of the three
  types is UI-framework-specific; only the host application embedding
  `AgenticToolkitCore` differs, never this contract. (`JITAvailability`'s
  own consumer, `ExtensionHost.swift`, happens to be an AppKit-hosted,
  macOS-only feature, but that is a fact about the caller, not this
  component.)
- **WinUI 3**: Windows has no direct analogue to
  `com.apple.security.cs.allow-jit` or the hardened runtime flag — code
  integrity on Windows is governed by Authenticode signing and, for packaged
  apps, MSIX package capabilities and WDAC/AppLocker policy, none of which
  expose a single per-app "is JIT allowed" bit the way a macOS entitlement
  does; a Windows port has no established source of truth to read in
  `JITAvailability`'s place and would need a new decision, not a
  translation. Model `UpstreamDivergence` as a C# `record` implementing
  `IEquatable<T>` with a nested `enum Detection { Counted, Declared }`, and
  `UpstreamDivergenceHit` the same way. Model `UpstreamDivergenceLedger` as
  a class backed by a `lock`-guarded `Dictionary<(string, string),
  UpstreamDivergenceHit>` (or a `ConcurrentDictionary` if lock-free reads are
  wanted instead), exposing its live rows through `System.Reactive.Subjects.BehaviorSubject<IReadOnlyList<UpstreamDivergenceHit>>`
  (Rx.NET's direct analogue of `CurrentValueSubject`) rather than
  `ObservableCollection`, since what is needed is "replay the latest full
  snapshot to a new subscriber," not incremental collection-changed
  notifications. Use `Microsoft.Extensions.Logging.ILogger<T>`, categorized
  by type the way `Loggable` categorizes by `type(of: self)`, in place of
  `OSLog`'s subsystem/category pair.

## Design Decisions

**Decision**: `JITAvailability` determines JIT availability by reading this
process's code-signing flags and entitlement, rather than by attempting an
actual `mmap` with `MAP_JIT` and observing whether the kernel grants it.
**Rationale**: Per the type's own doc comment, the `mmap`-based probe was
written first and measured against three signing configurations (hardened
and entitled, hardened and bare, and neither); it succeeded in all three,
because the kernel does not enforce the entitlement at mapping time. A probe
built on that call could never fail and would have shipped as a check that
silently never fires — the same defect class it exists to catch. Reading the
signature instead discriminates between the three configurations, which is
the whole reason the two boolean readings are what this type reads.
**Approved**: pending

**Decision**: `UpstreamDivergence.Detection` distinguishes `.counted`
divergences (those with a live call site that can record a hit) from
`.declared` divergences (those with no call site, because the narrowing
takes the form of a capability this app never advertised upstream).
**Rationale**: A `.counted` row reading zero is real evidence that nothing
tripped it; a `.declared` row has no meaningful count at all, since nothing
in the app could record one even if the narrowing mattered constantly. A
report that rendered both as "0" without the label would invite exactly the
wrong conclusion about the second kind — this is why `Detection` is a
distinct field on every entry rather than a derived property, and why the
catalogue currently keeps `.counted` entries in the majority (five of six).
**Approved**: pending

**Decision**: `UpstreamDivergenceLedger.publish()` takes a second lock,
`publishLock`, around taking its snapshot of `rows` and sending it to
`subject`, in addition to the `lock` that already guards `rows` itself.
**Rationale**: The type's own doc comment describes the bug this fixes: two
writers that each compute their snapshot under `lock` and send it only after
releasing leave the send order to the scheduler, so a recorder overtaken in
that gap by a concurrent `clear()` could publish rows the clear had already
removed — and because `CurrentValueSubject` replays only its last value,
that stale publish would never self-correct. Reading the snapshot inside the
second lock's exclusion guarantees whoever finishes last publishes the
newest state, whichever order the underlying mutations actually committed
in.
**Approved**: pending

**Decision**: `UpstreamDivergenceLedger` keeps no eviction policy, expiry,
or row cap — rows accumulate for the process's lifetime and are only ever
cleared by an explicit `clear()` call.
**Rationale**: The type's own doc comment calls this deliberate: the ledger
is "cheap: an in-memory dictionary behind a lock, no persistence, cleared
when the app quits," and a ledger that survived launches would accumulate
rows from code that has since changed — the same failure mode as any stale
diagnostic file. The source does not, however, document a bound on how large
`rows` may grow within a single long-running session before the next
`clear()`; see the "Unbounded ledger growth" edge case.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | Reliability |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | partial | Performance |

Notes: separation-of-concerns passes because `JITAvailability` and
`UpstreamDivergence` are self-contained value types with no dependency on
any UI or infrastructure layer, and `UpstreamDivergenceLedger` exposes only
`hits`, `hits(for:)`, and `hitsPublisher` as its seam — a consumer such as
the Language Servers settings panel never touches its `NSLock` or
dictionary directly, and every recorder depends on the concrete
`UpstreamDivergenceLedger` type through constructor injection defaulting to
`.shared`, never a bare global function. unit-test-coverage passes because
`JITAvailabilityTests.swift` exercises every `isHardenedRuntime`/`hasJITEntitlement`
combination and the memoization/stability of `current`/`probe()`, and
`UpstreamDivergenceLedgerTests.swift` plus `UpstreamDivergenceCatalogueTests`
exercise accumulation, row keying, sorting, filtering, publishing, clearing,
non-positive counts, 200-way concurrent recording, and every catalogue
invariant. secure-log-output passes because the only strings either type
logs are the fixed `diagnosis` prose and, in the ledger, the divergence's
`id` and its fixed `ourBehaviour` catalogue text, plus a caller-supplied
`detail` that the source's own doc comment restricts to a document URI or
server name — never a credential, token, or document's contents.
health-observability is partial because both types log only on a state
transition — `JITAvailability` at most once per process, the ledger only on
a key's first-ever hit — with nothing emitted on any periodic cadence, so a
monitoring system reading logs alone cannot distinguish "still healthy" from
"never checked since the last transition." resource-efficiency is partial
because, while both types are cheap at idle, `UpstreamDivergenceLedger` has
no eviction policy or row cap (see the "Unbounded ledger growth" edge case
and its Design Decisions entry), so a long session touching many distinct
documents grows `rows` without bound until an explicit `clear()`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
