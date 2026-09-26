---
id: da18e58b-c2d9-4798-8143-2dd30b5976fc
title: Status Server Monitor Reconcile Stuck Deploys
domain: agentictoolkit://cookbook/status-server/monitor/reconcile-stuck-deploys
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Re-fetches Vercel/Railway deploys stuck in flight by id, terminalizing vanished
  ones and expiring any unconfirmed for 6+ hours.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- vercel
- railway
- rate-limiting
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related:
- agentictoolkit://cookbook/status-server/monitor/enrich-deploy-errors
- agentictoolkit://cookbook/status-server/monitor/deploy-status
- agentictoolkit://cookbook/status-server/monitor/provider-conn
references:
- packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/sync.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/cycle-runner.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/deploy-store.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/conn/index.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/util/map-limit.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/providers/railway.ts (agentictoolkit)
- packages/web/packages/status-server/test/reconcile-stuck-deploys.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Reconcile Stuck Deploys

## Overview

`reconcile-stuck-deploys.ts` (`packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts`) is the status backend's by-id healer for Vercel/Railway deploy rows that the recent-deploys poll can no longer terminalize. Its own header comment states the problem: the poll reads only a provider's newest ~100 deployments, so a deployment that leaves that window while still in flight would otherwise freeze at `building` forever — observed in production, where a 45-project rebuild left rows reading `building` roughly 15 minutes after every build was green. The module exports two independent operations, both invoked from `sync.ts`'s `runCycle`: `reconcileVanishedDeploys(storage, conn)`, which re-fetches a bounded, cooldown-aware, per-row-backed-off batch of stale in-flight candidates by id and persists their real phases (or terminalizes them as `canceled` when the provider reports the deployment gone), and `expireUnconfirmedDeploys(storage)`, a terminal backstop that collapses any in-flight lifecycle unconfirmed for `EXPIRE_UNCONFIRMED_MS` (6 hours) to `unknown`. Both delegate the actual phase-mapping and in-flight vocabulary to `deploy-status.ts` (see `agentictoolkit://cookbook/status-server/monitor/deploy-status`) and their provider connection resolution to `deploy-platform/conn` (see `agentictoolkit://cookbook/status-server/monitor/provider-conn`); this file owns only the candidate selection, per-row dispatch, backoff bookkeeping, and persistence around those two operations.

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
- **vercel-phases-delegated**: on a body with a `readyState`, `fetchVercelPhasesById` MUST return `vercelPhases(d.readyState, d.readySubstate, d.target)` unchanged — the phase-mapping contract owned by `agentictoolkit://cookbook/status-server/monitor/deploy-status`, not reimplemented here.
- **railway-detail-request**: `fetchRailwayPhasesById` MUST call `gqlPost(token, "query($id: String!) { deployment(id: $id) { status } }", signal, { id })`, passing the deployment id as a GraphQL variable rather than interpolating it into the query string.
- **railway-429-suppressed**: when the response status is 429, `fetchRailwayPhasesById` MUST return `null` without logging — `gqlPost` has already recorded the cooldown for that response.
- **railway-non-ok-logged-null**: for any other non-ok response, `fetchRailwayPhasesById` MUST log `` `[reconcile] Railway deployment ${id} detail ${res.status}` `` via `console.error` and return `null`.
- **railway-deployment-null-is-gone**: when the parsed body's `data` key is present and `data.deployment` is exactly `null` (the query succeeded and the provider reports no such deployment), `fetchRailwayPhasesById` MUST return `"gone"`.
- **railway-status-delegated**: when `data.deployment.status` is a present string, `fetchRailwayPhasesById` MUST return `railwayPhases(status)`; when `data` is absent (including a GraphQL `errors` response) or `data.deployment.status` is absent, it MUST return `null`.

### Per-Row Bounding

- **per-call-timeout**: for each candidate row, `reconcileVanishedDeploys` MUST create an `AbortController`, start a `setTimeout` that calls `controller.abort()` after `RECONCILE_CALL_TIMEOUT_MS` (8,000) milliseconds, pass `controller.signal` into `fetchPhasesFor`, and MUST clear that timer in a `finally` block regardless of whether the fetch settled, rejected, or was aborted.
- **bounded-concurrency**: `reconcileVanishedDeploys` MUST process candidate rows via `mapLimit` with a concurrency limit of `RECONCILE_CONCURRENCY` (4), so no more than 4 candidate rows are ever being fetched at the same instant within one call.

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

## Appearance

Not applicable — this is a server-side deploy reconciliation and expiry healer, not a visual component.

## States

Not applicable — this is a server-side deploy reconciliation and expiry healer, not a visual component; its runtime states (no pollable platform, empty candidate set, per-row pending/gone/fetched/parked, and the terminal `unknown` collapse) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side deploy reconciliation and expiry healer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-reconcile-stuck-deploys-001 | terminalize-on-gone, vercel-404-is-gone | Stale in-flight `vc_gone` row (`buildPhase: "building"`, `fetchedAt` older than `RECONCILE_STALE_MS`); Vercel by-id fetch resolves `{ readyState: "READY", readySubstate: "PROMOTED", target: "production" }` | Row's `buildPhase` becomes `"built"` and `deployPhase` becomes `"deployed"` via `markDeployPhases` |
| status-server-monitor-reconcile-stuck-deploys-002 | candidate-query-shape | A row with `fetchedAt` set to now (fresh, within `RECONCILE_STALE_MS`) | `fetch` is never called; the row's `buildPhase` stays `"building"` — the poll window still covers it |
| status-server-monitor-reconcile-stuck-deploys-003 | persist-fresh-phases, terminal-writes-bump-fetched-at | Stale `vc_slow` row; Vercel by-id fetch resolves `{ readyState: "BUILDING" }` | Row's `buildPhase` stays `"building"`; `fetchedAt` is bumped to a time later than `NOW - RECONCILE_STALE_MS` |
| status-server-monitor-reconcile-stuck-deploys-004 | vercel-non-ok-logged-null, park-on-no-phases | Stale `vc_err` row; Vercel by-id fetch responds `500` | Row's `buildPhase` stays `"building"`; `fetchedAt` is untouched (unix-second precision unchanged) |
| status-server-monitor-reconcile-stuck-deploys-005 | vercel-404-is-gone, terminalize-on-gone | Stale `vc_deleted` row; Vercel by-id fetch responds `404` | Row terminalizes to `buildPhase: "canceled"`, `deployPhase: "none"`; `fetchedAt` is bumped |
| status-server-monitor-reconcile-stuck-deploys-006 | railway-deployment-null-is-gone, terminalize-on-gone | Stale `ry_deleted` Railway row; GraphQL fetch resolves `{ data: { deployment: null } }` | Row terminalizes to `buildPhase: "canceled"`, `deployPhase: "none"` |
| status-server-monitor-reconcile-stuck-deploys-007 | terminalize-on-gone | Stale row with `buildPhase: "built"`, `deployPhase: "deploying"` (a rolling deploy); Vercel by-id fetch responds `404` | `buildPhase` stays `"built"` (settled verdict preserved); only `deployPhase` collapses to `"none"` |
| status-server-monitor-reconcile-stuck-deploys-008 | railway-status-delegated, park-on-no-phases | Stale `ry_err` Railway row; GraphQL fetch resolves `{ errors: [{ message: "rate limited" }] }` (no `data` key) | `fetchRailwayPhasesById` returns `null`; row's `buildPhase` stays `"building"` |
| status-server-monitor-reconcile-stuck-deploys-009 | railway-status-delegated, persist-fresh-phases | Stale `ry_gone` Railway row; GraphQL fetch resolves `{ data: { deployment: { status: "SUCCESS" } } }` | Row's `buildPhase` becomes `"built"`, `deployPhase` becomes `"deployed"` |
| status-server-monitor-reconcile-stuck-deploys-010 | candidate-query-shape | A row already terminal (`buildPhase: "built"`, `deployPhase: "deployed"`) | `fetch` is never called — `listInFlightCandidates`' in-flight predicate excludes it |
| status-server-monitor-reconcile-stuck-deploys-011 | park-on-no-phases, backoff-escalation | Stale `vc_perma` row; Vercel by-id fetch responds `403` on every call; `reconcileVanishedDeploys` is called twice in succession | `fetch` is called exactly once — the second call's row is excluded via `parkedIds` before any second fetch |
| status-server-monitor-reconcile-stuck-deploys-012 | parked-ids-excluded-in-query | A newer `vc_perma` row (fetch fails, 403) and an older `vc_older` row (fetch succeeds) in the same cycle | `vc_older` heals to `buildPhase: "built"` in the same pass; `vc_perma` stays `"building"`, parked for a later cycle |
| status-server-monitor-reconcile-stuck-deploys-013 | parked-ids-excluded-in-query, candidate-query-shape | 12 newer failing rows (exceeding the `RECONCILE_MAX_PER_CYCLE` cap of 10) plus one older healthy row, in one cycle; `reconcileVanishedDeploys` called twice | After pass 1 the older row is still `"building"` (crowded out by the cap); after pass 2 it heals to `"built"` (its parked siblings are now excluded from the cap) |
| status-server-monitor-reconcile-stuck-deploys-014 | pollable-platform-filter, candidate-query-shape | `conn` has both Vercel and Railway tokens; `noteRateLimited("vercel")` is called before `reconcileVanishedDeploys` runs against a stale Vercel row | `fetch` is never called — `"vercel"` is filtered out of `polled`, and the candidate query's `platforms` argument excludes it |
| status-server-monitor-reconcile-stuck-deploys-015 | vercel-429-suppressed, park-on-no-phases | Stale `vc_429` row; Vercel by-id fetch responds `429` | `rateLimitedUntil("vercel")` becomes non-null afterward; the row's `buildPhase` stays `"building"`, untouched |
| status-server-monitor-reconcile-stuck-deploys-016 | expire-collapses-stale-in-flight | An in-flight row with `fetchedAt` older than `EXPIRE_UNCONFIRMED_MS`; `await expireUnconfirmedDeploys(storage)` | Row's `buildPhase` becomes `"unknown"`; its untouched `deployPhase` (`"none"`, never in flight) is unaffected |
| status-server-monitor-reconcile-stuck-deploys-017 | expire-collapses-stale-in-flight | A row with `buildPhase: "built"`, `deployPhase: "deploying"`, `fetchedAt` older than `EXPIRE_UNCONFIRMED_MS` | `buildPhase` stays `"built"`; only `deployPhase` collapses to `"unknown"` |
| status-server-monitor-reconcile-stuck-deploys-018 | expiry-not-created-at-windowed | A row created 20 days ago (past `RECONCILE_WINDOW_DAYS`), `fetchedAt` older than `EXPIRE_UNCONFIRMED_MS` | Row still expires to `buildPhase: "unknown"` — age since creation does not exempt it |
| status-server-monitor-reconcile-stuck-deploys-019 | expire-collapses-stale-in-flight | One row with fresh `fetchedAt` (still being actively confirmed) and one terminal row (`built`/`deployed`) with a stale `fetchedAt`, both passed to `expireUnconfirmedDeploys` | The fresh row stays `"building"`; the terminal row stays `built`/`deployed` — neither is touched |
| status-server-monitor-reconcile-stuck-deploys-020 | expire-fail-soft | `storage.deploy.expireStaleInFlight` stubbed to reject with `new Error("db down")` | `expireUnconfirmedDeploys` resolves `undefined` (does not throw); exactly one `console.error` call is made whose first argument is `[reconcile] expiry sweep failed:` |

## Edge Cases

- **Null and empty input**: no pollable platform (`polled.length === 0`, from no token being configured or every configured provider currently rate-limited) MUST short-circuit `reconcileVanishedDeploys` before any backoff pruning, storage query, or fetch — MUST (no-pollable-platform-short-circuit). An empty candidate array from `listInFlightCandidates` MUST short-circuit before any fetch — MUST (empty-candidates-short-circuit). A row whose platform/token combination `fetchPhasesFor` doesn't recognize MUST resolve `null` silently with no fetch — MUST (platform-dispatch-fallback-null).
- **Boundary values**: exactly `RECONCILE_MAX_PER_CYCLE` (10) rows are ever queried or fetched by `reconcileVanishedDeploys` in one call, even when more qualify — MUST. The candidate window's `createdAfterMs` boundary is strictly greater-than (per `listInFlightCandidates`'s `gt(deployments.createdAt, ...)`), so a row created at exactly 14 days ago is excluded from candidacy — MUST. The staleness boundary is strictly less-than (`lt(deployments.fetchedAt, ...)`), so a row fetched at exactly `RECONCILE_STALE_MS` ago is not yet a candidate — MUST. `EXPIRE_UNCONFIRMED_MS` (6 hours) is chosen, per the source's own comment, to be well past both a legitimate build duration and many reconcile/poll retry attempts, so it fires only after confirmation has failed persistently — this is a stated design threshold, not a value this file validates against, so it is recorded as a fact rather than a computed guarantee.
- **Concurrent access**: within one `reconcileVanishedDeploys` call, `mapLimit` bounds concurrent candidate processing to 4 in flight at once, each against a distinct row id, so two concurrent fetches within one call can never target the same storage row — MUST (bounded-concurrency, intra-call-concurrency-bound). `retryAfterFailure` is worker-thread-local module state (per its own doc comment), so it is not shared across the worker thread and the API thread the way the provider cooldown deliberately is; whether two overlapping cycle invocations (a fast tick and a full cycle, or two threads) could select and fetch the same row concurrently is a property of the caller's own scheduling, external to this file — `markDeployPhases` overwrites both lifecycle columns unconditionally on each write (persist-fresh-phases), so two such concurrent, independently-fetched writes to the same row would both apply fresh authoritative provider truth in whichever order they land, with the later write's phases winning; this file states that as its ordering rule rather than leaving it unstated.
- **Error states**: a `listInFlightCandidates` rejection is caught, logged, and the whole `reconcileVanishedDeploys` call returns without fetching anything — MUST (candidate-query-failure-fail-soft). A per-row `fetchPhasesFor`/`markDeployGone`/`markDeployPhases` rejection is caught and logged inside that row's own `mapLimit` callback, parking the row for later retry without affecting sibling rows or the overall call's resolution — MUST (park-on-throw). An `expireStaleInFlight` rejection is caught, logged, and `expireUnconfirmedDeploys` resolves normally — MUST (expire-fail-soft). A transient provider failure (a non-404/429 non-ok Vercel response, a non-2xx-with-no-`data` Railway GraphQL response, or a rejected `fetch`) is treated identically — parked via the same backoff, never distinguished from a "row still building" outcome except by the escalating retry delay — MUST.
- **Offline/disconnected state**: this file holds no persistent connection of its own to lose; its analogue is a provider being unreachable for the full `RECONCILE_CALL_TIMEOUT_MS` (8,000ms) window on a per-row fetch, which manifests as the `AbortController` firing and the resulting abort rejection being caught exactly like any other per-row failure (park-on-throw) — MUST. A provider whose outage lasts across many cycles has its affected rows' backoff escalate up to `RECONCILE_BACKOFF_MAX_MS` (5 minutes) rather than being retried at a fixed cadence — MUST (backoff-escalation).

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

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own; both exported functions only read candidate rows from `storage` and write back to it — there is no inbound URL to handle and no outbound deep link constructed.

## Localization

Not applicable: this file authors no user-facing string of its own. Its `console.log`/`console.error` calls (`[reconcile] vanished-deploy query failed:`, `[reconcile] Vercel deployment ${uid} detail ${res.status}`, `[reconcile] Railway deployment ${id} detail ${res.status}`, `[reconcile] ${row.id} gone at provider → canceling in-flight lifecycle(s)`, `[reconcile] ${row.id} phase fetch/store failed:`, `[reconcile] ${n} in-flight deploy row(s) unconfirmable for 6h+ → unknown`, `[reconcile] expiry sweep failed:`) are operator-facing diagnostic log lines, not text shown in any UI, so they carry no localization concern here.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind; `reconcileVanishedDeploys` and `expireUnconfirmedDeploys` are invoked unconditionally from `sync.ts`'s `runCycle` (on every tick and every full cycle respectively), with the cooldown/token/backoff gating already documented under Behavioral Requirements as their only on/off levers.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: this file receives `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` as opaque values (sourced by callers external to this file — `providerConnFromConfig`/`connFromEnv` in `deploy-platform/conn`) and, unlike a pass-through consumer, uses the token values itself to build the outbound `Authorization: Bearer` header (`fetchVercelPhasesById`) and the `gqlPost` call (`fetchRailwayPhasesById`). It also reads and persists each provider's own reported build/deploy phase via `storage.deploy.markDeployPhases`/`markDeployGone` — enumerated phase values only, never free-form provider text.
- **Storage**: the provider tokens are held only as in-memory `conn` fields for the duration of one `reconcileVanishedDeploys` call; this file never writes a token to storage. Token lifetime, storage, and revocation are entirely the concern of the `conn` resolution this file is handed (`deploy-platform/conn`, external to this file) — this file has no lifetime, storage, or revocation logic of its own to specify beyond "never persisted."
- **Transmission**: `conn.vercel.token` is transmitted over HTTPS as a Bearer credential to `api.vercel.com`; `conn.railway.token` is transmitted over HTTPS as a Bearer credential inside `gqlPost`'s GraphQL request to Railway's API. Neither token is ever logged by this file — every `console.error`/`console.log` call here logs only a deployment id, a platform name, an HTTP status, or a row count.
- **Retention**: not applicable to this file directly; the `buildPhase`/`deployPhase` values it persists are retained for as long as the `deployments` row exists, governed by `storage.deploy.pruneOlderThanDays(90)`, called elsewhere in `sync.ts` and external to this file.

## Logging

This file uses plain `console.log`/`console.error` calls, each with a literal `[reconcile]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| `listInFlightCandidates` rejects | error (`console.error`) | `[reconcile] vanished-deploy query failed:` (caught error as the second argument) |
| Vercel by-id detail fetch returns non-ok, non-404, non-429 | error (`console.error`) | `` `[reconcile] Vercel deployment ${uid} detail ${res.status}` `` |
| Railway by-id detail fetch returns non-ok, non-429 | error (`console.error`) | `` `[reconcile] Railway deployment ${id} detail ${res.status}` `` |
| A row's provider fetch resolves `"gone"` | info (`console.log`) | `` `[reconcile] ${row.id} gone at provider → canceling in-flight lifecycle(s)` `` |
| A row's fetch or store call rejects | error (`console.error`) | `` `[reconcile] ${row.id} phase fetch/store failed:` `` (caught error as the second argument) |
| `expireStaleInFlight` collapses one or more rows | info (`console.log`) | `` `[reconcile] ${n} in-flight deploy row(s) unconfirmable for 6h+ → unknown` `` |
| `expireStaleInFlight` rejects | error (`console.error`) | `[reconcile] expiry sweep failed:` (caught error as the second argument) |

No log line is emitted on a successful phase heal, an empty candidate set, a no-pollable-platform short circuit, or an expiry sweep that collapses zero rows — silence is the expected steady state.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple-side status monitor port would model `reconcileVanishedDeploys` as an `async` function isolated to an actor that owns the monitor cycle, using `URLSession` for the Vercel detail GET and the Railway GraphQL POST (the Swift equivalents of `fetchVercelPhasesById`/`fetchRailwayPhasesById`), a `withThrowingTaskGroup` capped at 4 concurrently-running child tasks as the `mapLimit` analogue, each child task racing its fetch against a `Task.sleep(for: .seconds(8))` (or `URLRequest.timeoutInterval = 8`) as the `AbortController`/8,000ms deadline analogue, and the per-row backoff registry as a plain `[String: Backoff]` dictionary owned by that same actor (so it is naturally isolated the way `retryAfterFailure`'s worker-thread locality is here). `expireUnconfirmedDeploys` ports as a second `async` function on the same actor issuing one bulk update.
- **Compose**: a Kotlin port models `reconcileVanishedDeploys` as a `suspend fun` using a `kotlinx.coroutines.sync.Semaphore(4)` (or a bounded dispatcher) as the direct substitute for `mapLimit`, `withTimeout(8_000)` for the per-row deadline, and the backoff registry as a `ConcurrentHashMap` (or a plain `HashMap` if confined to one coroutine dispatcher, mirroring this file's single-thread-per-call locality) guarded the same way `retryAfterFailure` is here — recreated fresh per process, never persisted.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts` as two plain exported `async` functions on the Node status backend — not client-side React, and no framework dependency beyond the `Storage` port and the shared `@agentic-toolkit/deploy-platform` cooldown/util/conn modules it imports. `reconcileVanishedDeploys` is invoked both on the fast probe-only tick and, together with `expireUnconfirmedDeploys`, on every full sync cycle, all from `sync.ts`'s `runCycle`, itself invoked from `runMonitorCycle` in `cycle-runner.ts`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; a macOS/iOS agent embedding this healer pattern has no UIKit/AppKit-specific concern, since this is a background sync task rather than a view-driven one — the actor + `URLSession` + `TaskGroup` shape described under SwiftUI applies unchanged.
- **WinUI 3**: model the candidate row as a `readonly record struct(string Id, string Platform)` (the `DeployIdPlatformRow` analogue) and the per-row backoff entry as `readonly record struct(DateTimeOffset Until, int Fails)`, kept in a plain `Dictionary<string, Backoff>` field on whatever singleton/hosted service owns the monitor cycle (the direct analogue of module-scope `retryAfterFailure` — .NET has no bare module scope, so a hosted-service-owned field is the closest structural match). Implement the candidate query as `async Task<IReadOnlyList<DeployIdPlatformRow>> ListInFlightCandidatesAsync(...)` over EF Core or Dapper mirroring `listInFlightCandidates`'s predicate (in-flight `build_phase`/`deploy_phase`, `CreatedAt >` cutoff, `FetchedAt <` cutoff, id `NOT IN` the parked set, ordered newest-first, `Take(10)`), and the per-row dispatch as a `switch` expression on `row.Platform` calling `HttpClient.GetAsync` for the Vercel detail endpoint (deserializing with `System.Text.Json`) or a `HttpClient.PostAsJsonAsync` GraphQL call for Railway. Give each call a `CancellationTokenSource(TimeSpan.FromSeconds(8))` — composed with any caller-supplied token via `CancellationTokenSource.CreateLinkedTokenSource` — as the `AbortController`/`AbortSignal.timeout` analogue, and cap concurrency with `Parallel.ForEachAsync(candidates, new ParallelOptions { MaxDegreeOfParallelism = 4 }, ...)` in place of `mapLimit`. Compute the exponential backoff with `TimeSpan.FromMilliseconds(Math.Min(60_000 * Math.Pow(2, fails - 1), 300_000))`, and implement `ExpireUnconfirmedDeploysAsync` as a single `UPDATE`-equivalent EF Core `ExecuteUpdateAsync` call mirroring `expireStaleInFlight`'s per-lifecycle `CASE`. Log through `ILogger<T>` with the same `[reconcile]`-prefixed message shapes in place of `console.log`/`console.error`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts` |

## Design Decisions

- **Decision**: run `reconcileVanishedDeploys` on both the fast probe-only tick and the full sync cycle, while `expireUnconfirmedDeploys` and `enrichDeployErrors` run only on the full cycle.
  **Rationale**: stated directly in the source's own header comment and echoed in `sync.ts`'s comment on the `opts.skipDeploys` branch — the deploy poll only terminalizes a finished build at its 5-minute cadence, so a burst of deploys leaving the poll's recent-deployments window read as `building` for up to that whole interval; running this specific, cheap, indexed-candidate-query healer at the probe cadence (RECONCILE_STALE_MS is deliberately shorter than the poll interval) closes that gap without paying the cost of the full provider poll on every tick.
  **Approved**: pending
- **Decision**: make `RECONCILE_STALE_MS` (2 minutes) shorter than the deploy poll's default interval (5 minutes) rather than longer.
  **Rationale**: stated directly in the source comment on `RECONCILE_STALE_MS` — gating the healer at longer than the poll interval made the poll the only thing that could terminalize a finished build, so any row the poll missed read `building` for the poll gap plus the threshold (observed as roughly 15 minutes after a 45-project rebuild); shorter than the poll means the fast tick re-confirms in-flight rows between polls instead of trusting a phase nothing has checked.
  **Approved**: pending
- **Decision**: exclude parked (backed-off) row ids in the `listInFlightCandidates` SQL `WHERE` clause rather than querying unfiltered and filtering in JavaScript after the fact.
  **Rationale**: stated directly in the source comment on `parkedIds` — a JS filter applied after a newest-first `LIMIT` let a cluster of permanently-failing rows fill the whole batch and starve older stale rows, requiring an over-select fudge factor that still broke down past roughly cap-times-factor parked rows; excluding parked ids in the `WHERE` clause means the `LIMIT` always returns that many retryable rows, however many are currently parked.
  **Approved**: pending
- **Decision**: use exponential backoff (`RECONCILE_BACKOFF_BASE_MS` doubling per consecutive failure, capped at `RECONCILE_BACKOFF_MAX_MS`) for a failing row rather than a flat retry delay.
  **Rationale**: stated directly in the source comment on the backoff constants — a flat delay forces one bad tradeoff: short enough to retry a transient blip promptly means a permanently-failing row keeps burning provider quota at that same cadence forever, while long enough to rate-limit a permanent failure means a row with one transient blip waits the full delay before its next real check; escalating from a short base lets a transient failure retry soon while a persistently-failing row backs off toward the cap.
  **Approved**: pending
- **Decision**: remember a lapsed backoff's escalation count for `RECONCILE_BACKOFF_MEMORY_MS` (10 minutes) past its expiry rather than resetting to the base delay on every failure.
  **Rationale**: stated directly in the source comment on `RECONCILE_BACKOFF_MEMORY_MS` — a row that fails again shortly after being retried should resume escalating rather than restarting at the base delay every time; past the memory window the entry is pruned and the next failure starts fresh.
  **Approved**: pending
- **Decision**: `expireUnconfirmedDeploys`'s `expireStaleInFlight` predicate is windowed only by `fetchedAt`, deliberately not also by `createdAt`/`RECONCILE_WINDOW_DAYS`.
  **Rationale**: stated directly in the source comment on `expireUnconfirmedDeploys` — rows older than the reconcile window are exactly the zombies this operation exists to clear, since they can no longer be re-fetched by id at all; windowing by `createdAt` would exempt the very rows most in need of a terminal verdict.
  **Approved**: pending
- **Decision**: `markDeployGone` and `expireStaleInFlight` collapse only the currently-in-flight lifecycle column(s) via a per-column `CASE`, evaluated against each row's current stored state, rather than overwriting both `buildPhase` and `deployPhase` unconditionally.
  **Rationale**: stated directly in the source comments on both call sites — a blanket overwrite would erase a settled verdict on one lifecycle (e.g., a finished `built` build) when only the sibling lifecycle (its `deploying` rollout) is the one that vanished or expired; the per-column `CASE` also makes the update race-safe against a concurrent write between the candidate select and the update itself, since it re-checks the row's current state at write time rather than trusting a stale in-memory snapshot.
  **Approved**: pending
- **Decision**: pass the Railway deployment id to `gqlPost` as a bound GraphQL variable (`{ id }`) rather than interpolating it into the query string.
  **Rationale**: not spelled out on this call site directly, but stated on `gqlPost`'s own declaration in `providers/railway.ts` (cited here as external evidence, not invented) — a bound variable is the shared choke point every by-id GraphQL caller in the codebase goes through so no caller can drift into building an injectable, string-interpolated query.
  **Approved**: pending
- **Decision**: keep `retryAfterFailure` as unpersisted, worker-thread-local module state rather than backing it with the shared cross-thread `SharedArrayBuffer` the provider cooldown module uses.
  **Rationale**: stated directly in the source comment on the `retryAfterFailure` declaration — a process restart simply retries a parked row sooner, which is an acceptable cost, and the registry is bounded by the number of in-flight rows a cycle can even see; unlike the provider-level cooldown (which two different threads must observe identically to avoid both independently exhausting the same rate limit), a per-row backoff miss on a restart or thread boundary only means one extra fetch attempt, not a repeated throttle violation.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | passed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `reconcile-stuck-deploys.test.ts` calls `reconcileVanishedDeploys` and `expireUnconfirmedDeploys` directly, against a real migrated in-memory libSQL database, exercising the healthy-heal, gone/404, GraphQL-null-gone, per-lifecycle-preservation, transient-failure, rate-limit, backoff-parking, head-of-line, and expiry paths — the module's own exported surface is under test, not only its downstream helpers. `separation-of-concerns` passes: this file owns exactly one concern — selecting stale/expired in-flight candidates and dispatching/persisting their resolved phases — delegating the phase-mapping vocabulary to `deploy-status.ts`, the cooldown check to `deploy-platform/cooldown`, the bounded fan-out to `deploy-platform/util`'s `mapLimit`, the Railway GraphQL transport to `providers/railway.ts`'s `gqlPost`, and every storage read/write to the `Storage` port, never touching a database directly. `explicit-error-handling` passes: every failure path this file can hit — the candidate query rejecting, a per-row fetch or store rejecting, and the expiry sweep rejecting — is caught explicitly and logged with a distinguishing `[reconcile]`-prefixed message; nothing is silently swallowed without a signal. `timeout-configuration` passes: every per-row by-id fetch carries an explicit 8,000ms deadline via `AbortController`/`setTimeout`, cleared in a `finally`. `retry-with-backoff` passes: a failing row is parked under a genuine exponential backoff (`RECONCILE_BACKOFF_BASE_MS` doubling per consecutive failure up to `RECONCILE_BACKOFF_MAX_MS`, with a memory window that lets escalation resume rather than reset), not merely a fixed per-cycle retry. `rate-limit-handling` passes: the shared cooldown (`rateLimitedUntil`) is consulted before the candidate query is built, and a 429 response is fed back into that same shared cooldown via `noteIfRateLimited`, so a throttled provider's rows wait for a later cycle instead of spending requests that would extend the throttle. `idempotent-operations` passes: `markDeployPhases` and `markDeployGone` both write via a deterministic mapping of provider truth to phase columns, and re-running either against an already-settled row (or `expireStaleInFlight` against an already-`unknown` row) is a no-op by construction — the in-flight predicate that gates candidacy excludes rows the write already terminalized. `graceful-degradation` passes: no pollable platform, an empty candidate set, a query failure, a per-row fetch/store failure, and an expiry-sweep failure all degrade to a skip/no-op for the affected scope rather than throwing, matching the module's own "best-effort and fail-soft" framing echoed in `sync.ts`'s comments at both call sites.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
