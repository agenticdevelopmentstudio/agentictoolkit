<!-- leaf: implement-status-server-monitor-2/sync--part-3 · source: status-server-monitor-sync.md -->

# Status Server Monitor Sync — continued (part 3)

**Rules** (cite as `implement-status-server-monitor-2/sync--part-3#<slug>`):

- `retire-noop-on-empty-doomed-set` MUST
- `retire-per-endpoint-outcome` MUST
- `retire-unclaimed-delegates-the-verdict` MUST
- `retire-unclaimed-logs-every-withheld-reason` MUST
- `healthy-probe-vetoes-removal` MUST
- `retire-reason-wording` MUST
- `stamp-writes-only-changed-rows` MUST
- `stamp-host-computation` MUST
- `stamp-uses-no-account-mirror` MUST

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

## Localization

This file's only literal strings are hardcoded English `console.log`/`console.error` messages (operator-facing, container stdout) and the two alert `detail` strings assembled in `retire-unclaimed-monitors`' `why` callback (`its <platform> project "<name>" no longer exists`, `no deploy project serves <host> any more`) — all routed through no localization mechanism, all consumed by an operator or by `notifyIssueAlert`'s own Slack/Discord-rendering (external, documented in the Status Server Monitor Alerts recipe), never by an end user.

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

## Privacy

- **Data collected**: this file reads provider API tokens indirectly through `conn` (resolved by `providerConn`, external) purely to decide whether to poll a provider (`has.*Token`) and to pass through to that provider's own fetcher call; it never itself inspects, transforms, or logs a token value. It reads and writes infrastructure-identifying data only — endpoint URLs/hostnames, deploy provider ids/project names/branches/commit hashes, health-check status codes and response times — no end-user PII passes through this file.
- **Storage**: none held by this file between calls; every value it touches is either a parameter, a value read fresh from `storage` this call, or a value a collaborator (a fetcher, `providerConn`, `enumerateDeployProjects`) resolved and handed back.
- **Transmission**: this file itself makes no direct network call — every outbound HTTP request (to Vercel/Cloudflare/Railway/CrunchyBridge, or to the alert webhook via `notifyIssueAlert`/`flushAlerts`) is made by a collaborator it calls into. The only value it threads toward an external destination is the provider token, passed straight through to that provider's own fetcher.
- **Retention**: `pruneOlderThanDays(90)` is this file's own retention rule, scoped to the `deployments` table, run once per full cycle when at least one deploy fetcher succeeded (prune-only-on-any-fetcher-success). Retention of `health_checks`/`metrics_hourly` is `MaintenanceStore.runMaintenance`'s concern, external to this file.

