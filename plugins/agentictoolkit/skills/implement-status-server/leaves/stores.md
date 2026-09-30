<!-- leaf: implement-status-server/stores · source: status-server-stores.md -->

# Status Server Stores

## Overview

This is the status backend's storage-port implementation layer: 14 files under
`src/libsql/stores/` that are the ONLY code in the package allowed to import
Drizzle's query builder or the driver types alongside `src/storage/ports.ts`'s
plain-domain interfaces. Thirteen of the files each export one
`createXStore(db, ...)` factory returning a port object (`AuthStore`,
`TokenStore`, `DeviceStore`, `HealthStore`, `HistoryStore`, `IssueStore`,
`ObservationStore`, `PeerStore`, `DeployStore`, `BoardStore`, `ConfigStore`,
`MaintenanceStore`, `TelemetryStore`); `src/libsql/index.ts`'s
`createLibsqlStorage(db, conn?)` composes all 13 into one `Storage` object,
passing `conn` only to `createMaintenanceStore`. The fourteenth file,
`owned-deploys.ts`, is not a store — it exports `ownedDeploysWhere(projects)`,
a shared SQL-predicate helper that `deploy-store.ts` and `board-store.ts` both
call to scope a query to a caller's owned platform/project set. Every method
on every port either returns a plain domain type from `ports.ts` or resolves
`void`/`boolean`/`number` — no query-builder or driver type crosses back out
of this layer. The methods embed atomic guards directly in SQL WHERE/subquery
clauses rather than reading then writing, to close race windows a monitor
cycle (polling) and a webhook route (pushing) can otherwise open against the
same row concurrently: the last-admin guard (`auth-store.ts`), the
webhook-vs-poll ordering guard (`deploy-store.ts`), the TOCTOU-safe
conditional deletes (`config-store.ts`), and the single-use atomic
delete-returning device-grant consumption (`device-store.ts`). Bulk writes
are chunked to stay under SQLite's per-statement parameter-count limit and
keep individual transactions small (`deploy-store.ts`'s
`UPSERT_CHUNK_PROJECTS`, `config-store.ts`'s `DELETE_CHUNK_NAMES`,
`maintenance-store.ts`'s `PRUNE_CHUNK_ROWS`/`PRUNE_MAX_ROWS_PER_RUN`), and
several failure paths are deliberately fail-soft (WAL checkpoint, DB
snapshot, orphan reconcile) so that a maintenance side-effect can never fail
the monitor cycle it rides along with. Secrets are hash-only at rest across
`auth-store.ts`, `token-store.ts`, and `device-store.ts`, with one documented,
time-boxed exception. `telemetry-store.ts` reconciles a polled "currently
unresolved" set against the stored table rather than only appending to it,
so an issue that stops being reported is swept closed instead of staying
open forever.

