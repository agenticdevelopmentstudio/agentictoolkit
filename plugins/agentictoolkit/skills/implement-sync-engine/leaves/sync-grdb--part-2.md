<!-- leaf: implement-sync-engine/sync-grdb--part-2 · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore — continued (part 2)

**Rules** (cite as `implement-sync-engine/sync-grdb--part-2#<slug>`):

- `sendable-store` MUST
- `async-serial-queue` MUST
- `async-single-transaction` MUST
- `sync-reads-on-pool` MUST
- `per-call-codecs` MUST
- `no-cancellation` MUST
- `in-conn-no-queue` MUST
- `table-name-charset` MUST
- `table-name-mapping` MUST
- `table-name-chokepoint` MUST
- `projection-claim` MUST
- `prepare-bookkeeping` MUST
- `prepare-projection-tables` MUST
- `prepare-mirror-table` MUST
- `prepare-no-mirror-for-claimed` MUST
- `prepare-register` MUST
- `prepare-idempotent` MUST
- `prepare-bad-name` MUST
- `cursor-bootstrap` MUST
- `cursor-read` MUST
- `registrations-bootstrap` MUST
- `registrations-map` MUST
- `apply-atomic` MUST
- `apply-unknown-resource` MUST
- `apply-version-strict` MUST
- `apply-upsert-mirror` MUST
- `apply-delete-mirror` MUST
- `apply-upsert-projection` MUST
- `apply-delete-projection` MUST
- `apply-cursor-optional` MUST
- `apply-order` MUST
- `stage-pull-only-first` MUST
- `stage-unknown-resource` MUST
- `stage-atomic` MUST
- `stage-base-version` MUST
- `stage-upsert-mirror` MUST
- `stage-delete-mirror` MUST
- `stage-upsert-projection` MUST
- `stage-delete-projection` MUST
- `stage-new-op` MUST
- `stage-coalesce` MUST
- `stage-coalesce-upsert` MUST
- `stage-coalesce-delete` MUST
- `stage-no-coalesce-inflight` MUST

## Behavioral Requirements

### Isolation and threading

- **sendable-store**: `GRDBSyncStore` MUST be safe to share across tasks; it is declared `final class … @unchecked Sendable`, every stored property is a `let`, and its concurrent use is serialised by the `BoundedDatabase` pool.
- **async-serial-queue**: Every `async` operation (`prepare(resources:)`, `cursor`, `apply`, `stage(_:)`, `pendingOps`, `complete`, `resetForResync`, `registrations`, `purgeResources`, `purgeForIdentityChange`) MUST run its body on one private serial queue, so two async operations on the same store never execute at the same time.
- **async-single-transaction**: Every `async` operation MUST perform all of its database work inside exactly one write transaction, so a failure anywhere in the operation leaves no partial effect.
- **sync-reads-on-pool**: `liveRows`, `liveRow`, `registeredResources` and `status` MUST be synchronous, MUST NOT use the serial queue, and MUST read from a reader connection (or from the writer connection when called inside a write), so they MAY run concurrently with each other and with an async write.
- **per-call-codecs**: The store MUST NOT share a JSON encoder or decoder between calls; each call that encodes or decodes builds its own, because a read may run on several pool connections at once.
- **no-cancellation**: Async operations MUST NOT observe task cancellation; once queued, the body runs to completion or error.
- **in-conn-no-queue**: `prepare(resources:in:)` and `stage(_:in:)` MUST run on the caller-supplied connection without opening a transaction or hopping to the queue, so the caller's surrounding transaction commits or rolls back their effects together with its own.

### Resource names and mirror tables

- **table-name-charset**: `mirrorTableName(for:)` MUST throw `SyncStoreFailure.unknownResource(resource)` when the resource is empty or contains any character outside lowercase `a`–`z`, digits `0`–`9`, underscore and period.
- **table-name-mapping**: `mirrorTableName(for:)` MUST return the resource with every `.` replaced by `_` (`personal.notes` → `personal_notes`).
- **table-name-chokepoint**: Every SQL statement that names a JSON mirror table MUST obtain the name through `mirrorTableName(for:)`, because SQLite cannot bind identifiers and the name is interpolated into the SQL text.
- **projection-claim**: A resource MUST be routed to the projection only when a projection was supplied and its `resources` set contains the resource name; every other resource MUST use its JSON mirror table.

### prepare

- **prepare-bookkeeping**: `prepare(resources:)` MUST create `_sync_state`, `_sync_resources`, `_sync_outbox` and `_sync_conflicts` if they do not exist.
- **prepare-projection-tables**: `prepare` MUST call the projection's `createTables(in:)` on every call when a projection is supplied, even when `resources` is empty.
- **prepare-mirror-table**: For each unclaimed resource, `prepare` MUST create its mirror table if absent with columns `id TEXT PRIMARY KEY NOT NULL`, `sync_version INTEGER NOT NULL DEFAULT 0`, `deleted_at TEXT`, `data TEXT NOT NULL DEFAULT '{}'`.
- **prepare-no-mirror-for-claimed**: For a resource the projection claims, `prepare` MUST NOT create a JSON mirror table.
- **prepare-register**: For each resource, `prepare` MUST insert `(resource, schemaVersion)` into `_sync_resources`, or overwrite the stored `schema_version` if the resource is already registered.
- **prepare-idempotent**: Calling `prepare` twice with the same resources MUST succeed and leave existing mirror rows intact.
- **prepare-bad-name**: `prepare` MUST throw `SyncStoreFailure.unknownResource` for an unclaimed resource whose name fails `mirrorTableName(for:)`, and the whole call MUST roll back.

### cursor and registrations

- **cursor-bootstrap**: `cursor()` MUST create the bookkeeping tables if absent before reading, so it returns `nil` on a never-prepared store instead of throwing.
- **cursor-read**: `cursor()` MUST return the `cursor` of the `_sync_state` row with `id = 1` wrapped in `SyncCursor(rawValue:)`, or `nil` when that row or value is absent.
- **registrations-bootstrap**: `registrations()` MUST create the bookkeeping tables if absent, so it returns `[:]` on a never-prepared store.
- **registrations-map**: `registrations()` MUST return every `_sync_resources` row as `resource → schema_version`.

### apply (pulled changes)

- **apply-atomic**: `apply(_:advancingTo:)` MUST write every change in the batch and the new cursor in one transaction; if any change fails, no change and no cursor update MUST persist.
- **apply-unknown-resource**: `apply` MUST throw `SyncStoreFailure.unknownResource(resource)` for a change whose resource is not in `_sync_resources`.
- **apply-version-strict**: `apply` MUST throw `SyncStoreFailure.invalidChange("unparseable syncVersion: <value>")` when a change's `syncVersion` does not parse as a Swift `Int`, and MUST NOT coerce it to 0.
- **apply-upsert-mirror**: For an unclaimed resource, an `.upsert` change MUST insert or replace the row so that `sync_version` equals the parsed version, `deleted_at` is NULL, and `data` is the JSON encoding of `change.data` (an empty object when `data` is nil).
- **apply-delete-mirror**: For an unclaimed resource, a `.delete` change MUST insert or update the row so that `sync_version` equals the parsed version, `deleted_at` is the current SQLite `datetime('now')`, and `data` is `'{}'`; a delete for a row never seen MUST still create the tombstone.
- **apply-upsert-projection**: For a claimed resource, an `.upsert` change MUST call the projection's `upsert(resource:id:syncVersion:data:isFullRow:in:)` with `isFullRow: true` and `data ?? [:]`.
- **apply-delete-projection**: For a claimed resource, a `.delete` change MUST call the projection's `markDeleted(resource:id:syncVersion:in:)` with the parsed version.
- **apply-cursor-optional**: When `cursor` is non-nil, `apply` MUST store it as the `_sync_state` row `id = 1`; when `cursor` is nil, the stored cursor MUST be left unchanged.
- **apply-order**: Changes in a batch MUST be applied in array order, so a later change for the same row overwrites an earlier one.

### stage (local mutations)

- **stage-pull-only-first**: `stage(_:)` MUST throw `SyncStoreFailure.pullOnlyResource(resource)` when the resource is in `pullOnlyResources`, before any database work and before the registration check; `stage(_:in:)` MUST apply the same check first.
- **stage-unknown-resource**: `stage` MUST throw `SyncStoreFailure.unknownResource(resource)` when the resource is not in `_sync_resources`.
- **stage-atomic**: The mirror write and the outbox write of one `stage` call MUST commit together or not at all.
- **stage-base-version**: `stage` MUST read the row's current `sync_version` (from the projection's `syncVersion(resource:id:in:)` for a claimed resource) before writing, and use it as the base version; a row not yet stored has no base version.
- **stage-upsert-mirror**: For an unclaimed resource, an `.upsert` MUST set `deleted_at` to NULL and `data` to the JSON encoding of `mutation.data ?? [:]`, leaving an existing row's `sync_version` unchanged and creating a new row with `sync_version` 0.
- **stage-mirror-patch**: NEEDS REVIEW: Not implemented in source. The JSON mirror replaces `data` wholesale with the staged patch while the outbox merges patches and the projection path calls a staged mutation "a deliberate partial patch", so fields absent from the patch vanish from `liveRow` until the next pull; whether the mirror should merge instead needs the sync owner to decide and a test asserting the intended local view.
- **stage-delete-mirror**: For an unclaimed resource, a `.delete` MUST set `deleted_at` to `datetime('now')` on the existing row and MUST NOT change its `data` or `sync_version`; when the row does not exist, no mirror row MUST be created.
- **stage-upsert-projection**: For a claimed resource, an `.upsert` MUST call the projection's `upsert` with `syncVersion` equal to the base version (0 when absent), `data ?? [:]`, and `isFullRow: false`.
- **stage-delete-projection**: For a claimed resource, a `.delete` MUST call the projection's `markDeleted` with `syncVersion: nil`.
- **stage-new-op**: When no `pending` outbox op exists for the same `(resource, rowId)`, `stage` MUST insert one with a fresh `SyncID.uuidV7()` `op_id`, the mutation's `type`, `base_version` equal to the base version as a decimal string (NULL when absent), `payload` equal to the JSON encoding of `data ?? [:]`, `status` `pending`, `attempts` 0, and `created_at` `datetime('now')`.
- **stage-coalesce**: When a `pending` op exists for the same `(resource, rowId)`, `stage` MUST update that op in place, keeping its `op_id` and its original `base_version`, and MUST NOT insert a second op.
- **stage-coalesce-upsert**: When coalescing an `.upsert`, the op's `type` MUST become `upsert` and its `payload` MUST become the existing payload merged with the new `data`, the new value winning for a repeated key.
- **stage-coalesce-delete**: When coalescing a `.delete`, the op's `type` MUST become `delete` and its `payload` MUST become an empty object.
- **stage-no-coalesce-inflight**: `stage` MUST NOT coalesce into an `inflight` or `quarantined` op; it MUST insert a new op with a fresh `op_id`.

