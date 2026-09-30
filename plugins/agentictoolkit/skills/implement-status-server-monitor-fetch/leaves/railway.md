<!-- leaf: implement-status-server-monitor-fetch/railway · source: status-server-monitor-fetch-railway.md -->

**Rules** (cite as `implement-status-server-monitor-fetch/railway#<slug>`):

- `env-shape` MUST
- `noop-missing-token` MUST
- `cooldown-gate-on-entry` MUST
- `overall-budget-default` MUST
- `call-timeout-default` MUST
- `deadline-starts-before-listing` MUST
- `listing-retry-on-timeout-only` MUST
- `per-project-retry-on-timeout-only` MUST
- `budget-exhaustion-before-first-attempt-is-skip` MUST
- `budget-exhaustion-mid-retry-is-error` MUST
- `exhausted-retries-logged-once` MUST
- `prefer-live-listing` MUST
- `fallback-to-configured-projects` MUST
- `blind-spot-vs-empty-account` MUST
- `bounded-concurrency-five` MUST
- `env-query-precedes-deployments` MUST
- `env-page-size-pinned` MUST
- `env-fetch-failure-is-project-error` MUST
- `env-full-page-logged` MUST
- `env-name-map-built` MUST

# Status Server Monitor Fetch Railway

## Overview

`fetch-railway.ts` (`packages/web/packages/status-server/src/monitor/fetch-railway.ts`) is the Railway provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external). It exports five members: `fetchRailwayDeployments`, the poll entry point that enumerates every Railway project a token can see, fetches each one's environment map and deployment history with a bounded, retrying fan-out, and maps the results into `ProviderDeploy` rows (`./provider-deploy`, external); `buildLogTail` and `buildLogFull`, the pure (network-free) shaping halves of a build log into a bounded tail or a complete text; `fetchRailwayBuildLogTail` and `fetchRailwayBuildLog`, the network wrappers that fetch one deployment's build-log lines over GraphQL and apply one of those two shapers; and `RAILWAY_NO_BUILD_TEXT`, the permanent placeholder string for a deployment Railway reports as never having had a build. `fetchRailwayBuildLogTail` is consumed by `enrich-deploy-errors.ts` (external) to persist `error_text` on failed rows; `fetchRailwayBuildLog` is consumed by the `GET /deployments/:id/log` route (`routes/deploy-logs.ts`, external) for the on-demand full-log read; both callers strip this file's own `ry_` id prefix before passing a deployment id in, which is the callers' responsibility, not this file's. This file shares its overall-budget-then-bounded-fan-out shape, its rate-limit cooldown gate, and its blind-spot-vs-healthy-empty-account distinction with the sibling Cloudflare fetcher (`fetch-cloudflare.ts`, external) — several comments in that sibling cite this file as the precedent an identical bug or fix was already solved for, and vice versa (this file's own comments cite "the domains fetch," `listRailwayProjectDomains` in the vendored `@agentic-toolkit/deploy-platform` provider, external, as flattening its own copy of the environment-map shape this file cannot reach into).

## Behavioral Requirements

### Signature and No-Op / Cooldown Preconditions

- **env-shape**: `fetchRailwayDeployments` MUST accept one `env` object with optional fields `RAILWAY_API_TOKEN?: string`, `projects?: readonly RailwayProject[]`, `overallBudgetMs?: number`, and `callTimeoutMs?: number`, and MUST return a `Promise` resolving to `{ ok: boolean; deploys: ProviderDeploy[] }`.
- **noop-missing-token**: When `env.RAILWAY_API_TOKEN` is falsy (absent, empty string, or otherwise falsy), `fetchRailwayDeployments` MUST return `{ ok: true, deploys: [] }` immediately, performing no network call.
- **cooldown-gate-on-entry**: Before any network call, `fetchRailwayDeployments` MUST check `rateLimitedUntil("railway")` (`@agentic-toolkit/deploy-platform/cooldown`, external) and, when it returns a truthy cooldown expiry, MUST return `{ ok: false, deploys: [] }` immediately, performing no network call. This check is a self-contained precondition of this function, independent of the caller-side `guard()` wrapper in `sync.ts` (external), which checks the same shared registry before invoking this function during the normal poll cycle; `provider-cooldown.test.ts` exercises this function directly, with no `guard` wrapper, to assert the second of two back-to-back calls makes no additional request.

### Budget

- **overall-budget-default**: `fetchRailwayDeployments` MUST default `overallBudgetMs` to 18,000 (18 seconds, `RAILWAY_OVERALL_BUDGET_MS`) when `env.overallBudgetMs` is not supplied. Per the source's own comment, this sits "under sync's 20s `guard`" (`PROVIDER_POLL_TIMEOUT_MS` in `sync.ts`, external).
- **call-timeout-default**: `fetchRailwayDeployments` MUST default `callTimeoutMs` to 6,000 (`RAILWAY_CALL_TIMEOUT_MS`) when `env.callTimeoutMs` is not supplied.
- **deadline-starts-before-listing**: The overall deadline (`Date.now() + overallBudgetMs`) MUST be computed before the project-listing call, so the listing's own elapsed time counts against the budget. Per the source's own comment, computing the deadline after the listing (an earlier version of this file) let the real worst case run "~6s listing + the full budget + a last in-flight wave" past `guard`'s 20-second cap, discarding the whole poll as unreachable.
- **listing-retry-on-timeout-only**: `fetchRailwayDeployments` MUST retry the project-listing call up to `RAILWAY_CALL_ATTEMPTS` (2) times in total, continuing to a second attempt only when the first attempt's own `AbortController` fired (`listed === null` AND `listController.signal.aborted`) and only while remaining budget is greater than zero; a listing call that answers at all — including an authorized "Not Authorized" GraphQL-error answer — MUST NOT be retried.
- **per-project-retry-on-timeout-only**: For each project, `fetchRailwayDeployments` MUST retry that project's poll (`pollProject`) up to `RAILWAY_CALL_ATTEMPTS` (2) times in total, continuing to a second attempt only when the previous attempt's result was `aborted: true` (this project's own per-call `AbortController` fired) and only while remaining overall budget is greater than zero; a project poll that resolves with any real answer — success or a non-abort error — MUST NOT be retried.
- **budget-exhaustion-before-first-attempt-is-skip**: When remaining overall budget is at or below zero before a project's first poll attempt, `fetchRailwayDeployments` MUST set the module-local `skipped` flag to `true` and MUST return `{ rows: [], error: false }` for that project — this project was never polled, and is not counted as a per-project error.
- **budget-exhaustion-mid-retry-is-error**: When remaining overall budget is at or below zero before a project's retry attempt (attempt greater than 1), `fetchRailwayDeployments` MUST return `{ rows: [], error: true }` for that project — this project WAS polled once and timed out, which is the provider failing the poll rather than a project the poll chose not to start.
- **exhausted-retries-logged-once**: When a project's poll is aborted on every one of its `RAILWAY_CALL_ATTEMPTS` attempts, `fetchRailwayDeployments` MUST log exactly one message, `` Railway <projectId> timed out on all <RAILWAY_CALL_ATTEMPTS> attempts ``, and MUST return `{ rows: [], error: true }`; the per-attempt abort itself MUST NOT be separately logged at this level.

### Project Listing and Fallback

- **prefer-live-listing**: `fetchRailwayDeployments` MUST call `listRailwayProjects(token, signal)` (`@agentic-toolkit/deploy-platform/providers`, external), which enumerates every project the token can see via the root `projects` GraphQL query, preferring it over any caller-supplied list.
- **fallback-to-configured-projects**: When `listRailwayProjects` resolves `null` across all listing attempts, `fetchRailwayDeployments` MUST fall back to `(env.projects ?? []).slice()`.
- **blind-spot-vs-empty-account**: When the resulting project list (live or fallback) has length zero, `fetchRailwayDeployments` MUST return `deploys: []` and MUST set `ok` to the boolean `listed !== null` — `false` when the live listing failed (returned `null`) and no fallback list resolved to a non-empty array either, because holding a token that can see nothing is a blind spot warranting a platform-health issue; `true` when the live listing itself succeeded with a genuinely empty, authorized workspace (`listed` was `[]`, not `null`).

### Bounded Concurrent Fan-Out

- **bounded-concurrency-five**: `fetchRailwayDeployments` MUST poll projects through `mapLimit` (`@agentic-toolkit/deploy-platform/util`, external) with a concurrency limit of 5 (`RAILWAY_PROJECT_CONCURRENCY`), never serially and never fully unbounded. Per the source's own comment, a serial loop made total time `N × 6s`, which with enough projects and a degraded API "alone blows the cycle budget and wedges the whole monitor."

### Per-Project Environment Resolution

- **env-query-precedes-deployments**: For each project, `fetchRailwayDeployments` MUST fetch the `environments(projectId, first)` query and receive a usable response before issuing that project's `deployments` query; the two calls are serial within one project's poll, never concurrent.
- **env-page-size-pinned**: The environments query MUST pin `first: RAILWAY_ENV_PAGE_SIZE` (200) as a GraphQL variable, never left to the server's own default page size.
- **env-fetch-failure-is-project-error**: A non-ok environments HTTP response, a response body carrying GraphQL `errors`, or a response body with no `data.environments` payload at all MUST be logged (`` Railway environments <projectId> <status> `` for the HTTP case, `` Railway environments <projectId> unusable: <messages> `` for the GraphQL-error/missing-payload case) and MUST cause that whole project's poll to return `{ rows: [], error: true, aborted: false }` without ever issuing that project's deployments query. An environments response whose `edges` array is present but empty (`{ data: { environments: { edges: [] } } }`) is NOT this case — it is a genuinely env-less, authorized project and MUST proceed to the deployments query with an empty environment-name map.
- **env-full-page-logged**: When the environments response returns an edge count greater than or equal to `RAILWAY_ENV_PAGE_SIZE`, `fetchRailwayDeployments` MUST log a warning naming the project id and the edge count (matching `FULL page`) because the environment map may be truncated, but MUST NOT treat that project as an error or route it to the platform-unreachable path — the project answered normally.
- **env-name-map-built**: `fetchRailwayDeployments` MUST build an environment-id-to-name map from the environments response's edges (via `buildEnvNameMap`) before fetching that project's deployments.

