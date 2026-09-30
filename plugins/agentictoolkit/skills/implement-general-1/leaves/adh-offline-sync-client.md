<!-- leaf: implement-general-1/adh-offline-sync-client · source: adh-offline-sync-client.md -->

**Rules** (cite as `implement-general-1/adh-offline-sync-client#<slug>`):

- `effective-set-is-intersection` MUST
- `unregistered-resources-surfaced` MUST
- `appearance-forces-full-resync` MUST
- `resync-preserves-outbox` MUST
- `disappearance-purges-mirror` MUST
- `disappearance-quarantines-outbox` MUST
- `schema-bump-is-disappear-then-appear` MUST
- `cursor-is-opaque` MUST
- `tombstones-apply-as-deletes` MUST
- `pull-drains-has-more` MUST
- `pull-only-refused-at-stage` MUST
- `rejected-is-terminal` MUST
- `conflict-adopts-server-row` MUST
- `applied-adopts-new-version` MUST
- `identity-change-purges` MUST
- `catalog-is-not-authority` MAY

# ADH Offline Sync Client

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
