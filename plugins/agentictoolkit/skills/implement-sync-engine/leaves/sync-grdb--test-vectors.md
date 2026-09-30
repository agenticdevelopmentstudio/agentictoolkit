<!-- leaf: implement-sync-engine/sync-grdb--test-vectors · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore

## Conformance Test Vectors

All vectors use a fresh file-backed `BoundedDatabase` and `notes = SyncResource(resource: "personal.notes", schemaVersion: 1)` prepared first, as `GRDBSyncStoreTests` does, unless stated otherwise. Projection vectors use the `TestProjection` of `SyncMirrorProjectionTests`, which claims `test.people` and stores it in a `people` table.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-grdb-001 | prepare-idempotent, prepare-mirror-table | `prepare([notes])` twice | No error; `liveRows("personal.notes")` returns 0 rows |
| sync-grdb-002 | apply-atomic, apply-unknown-resource | `apply([upsert personal.notes a v1, upsert unknown.table x v2], advancingTo: "c2")` | Throws; `liveRows` returns 0 rows; `cursor()` is nil |
| sync-grdb-003 | apply-version-strict | `apply([upsert personal.notes a syncVersion "not-a-number"], advancingTo: "c1")` | Throws `SyncStoreFailure.invalidChange`; 0 live rows |
| sync-grdb-004 | stage-atomic, stage-new-op, status-shape | `stage(upsert personal.notes r1 {title: "offline"})` | 1 live row with title "offline"; `pendingOps(10)` returns 1 op with rowId r1; `status().outboxDepth` = 1 |
| sync-grdb-005 | complete-applied-delete, complete-rejected | Stage r1 and r2; `pendingOps(10)`; complete r1 `.applied`, r2 `.rejected` "invalid_data" | `pendingOps(10)` empty; `status().quarantinedDepth` = 1 |
| sync-grdb-006 | complete-applied-adopt, stage-base-version | Stage r1; `pendingOps`; complete `.applied` newVersion "77"; stage r1 again | Mirror `sync_version` of r1 = 77; the new op's `baseVersion` = "77" |
| sync-grdb-007 | complete-applied-bad-version | Stage r1; `pendingOps`; complete `.applied` newVersion "bogus" | Mirror `sync_version` of r1 stays 0; `pendingOps` empty |
| sync-grdb-008 | pending-ops-corrupt-type | Stage r1; set its outbox `type` to "bogus" directly; `pendingOps(10)` | Throws `SyncStoreFailure.invalidChange` |
| sync-grdb-009 | stage-coalesce, stage-coalesce-upsert | Apply r1 v3; stage r1 {title: "first"}; stage r1 {body: "second"} | 1 op, same `opId` as the first, `baseVersion` "3", data has title "first" and body "second" |
| sync-grdb-010 | stage-coalesce-delete | Stage r1 upsert {title: "first"}; stage r1 `.delete` | 1 op, same `opId`, `type` `.delete`, `data` nil |
| sync-grdb-011 | stage-no-coalesce-inflight, pending-ops-mark-inflight | Stage r1; `pendingOps` (marks inflight); stage r1 {body: "second"}; `pendingOps` | 2 ops with distinct `opId`s, one equal to the first call's |
| sync-grdb-012 | pending-ops-select | Stage r1, r2, r3; `pendingOps(10)` | rowIds in order r1, r2, r3 |
| sync-grdb-013 | pending-ops-replay | Stage r1; `pendingOps(10)` twice | Both calls return the same `opId` list |
| sync-grdb-014 | stage-unknown-resource | `stage(upsert unknown.resource r1)` | Throws `SyncStoreFailure.unknownResource("unknown.resource")` |
| sync-grdb-015 | live-rows-unknown | `liveRows("unknown.resource")`; `liveRow("unknown.resource", "r1")` | Each throws `SyncStoreFailure.unknownResource("unknown.resource")` |
| sync-grdb-016 | table-name-charset, table-name-mapping | `mirrorTableName` of "personal.notes; DROP TABLE _sync_state;--", "Personal.Notes", "", "personal.notes_v2" | First three throw; the fourth returns "personal_notes_v2" |
| sync-grdb-017 | apply-delete-mirror, reset-mirrors, reset-preserves-outbox | Apply s1 v3 at c3; apply s1 `.delete` v4 at c4; stage "mine"; `resetForResync()` | Live rows 0 before reset; after reset `cursor()` nil and `pendingOps` returns 1 op |
| sync-grdb-018 | purge-identity-effect, purge-identity-keeps | Apply s1 at c1; stage r1, r2; `pendingOps`; reject r2; `purgeForIdentityChange()`; stage r3 | Before purge outboxDepth 1, quarantinedDepth 1; after: both 0, `cursor()` nil, 0 live rows, `registeredResources()` = {personal.notes}; `pendingOps` returns only r3 |
| sync-grdb-019 | stage-pull-only-first | Store with `pullOnlyResources: ["social.follows"]`, prepared; stage social.follows r1 | Throws `SyncStoreFailure.pullOnlyResource("social.follows")` |
| sync-grdb-020 | registrations-map, purge-resources-effect, purge-resources-keeps | Prepare a.x@1, b.y@2; apply a row each at c1; stage a.x row 1; `purgeResources(["a.x"])` | Before: registrations {a.x:1, b.y:2}. After: b.y has 1 live row; `liveRows("a.x")` throws; `pendingOps` empty; quarantinedDepth 1; registrations {b.y}; cursor "c1" |
| sync-grdb-021 | purge-resources-unregistered | Prepare a.x@1; apply a.x row at c1; `purgeResources(["never.prepared"])` | No error; a.x has 1 live row; registrations {a.x:1}; cursor "c1" |
| sync-grdb-022 | projection-claim, prepare-no-mirror-for-claimed | Projected store; prepare test.people and test.other | Table `people` exists; `test_people` does not; `test_other` does |
| sync-grdb-023 | apply-upsert-projection, live-rows-projection | Projected store; apply test.people p1 v7 {name: "Ada"} | `liveRow("test.people","p1")` = {id: "p1", name: "Ada"}; `people.sync_version` = 7 |
| sync-grdb-024 | apply-delete-projection | Projected store; apply p1 v1, then `.delete` p1 v2 | `liveRow` nil; `liveRows` empty |
| sync-grdb-025 | stage-base-version, stage-upsert-projection | Projected store; apply p1 v9 {name: "Ada"}; stage p1 {name: "Grace"} | 1 op with `baseVersion` "9"; `people.name` for p1 = "Grace" |
| sync-grdb-026 | in-conn-no-queue | `:memory:` database; inside one `write`: `prepare(resources:in:)`, insert people p1, `stage(_:in:)` | Commits; `liveRow("test.people","p1")?["name"]` = "Ada" |
| sync-grdb-027 | reset-mirrors, truncate-batched | Projected store; apply p1; `resetForResync()` | `liveRows("test.people")` empty |
| sync-grdb-028 | live-row-shape | Unprojected store; apply test.people p1 v3 {name: "Ada"} | Table `test_people` exists, `people` does not; `liveRow` = {id: "p1", name: "Ada"} |
| sync-grdb-029 | complete-conflict-audit, complete-conflict-delete | Stage r1; `pendingOps`; complete `.conflict` reason "stale" | `pendingOps` empty; `status().conflictCount` = 1; r1's mirror `data` unchanged |
| sync-grdb-030 | cursor-bootstrap, registrations-bootstrap | Never-prepared store; `cursor()`; `registrations()` | nil; `[:]`; neither throws |
| sync-grdb-031 | purge-resources-empty | `purgeResources([])` on a never-prepared store | Returns without error |

Vectors 001–021 come from `GRDBSyncStoreTests` and 022–028 from `SyncMirrorProjectionTests`; 029–031 are derived from the source (`complete`, `cursor`, `registrations`, `purgeResources`) with no existing test. **stage-mirror-patch** has no vector because its intended behavior is the open question on stage-mirror-patch.
