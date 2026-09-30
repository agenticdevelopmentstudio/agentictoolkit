<!-- leaf: implement-sync-engine/sync-grdb--edge-cases · source: sync-engine-sync-grdb.md -->

# GRDBSyncStore

**Rules** (cite as `implement-sync-engine/sync-grdb--edge-cases#<slug>`):

- `never-prepared-store` MUST — cursor() MUST return nil and registrations() MUST return [:] (both bootstrap the schema); status(), …
- `empty-batch` MUST — apply([], advancingTo: c) MUST store c with no row changes; apply([], advancingTo: nil) MUST change nothing.
- `change-with-nil-data` MUST — an .upsert MUST store '{}' as data; a staged .upsert with nil data MUST store and enqueue an empty object.
- `negative-or-oversized-syncversion` MUST — apply MUST accept any string Swift's Int(_:) parses, including a leading + or -; a value outside the 64-bit range MUST …
- `local-delete-of-a-row-never-stored` MUST — MUST create no mirror row, and MUST still enqueue a delete op with a NULL base_version.
- `upsert-coalesced-onto-a-pending-delete` MUST — the op MUST become upsert with payload {} merged with the new data, keeping the original op_id and base_version.
- `stage-while-the-row-s-op-is-inflight` MUST — a new op MUST be inserted carrying the mirror's current sync_version, which is still the pre-push version until …
- `pendingops` MUST — MUST return no ops and mark nothing inflight.
- `negative-pendingops-limit` MUST — MUST return every pending and inflight op and mark them all inflight, because SQLite treats a negative LIMIT as no …
- `negative-liverows-limit` MUST — MUST return every live row from offset, for the same SQLite reason; the doc comment makes capping limit the caller's …
- `undecodable-outbox-payload-or-mirror-data` MUST — decoding MUST throw the JSONDecoder error out of pendingOps, liveRows or liveRow; pendingOps rolls back its inflight …
- `result-for-an-unknown-opid` MUST — .applied and .rejected MUST be silent no-ops; .conflict MUST write an audit row with NULL resource and row_id.
- `applied-with-no-newversion` MUST — MUST delete the outbox row and leave sync_version unchanged.
- `projected-resource-with-an-invalid-name` MUST — MUST NOT be validated by mirrorTableName(for:), because claimed resources never name a JSON mirror table.
- `purge-of-a-mix-of-registered-and-unregistered-resources` MUST — MUST truncate only the registered ones, but MUST run the quarantine and deregistration statements for every named …
- `concurrent-async-calls` MUST — MUST execute one at a time in queue submission order.
- `concurrent-sync-read-during-an-async-write` MUST — MUST see the last committed state (WAL snapshot), never a half-applied batch.
- `nested-use-from-inside-the-caller-s-write` MUST — calling async stage(_:) from inside a BoundedDatabase.write would deadlock the writer; the caller MUST use stage(_:in:) …
- `database-deadline-or-lock-timeout` MUST — BoundedDatabase MUST eject an operation that exceeds its read or write deadline (10 s and 60 s by default) with …
- `disk-full-or-i-o-error` MUST — the GRDB error MUST propagate to the caller and the transaction MUST roll back.
- `cancellation` MUST — a cancelled task awaiting an async operation MUST still see the operation run to completion.

## Edge Cases

- **Never-prepared store**: `cursor()` MUST return nil and `registrations()` MUST return `[:]` (both bootstrap the schema); `status()`, `registeredResources()`, `liveRows` and `liveRow` MUST surface GRDB's "no such table" error, because they read on the pool without bootstrapping.
- **Empty batch**: `apply([], advancingTo: c)` MUST store `c` with no row changes; `apply([], advancingTo: nil)` MUST change nothing.
- **Change with nil `data`**: an `.upsert` MUST store `'{}'` as `data`; a staged `.upsert` with nil `data` MUST store and enqueue an empty object.
- **Negative or oversized syncVersion**: `apply` MUST accept any string Swift's `Int(_:)` parses, including a leading `+` or `-`; a value outside the 64-bit range MUST throw `invalidChange`.
- **Local delete of a row never stored**: MUST create no mirror row, and MUST still enqueue a `delete` op with a NULL `base_version`.
- **Upsert coalesced onto a pending delete**: the op MUST become `upsert` with payload `{}` merged with the new data, keeping the original `op_id` and `base_version`.
- **Stage while the row's op is inflight**: a new op MUST be inserted carrying the mirror's current `sync_version`, which is still the pre-push version until `complete` adopts the server's; how the server treats that base version belongs to the adh sync backend.
- **`pendingOps(limit: 0)`**: MUST return no ops and mark nothing inflight.
- **Negative `pendingOps` limit**: MUST return every `pending` and `inflight` op and mark them all inflight, because SQLite treats a negative `LIMIT` as no limit; the store does not validate `limit`.
- **Negative `liveRows` limit**: MUST return every live row from `offset`, for the same SQLite reason; the doc comment makes capping `limit` the caller's job (`MirrorServer`'s `listLimit`).
- **Undecodable outbox payload or mirror `data`**: decoding MUST throw the `JSONDecoder` error out of `pendingOps`, `liveRows` or `liveRow`; `pendingOps` rolls back its inflight marking.
- **Result for an unknown opId**: `.applied` and `.rejected` MUST be silent no-ops; `.conflict` MUST write an audit row with NULL `resource` and `row_id`.
- **`.applied` with no `newVersion`**: MUST delete the outbox row and leave `sync_version` unchanged.
- **Projected resource with an invalid name**: MUST NOT be validated by `mirrorTableName(for:)`, because claimed resources never name a JSON mirror table.
- **Purge of a mix of registered and unregistered resources**: MUST truncate only the registered ones, but MUST run the quarantine and deregistration statements for every named resource (no-ops for unknown ones).
- **Concurrent async calls**: MUST execute one at a time in queue submission order.
- **Concurrent sync read during an async write**: MUST see the last committed state (WAL snapshot), never a half-applied batch.
- **Nested use from inside the caller's write**: calling async `stage(_:)` from inside a `BoundedDatabase.write` would deadlock the writer; the caller MUST use `stage(_:in:)` there, as its doc comment states.
- **Database deadline or lock timeout**: `BoundedDatabase` MUST eject an operation that exceeds its read or write deadline (10 s and 60 s by default) with `BoundedDatabaseError.deadlineExceeded`, and fail a write that waits on a lock longer than its busy timeout (5 s by default); the store rethrows either error and its transaction rolls back.
- **Disk full or I/O error**: the GRDB error MUST propagate to the caller and the transaction MUST roll back.
- **Cancellation**: a cancelled task awaiting an async operation MUST still see the operation run to completion.
- **Offline / unreachable server**: not applicable to this component; it performs no network I/O, and offline edits accumulate in the outbox until the engine pushes them.
