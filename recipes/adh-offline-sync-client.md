---
id: d3a0b65f-92c0-43c1-b04c-77638eb72044
title: ADH Offline Sync Client
domain: agenticdeveloperhub://recipes/adh-offline-sync-client
type: ingredient
category: engine
version: 1.1.0
status: draft
language: en
created: '2026-07-22'
modified: '2026-09-09'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The offline-sync client contract as adh implements it: the enrollment-driven manifest lifecycle, cohort cursor, push modes, tombstones and purge rules, cited to the Swift targets and backend files that hold them."
platforms:
  - swift
  - apple
tags:
  - sync
  - offline
  - engine
  - adh
depends-on: []
related:
  - agenticdeveloperhub://recipes/offline-sync-client
references:
  - src/adh/src/sync/wire.ts (adhbackend)
  - src/adh/src/sync/registry.ts (adhbackend)
  - src/adh/docs/architecture/sync.md (adhbackend)
  - packages/apple/AgenticToolkit/Sync (agentictoolkit)
  - packages/apple/AgenticToolkit/SyncGRDB (agentictoolkit)
---

# ADH Offline Sync Client

> **Two recipes, one contract.** The public `offline-sync-client`
> (`agenticdeveloperhub://recipes/offline-sync-client`, in the agenticdevelopertoolkit
> repo — see `related` above) states the same contract as a *pattern*, for readers with no
> access to adh — it names no files, because that repo holds no implementation of it.
> **This** is the adh-concrete version: every path below resolves in this repo or in
> adhbackend, and `references` is populated so a reader can go read the code. Change
> the contract in both, or in neither.

## Overview

The offline sync client is the client half of adh's offline-first sync: a state
machine that keeps a local mirror of server data current, queues local mutations
while offline, and pushes them when connectivity returns. It is a headless
**engine** — no visual surface — so this recipe omits Appearance and
Accessibility.

The reference implementation ships as two Swift library targets:

- **`AgenticToolkitSync`** — the platform-neutral core: `SyncEngine` (the
  pull → reconcile → push cycle), the wire types (`SyncWire.swift`), the
  `SyncStore`/`SyncTransport`/`SyncTriggerSource` protocols
  (`SyncProtocols.swift`), the observability events (`SyncEvents.swift`), and
  `ADHSyncCatalog` (the adh resource catalog mirrored client-side).
- **`AgenticToolkitSyncGRDB`** — `GRDBSyncStore`, the on-disk `SyncStore`
  (JSON-payload mirror tables, an outbox, a conflicts audit) on a WAL-mode
  SQLite pool.

The contract is **server-authoritative**. The backend (`/sync/pull`,
`/sync/push`) owns the manifest of syncable resources, the single opaque cohort
cursor, and the outcome of every pushed op; the client mirrors what it is told,
queues what it originates, and never invents behavior the server did not grant.
A client-side catalog (`ADHSyncCatalog`) is an optimization — it lets a host
register the right resources and refuse pull-only writes before a round trip —
but it never overrides the manifest or a push result.

Each pull returns a **manifest** (the resources the server will sync for this
identity), a batch of **changes** (upserts and delete tombstones), a **cursor**,
and a `hasMore` flag. The client intersects the manifest with its
host-registered set to get the **effective set**, reconciles enrollment
transitions (a resource appearing, disappearing, or bumping schema version),
applies the batch atomically with the cursor, and drains `hasMore`. It then
drains its outbox to `/sync/push`, adopting server rows on conflict and adopting
new versions on apply.

## Behavioral Requirements

- **effective-set-is-intersection**: The client MUST compute its active resource
  set as the server manifest intersected with the host-registered set, on every
  pull response.
- **unregistered-resources-surfaced**: The client MUST ignore manifest resources
  the host did not register and MUST surface them via an observability event.
- **appearance-forces-full-resync**: When a resource enters the effective set
  while the cursor is non-fresh, the client MUST reset its mirror and cursor and
  re-pull from scratch, because rows changed while the resource was outside the
  set are permanently behind the server's single cursor stream.
- **resync-preserves-outbox**: A full resync MUST preserve pending local
  mutations for resources still in the effective set, replaying them with their
  original opIds.
- **disappearance-purges-mirror**: When a resource leaves the effective set, the
  client MUST stop serving it, delete its mirrored rows, and remove its
  registration, without touching the cursor.
- **disappearance-quarantines-outbox**: Pending local mutations for a resource
  that left the effective set MUST move to quarantine — surfaced, never silently
  dropped, never pushed.
- **schema-bump-is-disappear-then-appear**: A registered resource whose manifest
  schemaVersion **changes in either direction** — a rise OR a fall — MUST be
  purged and then treated as an appearance. A downgrade (e.g. a server rollback)
  is as much a schema mismatch as an upgrade: mirror rows written under the old
  version cannot be trusted against the new one, so both directions purge + resync.
- **cursor-is-opaque**: The client MUST treat the cursor as an opaque string —
  never fabricated, parsed, or compared beyond equality — and MUST persist it
  only together with an atomically applied pull batch.
- **tombstones-apply-as-deletes**: A change with op `delete` carries no data and
  MUST be applied as a local soft delete.
- **pull-drains-has-more**: The client MUST continue pulling while the server
  reports more, applying each batch atomically before requesting the next.
- **pull-only-refused-at-stage**: The client MUST refuse to stage a local
  mutation for a route-mode (pull-only) resource at the write path.
- **rejected-is-terminal**: Every push result with status `rejected` (reasons
  include unknown_resource, not_enrolled, route_only, invalid_data,
  constraint_violation) MUST quarantine the op and MUST NOT retry it.
- **conflict-adopts-server-row**: A push result with status `conflict` MUST
  resolve by adopting the server's current row locally (delete wins via its
  deleted_at), preserving the server's sync_version.
- **applied-adopts-new-version**: A push result with status `applied` that
  carries newVersion MUST adopt it as the row's base version immediately.
- **identity-change-purges**: A credential/identity change MUST purge mirrored
  rows, cursor, and the entire outbox before syncing as the new identity.
- **recovery-never-deletes-database**: No recovery or purge path may delete the
  database file; recovery is always row deletion within it.
- **catalog-is-not-authority**: A client-side resource catalog MAY optimize
  behavior (registration lists, pull-only refusal) but the server's manifest and
  push results remain authoritative when they disagree.

## States

The engine runs one cycle at a time; a coalesced kick runs a follow-up cycle
after the current one returns. `SyncEngine` is an actor, so these are logical
phases of a single cycle, not concurrent states.

| State | Entry condition |
|---|---|
| Idle | No cycle running. Emitted (`.idle`) after a full pull + push cycle completes with no error, and the resting state between cycles. |
| Pulling | A kick (`.periodic`/`.connectivityRestored`/`.manual`/`.hostSpecific`) started a cycle; `pullLoop` reads the stored cursor and fetches a page. Loops while `hasMore`, applying each batch atomically before the next request. |
| Reconciling | Every pull iteration, before `apply`: the effective manifest is diffed against the store's registrations — disappearances purge, schema bumps purge, appearances/bumps on a non-fresh cursor reset the mirror. |
| Resyncing | A reconcile reset fired (appearance/schema-bump on a non-fresh cursor), or the server returned 410 (`resyncRequired`): mirror + cursor cleared, outbox preserved, full re-pull from a nil cursor (`.resyncPerformed`). |
| Pushing | `pullLoop` finished; `pushLoop` drains the outbox in `pushBatchSize` batches, resolving each result (applied/conflict/rejected) and looping until the outbox is empty. |
| AuthRequired | The transport returned 401 (`unauthorized`); the engine pauses (`.authRequired`) and only a manual kick resumes it. |
| Backing-off | A transport/5xx failure, a bounded-guard trip (`pushMadeNoProgress`, `pullMadeNoProgress`, `manifestUnstable`), or a repeated 410 scheduled an exponential-backoff retry (`.failed`, then a `.periodic` kick after `min(baseBackoff · 2^(n−1), maxBackoff)` for the n-th consecutive failure). |

## Conformance Test Vectors

One row per Behavioral Requirement. Tests live in the two XCTest bundles
(`AgenticToolkitSyncTests`, `AgenticToolkitSyncGRDBTests`); wire-shape rows also
cite `SyncWireTests` and the vendored fixtures under `Tests/…/Fixtures`.

| ID | Requirements | Input | Expected |
|---|---|---|---|
| R1 | effective-set-is-intersection | `hostResources = [a.x]`; manifest = `[a.x, b.y]` with changes for both | Only `a.x` changes applied; `b.y` skipped — `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |
| R2 | unregistered-resources-surfaced | Manifest carries `b.y` the host did not register | `b.y` ignored; `.unregisteredManifestResources(["b.y"])` emitted — `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |
| R3 | appearance-forces-full-resync | `b.y` enters the effective set on a non-fresh cursor | Mirror + cursor reset, full re-pull, `.resourcesEnabled(["b.y"])` + `.resyncPerformed` — `SyncEngineTests.testAppearanceOnNonFreshCursorTriggersFullResync` |
| R4 | resync-preserves-outbox | A staged op exists when a 410 forces resync | Op replayed under its original opId after the re-pull — `SyncEngineTests.testResyncRequiredResetsMirrorPreservingOutboxThenRepullsAndReplaysOutbox` |
| R5 | disappearance-purges-mirror | `b.y` leaves the effective set | Its mirror rows deleted, registration removed, cursor untouched, `.resourcesDisabled(["b.y"])` — `SyncEngineTests.testDisappearancePurgesQuarantinesAndKeepsCursor` |
| R6 | disappearance-quarantines-outbox | Pending op for the departing `b.y` | Op moved to quarantine, never pushed — `SyncEngineTests.testDisappearancePurgesQuarantinesAndKeepsCursor`; store: `InMemorySyncStoreTests.testPurgeResourcesDropsRowsQuarantinesOpsDeregisters` / `GRDBSyncStoreTests.testRegistrationsAndPurgeResources` |
| R7 | schema-bump-is-disappear-then-appear | `a.x` manifest schemaVersion CHANGES from the registered version — a rise (v1→v2) or a fall (v2→v1) | Purged then resynced, `.resourcesSchemaBumped(["a.x"])` — `SyncEngineTests.testSchemaBumpPurgesAndResyncs` (rise) and `SyncEngineTests.testSchemaDowngradePurgesAndResyncs` (fall); pure classification: `SyncEngineTests.testReconcilePlanClassifiesVersionRiseAsBumped` / `testReconcilePlanClassifiesVersionFallAsBumped` |
| R8 | cursor-is-opaque | Pull response whose cursor is an opaque base64 string; apply throws mid-batch | Cursor persisted only with a fully applied batch; never parsed — `GRDBSyncStoreTests.testApplyIsAtomicWithCursor`; wire: `SyncWireTests.testDecodesPullResponseFixture` (`Fixtures/pull-response.json`) |
| R9 | tombstones-apply-as-deletes | Pulled change `{op: delete}` with no data | Row soft-deleted locally (drops out of live rows) — `GRDBSyncStoreTests.testDeleteTombstonesLocallyAndResyncPreservesOutbox`; wire: `SyncWireTests.testDecodesPullResponseFixture` (delete row, `Fixtures/pull-response.json`) |
| R10 | pull-drains-has-more | Two pages, first with `hasMore = true` | Both pages pulled and applied atomically, cursor advanced per batch — `SyncEngineTests.testPullLoopsWhileHasMoreAndAdvancesCursorPerBatch` |
| R11 | pull-only-refused-at-stage | `stage` a mutation for a resource in `pullOnlyResources` | Throws `SyncStoreFailure.pullOnlyResource`, no outbox op — `InMemorySyncStoreTests.testStageRefusesPullOnlyResource`, `GRDBSyncStoreTests.testStageRefusesPullOnlyResource` |
| R12 | rejected-is-terminal | Push result `{status: rejected}` | Op quarantined, absent from the next cycle's push — `SyncEngineTests.testRejectedPushResultQuarantinesOpAndIsNotRetriedNextCycle`; store: `GRDBSyncStoreTests.testCompleteAppliedRemovesOpRejectedQuarantines` |
| R13 | conflict-adopts-server-row | Push result `{status: conflict, current}` with server `sync_version` | Server row adopted locally, `sync_version` preserved, bookkeeping cols stripped — `SyncEngineTests.testPushDrainsOutboxAndAppliesConflictCurrentLocally`; delete wins when `current.deleted_at` is set (adopted as a local delete, mirror row tombstoned) — `SyncEngineTests.testPushConflictWithDeletedCurrentAppliesAsLocalDelete` |
| R14 | applied-adopts-new-version | Push result `{status: applied, newVersion}` | Mirror row's base version updated before the outbox row is cleared — `InMemorySyncStoreTests.testCompleteAppliedAdoptsNewVersionOntoMirrorRowForSubsequentStage`, `GRDBSyncStoreTests.testCompleteAppliedAdoptsNewVersionOntoMirrorRowForSubsequentStage`; wire: `SyncWireTests.testDecodesPushResponseFixtureIncludingConflictRow` (`Fixtures/push-response.json`) |
| R15 | identity-change-purges | Identity change with mirror rows, cursor, pending/inflight/quarantined ops | Mirror + cursor + entire outbox cleared, registrations kept — `GRDBSyncStoreTests.testPurgeForIdentityChangeClearsMirrorsCursorAndOutboxButKeepsRegistrations` |
| R16 | recovery-never-deletes-database | Resync and identity-change purge on a live on-disk store | Only rows deleted; the store keeps serving afterward (file survives) — `GRDBSyncStoreTests.testPurgeForIdentityChangeClearsMirrorsCursorAndOutboxButKeepsRegistrations`, `GRDBSyncStoreTests.testDeleteTombstonesLocallyAndResyncPreservesOutbox` |
| R17 | catalog-is-not-authority | Catalog lists a resource the manifest omits (or vice versa) | Manifest gates what actually syncs; catalog only shapes registration/refusal — `ADHSyncCatalogTests.testCatalogShape`, `SyncEngineTests.testHostSubsetFiltersManifestAndChanges` |

## Edge Cases

- **Fresh-cursor initial sync — no resync.** On a cold store the cursor is nil,
  so the first pull covers every effective resource with no gap; appearances on
  a nil cursor are *not* treated as a resync (they cannot be behind a cursor
  that does not exist yet). Verified by
  `SyncEngineTests.testFreshCursorInitialSyncDoesNotResync`.
- **Manifest flapping bound.** A manifest that flaps a resource in and out (or
  keeps bumping its schema version) faster than a resync can settle is bounded:
  after `maxReconcileResyncsPerCycle` (3) mirror resets in one cycle the engine
  surfaces `SyncEngineError.manifestUnstable` (a `.failed` event) and backs off,
  rather than hot-looping reset + re-pull forever. Verified by
  `SyncEngineTests.testFlappingManifestTripsReconcileResyncBoundAndFails`.
- **Conflict without `current`.** A `conflict` result carrying no `current` row
  has nothing to adopt; it is treated as a rejection — the op is quarantined
  (reason preserved), never silently dropped. Verified by
  `SyncEngineTests.testConflictWithoutCurrentIsQuarantinedNotSilentlyDropped`.
- **Unparseable server `sync_version` ⇒ terminal quarantine.** A conflict whose
  `current.sync_version` cannot yield a numeric version — a non-finite or
  out-of-`Int64`-range number, OR a non-numeric string (the conflict `current`
  is `z.unknown()` on the wire, so it is NOT schema-validated to `/^\d+$/`) — is
  unadoptable: the server row can't be mirrored. The op is routed to the SAME
  terminal quarantine path as an explicit `rejected` (never retried under its
  original opId; a fixed retry must re-`stage` for a fresh one), and the rest of
  the push batch still `complete`s so the loop makes progress. This replaces the
  earlier "skip adoption but resolve" behavior, under which a non-numeric string
  was handed to `apply` verbatim, threw before `complete()`, and re-pushed the
  op forever. Verified by
  `SyncEngineTests.testConflictWithUnrepresentableSyncVersionQuarantines` (number)
  and `testConflictWithNonNumericStringSyncVersionQuarantinesWithoutWedging`
  (string, plus a sibling op that still completes).
- **Re-enable after disable.** A resource disabled and later re-enabled comes
  back through the appearance rule (full resync on a non-fresh cursor), not as a
  silent resumption — its rows changed while it was outside the effective set
  and are behind the single cursor stream.
- **Enrollment disable racing an in-flight push.** If enrollment for a resource
  is disabled while a push for it is outstanding, the server answers that op with
  `rejected/not_enrolled`; the client quarantines it — the same terminal
  quarantine state the local disable transition (`disappearance-quarantines-outbox`)
  would have produced. The op is never pushed under a stale enrollment.

## Configuration

**`SyncEngineConfiguration`** (`AgenticToolkitSync`) — the engine's one config surface:

| Field | Type | Default | Description |
|---|---|---|---|
| `deviceId` | `String` | — | Device identifier sent in every `SyncPushRequest`. |
| `pullLimit` | `Int` | `500` | Max changes requested per `/sync/pull` page. |
| `pushBatchSize` | `Int` | `100` | Max outbox ops per `/sync/push` round-trip. |
| `baseBackoff` | `TimeInterval` | `2` | Base retry delay (seconds) for the exponential backoff. |
| `maxBackoff` | `TimeInterval` | `3600` | Cap on the retry delay. |
| `hostResources` | `[SyncResource]?` | `nil` | Resources this host mirrors. `nil` accepts the server's whole manifest (pre-enrollment behavior); when set, the effective set is `manifest ∩ hostResources` and out-of-set changes are skipped. |

Pull-only (route-mode) refusal is **not** an engine-config concern: it is
enforced solely at the store's write path, so the set is passed only to the
store's init (below), never to `SyncEngineConfiguration`.

**Store init parameters:**

- `GRDBSyncStore(database: BoundedDatabase, pullOnlyResources: Set<String> = [])`
- `InMemorySyncStore(pullOnlyResources: Set<String> = [])` (the reference/test store)

The store's `pullOnlyResources` is what actually enforces
`pull-only-refused-at-stage`: `stage(_:)` throws
`SyncStoreFailure.pullOnlyResource` before any DB work.

**`ADHSyncCatalog`** (`AgenticToolkitSync`) — the adh values hosts wire in,
generated from the backend `SYNC_REGISTRY` (`src/adh/src/sync/registry.ts` in the
**adhbackend** repo — it was `backend/src/adh/…` inside adh until the 2026-09 split):

- `ADHSyncCatalog.all` — every catalog resource (**97**, all `schemaVersion 1`),
  passed as `hostResources` / to `prepare(resources:)`.
- `ADHSyncCatalog.pullOnly` — the **44** `pushMode: 'route'` resources, passed as
  `pullOnlyResources` to the store init (the only place that enforces it).

Both counts are read off the checked-in
`packages/apple/AgenticToolkit/Sync/ADHSyncCatalog.swift`, not pinned to a backend
revision. They were 79 and 27 when this was first written against adh main
`64825b107`; the generated file is the live number, so count there rather than
trusting this paragraph.

## Logging

The engine emits a `SyncEvent` stream (`SyncEngine.events`,
`.bufferingNewest(256)`); hosts drain it to drive status UI. The full enum
(`SyncEvents.swift`):

| Event | Payload | Meaning |
|---|---|---|
| `started` | `SyncKickReason` | A cycle began (`.periodic` / `.connectivityRestored` / `.manual` / `.hostSpecific`). |
| `pulledBatch` | `changes: Int, cursor: SyncCursor` | One pull page applied atomically; cursor advanced. |
| `pushed` | `applied: Int, conflicts: Int, rejected: Int` | One push round-trip resolved. |
| `conflictResolved` | `resource: String, rowId: String` | A conflict adopted the server row locally. |
| `resyncPerformed` | — | Mirror + cursor reset and a full re-pull ran. |
| `resourcesEnabled` | `[String]` | **New:** resources newly in the effective set on a non-fresh cursor (a full resync was performed). |
| `resourcesDisabled` | `[String]` | **New:** resources that left the effective set — mirror purged, outbox quarantined, registration removed. |
| `resourcesSchemaBumped` | `[String]` | **New:** registered resources whose manifest schemaVersion rose — purged + resynced. |
| `unregisteredManifestResources` | `[String]` | **New:** manifest resources the host did not register — ignored, surfaced for observability. |
| `authRequired` | — | 401: engine paused, awaiting a manual kick. |
| `failed` | `String` | Human-readable failure; ops remain queued and a backoff retry is scheduled. |
| `idle` | — | A full pull + push cycle completed with no error. |

**`reachedBackend` classification** (`SyncEvent.reachedBackend`): a *reachability*
signal, not sync-health. `true` for `pulledBatch`, `idle`, and `authRequired`
(the backend answered — even a 401 is proof of a live round trip). `false` for
`started`, `pushed`, `conflictResolved`, `resyncPerformed`, `resourcesEnabled`,
`resourcesDisabled`, `resourcesSchemaBumped`, `unregisteredManifestResources`,
and `failed` (which covers both "never reached the backend" and "the backend
errored"). The switch is exhaustive on purpose so a new event forces a decision
at this call site.

## Platform Notes

- **Core (`AgenticToolkitSync`):** `packages/apple/AgenticToolkit/Sync/*` —
  `SyncEngine.swift`, `SyncEvents.swift`, `SyncWire.swift`, `SyncProtocols.swift`,
  `ADHSyncCatalog.swift`, `JSONValue.swift`, `SyncID.swift`, the `Triggers/*`
  trigger sources, and `Testing/*` (`InMemorySyncStore`, `ScriptedSyncTransport`).
- **On-disk store (`AgenticToolkitSyncGRDB`):**
  `packages/apple/AgenticToolkit/SyncGRDB/GRDBSyncStore.swift` — the SQLite/GRDB
  `SyncStore` on a `BoundedDatabase` WAL pool.
- **Conformance = the two XCTest bundles:**
  `Tests/AgenticToolkitSyncTests/*` (engine, wire, catalog, events, in-memory
  store) and `Tests/AgenticToolkitSyncGRDBTests/*` (the GRDB store + a
  SyncEngine-over-GRDB integration test).
- **No TypeScript / web implementation exists yet.** The wire types and the
  vendored fixtures (`Tests/AgenticToolkitSyncTests/Fixtures/*.json`) are the
  cross-language contract a future web client would conform to; the fixtures must
  not be edited locally.

## Design Decisions

- **Server is the source of truth.** The backend owns the manifest, the single
  cohort cursor, and every push outcome. The client mirrors and queues; it never
  fabricates a cursor, re-derives enrollment, or overrides a push result. This is
  what makes the client replaceable per platform without forking the contract.
- **Appearance ⇒ full resync (single cursor stream, no version touch on enable).**
  The server keeps *one* cursor stream per cohort and does **not** bump row
  versions or re-serve rows when a resource is enrolled-enabled
  (`docs/architecture/sync.md`). So a resource that enters the effective set on a
  non-fresh cursor has rows that changed while it was outside the set sitting
  permanently behind the cursor — an incremental pull would never see them. The
  only correct recovery is to reset the mirror + cursor and re-pull from scratch.
  A fresh (nil) cursor is exempt: the initial pull already covers everything.
- **Quarantine over drop or indefinite hold (privacy vs data loss).** A local op
  for a resource that left the effective set can neither be pushed (the server
  would reject it) nor kept live (the host must stop serving that resource). It
  is moved to quarantine — surfaced to the host, never silently dropped (that
  would lose the user's edit) and never silently pushed (that would leak data
  across an enrollment boundary). A fixed retry re-`stage`s for a fresh opId,
  because the server ledgers results immutably per opId.
- **The catalog lives client-side, not on the manifest wire.** Push mode
  (`route` vs generic) and the registration list are client knowledge:
  `ADHSyncCatalog` lets a host register the right tables and refuse a pull-only
  write *before* a round trip. Encoding that on the pull manifest would bloat
  every response with data the server already enforces authoritatively (it
  answers a mis-push with `rejected/route_only`). The catalog is an optimization
  that can go stale; the manifest and push results remain the backstop.

## Compliance

| Check | Status | Category |
|---|---|---|
| Frontmatter valid (id, domain, type `ingredient`, category `engine`, platforms) | pass | recipe schema |
| Sections present and in ingredient order | pass | recipe schema |
| Category `engine` ⇒ Appearance/Accessibility omitted, no demo required | pass | recipe schema |
| Every Behavioral Requirement has a Conformance Test Vector row | pass | contract fidelity |
| Cited tests exist in the two XCTest bundles | pass | contract fidelity |

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-07-22 | Mike Fullerton | Initial draft |
| 1.1.0 | 2026-09-09 | Mike Fullerton | Split from the public `offline-sync-client`, which was genericized when it moved to agenticdevelopertoolkit. Restores the file-level citations against the Swift targets in this repo; repoints the backend paths at adhbackend after the 2026-09 split; refreshes the catalog counts (79/27 → 97/44). |
