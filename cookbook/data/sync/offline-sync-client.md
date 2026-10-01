---
id: d3a0b65f-92c0-43c1-b04c-77638eb72044
title: Offline Sync Client
domain: agentictoolkit://cookbook/data/sync/offline-sync-client
type: ingredient
category: engine
version: 1.2.0
status: draft
language: en
created: '2026-07-22'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The offline-sync client contract: an enrollment-driven manifest lifecycle, a cohort cursor, push modes, tombstones, and purge rules that keep a local mirror consistent with a server-authoritative backend."
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
  - agenticdevelopertoolkit://recipes/offline-sync-client
references:
  - src/adh/src/sync/wire.ts (adhbackend)
  - src/adh/src/sync/registry.ts (adhbackend)
  - src/adh/docs/architecture/sync.md (adhbackend)
  - packages/apple/AgenticToolkit/Sync (agentictoolkit)
  - packages/apple/AgenticToolkit/SyncGRDB (agentictoolkit)
---

# Offline Sync Client

> **Two recipes, one contract.** The public `offline-sync-client`
> (`agenticdevelopertoolkit://recipes/offline-sync-client`, in the agenticdevelopertoolkit
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

The reference implementation splits into two parts:

- **The core** — the platform-neutral logic: the sync engine (the
  pull → reconcile → push cycle), the wire types, the store/transport/
  trigger-source contracts, the observability events, and the client-side
  sync catalog (the adh resource catalog mirrored client-side).
- **The on-disk store** — the persisted mirror (JSON-payload mirror tables,
  an outbox, a conflicts audit) on a durable local database.

The contract is **server-authoritative**. The backend (`/sync/pull`,
`/sync/push`) owns the manifest of syncable resources, the single opaque cohort
cursor, and the outcome of every pushed op; the client mirrors what it is told,
queues what it originates, and never invents behavior the server did not grant.
A client-side catalog is an optimization — it lets a host register the right
resources and refuse pull-only writes before a round trip — but it never
overrides the manifest or a push result.

Each pull returns a **manifest** (the resources the server will sync for this
identity), a batch of **changes** (upserts and delete tombstones), a **cursor**,
and a `hasMore` flag. The client intersects the manifest with its
host-registered set to get the **effective set**, reconciles enrollment
transitions (a resource appearing, disappearing, or bumping schema version),
applies the batch atomically with the cursor, and drains `hasMore`. It then
drains its outbox to `/sync/push`, adopting server rows on conflict and
adopting new versions on apply.

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
after the current one returns. The engine internally serializes its work, so
these are logical phases of a single cycle, not concurrent states.

| State | Entry condition |
|---|---|
| Idle | No cycle running. Emitted (`idle`) after a full pull + push cycle completes with no error, and the resting state between cycles. |
| Pulling | A kick (`periodic`/`connectivityRestored`/`manual`/`hostSpecific`) started a cycle; the pull phase reads the stored cursor and fetches a page. Loops while `hasMore`, applying each batch atomically before the next request. |
| Reconciling | Every pull iteration, before applying a batch: the effective manifest is diffed against the store's registrations — disappearances purge, schema bumps purge, appearances/bumps on a non-fresh cursor reset the mirror. |
| Resyncing | A reconcile reset fired (appearance/schema-bump on a non-fresh cursor), or the server returned an HTTP 410 (resync required): mirror + cursor cleared, outbox preserved, full re-pull from a nil cursor (`resyncPerformed`). |
| Pushing | The pull phase finished; the push phase drains the outbox in configured batches, resolving each result (applied/conflict/rejected) and looping until the outbox is empty. |
| AuthRequired | The transport returned an HTTP 401 (unauthorized); the engine pauses (`authRequired`) and only a manual kick resumes it. |
| Backing-off | A transport/5xx failure, a bounded-guard trip (`pushMadeNoProgress`, `pullMadeNoProgress`, `manifestUnstable`), or a repeated HTTP 410 scheduled an exponential-backoff retry (`failed`, then a `periodic` kick after `min(baseBackoff · 2^(n−1), maxBackoff)` for the n-th consecutive failure). |

## Conformance Test Vectors

One row per Behavioral Requirement.

| ID | Requirements | Input | Expected |
|---|---|---|---|
| R1 | effective-set-is-intersection | host-registered resources `[a.x]`; manifest `[a.x, b.y]` with changes for both | only `a.x`'s changes are applied; `b.y`'s are skipped |
| R2 | unregistered-resources-surfaced | manifest carries `b.y`, which the host did not register | `b.y` is ignored; an `unregisteredManifestResources` event naming `["b.y"]` is emitted |
| R3 | appearance-forces-full-resync | `b.y` enters the effective set on a non-fresh cursor | mirror + cursor reset, full re-pull, a `resourcesEnabled` event naming `["b.y"]` plus `resyncPerformed` |
| R4 | resync-preserves-outbox | a staged op exists when an HTTP 410 forces resync | the op is replayed under its original opId after the re-pull |
| R5 | disappearance-purges-mirror | `b.y` leaves the effective set | its mirror rows are deleted, registration removed, cursor untouched, a `resourcesDisabled` event naming `["b.y"]` |
| R6 | disappearance-quarantines-outbox | a pending op for the departing `b.y` | the op moves to quarantine, never pushed |
| R7 | schema-bump-is-disappear-then-appear | `a.x`'s manifest schema version changes from the registered version — a rise (v1→v2) or a fall (v2→v1) | purged then resynced, a `resourcesSchemaBumped` event naming `["a.x"]`, in both directions |
| R8 | cursor-is-opaque | a pull response whose cursor is an opaque base64 string; applying it fails partway through the batch | the cursor is persisted only with a fully applied batch; it is never parsed |
| R9 | tombstones-apply-as-deletes | a pulled change with op `delete` and no data | the row is soft-deleted locally (drops out of live rows) |
| R10 | pull-drains-has-more | two pages, the first reporting `hasMore = true` | both pages are pulled and applied atomically, cursor advanced per batch |
| R11 | pull-only-refused-at-stage | staging a mutation for a resource in the pull-only set | raises a pull-only-resource refusal error; no outbox op is created |
| R12 | rejected-is-terminal | a push result with status `rejected` | the op is quarantined, absent from the next cycle's push |
| R13 | conflict-adopts-server-row | a push result with status `conflict` and a `current` row carrying the server's sync_version | the server row is adopted locally, its sync_version preserved, bookkeeping columns stripped; when `current.deleted_at` is set, it is adopted as a local delete (mirror row tombstoned) |
| R14 | applied-adopts-new-version | a push result with status `applied` and a `newVersion` | the mirror row's base version is updated before the outbox row is cleared |
| R15 | identity-change-purges | an identity change with mirror rows, cursor, and pending/inflight/quarantined ops present | mirror + cursor + the entire outbox are cleared; registrations are kept |
| R16 | recovery-never-deletes-database | a resync and an identity-change purge on a live on-disk store | only rows are deleted; the store keeps serving afterward (the underlying file survives) |
| R17 | catalog-is-not-authority | the catalog lists a resource the manifest omits (or vice versa) | the manifest gates what actually syncs; the catalog only shapes registration/refusal |

## Edge Cases

- **Fresh-cursor initial sync — no resync.** On a cold store the cursor is nil,
  so the first pull covers every effective resource with no gap; appearances on
  a nil cursor are *not* treated as a resync (they cannot be behind a cursor
  that does not exist yet).
- **Manifest flapping bound.** A manifest that flaps a resource in and out (or
  keeps bumping its schema version) faster than a resync can settle is bounded:
  after a configured maximum of mirror resets in one cycle (3) the engine
  surfaces a manifest-instability error (a `failed` event) and backs off,
  rather than hot-looping reset + re-pull forever.
- **Conflict without `current`.** A `conflict` result carrying no `current` row
  has nothing to adopt; it is treated as a rejection — the op is quarantined
  (reason preserved), never silently dropped.
- **Unparseable server `sync_version` ⇒ terminal quarantine.** A conflict whose
  `current.sync_version` cannot yield a numeric version — a non-finite or
  out-of-range number for a 64-bit integer, OR a non-numeric string (the
  conflict `current` payload is not schema-validated to a numeric-string
  pattern on the wire) — is unadoptable: the server row can't be mirrored. The
  op is routed to the SAME terminal quarantine path as an explicit `rejected`
  (never retried under its original opId; a fixed retry must re-stage for a
  fresh one), and the rest of the push batch still completes so the loop makes
  progress. This replaces the earlier "skip adoption but resolve" behavior,
  under which a non-numeric string was handed to the apply step verbatim,
  raised before completion, and re-pushed the op forever.
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

**The engine's configuration** — the one config surface:

| Field | Type | Default | Description |
|---|---|---|---|
| `deviceId` | string | — | Device identifier sent in every push request. |
| `pullLimit` | integer | `500` | Max changes requested per pull page. |
| `pushBatchSize` | integer | `100` | Max outbox ops per push round-trip. |
| `baseBackoff` | duration (seconds) | `2` | Base retry delay for the exponential backoff. |
| `maxBackoff` | duration (seconds) | `3600` | Cap on the retry delay. |
| `hostResources` | optional list of resources | none | Resources this host mirrors. Absent accepts the server's whole manifest (pre-enrollment behavior); when set, the effective set is `manifest ∩ hostResources` and out-of-set changes are skipped. |

Pull-only (route-mode) refusal is **not** an engine-config concern: it is
enforced solely at the store's write path, so the set is passed only to the
store's construction (below), never to the engine's configuration.

**Store construction parameters:**

- The on-disk store's constructor takes the bounded database plus a set of
  pull-only resource identifiers (default empty).
- The in-memory reference store's constructor takes a set of pull-only
  resource identifiers (default empty).

The store's pull-only-resource set is what actually enforces
`pull-only-refused-at-stage`: staging a mutation raises a pull-only-resource
refusal error before any storage work.

**The client-side sync catalog** — the adh values hosts wire in, generated
from the backend's sync resource registry:

- The full catalog — every catalog resource (**97**, all schema version 1),
  passed as the host-registered resources for the engine's registration step.
- The pull-only subset of the catalog — the **44** route-mode resources,
  passed as the pull-only set to the store's construction (the only place
  that enforces it).

Both counts are read off the checked-in generated catalog source, not pinned
to a backend revision. They were 79 and 27 when this was first written
against adh main `64825b107`; the generated file is the live number, so
count there rather than trusting this paragraph.

## Logging

The engine emits an ordered stream of sync events that hosts drain to drive
status UI, retaining at least the most recent 256 events. The full set of
events:

| Event | Payload | Meaning |
|---|---|---|
| `started` | kick reason (`periodic`/`connectivityRestored`/`manual`/`hostSpecific`) | A cycle began. |
| `pulledBatch` | change count, cursor | One pull page applied atomically; cursor advanced. |
| `pushed` | applied count, conflict count, rejected count | One push round-trip resolved. |
| `conflictResolved` | resource name, row id | A conflict adopted the server row locally. |
| `resyncPerformed` | — | Mirror + cursor reset and a full re-pull ran. |
| `resourcesEnabled` | list of resource names | Resources newly in the effective set on a non-fresh cursor (a full resync was performed). |
| `resourcesDisabled` | list of resource names | Resources that left the effective set — mirror purged, outbox quarantined, registration removed. |
| `resourcesSchemaBumped` | list of resource names | Registered resources whose manifest schema version changed — purged + resynced. |
| `unregisteredManifestResources` | list of resource names | Manifest resources the host did not register — ignored, surfaced for observability. |
| `authRequired` | — | HTTP 401: engine paused, awaiting a manual kick. |
| `failed` | message string | Human-readable failure; ops remain queued and a backoff retry is scheduled. |
| `idle` | — | A full pull + push cycle completed with no error. |

**The reachedBackend classification**: a *reachability* signal, not
sync-health. `true` for `pulledBatch`, `idle`, and `authRequired` (the
backend answered — even an HTTP 401 is proof of a live round trip). `false`
for `started`, `pushed`, `conflictResolved`, `resyncPerformed`,
`resourcesEnabled`, `resourcesDisabled`, `resourcesSchemaBumped`,
`unregisteredManifestResources`, and `failed` (which covers both "never
reached the backend" and "the backend errored"). Every event is covered on
purpose, so a new event forces a decision at this call site.

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

## Reference Implementations

| Platform | Path |
|----------|------|

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
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | partial | Access Patterns |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |

Notes: separation-of-concerns passes because the pull, reconcile, and push phases, the SyncStore/SyncTransport/SyncTriggerSource protocols, and the client-side ADHSyncCatalog each live behind their own type, with the server kept as the sole authority the client never re-derives. unit-test-coverage passes because the two XCTest bundles (`SyncEngineTests.swift`, `InMemorySyncStoreTests.swift`, `GRDBSyncStoreTests.swift`, `SyncEngineGRDBIntegrationTests.swift`, `SyncWireTests.swift`, `ADHSyncCatalogTests.swift`, `SyncEventTests.swift`, `TriggerSourceTests.swift`, `SyncMirrorProjectionTests.swift`) exercise every Behavioral Requirement, one row per requirement in Conformance Test Vectors. explicit-error-handling passes because every push outcome (applied, conflict, rejected) and transport failure (401, 410, transient 5xx) is routed to a named terminal state (quarantine, resync, backoff) rather than swallowed. error-recovery and graceful-degradation pass because the AuthRequired and Backing-off states resume automatically from transient failures and dependency loss without user intervention or a crash. fault-tolerance passes because an unparseable conflict `sync_version` is routed to the same terminal quarantine path as an explicit rejection instead of throwing mid-batch. state-recovery passes because recovery-never-deletes-database and resync-preserves-outbox guarantee the mirror and outbox restore correctly after interruption. idempotent-operations passes because retried pushes are tracked by opId and a rejected or conflicting op is never re-pushed under the same id. data-integrity passes because a pull batch's cursor is persisted only together with an atomically applied batch, so a mid-batch failure cannot leave a corrupt or partially-applied mirror. health-observability passes because the SyncEvent stream (`started`/`pulledBatch`/`pushed`/`failed`/`idle`/etc.) gives a host everything it needs to build monitoring or status UI over the engine's health. offline-behavior passes because AuthRequired, Backing-off, and quarantine are all explicitly defined responses to a network-unavailable or backend-rejecting state. retry-with-backoff is partial: the engine defines exponential backoff via `baseBackoff`/`maxBackoff`, but neither the recipe nor the source adds jitter to the retry delay, which the catalog check requires alongside the exponential curve. timeout-configuration fails because neither the Configuration table nor the source (`SyncEngine.swift`, `SyncProtocols.swift`) sets or exposes a request timeout for the pull/push transport calls. error-response-handling passes because every documented push status (applied, conflict, rejected, with its listed rejection reasons) and pull-side HTTP condition (401, 410) has a defined client-side resolution.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-07-22 | Mike Fullerton | Initial draft |
| 1.1.0 | 2026-09-09 | Mike Fullerton | Split from the public `offline-sync-client`, which was genericized when it moved to agenticdevelopertoolkit. Restores the file-level citations against the Swift targets in this repo; repoints the backend paths at adhbackend after the 2026-09 split; refreshes the catalog counts (79/27 → 97/44). |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Compliance section rewritten as linked checks against the compliance catalog |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/sync/. |
