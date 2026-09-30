<!-- leaf: implement-status-server-monitor-2/sync--part-2 · source: status-server-monitor-sync.md -->

# Status Server Monitor Sync — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-2/sync--part-2#<slug>`):

- `rate-limited-provider-skip` MUST
- `poll-timeout-cap` MUST
- `poll-throw-degrades` MUST
- `poll-passthrough` MUST
- `timer-always-cleared` MUST
- `structural-prune-first` MUST
- `resolve-unmonitored-on-prune` MUST
- `probe-skipped-on-empty` MUST
- `still-serving-from-this-cycle-only` MUST
- `skip-deploys-early-return` MUST
- `provider-poll-token-gated` MUST
- `cloudflare-gated-on-resolved-account` MUST
- `provider-polls-run-concurrently` MUST
- `fetched-deploys-concatenation-order` MUST
- `upsert-before-enrichment` MUST
- `enrich-reconcile-expire-order` MUST
- `prune-only-on-any-fetcher-success` MUST
- `stamp-live-hosts-after-upsert` MUST
- `prod-states-liveurl-correlation` MUST
- `vercel-project-meta-uses-this-poll` MUST
- `retire-unclaimed-gated-on-live` MUST
- `enumerate-failure-yields-empty-inventory` MUST
- `vercel-added-to-verified-platforms-conditionally` MUST
- `verified-domains-filtered-to-verified-platforms` MUST
- `staleness-mirror-recorded-only-with-endpoints-and-ok` MUST
- `platform-observations-always-recorded` MUST
- `ledger-write-last` MUST

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

