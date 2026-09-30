<!-- leaf: implement-status-server-monitor-2/reconcile-stuck-deploys--part-2 · source: status-server-monitor-reconcile-stuck-deploys.md -->

# Status Server Monitor Reconcile Stuck Deploys — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-2/reconcile-stuck-deploys--part-2#<slug>`):

- `park-on-no-phases` MUST
- `terminalize-on-gone` MUST
- `persist-fresh-phases` MUST
- `park-on-throw` MUST
- `backoff-escalation` MUST
- `backoff-memory-window` MUST
- `terminal-writes-bump-fetched-at` MUST
- `expire-collapses-stale-in-flight` MUST
- `expire-logs-nonzero-count` MUST
- `expire-fail-soft` MUST
- `expiry-not-created-at-windowed` MUST
- `expired-value-is-overwritable` MUST
- `tokens-used-for-auth-only` MUST
- `module-state-scope` MUST
- `test-hook-only` MUST
- `intra-call-concurrency-bound` MAY

### Persistence and Backoff

- **park-on-no-phases**: when `fetchPhasesFor` resolves `null` for a row, `reconcileVanishedDeploys` MUST call `parkFailure(row.id, Date.now())` and MUST NOT call `storage.deploy.markDeployGone` or `storage.deploy.markDeployPhases` for that row.
- **terminalize-on-gone**: when `fetchPhasesFor` resolves `"gone"` for a row, `reconcileVanishedDeploys` MUST call `storage.deploy.markDeployGone(row.id)`, log `` `[reconcile] ${row.id} gone at provider → canceling in-flight lifecycle(s)` `` via `console.log`, and MUST delete `row.id` from `retryAfterFailure`.
- **persist-fresh-phases**: when `fetchPhasesFor` resolves a `Phases` object for a row, `reconcileVanishedDeploys` MUST call `storage.deploy.markDeployPhases(row.id, phases)` and MUST delete `row.id` from `retryAfterFailure`, treating the by-id fetch as authoritative and overwriting both lifecycle columns unconditionally.
- **park-on-throw**: when `fetchPhasesFor`, `markDeployGone`, or `markDeployPhases` rejects for a row, `reconcileVanishedDeploys` MUST catch that rejection inside that row's `mapLimit` callback, call `parkFailure(row.id, Date.now())`, log `` `[reconcile] ${row.id} phase fetch/store failed:` `` via `console.error` with the caught error as the second argument, and MUST NOT let the rejection propagate out of `mapLimit` or affect the processing of any other row.
- **backoff-escalation**: `parkFailure(id, now)` MUST set `fails` to the previous entry's `fails + 1` when a previous `retryAfterFailure` entry for `id` exists and its `until + RECONCILE_BACKOFF_MEMORY_MS` (600,000ms) is greater than `now`, and MUST set `fails` to `1` otherwise; it MUST then set `until` to `now + min(RECONCILE_BACKOFF_BASE_MS * 2^(fails - 1), RECONCILE_BACKOFF_MAX_MS)` — that is, `60,000ms` doubling on each consecutive escalating failure, capped at `300,000ms` (5 minutes).
- **backoff-memory-window**: a row's escalation count MUST reset to `1` on its next failure once its previous backoff's `until + RECONCILE_BACKOFF_MEMORY_MS` (600,000ms) has passed without a further failure for that id, per `backoff-prune-before-query`'s deletion of expired entries.
- **terminal-writes-bump-fetched-at**: per the libsql implementation of `markDeployGone` and `markDeployPhases`, both MUST set the row's `fetchedAt` to the current time on every write, so a row confirmed still building defers its next reconcile candidacy by `RECONCILE_STALE_MS` from that write, not from its original stale `fetchedAt`.

### Terminal Expiry (`expireUnconfirmedDeploys`)

- **expire-collapses-stale-in-flight**: `expireUnconfirmedDeploys` MUST call `storage.deploy.expireStaleInFlight(EXPIRE_UNCONFIRMED_MS)` (21,600,000ms / 6 hours), which — per the libsql implementation — collapses only the in-flight build/deploy lifecycle column(s) of a row unconfirmed (by `fetchedAt`) for at least that long to `unknown`, leaving any already-settled sibling lifecycle column on that same row untouched.
- **expire-logs-nonzero-count**: when `expireStaleInFlight` resolves a count `n` greater than `0`, `expireUnconfirmedDeploys` MUST log `` `[reconcile] ${n} in-flight deploy row(s) unconfirmable for 6h+ → unknown` `` via `console.log`; when `n` is `0` it MUST NOT log anything.
- **expire-fail-soft**: when `storage.deploy.expireStaleInFlight` rejects, `expireUnconfirmedDeploys` MUST catch the rejection, log it via `console.error` with `[reconcile] expiry sweep failed:` as the first argument and the caught error as the second, and MUST NOT rethrow.
- **expiry-not-created-at-windowed**: `expireStaleInFlight`'s predicate MUST NOT filter by the row's `createdAt`/`RECONCILE_WINDOW_DAYS` — a row's age since creation MUST NOT exempt it from expiry; only its `fetchedAt` staleness against `EXPIRE_UNCONFIRMED_MS` gates it, so a row that aged past the reconcile window (and so can no longer be re-fetched by id) is still reachable by expiry.
- **expired-value-is-overwritable**: because the shared `columnOverwritableSql` predicate treats a column value of `unknown` as overwritable (in the same way an in-flight value is), a fresh provider truth arriving later for that column — a poll upsert, a subsequent by-id re-fetch from this module, or a webhook — MUST replace an `unknown` value written by `expireStaleInFlight`, so a false expiry self-heals the next time any of those sources reports.

### Credential Handling

- **tokens-used-for-auth-only**: `fetchVercelPhasesById` and `fetchRailwayPhasesById` MUST use `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` only to construct the outbound `Authorization` header or GraphQL call to the corresponding provider, MUST NOT read any of the three from `process.env` or any source other than the `conn` parameter, and MUST NOT log or persist any of the three values.

### Ordering and Concurrency

- **module-state-scope**: `retryAfterFailure` MUST be a module-scope `Map<string, Backoff>` — worker-thread-local and unpersisted across a process restart, per the source's own comment on its declaration.
- **test-hook-only**: `_resetReconcileBackoff` MUST clear `retryAfterFailure` and MUST exist only to reset module state between tests; neither `sync.ts` nor `cycle-runner.ts` call it from any production code path.
- **intra-call-concurrency-bound**: within one `reconcileVanishedDeploys` call, up to `RECONCILE_CONCURRENCY` (4) candidate rows' fetches MAY run concurrently via `mapLimit`, each with its own `AbortController`/timer pair and targeting a distinct row id, so no two concurrent fetches within one call can write to the same storage row or share a timeout.
- **thread-context**: `reconcileVanishedDeploys` and `expireUnconfirmedDeploys` run on whichever thread their caller (`runCycle` in `sync.ts`, via `runMonitorCycle` in `cycle-runner.ts`) is executing on — the monitor's own worker thread for a scheduled cycle, or the API thread when invoked from there; this file makes no thread-affinity assumption of its own beyond running to completion on whichever thread called it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | required, caller-supplied | The storage port providing `storage.deploy.listInFlightCandidates`, `markDeployGone`, `markDeployPhases`, and `expireStaleInFlight`; this file never constructs or configures a storage implementation itself. |
| `conn` (parameter, `reconcileVanishedDeploys` only) | `ProviderConn` | required, caller-supplied | Resolved provider connections (`@agentic-toolkit/deploy-platform/conn`), carrying `conn.vercel.token`/`conn.vercel.teamId` and `conn.railway.token`, used to gate and authenticate the per-provider by-id fetches. |
| `RECONCILE_WINDOW_DAYS` (module-internal constant, not exported) | `number` | `14` | Recency window in days; only in-flight rows created within this window are reconcile candidates. |
| `RECONCILE_MAX_PER_CYCLE` (module-internal constant, not exported) | `number` | `10` | Maximum candidate rows queried and fetched per `reconcileVanishedDeploys` call. |
| `RECONCILE_CONCURRENCY` (module-internal constant, not exported) | `number` | `4` | Maximum concurrent in-flight fetches passed to `mapLimit`. |
| `RECONCILE_CALL_TIMEOUT_MS` (module-internal constant, not exported) | `number` | `8_000` | Per-row fetch deadline enforced via `AbortController`/`setTimeout`. |
| `RECONCILE_STALE_MS` (exported constant) | `number` | `120_000` (2 min) | How long an in-flight row may go unconfirmed before it becomes a reconcile candidate; also doubles as the natural retry cadence for a genuinely still-building row, since every check bumps `fetchedAt`. Deliberately shorter than the deploy poll's default 5-minute interval. |
| `RECONCILE_BACKOFF_BASE_MS` (exported constant) | `number` | `60_000` (1 min) | Base delay for a failing row's exponential backoff. |
| `RECONCILE_BACKOFF_MAX_MS` (exported constant) | `number` | `300_000` (5 min) | Cap on a failing row's escalating backoff delay. |
| `RECONCILE_BACKOFF_MEMORY_MS` (exported constant) | `number` | `600_000` (10 min) | How long a lapsed backoff's escalation count is remembered past its expiry before a fresh failure resets to the base delay. |
| `EXPIRE_UNCONFIRMED_MS` (exported constant, `expireUnconfirmedDeploys`) | `number` | `21_600_000` (6 hours) | How long an in-flight lifecycle column may stay unconfirmed before `expireUnconfirmedDeploys` collapses it to `unknown`. |
| `retryAfterFailure` (module-level state, not a parameter) | `Map<string, Backoff>` | empty at module load | Per-row backoff registry (`{ until: number; fails: number }`); worker-thread-local and unpersisted across a process restart. |

## Privacy

- **Data collected**: this file receives `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` as opaque values (sourced by callers external to this file — `providerConnFromConfig`/`connFromEnv` in `deploy-platform/conn`) and, unlike a pass-through consumer, uses the token values itself to build the outbound `Authorization: Bearer` header (`fetchVercelPhasesById`) and the `gqlPost` call (`fetchRailwayPhasesById`). It also reads and persists each provider's own reported build/deploy phase via `storage.deploy.markDeployPhases`/`markDeployGone` — enumerated phase values only, never free-form provider text.
- **Storage**: the provider tokens are held only as in-memory `conn` fields for the duration of one `reconcileVanishedDeploys` call; this file never writes a token to storage. Token lifetime, storage, and revocation are entirely the concern of the `conn` resolution this file is handed (`deploy-platform/conn`, external to this file) — this file has no lifetime, storage, or revocation logic of its own to specify beyond "never persisted."
- **Transmission**: `conn.vercel.token` is transmitted over HTTPS as a Bearer credential to `api.vercel.com`; `conn.railway.token` is transmitted over HTTPS as a Bearer credential inside `gqlPost`'s GraphQL request to Railway's API. Neither token is ever logged by this file — every `console.error`/`console.log` call here logs only a deployment id, a platform name, an HTTP status, or a row count.
- **Retention**: not applicable to this file directly; the `buildPhase`/`deployPhase` values it persists are retained for as long as the `deployments` row exists, governed by `storage.deploy.pruneOlderThanDays(90)`, called elsewhere in `sync.ts` and external to this file.

