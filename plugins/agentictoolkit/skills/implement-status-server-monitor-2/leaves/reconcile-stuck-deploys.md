<!-- leaf: implement-status-server-monitor-2/reconcile-stuck-deploys · source: status-server-monitor-reconcile-stuck-deploys.md -->

**Rules** (cite as `implement-status-server-monitor-2/reconcile-stuck-deploys#<slug>`):

- `reconcile-vanished-deploys-signature` MUST
- `expire-unconfirmed-deploys-signature` MUST
- `reconcile-never-throws` MUST
- `expire-never-throws` MUST
- `runs-after-upsert-on-full-cycle` MUST
- `runs-standalone-on-fast-tick` MUST
- `pollable-platform-filter` MUST
- `no-pollable-platform-short-circuit` MUST
- `backoff-prune-before-query` MUST
- `parked-ids-excluded-in-query` MUST
- `candidate-query-shape` MUST
- `candidate-query-failure-fail-soft` MUST
- `empty-candidates-short-circuit` MUST
- `id-platform-row-shape` MUST
- `platform-dispatch-vercel` MUST
- `platform-dispatch-railway` MUST
- `platform-dispatch-fallback-null` MUST
- `vercel-detail-request` MUST
- `vercel-404-is-gone` MUST
- `vercel-429-suppressed` MUST
- `vercel-non-ok-logged-null` MUST
- `vercel-missing-ready-state-null` MUST
- `vercel-phases-delegated` MUST
- `railway-detail-request` MUST
- `railway-429-suppressed` MUST
- `railway-non-ok-logged-null` MUST
- `railway-deployment-null-is-gone` MUST
- `railway-status-delegated` MUST
- `per-call-timeout` MUST
- `bounded-concurrency` MUST

# Status Server Monitor Reconcile Stuck Deploys

## Overview

`reconcile-stuck-deploys.ts` (`packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts`) is the status backend's by-id healer for Vercel/Railway deploy rows that the recent-deploys poll can no longer terminalize. Its own header comment states the problem: the poll reads only a provider's newest ~100 deployments, so a deployment that leaves that window while still in flight would otherwise freeze at `building` forever — observed in production, where a 45-project rebuild left rows reading `building` roughly 15 minutes after every build was green. The module exports two independent operations, both invoked from `sync.ts`'s `runCycle`: `reconcileVanishedDeploys(storage, conn)`, which re-fetches a bounded, cooldown-aware, per-row-backed-off batch of stale in-flight candidates by id and persists their real phases (or terminalizes them as `canceled` when the provider reports the deployment gone), and `expireUnconfirmedDeploys(storage)`, a terminal backstop that collapses any in-flight lifecycle unconfirmed for `EXPIRE_UNCONFIRMED_MS` (6 hours) to `unknown`. Both delegate the actual phase-mapping and in-flight vocabulary to `deploy-status.ts` (see `agentictoolkit://recipes/status-server-monitor-deploy-status`) and their provider connection resolution to `deploy-platform/conn` (see `agentictoolkit://recipes/status-server-monitor-provider-conn`); this file owns only the candidate selection, per-row dispatch, backoff bookkeeping, and persistence around those two operations.

## Behavioral Requirements

### Public Operations

- **reconcile-vanished-deploys-signature**: `reconcileVanishedDeploys` MUST accept exactly two parameters — `storage: Storage` and `conn: ProviderConn` — and MUST return `Promise<void>`.
- **expire-unconfirmed-deploys-signature**: `expireUnconfirmedDeploys` MUST accept exactly one parameter — `storage: Storage` — and MUST return `Promise<void>`.
- **reconcile-never-throws**: `reconcileVanishedDeploys`'s returned promise MUST NOT reject on any traced failure path (a candidate-query rejection, a per-row fetch/store rejection, or a per-call timeout) — every one of those is caught internally and logged, never re-thrown.
- **expire-never-throws**: `expireUnconfirmedDeploys`'s returned promise MUST NOT reject when `storage.deploy.expireStaleInFlight` rejects — the rejection is caught internally and logged, never re-thrown.
- **runs-after-upsert-on-full-cycle**: per `sync.ts`'s own call order, on a full sync cycle `reconcileVanishedDeploys` MUST be invoked with the cycle's freshly resolved `conn` only after `storage.deploy.upsertDeployments`, `storage.deploy.learnProjectIds`, and `enrichDeployErrors` have run, and `expireUnconfirmedDeploys` MUST be invoked immediately after that `reconcileVanishedDeploys` call, before `storage.deploy.pruneOlderThanDays`.
- **runs-standalone-on-fast-tick**: on a probe-only tick (`runCycle`'s `opts.skipDeploys` set), `sync.ts` MUST invoke only `reconcileVanishedDeploys(storage, await providerConn(storage, config))` from this module — neither `expireUnconfirmedDeploys` nor `enrichDeployErrors` runs on that tick — before returning early without polling any provider or upserting any deploy.

### Candidate Selection (`reconcileVanishedDeploys`)

- **pollable-platform-filter**: `reconcileVanishedDeploys` MUST compute its candidate platform list (`polled`) as `pollableByIdPlatforms(conn)` filtered to exclude every provider for which `rateLimitedUntil(provider)` returns non-null.
- **no-pollable-platform-short-circuit**: when `polled` is empty, `reconcileVanishedDeploys` MUST return immediately — without pruning `retryAfterFailure`, without calling `storage.deploy.listInFlightCandidates`, and without any provider fetch.
- **backoff-prune-before-query**: before computing parked ids, `reconcileVanishedDeploys` MUST delete every `retryAfterFailure` entry whose `until + RECONCILE_BACKOFF_MEMORY_MS` (600,000ms) is less than or equal to the current time.
- **parked-ids-excluded-in-query**: `reconcileVanishedDeploys` MUST compute `parkedIds` as every remaining `retryAfterFailure` entry whose `until` is still greater than the current time, and MUST pass those ids as `excludeIds` to `storage.deploy.listInFlightCandidates` so a parked row is excluded by the query's own `WHERE` clause rather than filtered out of an already-limited result afterward.
- **candidate-query-shape**: `reconcileVanishedDeploys` MUST call `storage.deploy.listInFlightCandidates` with `platforms` set to `polled`, `excludeIds` set to `parkedIds`, `createdAfterMs` set to the current time minus `RECONCILE_WINDOW_DAYS` (14) days in milliseconds, `fetchedBeforeMs` set to the current time minus `RECONCILE_STALE_MS` (120,000), and `limit` set to `RECONCILE_MAX_PER_CYCLE` (10).
- **candidate-query-failure-fail-soft**: when `storage.deploy.listInFlightCandidates` rejects, `reconcileVanishedDeploys` MUST catch the rejection, log it via `console.error` with `[reconcile] vanished-deploy query failed:` as the first argument and the caught error as the second, and return without calling `mapLimit` or performing any provider fetch.
- **empty-candidates-short-circuit**: when `listInFlightCandidates` resolves an empty array, `reconcileVanishedDeploys` MUST return without calling `mapLimit` or performing any provider fetch.

### Provider Dispatch (`fetchPhasesFor`)

- **id-platform-row-shape**: a candidate value, as returned by `storage.deploy.listInFlightCandidates`, MUST carry exactly two fields — `id: string` and `platform: string` — per its `DeployIdPlatformRow` declaration in `storage/ports.ts`.
- **platform-dispatch-vercel**: `fetchPhasesFor` MUST call `fetchVercelPhasesById` when `row.platform === "vercel"` and `conn.vercel.token` is set, passing `row.id` with a leading `vc_` prefix stripped, `conn`, and the per-call `AbortSignal`.
- **platform-dispatch-railway**: `fetchPhasesFor` MUST call `fetchRailwayPhasesById` when `row.platform === "railway"` and `conn.railway.token` is set, passing `row.id` with a leading `ry_` prefix stripped, `conn.railway.token`, and the per-call `AbortSignal`.
- **platform-dispatch-fallback-null**: for a row whose platform/token combination matches neither branch, `fetchPhasesFor` MUST resolve `null` without making any network call.
- **vercel-detail-request**: `fetchVercelPhasesById` MUST issue a GET to `https://api.vercel.com/v13/deployments/{uid}` (with `uid` URL-encoded) carrying header `Authorization: Bearer {conn.vercel.token}` and the per-call `AbortSignal`, and MUST append a `teamId` query parameter equal to `conn.vercel.teamId` when that value is set.
- **vercel-404-is-gone**: `fetchVercelPhasesById` MUST return the literal string `"gone"` when the response status is 404 — a permanent provider answer that the deployment no longer exists, distinct from a transient failure.
- **vercel-429-suppressed**: when `noteIfRateLimited("vercel", res)` returns true (a 429 response, already recorded into the shared cooldown by that call), `fetchVercelPhasesById` MUST return `null` without any further processing of the response.
- **vercel-non-ok-logged-null**: for any other non-ok response, `fetchVercelPhasesById` MUST log `` `[reconcile] Vercel deployment ${uid} detail ${res.status}` `` via `console.error` and return `null`.
- **vercel-missing-ready-state-null**: when the parsed JSON body has no `readyState`, `fetchVercelPhasesById` MUST return `null`.
- **vercel-phases-delegated**: on a body with a `readyState`, `fetchVercelPhasesById` MUST return `vercelPhases(d.readyState, d.readySubstate, d.target)` unchanged — the phase-mapping contract owned by `agentictoolkit://recipes/status-server-monitor-deploy-status`, not reimplemented here.
- **railway-detail-request**: `fetchRailwayPhasesById` MUST call `gqlPost(token, "query($id: String!) { deployment(id: $id) { status } }", signal, { id })`, passing the deployment id as a GraphQL variable rather than interpolating it into the query string.
- **railway-429-suppressed**: when the response status is 429, `fetchRailwayPhasesById` MUST return `null` without logging — `gqlPost` has already recorded the cooldown for that response.
- **railway-non-ok-logged-null**: for any other non-ok response, `fetchRailwayPhasesById` MUST log `` `[reconcile] Railway deployment ${id} detail ${res.status}` `` via `console.error` and return `null`.
- **railway-deployment-null-is-gone**: when the parsed body's `data` key is present and `data.deployment` is exactly `null` (the query succeeded and the provider reports no such deployment), `fetchRailwayPhasesById` MUST return `"gone"`.
- **railway-status-delegated**: when `data.deployment.status` is a present string, `fetchRailwayPhasesById` MUST return `railwayPhases(status)`; when `data` is absent (including a GraphQL `errors` response) or `data.deployment.status` is absent, it MUST return `null`.

### Per-Row Bounding

- **per-call-timeout**: for each candidate row, `reconcileVanishedDeploys` MUST create an `AbortController`, start a `setTimeout` that calls `controller.abort()` after `RECONCILE_CALL_TIMEOUT_MS` (8,000) milliseconds, pass `controller.signal` into `fetchPhasesFor`, and MUST clear that timer in a `finally` block regardless of whether the fetch settled, rejected, or was aborted.
- **bounded-concurrency**: `reconcileVanishedDeploys` MUST process candidate rows via `mapLimit` with a concurrency limit of `RECONCILE_CONCURRENCY` (4), so no more than 4 candidate rows are ever being fetched at the same instant within one call.

