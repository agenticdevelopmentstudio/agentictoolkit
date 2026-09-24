---
id: 21455a0c-b7b3-4121-8726-c6918d7af5a8
title: Status Server Monitor Sync
domain: agentictoolkit://recipes/status-server-monitor-sync
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The periodic monitor cycle — probes active endpoints, polls each deploy
  provider under a fail-soft timeout guard, upserts deploys, and deletes the one
  class of config allowed to auto-delete itself (a monitor for something gone).
platforms:
- web
tags:
- monitor
- deploy
- sync
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/observability/logging
- agenticdevelopercookbook://guidelines/implementing/code-quality/dependency-injection
related:
- agentictoolkit://recipes/status-server-monitor-cycle-runner
- agentictoolkit://recipes/status-server-monitor-alerts
- agentictoolkit://recipes/status-server-monitor-provider-conn
- agentictoolkit://recipes/status-server-monitor-enrich-deploy-errors
- agentictoolkit://recipes/status-server-monitor-reconcile-stuck-deploys
- agentictoolkit://recipes/status-server-board
- agentictoolkit://recipes/status-server-monitor-issues
references:
- packages/web/packages/status-server/src/monitor/sync.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/probe.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/ownership.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/reconcile.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-conn.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/url.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/alerts.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/refresh-project-meta.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/reconcile-stuck-deploys.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/enrich-deploy-errors.ts (agentictoolkit)
- packages/web/packages/status-server/src/config/port.ts (agentictoolkit)
- packages/web/packages/status-server/src/deploy-platform/src/engine/run.ts (agentictoolkit)
- packages/web/packages/status-server/src/deploy-platform/src/canon/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/status-server/test/sync.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/sync-guard.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/retire-unclaimed-monitors.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Sync

## Overview

`sync.ts` (`packages/web/packages/status-server/src/monitor/sync.ts`) is the periodic monitoring cycle itself — the body the pre-redesign cron and the live route used to split between them, now one function. It exports `runCycle(storage: Storage, config: StatusConfig, opts?: { skipDeploys?: boolean }): Promise<void>`, the full sweep: probe every active endpoint, persist the checks, roll up hourly metrics, poll each configured deploy provider, upsert the fetched deploys, stamp their live hosts from the explicit endpoint wiring, delete any monitor the platform inventory no longer accounts for, and fold every fact into the board's ledger. It also exports `guard<T extends { ok: boolean }>(label, provider, fallback, fn): Promise<T>`, the wrapper every provider poll in this file crosses: a rate-limited, thrown, or overrunning poll degrades to `fallback` instead of aborting or wedging the cycle. Three helpers are private to the module: `retireMonitors` (deletes a doomed set of endpoints, alerting and logging each one, swallowing per-endpoint failures), `retireUnclaimedMonitors` (the ONE automatic-deletion rule's caller — delegates the verdict to `endpointsClaimedByNothing` from `@agentic-toolkit/deploy-platform`, then applies the healthy-probe veto this file alone knows about), and `stampLiveHosts` (reconciles each stored deploy row's `live_host` against the roster). `cfg(conn)` is a small private mapper from a `ProviderConn` to four booleans (which providers have a token). Two module-level constants define the fail-soft fallback shapes: `EMPTY_DEPLOYS = { ok: false, deploys: [] }` and `EMPTY_PROJECTS: VercelProjectsResult = { ok: false, states: [], meta: [], deploys: [] }`. `PROVIDER_POLL_TIMEOUT_MS = 20_000` is the hard cap `guard` races every poll against. The retention prune for `health_checks`/`metrics_hourly` lives outside this file, in the libSQL `MaintenanceStore` (`storage.maintenance.runMaintenance`); this file's own `pruneOlderThanDays(90)` call is scoped only to the `deployments` table.

## Behavioral Requirements

### Provider Poll Guard (`guard`)

- **rate-limited-provider-skip**: When `guard` is called with a non-null `provider` and `rateLimitedUntil(provider)` returns a non-null timestamp, `guard` MUST return `fallback` immediately without ever calling `fn()`, and MUST log `[sync] ${label} is rate-limited — skipping until ${new Date(until).toISOString()}` via `console.error`.
- **poll-timeout-cap**: `guard` MUST race `fn()` against a `setTimeout` of exactly `PROVIDER_POLL_TIMEOUT_MS` (20,000ms) via `Promise.race`; if the timer fires first, it MUST resolve to `fallback` and log `[sync] ${label} poll exceeded 20000ms — treating as unreachable` via `console.error`. The abandoned `fn()` call keeps running to its own deadline — `guard` never cancels it.
- **poll-throw-degrades**: If `fn()` rejects before the timeout fires, `guard` MUST catch the rejection, log `[sync] ${label} poll threw — treating as unreachable:` (with the error) via `console.error`, and resolve to `fallback`.
- **poll-passthrough**: If `fn()` resolves before the timeout fires, `guard` MUST resolve with exactly that resolved value (the same object reference), untransformed.
- **timer-always-cleared**: `guard` MUST call `clearTimeout` on its internal timer in a `finally` block, on every exit path (rate-limited return, timeout, throw, or pass-through).

### Cycle Composition (`runCycle`)

- **structural-prune-first**: `runCycle` MUST call `storage.config.reconcileOrphanedEndpoints()` and MUST await its result before calling `storage.config.listActiveEndpoints()`.
- **resolve-unmonitored-on-prune**: When the structural prune's `prunedEndpointIds.length > 0`, `runCycle` MUST call `storage.issues.resolveUnmonitoredTargets(pruned.prunedEndpointIds)` with exactly those ids, before reading the active endpoint list.
- **probe-skipped-on-empty**: When `listActiveEndpoints()` resolves to an empty array, `runCycle` MUST NOT call `probeEndpoints`, `storage.health.recordChecks`, or `storage.maintenance.rollupMetrics` for that cycle.
- **still-serving-from-this-cycle-only**: The `stillServing` set MUST be computed as the `slug`s of this cycle's own `probeEndpoints` results whose `status === "healthy"`; it MUST NOT include any endpoint that was not probed this cycle (in particular, it is the empty set for the whole cycle when `endpoints.length === 0`).
- **skip-deploys-early-return**: When `opts?.skipDeploys` is `true`, `runCycle` MUST call `reconcileVanishedDeploys(storage, await providerConn(storage, config))`, then `reconcileBoardLedger(storage, config, { skipOnEmptyRoster: true })`, and then return — it MUST NOT call any of the four deploy-provider fetchers, `storage.deploy.upsertDeployments`, `enrichDeployErrors`, `expireUnconfirmedDeploys`, `pruneOlderThanDays`, `stampLiveHosts`, `syncVercelProjectMeta`, `enumerateDeployProjects`, or `retireUnclaimedMonitors` on that call.
- **provider-poll-token-gated**: `runCycle` MUST call `fetchVercelDeployments`/`fetchVercelProductionStates` only when `conn.vercel.token` is truthy, `fetchRailwayDeployments` only when `conn.railway.token` is truthy, and `fetchCrunchyClusters` only when `conn.crunchy.token` is truthy; when the corresponding token is absent it MUST use `EMPTY_DEPLOYS`/`EMPTY_PROJECTS` (via `Promise.resolve`, for the three that participate in the `Promise.all`) directly, WITHOUT ever calling `guard` for that provider.
- **cloudflare-gated-on-resolved-account**: `runCycle` MUST call `resolveCfAccountForConn(conn.cloudflare)` only when `conn.cloudflare.token` is truthy, and MUST call `fetchCloudflareDeployments` only when that resolution yields a non-null account id; otherwise it MUST use `EMPTY_DEPLOYS` for Cloudflare directly, without calling `guard`.
- **provider-polls-run-concurrently**: The (up to) four deploy-provider polls — Vercel, Cloudflare, Railway, Crunchy — MUST be started together via one `Promise.all` and MUST NOT be awaited one at a time in sequence; the Vercel production-states poll (`fetchVercelProductionStates`, the `prod` value) is a separate, earlier `await` and is not part of that `Promise.all`.
- **fetched-deploys-concatenation-order**: The `fetched` array upserted in step 7 MUST be the concatenation, in exactly this order, of `prod.deploys`, `vc.deploys`, `cf.deploys`, `ry.deploys`, `cr.deploys`.
- **upsert-before-enrichment**: `runCycle` MUST call `storage.deploy.upsertDeployments(fetched)` and then `storage.deploy.learnProjectIds(fetched)` before calling `enrichDeployErrors`, `reconcileVanishedDeploys`, or `expireUnconfirmedDeploys` on the full-cycle path.
- **enrich-reconcile-expire-order**: On the full-cycle path, `runCycle` MUST await, in exactly this order, `enrichDeployErrors(storage, conn)`, then `reconcileVanishedDeploys(storage, conn)`, then `expireUnconfirmedDeploys(storage)` — each fully awaited before the next begins.
- **prune-only-on-any-fetcher-success**: `runCycle` MUST call `storage.deploy.pruneOlderThanDays(90)` if and only if at least one of `vc.ok`, `cf.ok`, `ry.ok`, `prod.ok`, `cr.ok` is `true`; when all five are `false` it MUST instead log `[sync] all deploy fetchers failed — skipping prune` via `console.error` and MUST NOT call `pruneOlderThanDays`.
- **stamp-live-hosts-after-upsert**: `runCycle` MUST call `stampLiveHosts(storage, roster)` (with `roster` from `storage.board.readRoster()`) only after `upsertDeployments`/`learnProjectIds` have completed for that cycle.
- **prod-states-liveurl-correlation**: For each entry `s` of `prod.states`, `runCycle` MUST set `s.liveUrl` by calling `matchRosterEntry({ platform: "vercel", providerProjectId: null, projectName: s.projectName, environment: null }, byId, byName)` (with `byId`/`byName` from `rosterTargets(roster, [])`); when the match has a `url`, `s.liveUrl` MUST be `` `https://${hostOf(owner.url).toLowerCase()}` ``; otherwise it MUST be `null`.
- **vercel-project-meta-uses-this-poll**: `runCycle` MUST call `syncVercelProjectMeta(storage, { meta: prod.meta, ok: prod.ok, configured: has.vercelToken })` using the `prod` value already fetched this cycle; it MUST NOT issue a second Vercel projects fetch to do this reconcile.
- **retire-unclaimed-gated-on-live**: `runCycle` MUST attempt `enumerateDeployProjects` and `retireUnclaimedMonitors` only when `live.length > 0` (the endpoint list as narrowed by the structural prune and, on a later call within the same cycle, by nothing else yet); when `live.length === 0` it MUST skip both entirely for that cycle.
- **enumerate-failure-yields-empty-inventory**: If `enumerateDeployProjects(storage, config)` rejects, `runCycle` MUST catch the rejection, log `[sync] deploy-project enumeration failed — skipping monitor removal:` (with the error) via `console.error`, and proceed as though the enumeration had resolved `{ projects: [], verifiedPlatforms: [], verifiedDomains: [] }` (which, given `endpointsClaimedByNothing`'s own evidence requirements, condemns nothing).
- **vercel-added-to-verified-platforms-conditionally**: The `verifiedPlatforms` array passed into `retireUnclaimedMonitors`'s evidence MUST include `"vercel"` if and only if `syncVercelProjectMeta`'s returned `live` set is non-null (i.e., this cycle's Vercel projects read was both complete and authenticated) — never merely because `has.vercelToken` is true.
- **verified-domains-filtered-to-verified-platforms**: The `verifiedDomains` evidence passed into `retireUnclaimedMonitors` MUST be `enumerated.verifiedDomains` filtered to only the platforms present in `verifiedPlatforms` for that same call.
- **staleness-mirror-recorded-only-with-endpoints-and-ok**: `runCycle` MUST call `storage.observations.recordVercelProdStates(prod.states)` if and only if `endpoints.length > 0` (the list as originally read in step 1, before either retire step narrows it) AND `prod.ok` is `true`.
- **platform-observations-always-recorded**: `runCycle` MUST call `storage.observations.recordObservations` with exactly four entries — `{ source: "vercel", configured: has.vercelToken, reachable: vc.ok }`, `{ source: "cloudflare-pages", configured: has.cloudflareToken, reachable: cf.ok }`, `{ source: "railway", configured: has.railwayToken, reachable: ry.ok }`, `{ source: "crunchy", configured: has.crunchyToken, reachable: cr.ok }` — unconditionally on the full-cycle path, regardless of `endpoints.length`.
- **ledger-write-last**: `reconcileBoardLedger(storage, config, { skipOnEmptyRoster: true })` MUST be the last call `runCycle` makes on the full-cycle path, after both recorder calls above.

### Monitor Deletion (`retireMonitors` / `retireUnclaimedMonitors`)

- **retire-noop-on-empty-doomed-set**: `retireMonitors` MUST return the `endpoints` array unchanged, and MUST NOT make any `storage` call or log anything, when `doomed.length === 0`.
- **retire-per-endpoint-outcome**: For each endpoint in `doomed`, `retireMonitors` MUST call `storage.config.retireEndpoint(ep.slug)`; on success it MUST log `` `[sync] removed monitor ${ep.name} (${ep.url}) — ${reason}` `` via `console.log` and MUST call `notifyIssueAlert({ kind: "retired", target: ep.slug, name: ep.name, environment: ep.environment, state: null, detail: reason })`; on rejection it MUST log `` `[sync] failed to remove monitor ${ep.slug} (${reason}):` `` (with the error) via `console.error`, and MUST NOT call `notifyIssueAlert` for that endpoint and MUST leave that endpoint's slug out of the retired set (so it remains in the returned survivor list).
- **retire-unclaimed-delegates-the-verdict**: `retireUnclaimedMonitors` MUST compute `{ doomed, withheld }` by calling `endpointsClaimedByNothing(endpoints, projects, evidence)` exactly once, and MUST NOT independently recompute, second-guess, or override that verdict.
- **retire-unclaimed-logs-every-withheld-reason**: For each string in `withheld`, `retireUnclaimedMonitors` MUST log `` `[sync] not removing monitors — ${reason}` `` via `console.log`.
- **healthy-probe-vetoes-removal**: `retireUnclaimedMonitors` MUST filter `doomed` to exclude every endpoint whose `slug` is present in `stillServing` before passing the remainder to `retireMonitors` — a URL this cycle probed healthy is never deleted by the unclaimed-monitor rule, regardless of what the platform inventory says about it.
- **retire-reason-wording**: The `why` function `retireUnclaimedMonitors` passes to `retireMonitors` MUST produce `` `its ${platformCanon(ep.platform ?? "")} project "${ep.deployProject}" no longer exists` `` when `ep.deployProject` is set, and `` `no deploy project serves ${hostOf(ep.url)} any more` `` when it is not.

### Live-Host Stamping (`stampLiveHosts`)

- **stamp-writes-only-changed-rows**: For each row `d` returned by `storage.deploy.listForLiveHostStamp()`, `stampLiveHosts` MUST call `storage.deploy.setLiveHost(d.id, host)` if and only if `(d.liveHost ?? null) !== host`; it MUST NOT write a row whose computed host equals its currently stored one.
- **stamp-host-computation**: `host` MUST be computed as `(owner?.url ? hostOf(owner.url).toLowerCase() : "") || null` — where `owner` is `matchRosterEntry(d, byId, byName)` — so an empty string collapses to `null` rather than being written literally.
- **stamp-uses-no-account-mirror**: `stampLiveHosts` MUST call `rosterTargets(roster, [])` with an empty array as the second argument (no per-platform domain narrowing) for this correlation.

## Appearance

Not applicable — this is a server-side background sync function, not a visual component.

## States

Not applicable — this is a server-side background sync function, not a visual component; its runtime states (probe-only tick vs. full cycle, per-endpoint doomed/surviving, per-provider reachable/unreachable) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side background sync function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-sync-001 | poll-timeout-cap | `guard('test', null, fallback, () => new Promise(() => {}))` (never resolves) with fake timers advanced 20,000ms | The returned promise resolves to `fallback` (`===`) — `sync-guard.test.ts` › "caps a hung poll and resolves the fallback instead of hanging forever" |
| status-server-monitor-sync-002 | poll-throw-degrades | `guard('test', null, fallback, async () => { throw new Error('boom') })` | Resolves to `fallback` (`===`), never rejects — `sync-guard.test.ts` › "degrades a throwing poll to the fallback" |
| status-server-monitor-sync-003 | poll-passthrough | `guard('test', null, fallback, async () => good)` where `good` is a distinct object | Resolves to `good` (`===`), not `fallback` — `sync-guard.test.ts` › "passes a fast successful poll through unchanged" |
| status-server-monitor-sync-004 | provider-poll-token-gated, probe-skipped-on-empty (negative) | `runCycle(storage, testConfig())` against one seeded endpoint, `fetch` stubbed to 200, no Vercel/Railway/Cloudflare tokens set | Resolves without throwing; at least one `health_checks` row recorded with `status: 'healthy'` — `sync.int.test.ts` › "records a health check for an active endpoint and does not throw without provider tokens" |
| status-server-monitor-sync-005 | skip-deploys-early-return, prune-only-on-any-fetcher-success | An active Railway integration (empty-but-authorized enumeration, `ok:true`) plus a deploy row 200 days old; `runCycle(storage, testConfig(), { skipDeploys: true })` then `runCycle(storage, testConfig())` | After the `skipDeploys` call the aged row still exists and a health check was still recorded; after the following full call the aged row is gone — `sync.int.test.ts` › "skipDeploys runs the probe (steps 0-5) but skips the provider poll + prune" |
| status-server-monitor-sync-006 | provider-poll-token-gated, poll-throw-degrades, platform-observations-always-recorded | A Vercel integration configured with a token, `fetch` stubbed to always throw; `runCycle` called twice in a row | Neither call rejects; a `health_checks` row is still recorded (the probe's own fetch also throws, classified `down`); after the first call `platformHealthState` shows `consecutiveFailures >= 1` for `vercel`; after the second call an open issue with `target: 'platform-health\|vercel'` exists — `sync.int.test.ts` › "fail-soft: a provider poll that THROWS does not abort the cycle" |
| status-server-monitor-sync-007 | structural-prune-first, resolve-unmonitored-on-prune | FK enforcement OFF; a live endpoint plus a ghost endpoint whose owning site was deleted directly, with an open `dns` issue targeting the ghost; `runCycle(storage, testConfig())` | The ghost endpoint row is gone (only the live one remains) and its open issue is resolved (no phantom Problem) — `sync.int.test.ts` › "prunes a dangling endpoint (and resolves its issue) so a phantom DNS failure self-heals" |
| status-server-monitor-sync-008 | retire-per-endpoint-outcome, retire-reason-wording, healthy-probe-vetoes-removal (negative case) | Vercel configured; inventory has project `wired-live` (serving `live.example.test`) only; two seeded monitors, one wired to `wired-live`, one wired to `wired-gone`; one `runCycle` | Only `https://live.example.test` remains configured; the `wired-gone` endpoint's checks, metrics, and open issue are all gone; exactly one `retired` alert is queued with `detail: 'its vercel project "wired-gone" no longer exists'` — `retire-unclaimed-monitors.int.test.ts` › "deletes a monitor whose wired project is gone — row, checks, metrics, site, issue and an alert" |
| status-server-monitor-sync-009 | healthy-probe-vetoes-removal | Vercel configured; inventory claims only `veto-live`'s host; probes stub `serving.example.test` as 200-serving; three unwired/unclaimed monitors seeded (`vl`, `serving`, `dead`) | `serving.example.test` survives despite being claimed by nothing (the healthy veto), while `dead.example.test` (also unclaimed, not serving) is removed — `retire-unclaimed-monitors.int.test.ts` › "keeps a monitor that probed HEALTHY even though nothing claims it, and deletes its dead sibling" |
| status-server-monitor-sync-010 | retire-unclaimed-delegates-the-verdict, retire-unclaimed-logs-every-withheld-reason | Vercel configured; one project's `/domains` read 403s; one claimed host plus one orphan unwired host seeded | Both hosts survive (nothing removed) and the withheld log lines contain `domain lists not complete for vercel` — `retire-unclaimed-monitors.int.test.ts` › "withholds the unwired verdict when ONE project domain read 403s" |

## Edge Cases

- **Null and empty input**: `opts` omitted entirely is equivalent to `opts?.skipDeploys` being falsy — the full cycle runs (MUST). An empty active-endpoint list (`listActiveEndpoints()` resolves `[]`) skips the whole probe/record/rollup block (probe-skipped-on-empty) and resolves `undefined` with zero `health_checks` rows written — MUST (`sync.int.test.ts` › "completes with no configured endpoints"). When no provider has a configured token, `has.*Token` is `false` for all four providers, so `runCycle` never calls `guard` at all for them — the fallback shapes (`EMPTY_DEPLOYS`/`EMPTY_PROJECTS`) are produced directly via `Promise.resolve`/ternary, bypassing even the rate-limit check inside `guard` — MUST (provider-poll-token-gated).
- **Boundary values**: `PROVIDER_POLL_TIMEOUT_MS` is a fixed `20_000`, not read from `config` or an environment variable — every poll gets exactly the same cap regardless of provider or cycle — MUST. `pruneOlderThanDays(90)` is likewise a literal in this file, not a `StatusConfig` field — MUST. The healthy-probe veto (`healthy-probe-vetoes-removal`) is applied strictly AFTER `endpointsClaimedByNothing` has already decided the `doomed` set — it is a second, narrower filter this caller alone applies, never a change to the underlying rule's own preconditions — MUST NOT be read as the rule itself having a "still serving" clause.
- **Concurrent access**: `runCycle` installs no lock or reentrancy guard of its own against a second concurrent call against the same `storage` — nothing in this file prevents two cycles from interleaving their reads and writes; serialization is delegated entirely to the caller (the cycle-runner/scheduler composition, external to this file — see the [Status Server Monitor Cycle Runner](agentictoolkit://recipes/status-server-monitor-cycle-runner) recipe) — MUST NOT be read as a promise of its own concurrency safety. Within one call, the four deploy-provider polls run concurrently via `Promise.all` (provider-polls-run-concurrently), and each `guard` call's own `setTimeout` is independent and cleared in its own `finally`, so concurrent polls never share or leak each other's timers — MUST.
- **Error states**: Steps that carry no `try`/`catch` of their own — `reconcileOrphanedEndpoints`, `resolveUnmonitoredTargets`, `listActiveEndpoints`, `probeEndpoints`, `recordChecks`, `rollupMetrics`, `upsertDeployments`, `learnProjectIds`, `readRoster`, `stampLiveHosts`, `recordVercelProdStates`, `recordObservations`, `reconcileBoardLedger` — reject the whole `runCycle` promise on failure, with no fallback of their own; this bare propagation is what lets the cycle-runner composition's own failure handling (documented in its recipe) apply — MUST. The specifically fail-soft pieces are limited to: each provider poll (via `guard`), `enrichDeployErrors`, `reconcileVanishedDeploys`, `expireUnconfirmedDeploys` (each documented never-throws by its own module), and the `enumerateDeployProjects` call in step 8 (caught locally via `.catch`, `enumerate-failure-yields-empty-inventory`) — MUST.
- **Offline / disconnected state**: A provider whose network is entirely unreachable is absorbed by `guard`'s throw-catch (poll-throw-degrades) into the same `{ ok: false }` shape a documented API failure produces — the cycle records `reachable: false` for that source (platform-observations-always-recorded) rather than aborting — MUST. Two consecutive unreachable polls of the same provider are what the platform-health issue in the ledger (written downstream by `reconcileBoardLedger`, via `PLATFORM_UNREACHABLE_POLLS` in `issue-sources.ts`, external to this file) eventually pages on — this file only supplies the per-cycle `reachable` fact, never the debounce threshold itself — MUST NOT be read as this file owning that threshold.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | none — caller-supplied, required | The persistence port every read/write in this file goes through. Opened and owned entirely by the caller; this file never manages a connection. |
| `config` (parameter) | `StatusConfig` | none — caller-supplied, required | Threaded into `providerConn`, `enumerateDeployProjects`, and `reconcileBoardLedger`. This file itself reads provider credentials only indirectly, through `providerConn(storage, config)`'s resolved `conn`. |
| `opts.skipDeploys` (parameter) | `boolean \| undefined` | `undefined` (falsy → full cycle) | `true` runs only the cheap probe (steps 0-5) plus the bounded in-flight deploy reconcile and the ledger write, then returns; the expensive provider-poll/prune/retire phase (steps 6-8) is skipped entirely for that call. |
| `PROVIDER_POLL_TIMEOUT_MS` (module constant) | `number` | `20_000` | Hard cap every `guard`-wrapped provider poll races against; not configurable from `StatusConfig` or the environment. |
| deploy retention window (`pruneOlderThanDays` argument) | `number` (literal) | `90` | Hardcoded in this file's call; the row-level retention this cycle itself performs on the `deployments` table (distinct from the `health_checks`/`metrics_hourly` retention owned by `MaintenanceStore`). |
| `EMPTY_DEPLOYS` / `EMPTY_PROJECTS` (module constants) | `{ ok: false, deploys: [] }` / `VercelProjectsResult`-shaped | fixed literal | The fallback shapes `guard`, and the token-gating ternaries, substitute for a provider that is unconfigured, unreachable, rate-limited, or timed out — every downstream consumer of a poll result reads the same shape whether the provider ran or not. |
| provider tokens (`conn.vercel.token`, `conn.cloudflare.token`, `conn.railway.token`, `conn.crunchy.token`) | `string \| undefined`, resolved via `providerConn(storage, config)` (external) | none | Presence alone (not value) gates whether a provider is polled at all this cycle (provider-poll-token-gated); the token value itself is only ever passed to that provider's own fetcher, never inspected or logged by this file. |

## Deep Linking

Not applicable: this file defines no application URL scheme or HTTP route of its own; `hostOf` only parses URLs it is handed, and calls out to no destination this file itself resolves as a deep link.

## Localization

This file's only literal strings are hardcoded English `console.log`/`console.error` messages (operator-facing, container stdout) and the two alert `detail` strings assembled in `retire-unclaimed-monitors`' `why` callback (`its <platform> project "<name>" no longer exists`, `no deploy project serves <host> any more`) — all routed through no localization mechanism, all consumed by an operator or by `notifyIssueAlert`'s own Slack/Discord-rendering (external, documented in the [Status Server Monitor Alerts](agentictoolkit://recipes/status-server-monitor-alerts) recipe), never by an end user.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a | `[sync] removed monitor <name> (<url>) — <reason>` | `console.log` after a successful `retireEndpoint` call |
| n/a | `[sync] failed to remove monitor <slug> (<reason>): <err>` | `console.error` after a rejected `retireEndpoint` call |
| n/a | `[sync] not removing monitors — <reason>` | `console.log`, once per string in `endpointsClaimedByNothing`'s `withheld` list |
| n/a | `[sync] <label> is rate-limited — skipping until <ISO timestamp>` | `console.error` inside `guard`, when `rateLimitedUntil` returns a cooldown |
| n/a | `[sync] <label> poll exceeded 20000ms — treating as unreachable` | `console.error` inside `guard`, on the timeout branch |
| n/a | `[sync] <label> poll threw — treating as unreachable: <err>` | `console.error` inside `guard`, on the caught-throw branch |
| n/a | `[sync] all deploy fetchers failed — skipping prune` | `console.error` when every one of `vc.ok/cf.ok/ry.ok/prod.ok/cr.ok` is `false` |
| n/a | `[sync] deploy-project enumeration failed — skipping monitor removal: <err>` | `console.error` when `enumerateDeployProjects` rejects |
| n/a | `its <platform> project "<name>" no longer exists` | `retired` alert `detail` / removal-log `reason`, for a wired-and-gone monitor |
| n/a | `no deploy project serves <host> any more` | `retired` alert `detail` / removal-log `reason`, for an unwired-and-unclaimed monitor |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system. Its only on/off levers are the per-provider token presence (`has.vercelToken`, etc., documented under Configuration) and the caller-supplied `opts.skipDeploys`, neither of which is a flag lookup this file performs itself.

## Analytics

Not applicable: this file emits no analytics or usage-telemetry event describing its own execution, and it consumes no analytics data either — the GlitchTip/PostHog telemetry poll is a separate collaborator (`telemetry/server.ts`, external, used by the cycle-runner composition, not by this file).

## Privacy

- **Data collected**: this file reads provider API tokens indirectly through `conn` (resolved by `providerConn`, external) purely to decide whether to poll a provider (`has.*Token`) and to pass through to that provider's own fetcher call; it never itself inspects, transforms, or logs a token value. It reads and writes infrastructure-identifying data only — endpoint URLs/hostnames, deploy provider ids/project names/branches/commit hashes, health-check status codes and response times — no end-user PII passes through this file.
- **Storage**: none held by this file between calls; every value it touches is either a parameter, a value read fresh from `storage` this call, or a value a collaborator (a fetcher, `providerConn`, `enumerateDeployProjects`) resolved and handed back.
- **Transmission**: this file itself makes no direct network call — every outbound HTTP request (to Vercel/Cloudflare/Railway/CrunchyBridge, or to the alert webhook via `notifyIssueAlert`/`flushAlerts`) is made by a collaborator it calls into. The only value it threads toward an external destination is the provider token, passed straight through to that provider's own fetcher.
- **Retention**: `pruneOlderThanDays(90)` is this file's own retention rule, scoped to the `deployments` table, run once per full cycle when at least one deploy fetcher succeeded (prune-only-on-any-fetcher-success). Retention of `health_checks`/`metrics_hourly` is `MaintenanceStore.runMaintenance`'s concern, external to this file.

## Logging

This file uses plain `console.log`/`console.error` calls with a literal `[sync]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A doomed endpoint's `retireEndpoint` call succeeded | log (`console.log`) | `[sync] removed monitor <name> (<url>) — <reason>` |
| A doomed endpoint's `retireEndpoint` call rejected | error (`console.error`) | `[sync] failed to remove monitor <slug> (<reason>): <err>` |
| `endpointsClaimedByNothing` withheld a verdict | log (`console.log`) | `[sync] not removing monitors — <reason>` (once per withheld reason) |
| A provider is under an active rate-limit cooldown | error (`console.error`) | `[sync] <label> is rate-limited — skipping until <ISO>` |
| A provider poll exceeded the 20s cap | error (`console.error`) | `[sync] <label> poll exceeded 20000ms — treating as unreachable` |
| A provider poll threw | error (`console.error`) | `[sync] <label> poll threw — treating as unreachable: <err>` |
| Every configured deploy fetcher returned `ok:false` this cycle | error (`console.error`) | `[sync] all deploy fetchers failed — skipping prune` |
| `enumerateDeployProjects` rejected | error (`console.error`) | `[sync] deploy-project enumeration failed — skipping monitor removal: <err>` |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this cycle models `runCycle` as an `async` function or `actor` method taking a `Storage`-equivalent protocol and a `Sendable` `StatusConfig`-equivalent struct; `guard` becomes a small generic helper built on `withThrowingTaskGroup` or `Task` + `Task.sleep` racing, cancelling the loser but — matching the source's own choice — never cancelling the abandoned real call, only abandoning its result.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `runCycle` as a `suspend fun`; `guard` becomes `withTimeoutOrNull` composed with a `try`/`catch`, since Kotlin's `withTimeoutOrNull` alone cancels the racing coroutine (a deliberate divergence to note, since the source's `guard` does not cancel `fn()`); the four provider polls map to a `coroutineScope` running four `async` children joined together, matching `Promise.all`.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/sync.ts` as two exported `async function`s on the Node status backend (`runCycle`, `guard`), imported by the cycle-runner composition (`cycle-runner.ts`) and by the integration test suites that exercise it directly. Depends on plain `Promise.race`/`Promise.all`/`setTimeout`/`clearTimeout` — no framework of its own beyond the `Storage` port and the `@agentic-toolkit/deploy-platform` package for the deletion rule and cooldown state.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this cycle would typically run it from a background `Task` rather than Node's dedicated worker thread; there is no direct AppKit/UIKit view-layer analogue to any part of this file.
- **WinUI 3**: a .NET port models `runCycle` as `async Task RunCycleAsync(IStorage storage, StatusConfig config, SyncOptions? opts = null)` using `HttpClient` inside each fetcher and `System.Text.Json` for its JSON bodies; `guard` becomes a small generic `async Task<T> GuardAsync<T>(string label, string? provider, T fallback, Func<Task<T>> fn)` built on `Task.WhenAny(fn(), Task.Delay(20_000))` with a `CancellationTokenSource` used only to stop the *timer*, never the abandoned real call — mirroring the source's no-cancel choice. The four provider polls map to `Task.WhenAll`. `Windows.Storage` has no role here (there is no local file persistence in this file); persistence is entirely behind `IStorage`. `ObservableCollection`/`INotifyPropertyChanged` do not apply: this file exposes no UI-bound state of its own — those types belong to a WinUI 3 host's dashboard view model consuming the board this cycle feeds, not to the cycle itself.

## Design Decisions

- **Decision**: a currently-healthy probe (`stillServing`) vetoes the unclaimed-monitor deletion rule outright, even when the platform inventory condemns the same endpoint.
  **Rationale**: the source comment states it directly — a deploy project is keyed by NAME, so a rename or a team transfer at the provider reads exactly like a deletion; a URL that is still answering is a site worth watching regardless of what the inventory currently says, and a genuinely deleted project takes its own deployment down with it, so the healthy case is precisely the ambiguous one this veto exists to protect.
  **Approved**: pending
- **Decision**: split config deletion into two separate gates — a structural prune (step 0, `reconcileOrphanedEndpoints`) and a platform-inventory prune (step 8, `retireUnclaimedMonitors`) — rather than one combined check.
  **Rationale**: the source's own step-by-step comment states each answers "a different half of the same question": step 0 is about the configured group→site→endpoint chain no longer owning a row; step 8 is about no *provider* accounting for the row any more. Both are gated on evidence that survives a transient failure, but they read from entirely different sources of truth and would conflate two independent failure modes if merged.
  **Approved**: pending
- **Decision**: put the rate-limit cooldown check inside `guard` itself, the one wrapper every cycle poll crosses, rather than inside each fetcher.
  **Rationale**: source comment: doing it in each fetcher is "a convention a new provider's author has to remember (and where a typo'd name would silently disable it)." Centralizing it in `guard` makes the cooldown unconditional for every future provider poll added to this file.
  **Approved**: pending
- **Decision**: only run `pruneOlderThanDays(90)` when at least one deploy fetcher succeeded this cycle, rather than pruning unconditionally on a fixed schedule.
  **Rationale**: source comment: pruning unconditionally "avoid[s] deleting history when a temporary outage makes all fetchers return ok:false" — an all-providers-down cycle must not be indistinguishable, in its effect on stored history, from a genuinely stale set of rows.
  **Approved**: pending
- **Decision**: keep the bounded in-flight deploy reconcile (`reconcileVanishedDeploys`) and the ledger write (`reconcileBoardLedger`) running even on a `skipDeploys` (probe-only) tick, while skipping every other deploy-phase step.
  **Rationale**: source comment: only the deploy block terminalizes a finished build, so without this exemption the board kept asserting "building" for deploys the provider had already marked ready, for the full slow-cadence interval; the reconcile itself is "by-id, capped, and a no-op when nothing is in flight," so it costs one small query per tick and only does real work during a deploy burst — exactly when the board would otherwise go stale.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |

`unit-test-coverage` passes: `sync-guard.test.ts` pins `guard`'s three branches directly (timeout, throw, pass-through), `sync.int.test.ts` exercises `runCycle` end-to-end across the probe/rollup/skip-deploys/prune/fail-soft-poll/structural-prune paths, and `retire-unclaimed-monitors.int.test.ts` exhaustively pins the deletion rule's positive and every withheld case through `runCycle` itself. `separation-of-concerns` passes: this file composes and sequences, but the deletion rule's own preconditions live in `endpointsClaimedByNothing` (`deploy-platform/engine/run.ts`), the ownership correlation lives in `board/ownership.ts`, each provider's own fetch/parse lives in its own `fetch-*.ts` module, and the board-derivation/ledger logic lives in `board/reconcile.ts` and `board/derive.ts` — this file owns only the cycle's own sequencing, fail-soft wrapping, and the one caller-side veto (`stillServing`) that no lower layer can see. `explicit-error-handling` passes: every fail-soft path is an explicit `try`/`catch` or `.catch` with a logged fallback (`guard`, the `enumerateDeployProjects` catch), and every other step is left to propagate deliberately, documented under Edge Cases, rather than silently swallowed. `error-recovery` passes: a rejected `runCycle` call does not corrupt state for the next attempt — every write in this file is either idempotent or narrowly scoped, so a retried cycle (by the caller, on the next tick) picks up cleanly. `graceful-degradation` passes: a missing token, a rate-limited provider, a thrown fetch, or an overrunning poll each degrade to the same `{ ok: false }` fallback shape and a recorded blind spot, never an aborted cycle. `fault-tolerance` passes: one provider's failure (network down, API error, timeout) never prevents the other three providers' polls, the endpoint probe, or the ledger write from completing. `timeout-handling` passes: `guard`'s `PROVIDER_POLL_TIMEOUT_MS` cap is exactly the "one slow/hung platform must not wedge the cycle" mechanism this check calls for. `idempotent-operations` passes: `retireEndpoint` is documented idempotent (an already-deleted id is a no-op), `upsertDeployments`/`learnProjectIds` are upserts, `pruneOlderThanDays` is a repeatable cutoff-keyed delete, and `stampLiveHosts` only writes rows whose computed value actually changed. `secure-log-output` passes: every `console.log`/`console.error` call in this file logs endpoint URLs, project names, hostnames, and error objects — never a provider token or any other credential value, even though `conn` (which holds them) is threaded through several of this file's own calls.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
