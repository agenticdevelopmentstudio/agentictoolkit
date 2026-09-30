<!-- leaf: implement-sync/engine--part-2 · source: sync-engine.md -->

# SyncEngine — continued (part 2)

**Rules** (cite as `implement-sync/engine--part-2#<slug>`):

- `actor-isolation` MUST
- `sendable-values` MUST
- `single-cycle` MUST
- `events-stream` MUST
- `attach-trigger` MUST
- `stop-cancels` MUST
- `stop-in-flight` MUST
- `kick-paused` MUST
- `kick-coalesce` MUST
- `kick-start` MUST
- `pending-first-wins` MUST
- `syncnow-paused` MUST
- `syncnow-auth-gate` MUST
- `syncnow-join` MUST
- `follow-up-cycle` MUST
- `pause-drops-pending` MUST
- `pause-wait` MUST
- `resume-no-sync` MUST
- `waiters-resumed` MUST
- `cycle-order` MUST
- `cycle-success` MUST
- `unauthorized-pause` MUST
- `resync-required` MUST
- `generic-failure` MUST
- `engine-error-text` MUST
- `invalid-response-generic` MUST
- `backoff-delay` MUST
- `backoff-single-timer` MUST
- `backoff-cancelled` MUST
- `registrations-snapshot` MUST
- `pull-request` MUST
- `effective-set` MUST
- `reconcile-before-prepare` MUST
- `prepare-when-changed` MUST
- `change-filter` MUST
- `apply-advances` MUST
- `pulled-batch-event` MUST
- `pull-continues` MUST
- `pull-no-progress` MUST
- `reconcile-plan` MUST
- `unregistered-event` MUST
- `disable-purge` MUST
- `manifest-complete` MUST
- `bump-purge` MUST
- `fresh-cursor-no-resync` MUST
- `reconcile-resync` MUST
- `reconcile-bound` MUST

## Behavioral Requirements

### Isolation and lifecycle

- **actor-isolation**: `SyncEngine` MUST be an actor; every mutable field (`running`, `pendingReason`, `authPaused`, `hostPaused`, `cycleWaiters`, `consecutiveFailures`, `consecutiveResyncs`, `triggerTasks`, `retryTask`) MUST be read and written only on that actor.
- **sendable-values**: Every wire type, `JSONValue`, `SyncEvent`, `SyncKickReason`, `LocalMutation` and `SyncEngineConfiguration` MUST be `Sendable`, and `SyncStore`, `SyncTransport` and `SyncTriggerSource` MUST refine `Sendable`.
- **single-cycle**: The engine MUST run at most one cycle at a time; a kick that arrives while `running` is true MUST NOT start a second concurrent cycle.
- **events-stream**: `events` MUST be a nonisolated `AsyncStream<SyncEvent>` created with a buffering policy of the newest 256 events; when a subscriber falls more than 256 events behind, the oldest undelivered events MUST be dropped.
- **attach-trigger**: `attach(_:)` MUST start a task that calls `kick(reason:)` once for every value the trigger's `kicks` stream yields, in stream order, and MUST hold the engine weakly so an attached trigger never keeps the engine alive.
- **stop-cancels**: `stop()` MUST cancel every attached trigger task, cancel any pending retry task, and finish the `events` stream.
- **stop-in-flight**: `stop()` MUST NOT wait for or cancel a cycle already in flight; that cycle continues to call the store and transport until it ends.
- **stop-during-cycle**: NEEDS REVIEW: Not implemented in source. `stop()` sets no stopped flag, so a cycle suspended at an `await` when `stop()` runs can still reach `scheduleRetry()` on failure and arm a new retry task that later calls `kick(reason: .periodic)` after the host stopped the engine, with every event it yields discarded by the finished stream; a stopped-state contract (refuse `kick`/`syncNow`/`scheduleRetry` after `stop()`) or a documented statement that `stop()` must follow `pause()` would settle it.

### Entry points and coalescing

- **kick-paused**: `kick(reason:)` MUST return without effect while `hostPaused` is true.
- **kick-coalesce**: `kick(reason:)` called while a cycle is running MUST record the reason as `pendingReason` only when none is already recorded, and MUST return without waiting for the cycle.
- **kick-start**: `kick(reason:)` called while idle and unpaused MUST run a cycle through `syncNow(reason:)` and return when that call returns.
- **pending-first-wins**: When several kicks coalesce into one running cycle, only the first recorded reason MUST be kept; later reasons are discarded.
- **syncnow-paused**: `syncNow(reason:)` MUST return immediately, without a cycle, while `hostPaused` is true.
- **syncnow-auth-gate**: While `authPaused` is true, `syncNow(reason:)` MUST return immediately unless the reason is `.manual` or `.hostSpecific(_)`; for those two it MUST clear `authPaused` and proceed.
- **syncnow-join**: `syncNow(reason:)` called while a cycle is running MUST record its reason as `pendingReason` (first wins) and MUST suspend until the running cycle finishes; it MUST NOT wait for the follow-up cycle its reason may trigger.
- **follow-up-cycle**: When a cycle ends with `hostPaused` false and a `pendingReason` recorded, the engine MUST clear `pendingReason` and immediately run exactly one more cycle with that reason.
- **pause-drops-pending**: When a cycle ends with `hostPaused` true, the engine MUST discard any `pendingReason` rather than run it after `resume()`.
- **pause-wait**: `pause()` MUST set `hostPaused`; if a cycle is running it MUST suspend until that cycle finishes, and if none is running it MUST return immediately.
- **resume-no-sync**: `resume()` MUST clear `hostPaused` and MUST NOT start a cycle itself.
- **waiters-resumed**: At the end of every cycle, every continuation queued by `pause()` or a joining `syncNow(reason:)` MUST be resumed exactly once, before any follow-up cycle starts.

### Cycle outcome

- **cycle-order**: A cycle MUST emit `.started(reason)`, then run the pull loop to completion, then the push loop to completion; the push loop MUST NOT start if the pull loop threw.
- **cycle-success**: A cycle whose pull and push loops both complete MUST reset `consecutiveFailures` and `consecutiveResyncs` to 0 and emit `.idle`.
- **unauthorized-pause**: A `SyncTransportError.unauthorized` thrown anywhere in the cycle MUST set `authPaused`, emit `.authRequired`, and MUST NOT emit `.failed` or schedule a retry.
- **resync-required**: A `SyncTransportError.resyncRequired` thrown in the cycle MUST run the resync procedure (see **resync-procedure**) instead of emitting `.failed`.
- **generic-failure**: Any other error MUST increment `consecutiveFailures`, emit `.failed(String(describing: error))`, and schedule a retry; no outbox op may be removed as a result.
- **engine-error-text**: `SyncEngineError` MUST describe itself as `"push made no progress"`, `"pull made no progress"` and `"manifest unstable"` for `.pushMadeNoProgress`, `.pullMadeNoProgress` and `.manifestUnstable`, so those strings are the `.failed` payload.
- **invalid-response-generic**: `SyncTransportError.transport(_)` and `.invalidResponse(statusCode:)` MUST take the generic-failure path; the engine gives them no special handling.

### Backoff

- **backoff-delay**: A scheduled retry MUST wait `min(baseBackoff * 2^(min(consecutiveFailures, 16) - 1), maxBackoff)` seconds, then call `kick(reason: .periodic)`.
- **backoff-single-timer**: Scheduling a retry MUST cancel any retry task already pending, so at most one retry timer exists.
- **backoff-cancelled**: A retry task cancelled before its delay elapses MUST NOT kick.

### Pull loop

- **registrations-snapshot**: The pull loop MUST read `store.registrations()` once at cycle start and keep that local snapshot current as reconciliation purges and preparation registers, rather than re-reading it per page.
- **pull-request**: Each page MUST call `transport.pull(cursor:limit:)` with the store's current `cursor()` and `pullLimit`.
- **effective-set**: The effective resource set MUST equal the page's `manifest` when `hostResources` is nil, and `manifest` filtered to resources whose names appear in `hostResources` otherwise; the manifest's `schemaVersion` is the one kept.
- **reconcile-before-prepare**: Reconciliation MUST run on every page, before the page's `prepare` and `apply`.
- **prepare-when-changed**: The engine MUST call `store.prepare(resources:)` with the effective set only when the snapshot does not already hold every effective resource at the identical `schemaVersion`, and MUST then record those versions in the snapshot.
- **change-filter**: When `hostResources` is set, only changes whose `resource` is in the effective set MUST be applied; when it is nil, every change in the page MUST be applied unfiltered.
- **apply-advances**: The page's applicable changes MUST be passed to `store.apply(_:advancingTo:)` together with `SyncCursor(rawValue: response.cursor)` in a single call.
- **pulled-batch-event**: After each successful apply the engine MUST emit `.pulledBatch(changes:cursor:)` carrying the applicable-change count and the new cursor, including for an empty page.
- **pull-continues**: The pull loop MUST request another page while the last response's `hasMore` is true, and stop when it is false.
- **pull-no-progress**: A response with empty `changes`, `hasMore` true, and a cursor equal to the one requested MUST count as no progress; 2 consecutive no-progress responses MUST throw `SyncEngineError.pullMadeNoProgress`, and any other response MUST reset the count to 0.

### Manifest reconciliation

- **reconcile-plan**: `reconcilePlan(registered:effective:)` MUST be a pure function returning three name lists, each sorted ascending: `disabled` (registered, absent from the effective set), `bumped` (registered at a `schemaVersion` different from the manifest's, higher or lower), and `appeared` (effective, not registered, and not in `bumped`).
- **unregistered-event**: When `hostResources` is set, the engine MUST emit `.unregisteredManifestResources(names)` with the sorted manifest names outside the effective set, only when that list is non-empty and differs from the list last emitted in the same cycle.
- **disable-purge**: A non-empty `disabled` list MUST be passed to `store.purgeResources(_:)`, removed from the snapshot, and reported as `.resourcesDisabled(names)`; disablement alone MUST NOT reset the cursor or resync.
- **manifest-complete**: The engine MUST treat each page's manifest as complete: a registered resource missing from any single page MUST be disabled on that page, with no floor for an empty or partial manifest.
- **bump-purge**: A non-empty `bumped` list MUST be passed to `store.purgeResources(_:)`, removed from the snapshot, and reported as `.resourcesSchemaBumped(names)`.
- **fresh-cursor-no-resync**: When the page was requested with a nil cursor, appearance and bump MUST NOT trigger a resync.
- **reconcile-resync**: When the page was requested with a non-nil cursor and `appeared` or `bumped` is non-empty, the engine MUST call `store.resetForResync()`, emit `.resourcesEnabled(appeared)` when `appeared` is non-empty, emit `.resyncPerformed`, skip the page's changes, and restart the pull from the (now nil) stored cursor.
- **reconcile-bound**: More than 3 reconcile-triggered resets in one cycle MUST throw `SyncEngineError.manifestUnstable`.

