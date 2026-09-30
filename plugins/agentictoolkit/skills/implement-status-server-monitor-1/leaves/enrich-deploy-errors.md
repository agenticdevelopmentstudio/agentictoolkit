<!-- leaf: implement-status-server-monitor-1/enrich-deploy-errors · source: status-server-monitor-enrich-deploy-errors.md -->

**Rules** (cite as `implement-status-server-monitor-1/enrich-deploy-errors#<slug>`):

- `enrich-deploy-errors-signature` MUST
- `runs-after-upsert` MUST
- `never-throws` MUST
- `candidate-platform-filter` MUST
- `no-pollable-platform-short-circuit` MUST
- `candidate-query-shape` MUST
- `candidate-window-boundary` MUST
- `query-failure-fail-soft` MUST
- `empty-candidates-short-circuit` MUST
- `id-platform-row-shape` MUST
- `platform-dispatch-vercel` MUST
- `platform-dispatch-railway` MUST
- `platform-dispatch-fallback-null` MUST
- `per-call-timeout` MUST
- `bounded-concurrency` MUST
- `persist-only-truthy-text` MUST
- `no-persist-on-null` MUST
- `idempotent-enrichment` MUST
- `per-row-fetch-failure-fail-soft` MUST
- `timeout-manifests-as-abort` MUST
- `tokens-passed-opaque` MUST
- `tokens-gate-not-authenticate` MUST
- `single-invocation-per-cycle` MUST
- `intra-call-concurrency-bound` MAY

# Status Server Monitor Enrich Deploy Errors

## Overview

`enrich-deploy-errors.ts` (`packages/web/packages/status-server/src/monitor/enrich-deploy-errors.ts`) is the status backend's deploy-error enrichment healer. Its own header comment states the problem it exists to fix: a failed Vercel or Railway deploy row is stored with no explanation of WHY it failed, so the details pane (and its copy button) has nothing to show an operator short of opening the provider's own dashboard. This module fills in `error_text` for failed deploys that don't have it yet — Vercel's `errorMessage` via `fetchVercelDeployError`, Railway's build-log tail via `fetchRailwayBuildLogTail` — fetched ONCE per deploy and persisted via `storage.deploy.setErrorText`. It exports one function, `enrichDeployErrors`, invoked by `sync.ts`'s `runCycle` immediately after `storage.deploy.upsertDeployments` on every full sync cycle. Per its own doc comment it is deliberately bounded and fail-soft: a recent-only window, a small per-cycle cap, bounded concurrency, and a per-call timeout keep it from threatening the cycle's own time budget, and every fetch is wrapped so a single failure can never abort the cycle — a failed fetch just leaves `error_text` null, to retry next cycle.

## Behavioral Requirements

### Public Operation

- **enrich-deploy-errors-signature**: `enrichDeployErrors` MUST accept exactly two parameters — `storage: Storage` and `conn: ProviderConn` — and MUST return `Promise<void>`.
- **runs-after-upsert**: Per `sync.ts`'s own call order and comment, `enrichDeployErrors` MUST be invoked only after `storage.deploy.upsertDeployments` has persisted the current cycle's freshly fetched deploys, so `listFailedWithoutError` can see failures upserted earlier in that same cycle.
- **never-throws**: `enrichDeployErrors`'s returned promise MUST NOT reject on any traced failure path (a candidate-query rejection, a per-row fetch/store rejection, or a per-call timeout) — every one of those is caught internally and logged, never re-thrown.

### Candidate Selection

- **candidate-platform-filter**: `enrichDeployErrors` MUST compute its candidate platform list as `pollableByIdPlatforms(conn)` filtered to exclude any provider for which `rateLimitedUntil(provider)` is non-null (currently cooling down after a 429), and MUST use only that filtered list (`polled`) as the `platforms` argument to `storage.deploy.listFailedWithoutError`.
- **no-pollable-platform-short-circuit**: When the filtered `polled` list is empty — per the source comment, "no token, or both cooling down" — `enrichDeployErrors` MUST return immediately without calling `storage.deploy.listFailedWithoutError` and without performing any provider fetch.
- **candidate-query-shape**: `enrichDeployErrors` MUST call `storage.deploy.listFailedWithoutError` with `platforms` set to `polled`, `createdAfterMs` set to `Date.now()` minus `ENRICH_WINDOW_DAYS` (14) days expressed in milliseconds, and `limit` set to `ENRICH_MAX_PER_CYCLE` (8).
- **candidate-window-boundary**: Per the libsql `listFailedWithoutError` implementation's `gt(deployments.createdAt, new Date(input.createdAfterMs))` predicate, a deploy row created at exactly the 14-day-ago instant MUST be excluded from the candidate set, not included — the boundary is strictly greater-than.
- **query-failure-fail-soft**: When `storage.deploy.listFailedWithoutError` rejects, `enrichDeployErrors` MUST catch the rejection, log it via `console.error` with `[enrich] failed-deploy query failed:` as the first argument and the caught error as the second, and return without calling `mapLimit` or performing any provider fetch.
- **empty-candidates-short-circuit**: When `listFailedWithoutError` resolves an empty array, `enrichDeployErrors` MUST return without calling `mapLimit` or performing any provider fetch.

### Platform Dispatch (`fetchErrorFor`)

- **id-platform-row-shape**: A `DeployIdPlatformRow` value, as returned by `listFailedWithoutError`, MUST carry exactly two fields — `id: string` and `platform: string` — per its declaration in `storage/ports.ts`.
- **platform-dispatch-vercel**: `fetchErrorFor` MUST call `fetchVercelDeployError` when `row.platform === "vercel"` and `conn.vercel.token` is set, passing `row.id` with a leading `vc_` prefix stripped, an env object built from `conn.vercel.token`/`conn.vercel.teamId`, and the per-call `AbortSignal`.
- **platform-dispatch-railway**: `fetchErrorFor` MUST call `fetchRailwayBuildLogTail` when `row.platform === "railway"` and `conn.railway.token` is set, passing `row.id` with a leading `ry_` prefix stripped, `conn.railway.token`, and the per-call `AbortSignal`.
- **platform-dispatch-fallback-null**: For a row whose platform/token combination matches neither the Vercel nor the Railway branch, `fetchErrorFor` MUST resolve `null` without making any network call — per its own doc comment, "for a platform we can't fetch (no token / no reason)."
- **per-call-timeout**: For each candidate row, `enrichDeployErrors` MUST create an `AbortController`, start a `setTimeout` that calls `controller.abort()` after `ENRICH_CALL_TIMEOUT_MS` (8,000) milliseconds, pass `controller.signal` into `fetchErrorFor`, and MUST clear that timer in a `finally` block regardless of whether the fetch settled, rejected, or was aborted.
- **bounded-concurrency**: `enrichDeployErrors` MUST process the candidate rows via `mapLimit` with a concurrency limit of `ENRICH_CONCURRENCY` (4), so no more than 4 candidate rows are ever being fetched at the same instant.

### Persistence

- **persist-only-truthy-text**: When `fetchErrorFor` resolves a truthy string for a row, `enrichDeployErrors` MUST call `storage.deploy.setErrorText(row.id, text)` exactly once for that row before that row's `mapLimit` task completes.
- **no-persist-on-null**: When `fetchErrorFor` resolves `null` for a row, `enrichDeployErrors` MUST NOT call `storage.deploy.setErrorText` for that row, and MUST NOT log anything for that row — a null result is a normal outcome (no reason available yet), not a failure.
- **idempotent-enrichment**: Because `setErrorText` sets a row's `error_text` to a non-null value and `listFailedWithoutError`'s own predicate (`isNull(deployments.errorText)`) excludes any row with a non-null `error_text`, a row enriched in one cycle MUST NOT be re-selected as a candidate by a later cycle's call to `listFailedWithoutError` — from this function's perspective, enrichment of a given row is write-once.

### Error Handling and Fail-Soft Behavior

- **per-row-fetch-failure-fail-soft**: When `fetchErrorFor` or the subsequent `setErrorText` call rejects for one candidate row, `enrichDeployErrors` MUST catch that rejection inside that row's `mapLimit` callback, log it via `console.error` with a template string `` `[enrich] ${row.id} error fetch/store failed:` `` as the first argument and the caught error as the second, and MUST NOT let that rejection propagate out of the `mapLimit` call or affect the processing of any other candidate row.
- **timeout-manifests-as-abort**: When a candidate row's fetch has not settled after `ENRICH_CALL_TIMEOUT_MS` (8,000) milliseconds, the fired timer's `controller.abort()` call MUST cause the in-flight `fetchErrorFor` call's underlying request promise to reject with an abort error, which MUST then be caught and logged exactly as any other per-row fetch failure (per-row-fetch-failure-fail-soft), not treated as a distinct case.

### Credential Handling

- **tokens-passed-opaque**: `enrichDeployErrors` and `fetchErrorFor` MUST treat `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` as opaque values received via the `conn` parameter — this file MUST NOT read them from `process.env` or any other source itself, and MUST NOT log, persist, or otherwise expose any of these three values.
- **tokens-gate-not-authenticate**: This file's own use of a provider token MUST be limited to a truthiness check (`conn.vercel.token` / `conn.railway.token` set or unset) that decides whether `fetchErrorFor` attempts a fetch at all; the token value itself is forwarded unread to `fetchVercelDeployError`/`fetchRailwayBuildLogTail` (both external to this file), which are the functions that actually place it on an outbound request.

### Ordering and Concurrency

- **single-invocation-per-cycle**: `enrichDeployErrors` MUST be invoked at most once per full sync cycle, synchronously awaited by `runCycle` before that cycle continues to `reconcileVanishedDeploys`; this file holds no module-level state of its own (no queue, no singleton), so nothing internal to it can race across cycles.
- **intra-call-concurrency-bound**: Within one `enrichDeployErrors` call, up to `ENRICH_CONCURRENCY` (4) candidate rows' fetches MAY run concurrently via `mapLimit`, each against its own distinct row id and its own `AbortController`/timer pair, so no two concurrent fetches within one call can write to the same storage row or share a timeout.
- **thread-context**: This function runs on whichever thread its caller (`runCycle` in `sync.ts`, via `runMonitorCycle` in `cycle-runner.ts`) is executing on — the monitor's own worker thread for a scheduled cycle, or the API thread when `runMonitorCycle` is invoked from there — per `cycle-runner.ts`'s own doc comment describing `config` (and, by the same structural argument, the `storage`/`conn` handles) as threaded in from whichever caller owns that invocation; this file itself makes no thread-affinity assumption beyond running to completion on whichever thread called it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | required, caller-supplied | The storage port providing `storage.deploy.listFailedWithoutError` and `storage.deploy.setErrorText`; this file never constructs or configures a storage implementation itself. |
| `conn` (parameter) | `ProviderConn` | required, caller-supplied | Resolved provider connections (`@agentic-toolkit/deploy-platform/conn`), carrying `conn.vercel.token`/`conn.vercel.teamId` and `conn.railway.token`, used only to gate and authenticate the per-provider fetches this file dispatches to. |
| `ENRICH_WINDOW_DAYS` (module constant) | `number` | `14` | Recency window in days; only failed deploys created within this window are candidates. Not configurable per call and has no environment override in this file. |
| `ENRICH_MAX_PER_CYCLE` (module constant) | `number` | `8` | Maximum candidate rows queried and enriched per call. Not configurable per call. |
| `ENRICH_CONCURRENCY` (module constant) | `number` | `4` | Maximum concurrent in-flight fetches passed to `mapLimit`. Not configurable per call. |
| `ENRICH_CALL_TIMEOUT_MS` (module constant) | `number` | `8_000` | Per-row fetch deadline enforced via `AbortController`/`setTimeout`. Not configurable per call. |

