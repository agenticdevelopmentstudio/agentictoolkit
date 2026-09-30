<!-- leaf: implement-status-server/stores--part-4 · source: status-server-stores.md -->

# Status Server Stores — continued (part 4)

**Rules** (cite as `implement-status-server/stores--part-4#<slug>`):

- `rollup-metrics` MUST
- `budgeted-chunked-prune` MUST
- `fail-soft-checkpoint` MUST
- `no-conn-degrades-maintenance` MUST
- `snapshot-fail-soft` MUST
- `snapshot-success-logged` MUST
- `errors-reconcile-not-append` MUST
- `empty-poll-resolves-all` MUST
- `fetched-at-not-restamped-on-sweep` MUST
- `truncated-poll-logged-not-swept` MUST
- `project-refreshed-on-conflict` MUST
- `analytics-append-only` MUST
- `errors-and-analytics-load` MUST
- `swiftui-appkit-uikit` MUST — a client consuming this same contract would model each store as a small actor (or a @MainActor-isolated service) …
- `jetpack-compose` MUST — model each store as a class exposing suspend fun methods returning sealed result types (mirroring …

### Maintenance (maintenance-store.ts)

- **rollup-metrics**: `rollupMetrics(serviceSlugs)` MUST recompute and
  upsert `metrics_hourly` buckets for every hour touched by
  `health_checks` rows for `serviceSlugs`, via the exported
  `rollupMetricsSql(serviceSlugs)` fragment.
- **budgeted-chunked-prune**: the retention prune inside `runMaintenance`
  MUST delete in batches no larger than `PRUNE_CHUNK_ROWS` rows per
  statement and MUST stop once it has deleted `PRUNE_MAX_ROWS_PER_RUN`
  rows in a single call, deferring any remaining backlog to the next
  scheduled run rather than running one unbounded delete.
- **fail-soft-checkpoint**: `runMaintenance`'s WAL-checkpoint step MUST
  catch any error from `checkpointWal` and log it via `console.error` with
  the message `` `[maintenance] wal checkpoint failed: ${message}` ``
  rather than letting a checkpoint failure abort the rest of the
  maintenance cycle.
- **no-conn-degrades-maintenance**: when `createMaintenanceStore` was
  built without a `conn`, the WAL-checkpoint and DB-snapshot steps MUST
  be skipped rather than throw; the first time either step is skipped,
  `warnNoConn(step)` MUST log exactly once per store instance via
  `console.warn` with the message `` `[maintenance] ${step} skipped:
  storage was built without a connection descriptor
  (createLibsqlStorage(db, conn)) — WAL checkpoint and DB snapshots are
  disabled` `` — every later skip in the same store instance MUST NOT
  log again.
- **snapshot-fail-soft**: `snapshotIfDue(opts?)` MUST catch any error
  from the VACUUM-INTO snapshot attempt, log it via `console.error` with
  the message `` `[snapshot] failed: ${message}` ``, and resolve `{
  created: false }` rather than reject — a failing backup MUST NOT fail
  the maintenance cycle it rides along with.
- **snapshot-success-logged**: on a successful snapshot,
  `snapshotIfDue` MUST log via `console.log` with the message
  `` `[snapshot] wrote ${finalPath}` `` and resolve `{ created: true,
  path: finalPath }`.

### Telemetry (telemetry-store.ts)

- **errors-reconcile-not-append**: `errorsStore.save(items, opts?)` MUST
  upsert every item in `items` by `issueKey` and MUST then resolve every
  currently-unresolved row NOT present in `items` to `resolved = true`,
  UNLESS `opts.complete === false`, in which case the sweep MUST be
  skipped entirely for that call — an item present in `items` but not
  seen on a prior call MUST also be reopened (`resolved` reset to
  `false`) via the upsert's own `excluded.resolved` conflict clause.
- **empty-poll-resolves-all**: an empty `items` array with
  `opts.complete !== false` MUST resolve every still-open row, and MUST
  do so via a branch that does not compile to `NOT IN ()` (invalid SQLite
  syntax for an empty exclusion list) — this is the case
  `notInArray` cannot express directly and the store MUST route around
  it explicitly.
- **fetched-at-not-restamped-on-sweep**: a row resolved by the sweep
  (because it was absent from the poll) MUST NOT have its `fetchedAt`
  updated — `fetchedAt` records when a row was last actually seen, and a
  swept row was, by definition, not seen this poll.
- **truncated-poll-logged-not-swept**: when the upstream poll itself was
  truncated (a full page with no confirmation the answer is complete),
  `save` MUST upsert whatever it saw and MUST skip the sweep, logging via
  `console.warn` with the message `` `[telemetry] GlitchTip returned a
  full page (${items.length}); the unresolved set is truncated, so no
  rows were swept this poll` `` — sweeping a partial page would resolve
  everything past its edge and cause a flap between open and resolved on
  every subsequent poll for a project whose issue count straddles the
  page boundary.
- **project-refreshed-on-conflict**: on conflict, `project` MUST be
  overwritten (never frozen at first insert) — `project` is the field the
  board mints its issue-ledger key from, so a stale value would derive a
  target no current fact mentions.
- **analytics-append-only**: `analyticsStore.save(items)` MUST plain
  insert every item with no conflict handling — analytics rows are
  point-in-time samples, never upserted or reconciled the way errors are.
- **errors-and-analytics-load**: `errorsStore.load()` MUST return only
  currently-unresolved rows; `analyticsStore.load()` MUST return every
  stored sample.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `conn` | `LibsqlConnection \| undefined` | `undefined` | Passed to `createLibsqlStorage(db, conn)`; forwarded only to `createMaintenanceStore`. Omitting it degrades `runMaintenance`/`snapshotIfDue` to a logged no-op for their checkpoint/snapshot steps rather than failing construction. |
| `SESSION_TTL_MS` | `number` (module constant, `auth-store.ts`) | source-defined | Session lifetime passed to `createSession`'s default `ttlMs` parameter when a caller does not override it. |
| `UPSERT_CHUNK_PROJECTS` | `number` (module constant, `deploy-store.ts`) | `200` | Maximum deployments per upsert statement in `upsertDeployments`/`learnProjectIds`. |
| `DELETE_CHUNK_NAMES` | `number` (module constant, `config-store.ts`/`deploy-store.ts`) | `500` | Maximum names per chunked delete statement (`deleteProjectMeta`, ignored-project bulk deletes). |
| `PRUNE_CHUNK_ROWS` | `number` (module constant, `maintenance-store.ts`) | `25_000` | Maximum rows deleted per statement inside the retention prune. |
| `PRUNE_MAX_ROWS_PER_RUN` | `number` (module constant, `maintenance-store.ts`) | `100_000` | Total row-delete budget per `runMaintenance` call before the remaining backlog is deferred to the next run. |
| `opts.source` | `"webhook" \| undefined` | `undefined` | `upsertDeployments(deploys, opts)`'s discriminator between a webhook push (ordering-guarded) and a poll (treated as current truth). |
| `opts.complete` | `boolean \| undefined` | `undefined` (treated as `true`) | `errorsStore.save(items, opts)`'s discriminator for whether `items` is a whole answer (sweep runs) or a truncated page (sweep skipped). |
| `SnapshotOptions` fields | object | source-defined | Passed to `snapshotIfDue(opts)` to control snapshot cadence/destination; an omitted option set uses the store's built-in defaults. |
| `TOKEN_PREFIX` / `PREFIX_LEN` | `string` / `number` (module constants, `token-store.ts`) | `'sts_'` / source-defined | Display-only API-token prefix format; never affects the hashed value used for validation. |

## Privacy

- **Data collected**: `auth-store.ts` persists an email, optional password
  hash, optional GitHub id, and role per user. `token-store.ts` persists
  only a `tokenHash` and a display-only `prefix` per API token — never the
  raw bearer. `device-store.ts` persists only `deviceCodeHash`/
  `userCodeHash` per grant, with `tokenRaw` as the one documented,
  time-boxed exception: held in the row only between `approve` and the
  single successful `consumeApproved` call, which clears it as part of
  the same atomic statement. `telemetry-store.ts` persists polled,
  aggregate third-party data (GlitchTip issue titles/culprits/counts,
  analytics pageview/visitor counts) — not raw end-user request data.
- **Storage**: every store in this layer persists through the single `Db`
  handle it is constructed with; none opens a second connection or writes
  to a second store.
- **Transmission**: none of these 14 files performs a network call —
  `validateApiToken`, `resolveSession`, and every other lookup compare
  only locally-computed hashes against stored hashes; the raw secret a
  caller presents is hashed in-process and never re-transmitted or logged
  by this layer.
- **Retention**: `pruneOlderThanDays` (deploy-store.ts), the retention
  prune inside `runMaintenance` (maintenance-store.ts), and `purgeExpired`
  (device-store.ts) are this layer's own retention mechanisms;
  `deleteGroup`/`deleteSite`/`deleteEndpoint`'s history/issue cascades
  (config-store.ts) are retention triggered by an explicit administrative
  delete rather than age. No other file in this layer deletes a row on a
  schedule of its own.

## Platform Notes

- **TypeScript / Node (source)**: this layer is written directly against
  Drizzle ORM's query builder over `@libsql/client`; every atomic guard is
  expressed as a single SQL statement's WHERE/subquery/`ON CONFLICT`
  clause rather than an application-level lock, which is what makes the
  guards safe under Node's single-threaded, interleaved-`await` execution
  model.
- **SwiftUI / AppKit / UIKit**: a client consuming this same contract
  would model each store as a small `actor` (or a `@MainActor`-isolated
  service) exposing `async throws` methods mirroring the port signatures;
  a device-grant's single-use consumption (`consumeApproved`) maps to a
  server round trip whose response is only ever accepted once client-side
  too — the client MUST NOT infer "not consumed yet" from a `nil`
  response without a fresh request, since the guard's authority is the
  server's atomic statement, not client-side caching.
- **Jetpack Compose (Kotlin)**: model each store as a `class` exposing
  `suspend fun` methods returning sealed result types (mirroring
  `"blocked"`/`true`/`false`/`null` as a sealed class rather than a raw
  boolean-or-string union), backed by a Retrofit/Ktor client; the
  webhook-vs-poll ordering guard has no client-side analog — a Compose
  client only ever sees the server's already-reconciled state and MUST
  NOT attempt to re-derive the ordering rule locally.
- **WinUI 3**: model each store as a service class using `HttpClient` for
  the network hop and `System.Text.Json` for (de)serializing the same
  plain domain shapes `ports.ts` defines, with results surfaced through an
  `ObservableCollection<T>` (for list-shaped reads like `listActive`,
  `listOpen`, `listRecentOwned`) and `INotifyPropertyChanged` for
  single-row state (a resolved session, a consumed device grant); every
  method should be `async Task<T>`, and a `"blocked"`/`false`/`null`
  outcome should surface as a discriminated result type rather than a
  thrown exception, matching this layer's own use of return values (not
  throws) for an expected "guard tripped" outcome.

