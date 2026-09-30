<!-- leaf: implement-sync-engine/testing--edge-cases · source: sync-engine-testing.md -->

# Sync Engine Testing

**Rules** (cite as `implement-sync-engine/testing--edge-cases#<slug>`):

- `empty-batch` MUST — apply([], advancingTo: c) MUST store c and change no rows; with a nil cursor it MUST change nothing.
- `sign-prefixed-version` MUST — A syncVersion such as "+5" or "-5" parses as an Int, so apply and complete MUST accept it even though the wire contract …
- `duplicate-ids-in-one-batch` MUST — When a batch carries the same (resource, id) twice, the later change MUST win.
- `delete-with-data` MUST — A pulled or staged delete with non-nil data MUST store that data on the tombstoned row.
- `upsert-after-a-pending-delete` MUST — Coalescing an upsert into a pending delete MUST produce an upsert whose data is the new data (the delete's nil data …
- `stage-over-a-pulled-tombstone` MUST — Staging an upsert for a row whose mirror entry is a tombstone MUST take that tombstone's syncVersion as baseVersion.
- `pull-overwrites-an-optimistic-row` MUST — apply MUST overwrite a locally staged row for the same id; the outbox op is unaffected.
- `adoption-after-reset-or-purge` MUST — An .applied result whose row was cleared by resetForResync or purgeResources MUST skip adoption and still remove the …
- `result-for-an-unknown-opid` MUST — complete MUST skip it silently; the engine, not the store, detects the missing progress.
- `duplicate-results-for-one-opid` MUST — The second result MUST find no entry and be skipped.
- `zero-limit` MUST — pendingOps(limit: 0) MUST return empty and mark nothing inflight.
- `duplicate-descriptors-in-prepare` MUST — The last descriptor's schemaVersion MUST win.
- `empty-prepare` MUST — prepare(resources: []) MUST change nothing.
- `concurrent-calls` MUST — Both fakes are actors, so concurrent calls MUST run one at a time; no call suspends inside its body, so no call …
- `exhausted-script` MUST — A drained script MUST fall back to the default response rather than throwing; a test that expects a failure MUST …

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
