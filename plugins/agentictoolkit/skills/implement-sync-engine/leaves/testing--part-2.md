<!-- leaf: implement-sync-engine/testing--part-2 · source: sync-engine-testing.md -->

# Sync Engine Testing — continued (part 2)

**Rules** (cite as `implement-sync-engine/testing--part-2#<slug>`):

- `store-actor` MUST
- `transport-actor` MUST
- `row-shape` MUST
- `outcome-shape` MUST
- `failure-shape` MUST
- `observable-logs` MUST
- `transport-records` MUST
- `prepare-upsert` MUST
- `prepare-new-empty` MUST
- `registration-truth` MUST
- `registrations-projection` MUST
- `cursor-read` MUST
- `apply-unknown-resource` MUST
- `apply-unparseable-version` MUST
- `apply-atomic` MUST
- `apply-row-write` MUST
- `apply-keeps-string-version` MUST
- `apply-advances` MUST
- `apply-ignores-pull-only` MUST
- `stage-pull-only` MUST
- `stage-unknown-resource` MUST
- `stage-optimistic-row` MUST
- `stage-new-op` MUST
- `stage-coalesce` MUST
- `coalesce-upsert-merge` MUST
- `coalesce-delete-nil` MUST
- `inflight-not-coalesced` MUST
- `pending-ops-fifo` MUST
- `pending-ops-marks-inflight` MUST
- `inflight-replay` MUST
- `complete-unknown-op` MUST
- `complete-applied` MUST
- `complete-adopt-version` MUST
- `complete-skip-unparseable` MUST
- `complete-conflict` MUST
- `complete-rejected` MUST
- `quarantine-never-pushed` MUST
- `resync-clears` MUST
- `resync-keeps-registrations` MUST
- `resync-keeps-outbox` MUST
- `purge-deregisters` MUST
- `purge-quarantines` MUST
- `purge-keeps-cursor` MUST
- `purge-unregistered-noop` MUST
- `purge-empty-noop` MUST
- `row-count` MUST
- `row-count-unknown` MUST
- `row-lookup` MUST
- `pending-op-id` MUST
- `init-scripts` MUST
- `enqueue` MUST
- `pull-records-cursor` MUST
- `pull-scripted` MUST
- `pull-default` MUST
- `pull-ignores-limit` MUST
- `push-records-request` MUST
- `push-scripted` MUST
- `push-default` MUST
- `scripts-unvalidated` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `pullOnlyResources` | `Set<String>` | `[]` | `InMemorySyncStore.init` — resources `stage(_:)` refuses with `pullOnlyResource` |
| `pulls` | `[Outcome<SyncPullResponse>]` | `[]` | `ScriptedSyncTransport.init` — initial pull script, consumed FIFO |
| `pushes` | `[Outcome<SyncPushResponse>]` | `[]` | `ScriptedSyncTransport.init` — initial push script, consumed FIFO |

No environment variables, settings keys or injected dependencies are read. The opId generator `SyncID.uuidV7()` is called directly and cannot be injected.

