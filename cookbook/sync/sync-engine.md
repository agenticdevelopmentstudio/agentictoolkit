---
id: 355a8f54-aee5-45cd-a28d-12c3b7a3085c
title: SyncEngine
domain: agentictoolkit://cookbook/sync/sync-engine
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Actor-isolated offline-sync state machine: pull loop, manifest reconciliation,
  outbox push with LWW/delete-wins conflict adoption, 410 resync, and exponential
  backoff.'
platforms:
- swift
- macos
- ios
tags:
- sync
- offline
- engine
depends-on: []
related:
- agentictoolkit://cookbook/adh-offline-sync-client
references:
- packages/apple/AgenticToolkit/Sync/SyncEngine.swift
- packages/apple/AgenticToolkit/Sync/SyncEvents.swift
- packages/apple/AgenticToolkit/Sync/SyncProtocols.swift
- packages/apple/AgenticToolkit/Sync/SyncWire.swift
- packages/apple/AgenticToolkit/Sync/JSONValue.swift
- packages/apple/AgenticToolkit/Sync/SyncID.swift
- packages/apple/AgenticToolkit/Sync/ADHSyncCatalog.swift
- packages/apple/AgenticToolkit/Tests/AgenticToolkitSyncTests/SyncEngineTests.swift
approved-by: ''
approved-date: ''
---

# SyncEngine

## Overview

`SyncEngine` is the client half of an offline-first sync protocol: a Swift
`actor` that runs one *cycle* at a time — pull every page of server changes
into a local mirror, reconcile the server's resource manifest against what the
host has registered, then drain the local outbox to the server and adopt the
server's row on every conflict. It owns no storage, no network code and no
credentials: persistence is injected as a `SyncStore`, the wire as a
`SyncTransport`, and wake-ups as `SyncTriggerSource`s. Progress is reported
only through the `events` stream of `SyncEvent` values.

The recipe also covers the value types the engine's contract is written in:
the wire shapes in `SyncWire.swift` (`SyncCursor`, `SyncResource`,
`SyncChange`, `SyncPullResponse`, `SyncPushOp`, `SyncPushRequest`,
`SyncPushResult`, `SyncPushResponse`), the schema-flexible payload `JSONValue`,
the UUIDv7 generator `SyncID`, and the generated resource list
`ADHSyncCatalog`. The adh-specific enrollment and backend rules the engine
serves are specified in
[ADH Offline Sync Client](agentictoolkit://cookbook/adh-offline-sync-client).

Use it when a host (an app or a daemon) keeps a local mirror of server rows,
lets the user edit offline, and needs those edits pushed later without ever
being lost.

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

## Appearance

Not applicable — this is an actor-isolated sync state machine, not a visual component.

## States

Not applicable — this is an actor-isolated sync state machine, not a visual component.

## Accessibility

Not applicable — this is an actor-isolated sync state machine, not a visual component.

## Conformance Test Vectors

All engine vectors use `SyncEngineConfiguration(deviceId: "test-device", pullLimit: 10, pushBatchSize: 5, …)`, a scripted transport and an in-memory store, as `SyncEngineTests` does.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-engine-001 | pull-request, pull-continues, apply-advances | Pages `a` (cursor c1, hasMore true) then `b` (cursor c2, hasMore false); `syncNow(.manual)` | Cursors sent are nil then c1; stored cursor is c2; 2 mirror rows |
| sync-engine-002 | conflict-adopt, strip-bookkeeping, adopt-before-complete | Staged upsert r1; push returns `.conflict` with `current` title "theirs", `sync_version` 9, `sync_stamped_at`, `deleted_at` null | Outbox empty; mirror r1 title "theirs", syncVersion "9"; no `sync_version`/`sync_stamped_at` in its data |
| sync-engine-003 | delete-wins | Same as 002 but `deleted_at` is a timestamp | Outbox empty; r1 tombstoned with syncVersion "9" and empty data; live row count 0 |
| sync-engine-004 | conflict-no-current | `.conflict` with `current` nil, reason "server_row_missing" | Outbox empty; op in quarantine; local title still "mine" |
| sync-engine-005 | conflict-unadoptable, adopted-version | `.conflict` with `sync_version` `.number(.infinity)` | Op quarantined; outbox empty; local row untouched |
| sync-engine-006 | conflict-unadoptable, pushed-event, cycle-success | Two ops: "bad" conflict with `sync_version` "not-a-number", "good" `.applied` newVersion "7" | Outbox empty; only "bad" quarantined; events contain `.idle`, no `.failed` |
| sync-engine-007 | unauthorized-pause, syncnow-auth-gate | First pull throws `.unauthorized`; then `syncNow(.periodic)`; then `syncNow(.manual)` | 1 pull after the periodic call; 2 pulls after the manual call |
| sync-engine-008 | resync-required, resync-preserves-outbox | Stored row "old" at cursor "stale", one staged op; pull throws `.resyncRequired`, then returns row "fresh" | "fresh" present, "old" gone; the staged opId pushed exactly once; outbox empty |
| sync-engine-009 | resync-unauthorized | Pulls: `.resyncRequired`, then `.unauthorized`; then `syncNow(.periodic)` | 2 pulls total; events include `.resyncPerformed` and `.authRequired`, no `.failed` |
| sync-engine-010 | resync-nested-once, resync-counter-persists | Transport always throws `.resyncRequired`; `syncNow(.manual)` three times | Pull count 3, then 5, then 7; 3 `.failed` events each containing "resync_required"; outbox still 1 op |
| sync-engine-011 | generic-failure | Push throws `.transport("boom")` | Outbox still holds 1 op |
| sync-engine-012 | backoff-delay, cycle-success | Pulls fail 3 times, succeed, fail once, succeed; baseBackoff 0.02 | Retries fire unaided; the post-success retry gap is under 3x the first retry gap; 4 `.failed` events |
| sync-engine-013 | push-no-progress | Push result opId "bogus-op-id-not-in-outbox" `.applied` | Outbox still 1 op; a `.failed` event emitted |
| sync-engine-014 | push-no-progress, engine-error-text | Non-empty batch answered with `results: []` | No `.idle`; first `.failed` payload is "push made no progress"; outbox 1 op |
| sync-engine-015 | rejected-result, store-complete-terminal | Push result `.rejected` reason "invalid_data"; then a second `syncNow` | Op quarantined; outbox empty; exactly 1 push request across both cycles |
| sync-engine-016 | pull-no-progress | Four pages all empty, cursor "stalled", hasMore true | Exactly 3 pulls; first `.failed` payload is "pull made no progress" |
| sync-engine-017 | pause-wait | `pause()` called while a gated pull is in flight | `pause()` has not returned before release; returns after the cycle ends |
| sync-engine-018 | syncnow-join, follow-up-cycle | Two concurrent `syncNow` calls (manual, periodic) against a gated pull | Neither returns before release; both return after; exactly 2 pulls |
| sync-engine-019 | kick-paused, syncnow-paused, pause-drops-pending | `pause()` while idle, then `kick(.periodic)` and `syncNow(.manual)` | 0 pulls |
| sync-engine-020 | resume-no-sync, kick-start | `pause()`, `kick(.periodic)`, `resume()`, `kick(.manual)` | Exactly 1 pull |
| sync-engine-021 | reconcile-resync, resync-preserves-outbox | Registered a.x at cursor c1; staged op on a.x; next manifest [a.x, b.y] | `.resourcesEnabled(["b.y"])` and `.resyncPerformed`; 3rd pull cursor nil; staged op still pending; b.y has 1 row; cursor c3 |
| sync-engine-022 | disable-purge, manifest-complete | Registered a.x and b.y; staged op on b.y; next manifest [a.x] | `.resourcesDisabled(["b.y"])`, no `.resyncPerformed`; a.x keeps 1 row; b.y unregistered; op quarantined; cursor c2 |
| sync-engine-023 | bump-purge, reconcile-resync | a.x registered at 1; manifest reports 2 | `.resourcesSchemaBumped(["a.x"])`, `.resyncPerformed`; 3rd pull cursor nil; registration a.x = 2 |
| sync-engine-024 | bump-purge, reconcile-plan | a.x registered at 2; manifest reports 1 | Same bump path; registration a.x = 1; old row "1" gone, new row "2" present |
| sync-engine-025 | effective-set, change-filter, unregistered-event | hostResources [a.x]; manifest [a.x, b.y] with a change for each | `.unregisteredManifestResources(["b.y"])`; a.x 1 row; registrations exactly a.x = 1 |
| sync-engine-026 | unregistered-event | hostResources [a.x]; 3 pages each with manifest [a.x, b.y] | 3 pulls; exactly one `.unregisteredManifestResources(["b.y"])` |
| sync-engine-027 | fresh-cursor-no-resync | Fresh store; manifest [a.x, b.y] | No `.resourcesEnabled`, no `.resyncPerformed`; one `.pulledBatch` |
| sync-engine-028 | reconcile-bound | Alternating pages manifest [a.x] then [a.x, b.y], four times | 8 pulls; `.failed` payloads exactly ["manifest unstable"] |
| sync-engine-029 | reconcile-plan | registered {a.x:1, b.y:1}, effective [a.x@1] | disabled ["b.y"], bumped [], appeared [] |
| sync-engine-030 | reconcile-plan | registered {a.x:1}, effective [a.x@2, b.y@1] | bumped ["a.x"], appeared ["b.y"], disjoint |
| sync-engine-031 | reconcile-plan | registered {a.x:1, b.y:1, c.z:3}, effective [] | disabled ["a.x", "b.y", "c.z"], others empty |
| sync-engine-032 | reached-backend | Each `SyncEvent` case | true for `.idle`, `.pulledBatch`, `.authRequired`; false for the other nine |
| sync-engine-033 | uuidv7-format, uuidv7-monotonic | 1000 back-to-back `SyncID.uuidV7()` calls | Strictly increasing, no duplicates, 36 characters, character 14 is "7" |
| sync-engine-034 | catalog-shape | `ADHSyncCatalog` | 97 unique names, 44 pull-only, all schemaVersion 1; "social.follows" pull-only, "content.contacts" not |

**stop-during-cycle** and **adopted-version-sign** have no vector: the first is the open question on stop-during-cycle, and the second's intended behavior is the open question on adopted-version-sign.

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

## Deep Linking

Not applicable: `SyncEngine` exposes no URL or route; it is driven only by `kick`, `syncNow`, `pause`, `resume` and attached trigger sources.

## Localization

The engine has no localized strings. Its only human-readable text is hardcoded English, carried in `SyncEvent.failed(String)`: the `SyncEngineError` descriptions `"push made no progress"`, `"pull made no progress"` and `"manifest unstable"`, the literal `"repeated resync_required from server; backing off"`, and `String(describing:)` of any other error. A host that shows these to users must map them itself.

## Accessibility Options

Not applicable: `SyncEngine` has no visual surface, so no display accessibility option affects it.

## Feature Flags

Not applicable: no flag lookup appears in the sources; the nearest control, `hostResources`, is configuration passed at init.

## Analytics

Not applicable: the engine emits no analytics; `events` is a local `AsyncStream` for the host.

## Privacy

- **Data collected**: The engine moves the host's row data (`[String: JSONValue]` payloads) between store and transport; it collects nothing of its own beyond the host-supplied `deviceId`.
- **Storage**: The engine persists nothing; all rows, the cursor and the outbox live in the injected `SyncStore`.
- **Transmission**: Outbox ops and `deviceId` leave the device through the injected `SyncTransport`; the engine holds no credentials (the transport does).
- **Retention**: Rows purged by `purgeResources` or cleared by `resetForResync` are removed by the store; rejected and unadoptable ops are quarantined, never dropped, and their retention is the store's.

## Logging

Not applicable: the sources make no log call; every outcome is reported as a `SyncEvent` on `events` instead.

## Platform Notes

- **SwiftUI**: Source platform (`Sync/SyncEngine.swift`, `SyncEvents.swift`, `SyncProtocols.swift`, `SyncWire.swift`, `JSONValue.swift`, `SyncID.swift`, `ADHSyncCatalog.swift`). The engine is an `actor` using `CheckedContinuation` for waiters, `AsyncStream.makeStream(of:bufferingPolicy: .bufferingNewest(256))` for events, `Task.sleep(for:)` for backoff, and `Codable` for wire types. A SwiftUI host consumes `events` in a `.task` modifier and mirrors state into an `@Observable` model; `NSLock` plus `nonisolated(unsafe)` statics keep `SyncID.uuidV7` synchronous.
- **Compose**: Port the actor to a class whose methods run under a `Mutex` or a single-threaded `CoroutineDispatcher` (`limitedParallelism(1)`); note that coroutines, like Swift actors, interleave at suspension points. Events become a `MutableSharedFlow<SyncEvent>(extraBufferCapacity = 256, onBufferOverflow = DROP_OLDEST)`; waiters become `CompletableDeferred<Unit>`; backoff is `delay()` in a `Job` cancelled on reschedule; wire types use `kotlinx.serialization` with a `JsonElement` in place of `JSONValue`. `java.util.UUID` has no v7 generator, so port `SyncID` by hand.
- **React/Web**: Single-threaded JS gives the one-cycle-at-a-time rule for free between `await`s but not across them, so keep the explicit `running` flag and a promise-based waiter list. Events map to an `EventTarget` or a bounded array-backed emitter; backoff is `setTimeout` with `clearTimeout` on reschedule; `JSONValue` is plain `unknown` JSON, and numbers are IEEE doubles as in the source. Persistence would sit on IndexedDB behind the `SyncStore` interface; `fetch` implements `SyncTransport`.
- **AppKit / UIKit**: The same Swift sources apply unchanged (the target is Foundation-only and daemon-safe). A UIKit or AppKit host iterates `events` in a `Task` owned by its controller, calls `pause()` before a sign-out purge, and uses `BGTaskScheduler` (iOS) or a launchd timer (macOS daemon) as a `SyncTriggerSource` that yields `.periodic`.
- **WinUI 3**: Port the actor to a class that serialises cycles with a `SemaphoreSlim(1, 1)` or a dedicated single-threaded `TaskScheduler`; `await` interleaving means the `running`/`pendingReason` coalescing logic must be kept, not replaced by the lock. Waiters become `TaskCompletionSource` instances completed at cycle end; events become a `System.Threading.Channels.Channel<SyncEvent>` created with `BoundedChannelOptions(256) { FullMode = BoundedChannelFullMode.DropOldest }`, which the UI marshals to its thread through `DispatcherQueue.TryEnqueue` before updating an `INotifyPropertyChanged` view model or `ObservableCollection`. Backoff is `Task.Delay` with a `CancellationTokenSource` replaced on each reschedule. `HttpClient` implements `SyncTransport` (map `HttpStatusCode.Unauthorized` and `Gone` to the two special errors); `System.Text.Json` with `JsonNode`/`JsonElement` replaces `JSONValue` and wire `Codable`, with `JsonSerializerOptions` camelCase naming to match the Swift property names. The store would sit on SQLite (`Microsoft.Data.Sqlite`) under `Windows.Storage.ApplicationData.Current.LocalFolder`. `Guid.CreateVersion7()` (.NET 9) produces v7 ids but does not guarantee same-millisecond monotonic ordering, so port `SyncID`'s counter logic if ordering matters.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Sync/ADHSyncCatalog.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/JSONValue.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/SyncEngine.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/SyncEvents.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/SyncID.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/SyncProtocols.swift` |
| apple | `packages/apple/AgenticToolkit/Sync/SyncWire.swift` |

## Design Decisions

### Server manifest is authoritative and complete

**Decision**: Every pull page's manifest is treated as the full enrollment set; a registered resource missing from it is disabled on that page.

**Rationale**: The source comment (fix B1) states the client cannot distinguish "server dropped it" from "server forgot it", so omission is the signal and the server must send the full manifest every page.

**Approved**: pending

### Schema downgrade is a bump

**Decision**: `bumped` uses a not-equal comparison, so a lower manifest `schemaVersion` purges and resyncs exactly like a higher one.

**Rationale**: Per fix A2, mirror rows written under one schema cannot be trusted under another in either direction.

**Approved**: pending

### Unadoptable conflicts quarantine

**Decision**: A conflict with no `current`, or with a `sync_version` that cannot become an integer, is recorded as `.rejected` so the store quarantines it.

**Rationale**: Fixes p2-Minor9 and A3: the old behaviour either dropped the op silently or let `store.apply` throw before `complete`, re-pushing the op every cycle.

**Approved**: pending

### Bounded loops everywhere

**Decision**: Pull no-progress (2), reconcile resets per cycle (3), nested 410 resyncs (1 immediate) and push no-progress all convert a potential hot loop into a regular failure with backoff.

**Rationale**: Each guards a misbehaving or lagging server (the source cites a cohort stall guard and a moving GC horizon); failing into backoff keeps the outbox intact while giving the server time to catch up.

**Approved**: pending

### Joining `syncNow` waits; `kick` does not

**Decision**: A `syncNow` that coalesces into a running cycle suspends until that cycle ends, while `kick` returns at once.

**Rationale**: The doc comment makes `syncNow` an honest "a sync just ran" signal for pull-to-refresh spinners and background-task completion handlers.

**Approved**: pending

### Pause buffers nothing

**Decision**: Kicks during `pause()` are dropped and a pending reason is cleared when a cycle ends paused; `resume()` does not sync.

**Rationale**: `pause()` exists for identity-boundary operations such as a sign-out purge; resurrecting a reason queued before the purge would sync the wrong identity's state.

**Approved**: pending

### Event buffer of 256 newest

**Decision**: `events` buffers the newest 256 events instead of an unbounded buffer.

**Rationale**: The init comment calls it a backstop against a host that never subscribes; both shipped hosts drain continuously, and the obligation to drain still stands.

**Approved**: pending

### Snapshot registrations once per cycle

**Decision**: Registrations are read once per cycle and `prepare` is skipped when the snapshot already covers the effective set (fix H5+H1).

**Rationale**: Avoids a store read and a no-op store write on every steady-state page.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | failed | Reliability |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | partial | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | passed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |

The engine depends only on the `SyncStore`, `SyncTransport` and `SyncTriggerSource` protocols, and `SyncEngineTests` exercises every cycle path against in-memory fakes, including the pure `reconcilePlan`. Outbox ops are never dropped: every failure keeps them and backs off, 410 replays them under their original opIds, and unresolvable ones are quarantined. Explicit error handling and data integrity are partial because `adoptedVersion` accepts sign-prefixed versions the documented format forbids, and because `stop()` does not stop a cycle already in flight from re-arming a retry. Retry with backoff is partial because the exponential delay carries no jitter. Timeout handling fails because the engine sets no timeout of its own and relies entirely on the injected transport.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the Apple `Sync` sources and `SyncEngineTests` |
