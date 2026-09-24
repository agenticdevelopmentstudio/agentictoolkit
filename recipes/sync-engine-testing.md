---
id: fbb19775-20c8-4857-9945-53947a2078df
title: Sync Engine Testing
domain: agentictoolkit://recipes/sync-engine-testing
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'In-framework test fakes for the sync engine: an actor-isolated in-memory
  SyncStore with outbox coalescing and a scripted SyncTransport.'
platforms:
- swift
- macos
- ios
tags:
- sync
- offline
- testing
depends-on:
- agentictoolkit://recipes/sync-engine
related:
- agentictoolkit://recipes/sync-engine
- agentictoolkit://recipes/adh-offline-sync-client
references:
- packages/apple/AgenticToolkit/Sync/Testing/InMemorySyncStore.swift
- packages/apple/AgenticToolkit/Sync/Testing/ScriptedSyncTransport.swift
- packages/apple/AgenticToolkit/Sync/SyncProtocols.swift
- packages/apple/AgenticToolkit/Sync/SyncWire.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncTests/InMemorySyncStoreTests.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncTests/SyncEngineTests.swift
approved-by: ''
approved-date: ''
---

# Sync Engine Testing

## Overview

Sync Engine Testing is the pair of reference fakes that ship inside the
`AgenticToolkitSync` framework (the toolkit convention, per the source comment:
"fakes ship in the framework"), under `Sync/Testing/`:

- `InMemorySyncStore` — an `actor` conforming to `SyncStore` that keeps
  per-resource mirror rows, a cursor, an outbox, a conflict log and a
  quarantine list in memory. Its doc comments state that it mirrors
  `GRDBSyncStore` for registration, atomic apply, outbox coalescing, inflight
  replay, `newVersion` adoption and purge, "so the fakes don't lie" about the
  real store's behavior. It also exposes test conveniences (`rowCount`, `row`,
  `pendingOpId`).
- `ScriptedSyncTransport` — an `actor` conforming to `SyncTransport` that
  returns queued pull and push outcomes in FIFO order, records every request,
  and falls back to an empty pull or an all-applied push when its script is
  empty.
- `SyncStoreFailure` — the error enum both stores throw
  (`unknownResource`, `invalidChange`, `pullOnlyResource`).

Use them to drive [SyncEngine](agentictoolkit://recipes/sync-engine) in unit
tests and previews without SQLite or a network, and as the executable
specification a port's own store and transport fakes are checked against.

## Behavioral Requirements

### Isolation and types

- **store-actor**: `InMemorySyncStore` MUST be an actor, so every call to it (protocol methods and test conveniences alike) is serialized on that actor and callers outside it MUST `await` it.
- **transport-actor**: `ScriptedSyncTransport` MUST be an actor, so enqueueing, pulling and pushing are serialized and never interleave within one call.
- **row-shape**: `InMemorySyncStore.Row` MUST be a `Sendable`, `Equatable` struct with the mutable fields `syncVersion: String`, `deleted: Bool` and `data: [String: JSONValue]`.
- **outcome-shape**: `ScriptedSyncTransport.Outcome<T: Sendable>` MUST be a `Sendable` enum with exactly two cases, `success(T)` and `failure(SyncTransportError)`.
- **failure-shape**: `SyncStoreFailure` MUST be a `Sendable`, `Equatable` `Error` enum with the cases `unknownResource(String)`, `invalidChange(String)` and `pullOnlyResource(String)`.
- **observable-logs**: `conflictLog` (`[(opId: String, reason: String?)]`) and `quarantined` (`[SyncPushOp]`) MUST be publicly readable and writable only by the store itself.
- **transport-records**: `pullCursors` (`[SyncCursor?]`) and `pushedRequests` (`[SyncPushRequest]`) MUST be publicly readable and writable only by the transport itself.

### InMemorySyncStore — registration

- **prepare-upsert**: `prepare(resources:)` MUST register every descriptor's `resource` with its `schemaVersion`; for an already-registered resource it MUST replace the schema version and keep the existing mirror rows.
- **prepare-new-empty**: A newly registered resource MUST start with no mirror rows.
- **registration-truth**: A resource MUST count as registered exactly when it has an entry holding both its schema version and its rows; `stage`, `apply` and `rowCount` MUST consult that single entry, so schema version and rows can never disagree about registration.
- **registrations-projection**: `registrations()` MUST return `[resource: schemaVersion]` for every registered resource and nothing else.

### InMemorySyncStore — pulled changes

- **cursor-read**: `cursor()` MUST return the last cursor stored by `apply`, or nil if none has been stored or after `resetForResync()`.
- **apply-unknown-resource**: `apply(_:advancingTo:)` MUST throw `SyncStoreFailure.unknownResource(resource)` for a change whose resource is not registered.
- **apply-unparseable-version**: `apply(_:advancingTo:)` MUST throw `SyncStoreFailure.invalidChange("unparseable syncVersion: <value>")` for a change whose `syncVersion` does not parse as an `Int`.
- **apply-atomic**: When `apply` throws for any change in the batch, it MUST leave every mirror row and the stored cursor exactly as they were before the call.
- **apply-row-write**: For each change, `apply` MUST set the row keyed by `change.id` to `syncVersion` = `change.syncVersion`, `deleted` = `change.op == .delete`, and `data` = `change.data`, or an empty dictionary when `data` is nil.
- **apply-keeps-string-version**: `apply` MUST store `syncVersion` as the original string; the `Int` parse is a validation check only.
- **apply-advances**: A successful `apply` with a non-nil cursor MUST store that cursor; with a nil cursor it MUST leave the stored cursor unchanged.
- **apply-ignores-pull-only**: `apply` MUST accept changes for a resource in `pullOnlyResources`; only `stage` refuses them.

### InMemorySyncStore — local mutations and outbox

- **stage-pull-only**: `stage(_:)` MUST throw `SyncStoreFailure.pullOnlyResource(resource)` when `mutation.resource` is in `pullOnlyResources`, before checking registration.
- **stage-unknown-resource**: `stage(_:)` MUST throw `SyncStoreFailure.unknownResource(resource)` for an unregistered resource and MUST NOT create storage for it.
- **stage-optimistic-row**: `stage(_:)` MUST write the mirror row for `rowId` with `syncVersion` equal to the existing row's `syncVersion` (or `"0"` when there is no row), `deleted` = `type == .delete`, and `data` = `mutation.data`, or an empty dictionary when nil.
- **stage-new-op**: When no `pending` outbox entry exists for the same `(resource, rowId)`, `stage` MUST append a `pending` op with a fresh `SyncID.uuidV7()` opId, the mutation's `type` and `data`, and `baseVersion` equal to the pre-stage row's `syncVersion` (nil when there was no row).
- **stage-coalesce**: When a `pending` outbox entry exists for the same `(resource, rowId)`, `stage` MUST replace it in place, keeping its `opId`, `baseVersion` and queue position, and taking the new mutation's `type`.
- **coalesce-upsert-merge**: A coalesced upsert MUST carry the existing op's data merged with the new data, with the new value winning on a key collision; a nil side counts as empty.
- **coalesce-delete-nil**: A coalesced delete MUST carry nil data.
- **inflight-not-coalesced**: `stage` MUST NOT coalesce into an `inflight` entry; it MUST append a new op with a fresh opId instead.
- **pending-ops-fifo**: `pendingOps(limit:)` MUST return, in insertion order, at most `limit` ops whose status is `pending` or `inflight`.
- **pending-ops-marks-inflight**: `pendingOps(limit:)` MUST mark every op it returns `inflight`.
- **inflight-replay**: An `inflight` op MUST be returned again by later `pendingOps` calls, under the same opId, until `complete` resolves it.
- **pending-ops-limit**: A non-negative `limit` is a caller precondition. `pendingOps(limit:)` passes `limit` unchecked to `prefix`, which traps on a negative value; no error is thrown.

### InMemorySyncStore — push results

- **complete-unknown-op**: `complete(_:)` MUST skip, without error, any result whose `opId` matches no outbox entry.
- **complete-applied**: An `.applied` result MUST remove its outbox entry.
- **complete-adopt-version**: Before removing it, an `.applied` result with a `newVersion` that parses as an `Int` MUST set the mirror row's `syncVersion` to `newVersion` when that row exists.
- **complete-skip-unparseable**: An `.applied` result whose `newVersion` is nil, does not parse as an `Int`, or whose mirror row no longer exists MUST leave the row untouched and still remove the outbox entry.
- **complete-conflict**: A `.conflict` result MUST append `(opId, reason)` to `conflictLog`, remove the outbox entry, and leave the mirror row untouched.
- **complete-rejected**: A `.rejected` result MUST move the op from the outbox to the end of `quarantined`.
- **quarantine-never-pushed**: A quarantined op MUST never be returned by `pendingOps` again; a retry requires a fresh `stage(_:)`, which mints a new opId.

### InMemorySyncStore — reset and purge

- **resync-clears**: `resetForResync()` MUST clear every registered resource's mirror rows and set the cursor to nil.
- **resync-keeps-registrations**: `resetForResync()` MUST keep every registration and its schema version.
- **resync-keeps-outbox**: `resetForResync()` MUST leave the outbox, `quarantined` and `conflictLog` unchanged.
- **purge-deregisters**: `purgeResources(_:)` MUST remove each listed resource's mirror rows and registration.
- **purge-quarantines**: `purgeResources(_:)` MUST move every outbox entry (pending or inflight) for a purged resource to `quarantined`, preserving the survivors' relative order.
- **purge-keeps-cursor**: `purgeResources(_:)` MUST leave the stored cursor unchanged.
- **purge-unregistered-noop**: Purging a resource that was never registered MUST be a silent no-op that throws nothing.
- **purge-empty-noop**: `purgeResources([])` MUST return without changing any state.

### InMemorySyncStore — test conveniences

- **row-count**: `rowCount(resource:)` MUST return the number of non-deleted rows of a registered resource.
- **row-count-unknown**: `rowCount(resource:)` MUST throw `SyncStoreFailure.unknownResource(resource)` for a resource that is not registered, including one removed by `purgeResources`.
- **row-lookup**: `row(resource:id:)` MUST return the stored `Row`, tombstones included, or nil when the resource or row is absent.
- **pending-op-id**: `pendingOpId(resource:rowId:)` MUST return the opId of the first `pending` entry for `(resource, rowId)`, or nil, and MUST NOT change any entry's status.

### ScriptedSyncTransport

- **init-scripts**: `init(pulls:pushes:)` MUST seed the pull and push scripts, both defaulting to empty.
- **enqueue**: `enqueuePull(_:)` and `enqueuePush(_:)` MUST append one outcome to the end of the matching script.
- **pull-records-cursor**: `pull(cursor:limit:)` MUST append `cursor` to `pullCursors` before consuming any outcome, including on calls that then throw.
- **pull-scripted**: With a non-empty pull script, `pull` MUST remove the first outcome and return its response on `.success` or throw its `SyncTransportError` on `.failure`.
- **pull-default**: With an empty pull script, `pull` MUST return `SyncPullResponse(manifest: [], changes: [], cursor: <cursor.rawValue or "empty">, hasMore: false)`.
- **pull-ignores-limit**: `pull` MUST ignore `limit`.
- **push-records-request**: `push(_:)` MUST append the request to `pushedRequests` before consuming any outcome.
- **push-scripted**: With a non-empty push script, `push` MUST remove the first outcome and return its response or throw its error.
- **push-default**: With an empty push script, `push` MUST return one `SyncPushResult(opId:, status: .applied)` per request op, in op order, with no `newVersion`, and `watermark` `"0"`.
- **scripts-unvalidated**: `ScriptedSyncTransport` MUST return scripted responses verbatim, without checking them against the request (opIds, cursors or `deviceId`).

## Appearance

Not applicable — this is a pair of in-memory test fakes for the sync store and transport, not a visual component.

## States

Not applicable — this is a pair of in-memory test fakes for the sync store and transport, not a visual component.

## Accessibility

Not applicable — this is a pair of in-memory test fakes for the sync store and transport, not a visual component.

## Conformance Test Vectors

Store vectors start from `InMemorySyncStore()` after `prepare(resources: [SyncResource(resource: "personal.notes", schemaVersion: 1)])` unless noted; they are drawn from `InMemorySyncStoreTests` and `SyncEngineTests`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-engine-testing-001 | stage-new-op, pending-ops-fifo, complete-applied | Stage upsert r1 `{title: "offline"}`; `pendingOps(limit: 10)`; complete it `.applied` | One op of type `.upsert`; afterwards `pendingOps` returns empty |
| sync-engine-testing-002 | complete-adopt-version, stage-new-op | Stage upsert r1; complete `.applied` with `newVersion: "77"`; stage upsert r1 again | `row(r1).syncVersion == "77"`; the new op's `baseVersion == "77"` |
| sync-engine-testing-003 | complete-skip-unparseable, stage-optimistic-row | Stage upsert r1; complete `.applied` with `newVersion: "bogus"` | `row(r1).syncVersion == "0"`; outbox empty |
| sync-engine-testing-004 | stage-coalesce, coalesce-upsert-merge, pending-op-id | Apply r1 at syncVersion "3" (cursor c3); stage upsert `{title: "first"}`; capture `pendingOpId`; stage upsert `{body: "second"}` | One op; opId equals the captured id; `baseVersion == "3"`; data has title "first" and body "second" |
| sync-engine-testing-005 | coalesce-delete-nil | Stage upsert r1; stage delete r1 | One op, same opId, type `.delete`, data nil |
| sync-engine-testing-006 | inflight-not-coalesced, inflight-replay, pending-ops-marks-inflight | Stage upsert r1; `pendingOps`; stage upsert r1 again; `pendingOps` | Two ops with distinct opIds, one of them the first call's opId |
| sync-engine-testing-007 | stage-unknown-resource | Stage upsert on "unknown.resource" | Throws `unknownResource("unknown.resource")` |
| sync-engine-testing-008 | apply-unparseable-version | Apply one change with syncVersion "not-a-number" | Throws `invalidChange`; `rowCount` is 0 |
| sync-engine-testing-009 | apply-atomic | Apply `[good (syncVersion "1"), bad (syncVersion "not-a-number")]` advancing to c1 | Throws `invalidChange`; `row(good)` nil; `rowCount` 0; `cursor()` nil |
| sync-engine-testing-010 | apply-advances, resync-clears, resync-keeps-outbox | Stage delete r1; apply s1 at "5" to c5; `resetForResync()` | Cursor c5 and 1 row before reset; after reset cursor nil, 0 rows, 1 pending op |
| sync-engine-testing-011 | stage-pull-only | `InMemorySyncStore(pullOnlyResources: ["social.follows"])`, prepared; stage upsert on it | Throws `pullOnlyResource("social.follows")` |
| sync-engine-testing-012 | registrations-projection, prepare-upsert | Prepare "a.x" v1 and "b.y" v2 | `registrations() == ["a.x": 1, "b.y": 2]` |
| sync-engine-testing-013 | purge-deregisters, purge-quarantines, purge-keeps-cursor, row-count-unknown | Prepare a.x, b.y; apply a row in each to c1; stage upsert a.x/1; `purgeResources(["a.x"])` | b.y count 1; `rowCount(a.x)` throws `unknownResource`; no pending ops; `quarantined` resources `["a.x"]`; registrations `["b.y"]`; cursor c1 |
| sync-engine-testing-014 | purge-unregistered-noop | Prepare a.x, apply a row to c1; `purgeResources(["never.prepared"])` | No throw; a.x count 1; registrations `["a.x": 1]`; cursor c1 |
| sync-engine-testing-015 | complete-rejected, quarantine-never-pushed | Stage upsert r1; `pendingOps`; complete `.rejected` | `quarantined` holds the op; `pendingOps` empty |
| sync-engine-testing-016 | complete-conflict | Stage upsert r1; `pendingOps`; complete `.conflict` reason "stale" | `conflictLog` is `[(opId, "stale")]`; outbox empty; `row(r1)` unchanged |
| sync-engine-testing-017 | pull-scripted, pull-records-cursor | Transport scripted with pages c1 (hasMore true) then c2; engine `syncNow(.manual)` | `pullCursors` raw values `[nil, "c1"]` |
| sync-engine-testing-018 | pull-scripted, pull-default | Transport scripted `[.failure(.unauthorized)]`; call `pull(cursor: nil, limit: 10)` twice | First call throws `.unauthorized`; second returns cursor "empty", hasMore false; `pullCursors.count == 2` |
| sync-engine-testing-019 | push-default, push-records-request | Empty push script; `push(SyncPushRequest(deviceId: "d", ops: [op1, op2]))` | Results `[op1 .applied, op2 .applied]`, watermark "0"; `pushedRequests.count == 1` |
| sync-engine-testing-020 | enqueue, pull-scripted | `enqueuePull(.success(page c0))` after the script is drained; `pull` | Returns the enqueued page (cursor c0) |

## Edge Cases

- **Empty batch**: `apply([], advancingTo: c)` MUST store `c` and change no rows; with a nil cursor it MUST change nothing.
- **Sign-prefixed version**: A `syncVersion` such as `"+5"` or `"-5"` parses as an `Int`, so `apply` and `complete` MUST accept it even though the wire contract promises digits only.
- **Duplicate ids in one batch**: When a batch carries the same `(resource, id)` twice, the later change MUST win.
- **Delete with data**: A pulled or staged delete with non-nil data MUST store that data on the tombstoned row.
- **Upsert after a pending delete**: Coalescing an upsert into a pending delete MUST produce an upsert whose data is the new data (the delete's nil data counts as empty), under the original opId and baseVersion.
- **Stage over a pulled tombstone**: Staging an upsert for a row whose mirror entry is a tombstone MUST take that tombstone's `syncVersion` as `baseVersion`.
- **Pull overwrites an optimistic row**: `apply` MUST overwrite a locally staged row for the same id; the outbox op is unaffected.
- **Adoption after reset or purge**: An `.applied` result whose row was cleared by `resetForResync` or `purgeResources` MUST skip adoption and still remove the outbox entry.
- **Result for an unknown opId**: `complete` MUST skip it silently; the engine, not the store, detects the missing progress.
- **Duplicate results for one opId**: The second result MUST find no entry and be skipped.
- **Zero limit**: `pendingOps(limit: 0)` MUST return empty and mark nothing inflight.
- **Negative limit**: See pending-ops-limit; the call traps at runtime.
- **Duplicate descriptors in prepare**: The last descriptor's `schemaVersion` MUST win.
- **Empty prepare**: `prepare(resources: [])` MUST change nothing.
- **Concurrent calls**: Both fakes are actors, so concurrent calls MUST run one at a time; no call suspends inside its body, so no call interleaves with another.
- **Exhausted script**: A drained script MUST fall back to the default response rather than throwing; a test that expects a failure MUST enqueue it.
- **Cancellation and timeouts**: Neither fake checks task cancellation or applies a timeout; every call returns immediately.
- **Offline or unreachable server**: Not applicable to the store (no I/O); the transport simulates it only through a scripted `.failure(.transport(_))`.
- **Missing files**: Not applicable: neither fake touches the file system; all state is lost when the instance is released.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pullOnlyResources` | `Set<String>` | `[]` | `InMemorySyncStore.init` — resources `stage(_:)` refuses with `pullOnlyResource` |
| `pulls` | `[Outcome<SyncPullResponse>]` | `[]` | `ScriptedSyncTransport.init` — initial pull script, consumed FIFO |
| `pushes` | `[Outcome<SyncPushResponse>]` | `[]` | `ScriptedSyncTransport.init` — initial push script, consumed FIFO |

No environment variables, settings keys or injected dependencies are read. The opId generator `SyncID.uuidV7()` is called directly and cannot be injected.

## Deep Linking

Not applicable: neither fake exposes a URL or route; tests call their methods directly.

## Localization

The fakes have no localized strings. The only human-readable text is the hardcoded English `invalidChange` payload `"unparseable syncVersion: <value>"`; `SyncStoreFailure` has no `LocalizedError` conformance.

## Accessibility Options

Not applicable: the fakes have no visual surface, so no display accessibility option affects them.

## Feature Flags

Not applicable: no flag lookup appears in either source file.

## Analytics

Not applicable: neither fake emits analytics events.

## Privacy

- **Data collected**: Only the row payloads, ops and requests a test supplies.
- **Storage**: In actor memory only (`resourceStates`, `outbox`, `quarantined`, `conflictLog`, `pullCursors`, `pushedRequests`).
- **Transmission**: None; `ScriptedSyncTransport` makes no network call.
- **Retention**: Until the instance is released; nothing is persisted.

## Logging

Not applicable: neither source makes a log call; outcomes are observed through return values, thrown errors, `conflictLog`, `quarantined`, `pullCursors` and `pushedRequests`.

## Platform Notes

- **SwiftUI**: Source platform (`Sync/Testing/InMemorySyncStore.swift`, `Sync/Testing/ScriptedSyncTransport.swift`, compiled into the `AgenticToolkitSync` framework, not a test target). Both are `actor`s, so tests `await` even the synchronous conveniences. `SyncID.uuidV7()` supplies opIds; `Dictionary.merging(_:uniquingKeysWith:)` implements the coalescing merge. A SwiftUI preview can seed an `InMemorySyncStore` and a `ScriptedSyncTransport` to render sync UI with no backend.
- **Compose**: Write the store as a class guarding its maps with a `kotlinx.coroutines.sync.Mutex` (or confine it to `Dispatchers.Default.limitedParallelism(1)`) so `suspend` methods serialize like the actor. Use `LinkedHashMap` for rows and a `MutableList` for the outbox to keep FIFO order; stage `apply` into a copy and swap it in for atomicity. The transport becomes an `ArrayDeque<Result<T>>` per script. Test with `kotlinx-coroutines-test` `runTest`; `java.util.UUID` has no v7 generator, so port `SyncID`.
- **React/Web**: Single-threaded JS makes each synchronous method atomic without a lock, but async methods interleave across `await`, so keep method bodies free of `await` as the source does. Use `Map` (insertion-ordered) for rows and an array for the outbox; deep-copy the resource map with `structuredClone` before applying a batch. The transport is two arrays shifted per call. `Number.parseInt` accepts trailing garbage, so validate `syncVersion` with a digits-only check instead.
- **AppKit / UIKit**: The same Swift sources apply unchanged; the framework is Foundation-only, so AppKit and UIKit hosts and XCTest bundles use the fakes directly.
- **WinUI 3**: Write the store as a class whose `Task`-returning methods take a `SemaphoreSlim(1, 1)` (or keep bodies synchronous and use `lock`), with `Dictionary<string, ResourceState>` for rows and `List<OutboxEntry>` for the outbox; copy the dictionary before applying a batch to keep `apply` atomic. The transport holds two `Queue<Outcome<T>>` and returns `Task.FromResult` or `Task.FromException`. Record requests in `List<T>` exposed as `IReadOnlyList<T>`. Wire types use `System.Text.Json` with `JsonNode` in place of `JSONValue`. For the `syncVersion` check use `int.TryParse` with `NumberStyles.AllowLeadingSign` and `CultureInfo.InvariantCulture`, which matches Swift's `Int(_:)` (sign allowed, whitespace rejected); the default `NumberStyles.Integer` also accepts surrounding whitespace. `Guid.CreateVersion7()` (.NET 9) supplies opIds but does not guarantee same-millisecond ordering. A view model bound to `ObservableCollection` can read the fakes in XAML previews, but tests need no `INotifyPropertyChanged`.

## Design Decisions

### Fakes ship in the framework

**Decision**: The fakes live in the production `AgenticToolkitSync` target under `Sync/Testing/`, not in a test target.

**Rationale**: The source comment names this the toolkit convention (see `Core/Chat/MockChatSession.swift`), so host apps' tests and previews can use the same fakes as the toolkit's own tests.

**Approved**: pending

### Parity with GRDBSyncStore

**Decision**: `InMemorySyncStore` reproduces `GRDBSyncStore`'s atomic apply, `syncVersion` validation, coalescing, inflight replay, unparseable-`newVersion` skipping and unregistered-purge no-op.

**Rationale**: The doc comments say the fakes must not "lie" about the real store (sync fix-wave items p2a, p2o, A5, E3/F5), so engine tests run against the fake predict behavior on SQLite.

**Approved**: pending

### One entry for registration and rows

**Decision**: Schema version and rows are held in one `ResourceState` value per resource.

**Rationale**: The source comment says key presence IS the registration truth, replacing two dictionaries that had to be kept in step by hand.

**Approved**: pending

### Inflight ops are replayed, never coalesced

**Decision**: `pendingOps` marks ops inflight and returns them again; `stage` never edits an inflight op.

**Rationale**: A push that never completed must be retried under the same opId, because the server ledgers results per opId; editing an op already sent would change what that opId means.

**Approved**: pending

### Default transport responses

**Decision**: An empty script yields an empty pull echoing the cursor (or "empty") and an all-applied push.

**Rationale**: Tests script only the calls they care about; every other cycle step succeeds quietly.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

Each fake implements exactly one protocol seam (`SyncStore` or `SyncTransport`) with no I/O, and `InMemorySyncStoreTests` covers staging, coalescing, adoption, atomic apply, resync, purge and pull-only refusal, while `SyncEngineTests` exercises the transport. The fakes are deterministic apart from generated opIds, which tests capture rather than predict. Batches apply all-or-nothing and inflight ops replay under their original opId. Explicit error handling is partial because `pendingOps(limit:)` traps on a negative limit instead of reporting it, and `complete` silently skips results for unknown opIds by design.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the Apple `Sync/Testing` sources and `InMemorySyncStoreTests` |
