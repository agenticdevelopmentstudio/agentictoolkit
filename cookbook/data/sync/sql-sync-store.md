---
id: 14ca2162-b5ec-48bb-95a0-90577e7c9810
title: SQL Sync Store
domain: agentictoolkit://cookbook/data/sync/sql-sync-store
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'SQLite-backed store implementation: JSON mirror tables, a coalescing
  outbox, a cursor and a conflicts audit, with optional typed mirror projections.'
platforms:
- swift
- macos
- ios
tags:
- sync
- offline
- persistence
- sqlite
depends-on:
- agentictoolkit://cookbook/data/sync/sync-engine
related:
- agentictoolkit://cookbook/data/sync/sync-engine
- agentictoolkit://cookbook/data/sync/offline-sync-client
references:
- packages/apple/AgenticToolkit/SyncGRDB/GRDBSyncStore.swift
- packages/apple/AgenticToolkit/SyncGRDB/SyncMirrorProjection.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncGRDBTests/GRDBSyncStoreTests.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncGRDBTests/SyncMirrorProjectionTests.swift
approved-by: ''
approved-date: ''
---

# SQL Sync Store

## Overview

This store is a SQLite-backed implementation of the store contract driven by
the sync engine (see [Sync Engine](agentictoolkit://cookbook/data/sync/sync-engine)).
It sits on a bounded, deadline-guarded write-ahead-logged connection pool and
keeps four bookkeeping tables plus one mirror table per registered resource:

- `_sync_state` — the single-row pull cursor.
- `_sync_resources` — the registered resource names and their schema versions.
- `_sync_outbox` — local mutations owed to the server, each `pending`, `inflight` or `quarantined`.
- `_sync_conflicts` — an append-only audit of conflicted pushes.
- one mirror table per resource — `(id, sync_version, deleted_at, data)` with the row's fields stored as a JSON blob in `data`.

An optional projection can claim a subset of resources and store them in typed
tables instead of the JSON mirror; every mirror-touching operation asks the
projection first and falls through to the JSON mirror for unclaimed resources.

Use it when a host needs the offline mirror and outbox to survive restarts.
Beyond the store contract it offers synchronous read helpers (`liveRows`,
`liveRow`, `registeredResources`, `status`) for a daemon or UI, and
transaction-joining variants of `prepare` and `stage` for a store layered on
top of it.

## Behavioral Requirements

### Concurrency and isolation

- **concurrency-safe-store**: The store MUST be safe to use concurrently from multiple callers; its internal state MUST NOT change after construction, and concurrent access MUST be serialized by the underlying connection pool.
- **serialized-operations**: Every store-mutating operation (`prepare`, `cursor`, `apply`, `stage`, `pendingOps`, `complete`, `resetForResync`, `registrations`, `purgeResources`, `purgeForIdentityChange`) MUST run through a single internal serialization point, so two such operations on the same store never execute at the same time.
- **single-transaction-operations**: Every such operation MUST perform all of its database work inside exactly one write transaction, so a failure anywhere in the operation leaves no partial effect.
- **concurrent-read-helpers**: `liveRows`, `liveRow`, `registeredResources` and `status` MUST be synchronous reads that bypass the serialization point, reading from a reader connection (or the writer connection when called during a write), so they MAY run concurrently with each other and with a mutating operation.
- **per-call-codecs**: The store MUST NOT share a JSON encoder or decoder between calls; each call that encodes or decodes builds its own, because a read may run on several pool connections at once.
- **no-cancellation**: Once an operation is queued it MUST run to completion or error; a cancellation requested after queuing MUST have no effect on it.
- **same-connection-variants**: The transaction-joining variants of `prepare` and `stage` MUST run on the caller-supplied connection without opening a transaction or going through the serialization point, so the caller's surrounding transaction commits or rolls back their effects together with its own.

### Resource names and mirror tables

- **table-name-charset**: The mirror-table-name mapping MUST raise an `unknownResource` error naming the resource when the resource is empty or contains any character outside lowercase `a`–`z`, digits `0`–`9`, underscore and period.
- **table-name-mapping**: The mirror-table-name mapping MUST return the resource with every `.` replaced by `_` (`personal.notes` → `personal_notes`).
- **table-name-chokepoint**: Every SQL statement that names a JSON mirror table MUST obtain the name through that one mapping, because SQL cannot bind identifiers and the name is interpolated into the SQL text.
- **projection-claim**: A resource MUST be routed to the projection only when a projection was supplied and its claimed-resources set contains the resource name; every other resource MUST use its JSON mirror table.

### prepare

- **prepare-bookkeeping**: `prepare` MUST create `_sync_state`, `_sync_resources`, `_sync_outbox` and `_sync_conflicts` if they do not exist.
- **prepare-projection-tables**: `prepare` MUST have the projection create its own tables on every call when a projection is supplied, even when the resource list is empty.
- **prepare-mirror-table**: For each unclaimed resource, `prepare` MUST create its mirror table if absent with columns `id TEXT PRIMARY KEY NOT NULL`, `sync_version INTEGER NOT NULL DEFAULT 0`, `deleted_at TEXT`, `data TEXT NOT NULL DEFAULT '{}'`.
- **prepare-no-mirror-for-claimed**: For a resource the projection claims, `prepare` MUST NOT create a JSON mirror table.
- **prepare-register**: For each resource, `prepare` MUST insert `(resource, schemaVersion)` into `_sync_resources`, or overwrite the stored `schema_version` if the resource is already registered.
- **prepare-idempotent**: Calling `prepare` twice with the same resources MUST succeed and leave existing mirror rows intact.
- **prepare-bad-name**: `prepare` MUST raise an `unknownResource` error for an unclaimed resource whose name fails the mirror-table-name mapping, and the whole call MUST roll back.

### cursor and registrations

- **cursor-bootstrap**: `cursor` MUST create the bookkeeping tables if absent before reading, so it returns nothing on a never-prepared store instead of raising an error.
- **cursor-read**: `cursor` MUST return the `cursor` value of the `_sync_state` row with `id = 1`, or nothing when that row or value is absent.
- **registrations-bootstrap**: `registrations` MUST create the bookkeeping tables if absent, so it returns an empty map on a never-prepared store.
- **registrations-map**: `registrations` MUST return every `_sync_resources` row as `resource → schema_version`.

### apply (pulled changes)

- **apply-atomic**: `apply`, given a batch of changes and a new cursor, MUST write every change in the batch and the new cursor in one transaction; if any change fails, no change and no cursor update MUST persist.
- **apply-unknown-resource**: `apply` MUST raise an `unknownResource` error for a change whose resource is not in `_sync_resources`.
- **apply-version-strict**: `apply` MUST raise an `invalidChange` error with message "unparseable syncVersion: <value>" when a change's `syncVersion` does not parse as an integer, and MUST NOT coerce it to 0.
- **apply-upsert-mirror**: For an unclaimed resource, an upsert change MUST insert or replace the row so that `sync_version` equals the parsed version, `deleted_at` is empty, and `data` is the JSON encoding of the change's data (an empty object when the data is absent).
- **apply-delete-mirror**: For an unclaimed resource, a delete change MUST insert or update the row so that `sync_version` equals the parsed version, `deleted_at` is the current timestamp, and `data` is `'{}'`; a delete for a row never seen MUST still create the tombstone.
- **apply-upsert-projection**: For a claimed resource, an upsert change MUST call the projection's upsert operation, marking the row as a full replacement (not a partial patch), with the data (an empty object when absent).
- **apply-delete-projection**: For a claimed resource, a delete change MUST call the projection's mark-deleted operation with the parsed version.
- **apply-cursor-optional**: When a cursor is supplied, `apply` MUST store it as the `_sync_state` row `id = 1`; when no cursor is supplied, the stored cursor MUST be left unchanged.
- **apply-order**: Changes in a batch MUST be applied in array order, so a later change for the same row overwrites an earlier one.

### stage (local mutations)

- **stage-pull-only-first**: `stage` MUST raise a `pullOnlyResource` error naming the resource when the resource is in the pull-only set, before any database work and before the registration check; the same-connection variant of `stage` MUST apply the same check first.
- **stage-unknown-resource**: `stage` MUST raise an `unknownResource` error when the resource is not in `_sync_resources`.
- **stage-atomic**: The mirror write and the outbox write of one `stage` call MUST commit together or not at all.
- **stage-base-version**: `stage` MUST read the row's current `sync_version` (from the projection's stored-version lookup for a claimed resource) before writing, and use it as the base version; a row not yet stored has no base version.
- **stage-upsert-mirror**: For an unclaimed resource, an upsert MUST set `deleted_at` empty and `data` to the JSON encoding of the mutation's data (an empty object when absent), leaving an existing row's `sync_version` unchanged and creating a new row with `sync_version` 0.
- **stage-mirror-patch**: NEEDS REVIEW: Not implemented in source. The JSON mirror replaces `data` wholesale with the staged patch while the outbox merges patches and the projection path treats a staged mutation as a deliberate partial patch, so fields absent from the patch vanish from `liveRow` until the next pull; whether the mirror should merge instead needs the sync owner to decide and a test asserting the intended local view.
- **stage-delete-mirror**: For an unclaimed resource, a delete MUST set `deleted_at` to the current timestamp on the existing row and MUST NOT change its `data` or `sync_version`; when the row does not exist, no mirror row MUST be created.
- **stage-upsert-projection**: For a claimed resource, an upsert MUST call the projection's upsert operation with the base version (0 when absent), the data (an empty object when absent), marking the row as a partial patch (not a full replacement).
- **stage-delete-projection**: For a claimed resource, a delete MUST call the projection's mark-deleted operation with no version.
- **stage-new-op**: When no `pending` outbox op exists for the same `(resource, rowId)`, `stage` MUST insert one with a freshly minted UUIDv7 `op_id`, the mutation's type, `base_version` equal to the base version as a decimal string (empty when absent), `payload` equal to the JSON encoding of the data (an empty object when absent), `status` `pending`, `attempts` 0, and `created_at` set to the current timestamp.
- **stage-coalesce**: When a `pending` op exists for the same `(resource, rowId)`, `stage` MUST update that op in place, keeping its `op_id` and its original `base_version`, and MUST NOT insert a second op.
- **stage-coalesce-upsert**: When coalescing an upsert, the op's type MUST become `upsert` and its `payload` MUST become the existing payload merged with the new data, the new value winning for a repeated key.
- **stage-coalesce-delete**: When coalescing a delete, the op's type MUST become `delete` and its `payload` MUST become an empty object.
- **stage-no-coalesce-inflight**: `stage` MUST NOT coalesce into an `inflight` or `quarantined` op; it MUST insert a new op with a freshly minted `op_id`.

### pendingOps

- **pending-ops-select**: `pendingOps`, given a limit, MUST return at most that many ops whose status is `pending` or `inflight`, ordered by insertion order.
- **pending-ops-mark-inflight**: `pendingOps` MUST set every returned op's status to `inflight` in the same transaction that selects them.
- **pending-ops-replay**: An op already `inflight` MUST be returned again by later `pendingOps` calls until `complete` resolves it, with the same `op_id`.
- **pending-ops-shape**: Each returned pending op MUST carry `opId`, `resource`, `rowId`, `type`, `baseVersion` from the outbox row, and `data` set to the decoded payload, or nothing when the payload is absent or decodes to an empty object.
- **pending-ops-corrupt-type**: `pendingOps` MUST raise an `invalidChange` error with message "corrupt outbox type column: <value>" when an outbox row's `type` is not `upsert` or `delete`, and the inflight marking MUST roll back.

### complete

- **complete-applied-delete**: For an applied result, `complete` MUST delete the outbox row with that `op_id`.
- **complete-applied-adopt**: For an applied result whose new version parses as an integer, `complete` MUST write that version onto the row's mirror `sync_version` (or through the projection's version setter) before deleting the outbox row, in the same transaction.
- **complete-applied-bad-version**: For an applied result whose new version is present but does not parse as an integer, `complete` MUST skip the version adoption, MUST NOT raise an error, and MUST still delete the outbox row.
- **complete-conflict-audit**: For a conflict result, `complete` MUST insert a `_sync_conflicts` row with the `op_id`, the outbox row's `resource` and `row_id` (empty when the op is not in the outbox), the result's reason, and `resolved_at` set to the current timestamp.
- **complete-conflict-delete**: For a conflict result, `complete` MUST delete the outbox row and MUST NOT change the mirror; adopting the server's row is the caller's job through `apply`.
- **complete-rejected**: For a rejected result, `complete` MUST set the op's status to `quarantined` and increment `attempts` by 1, keeping the row.
- **complete-unknown-op**: A result whose `opId` has no outbox row MUST NOT raise an error; applied and rejected results MUST change nothing, and a conflict result MUST still write an audit row.
- **complete-atomic**: All results in one `complete` call MUST commit in one transaction.

### Recovery and purge paths

- **reset-mirrors**: `resetForResync` MUST delete every row of every registered resource's mirror (through the projection's truncate operation for claimed resources) and delete the `_sync_state` row.
- **reset-preserves-outbox**: `resetForResync` MUST leave `_sync_outbox`, `_sync_resources` and `_sync_conflicts` untouched.
- **purge-resources-empty**: `purgeResources` given an empty list MUST return immediately without touching the database.
- **purge-resources-effect**: For each named resource, `purgeResources` MUST empty its mirror, set its `pending` and `inflight` outbox ops to `quarantined`, and delete its `_sync_resources` row.
- **purge-resources-keeps**: `purgeResources` MUST leave the cursor, already-`quarantined` ops and other resources untouched.
- **purge-resources-unregistered**: `purgeResources` MUST skip the mirror truncation of an unregistered resource silently, without raising an error.
- **purge-identity-effect**: `purgeForIdentityChange` MUST empty every registered mirror, delete the `_sync_state` row, and delete every `_sync_outbox` row whatever its status.
- **purge-identity-projection**: `purgeForIdentityChange` MUST call the projection's identity-purge operation in the same transaction.
- **purge-identity-keeps**: `purgeForIdentityChange` MUST leave `_sync_resources` and `_sync_conflicts` untouched, so `stage` works for the next identity without a new `prepare`.
- **truncate-batched**: Every mirror truncation MUST filter the resources against `_sync_resources` first, then hand all claimed resources to the projection's truncate operation in one call, then delete rows from each unclaimed resource's table.
- **rows-only**: Store operations MUST NOT drop a table or delete the database file; recovery only deletes rows.

### Read helpers

- **live-rows-unknown**: `liveRows` and `liveRow` MUST raise an `unknownResource` error when the resource is not in `_sync_resources`.
- **live-rows-page**: `liveRows`, given a resource, limit and offset, MUST return the non-tombstoned rows (`deleted_at` empty) ordered by `id`, skipping `offset` rows and returning at most `limit`; defaults are `limit` 100 and `offset` 0.
- **live-row-lookup**: `liveRow` MUST return the row with that `id` when it is not tombstoned, and nothing otherwise.
- **live-row-shape**: A JSON-mirror row MUST be returned as its decoded data object with an added `"id"` key set to the row's `id` column, which overrides any `"id"` key inside the data.
- **live-rows-projection**: For a claimed resource, `liveRows` and `liveRow` MUST return the projection's own row-listing and row-lookup results unchanged.
- **registered-resources**: `registeredResources` MUST return the set of resource names in `_sync_resources`.
- **status-shape**: `status` MUST return a status value with `cursor` (the stored cursor or nothing), `outboxDepth` (count of `pending` plus `inflight` ops), `quarantinedDepth` (count of `quarantined` ops) and `conflictCount` (count of all `_sync_conflicts` rows).
- **status-codable**: The status value MUST support standard structured encoding and be safe to pass across concurrent contexts, with the four fields named `cursor`, `outboxDepth`, `quarantinedDepth`, `conflictCount`.

### Persistence and durability

- **durable-state**: The cursor, registrations, mirror rows, outbox ops and conflict audit MUST persist in the database file across process restarts; the store keeps no in-memory copy.
- **crash-replay**: Ops marked `inflight` when the process dies MUST be returned again by the first `pendingOps` after restart.
- **quarantine-retained**: Quarantined ops MUST remain in `_sync_outbox` until `purgeForIdentityChange`; the store offers no operation that retries or deletes one individually.
- **conflicts-retained**: `_sync_conflicts` rows MUST never be deleted by any store operation.

### Projection contract

- **projection-sendable**: A projection MUST be safe to use across concurrent contexts.
- **projection-in-caller-txn**: Every projection operation MUST work on the connection it is handed and MUST NOT open its own transaction.
- **projection-create-idempotent**: The projection's table-creation operation MUST be idempotent, because every `prepare` calls it.
- **projection-mark-deleted-nil**: The mark-deleted operation, given no version (a local delete) SHOULD leave the stored version unchanged; the contract states this as guidance, and the store relies on it so a later push can adopt the server version.
- **projection-rows-shape**: The projection's row-listing and row-lookup operations MUST return objects that include an `"id"` key, matching the JSON mirror's return shape.
- **projection-upsert-default**: A projection that does not implement the full-row/partial-patch distinction for its upsert operation MUST receive calls through a default that forwards to a simpler upsert and discards that distinction.
- **projection-purge-default**: A projection that does not implement an identity-purge operation MUST get a default that does nothing.

## Appearance

Not applicable — this is a SQL-backed sync persistence store, not a visual component.

## States

Not applicable — this is a SQL-backed sync persistence store, not a visual component.

## Accessibility

Not applicable — this is a SQL-backed sync persistence store, not a visual component.

## Conformance Test Vectors

All vectors use a fresh file-backed database and a `personal.notes` resource at schema version 1, prepared first, unless stated otherwise. Projection vectors use a projection test double that claims `test.people` and stores it in a `people` table.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-grdb-001 | prepare-idempotent, prepare-mirror-table | `prepare` called twice with the notes resource | No error; `liveRows("personal.notes")` returns 0 rows |
| sync-grdb-002 | apply-atomic, apply-unknown-resource | `apply` with an upsert for personal.notes row a v1 and an upsert for unknown.table row x v2, advancing to cursor "c2" | Raises an error; `liveRows` returns 0 rows; `cursor` returns nothing |
| sync-grdb-003 | apply-version-strict | `apply` with an upsert for personal.notes row a whose syncVersion is "not-a-number", advancing to cursor "c1" | Raises an `invalidChange` error; 0 live rows |
| sync-grdb-004 | stage-atomic, stage-new-op, status-shape | `stage` an upsert for personal.notes row r1 with {title: "offline"} | 1 live row with title "offline"; `pendingOps(10)` returns 1 op with rowId r1; `status().outboxDepth` = 1 |
| sync-grdb-005 | complete-applied-delete, complete-rejected | Stage r1 and r2; `pendingOps(10)`; complete r1 applied, r2 rejected "invalid_data" | `pendingOps(10)` empty; `status().quarantinedDepth` = 1 |
| sync-grdb-006 | complete-applied-adopt, stage-base-version | Stage r1; `pendingOps`; complete applied with new version "77"; stage r1 again | Mirror `sync_version` of r1 = 77; the new op's `baseVersion` = "77" |
| sync-grdb-007 | complete-applied-bad-version | Stage r1; `pendingOps`; complete applied with new version "bogus" | Mirror `sync_version` of r1 stays 0; `pendingOps` empty |
| sync-grdb-008 | pending-ops-corrupt-type | Stage r1; set its outbox type to "bogus" directly; `pendingOps(10)` | Raises an `invalidChange` error |
| sync-grdb-009 | stage-coalesce, stage-coalesce-upsert | Apply r1 v3; stage r1 {title: "first"}; stage r1 {body: "second"} | 1 op, same `opId` as the first, `baseVersion` "3", data has title "first" and body "second" |
| sync-grdb-010 | stage-coalesce-delete | Stage r1 upsert {title: "first"}; stage r1 delete | 1 op, same `opId`, type delete, data nothing |
| sync-grdb-011 | stage-no-coalesce-inflight, pending-ops-mark-inflight | Stage r1; `pendingOps` (marks inflight); stage r1 {body: "second"}; `pendingOps` | 2 ops with distinct `opId`s, one equal to the first call's |
| sync-grdb-012 | pending-ops-select | Stage r1, r2, r3; `pendingOps(10)` | rowIds in order r1, r2, r3 |
| sync-grdb-013 | pending-ops-replay | Stage r1; `pendingOps(10)` twice | Both calls return the same `opId` list |
| sync-grdb-014 | stage-unknown-resource | `stage` an upsert for unknown.resource r1 | Raises an `unknownResource` error naming "unknown.resource" |
| sync-grdb-015 | live-rows-unknown | `liveRows("unknown.resource")`; `liveRow("unknown.resource", "r1")` | Each raises an `unknownResource` error naming "unknown.resource" |
| sync-grdb-016 | table-name-charset, table-name-mapping | Mirror-table-name mapping applied to "personal.notes; DROP TABLE _sync_state;--", "Personal.Notes", "", "personal.notes_v2" | First three raise an error; the fourth returns "personal_notes_v2" |
| sync-grdb-017 | apply-delete-mirror, reset-mirrors, reset-preserves-outbox | Apply s1 v3 at c3; apply s1 delete v4 at c4; stage "mine"; `resetForResync` | Live rows 0 before reset; after reset `cursor` returns nothing and `pendingOps` returns 1 op |
| sync-grdb-018 | purge-identity-effect, purge-identity-keeps | Apply s1 at c1; stage r1, r2; `pendingOps`; reject r2; `purgeForIdentityChange`; stage r3 | Before purge outboxDepth 1, quarantinedDepth 1; after: both 0, `cursor` returns nothing, 0 live rows, `registeredResources` = {personal.notes}; `pendingOps` returns only r3 |
| sync-grdb-019 | stage-pull-only-first | Store with pull-only resources ["social.follows"], prepared; stage social.follows r1 | Raises a `pullOnlyResource` error naming "social.follows" |
| sync-grdb-020 | registrations-map, purge-resources-effect, purge-resources-keeps | Prepare a.x@1, b.y@2; apply a row each at c1; stage a.x row 1; `purgeResources(["a.x"])` | Before: registrations {a.x:1, b.y:2}. After: b.y has 1 live row; `liveRows("a.x")` raises an error; `pendingOps` empty; quarantinedDepth 1; registrations {b.y}; cursor "c1" |
| sync-grdb-021 | purge-resources-unregistered | Prepare a.x@1; apply a.x row at c1; `purgeResources(["never.prepared"])` | No error; a.x has 1 live row; registrations {a.x:1}; cursor "c1" |
| sync-grdb-022 | projection-claim, prepare-no-mirror-for-claimed | Projected store; prepare test.people and test.other | Table `people` exists; `test_people` does not; `test_other` does |
| sync-grdb-023 | apply-upsert-projection, live-rows-projection | Projected store; apply test.people p1 v7 {name: "Ada"} | `liveRow("test.people","p1")` = {id: "p1", name: "Ada"}; `people.sync_version` = 7 |
| sync-grdb-024 | apply-delete-projection | Projected store; apply p1 v1, then delete p1 v2 | `liveRow` nothing; `liveRows` empty |
| sync-grdb-025 | stage-base-version, stage-upsert-projection | Projected store; apply p1 v9 {name: "Ada"}; stage p1 {name: "Grace"} | 1 op with `baseVersion` "9"; `people.name` for p1 = "Grace" |
| sync-grdb-026 | same-connection-variants | In-memory database; inside one write transaction: the same-connection `prepare`, insert people p1, the same-connection `stage` | Commits; `liveRow("test.people","p1")?["name"]` = "Ada" |
| sync-grdb-027 | reset-mirrors, truncate-batched | Projected store; apply p1; `resetForResync` | `liveRows("test.people")` empty |
| sync-grdb-028 | live-row-shape | Unprojected store; apply test.people p1 v3 {name: "Ada"} | Table `test_people` exists, `people` does not; `liveRow` = {id: "p1", name: "Ada"} |
| sync-grdb-029 | complete-conflict-audit, complete-conflict-delete | Stage r1; `pendingOps`; complete conflict reason "stale" | `pendingOps` empty; `status().conflictCount` = 1; r1's mirror data unchanged |
| sync-grdb-030 | cursor-bootstrap, registrations-bootstrap | Never-prepared store; `cursor`; `registrations` | nothing; empty map; neither raises an error |
| sync-grdb-031 | purge-resources-empty | `purgeResources([])` on a never-prepared store | Returns without error |

**stage-mirror-patch** has no vector because its intended behavior is the open question the requirement text describes.

## Edge Cases

- **Never-prepared store**: `cursor` MUST return nothing and `registrations` MUST return an empty map (both bootstrap the schema); `status`, `registeredResources`, `liveRows` and `liveRow` MUST surface the underlying database's "no such table" error, because they read on the pool without bootstrapping.
- **Empty batch**: `apply` with an empty change list and a cursor `c` MUST store `c` with no row changes; `apply` with an empty change list and no cursor MUST change nothing.
- **Change with no data**: an upsert MUST store `'{}'` as `data`; a staged upsert with no data MUST store and enqueue an empty object.
- **Negative or oversized syncVersion**: `apply` MUST accept any string the standard integer parser accepts, including a leading `+` or `-`; a value outside the 64-bit range MUST raise an `invalidChange` error.
- **Local delete of a row never stored**: MUST create no mirror row, and MUST still enqueue a delete op with an empty `base_version`.
- **Upsert coalesced onto a pending delete**: the op MUST become an upsert with payload `{}` merged with the new data, keeping the original `op_id` and `base_version`.
- **Stage while the row's op is inflight**: a new op MUST be inserted carrying the mirror's current `sync_version`, which is still the pre-push version until `complete` adopts the server's; how the server treats that base version belongs to the server's sync backend.
- **`pendingOps` with limit 0**: MUST return no ops and mark nothing inflight.
- **Negative `pendingOps` limit**: MUST return every `pending` and `inflight` op and mark them all inflight, because a negative limit is treated as no limit; the store does not validate the limit.
- **Negative `liveRows` limit**: MUST return every live row from `offset`, for the same reason; capping the limit is documented as the caller's job (a host's listing endpoint).
- **Undecodable outbox payload or mirror data**: decoding MUST raise a decoding error out of `pendingOps`, `liveRows` or `liveRow`; `pendingOps` rolls back its inflight marking.
- **Result for an unknown opId**: applied and rejected results MUST be silent no-ops; a conflict result MUST write an audit row with an empty `resource` and `row_id`.
- **Applied result with no new version**: MUST delete the outbox row and leave `sync_version` unchanged.
- **Projected resource with an invalid name**: MUST NOT be validated by the mirror-table-name mapping, because claimed resources never name a JSON mirror table.
- **Purge of a mix of registered and unregistered resources**: MUST truncate only the registered ones, but MUST run the quarantine and deregistration statements for every named resource (no-ops for unknown ones).
- **Concurrent mutating calls**: MUST execute one at a time in submission order.
- **Concurrent read during a mutating write**: MUST see the last committed state (a consistent snapshot), never a half-applied batch.
- **Nested use from inside the caller's write**: calling the ordinary `stage` from inside the caller's own write transaction would deadlock the writer; the caller MUST use the same-connection variant there, as its documentation states.
- **Database deadline or lock timeout**: the underlying bounded database MUST eject an operation that exceeds its read or write deadline (10 s and 60 s by default) with a deadline-exceeded error, and fail a write that waits on a lock longer than its busy timeout (5 s by default); the store re-raises either error and its transaction rolls back.
- **Disk full or I/O error**: the underlying database error MUST propagate to the caller and the transaction MUST roll back.
- **Cancellation**: a cancelled caller awaiting a mutating operation MUST still see the operation run to completion.
- **Offline / unreachable server**: not applicable to this component; it performs no network I/O, and offline edits accumulate in the outbox until the engine pushes them.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `database` | database handle | required | The pool (or in-memory queue) holding every table; exposed read-only |
| `pullOnlyResources` | set of strings | `[]` | Resources that `stage` refuses with a `pullOnlyResource` error |
| `projection` | optional projection | none | Typed storage for the resources it claims; absent keeps every resource in JSON mirrors |
| `liveRows` `limit` | integer | `100` | Page size per call |
| `liveRows` `offset` | integer | `0` | Rows skipped per call |
| Database deadlines | duration | read 10 s, write 60 s | Set on the injected database, not on the store |

No environment variables or settings keys are read.

## Deep Linking

Not applicable: this store exposes no URL or route; it is called only through its host-language API.

## Localization

Not applicable to users: the store has no localized strings. Its only text is developer-facing and hardcoded English, carried in `invalidChange` error payloads ("unparseable syncVersion: <value>", "corrupt outbox type column: <value>"); a host that shows these to users must map them itself.

## Accessibility Options

Not applicable: the store has no visual surface, so no display accessibility option affects it.

## Feature Flags

Not applicable: no flag lookup appears in the sources; the nearest controls, `pullOnlyResources` and `projection`, are init parameters.

## Analytics

Not applicable: the store emits no analytics; `status` is a local snapshot for the host.

## Privacy

- **Data collected**: The store persists whatever row data the host syncs (JSON object payloads), the pull cursor, and conflict reasons; it adds nothing of its own.
- **Storage**: Everything lives unencrypted in the SQLite file at its configured path; the store applies no encryption and relies on the file's location and OS file protection.
- **Transmission**: The store performs no network I/O; outbox ops leave the device only when the caller pushes them.
- **Retention**: Mirror rows stay until a newer pull, `resetForResync`, `purgeResources` or `purgeForIdentityChange` removes them; tombstones stay indefinitely; quarantined ops stay until `purgeForIdentityChange`; `_sync_conflicts` rows (op id, resource, row id, reason) are never deleted, even across an identity change.

## Logging

Not applicable: the sources make no log call; every failure is raised to the caller, and bookkeeping is observable through `status`.

## Platform Notes

- **SwiftUI**: Source platform (`SyncGRDB/GRDBSyncStore.swift`, `SyncGRDB/SyncMirrorProjection.swift`). The store uses GRDB (`Database`, `Row`, `StatementArguments`) through `BoundedDatabase`, a private serial `DispatchQueue` bridged to async with `withCheckedThrowingContinuation`, `JSONEncoder`/`JSONDecoder` built per call, and `SyncID.uuidV7()` for op ids. A SwiftUI host reads `liveRows` or `status()` from a model refreshed on `SyncEngine` events; GRDB's `ValueObservation` on the mirror table is the natural live-update source.
- **Compose**: Start from Room or SQLDelight on the Android SQLite driver with WAL enabled (`enableWriteAheadLogging`). Run async operations on `Dispatchers.IO.limitedParallelism(1)` inside `withTransaction`/`transaction {}`; keep the table-name allow-list check because Room's `@RawQuery` and SQLDelight dynamic SQL also cannot bind identifiers. Store `data` as a `kotlinx.serialization` `JsonObject` string; port `SyncMirrorProjection` as an interface taking a `SupportSQLiteDatabase`.
- **React/Web**: Start from IndexedDB (via `idb`) or SQLite-WASM (`@sqlite.org/sqlite-wasm` with OPFS). IndexedDB replaces tables with object stores — one per resource plus `outbox`, `state`, `resources`, `conflicts` — and a single `readwrite` transaction over all touched stores gives the same atomicity; `rowid` order becomes an auto-increment key. JS is single-threaded, so the serial queue becomes a promise chain; there are no identifiers to inject with IndexedDB, but a SQLite-WASM port keeps the allow-list.
- **AppKit / UIKit**: The same Swift sources apply unchanged; the target depends only on Foundation, GRDB and the toolkit's `Database` and `Sync` modules. Place the database file under Application Support and, on iOS, set `FileProtectionType.completeUntilFirstUserAuthentication` so a background sync can open it.
- **WinUI 3**: Start from `Microsoft.Data.Sqlite` with `PRAGMA journal_mode=WAL`, one writer `SqliteConnection` plus pooled readers, and the file under `Windows.Storage.ApplicationData.Current.LocalFolder`. Serialise async operations with a `SemaphoreSlim(1, 1)` and run each inside `connection.BeginTransaction()`, exposing `Task`-returning `async` methods; the synchronous read helpers use their own reader connection. `System.Text.Json` `JsonObject`/`JsonNode` replaces `[String: JSONValue]` for `data` and payloads; `JsonSerializer.Serialize` replaces the per-call encoder (`JsonSerializerOptions` is thread-safe once frozen, so sharing one is fine in .NET). `SqliteCommand` parameters cannot bind table names either, so keep the lowercase/digit/underscore/period allow-list before interpolating. Op ids need a monotonic UUIDv7 port (`Guid.CreateVersion7()` lacks same-millisecond ordering). Cancellation differs: .NET APIs take a `CancellationToken`, and passing one would let a queued operation abort, which the source never does. A UI observing `status()` marshals updates through `DispatcherQueue.TryEnqueue` into an `INotifyPropertyChanged` view model; mirror rows for a list bind through `ObservableCollection<T>`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/SyncGRDB/` |

## Design Decisions

### Coalesce into a pending op, never an inflight one

**Decision**: A second local edit to a row with a `pending` op updates that op in place, keeping its `op_id` and original `base_version`; an `inflight` op is never modified.

**Rationale**: The `stage` doc comment (sync fix-wave item p2a) records that two ops with the same base version make the server apply the first and stale-conflict the second, silently dropping the newer edit. An inflight op may already be at the server, and its replay under the same `op_id` must carry the same content.

**Approved**: pending

### Strict parsing on pull, lenient on completion

**Decision**: An unparseable `syncVersion` in `apply` throws `invalidChange`, but an unparseable `newVersion` in `complete` is skipped silently while the outbox row is still deleted.

**Rationale**: The source comments explain that coercing to 0 would corrupt version ordering, so `apply` fails loudly; but throwing inside `complete` would roll back the outbox deletion and wedge the op on replay even though the server already applied it.

**Approved**: pending

### Inflight ops are replayed until completed

**Decision**: `pendingOps` returns `inflight` ops again on every call.

**Rationale**: The `pendingOps` doc comment states that replaying the same opIds after a crash or an unfinished round-trip is covered by the server contract's idempotency guarantee, so re-sending is safe and nothing is stranded.

**Approved**: pending

### Identity change clears the outbox; resync does not

**Decision**: `resetForResync` keeps every outbox op; `purgeForIdentityChange` deletes all of them, including quarantined ones, and asks the projection to drop its local-only state.

**Rationale**: The `purgeForIdentityChange` doc comment explains that a resync keeps the same identity, which still owes the server its queued edits, while pushing a departing identity's ops under new credentials would misattribute them; `MarkdownProjection`'s sidecar outbox is the cited case for `purgeIdentityState`.

**Approved**: pending

### Registrations and the conflict audit survive every purge

**Decision**: No purge path deletes `_sync_conflicts`, and only `purgeResources` deletes registrations.

**Rationale**: The doc comments call registrations app-level rather than per-identity state (so the next identity need not re-`prepare`), and call the conflict audit a historical record never read back into a sync decision.

**Approved**: pending

### Offset pagination on the mirror

**Decision**: `liveRows` pages with `LIMIT`/`OFFSET` ordered by `id`.

**Rationale**: The `liveRows` doc comment says the mirror shadows the backend's own offset/limit REST contract because the daemon is a transparent proxy; the `O(offset)` cost is bounded by callers capping `limit` (`MirrorServer`'s `listLimit`, 200).

**Approved**: pending

### Projections see a whole purge batch at once

**Decision**: Every truncation hands all claimed resources to `truncate(resources:in:)` in one call.

**Rationale**: The `deleteMirrorRows` comment explains that a projection with foreign keys between its own tables can only tell a legal whole-family purge from an orphaning partial one by seeing the whole batch.

**Approved**: pending

### SyncMirrorProjection

**Decision**: Typed storage is opt-in per resource through a projection, and the `isFullRow:` and `purgeIdentityState` requirements have defaults.

**Rationale**: The protocol doc says the JSON mirror survives schema evolution without migrations and is the right default, while indexed or foreign-keyed local storage needs real columns; the defaults keep projections written before those requirements existed source-compatible.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [encryption-at-rest](agenticdevelopercookbook://compliance/privacy-and-data#encryption-at-rest) | failed | Privacy And Data |
| [data-retention-policy](agenticdevelopercookbook://compliance/privacy-and-data#data-retention-policy) | partial | Privacy And Data |

Storage is behind the `SyncStore` and `SyncMirrorProjection` protocols, and `GRDBSyncStoreTests` plus `SyncMirrorProjectionTests` cover atomicity, coalescing, replay, every purge path and projection routing. Every operation is a single transaction, inflight ops replay after a crash, `prepare` is idempotent, `BoundedDatabase` deadlines bound every call, and `status()` exposes outbox, quarantine and conflict depth. Resource names are allow-listed before they reach SQL, and every value is a bound parameter. Explicit error handling is partial because a completion for an unknown op id is silently ignored and an unparseable `newVersion` is skipped without a signal. Data integrity is partial because a staged upsert replaces the JSON mirror's whole `data` blob while the outbox merges patches, the open question on stage-mirror-patch. Encryption at rest fails because the SQLite file is written unencrypted. Data retention is partial because the conflict audit and tombstones are never pruned, even across an identity change.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/sync/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the Apple `SyncGRDB` sources, `GRDBSyncStoreTests` and `SyncMirrorProjectionTests` |
