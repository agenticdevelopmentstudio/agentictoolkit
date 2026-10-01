---
id: 639bf7b5-011e-4dc0-9c4e-bc704957cf97
title: Extension Runtime Diagnostics
domain: agentictoolkit://cookbook/workspace/extensions/host/runtime-diagnostics
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- code-signing
- entitlements
- singleton
- logging
depends-on:
- agenticdevelopercookbook://guidelines/implementing/observability/logging
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related:
- agentictoolkit://cookbook/workspace/extensions/host/extension-host
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

# Extension Runtime Diagnostics

## Overview

Three related pieces of runtime diagnostics that make two otherwise-invisible
facts about a running build observable. The JIT availability value answers,
from this process's own code-signing entitlements, whether a JavaScript
engine in this process will compile code or silently fall back to its
interpreter — a degradation the engine never surfaces on its own. This
diagnosis is inherently about a macOS-specific security mechanism (the
hardened runtime and its per-app entitlements) with no cross-platform
equivalent; see Platform Notes. The divergence catalogue is a fixed,
built-in list of six places this app deliberately does less than VS Code,
each entry carrying what VS Code does, what this app does instead, why, and
whether it can be observed happening at runtime. The divergence ledger is
the process-wide, thread-safe tally of which catalogue entries a real
extension session actually trips, published live to any subscriber, such as
a language-server settings panel. All three exist so that a narrowing
recorded only in a source comment — or a degradation with no symptom at all
— becomes something a person or a panel can actually see.

## Behavioral Requirements

- **jit-value-shape**: The JIT availability value MUST be an immutable
  value with exactly two fields — a hardened-runtime flag and a
  JIT-entitlement flag, both booleans — and constructing it MUST assign both
  values directly with no validation.
- **jit-degraded-definition**: The degraded state MUST be true only when the
  hardened-runtime flag is set and the JIT-entitlement flag is absent, and
  false in every other combination, including when the hardened-runtime flag
  is unset (where the entitlement flag is irrelevant).
- **jit-diagnosis-nil-when-healthy**: The diagnosis message MUST be absent
  whenever the degraded state is false.
- **jit-diagnosis-content**: When the degraded state is true, the diagnosis
  message MUST be a fixed, non-empty sentence naming
  `com.apple.security.cs.allow-jit` as the missing entitlement, stating that
  extensions will run but every one of them interpreted, and naming
  `App.entitlements` as where the fix belongs.
- **jit-current-memoized-once**: The process-wide cached value MUST be
  computed by probing exactly once for the life of the process, and MUST
  return that same value on every later read for the rest of the process's
  lifetime.
- **jit-probe-live-each-call**: Probing MUST re-read the hardened-runtime
  flag and the JIT-entitlement flag fresh on every invocation, independent
  of whatever the process-wide cached value has already memoized.
- **jit-hardened-flag-read**: Reading the hardened-runtime flag MUST derive
  its answer from this process's own code-signing information, read as a
  flags value, and test it against the hardened-runtime bit (Platform
  Notes: SwiftUI — the exact call chain and bit mask).
- **jit-hardened-read-failure-is-false**: Reading the hardened-runtime flag
  MUST return false, never throw or crash, when any step of that reading
  fails — an unreadable code object, signing information that cannot be
  parsed, or a missing flags value.
- **jit-entitlement-read**: Reading the JIT-entitlement flag MUST read the
  `com.apple.security.cs.allow-jit` entitlement off this process's own task,
  and MUST return false when the process's task cannot be read or the
  entitlement value is not a boolean (Platform Notes — the exact
  calls).
- **jit-log-once-per-process**: Logging when degraded MUST write the
  diagnosis message to the diagnostic log at most once for the process's
  entire lifetime, however many times or from however many call sites it is
  invoked.
- **jit-no-log-when-healthy**: Logging when degraded MUST NOT write
  anything to the log when the diagnosis message is absent.
- **jit-log-privacy**: The one log line logging when degraded can produce
  MUST mark the diagnosis message as safe to disclose in full, not
  redacted, in the logging system's metadata.
- **jit-logging-category**: Logging for the JIT availability value MUST use
  a log category named after the value's own name and a subsystem
  identifying the host application.
- **divergence-value-shape**: A divergence catalogue entry MUST be an
  immutable, identifiable, serializable value with exactly the six fields
  `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, `rationale`, and
  `detection`.
- **divergence-detection-cases**: The detection kind MUST have exactly two
  named cases, `counted` and `declared`, each represented as those exact
  strings wherever the value is serialized.
- **divergence-public-init**: Constructing a divergence catalogue entry
  MUST be available to any caller and MUST assign all six fields directly,
  with no validation, normalization, or default value.
- **divergence-known-catalogue**: The known catalogue MUST be the single
  list a consumer iterates to enumerate "every divergence this app knows
  about" — a divergence entry defined elsewhere but omitted from the known
  catalogue MUST remain individually addressable but MUST NOT appear to any
  caller that iterates the known catalogue.
- **divergence-known-fixed-membership**: The known catalogue MUST contain
  exactly six entries in this fixed order: `documentOutsideWorkspaceScope`,
  `semanticTokenLineOutOfRange`, `semanticTokenModifiersIgnored`,
  `semanticTokenMultilineUnsupported`, `semanticTokenOverlapDropped`,
  `semanticTokenTypeUnmapped`.
- **divergence-ids-unique**: Every entry in the known catalogue MUST have a
  distinct `id` string.
- **divergence-fields-nonempty**: Every entry in the known catalogue MUST
  have a non-empty `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, and
  `rationale`.
- **divergence-detection-mix**: The known catalogue MUST contain at least
  one entry of each detection kind, and the number of `counted` entries MUST
  be greater than or equal to the number of `declared` entries (currently
  five `counted` entries and one `declared` entry).
- **hit-value-shape**: A divergence hit record MUST be an immutable,
  identifiable value with exactly the five fields `divergence`, `detail`,
  `firstSeen`, `lastSeen`, and `count`.
- **hit-identity-key**: A divergence hit record's identity MUST be computed
  as its divergence's `id` and its `detail` joined by the ASCII
  unit-separator character `\u{1F}` — never a generated identifier.
- **ledger-shared-instance-available**: The ledger MUST expose one
  process-wide shared instance usable safely from any thread, and MUST also
  leave direct construction available so a caller (a test, or another host)
  MAY build an independent ledger instead of using the shared one.
- **ledger-record-noop-nonpositive**: Recording a hit MUST perform no row
  write, no log write, and no publish when the given count is zero or
  negative.
- **ledger-record-default-count-one**: Recording a hit with no count given
  MUST record exactly one occurrence.
- **ledger-row-key-by-detail**: A ledger row MUST be keyed by the pair of
  the divergence's `id` and the caller-supplied `detail` string — two
  recordings for the same divergence but different `detail` values MUST
  produce two independent rows, never merged into one.
- **ledger-row-accumulates**: A second recording for a key that already has
  a row MUST add its count to the existing row's count, MUST replace
  `lastSeen` with the current time, and MUST leave `firstSeen` unchanged
  from the row's original creation.
- **ledger-write-serialization**: Every read and every write of the
  ledger's rows MUST be mutually exclusive, so that concurrent recording,
  clearing, and reading calls from different threads MUST NOT corrupt the
  rows or lose an update (confirmed by a test that fires 200 concurrent
  recordings for one key and observes all 200 counted).
- **ledger-first-hit-logs-once**: Recording a hit MUST write an info-level
  diagnostic log line containing the divergence's `id` and its
  `ourBehaviour` text, marked safe to disclose in full, only on the call
  where the key has no existing row (the key's first-ever hit); every later
  recording for that same key MUST NOT log again.
- **ledger-hits-sorted**: Reading all rows or reading the rows for one
  divergence MUST return them sorted by the pair `(divergence.id, detail)`,
  never in insertion or arrival order.
- **ledger-hits-for-filters**: Reading the rows for one divergence MUST
  return only the rows whose key's divergence id equals the given
  divergence's `id`.
- **ledger-publisher-current-value**: The ledger's live rows publisher MUST
  deliver its current value immediately to a new subscriber, even if no
  recording or clearing happens afterward.
- **ledger-every-mutation-publishes**: Both recording (when the count is
  positive) and clearing MUST publish exactly once per call, each sending a
  fresh snapshot of the current rows to every subscriber.
- **ledger-clear-empties**: Clearing MUST remove every row from the ledger
  and then publish an empty list to subscribers; it MUST NOT touch
  `firstSeen`/`lastSeen` bookkeeping for any row, because it discards the
  rows themselves rather than resetting a per-row field.
- **ledger-publish-lock-ordering**: Publishing MUST guarantee that two
  publish operations racing from different threads deliver to subscribers
  in the same order their respective row mutations actually committed, and
  MUST NOT deliver a stale snapshot after a newer one (Platform Notes — implemented as a second exclusion around the snapshot-and-send
  step).
- **ledger-logging-category**: Logging for the divergence ledger MUST use a
  log category named after the ledger's own name.

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
| foundation-diagnostics-001 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | hardened-runtime flag = true, JIT-entitlement flag = true. | degraded state = false; diagnosis message is absent. |
| foundation-diagnostics-002 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | hardened-runtime flag = false, JIT-entitlement flag = false. | degraded state = false; diagnosis message is absent. |
| foundation-diagnostics-003 | jit-degraded-definition, jit-diagnosis-nil-when-healthy | hardened-runtime flag = false, JIT-entitlement flag = true. | degraded state = false; diagnosis message is absent. |
| foundation-diagnostics-004 | jit-degraded-definition, jit-diagnosis-content | hardened-runtime flag = true, JIT-entitlement flag = false. | degraded state = true; diagnosis message contains `com.apple.security.cs.allow-jit`, contains "slow" case-insensitively, and contains `App.entitlements`. |
| foundation-diagnostics-005 | jit-diagnosis-content | Read the diagnosis message for hardened-runtime flag = true, JIT-entitlement flag = false. | Message is longer than 60 characters and ends with a period. |
| foundation-diagnostics-006 | jit-probe-live-each-call | Probe twice in the same process. | Both calls return the same hardened-runtime flag and the same JIT-entitlement flag as each other. |
| foundation-diagnostics-007 | jit-current-memoized-once | Compare the process-wide cached value to a fresh probe. | The cached value's hardened-runtime flag and JIT-entitlement flag equal the fresh probe's. |
| foundation-diagnostics-008 | jit-value-shape, jit-hardened-flag-read, jit-entitlement-read | Inspect the value's shape and the two flag-reading procedures (not exercised by a value-level unit test since both readings depend on how the test runner itself was signed). | The value has exactly the two documented fields; both readers follow the documented signing-information chain and return false on any failure step. |
| foundation-diagnostics-009 | divergence-ids-unique | The known catalogue's `id` values. | No two are equal. |
| foundation-diagnostics-010 | divergence-fields-nonempty | Every entry in the known catalogue. | `id`, `area`, `upstreamBehaviour`, `ourBehaviour`, and `rationale` are all non-empty for every entry. |
| foundation-diagnostics-011 | divergence-detection-mix | Partition the known catalogue by detection kind. | Neither partition is empty, and the `counted` partition's size is greater than or equal to the `declared` partition's size. |
| foundation-diagnostics-012 | divergence-known-fixed-membership | Read the known catalogue. | Exactly six entries, in the order `documentOutsideWorkspaceScope`, `semanticTokenLineOutOfRange`, `semanticTokenModifiersIgnored`, `semanticTokenMultilineUnsupported`, `semanticTokenOverlapDropped`, `semanticTokenTypeUnmapped`. |
| foundation-diagnostics-013 | ledger-row-key-by-detail | Record the overlap-dropped divergence, detail `"file:///a.swift"`, count 3, on a fresh ledger. | The ledger has 1 row; that row's divergence is the overlap-dropped entry, detail is `"file:///a.swift"`, count is 3. |
| foundation-diagnostics-014 | ledger-row-accumulates | Record the overlap-dropped divergence, detail `"file:///a.swift"`, count 2, then again with count omitted (defaults to 1). | The ledger has 1 row; that row's count is 3. |
| foundation-diagnostics-015 | ledger-row-key-by-detail | Record the overlap-dropped divergence for detail `"file:///a.swift"`, then again for detail `"file:///b.swift"`. | The ledger has 2 rows; the rows for the overlap-dropped divergence number 2; the two rows' `detail` values are exactly `{"file:///a.swift", "file:///b.swift"}`. |
| foundation-diagnostics-016 | ledger-row-accumulates | Record the overlap-dropped divergence for detail `"x"` twice, capturing the first row after each call. | The second reading's `firstSeen` equals the first reading's `firstSeen`; the second reading's `lastSeen` is at or after the first reading's `lastSeen`. |
| foundation-diagnostics-017 | ledger-hits-sorted | Record the type-unmapped divergence for detail `"z"`, then the overlap-dropped divergence for detail `"b"`, then the overlap-dropped divergence for detail `"a"`. | The rows, read as "divergence id/detail" pairs, come back already sorted ascending. |
| foundation-diagnostics-018 | ledger-hits-for-filters | Record the overlap-dropped divergence for detail `"a"` and the type-unmapped divergence for detail `"a"`. | Reading the rows for the type-unmapped divergence returns exactly that one divergence. |
| foundation-diagnostics-019 | ledger-publisher-current-value, ledger-every-mutation-publishes | Subscribe to the live rows publisher after one recording, then record a second, different divergence. | The subscriber's first delivered list has count 1 immediately on subscribe; after the second recording, a second delivery arrives with count 2. |
| foundation-diagnostics-020 | ledger-clear-empties | Record the overlap-dropped divergence for detail `"a"`, subscribe, then clear the ledger. | The ledger has no rows; the last value delivered to the subscriber is an empty list. |
| foundation-diagnostics-021 | ledger-record-noop-nonpositive | Record the overlap-dropped divergence for detail `"a"` with count 0, then again with count -4. | The ledger has no rows. |
| foundation-diagnostics-022 | ledger-write-serialization | 200 concurrent recordings of the overlap-dropped divergence for detail `"shared"`. | The ledger has 1 row; that row's count is 200 — no increment lost to the race. |
| foundation-diagnostics-023 | ledger-shared-instance-available | Read the shared ledger instance from two call sites, and separately construct a ledger directly (not exercised by a dedicated identity test — every ledger test in the suite deliberately constructs its own instance instead of using the shared one). | The shared instance is reachable and constructible exactly once; direct construction succeeds and yields an independent, empty ledger. |

## Edge Cases

- **Null and empty input**: Neither field of the JIT availability value is
  optional, so there is no null case there. Constructing a divergence
  catalogue entry and recording a hit both accept their string fields
  (`detail`, `area`, and so on) as plain, unvalidated strings — an empty
  string (`detail: ""`) MUST be accepted and treated as an ordinary,
  distinct row key exactly like any other string.
- **Boundary values**: A hit record's `count` has no upper bound enforced
  by recording — what happens once accumulation reaches the numeric type's
  maximum is platform-dependent (see Platform Notes); reaching that
  boundary requires on the order of the numeric type's maximum accumulated
  occurrences, which no known call site can produce in a single process's
  lifetime. Recording's zero-or-negative-count boundary (a count of exactly
  zero, or any negative value) MUST be a no-op, per
  `ledger-record-noop-nonpositive`.
- **Concurrent access**: The ledger's rows MUST be read and written only
  under mutual exclusion, and publishing's snapshot-and-send step MUST run
  under a second, separate exclusion, so recording, clearing, and reading
  called concurrently from different threads MUST NOT corrupt state or
  misorder subscriber deliveries relative to the mutations that produced
  them (see `ledger-write-serialization` and `ledger-publish-lock-ordering`).
  Two independently constructed ledger instances (for example the shared
  one and one built by a test) each own their own rows, exclusion, and
  publisher; a recording on one MUST have no effect on the other's rows.
  The process-wide cached JIT availability value and its one-time logging
  guard are both initialized exactly once even when first read from several
  threads at once — for example, several concurrently created script
  engines all triggering a degraded-state log at the same moment — so no
  additional coordination is needed for that case. Probing itself holds no
  lock and no shared mutable state, so concurrent probes MUST run
  independently with no coordination between them.
- **Error states**: Reading the hardened-runtime flag and reading the
  JIT-entitlement flag each depend on operating-system calls that can fail
  for reasons outside this component's control (an unsigned binary, a
  signature the OS cannot parse); an unreadable signature MUST answer false
  rather than throw, because this diagnosis may not invent a problem it
  cannot demonstrate. Neither the divergence catalogue nor the divergence
  ledger has any dependency capable of failing; recording, clearing, and
  reading all complete unconditionally.
- **Offline or disconnected state**: Not applicable — none of the three
  pieces opens a network connection, reads a file path, or depends on any
  connectivity state; the JIT availability value's only external dependency
  is a read of this process's own in-memory code-signing information, and
  the divergence ledger's only dependencies are an in-process log handle and
  its live-rows publisher.
- **Unbounded ledger growth**: The divergence ledger provides no automatic
  eviction, expiry, or row limit — every distinct (divergence id, detail)
  pair recorded for the life of the process occupies one row until an
  explicit clear, per its own documented intent to be "cheap: an in-memory
  table behind a lock, no persistence, cleared when the app quits." A
  session that opens many distinct documents that each trip the
  out-of-workspace-scope divergence or a semantic-token divergence MUST
  therefore grow the table by one row per distinct document identifier,
  with no bound other than an explicit clear (see Design Decisions).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| JIT availability value's two fields, given at construction | boolean, boolean | none — both required | Used directly only by the unit tests; production code reads the process-wide cached value or probes fresh rather than constructing a value by hand. |
| Divergence catalogue entry's six fields, given at construction | string ×4, detection kind | none — all six required | Used only to define the six catalogue entries; construction is available to any caller, so an external caller MAY build an additional divergence, but no call site in this codebase does. |
| Ledger recording's count | integer | 1 | The only defaulted field across the three pieces; every other field in all three is required with no default. |
| Ledger instance (injection seam) | ledger | the shared instance, at each consumer's own call site | Consumers depend on the concrete ledger rather than an abstract interface, but direct construction lets a test or an alternate host substitute an independent ledger, as one document-sync consumer's default parameter does. |

None of the three pieces reads an environment variable or a settings key of
its own.

## Deep Linking

Not applicable: none of the three pieces defines a URL scheme, a route, or a
navigation destination — the JIT availability value, the divergence
catalogue, and the divergence ledger are process-internal data sources, not
app navigation.

## Localization

The JIT availability diagnosis message and every divergence catalogue
entry's `area`, `upstreamBehaviour`, `ourBehaviour`, and `rationale` text are
hardcoded English prose with no localization mechanism. Both surfaces are
read by a person: the diagnosis message is written as prose because it
reaches the log and an extensions settings panel, and the divergence
catalogue's fields are rendered by a language-servers settings panel.
Neither offers a second language.

## Accessibility Options

Not applicable: none of the three pieces presents any UI of its own, so
none of them responds to Reduce Motion, Increase Contrast, or Differentiate
Without Color — those settings are the concern of whatever view renders the
strings and rows these pieces produce.

## Feature Flags

Not applicable: none of the three pieces defines or checks a feature-flag or
on/off settings key; the JIT availability reading and the divergence
catalogue are both unconditional.

## Analytics

Not applicable: none of the three pieces contains an analytics or
event-tracking call; the diagnostic log lines produced when degraded and
when recording a hit are diagnostic logging, covered under Logging below,
not analytics instrumentation.

## Privacy

- **Data collected**: Neither piece collects data on its own initiative.
  Recording a hit accepts a caller-supplied `detail` string that becomes
  part of a logged and published row; its own documented constraint states
  it explicitly: "a document URI or a server name is the useful thing,
  never anything drawn from the file's contents." Enforcing that constraint
  is the caller's responsibility — every current call site passes a
  document URI or a token-type name, never document text.
- **Storage**: In-memory only. The ledger's rows are a plain in-memory
  table with no disk, database, or persisted-settings storage of any kind.
- **Transmission**: None. Neither piece makes a network call; the
  live-rows publisher delivers rows only to in-process subscribers.
- **Retention**: A row persists only until the process exits or an explicit
  clear empties the ledger; nothing in either piece writes a row to
  persistent storage, so no data survives a relaunch.

## Logging

Subsystem: the host application's bundle identifier | Category: the JIT
availability value's own name, and the divergence ledger's own name,
respectively.

| Event | Level | Message |
|-------|-------|---------|
| Degraded JIT availability, first detection in the process | error | The full diagnosis message, marked safe to disclose in full. |
| Healthy JIT availability | — | No log line is written (`jit-no-log-when-healthy`). |
| A divergence's first-ever hit for a given key | info | `"Divergence from VS Code first seen: {divergence id} — {ourBehaviour}"`, marked safe to disclose in full. |
| A repeat hit for a key already recorded | — | No log line is written (`ledger-first-hit-logs-once`). |

## Platform Notes

- **SwiftUI**: The three pieces are implemented as `JITAvailability`,
  `UpstreamDivergence` (with its nested `Detection` enum and companion
  `UpstreamDivergenceHit`), and `UpstreamDivergenceLedger`, in
  `packages/apple/AgenticToolkit/Core/Diagnostics/`, part of the
  `AgenticToolkitCore` framework target. `JITAvailability` is a `Sendable,
  Hashable` struct with a public initializer that assigns its two `Bool`
  properties (`isHardenedRuntime`, `hasJITEntitlement`) directly; its
  `current` is a `static let`, memoized once by Swift's own thread-safe
  static-initialization guarantee, backed by a `probe()` that performs a
  fresh read on every call. `readHardenedRuntimeFlag()` calls
  `SecCodeCopySelf`, then `SecCodeCopyStaticCode`, then
  `SecCodeCopySigningInformation` with `kSecCSSigningInformation`, reads the
  `kSecCodeInfoFlags` entry as a `UInt32`, and tests it against the literal
  mask `0x0001_0000` (`kSecCodeSignatureRuntime`, not exposed to Swift),
  returning `false` on any `guard ... else` failure. `readJITEntitlement()`
  calls `SecTaskCreateFromSelf(nil)` and `SecTaskCopyValueForEntitlement`,
  returning `false` if either fails to produce a `Bool`. `logIfDegraded()`
  forces evaluation of a private `static let hasLogged` closure — a Swift
  static stored property whose initializer runs exactly once regardless of
  concurrent first callers — to log at most once per process, marking the
  message `privacy: .public`. `UpstreamDivergence` is a `Sendable, Hashable,
  Identifiable, Codable` struct; `Detection` is a `String`-backed,
  `Sendable, Hashable, Codable` enum. `UpstreamDivergenceHit.count`
  accumulation uses Swift's `+`, which traps on signed-integer overflow
  rather than saturating or wrapping, since the source performs no
  `addingReportingOverflow` or clamping of its own. `UpstreamDivergenceLedger`
  is declared `final class UpstreamDivergenceLedger: @unchecked Sendable`,
  uses an `NSLock` (`lock`) to guard its `rows` dictionary and a second
  `NSLock` (`publishLock`) around `publish()`'s snapshot-and-send step (the
  ordering fix described in Design Decisions), and publishes through a
  Combine `CurrentValueSubject`. Both `JITAvailability` and
  `UpstreamDivergenceLedger` obtain their logger through a shared
  `Loggable` protocol's default `makeLogger()`, which supplies OSLog
  category equal to the conforming type's own name and subsystem
  `Bundle.main.bundleIdentifier`. Nothing here is SwiftUI-specific — any
  host consumes it identically.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Diagnostics/` |

## Design Decisions

**Decision**: On Apple platforms, `JITAvailability` determines JIT
availability by reading this process's code-signing flags and entitlement,
rather than by attempting an actual `mmap` with `MAP_JIT` and observing
whether the kernel grants it.
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

**Decision**: On Apple platforms, `UpstreamDivergenceLedger.publish()`
takes a second lock, `publishLock`, around taking its snapshot of `rows`
and sending it to `subject`, in addition to the `lock` that already guards
`rows` itself.
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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/host/. |
