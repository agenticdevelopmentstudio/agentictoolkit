<!-- leaf: implement-sync-engine/sync-grdb--part-3 · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore — continued (part 3)

**Rules** (cite as `implement-sync-engine/sync-grdb--part-3#<slug>`):

- `pending-ops-select` MUST
- `pending-ops-mark-inflight` MUST
- `pending-ops-replay` MUST
- `pending-ops-shape` MUST
- `pending-ops-corrupt-type` MUST
- `complete-applied-delete` MUST
- `complete-applied-adopt` MUST
- `complete-applied-bad-version` MUST
- `complete-conflict-audit` MUST
- `complete-conflict-delete` MUST
- `complete-rejected` MUST
- `complete-unknown-op` MUST
- `complete-atomic` MUST
- `reset-mirrors` MUST
- `reset-preserves-outbox` MUST
- `purge-resources-empty` MUST
- `purge-resources-effect` MUST
- `purge-resources-keeps` MUST
- `purge-resources-unregistered` MUST
- `purge-identity-effect` MUST
- `purge-identity-projection` MUST
- `purge-identity-keeps` MUST
- `truncate-batched` MUST
- `rows-only` MUST
- `live-rows-unknown` MUST
- `live-rows-page` MUST
- `live-row-lookup` MUST
- `live-row-shape` MUST
- `live-rows-projection` MUST
- `registered-resources` MUST
- `status-shape` MUST
- `status-codable` MUST
- `durable-state` MUST
- `crash-replay` MUST
- `quarantine-retained` MUST
- `conflicts-retained` MUST
- `projection-sendable` MUST
- `projection-in-caller-txn` MUST
- `projection-create-idempotent` MUST
- `projection-mark-deleted-nil` SHOULD
- `projection-rows-shape` MUST
- `projection-upsert-default` MUST
- `projection-purge-default` MUST

### pendingOps

- **pending-ops-select**: `pendingOps(limit:)` MUST return at most `limit` ops whose status is `pending` or `inflight`, ordered by SQLite `rowid` (insertion order).
- **pending-ops-mark-inflight**: `pendingOps` MUST set every returned op's status to `inflight` in the same transaction that selects them.
- **pending-ops-replay**: An op already `inflight` MUST be returned again by later `pendingOps` calls until `complete` resolves it, with the same `op_id`.
- **pending-ops-shape**: Each returned `SyncPushOp` MUST carry `opId`, `resource`, `rowId`, `type`, `baseVersion` from the outbox row, and `data` set to the decoded payload, or nil when the payload is absent or decodes to an empty object.
- **pending-ops-corrupt-type**: `pendingOps` MUST throw `SyncStoreFailure.invalidChange("corrupt outbox type column: <value>")` when an outbox row's `type` is not `upsert` or `delete`, and the inflight marking MUST roll back.

### complete

- **complete-applied-delete**: For a `.applied` result, `complete` MUST delete the outbox row with that `op_id`.
- **complete-applied-adopt**: For a `.applied` result whose `newVersion` parses as an `Int`, `complete` MUST write that version onto the row's mirror `sync_version` (or through the projection's `setSyncVersion`) before deleting the outbox row, in the same transaction.
- **complete-applied-bad-version**: For a `.applied` result whose `newVersion` is present but does not parse as an `Int`, `complete` MUST skip the version adoption, MUST NOT throw, and MUST still delete the outbox row.
- **complete-conflict-audit**: For a `.conflict` result, `complete` MUST insert a `_sync_conflicts` row with the `op_id`, the outbox row's `resource` and `row_id` (NULL when the op is not in the outbox), the result's `reason`, and `resolved_at` `datetime('now')`.
- **complete-conflict-delete**: For a `.conflict` result, `complete` MUST delete the outbox row and MUST NOT change the mirror; adopting the server's row is the caller's job through `apply`.
- **complete-rejected**: For a `.rejected` result, `complete` MUST set the op's status to `quarantined` and increment `attempts` by 1, keeping the row.
- **complete-unknown-op**: A result whose `opId` has no outbox row MUST NOT throw; `.applied` and `.rejected` MUST change nothing, and `.conflict` MUST still write an audit row.
- **complete-atomic**: All results in one `complete` call MUST commit in one transaction.

### Recovery and purge paths

- **reset-mirrors**: `resetForResync()` MUST delete every row of every registered resource's mirror (through the projection's `truncate` for claimed resources) and delete the `_sync_state` row.
- **reset-preserves-outbox**: `resetForResync()` MUST leave `_sync_outbox`, `_sync_resources` and `_sync_conflicts` untouched.
- **purge-resources-empty**: `purgeResources([])` MUST return immediately without touching the database.
- **purge-resources-effect**: For each named resource, `purgeResources` MUST empty its mirror, set its `pending` and `inflight` outbox ops to `quarantined`, and delete its `_sync_resources` row.
- **purge-resources-keeps**: `purgeResources` MUST leave the cursor, already-`quarantined` ops and other resources untouched.
- **purge-resources-unregistered**: `purgeResources` MUST skip the mirror truncation of an unregistered resource silently, without throwing.
- **purge-identity-effect**: `purgeForIdentityChange()` MUST empty every registered mirror, delete the `_sync_state` row, and delete every `_sync_outbox` row whatever its status.
- **purge-identity-projection**: `purgeForIdentityChange()` MUST call the projection's `purgeIdentityState(in:)` in the same transaction.
- **purge-identity-keeps**: `purgeForIdentityChange()` MUST leave `_sync_resources` and `_sync_conflicts` untouched, so `stage` works for the next identity without a new `prepare`.
- **truncate-batched**: Every mirror truncation MUST filter the resources against `_sync_resources` first, then hand all claimed resources to the projection's `truncate(resources:in:)` in one call, then delete rows from each unclaimed resource's table.
- **rows-only**: Store operations MUST NOT drop a table or delete the database file; recovery only deletes rows.

### Read helpers

- **live-rows-unknown**: `liveRows` and `liveRow` MUST throw `SyncStoreFailure.unknownResource(resource)` when the resource is not in `_sync_resources`.
- **live-rows-page**: `liveRows(resource:limit:offset:)` MUST return the non-tombstoned rows (`deleted_at IS NULL`) ordered by `id`, skipping `offset` rows and returning at most `limit`; defaults are `limit` 100 and `offset` 0.
- **live-row-lookup**: `liveRow(resource:id:)` MUST return the row with that `id` when it is not tombstoned, and nil otherwise.
- **live-row-shape**: A JSON-mirror row MUST be returned as its decoded `data` object with an added `"id"` key set to the row's `id` column, which overrides any `"id"` key inside `data`.
- **live-rows-projection**: For a claimed resource, `liveRows` and `liveRow` MUST return the projection's `rows(resource:limit:offset:in:)` and `row(resource:id:in:)` results unchanged.
- **registered-resources**: `registeredResources()` MUST return the set of resource names in `_sync_resources`.
- **status-shape**: `status()` MUST return `GRDBSyncStoreStatus` with `cursor` (the stored cursor or nil), `outboxDepth` (count of `pending` plus `inflight` ops), `quarantinedDepth` (count of `quarantined` ops) and `conflictCount` (count of all `_sync_conflicts` rows).
- **status-codable**: `GRDBSyncStoreStatus` MUST be `Codable` and `Sendable` with the four fields named `cursor`, `outboxDepth`, `quarantinedDepth`, `conflictCount`.

### Persistence and durability

- **durable-state**: The cursor, registrations, mirror rows, outbox ops and conflict audit MUST persist in the database file across process restarts; the store keeps no in-memory copy.
- **crash-replay**: Ops marked `inflight` when the process dies MUST be returned again by the first `pendingOps` after restart.
- **quarantine-retained**: Quarantined ops MUST remain in `_sync_outbox` until `purgeForIdentityChange()`; the store offers no operation that retries or deletes one individually.
- **conflicts-retained**: `_sync_conflicts` rows MUST never be deleted by any store operation.

### Projection contract (`SyncMirrorProjection`)

- **projection-sendable**: A projection MUST conform to `Sendable`.
- **projection-in-caller-txn**: Every projection method MUST work on the connection it is handed and MUST NOT open its own transaction.
- **projection-create-idempotent**: `createTables(in:)` MUST be idempotent, because every `prepare` calls it.
- **projection-mark-deleted-nil**: `markDeleted` with `syncVersion: nil` (a local delete) SHOULD leave the stored version unchanged; the protocol doc states this as guidance, and the store relies on it so a later push can adopt the server version.
- **projection-rows-shape**: `rows` and `row` MUST return dictionaries that include an `"id"` key, matching the JSON mirror's return shape.
- **projection-upsert-default**: A projection that does not implement the `isFullRow:` overload of `upsert` MUST receive calls through the default, which forwards to `upsert(resource:id:syncVersion:data:in:)` and discards `isFullRow`.
- **projection-purge-default**: A projection that does not implement `purgeIdentityState(in:)` MUST get a default that does nothing.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `database` | `BoundedDatabase` | required | The WAL pool (or `:memory:` queue) holding every table; exposed read-only as `database` |
| `pullOnlyResources` | `Set<String>` | `[]` | Resources that `stage` refuses with `pullOnlyResource` |
| `projection` | `(any SyncMirrorProjection)?` | `nil` | Typed storage for the resources it claims; nil keeps every resource in JSON mirrors |
| `liveRows` `limit` | `Int` | `100` | Page size per call |
| `liveRows` `offset` | `Int` | `0` | Rows skipped per call |
| `BoundedDatabase` deadlines | `Duration` | read 10 s, write 60 s | Set on the injected database, not on the store |

No environment variables or settings keys are read.

## Privacy

- **Data collected**: The store persists whatever row data the host syncs (`[String: JSONValue]` payloads), the pull cursor, and conflict reasons; it adds nothing of its own.
- **Storage**: Everything lives unencrypted in the SQLite file at the `BoundedDatabase` path; the store applies no encryption and relies on the file's location and OS file protection.
- **Transmission**: The store performs no network I/O; outbox ops leave the device only when the caller pushes them.
- **Retention**: Mirror rows stay until a newer pull, `resetForResync`, `purgeResources` or `purgeForIdentityChange` removes them; tombstones stay indefinitely; quarantined ops stay until `purgeForIdentityChange`; `_sync_conflicts` rows (op id, resource, row id, reason) are never deleted, even across an identity change.

