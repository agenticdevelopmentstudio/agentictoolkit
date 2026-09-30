<!-- leaf: implement-sync-engine/testing--test-vectors · source: sync-engine-testing.md -->

# Sync Engine Testing

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
