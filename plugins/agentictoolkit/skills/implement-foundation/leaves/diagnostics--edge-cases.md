<!-- leaf: implement-foundation/diagnostics--edge-cases · source: foundation-diagnostics.md -->

# JITAvailability, UpstreamDivergence & UpstreamDivergenceLedger

**Rules** (cite as `implement-foundation/diagnostics--edge-cases#<slug>`):

- `null-and-empty-input` MUST — Neither JITAvailability.init parameter is optional, so there is no null case for JITAvailability. …
- `boundary-values` MUST — UpstreamDivergenceHit.count is an Int with no upper bound enforced by record(_:detail:count:) — repeated accumulation …
- `concurrent-access` MUST — UpstreamDivergenceLedger.rows MUST be read and written only under lock, and publish()'s snapshot-and-send MUST run …
- `error-states` MUST — readHardenedRuntimeFlag() and readJITEntitlement() each depend on Security-framework calls …
- `unbounded-ledger-growth` MUST — UpstreamDivergenceLedger provides no automatic eviction, expiry, or row limit — every distinct (divergence.id, detail) …

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
