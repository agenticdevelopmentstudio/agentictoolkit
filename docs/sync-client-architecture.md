# Sync Client Architecture

How the Swift offline-sync client stack is built: the two library targets,
the three protocol seams, the engine actor that drives them, the enrollment
reconciliation loop, the adh resource catalog, and how a host wires it all
together. This is the client counterpart of the adh backend's server-side
`docs/architecture/sync.md`.

**Read this for the _how_.** For the _what_ — the platform-neutral behavioral
contract every sync client must satisfy (17 requirements + conformance test
vectors) — read [`../cookbook/adh-offline-sync-client.md`](../cookbook/adh-offline-sync-client.md).
This document does not restate that requirement list; it links to it and
describes the Swift implementation that conforms to it.

## Provenance

- **Server contract:** the adh backend owns the manifest of syncable
  resources, the single opaque cohort cursor, and the outcome of every pushed
  op. The authoritative server-side document is
  `backend/src/adh/docs/architecture/sync.md` in the adh repo; its **§3 Push**
  and **§4 Resync** sections are the semantics the client code cites directly
  (see `SyncEngine.performResync` and `SyncEngine.pushLoop`). The wire shapes
  are defined in `backend/src/adh/src/sync/wire.ts`.
- **Behavioral contract:** [`../cookbook/adh-offline-sync-client.md`](../cookbook/adh-offline-sync-client.md)
  — the platform-neutral requirement list and its conformance vectors.
- **Pinned to adh main `64825b107`** (per-ecosystem sync enrollment, merged
  2026-07-22). The catalog (`ADHSyncCatalog`) was generated against that
  revision; the enrollment reconciliation described below is the client half of
  the per-ecosystem enrollment that shipped in it.

The contract is **server-authoritative** throughout: the client mirrors what it
is told, queues what it originates, and never invents behavior the server did
not grant. Everything below is a mechanism in service of that.

## The two targets

| Target | Holds |
|---|---|
| **`AgenticToolkitSync`** | The platform-neutral core: `SyncEngine` (the actor), the wire types (`SyncWire.swift`, mirroring adh's `wire.ts`), the `SyncStore` / `SyncTransport` / `SyncTriggerSource` protocols (`SyncProtocols.swift`), the observability events (`SyncEvents.swift`), the three trigger sources (`Triggers/*`), `ADHSyncCatalog`, and the test doubles (`Testing/InMemorySyncStore`, `Testing/ScriptedSyncTransport`). |
| **`AgenticToolkitSyncGRDB`** | `GRDBSyncStore` — the on-disk `SyncStore` on a `BoundedDatabase` WAL pool: JSON-payload per-resource mirror tables, an outbox, and a conflicts audit. |

Source lives under `packages/apple/AgenticToolkit/Sync/*` and
`packages/apple/AgenticToolkit/SyncGRDB/*`; conformance is the two XCTest
bundles (`Tests/AgenticToolkitSyncTests/*`,
`Tests/AgenticToolkitSyncGRDBTests/*`).

## Seams

The engine is an actor with three injected dependencies, one per protocol. It
owns no credentials (the transport does), no persistence (the store does), and
no scheduling (the trigger sources do). That separation is what makes each side
independently replaceable — a different backend transport, an in-memory store
for tests, a host-specific trigger — without touching the engine.

```
  SyncTriggerSource ──kicks──▶  SyncEngine  ──pull/push──▶  SyncTransport
   (periodic /                  (the actor)                 (ADHSyncAPI +
    connectivity /                  │                        host adapter)
    manual)                    prepare/apply/stage/…
                                    ▼
                                SyncStore
                            (GRDBSyncStore /
                             InMemorySyncStore)
```

### `SyncStore` — local persistence (mirror rows + outbox)

Implementations must make `stage` and `apply` atomic with the outbox mutations
they imply; the engine relies on that to stay crash-safe. Current surface
(`Sync/SyncProtocols.swift`), verbatim:

```swift
public protocol SyncStore: Sendable {
    func prepare(resources: [SyncResource]) async throws
    func cursor() async throws -> SyncCursor?
    func apply(_ batch: [SyncChange], advancingTo cursor: SyncCursor?) async throws
    func stage(_ mutation: LocalMutation) async throws
    func pendingOps(limit: Int) async throws -> [SyncPushOp]
    func complete(_ results: [SyncPushResult]) async throws
    func resetForResync() async throws
    func registrations() async throws -> [String: Int]
    func purgeResources(_ resources: [String]) async throws
}
```

- **`prepare(resources:)`** registers resources and creates any mirror storage
  they need. Idempotent; schema versions upsert. Hosts MUST call it — via a
  static manifest, or by letting the first successful pull populate it — before
  ever calling `stage(_:)` for a resource.
- **`apply(_:advancingTo:)`** applies a pulled batch atomically; a `nil` cursor
  applies without advancing (used for conflict adoptions in the push loop).
- **`stage(_:)`** is the one local-write path: an optimistic mirror write plus
  an outbox op, atomic. It refuses a pull-only resource up front
  (`SyncStoreFailure.pullOnlyResource`) and throws
  `SyncStoreFailure.unknownResource` for a resource nothing has `prepare`d.
- **`resetForResync()`** clears mirror rows + cursor but **preserves the
  outbox**, and never deletes the database file.
- **`registrations()`** returns `resource -> registered schema_version`; the
  reconciler diffs the effective manifest against it.
- **`purgeResources(_:)`** is the enrollment-disable transition: delete the
  resources' mirror rows, move their pending/inflight outbox ops to quarantine
  (never dropped, never pushed), remove their registrations. The cursor is
  untouched.

Failures are a single additive enum (`SyncStoreFailure`): `unknownResource`,
`invalidChange` (an un-interpretable `syncVersion`/outbox `type`), and
`pullOnlyResource`. Hosts only `catch is SyncStoreFailure`; they never switch
exhaustively over it, so adding a case never breaks a host.

**Who implements it:** `GRDBSyncStore` (on-disk, production) and
`InMemorySyncStore` (the reference/test store, ships in the framework). Both
take `pullOnlyResources: Set<String>` at init — that set, not the manifest, is
what enforces stage-time refusal.

### `SyncTransport` — the wire

```swift
public protocol SyncTransport: Sendable {
    func pull(cursor: SyncCursor?, limit: Int) async throws -> SyncPullResponse
    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse
}

public enum SyncTransportError: Error, Sendable, Equatable {
    case unauthorized                 // HTTP 401 → engine pauses, emits .authRequired
    case resyncRequired               // HTTP 410 → engine resets mirror + full re-pull
    case transport(String)            // network/5xx → retry with backoff
    case invalidResponse(statusCode: Int)
}
```

**Who implements it:** the concrete wire client is **`ADHSyncAPI`** in the
sibling `agenticdevelopertoolkit` repo
(`packages/apple/AgenticDeveloperHubClient/Sources/Sync/ADHSyncAPI.swift`). It deliberately
decodes nothing — it owns only URLs, bearer auth, and HTTP status → `Failure`
mapping (`unauthorized` for 401, `resyncRequired` for 410, `http(code)`
otherwise), so that package needs no toolkit dependency and moves raw `Data`.
Each host adapts it to `SyncTransport` in a ~20-line **`ADHSyncTransportAdapter`**
(one per host: `ADHDaemon/ADHDCore` and `BitbagIOS`) that JSON-encodes the
`SyncPushRequest`, decodes the response into the `SyncWire` types, and maps
`ADHSyncAPI.Failure` → `SyncTransportError`. The engine's test double is
`ScriptedSyncTransport` (queue up pull/push outcomes; records requests).

### `SyncTriggerSource` — when to run

```swift
public protocol SyncTriggerSource: Sendable {
    var kicks: AsyncStream<SyncKickReason> { get }
}
```

`SyncKickReason` is `.periodic`, `.connectivityRestored`, `.manual`, or
`.hostSpecific(String)`. Three sources ship:

- **`PeriodicTriggerSource(interval:)`** — ticks `.periodic` on a fixed
  interval until `stop()`.
- **`ConnectivityTriggerSource`** — emits `.connectivityRestored` on each
  unsatisfied→satisfied `NWPathMonitor` transition. The only place in the core
  target that imports `Network`; still daemon-safe.
- **`ManualTriggerSource`** — host-driven; call `fire(_:)` to kick on demand.
  Holds no OS resource, so it needs no `stop()`.

A host attaches sources with `engine.attach(_:)`; each attach spawns a task
that forwards the source's kicks into `engine.kick(reason:)`.

### The engine actor between them

`SyncEngine` is an `actor`, so its cycle phases are logical, not concurrent: it
runs one cycle at a time and coalesces a second kick into a single `pendingReason`
follow-up. `kick(reason:)` is fire-and-forget; `syncNow(reason:)` runs one full
cycle and only returns once it (or the running cycle it joined) finishes —
the honest "a sync just ran" signal a pull-to-refresh spinner or BG-task
completion handler wants. `pause()`/`resume()` bracket identity-boundary
mutations (see Host adoption). The engine surfaces everything it does through
`events` (an `AsyncStream<SyncEvent>` buffered `.bufferingNewest(256)`); the
host is obligated to drain it.

## The enrollment lifecycle

Per-ecosystem enrollment means the set of resources the server will sync for an
identity can change between pulls — a resource can appear, disappear, or bump
its schema version. The client reconciles those transitions on **every pull
iteration, before `apply`**, in `SyncEngine.reconcile(…)`. The pure
classification half is factored out as a testable `SyncEngine.reconcilePlan(registered:effective:)`
(fix I6) that returns the `(disabled, bumped, appeared)` split; `reconcile`
itself performs the resulting purge/reset/emit side effects.

### Effective set

```
effective = manifest ∩ hostResources        (when hostResources is set)
effective = manifest                          (when hostResources is nil)
```

`hostResources` is the host's registered set (`SyncEngineConfiguration`). When
it is set, changes for resources outside the effective set are filtered out of
the applied batch, and manifest resources the host did not register are
surfaced via `.unregisteredManifestResources([...])` and otherwise ignored.
When it is `nil`, the client accepts the server's whole manifest (the
pre-enrollment behavior).

### Transitions

Given the effective set and the store's registrations, the reconciler computes,
in order (the registrations are read **once per cycle** into a snapshot that the
reconciler keeps current as it purges and prepares — fix H5+H1 — rather than
re-reading `registrations()` on every page; reconcile itself still runs per page):

1. **Disappearance** — registered resources no longer in the effective set.
   The reconciler calls `store.purgeResources(disabled)` (mirror rows deleted,
   pending/inflight outbox ops quarantined, registration removed) and emits
   `.resourcesDisabled([...])`. **The cursor is untouched.**
2. **Schema bump** — effective resources whose manifest `schemaVersion`
   *changed* from the registered version, a rise **or** a fall (fix A2: a
   downgrade — e.g. a server rollback — is as much a schema mismatch as an
   upgrade; mirror rows written under the old version can't be trusted against
   the new one, so `bumped` is the `!=` predicate, not `<`). Same purge, then
   emits `.resourcesSchemaBumped([...])`. A schema bump is deliberately modelled
   as _disappear then appear_ conceptually — in code the `bumped` set is computed
   separately from `appeared`; both feed the same purge + resync effects rather
   than running as a literal two-step transition.
3. **Appearance** — effective resources with no registration (minus the ones
   just schema-bumped).

If any appearance or schema-bump happened **and the cursor is non-fresh**, the
reconciler calls `store.resetForResync()`, emits `.resourcesEnabled(appeared)`
(when non-empty) followed by `.resyncPerformed`, and returns `true` — which
makes `pullLoop` restart the pull from a `nil` cursor.

### The fresh-cursor rule

```swift
// Fresh cursor: the initial pull covers everything — no gap, no resync.
guard cursor != nil, !(appeared.isEmpty && bumped.isEmpty) else { return false }
```

On a cold store the cursor is `nil`, so the first pull already covers every
effective resource with no gap; an appearance on a `nil` cursor is **not**
treated as a resync — it cannot be behind a cursor that does not exist yet.

### Why appearance forces a full resync

The rationale has a single home — the recipe's `appearance-forces-full-resync`
requirement and its "Appearance ⇒ full resync" Design Decision
([`../cookbook/adh-offline-sync-client.md`](../cookbook/adh-offline-sync-client.md#design-decisions)).
In short: the server keeps one cursor stream per cohort and does not re-serve a
resource's rows when it is enrolled-enabled, so rows that changed while the
resource sat outside the effective set are permanently behind the cursor; only a
mirror + cursor reset and a re-pull from scratch recovers them.

A resync clears the mirror and cursor but **preserves the outbox** — the queued
local edits are still owed to the server, so `performResync` re-pulls the full
snapshot and then replays the preserved outbox under its existing opIds, exactly
as it would have without the reset (adh `sync.md` §4). Re-enabling a
previously-disabled resource comes back through this same appearance rule, not
as a silent resumption.

### Why disappearance quarantines instead of dropping

Same single source — the recipe's `disappearance-quarantines-outbox` requirement
and its "Quarantine over drop or indefinite hold" Design Decision
([`../cookbook/adh-offline-sync-client.md`](../cookbook/adh-offline-sync-client.md#design-decisions)).
In short: a local op for a departed resource can neither be pushed (the server
would reject it) nor kept live (the host must stop serving it), so it is
quarantined — surfaced, never silently dropped (that loses the user's edit) and
never silently pushed (that leaks data across an enrollment boundary); a fixed
retry re-`stage`s for a fresh opId, because the server ledgers results immutably
per opId.

If enrollment is disabled while a push for that resource is already in flight,
the server answers that op with `rejected/not_enrolled` and the client
quarantines it — the same terminal state the local disable transition would
have produced.

### Server obligation: a complete manifest on every page

The disappearance purge (transition 1 above) trusts the manifest as **complete**:
a registered resource absent from a pull page's effective set is read as
enrollment-disabled and its mirror rows are purged + its unpushed edits terminally
quarantined, per page, with **no** empty- or partial-manifest floor. This purge
semantics is deliberate and frozen (recipe: `disappearance-purges-mirror` +
`disappearance-quarantines-outbox`), which places a hard obligation on the server:
it MUST send the full manifest on every `/sync/pull` page. The client cannot tell
"the server dropped this resource from enrollment" from "the server truncated the
manifest" — the omission *is* the disable signal — so a partial or truncated
manifest will be (correctly, by this contract) treated as a disablement and will
purge + quarantine the omitted resources. The same comment lives at the purge
site in `SyncEngine.reconcile`.

### The flapping bound

A manifest that flaps a resource in and out (or keeps bumping its schema
version) faster than a resync can settle would hot-loop reset + re-pull forever.
`pullLoop` counts mirror resets per cycle: up to `maxReconcileResyncsPerCycle`
(**3**) are allowed within a cycle, and it throws `SyncEngineError.manifestUnstable`
the moment a 4th would be needed (`reconcileResyncs > 3`), surfaced as a `.failed`
event that routes through the normal exponential backoff. Two sibling bounds
guard the same class of server misbehavior: `maxConsecutiveNoProgressPulls`
(**2**) for an empty-but-`hasMore` page whose cursor never advances
(`pullMadeNoProgress`), and a push spin guard that trips `pushMadeNoProgress`
when a round-trip resolves none of the ops it attempted.

## The catalog

`ADHSyncCatalog` (`Sync/ADHSyncCatalog.swift`) is the adh resource catalog
mirrored client-side — the values a host wires into config and store init:

- **`ADHSyncCatalog.all`** — every catalog resource (**79** as of adh
  `64825b107`, all `schemaVersion 1`), passed as `hostResources` and/or to
  `prepare(resources:)`.
- **`ADHSyncCatalog.pullOnly`** — the **27** `pushMode: 'route'` resources
  (a subset of `all`), passed as `pullOnlyResources` to the **store init** (the
  sole enforcement point; the engine config carries no such field).

**What it is not: authority.** The catalog is client knowledge — a static
snapshot of the backend's `SYNC_REGISTRY`. It lets a host register the right
tables and refuse a pull-only write _before_ a round trip, but the server's
manifest gates what actually syncs and its push results remain the backstop
when the catalog is stale (recipe: `catalog-is-not-authority`). Push mode and
the registration list are client knowledge precisely because encoding them on
the pull manifest would bloat every response with data the server already
enforces authoritatively (it answers a mis-push with `rejected/route_only`).

**Regeneration** — from an adh checkout, run the codegen target named in the
file's own doc comment. It re-emits `ADHSyncCatalog.swift` **and** runs a
backend-CI-gated semantic-drift check that fails if the checked-in catalog no
longer matches `SYNC_REGISTRY`:

```bash
python3 tools/codegen/generate.py sync-catalog
```

Keep the catalog's `Generated … against adh main <sha>` provenance line in sync
with the checkout you regenerate from.

**How hosts wire it** — the catalog is the adoption path for enrollment
subsetting and config-level pull-only refusal:

```swift
let store = GRDBSyncStore(database: db, pullOnlyResources: ADHSyncCatalog.pullOnly)
let engine = SyncEngine(
    store: store,
    transport: adapter,
    configuration: SyncEngineConfiguration(
        deviceId: deviceId,
        hostResources: ADHSyncCatalog.all        // or a curated subset
    )
)
```

A host that mirrors only part of the surface passes a subset as `hostResources`;
the effective set is then `manifest ∩ hostResources` and the rest of the server
manifest is surfaced as unregistered and ignored (`hostResources = nil`, the
default, accepts the whole manifest). `pullOnlyResources` goes **only** to the
store init — the store's write path is what enforces the stage-time refusal, so
there is nothing for the engine config to hold (fix E1 removed the dead
config-level copy that the engine never read).

> The two shipped hosts today (`SyncRuntime` in ADHDaemon, `AppServices` in
> BitBag) construct `SyncEngineConfiguration(deviceId:)` with the defaults —
> `hostResources = nil` (whole manifest). The
> `ADHSyncCatalog`/`hostResources`/`pullOnly` wiring above is the mechanism for
> opting into per-ecosystem enrollment subsetting (via the config) and
> stage-time refusal (via the store init); it is exercised end-to-end by the
> toolkit's own `SyncEngineTests`.

## Host adoption guide

### Bootstrap order: store → engine → triggers → events

The daemon's `SyncRuntime.bootstrap` is the reference (`ADHDaemon/ADHDCore`):

1. **Store.** Open a `BoundedDatabase` on a real file (it _throws_ rather than
   deleting a database it can't open — the mirror is never wiped as a recovery
   path), then `GRDBSyncStore(database:pullOnlyResources:)`. Optionally warm the
   bookkeeping schema by calling `cursor()` once, so a status poll racing the
   first pull doesn't hit "no such table".
2. **Engine.** Build the transport (`ADHSyncAPI` + `ADHSyncTransportAdapter`)
   and `SyncEngine(store:transport:configuration:)`. The engine owns no
   credential — the transport's `CredentialProvider` does, and the host reuses
   that same provider for any offline auth gate so both agree on "the
   credential".
3. **Triggers + events.** At startup, `engine.attach(ConnectivityTriggerSource())`
   (and a periodic source, or drive periodic from the host's own scheduler),
   then start a permanent task draining `engine.events`. That drain loop must be
   the **only** consumer of `events` — the stream has one buffer; a second
   reader splits events non-deterministically.

### The `prepare` obligation

`prepare(resources:)` is what registers the mirror tables `stage(_:)` writes
into, and the engine only ever calls it from the pull loop, seeded from each
pull response's manifest. So a host that accepts offline writes must not
`stage(_:)` before the first successful pull has run `prepare` — doing so throws
`SyncStoreFailure.unknownResource` by design. Two ways to satisfy it: gate
`stage` behind a "has synced at least once" flag (drive it off
`SyncEvent.reachedBackend`), or `prepare` a known static manifest yourself at
startup (BitBag does this with its chat manifest, best-effort, so its first
offline write doesn't race the engine's pull-driven `prepare`).

### The one write path: `stage`

All local mutations go through `store.stage(_:)` and nothing else. Hosts wrap it
(e.g. BitBag exposes a `stage`-forwarding method; views never touch
`store.stage` directly). `stage` refuses a pull-only resource before any DB work
(`SyncStoreFailure.pullOnlyResource`) and coalesces a repeat edit of the same
`(resource, rowId)` into the existing pending outbox op — same opId, same
original `baseVersion` — so two edits never race each other into a stale
self-conflict on push.

### Identity-change purge: `pause()` → `purgeForIdentityChange()` → `resume()`

An ordinary resync preserves the outbox; an **identity change** (sign-out,
switch account) must not — every queued op belongs to the departing identity and
pushing it under the new identity's credentials would misattribute it. That is
what `GRDBSyncStore.purgeForIdentityChange()` exists for: in one transaction it
empties every mirror table, clears the cursor (`_sync_state`), and deletes
**every** outbox row regardless of status (`pending`, `inflight`, _and_
`quarantined`), while leaving `_sync_resources` (the registrations) and
`_sync_conflicts` (the audit) untouched. Like every recovery path it only
deletes rows — never the database file.

Hosts must **bracket** that purge with the engine paused (BitBag's `signOut`):

```swift
await engine.pause()                        // suspends until any in-flight cycle
                                            //   finishes; kick/syncNow no-op while paused
try? await store.purgeForIdentityChange()   // credentials still valid here
credentials.clear()
await engine.resume()                       // does NOT itself kick; the next
                                            //   credential save kicks on its own
```

The ordering is a correctness requirement, not a nicety: without the pause a
cycle already mid-flight could `apply()` a pull or `complete()` a push against
the store after the purge clears it, leaving stale rows from the outgoing
identity behind. Purge **before** clearing credentials, because
`purgeForIdentityChange()` still needs an authenticated, usable store.

### Bumping the toolkit across a `SyncEvent` case addition

`SyncEvent` grows additively — the per-ecosystem enrollment work added four
cases (`resourcesEnabled`, `resourcesDisabled`, `resourcesSchemaBumped`,
`unregisteredManifestResources`), plus `reachedBackend`. When a host bumps the
toolkit past such an addition:

- Any **exhaustive `switch` over `SyncEvent`** in the host (status-pill mapping,
  a logging switch, etc.) stops compiling until the new case is handled — that
  is deliberate. Decide how each new enrollment case surfaces (a status badge,
  a log line, a no-op) rather than papering it over with a `default:` that
  silently swallows it. `SyncEvent.reachedBackend` inside the toolkit models the
  same discipline: it is exhaustive on purpose so a new case forces a
  reachability decision at that one call site (the four enrollment cases and
  `failed` are `false`; `pulledBatch`, `idle`, and `authRequired` are `true`).
- A host that logs events should treat only `.failed(String)` as carrying
  free-form, possibly-sensitive text (log it `.private`); the other cases are
  fixed and safe to log by name.

`SyncStoreFailure`, by contrast, is caught with `catch is SyncStoreFailure` and
never switched exhaustively, so a new failure case needs no host change.

## Failure taxonomy

Failures arrive on three axes: transport-level errors, per-op push results, and
the quarantine/audit bookkeeping a host reads back.

### Transport errors (`SyncTransportError`) → engine reaction

| Error | Origin | Engine reaction |
|---|---|---|
| `unauthorized` | HTTP 401 | Sets `authPaused`, emits `.authRequired`, and stops. Only a **manual** kick (`.manual` / `.hostSpecific`) resumes — a periodic/connectivity kick is ignored while auth-paused. |
| `resyncRequired` | HTTP 410 | `performResync`: `resetForResync()` (mirror + cursor cleared, outbox preserved), emit `.resyncPerformed`, full re-pull, then replay the outbox (adh `sync.md` §4). A second consecutive 410 mid-resync gets **one** immediate nested retry; any further one routes through backoff. |
| `transport(String)` | network / 5xx | Emits `.failed`, increments the failure count, schedules an exponential-backoff retry (`min(baseBackoff · 2^(n-1), maxBackoff)`, then a `.periodic` kick). |
| `invalidResponse(statusCode:)` | other non-2xx | Thrown like any other error → `.failed` + backoff. |

The engine's own internal failures — `manifestUnstable`, `pullMadeNoProgress`,
`pushMadeNoProgress` (see the flapping bound) — surface through the same
`.failed` + backoff path; they are not part of the frozen public surface.

### Push results (`SyncPushStatus`) → client reaction

Each op in a `/sync/push` batch comes back with one of three statuses, resolved
per-op in `SyncEngine.pushLoop`:

| Status | Client reaction |
|---|---|
| `applied` | The op succeeded. If the result carries `newVersion`, the store adopts it as the mirror row's base version **before** deleting the outbox row, in the same transaction — closing the stage-during-push self-conflict race (adh `sync.md` §3). Then the outbox row is removed. |
| `conflict` | Adopt the server's `current` row locally (last-writer-wins, delete-wins): if `current.deleted_at` is set, adopt as a local delete; otherwise adopt its data, stripping the bookkeeping columns `sync_version` / `sync_stamped_at`, and preserve the server's `sync_version` as the new base. Emits `.conflictResolved`. Two edge cases **quarantine** instead of adopting (fix A3): a `conflict` carrying no `current` row has nothing to adopt; and a `current.sync_version` that can't yield a numeric version — a non-finite/out-of-`Int64` number OR a non-numeric string (`current` is `z.unknown()`, unvalidated on the wire) — is unadoptable. Both route to the terminal quarantine path (reason preserved) rather than being handed to `apply` (which would throw and wedge the loop); the rest of the batch still `complete`s so the push makes progress. |
| `rejected` | **Terminal.** Quarantine the op and never retry it under the same opId — the server ledgers results immutably per opId. A fixed retry must mint a fresh opId via a new `stage(_:)`. |

**Every rejected reason** (server-assigned; see the recipe's
`rejected-is-terminal` and adh `sync.md` §3) draws the same uniform client
reaction — quarantine, no retry:

| Reason | Meaning |
|---|---|
| `unknown_resource` | The server does not know this resource. |
| `not_enrolled` | Enrollment for this resource was disabled (possibly racing an in-flight push). |
| `route_only` | A `pushMode: 'route'` resource — its writes belong to a bespoke route a generic push may not use. |
| `invalid_data` | The payload failed server-side validation. |
| `constraint_violation` | The write violated a server constraint. |

### Quarantine semantics and surfacing depth

Quarantine is an outbox status, not a deletion: a quarantined op is **surfaced,
never silently dropped, never pushed**. In `GRDBSyncStore` the outbox
(`_sync_outbox`) carries a `status` column that moves `pending` → `inflight`
(handed to a push round-trip) → resolved: an `applied`/adopted `conflict` op is
deleted, a `rejected` op or a `purgeResources` casualty becomes `quarantined`.
Conflicts are additionally recorded in the `_sync_conflicts` audit table (a
historical record, not live sync state).

Hosts read depth back through `GRDBSyncStore.status()` (annotated below — the
inline comments are added for this doc, not present in the source):

```swift
public struct GRDBSyncStoreStatus: Codable, Sendable {
    public let cursor: String?
    public let outboxDepth: Int        // pending + inflight — ops still owed to the server
    public let quarantinedDepth: Int   // quarantined — surfaced, never pushed
    public let conflictCount: Int      // rows in the _sync_conflicts audit
}
```

The daemon serves this at `/adhd/sync/status`; a UI host surfaces the same three
numbers as a badge. `quarantinedDepth > 0` is the signal a host uses to prompt
the user (the edits that need a fresh `stage` retry); `outboxDepth` is
"unsynced work pending"; `conflictCount` is the running audit.

### Bookkeeping tables (GRDB)

`GRDBSyncStore` keeps four bookkeeping tables plus one mirror table per
registered resource:

| Table | Holds |
|---|---|
| `_sync_state` | The single opaque cursor (`id = 1`, `cursor TEXT`). |
| `_sync_resources` | `resource -> schema_version` registrations. |
| `_sync_outbox` | Queued local ops: `op_id`, `resource`, `row_id`, `type`, `base_version`, `payload`, `status`, `attempts`, `created_at`. |
| `_sync_conflicts` | Append-only conflict audit. |
| `<resource>` (per resource, `.` → `_`) | Mirror rows: `id`, `sync_version`, `deleted_at` (soft delete), `data` (JSON blob). |

The cursor is treated as opaque throughout — never fabricated, parsed, or
compared beyond equality, and persisted only together with an atomically
applied pull batch. See the recipe's conformance vectors (`cursor-is-opaque`,
`recovery-never-deletes-database`) for the tests that lock these invariants.

## See also

- [`../cookbook/adh-offline-sync-client.md`](../cookbook/adh-offline-sync-client.md) —
  the platform-neutral behavioral contract (17 requirements + conformance
  vectors). The source of truth for _what_ the client must do.
- adh `backend/src/adh/docs/architecture/sync.md` — the server-side contract
  (registry, pull, §3 Push, §4 Resync).
- adh `backend/src/adh/src/sync/wire.ts` — the authoritative wire shapes
  `SyncWire.swift` mirrors.
- [`repo-pattern.md`](repo-pattern.md) /
  [`consuming-as-submodule.md`](consuming-as-submodule.md) — how the toolkit is
  laid out and embedded by a first-party consumer.
