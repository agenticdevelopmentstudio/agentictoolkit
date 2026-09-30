<!-- leaf: implement-sync/engine--part-3 · source: sync-engine.md -->

# SyncEngine — continued (part 3)

**Rules** (cite as `implement-sync/engine--part-3#<slug>`):

- `push-batch` MUST
- `push-request` MUST
- `applied-result` MUST
- `rejected-result` MUST
- `conflict-unmatched` MUST
- `conflict-no-current` MUST
- `conflict-unadoptable` MUST
- `adopted-version` MUST
- `conflict-adopt` MUST
- `delete-wins` MUST
- `strip-bookkeeping` MUST
- `adopt-before-complete` MUST
- `pushed-event` MUST
- `push-no-progress` MUST
- `resync-procedure` MUST
- `resync-preserves-outbox` MUST
- `resync-unauthorized` MUST
- `resync-nested-once` MUST
- `resync-counter-persists` MUST
- `resync-other-failure` MUST
- `store-atomic` MUST
- `store-apply-nil-cursor` MUST
- `store-stage-registered` MUST
- `store-prepare-idempotent` MUST
- `store-complete-terminal` MUST
- `store-reset` MUST
- `store-purge` MUST
- `transport-errors` MUST
- `jsonvalue-decode-order` MUST
- `jsonvalue-number-lossy` MUST
- `jsonvalue-accessors` MUST
- `uuidv7-format` MUST
- `uuidv7-monotonic` MUST
- `reached-backend` MUST
- `catalog-shape` MUST
- `engine-ignores-watermark` MUST

### Push loop

- **push-batch**: The push loop MUST fetch up to `pushBatchSize` ops with `store.pendingOps(limit:)` and return when none remain.
- **push-request**: Each batch MUST be sent as one `SyncPushRequest(deviceId:ops:)` carrying the configured `deviceId`.
- **applied-result**: An `.applied` result MUST be counted as applied and forwarded unchanged to `store.complete(_:)`, including its `newVersion`.
- **rejected-result**: A `.rejected` result MUST be counted as rejected and forwarded unchanged to `store.complete(_:)`.
- **conflict-unmatched**: A `.conflict` result whose `opId` matches no op in the batch MUST be counted as a conflict and forwarded unchanged, with nothing adopted.
- **conflict-no-current**: A `.conflict` result with a nil `current` MUST be counted as rejected and forwarded as `.rejected` with its original `reason`, with nothing adopted.
- **conflict-unadoptable**: A `.conflict` result whose `current["sync_version"]` cannot be adopted MUST be counted as rejected and forwarded as `.rejected` with its original `reason`, with nothing adopted.
- **adopted-version**: A missing `sync_version` MUST adopt as `"0"`; a `.number` MUST adopt as its decimal integer text only when it converts exactly to a 64-bit `Int`; a `.string` MUST adopt verbatim only when it parses as an `Int`; every other JSON type MUST be unadoptable.
- **adopted-version-sign**: NEEDS REVIEW: Not implemented in source. `adoptedVersion(from:)` documents that `SyncChange.syncVersion` expects digits only, but `Int(_:)` accepts a leading `+` or `-` and `Int(exactly:)` accepts negative numbers, so `"-5"`, `"+5"` or `-3` pass through to `store.apply`, which could throw and re-push the op every cycle (the wedge the fix set out to remove); a non-negative, unsigned check or a store contract that accepts signed text would settle it.
- **conflict-adopt**: An adoptable `.conflict` MUST produce one `SyncChange` for the op's `resource` and `rowId` at the adopted version, emit `.conflictResolved(resource:rowId:)`, and forward the result unchanged.
- **delete-wins**: The adopted change MUST be `.delete` with nil `data` when `current["deleted_at"]` is present and not JSON null, and `.upsert` otherwise; a missing `deleted_at` key counts as not deleted.
- **strip-bookkeeping**: An adopted `.upsert` MUST carry `current` with the `sync_version` and `sync_stamped_at` keys removed.
- **adopt-before-complete**: All of a batch's adoptions MUST be applied in one `store.apply(_:advancingTo: nil)` call, skipped when there are none, before `store.complete(_:)` is called with every result.
- **pushed-event**: After `complete`, the engine MUST emit `.pushed(applied:conflicts:rejected:)` with the batch's three counts.
- **push-no-progress**: After each batch, when every attempted `opId` is still returned by `pendingOps(limit: pushBatchSize)`, the engine MUST throw `SyncEngineError.pushMadeNoProgress`; this covers an empty `results` array for a non-empty batch.

### Resync (HTTP 410)

- **resync-procedure**: The resync procedure MUST call `store.resetForResync()`, emit `.resyncPerformed`, run the pull loop, then the push loop; on success it MUST reset both failure counters and emit `.idle`.
- **resync-preserves-outbox**: Resync MUST replay the preserved outbox under its original `opId`s; the engine MUST NOT re-stage or re-mint ops.
- **resync-unauthorized**: `unauthorized` during resync MUST set `authPaused` and emit `.authRequired`, with no `.failed` and no retry.
- **resync-nested-once**: A `resyncRequired` during resync MUST increment `consecutiveResyncs`; while it is 1 or less the resync MUST be retried immediately, and above 1 the engine MUST increment `consecutiveFailures`, emit `.failed("repeated resync_required from server; backing off")`, and schedule a retry.
- **resync-counter-persists**: `consecutiveResyncs` MUST persist across cycles and reset only on a fully successful cycle or resync.
- **resync-other-failure**: Any other error during resync MUST take the generic-failure path.

### Store and transport contract (injected)

- **store-atomic**: A `SyncStore` MUST make `stage(_:)` and `apply(_:advancingTo:)` atomic with the outbox mutations they imply.
- **store-apply-nil-cursor**: `apply(_:advancingTo: nil)` MUST apply without advancing the cursor.
- **store-stage-registered**: `stage(_:)` MUST throw `SyncStoreFailure.unknownResource` for a resource never passed to `prepare(resources:)`; hosts MUST `prepare` before staging.
- **store-prepare-idempotent**: `prepare(resources:)` MUST be idempotent, upserting schema versions.
- **store-complete-terminal**: `complete(_:)` MUST resolve ops by `opId`, and a rejected op MUST never be retried under the same `opId`; a retry MUST go through a fresh `stage(_:)`.
- **store-reset**: `resetForResync()` MUST clear mirror rows and the cursor, preserve the outbox, and never delete the database file.
- **store-purge**: `purgeResources(_:)` MUST delete the resources' mirror rows, quarantine their pending and in-flight ops, remove their registrations, and leave the cursor untouched.
- **transport-errors**: A `SyncTransport` MUST map HTTP 401 to `SyncTransportError.unauthorized` and HTTP 410 to `.resyncRequired`; the engine owns no credentials.

### Supporting types

- **jsonvalue-decode-order**: `JSONValue` MUST decode null, then `Bool`, then `Double`, then `String`, then array, then object, and throw `DecodingError.dataCorrupted` ("not JSON") when none match.
- **jsonvalue-number-lossy**: Every JSON number MUST decode to `.number(Double)`; integers beyond 2^53 lose precision by design of this projection.
- **jsonvalue-accessors**: `subscript(key:)` MUST return nil on a non-object, `stringValue` nil on a non-string, and `isNull` true only for `.null`.
- **uuidv7-format**: `SyncID.uuidV7(now:)` MUST return a 36-character lowercase hyphenated UUID with version nibble `7` and the RFC 4122 variant bits.
- **uuidv7-monotonic**: Ids minted by one process MUST sort strictly increasing: a new millisecond resets the 12-bit counter to a random value in 0...0x7FF, the same or an earlier millisecond increments it, and a counter at 0xFFF borrows the next millisecond and restarts at 0; all of this happens under one process-wide lock.
- **reached-backend**: `SyncEvent.reachedBackend` MUST be true for `.pulledBatch`, `.idle` and `.authRequired` and false for every other case.
- **catalog-shape**: `ADHSyncCatalog.all` MUST list 97 unique resources, all at `schemaVersion` 1, and `ADHSyncCatalog.pullOnly` MUST be a 44-name subset of them; the catalog is generated and is client knowledge only — the server manifest gates what syncs.
- **engine-ignores-watermark**: The engine MUST NOT read `SyncPushResponse.watermark`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deviceId` | `String` | required | Sent as `SyncPushRequest.deviceId` on every push |
| `pullLimit` | `Int` | `500` | `limit` passed to each `transport.pull` |
| `pushBatchSize` | `Int` | `100` | Max ops per push batch and per no-progress re-check |
| `baseBackoff` | `TimeInterval` | `2` | Seconds for the first retry delay |
| `maxBackoff` | `TimeInterval` | `3600` | Cap on any retry delay, in seconds |
| `hostResources` | `[SyncResource]?` | `nil` | nil accepts the whole manifest; set narrows the effective set to manifest ∩ hostResources |
| `store` | `any SyncStore` | required (init) | Mirror, outbox, cursor and registrations |
| `transport` | `any SyncTransport` | required (init) | Pull/push wire and credentials |
| trigger | `any SyncTriggerSource` | none | Attached with `attach(_:)`; any number |
| `maxConsecutiveNoProgressPulls` | constant | `2` | Not configurable |
| `maxReconcileResyncsPerCycle` | constant | `3` | Not configurable |
| event buffer | constant | newest 256 | Not configurable |

No environment variables or settings keys are read.

## Localization

The engine has no localized strings. Its only human-readable text is hardcoded English, carried in `SyncEvent.failed(String)`: the `SyncEngineError` descriptions `"push made no progress"`, `"pull made no progress"` and `"manifest unstable"`, the literal `"repeated resync_required from server; backing off"`, and `String(describing:)` of any other error. A host that shows these to users must map them itself.

## Privacy

- **Data collected**: The engine moves the host's row data (`[String: JSONValue]` payloads) between store and transport; it collects nothing of its own beyond the host-supplied `deviceId`.
- **Storage**: The engine persists nothing; all rows, the cursor and the outbox live in the injected `SyncStore`.
- **Transmission**: Outbox ops and `deviceId` leave the device through the injected `SyncTransport`; the engine holds no credentials (the transport does).
- **Retention**: Rows purged by `purgeResources` or cleared by `resetForResync` are removed by the store; rejected and unadoptable ops are quarantined, never dropped, and their retention is the store's.

