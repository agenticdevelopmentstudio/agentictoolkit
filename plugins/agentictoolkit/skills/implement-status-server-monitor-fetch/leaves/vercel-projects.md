<!-- leaf: implement-status-server-monitor-fetch/vercel-projects · source: status-server-monitor-fetch-vercel-projects.md -->

**Rules** (cite as `implement-status-server-monitor-fetch/vercel-projects#<slug>`):

- `env-shape` MUST
- `noop-missing-token` MUST
- `cooldown-gate-on-entry` MUST
- `overall-budget-default` MUST
- `per-page-call-timeout-default` MUST
- `deadline-computed-once` MUST
- `page-iteration-cap` MUST
- `page-size-100` MUST
- `latest-deployments-depth-per-mode` MUST
- `team-scoping-param` MUST
- `cursor-pagination` MUST
- `per-page-retry` MUST
- `first-page-failure-definitive` MUST
- `later-page-error-partial` MUST
- `later-page-timeout-partial` MUST
- `budget-exhaustion-stops-pagination` MUST
- `truncation-cause-tracked` MUST
- `truncation-logged-once` MUST
- `domain-prefers-production-alias` MUST
- `domain-fallback-lookup-bounded` MUST
- `domain-fallback-skipped-past-deadline` MUST
- `domain-list-cache-ttl` MUST
- `domain-list-cache-fallback-on-failure` MUST
- `domain-canonical-non-redirect` MUST
- `domain-fixed-five-second-timeout` MUST
- `meta-built-for-every-project` MUST
- `meta-only-short-circuit` MUST

# Status Server Monitor Fetch Vercel Projects

## Overview

`fetch-vercel-projects.ts` (`packages/web/packages/status-server/src/monitor/fetch-vercel-projects.ts`) is the Vercel projects-and-production-staleness provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external). Its main export, `fetchVercelProductionStates`, paginates the whole account's project list, maps every project's recent deployment window into `ProviderDeploy` rows (`./provider-deploy`, external), backfills the newest conclusive deploy for a project whose window holds nothing but Ignored-Build-Step skips, resolves the account's dashboard slug, and judges each project's live production deployment for staleness. It shares its overall-budget-then-partial-return contract with the sibling Railway and Cloudflare fetchers (`fetch-railway.ts`, `fetch-cloudflare.ts`, both external) — several of the file's own comments name that precedent directly. Two pure helpers, `evaluateProdStaleness` and `staleDetail`, carry the staleness judgment itself and are exported for direct unit testing; `latestDeploysOf` carries the "always resupply the last verdict" contract and is exported the same way; `__resetTeamSlugCache` is a test-only seam.

## Behavioral Requirements

### Signature and No-Op Preconditions

- **env-shape**: `fetchVercelProductionStates` MUST accept one `env` object with optional fields `VERCEL_API_TOKEN?: string`, `VERCEL_TEAM_ID?: string`, `overallBudgetMs?: number`, `metaOnly?: boolean`, and `callTimeoutMs?: number`, and MUST return a `Promise` resolving to a `VercelProjectsResult` (`{ ok: boolean; states: VercelProdState[]; meta: VercelProjectMeta[]; deploys: ProviderDeploy[] }`).
- **noop-missing-token**: When `env.VERCEL_API_TOKEN` is falsy (absent, empty string, or otherwise falsy), `fetchVercelProductionStates` MUST return `{ ok: true, states: [], meta: [], deploys: [] }` immediately, performing no network call.
- **cooldown-gate-on-entry**: After the token check and before any network call, `fetchVercelProductionStates` MUST check `rateLimitedUntil("vercel")` (`@agentic-toolkit/deploy-platform/cooldown`, external) and, when it returns a truthy cooldown expiry, MUST return `{ ok: false, states: [], meta: [], deploys: [] }` immediately, performing no network call. This is the identical shared-registry check the deploys fetcher (`fetch-vercel.ts`, external) performs, and — per that module's own header comment — the registry is deliberately shared across the Node `Worker` thread the monitor cycle runs on and the API thread that enumerates `/deploy-projects`, so a 429 either side records is visible to this function's very next call.

### Budget and Timeouts

- **overall-budget-default**: `fetchVercelProductionStates` MUST default `overallBudgetMs` to 18,000 (18 seconds, `PROJECTS_OVERALL_BUDGET_MS`) when `env.overallBudgetMs` is not supplied, per the source's own comment, "under sync's 20s `guard`, so we return a partial ourselves rather than being abandoned by it."
- **per-page-call-timeout-default**: `fetchVercelProductionStates` MUST default `callTimeoutMs` to 6,000 (`PROJECTS_CALL_TIMEOUT_MS`) when `env.callTimeoutMs` is not supplied.
- **deadline-computed-once**: The overall deadline (`Date.now() + overallBudgetMs`) MUST be computed exactly once, before the project-enumeration loop starts, and every later phase (domain resolution, deploy derivation, the blind-project backfill, team-slug resolution) MUST measure its own remaining time against that same fixed deadline rather than recomputing a fresh budget.
- **page-iteration-cap**: The project-enumeration loop MUST stop after 50 iterations (`for (let page = 0; page < 50; page++)`) regardless of whether the API's `pagination.next` cursor is still non-null, as a fixed hard ceiling independent of the time-based deadline.

### Project Enumeration

- **page-size-100**: Each `/v9/projects` request MUST set `limit=100`.
- **latest-deployments-depth-per-mode**: Each `/v9/projects` request MUST set `latestDeployments` to `1` when `env.metaOnly` is `true`, or to `10` (`LATEST_DEPLOYMENTS_DEPTH`) otherwise. Per the source's own comment, Vercel's own default of 2 let a project's last real verdict "fall out of the window after just TWO commits," and 10 is "the cheap depth win: same call, no extra requests."
- **team-scoping-param**: Each `/v9/projects` request MUST include `teamId=<env.VERCEL_TEAM_ID>` in its query string when `env.VERCEL_TEAM_ID` is set, and MUST omit the parameter entirely otherwise.
- **cursor-pagination**: `fetchVercelProductionStates` MUST continue paginating by setting `until=<pagination.next>` on the following request whenever a page's response body carries a non-null `pagination.next`, and MUST stop paginating (with no further `/v9/projects` call) once a page's `pagination.next` is null or absent.
- **per-page-retry**: Each page fetch MUST be attempted up to `PROJECTS_CALL_ATTEMPTS` (2) times when an attempt throws (including its own `AbortController` firing), retrying immediately on the same call with no delay between attempts, before that page is treated as failed.
- **first-page-failure-definitive**: When the FIRST page (`page === 0`) receives a non-ok HTTP response, `fetchVercelProductionStates` MUST return `{ ok: false, states: [], meta: [], deploys: [] }` immediately, without attempting any further page.
- **later-page-error-partial**: When a page AFTER the first receives a non-ok HTTP response, `fetchVercelProductionStates` MUST NOT discard the projects already collected from earlier pages; it MUST set the truncation cause to `"page-error"` and stop paginating, keeping every project fetched so far.
- **later-page-timeout-partial**: When a page's fetch throws on every one of its `PROJECTS_CALL_ATTEMPTS` attempts (a stalled or aborted connection, not a definitive HTTP error), `fetchVercelProductionStates` MUST set the truncation cause to `"page-timeout"` and stop paginating, keeping every project fetched so far.
- **budget-exhaustion-stops-pagination**: When the remaining time before the deadline is `<= 0` at the start of a loop iteration, `fetchVercelProductionStates` MUST set the truncation cause to `"budget"` and stop paginating without issuing that page's request, keeping every project fetched so far.
- **truncation-cause-tracked**: `fetchVercelProductionStates` MUST track exactly one of three mutually distinguishable truncation causes — `"budget"`, `"page-error"`, or `"page-timeout"` — and MUST NOT report `"budget"` when the actual cause was a page's non-ok response or repeated timeout, per the source's own comment naming this "the WHY the enumeration was truncated, not merely THAT it was," because "the budget was never the cause" of the page-error/page-timeout cases in production.
- **truncation-logged-once**: When a truncation cause is set, `fetchVercelProductionStates` MUST log exactly one `console.error` line naming that cause (`` [vercel-projects] overall budget exceeded — returning partial ``, `` [vercel-projects] a page was refused by the API — returning partial ``, or `` [vercel-projects] a page timed out 2x — returning partial ``) via `reportTruncation`, and MUST NOT log anything from `reportTruncation` when no truncation occurred.

### Custom Domain Resolution

- **domain-prefers-production-alias**: For every enumerated project, `fetchVercelProductionStates` MUST first derive its domain from `pickDomain(p.targets?.production?.alias)` — the first alias entry that does not end in `.vercel.app` — before consulting any API.
- **domain-fallback-lookup-bounded**: For every project whose alias-derived domain is `null`, and only when `Date.now() < deadline` at that point, `fetchVercelProductionStates` MUST resolve its domain via `fetchProjectDomain` through a bounded concurrency of 8 concurrent calls (`mapLimit(missing, 8, ...)`).
- **domain-fallback-skipped-past-deadline**: When `Date.now() >= deadline` at the point domain resolution begins, `fetchVercelProductionStates` MUST skip the fallback lookup entirely for every project (the `missing` list is computed as `[]`), leaving each affected project's `domain` as `null` in its metadata rather than issuing any further request.
- **domain-list-cache-ttl**: `fetchProjectDomainList` MUST cache a successfully fetched domain list per project name for 3,600,000ms (`DOMAIN_CACHE_TTL_MS`, 1 hour) in the module-scope `domainListCache` map, and MUST return the cached list without issuing a request when a fresh-enough entry exists.
- **domain-list-cache-fallback-on-failure**: When the domains-API call for a project returns a non-ok response or throws, `fetchProjectDomainList` MUST return the project's last cached domain list if one exists, or `[]` if none exists, and MUST NOT overwrite the cache with an empty result on failure.
- **domain-canonical-non-redirect**: `fetchProjectDomain` MUST return the first entry of the project's verified domain list whose `redirect` field is falsy, or `null` when no such entry exists.
- **domain-fixed-five-second-timeout**: Each `/v9/projects/<name>/domains` request MUST be aborted after a fixed 5,000ms, independent of the shared overall deadline (unlike the team-slug and per-page timeouts, which shrink as the remaining budget shrinks).

### Project Metadata

- **meta-built-for-every-project**: `fetchVercelProductionStates` MUST build one `VercelProjectMeta` entry — `{ projectName, domain, gitRepo, gitBranch, rootDirectory, framework }` — for EVERY enumerated project, including a project with no production target, because, per the source's own comment, "the browser shows all of them." `gitRepo` MUST be `` `${p.link.org}/${p.link.repo}` `` when both are present on `p.link`, or `null` otherwise; `gitBranch` MUST be `p.link?.productionBranch ?? null`; `rootDirectory` and `framework` MUST pass through `p.rootDirectory ?? null` and `p.framework ?? null` unchanged.
- **meta-only-short-circuit**: When `env.metaOnly` is `true`, `fetchVercelProductionStates` MUST log any tracked truncation, then return `{ ok: !truncated, states: [], meta, deploys: [] }` immediately after building `meta` — it MUST NOT derive `deploys`, MUST NOT run the blind-project backfill, and MUST NOT resolve the team slug for this call.

