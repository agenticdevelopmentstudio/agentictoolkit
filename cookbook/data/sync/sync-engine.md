---
id: 355a8f54-aee5-45cd-a28d-12c3b7a3085c
title: Sync Engine
domain: agentictoolkit://cookbook/data/sync/sync-engine
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Offline-sync state machine: pull loop, manifest reconciliation, outbox
  push with last-write-wins/delete-wins conflict adoption, HTTP 410 resync, and
  exponential backoff.'
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
- agentictoolkit://cookbook/data/sync/offline-sync-client
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

# Sync Engine

## Overview

The sync engine is the client half of an offline-first sync protocol: a state
machine that runs one *cycle* at a time — pull every page of server changes
into a local mirror, reconcile the server's resource manifest against what the
host has registered, then drain the local outbox to the server and adopt the
server's row on every conflict. It owns no storage, no network code and no
credentials: persistence is injected as a store, the wire as a transport, and
wake-ups as trigger sources. Progress is reported only through an events
stream.

The recipe also covers the value types the engine's contract is written in:
the wire shapes (a cursor, a resource descriptor, a change, a pull response, a
push op, a push request, a push result, a push response), a schema-flexible
JSON payload type, a UUIDv7 id generator, and a generated resource catalog.
The product-specific enrollment and backend rules the engine serves are
specified in
[Offline Sync Client](agentictoolkit://cookbook/data/sync/offline-sync-client).

Use it when a host (an app or a daemon) keeps a local mirror of server rows,
lets the user edit offline, and needs those edits pushed later without ever
being lost.

## Behavioral Requirements

### Lifecycle and concurrency

- **single-owner-state**: The engine MUST confine every mutable field (running flag, pending reason, auth-paused flag, host-paused flag, cycle waiters, consecutive-failure count, consecutive-resync count, trigger tasks, retry task) to itself, accessed only through its own operations.
- **concurrency-safe-values**: Every wire type, JSON value, event, kick reason, local mutation and the engine's configuration MUST be safe to pass across concurrent contexts, and the store, transport and trigger-source contracts MUST require the same of their conforming implementations.
- **single-cycle**: The engine MUST run at most one cycle at a time; a kick that arrives while a cycle is running MUST NOT start a second concurrent cycle.
- **events-stream**: `events` MUST be an ordered event stream created with a buffering policy of the newest 256 events; when a subscriber falls more than 256 events behind, the oldest undelivered events MUST be dropped.
- **attach-trigger**: Attaching a trigger source MUST start a background process that calls `kick` once for every value the trigger's kick stream yields, in stream order, and MUST hold the engine weakly, so an attached trigger never keeps the engine alive.
- **stop-cancels**: `stop` MUST cancel every attached trigger task, cancel any pending retry task, and finish the `events` stream.
- **stop-in-flight**: `stop` MUST NOT wait for or cancel a cycle already in flight; that cycle continues to call the store and transport until it ends.
- **stop-during-cycle**: NEEDS REVIEW: Not implemented in source. `stop` sets no stopped flag, so a cycle suspended mid-operation when `stop` runs can still reach the retry scheduler on failure and arm a new retry that later calls `kick` with reason `periodic` after the host stopped the engine, with every event it yields discarded by the finished stream; a stopped-state contract (refuse `kick`/`syncNow`/`scheduleRetry` after `stop`) or a documented statement that `stop` must follow `pause` would settle it.

### Entry points and coalescing

- **kick-paused**: `kick` MUST return without effect while host-paused is true.
- **kick-coalesce**: `kick` called while a cycle is running MUST record the reason as the pending reason only when none is already recorded, and MUST return without waiting for the cycle.
- **kick-start**: `kick` called while idle and unpaused MUST run a cycle through `syncNow` and return when that call returns.
- **pending-first-wins**: When several kicks coalesce into one running cycle, only the first recorded reason MUST be kept; later reasons are discarded.
- **syncnow-paused**: `syncNow` MUST return immediately, without a cycle, while host-paused is true.
- **syncnow-auth-gate**: While auth-paused is true, `syncNow` MUST return immediately unless the reason is `manual` or `hostSpecific`; for those two it MUST clear the auth-paused state and proceed.
- **syncnow-join**: `syncNow` called while a cycle is running MUST record its reason as the pending reason (first wins) and MUST suspend until the running cycle finishes; it MUST NOT wait for the follow-up cycle its reason may trigger.
- **follow-up-cycle**: When a cycle ends with host-paused false and a pending reason recorded, the engine MUST clear the pending reason and immediately run exactly one more cycle with that reason.
- **pause-drops-pending**: When a cycle ends with host-paused true, the engine MUST discard any pending reason rather than run it after `resume`.
- **pause-wait**: `pause` MUST set the host-paused state; if a cycle is running it MUST suspend until that cycle finishes, and if none is running it MUST return immediately.
- **resume-no-sync**: `resume` MUST clear the host-paused state and MUST NOT start a cycle itself.
- **waiters-resumed**: At the end of every cycle, every caller waiting on `pause` or a joining `syncNow` MUST be resumed exactly once, before any follow-up cycle starts.

### Cycle outcome

- **cycle-order**: A cycle MUST emit a `started` event carrying the reason, then run the pull loop to completion, then the push loop to completion; the push loop MUST NOT start if the pull loop raised an error.
- **cycle-success**: A cycle whose pull and push loops both complete MUST reset the consecutive-failure and consecutive-resync counts to 0 and emit an `idle` event.
- **unauthorized-pause**: An unauthorized transport error raised anywhere in the cycle MUST set the auth-paused state, emit an `authRequired` event, and MUST NOT emit a `failed` event or schedule a retry.
- **resync-required**: A resync-required transport error raised in the cycle MUST run the resync procedure (see **resync-procedure**) instead of emitting a `failed` event.
- **generic-failure**: Any other error MUST increment the consecutive-failure count, emit a `failed` event carrying a description of the error, and schedule a retry; no outbox op may be removed as a result.
- **engine-error-text**: The engine's internal errors MUST describe themselves as "push made no progress", "pull made no progress" and "manifest unstable" for a push-made-no-progress, pull-made-no-progress and manifest-unstable error respectively, so those strings are the `failed` event's payload.
- **invalid-response-generic**: A generic transport error or an invalid-response error (carrying a status code) MUST take the generic-failure path; the engine gives them no special handling.

### Backoff

- **backoff-delay**: A scheduled retry MUST wait `min(baseBackoff * 2^(min(consecutiveFailures, 16) - 1), maxBackoff)` seconds, then call `kick` with reason `periodic`.
- **backoff-single-timer**: Scheduling a retry MUST cancel any retry task already pending, so at most one retry timer exists.
- **backoff-cancelled**: A retry task cancelled before its delay elapses MUST NOT kick.

### Pull loop

- **registrations-snapshot**: The pull loop MUST read `registrations` once at cycle start and keep that local snapshot current as reconciliation purges and preparation registers, rather than re-reading it per page.
- **pull-request**: Each page MUST call the transport's pull operation with the store's current `cursor` and `pullLimit`.
- **effective-set**: The effective resource set MUST equal the page's manifest when `hostResources` is not set, and the manifest filtered to resources whose names appear in `hostResources` otherwise; the manifest's `schemaVersion` is the one kept.
- **reconcile-before-prepare**: Reconciliation MUST run on every page, before the page's `prepare` and `apply`.
- **prepare-when-changed**: The engine MUST call `prepare` with the effective set only when the snapshot does not already hold every effective resource at the identical `schemaVersion`, and MUST then record those versions in the snapshot.
- **change-filter**: When `hostResources` is set, only changes whose resource is in the effective set MUST be applied; when it is not set, every change in the page MUST be applied unfiltered.
- **apply-advances**: The page's applicable changes MUST be passed to `apply`, together with the response's cursor, in a single call.
- **pulled-batch-event**: After each successful apply the engine MUST emit a `pulledBatch` event carrying the applicable-change count and the new cursor, including for an empty page.
- **pull-continues**: The pull loop MUST request another page while the last response's `hasMore` is true, and stop when it is false.
- **pull-no-progress**: A response with no changes, `hasMore` true, and a cursor equal to the one requested MUST count as no progress; 2 consecutive no-progress responses MUST raise a pull-made-no-progress error, and any other response MUST reset the count to 0.

### Manifest reconciliation

- **reconcile-plan**: Reconciliation planning MUST be a pure computation over the registered and effective resource sets, returning three name lists, each sorted ascending: `disabled` (registered, absent from the effective set), `bumped` (registered at a `schemaVersion` different from the manifest's, higher or lower), and `appeared` (effective, not registered, and not in `bumped`).
- **unregistered-event**: When `hostResources` is set, the engine MUST emit an `unregisteredManifestResources` event carrying the sorted manifest names outside the effective set, only when that list is non-empty and differs from the list last emitted in the same cycle.
- **disable-purge**: A non-empty `disabled` list MUST be passed to `purgeResources`, removed from the snapshot, and reported as a `resourcesDisabled` event; disablement alone MUST NOT reset the cursor or resync.
- **manifest-complete**: The engine MUST treat each page's manifest as complete: a registered resource missing from any single page MUST be disabled on that page, with no floor for an empty or partial manifest.
- **bump-purge**: A non-empty `bumped` list MUST be passed to `purgeResources`, removed from the snapshot, and reported as a `resourcesSchemaBumped` event.
- **fresh-cursor-no-resync**: When the page was requested with no cursor, appearance and bump MUST NOT trigger a resync.
- **reconcile-resync**: When the page was requested with a cursor and `appeared` or `bumped` is non-empty, the engine MUST call `resetForResync`, emit a `resourcesEnabled` event when `appeared` is non-empty, emit a `resyncPerformed` event, skip the page's changes, and restart the pull from the (now cleared) stored cursor.
- **reconcile-bound**: More than 3 reconcile-triggered resets in one cycle MUST raise a manifest-unstable error.

### Push loop

- **push-batch**: The push loop MUST fetch up to `pushBatchSize` ops with `pendingOps` and return when none remain.
- **push-request**: Each batch MUST be sent as one push request carrying the configured `deviceId` and the batch of ops.
- **applied-result**: An applied result MUST be counted as applied and forwarded unchanged to `complete`, including its new version.
- **rejected-result**: A rejected result MUST be counted as rejected and forwarded unchanged to `complete`.
- **conflict-unmatched**: A conflict result whose `opId` matches no op in the batch MUST be counted as a conflict and forwarded unchanged, with nothing adopted.
- **conflict-no-current**: A conflict result with no current row MUST be counted as rejected and forwarded as rejected with its original reason, with nothing adopted.
- **conflict-unadoptable**: A conflict result whose current row's `sync_version` cannot be adopted MUST be counted as rejected and forwarded as rejected with its original reason, with nothing adopted.
- **adopted-version**: A missing `sync_version` MUST adopt as "0"; a numeric value MUST adopt as its decimal integer text only when it converts exactly to a 64-bit integer; a string value MUST adopt verbatim only when it parses as an integer; every other JSON type MUST be unadoptable.
- **adopted-version-sign**: NEEDS REVIEW: Not implemented in source. The version-adoption logic documents that a change's `syncVersion` expects digits only, but the integer parser used accepts a leading `+` or `-` and negative numbers, so "-5", "+5" or a negative number pass through to `apply`, which could raise an error and re-push the op every cycle (the wedge the fix set out to remove); a non-negative, unsigned check or a store contract that accepts signed text would settle it.
- **conflict-adopt**: An adoptable conflict MUST produce one change record for the op's resource and row id at the adopted version, emit a `conflictResolved` event, and forward the result unchanged.
- **delete-wins**: The adopted change MUST be a delete with no data when the current row's `deleted_at` is present and not null, and an upsert otherwise; a missing `deleted_at` key counts as not deleted.
- **strip-bookkeeping**: An adopted upsert MUST carry the current row with the `sync_version` and `sync_stamped_at` keys removed.
- **adopt-before-complete**: All of a batch's adoptions MUST be applied in one `apply` call with no cursor advance, skipped when there are none, before `complete` is called with every result.
- **pushed-event**: After `complete`, the engine MUST emit a `pushed` event with the batch's applied, conflict and rejected counts.
- **push-no-progress**: After each batch, when every attempted `opId` is still returned by `pendingOps` at the configured `pushBatchSize`, the engine MUST raise a push-made-no-progress error; this covers an empty results list for a non-empty batch.

### Resync (HTTP 410)

- **resync-procedure**: The resync procedure MUST call `resetForResync`, emit a `resyncPerformed` event, run the pull loop, then the push loop; on success it MUST reset both failure counters and emit an `idle` event.
- **resync-preserves-outbox**: Resync MUST replay the preserved outbox under its original `opId`s; the engine MUST NOT re-stage or re-mint ops.
- **resync-unauthorized**: An unauthorized error during resync MUST set the auth-paused state and emit an `authRequired` event, with no `failed` event and no retry.
- **resync-nested-once**: A resync-required error during resync MUST increment the consecutive-resync count; while it is 1 or less the resync MUST be retried immediately, and above 1 the engine MUST increment the consecutive-failure count, emit a `failed` event with message "repeated resync_required from server; backing off", and schedule a retry.
- **resync-counter-persists**: The consecutive-resync count MUST persist across cycles and reset only on a fully successful cycle or resync.
- **resync-other-failure**: Any other error during resync MUST take the generic-failure path.

### Store and transport contract (injected)

- **store-atomic**: The store contract MUST make `stage` and `apply` atomic with the outbox mutations they imply.
- **store-apply-nil-cursor**: `apply` with no cursor MUST apply without advancing the cursor.
- **store-stage-registered**: `stage` MUST raise an unknownResource error for a resource never passed to `prepare`; hosts MUST `prepare` before staging.
- **store-prepare-idempotent**: `prepare` MUST be idempotent, upserting schema versions.
- **store-complete-terminal**: `complete` MUST resolve ops by `opId`, and a rejected op MUST never be retried under the same `opId`; a retry MUST go through a fresh `stage`.
- **store-reset**: `resetForResync` MUST clear mirror rows and the cursor, preserve the outbox, and never delete the database file.
- **store-purge**: `purgeResources` MUST delete the resources' mirror rows, quarantine their pending and in-flight ops, remove their registrations, and leave the cursor untouched.
- **transport-errors**: The transport contract MUST map HTTP 401 to an unauthorized error and HTTP 410 to a resync-required error; the engine owns no credentials.

### Supporting value types

- **jsonvalue-decode-order**: The JSON value type MUST decode null, then boolean, then floating-point number, then string, then array, then object, and raise a decoding error ("not JSON") when none match.
- **jsonvalue-number-lossy**: Every JSON number MUST decode to a floating-point number; integers beyond 2^53 lose precision by design of this projection.
- **jsonvalue-accessors**: Looking up a key MUST return nothing on a non-object value, reading it as a string MUST return nothing on a non-string value, and a null check MUST be true only for the null value.
- **uuidv7-format**: The id generator MUST return a 36-character lowercase hyphenated UUID with version nibble 7 and the RFC 4122 variant bits.
- **uuidv7-monotonic**: Ids minted by one process MUST sort strictly increasing: a new millisecond resets a 12-bit counter to a random value in 0...0x7FF, the same or an earlier millisecond increments it, and a counter at 0xFFF borrows the next millisecond and restarts at 0; all of this happens under one process-wide serialization point.
- **reached-backend**: Each event's reachedBackend flag MUST be true for `pulledBatch`, `idle` and `authRequired` and false for every other event.
- **catalog-shape**: The generated resource catalog MUST list 97 unique resources, all at schema version 1, and its pull-only subset MUST be a 44-name subset of them; the catalog is generated and is client knowledge only — the server manifest gates what syncs.
- **engine-ignores-watermark**: The engine MUST NOT read the push response's watermark field.

## Appearance

Not applicable — this is a sync state machine, not a visual component.

## States

Not applicable — this is a sync state machine, not a visual component.

## Accessibility

Not applicable — this is a sync state machine, not a visual component.

## Conformance Test Vectors

All engine vectors use a configuration with deviceId "test-device", pullLimit 10, pushBatchSize 5, a scripted transport and an in-memory store.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sync-engine-001 | pull-request, pull-continues, apply-advances | Pages `a` (cursor c1, hasMore true) then `b` (cursor c2, hasMore false); `syncNow` with reason manual | Cursors sent are none then c1; stored cursor is c2; 2 mirror rows |
| sync-engine-002 | conflict-adopt, strip-bookkeeping, adopt-before-complete | Staged upsert r1; push returns a conflict with current row title "theirs", sync_version 9, sync_stamped_at, deleted_at empty | Outbox empty; mirror r1 title "theirs", syncVersion "9"; no sync_version/sync_stamped_at in its data |
| sync-engine-003 | delete-wins | Same as 002 but deleted_at is a timestamp | Outbox empty; r1 tombstoned with syncVersion "9" and empty data; live row count 0 |
| sync-engine-004 | conflict-no-current | Conflict result with no current row, reason "server_row_missing" | Outbox empty; op in quarantine; local title still "mine" |
| sync-engine-005 | conflict-unadoptable, adopted-version | Conflict result with sync_version being a non-finite number | Op quarantined; outbox empty; local row untouched |
| sync-engine-006 | conflict-unadoptable, pushed-event, cycle-success | Two ops: "bad" conflict with sync_version "not-a-number", "good" applied with new version "7" | Outbox empty; only "bad" quarantined; events contain an idle event, no failed event |
| sync-engine-007 | unauthorized-pause, syncnow-auth-gate | First pull raises an unauthorized error; then `syncNow` with reason periodic; then `syncNow` with reason manual | 1 pull after the periodic call; 2 pulls after the manual call |
| sync-engine-008 | resync-required, resync-preserves-outbox | Stored row "old" at cursor "stale", one staged op; pull raises a resync-required error, then returns row "fresh" | "fresh" present, "old" gone; the staged opId pushed exactly once; outbox empty |
| sync-engine-009 | resync-unauthorized | Pulls: a resync-required error, then an unauthorized error; then `syncNow` with reason periodic | 2 pulls total; events include a resyncPerformed event and an authRequired event, no failed event |
| sync-engine-010 | resync-nested-once, resync-counter-persists | Transport always raises a resync-required error; `syncNow` with reason manual, three times | Pull count 3, then 5, then 7; 3 failed events each containing "resync_required"; outbox still 1 op |
| sync-engine-011 | generic-failure | Push raises a generic transport error ("boom") | Outbox still holds 1 op |
| sync-engine-012 | backoff-delay, cycle-success | Pulls fail 3 times, succeed, fail once, succeed; baseBackoff 0.02 | Retries fire unaided; the post-success retry gap is under 3x the first retry gap; 4 failed events |
| sync-engine-013 | push-no-progress | Push result opId "bogus-op-id-not-in-outbox" applied | Outbox still 1 op; a failed event emitted |
| sync-engine-014 | push-no-progress, engine-error-text | Non-empty batch answered with an empty results list | No idle event; first failed event's payload is "push made no progress"; outbox 1 op |
| sync-engine-015 | rejected-result, store-complete-terminal | Push result rejected, reason "invalid_data"; then a second `syncNow` | Op quarantined; outbox empty; exactly 1 push request across both cycles |
| sync-engine-016 | pull-no-progress | Four pages all empty, cursor "stalled", hasMore true | Exactly 3 pulls; first failed event's payload is "pull made no progress" |
| sync-engine-017 | pause-wait | `pause` called while a gated pull is in flight | `pause` has not returned before release; returns after the cycle ends |
| sync-engine-018 | syncnow-join, follow-up-cycle | Two concurrent `syncNow` calls (manual, periodic) against a gated pull | Neither returns before release; both return after; exactly 2 pulls |
| sync-engine-019 | kick-paused, syncnow-paused, pause-drops-pending | `pause` while idle, then `kick` with reason periodic and `syncNow` with reason manual | 0 pulls |
| sync-engine-020 | resume-no-sync, kick-start | `pause`, `kick` with reason periodic, `resume`, `kick` with reason manual | Exactly 1 pull |
| sync-engine-021 | reconcile-resync, resync-preserves-outbox | Registered a.x at cursor c1; staged op on a.x; next manifest [a.x, b.y] | A resourcesEnabled event naming ["b.y"] and a resyncPerformed event; 3rd pull cursor cleared; staged op still pending; b.y has 1 row; cursor c3 |
| sync-engine-022 | disable-purge, manifest-complete | Registered a.x and b.y; staged op on b.y; next manifest [a.x] | A resourcesDisabled event naming ["b.y"], no resyncPerformed event; a.x keeps 1 row; b.y unregistered; op quarantined; cursor c2 |
| sync-engine-023 | bump-purge, reconcile-resync | a.x registered at 1; manifest reports 2 | A resourcesSchemaBumped event naming ["a.x"], a resyncPerformed event; 3rd pull cursor cleared; registration a.x = 2 |
| sync-engine-024 | bump-purge, reconcile-plan | a.x registered at 2; manifest reports 1 | Same bump path; registration a.x = 1; old row "1" gone, new row "2" present |
| sync-engine-025 | effective-set, change-filter, unregistered-event | hostResources [a.x]; manifest [a.x, b.y] with a change for each | An unregisteredManifestResources event naming ["b.y"]; a.x 1 row; registrations exactly a.x = 1 |
| sync-engine-026 | unregistered-event | hostResources [a.x]; 3 pages each with manifest [a.x, b.y] | 3 pulls; exactly one unregisteredManifestResources event naming ["b.y"] |
| sync-engine-027 | fresh-cursor-no-resync | Fresh store; manifest [a.x, b.y] | No resourcesEnabled event, no resyncPerformed event; one pulledBatch event |
| sync-engine-028 | reconcile-bound | Alternating pages manifest [a.x] then [a.x, b.y], four times | 8 pulls; failed event payloads exactly ["manifest unstable"] |
| sync-engine-029 | reconcile-plan | registered {a.x:1, b.y:1}, effective [a.x@1] | disabled ["b.y"], bumped [], appeared [] |
| sync-engine-030 | reconcile-plan | registered {a.x:1}, effective [a.x@2, b.y@1] | bumped ["a.x"], appeared ["b.y"], disjoint |
| sync-engine-031 | reconcile-plan | registered {a.x:1, b.y:1, c.z:3}, effective [] | disabled ["a.x", "b.y", "c.z"], others empty |
| sync-engine-032 | reached-backend | Each event kind | true for idle, pulledBatch, authRequired; false for the other nine |
| sync-engine-033 | uuidv7-format, uuidv7-monotonic | 1000 back-to-back id-generator calls | Strictly increasing, no duplicates, 36 characters, character 14 is "7" |
| sync-engine-034 | catalog-shape | The generated resource catalog | 97 unique names, 44 pull-only, all schemaVersion 1; "social.follows" pull-only, "content.contacts" not |

**stop-during-cycle** and **adopted-version-sign** have no vector: the first is the open question on stop-during-cycle, and the second's intended behavior is the open question on adopted-version-sign.

## Edge Cases

- **Empty outbox**: `pendingOps` returns nothing — the push loop MUST return without calling the transport.
- **Empty pull page that advances the cursor**: MUST be applied (zero changes), emit a `pulledBatch` event with a change count of 0, and reset the no-progress count.
- **Same-cursor page with changes**: MUST NOT count as no progress.
- **Empty manifest on a non-fresh cursor**: every registered resource MUST be disabled — purged and its ops quarantined — because the manifest is read as complete.
- **Change for an unregistered resource with no host resource list configured**: the engine MUST pass it to `apply` unfiltered; whatever error the store raises (an in-memory store raises an unknownResource error) MUST take the generic-failure path and back off. The server owns sending only manifest resources.
- **Push result for an op outside the batch**: an applied or rejected result MUST be forwarded to `complete` unchanged; the engine does not check it against the attempted batch, so the store resolves whatever op carries that `opId`.
- **Conflict for an op outside the batch**: MUST be counted as a conflict and forwarded, with nothing adopted.
- **Negative or zero consecutive-failure count**: cannot occur — every retry is scheduled after an increment, so the exponent is at least 0 (2^0 × baseBackoff) and is capped at 15 (exponent `min(n,16) - 1`).
- **Very large failure count**: the delay MUST NOT exceed `maxBackoff` (default 3600 seconds).
- **Concurrent kicks**: MUST coalesce into the running cycle plus at most one follow-up cycle carrying the first coalesced reason.
- **Kick while auth-paused**: a kick with reason periodic, and a retry's periodic kick, MUST return without a pull; only a manual or hostSpecific reason resumes.
- **Pause during a cycle**: the running cycle MUST finish; any reason coalesced before or during the pause MUST be dropped.
- **Event subscriber absent**: events past 256 MUST drop the oldest; the engine keeps running.
- **Events after `stop`**: MUST be discarded silently by the finished stream.
- **Cancellation of an in-flight transport call**: the engine offers none; cancellation reaches the transport only if the host cancels its own call to `syncNow`.
- **Timeouts**: the engine applies none; any timeout is the transport's and surfaces as a raised error on the generic-failure path.
- **Offline / unreachable server**: the transport's raised error MUST take the generic-failure path, keep every outbox op, and back off; connectivity-restored wake-ups arrive only through an attached trigger source yielding a connectivity-restored value.
- **Crash mid-cycle**: the engine holds no durable state; crash safety MUST come from the store's atomic `stage`/`apply` (see **store-atomic**).
- **Clock moving backwards**: the id generator MUST keep incrementing the counter from the last millisecond rather than reuse an earlier timestamp.
- **Counter overflow in one millisecond**: the id generator MUST borrow the next millisecond and restart the counter at 0.
- **Undecodable JSON token**: the JSON value type's decoding MUST raise a decoding error with message "not JSON".

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deviceId` | string | required | Sent as the push request's deviceId on every push |
| `pullLimit` | integer | `500` | Limit passed to each pull request |
| `pushBatchSize` | integer | `100` | Max ops per push batch and per no-progress re-check |
| `baseBackoff` | duration (seconds) | `2` | Seconds for the first retry delay |
| `maxBackoff` | duration (seconds) | `3600` | Cap on any retry delay, in seconds |
| `hostResources` | optional list of resources | none | Absent accepts the whole manifest; set narrows the effective set to manifest ∩ hostResources |
| `store` | store contract implementation | required (construction) | Mirror, outbox, cursor and registrations |
| `transport` | transport contract implementation | required (construction) | Pull/push wire and credentials |
| trigger | trigger source implementation | none | Attached with `attach`; any number |
| `maxConsecutiveNoProgressPulls` | constant | `2` | Not configurable |
| `maxReconcileResyncsPerCycle` | constant | `3` | Not configurable |
| event buffer | constant | newest 256 | Not configurable |

No environment variables or settings keys are read.

## Deep Linking

Not applicable: the engine exposes no URL or route; it is driven only by `kick`, `syncNow`, `pause`, `resume` and attached trigger sources.

## Localization

The engine has no localized strings. Its only human-readable text is hardcoded English, carried in a `failed` event's message: the engine's internal error descriptions "push made no progress", "pull made no progress" and "manifest unstable", the literal "repeated resync_required from server; backing off", and a description of any other error. A host that shows these to users must map them itself.

## Accessibility Options

Not applicable: the engine has no visual surface, so no display accessibility option affects it.

## Feature Flags

Not applicable: no flag lookup appears in the sources; the nearest control, `hostResources`, is configuration passed at construction.

## Analytics

Not applicable: the engine emits no analytics; `events` is a local stream for the host.

## Privacy

- **Data collected**: The engine moves the host's row data (JSON object payloads) between store and transport; it collects nothing of its own beyond the host-supplied `deviceId`.
- **Storage**: The engine persists nothing; all rows, the cursor and the outbox live in the injected store.
- **Transmission**: Outbox ops and `deviceId` leave the device through the injected transport; the engine holds no credentials (the transport does).
- **Retention**: Rows purged by `purgeResources` or cleared by `resetForResync` are removed by the store; rejected and unadoptable ops are quarantined, never dropped, and their retention is the store's.

## Logging

Not applicable: the sources make no log call; every outcome is reported as an event on `events` instead.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/sync/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from the Apple `Sync` sources and `SyncEngineTests` |
