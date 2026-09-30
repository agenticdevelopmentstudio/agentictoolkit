<!-- leaf: implement-sync/engine--edge-cases · source: sync-engine.md -->

# SyncEngine

**Rules** (cite as `implement-sync/engine--edge-cases#<slug>`):

- `empty-outbox` MUST — pendingOps returns nothing — the push loop MUST return without calling the transport.
- `empty-pull-page-that-advances-the-cursor` MUST — MUST be applied (zero changes), emit .pulledBatch(changes: 0, …), and reset the no-progress count.
- `same-cursor-page-with-changes` MUST — MUST NOT count as no progress.
- `empty-manifest-on-a-non-fresh-cursor` MUST — every registered resource MUST be disabled — purged and its ops quarantined — because the manifest is read as complete.
- `change-for-an-unregistered-resource-with-hostresources-nil` MUST — the engine MUST pass it to store.apply unfiltered; whatever the store throws (the in-memory store throws …
- `push-result-for-an-op-outside-the-batch` MUST — an .applied or .rejected result MUST be forwarded to store.complete unchanged; the engine does not check it against the …
- `conflict-for-an-op-outside-the-batch` MUST — MUST be counted as a conflict and forwarded, with nothing adopted.
- `very-large-failure-count` MUST — the delay MUST NOT exceed maxBackoff (default 3600 seconds).
- `concurrent-kicks` MUST — MUST coalesce into the running cycle plus at most one follow-up cycle carrying the first coalesced reason.
- `kick-while-auth-paused` MUST — kick(.periodic) and a retry's .periodic kick MUST return without a pull; only .manual or .hostSpecific(_) resumes.
- `pause-during-a-cycle` MUST — the running cycle MUST finish; any reason coalesced before or during the pause MUST be dropped.
- `event-subscriber-absent` MUST — events past 256 MUST drop the oldest; the engine keeps running.
- `events-after-stop` MUST — MUST be discarded silently by the finished stream.
- `offline-unreachable-server` MUST — the transport's thrown error MUST take the generic-failure path, keep every outbox op, and back off; …
- `crash-mid-cycle` MUST — the engine holds no durable state; crash safety MUST come from the store's atomic stage/apply (see store-atomic).
- `clock-moving-backwards` MUST — SyncID MUST keep incrementing the counter from the last millisecond rather than reuse an earlier timestamp.
- `counter-overflow-in-one-millisecond` MUST — SyncID MUST borrow the next millisecond and restart the counter at 0.
- `undecodable-json-token` MUST — JSONValue decoding MUST throw DecodingError.dataCorrupted with "not JSON".

## Edge Cases

- **Empty outbox**: `pendingOps` returns nothing — the push loop MUST return without calling the transport.
- **Empty pull page that advances the cursor**: MUST be applied (zero changes), emit `.pulledBatch(changes: 0, …)`, and reset the no-progress count.
- **Same-cursor page with changes**: MUST NOT count as no progress.
- **Empty manifest on a non-fresh cursor**: every registered resource MUST be disabled — purged and its ops quarantined — because the manifest is read as complete.
- **Change for an unregistered resource with `hostResources` nil**: the engine MUST pass it to `store.apply` unfiltered; whatever the store throws (the in-memory store throws `SyncStoreFailure.unknownResource`) MUST take the generic-failure path and back off. The server owns sending only manifest resources.
- **Push result for an op outside the batch**: an `.applied` or `.rejected` result MUST be forwarded to `store.complete` unchanged; the engine does not check it against the attempted batch, so the store resolves whatever op carries that `opId`.
- **Conflict for an op outside the batch**: MUST be counted as a conflict and forwarded, with nothing adopted.
- **Negative or zero `consecutiveFailures`**: cannot occur — every retry is scheduled after an increment, so the exponent is at least 0 (`2^0 × baseBackoff`) and is capped at 15 (exponent `min(n,16) - 1`).
- **Very large failure count**: the delay MUST NOT exceed `maxBackoff` (default 3600 seconds).
- **Concurrent kicks**: MUST coalesce into the running cycle plus at most one follow-up cycle carrying the first coalesced reason.
- **Kick while auth-paused**: `kick(.periodic)` and a retry's `.periodic` kick MUST return without a pull; only `.manual` or `.hostSpecific(_)` resumes.
- **Pause during a cycle**: the running cycle MUST finish; any reason coalesced before or during the pause MUST be dropped.
- **Event subscriber absent**: events past 256 MUST drop the oldest; the engine keeps running.
- **Events after `stop()`**: MUST be discarded silently by the finished stream.
- **Cancellation of an in-flight transport call**: the engine offers none; cancellation reaches the transport only if the host cancels the task awaiting `syncNow`.
- **Timeouts**: the engine applies none; any timeout is the transport's and surfaces as a thrown error on the generic-failure path.
- **Offline / unreachable server**: the transport's thrown error MUST take the generic-failure path, keep every outbox op, and back off; connectivity-restored wake-ups arrive only through an attached `SyncTriggerSource` yielding `.connectivityRestored`.
- **Crash mid-cycle**: the engine holds no durable state; crash safety MUST come from the store's atomic `stage`/`apply` (see **store-atomic**).
- **Clock moving backwards**: `SyncID` MUST keep incrementing the counter from the last millisecond rather than reuse an earlier timestamp.
- **Counter overflow in one millisecond**: `SyncID` MUST borrow the next millisecond and restart the counter at 0.
- **Undecodable JSON token**: `JSONValue` decoding MUST throw `DecodingError.dataCorrupted` with "not JSON".
