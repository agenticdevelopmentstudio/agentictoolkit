---
id: 6a84b15a-5e4e-4b1c-9d73-0ae8a8b602af
title: Status Server Monitor Fetch Railway
domain: agentictoolkit://cookbook/status-server/monitor/fetch-railway
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Polls every Railway project's deployments with a retrying, bounded fan-out
  and an 18s budget into ProviderDeploy rows; also fetches Railway build-log tails
  and full logs for error enrichment and the details pane.
platforms:
- typescript
- web
tags:
- monitor
- railway
- deploy
- fetcher
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related:
- agentictoolkit://cookbook/status-server/monitor/fetch-cloudflare
- agentictoolkit://cookbook/status-server/monitor/deploy-status
- agentictoolkit://cookbook/status-server/monitor/alerts
- agentictoolkit://cookbook/status-server/monitor/enrich-deploy-errors
references:
- packages/web/packages/status-server/src/monitor/fetch-railway.ts (agentictoolkit)
- packages/web/packages/status-server/test/railway-deployments.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-error-shaping.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/provider-cooldown.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

### Deployment Fetch and Row Mapping

- **deployments-query-first-20**: For each project, `fetchRailwayDeployments` MUST request `deployments(first: 20, input: { projectId })`.
- **deployments-fetch-failure-is-project-error**: A non-ok deployments HTTP response MUST be logged (`` Railway <projectId> <status> ``) and MUST cause that project's poll to return `{ rows: [], error: true, aborted: false }`. A response body carrying GraphQL `errors` MUST be logged (`` Railway <projectId> GraphQL errors: <messages> ``) and MUST produce the same `{ rows: [], error: true, aborted: false }` result.
- **row-created-at-validated**: Each mapped row's `createdAt` MUST be the result of `toValidDate(node.createdAt)` (`./provider-deploy`, external); when that call returns `null`, `fetchRailwayDeployments` MUST log `` Railway deployment <id> has unparseable createdAt <JSON-stringified value> — skipping `` and MUST exclude only that one deployment from the project's rows (via `flatMap` returning `[]` for it), without failing the rest of the project's deployments.
- **row-environment-name-required**: Each mapped row's `environment` MUST be the environment-name map's resolved name for `node.environmentId`; when that id is absent from the map, `fetchRailwayDeployments` MUST log `` Railway deployment <id> references unknown environment <JSON-stringified environmentId> — skipping `` and MUST exclude only that one deployment from the project's rows. A row's `environment` MUST NEVER be the raw `environmentId` UUID or an empty string — either would mint a board target (`railway|<project>|<env>`, external) that matches no roster entry, or collides with an environment-less roster entry.
- **row-id-prefix**: Each mapped row's `id` MUST be the literal string `ry_` concatenated with the Railway deployment's `id` field.
- **row-platform-literal**: Each mapped row's `platform` MUST be the literal string `railway`.
- **row-project-name-from-config**: Each mapped row's `projectName` MUST be the Railway project's configured or enumerated `name` (the value the poll was called with for that project), never a value read from the deployment or its `meta`.
- **row-provider-project-id**: Each mapped row's `providerProjectId` MUST be the polled project's `id`.
- **row-phases-from-status**: Each mapped row's `buildPhase` and `deployPhase` MUST be the two fields of `railwayPhases(node.status)` (`./deploy-status`, external), spread directly onto the row.
- **row-commit-hash-shortened**: When `meta?.commitHash` is a `string`, the mapped row's `commitHash` MUST be `shortSha(meta.commitHash)` (`./format`, external, a 7-character truncation); otherwise it MUST be `null`.
- **row-commit-message-full**: When `meta?.commitMessage` is a `string`, the mapped row's `commitMessage` MUST be `commitFullMessage(meta.commitMessage)` (`./format`, external, the whole message capped at 4,000 characters with trailing whitespace stripped); otherwise it MUST be `null`.
- **row-branch-passthrough**: When `meta?.branch` is a `string`, the mapped row's `branch` MUST be that string unchanged; otherwise it MUST be `null`.
- **row-commit-repo-conditional**: When `meta?.repo` is a `string` AND contains a `/` character, the mapped row's `commitRepo` MUST be that string unchanged; otherwise it MUST be `null`.
- **row-url-dashboard-link**: Each mapped row's `url` MUST be the literal string `https://railway.com/project/` concatenated with the project id — the Railway dashboard link for that project — and MUST NOT be `node.staticUrl` or any other per-deployment live URL.

### Return Value

- **deploys-flattened**: `fetchRailwayDeployments` MUST return every successfully mapped row from every polled project's poll, concatenated into one flat `deploys` array, regardless of whether `ok` is `true` or `false` for the overall call.
- **ok-composition**: For the branch where at least one project was listed and polled, the returned `ok` MUST be `!anyError && !skipped` — `true` only when every polled project's poll succeeded with no unresolved error and no project was left unpolled for lack of remaining budget.

### Build Log Shaping (network-free)

- **build-log-tail-signature**: `buildLogTail` MUST accept an array of `string | null | undefined` and MUST return `string | null`.
- **build-log-tail-trims-and-filters**: `buildLogTail` MUST call `trimEnd()` on each message and MUST drop any message that is `null`, `undefined`, or empty after trimming, before joining the rest.
- **build-log-tail-keeps-last-40**: `buildLogTail` MUST keep only the last `RAILWAY_LOG_TAIL_LINES` (40) surviving lines, joined with `\n`.
- **build-log-tail-caps-chars**: `buildLogTail` MUST cap the joined tail at `RAILWAY_LOG_MAX_CHARS` (4,000) characters, keeping the END of the string and prefixing it with a single `…` character when truncation occurs.
- **build-log-tail-null-when-empty**: `buildLogTail` MUST return `null` when no non-blank lines remain after filtering.
- **build-log-full-keeps-all**: `buildLogFull` MUST accept the same input shape as `buildLogTail`, MUST apply the same trim-and-drop-blank filtering, but MUST keep every surviving line — with no line-count cap and no character cap — joined with `\n`, or `null` when none remain.

### Build Log Retrieval (network)

- **no-build-permanent-sentinel**: The internal `railwayBuildLogMessages` helper, shared by both `fetchRailwayBuildLogTail` and `fetchRailwayBuildLog`, MUST return the internal `NO_BUILD` symbol when the `buildLogs` query's GraphQL `errors` include a message matching `does not have an associated build` (case-insensitive), and MUST return `null` for any other GraphQL error, any non-ok HTTP response, or a thrown fetch — each logged with a distinguishing message (`` Railway buildLogs <deploymentId> <status> ``, `` Railway buildLogs <deploymentId> GraphQL errors: <messages> ``, or `` Railway buildLogs <deploymentId> fetch failed <err> ``).
- **fetch-build-log-tail-contract**: `fetchRailwayBuildLogTail(deploymentId, token, signal)` MUST request `buildLogs` with `limit: 200`, MUST return `RAILWAY_NO_BUILD_TEXT` when the shared helper reports the permanent sentinel, and otherwise MUST return `buildLogTail(messages)` when messages were retrieved or `null` when the helper itself failed.
- **fetch-build-log-full-contract**: `fetchRailwayBuildLog(deploymentId, token, signal)` MUST request `buildLogs` with `limit: RAILWAY_LOG_FULL_LINES` (10,000), MUST return `RAILWAY_NO_BUILD_TEXT` when the shared helper reports the permanent sentinel, and otherwise MUST return `buildLogFull(messages)` when messages were retrieved or `null` when the helper itself failed.
- **no-build-text-constant**: The exported `RAILWAY_NO_BUILD_TEXT` MUST be the literal string `(no build logs — the deployment has no associated build)`.

## Appearance

Not applicable — this is a server-side Railway deployment-polling and build-log-fetching module, not a visual component.

## States

Not applicable — this is a server-side Railway deployment-polling and build-log-fetching module, not a visual component; its runtime state (no-op, cooling down, listing, per-project fan-out with retry, budget-exhausted, per-deployment build-log lookup) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side Railway deployment-polling and build-log-fetching module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-fetch-railway-001 | noop-missing-token, env-shape | `fetchRailwayDeployments({})` | Resolves `{ ok: true, deploys: [] }` with no `fetch` call made — `railway-deployments.test.ts` › "is a no-op (ok) when no token is configured" |
| status-server-monitor-fetch-railway-002 | blind-spot-vs-empty-account | The `projects` listing query returns `{ errors: [{ message: 'Not Authorized' }] }`; called with `RAILWAY_API_TOKEN: 'unauthorized'` and no `projects` fallback | `out.ok === false`; `out.deploys` is `[]` — a token that cannot enumerate with no configured fallback is a blind spot — `railway-deployments.test.ts` › "reports ok:false when the token cannot enumerate AND no projects are configured" |
| status-server-monitor-fetch-railway-003 | blind-spot-vs-empty-account | The `projects` listing query returns `{ data: { projects: { edges: [] } } }`; called with `RAILWAY_API_TOKEN: 'workspace'` | `out` deep-equals `{ ok: true, deploys: [] }` — an authorized, genuinely empty workspace is healthy, not a blind spot — `railway-deployments.test.ts` › "reports ok:true when an authorized token genuinely has zero projects" |
| status-server-monitor-fetch-railway-004 | prefer-live-listing, env-query-precedes-deployments, row-id-prefix, row-platform-literal, row-project-name-from-config, row-phases-from-status, row-environment-name-required, row-commit-hash-shortened, row-branch-passthrough, deploys-flattened, ok-composition | `listRailwayProjects` returns one project `{ id: 'p0', name: 'adh-backend' }`; its environments query returns edge `{ id: 'e1', name: 'production' }`; its deployments query returns one node `{ id: 'd1', status: 'SUCCESS', createdAt: '2026-06-26T00:00:00.000Z', meta: { branch: 'main', commitHash: 'abcdef123456' }, environmentId: 'e1' }`; called with `RAILWAY_API_TOKEN: 'workspace'` | `out.ok === true`; `out.deploys` has length 1; `out.deploys[0]` matches `{ platform: 'railway', projectName: 'adh-backend', environment: 'production' }` (asserted by the test) and, by the unmodified row-mapping `flatMap`, also carries `id: 'ry_d1'`, `buildPhase: 'built'`, `deployPhase: 'deployed'`, `commitHash: 'abcdef1'`, `branch: 'main'`, `commitMessage: null`, `commitRepo: null`, `url: 'https://railway.com/project/p0'` — `railway-deployments.test.ts` › "enumerates projects then fetches their deployments" |
| status-server-monitor-fetch-railway-005 | fallback-to-configured-projects | The `projects` listing query returns `{ errors: [{ message: 'Not Authorized' }] }`; `env.projects` is `[{ id: 'p1', name: 'adh-backend' }]`; that project's environments/deployments queries succeed with one deployment whose `meta` is `null` | `out.ok === true`; `out.deploys` has length 1, matching `{ platform: 'railway', projectName: 'adh-backend', environment: 'production' }` — the failed live listing falls back to the configured list — `railway-deployments.test.ts` › "falls back to the configured projects list when enumeration returns null" |
| status-server-monitor-fetch-railway-006 | budget-exhaustion-before-first-attempt-is-skip, ok-composition | Three projects listed (`adh-backend`, `cookbook-backend`, `olylo-backend`), each would otherwise succeed; called with `overallBudgetMs: 0` | `out.ok === false`; `out.deploys` is `[]` — every project is skipped for budget with no throw — `railway-deployments.test.ts` › "returns a partial (ok:false) instead of discarding the whole poll when the overall budget is spent" |
| status-server-monitor-fetch-railway-007 | env-fetch-failure-is-project-error | One project listed; its environments query returns `{ errors: [{ message: 'Problem processing request' }] }`; its deployments query (mocked to return one FAILED deployment) is never reached because the environments failure short-circuits the project | `out.ok === false`; `out.deploys` is `[]` — nothing from the FAILED deployment is written, because the project's poll never reaches the deployments query — `railway-deployments.test.ts` › "reports ok:false and writes NOTHING when the env query returns GraphQL errors" |
| status-server-monitor-fetch-railway-008 | env-fetch-failure-is-project-error | One project listed; its environments query returns HTTP 502; its deployments query would otherwise return one FAILED deployment | `out.ok === false`; `out.deploys` is `[]`, for the same reason as -007 (non-ok HTTP response instead of a GraphQL-error body) — `railway-deployments.test.ts` › "reports ok:false and writes NOTHING when the env query returns a non-200" |
| status-server-monitor-fetch-railway-009 | row-environment-name-required | One project's environments map resolves only `e1` → `production`; its deployments query returns two nodes, one with `environmentId: 'e-deleted-last-year'` (unresolvable) and one with `environmentId: 'e1'` | `out.deploys.map(d => d.id)` equals `['ry_d-live']` — the unresolvable-environment deployment is dropped, its sibling kept, and `out.deploys[0]` matches `{ environment: 'production' }` — `railway-deployments.test.ts` › "never emits a row whose environment is a raw id — the unresolvable one is dropped, its sibling kept" |
| status-server-monitor-fetch-railway-010 | env-page-size-pinned | One project listed; the environments query is inspected for its sent variables | The sent query text matches an `environments(...)` call carrying a `first:` argument, and the sent `variables.first` is `200` (greater than or equal to 100) — `railway-deployments.test.ts` › "pins an explicit page size on the environments query — the completeness premise" |
| status-server-monitor-fetch-railway-011 | env-full-page-logged | One project's environments query returns exactly 200 edges (the pinned page size); its deployments query returns one deployment whose `environmentId` resolves via the first of those edges | `out.ok === true`; `out.deploys.map(d => d.id)` equals `['ry_d1']`; `console.error` is called at least once with a message matching `FULL page` — `railway-deployments.test.ts` › "logs when the environments page comes back FULL — a possible truncation is never silent" |
| status-server-monitor-fetch-railway-012 | env-fetch-failure-is-project-error (empty-edges branch) | One project's environments query returns `{ data: { environments: { edges: [] } } }`; its deployments query returns `{ data: { deployments: { edges: [] } } }` | `out` deep-equals `{ ok: true, deploys: [] }` — a genuinely env-less, authorized project is healthy, not an error — `railway-deployments.test.ts` › "an authorized project with genuinely ZERO environments is still ok — [] is not a failure" |
| status-server-monitor-fetch-railway-013 | deadline-starts-before-listing, budget-exhaustion-before-first-attempt-is-skip | The projects-listing fetch is delayed 250ms (ignoring its abort signal); called with `overallBudgetMs: 150` | `out.ok === false`; `out.deploys` is `[]`; no `fetch` call whose body contains `deployments(` is ever made — the listing alone consumed the whole 150ms budget before any per-project poll could start, so every project is skipped rather than attempted — `railway-deployments.test.ts` › "spends the listing time against the overall budget (no per-project fetches once spent)" |
| status-server-monitor-fetch-railway-014 | listing-retry-on-timeout-only | The `projects` listing call stalls (honoring the abort signal) on its first attempt only; called with `callTimeoutMs: 20`, `overallBudgetMs: 2_000` | The `projects` operation is sent exactly twice (the retry); `out.ok === true`; `out.deploys.map(d => d.id)` equals `['ry_d0']` — `railway-deployments.test.ts` › "retries the LISTING too — the coldest call, and the one whose loss costs a cycle" |
| status-server-monitor-fetch-railway-015 | per-project-retry-on-timeout-only | One project's `environments` call stalls (honoring the abort signal) on its first attempt only; called with `callTimeoutMs: 20`, `overallBudgetMs: 2_000` | The `environments` operation is sent exactly twice; `out.ok === true`; `out.deploys.map(d => d.id)` equals `['ry_d0']` — a single transient abort no longer makes the whole poll `ok:false` — `railway-deployments.test.ts` › "retries a project whose first call lost to the box, and reports a CLEAN poll" |
| status-server-monitor-fetch-railway-016 | per-project-retry-on-timeout-only, exhausted-retries-logged-once | One project's `environments` call stalls (honoring the abort signal) on every attempt; called with `callTimeoutMs: 20`, `overallBudgetMs: 2_000` | The `environments` operation is sent exactly twice (capped at `RAILWAY_CALL_ATTEMPTS`), never a third time; `out.ok === false`; `out.deploys` is `[]` — `railway-deployments.test.ts` › "gives up after the second attempt rather than retrying forever" |
| status-server-monitor-fetch-railway-017 | listing-retry-on-timeout-only, per-project-retry-on-timeout-only | One project's `environments` call answers immediately with `{ errors: [{ message: 'Not Authorized' }] }` (a real answer, not a timeout); called with `callTimeoutMs: 20`, `overallBudgetMs: 2_000` | The `environments` operation is sent exactly once — a real answer is never retried, even though it is an error — `out.ok === false` — `railway-deployments.test.ts` › "does NOT retry an answer, only a timeout" |
| status-server-monitor-fetch-railway-018 | cooldown-gate-on-entry | Every `fetch` call (including the listing) resolves HTTP 429; `fetchRailwayDeployments({ RAILWAY_API_TOKEN: 'tok' })` is called, then called again immediately | The second call makes no additional `fetch` call beyond the first call's count — the entry-point cooldown gate short-circuits it — `provider-cooldown.test.ts` › "railway: a 429 on the GraphQL endpoint cools the provider down" |
| status-server-monitor-fetch-railway-019 | build-log-tail-keeps-last-40 | `buildLogTail` called with 100 lines, `'line 0'` through `'line 99'` | Result splits into exactly 40 lines; the first is `'line 60'`, the last is `'line 99'` — `deploy-error-shaping.test.ts` › `buildLogTail` "keeps only the LAST 40 lines (the failure is at the tail)" |
| status-server-monitor-fetch-railway-020 | build-log-tail-caps-chars | `buildLogTail` called with one 10,000-character line | Result length is at most 4,001 characters, starts with `…`, and ends with the original line's last character — `deploy-error-shaping.test.ts` › `buildLogTail` "caps overall length, keeping the END with a leading ellipsis" |
| status-server-monitor-fetch-railway-021 | build-log-full-keeps-all | `buildLogFull` and `buildLogTail` both called with the same 100 lines | `buildLogFull`'s result splits into exactly 100 lines; `buildLogTail`'s result on the identical input splits into exactly 40 — `deploy-error-shaping.test.ts` › `buildLogFull` "keeps every line, unlike the 40-line tail" |
| status-server-monitor-fetch-railway-022 | no-build-permanent-sentinel, fetch-build-log-tail-contract | The `buildLogs` query returns `{ errors: [{ message: 'Deployment does not have an associated build' }] }` | `fetchRailwayBuildLogTail(...)` resolves `RAILWAY_NO_BUILD_TEXT` — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLogTail` "a buildless deployment ('no associated build') gets the PERMANENT placeholder, not a retry" |
| status-server-monitor-fetch-railway-023 | no-build-permanent-sentinel, fetch-build-log-tail-contract | The `buildLogs` query returns `{ errors: [{ message: 'Not Authorized' }] }` (a different GraphQL error) | `fetchRailwayBuildLogTail(...)` resolves `null` — a transient error retries next cycle rather than persisting a placeholder — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLogTail` "any other GraphQL error stays null (transient — retry next cycle)" |
| status-server-monitor-fetch-railway-024 | no-build-permanent-sentinel, fetch-build-log-full-contract | The `buildLogs` query returns 60 lines of messages | `fetchRailwayBuildLog(...)` resolves a string splitting into exactly 60 lines — the same input the tail would have capped at 40 — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLog` "returns every line the build emitted" |

## Edge Cases

- **Null and empty input**: `env.RAILWAY_API_TOKEN` absent, `undefined`, or an empty string all satisfy the same falsy check and MUST produce the `{ ok: true, deploys: [] }` no-op (noop-missing-token) — MUST. `env.projects` absent MUST be treated as an empty array (`env.projects ?? []`) when a fallback is needed — MUST. A `meta` field of `null` on a deployment node MUST resolve every conditional row field (`commitHash`, `commitMessage`, `branch`, `commitRepo`) to `null` rather than throwing — MUST, exercised by the "falls back to the configured projects list" test's `meta: null` fixture.
- **Boundary values**: exactly `RAILWAY_ENV_PAGE_SIZE` (200) or more environment edges triggers the truncation-possible log (env-full-page-logged) — MUST; fewer than 200 logs nothing. Exactly `RAILWAY_CALL_ATTEMPTS` (2) consecutive aborts on one call site (listing or one project) is the maximum retried — a third attempt is never made (listing-retry-on-timeout-only, per-project-retry-on-timeout-only) — MUST. The deployments query is pinned to `first: 20`: a project with more than 20 deployments recorded by Railway since the previous poll surfaces only its 20 most recent; any deployment outside that window is never returned by this call and is not an error condition this file detects — MUST, traced to the literal `deployments(first: 20, ...)` query text; this is a known, undocumented-as-a-limitation boundary of the fixed page size, not a bug this file guards against. Concurrency is capped at exactly `RAILWAY_PROJECT_CONCURRENCY` (5) simultaneous project polls (bounded-concurrency-five); a 6th project's poll does not start until one of the first 5 completes, per `mapLimit`'s own contract (`map-limit.ts`, external): "at most `limit` in flight."
- **Concurrent access**: this module has no internal mutable state shared ACROSS separate calls to `fetchRailwayDeployments` — its own local variables (`deploys`, `skipped`, the per-call `deadline`) are function-scoped and freshly created on each invocation. The provider-cooldown registry it reads via `rateLimitedUntil` and that the vendored `gqlPost` writes via `noteRateLimited` (`@agentic-toolkit/deploy-platform/cooldown`, external) IS shared cross-thread by design — that module's own header comment states it uses a `SharedArrayBuffer` with `Atomics` reads/writes specifically because the monitor cycle and the API thread's live enumeration run on different Node `Worker` threads and must agree on the same cooldown state. This file makes no additional synchronization of its own; a 429 noted by a concurrent caller on a different thread is visible to this function's own `rateLimitedUntil("railway")` check on its very next invocation, by construction of the shared registry — MUST. Within one call, the per-project `mapLimit` workers share no mutable per-project state with each other; each project's `rows`/`error`/`aborted` result is independent — MUST.
- **Error states**: a non-ok or GraphQL-error environments response fails the WHOLE project (rows dropped entirely, not partially) before any deployments call is made (env-fetch-failure-is-project-error) — MUST. A non-ok or GraphQL-error deployments response fails the whole project the same way, after the environments map succeeded (deployments-fetch-failure-is-project-error) — MUST. A single unparseable `createdAt` or unresolvable `environmentId` drops only that ONE deployment, not the rest of the project's rows (row-created-at-validated, row-environment-name-required) — MUST. Every logged failure in this file passes through `console.error` with a message naming the project id or deployment id, so no failure here is silent (see Logging) — MUST. A failed project listing with no configured `projects` fallback is reported as `ok: false` (blind-spot-vs-empty-account) — MUST.
- **Offline / disconnected state**: every network call this file issues directly or through `pollProject` — the project listing and each per-project environments/deployments call — carries its own `AbortController` timeout bounded by `Math.min(callTimeoutMs, remaining)` against the shared overall deadline, so a fully offline or unresponsive Railway API degrades to the abort-then-retry-once-then-log path described under Budget, rather than hanging indefinitely — MUST. Beyond the ONE retry described above, this function performs no further retry of any kind on any failure; a project or listing call that has exhausted its retries, or that received a real error answer, is not retried again within the same call — SHOULD NOT be assumed to recover an offline call within the same poll cycle; the next scheduled poll cycle (external, `sync.ts`) is the only further retry.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `RAILWAY_API_TOKEN` | `string \| undefined` (field of `env`) | none — required for a non-no-op poll | The Railway API Bearer token, sent by the vendored `gqlPost` as `Authorization: Bearer <token>` on every GraphQL call. Absent or empty triggers the no-op branch (noop-missing-token). This file reads it only from the `env` object passed in, not from `process.env`. |
| `projects` | `readonly RailwayProject[] \| undefined` (field of `env`) | `[]` (via `env.projects ?? []`) | The configured fallback project list (`{ id, name }` pairs), used only when `listRailwayProjects` fails to enumerate live (fallback-to-configured-projects). The caller (`sync.ts`, external) passes `conn.railway.projects`, sourced from the DB integration config. |
| `overallBudgetMs` | `number \| undefined` (field of `env`) | `18_000` | The overall poll budget in milliseconds, counted from before the project-listing call starts (deadline-starts-before-listing). Per the source's own comment, deliberately shorter than the caller's `PROVIDER_POLL_TIMEOUT_MS` (20,000ms, `sync.ts`, external), and overridable "for tests/tuning." |
| `callTimeoutMs` | `number \| undefined` (field of `env`) | `6_000` (`RAILWAY_CALL_TIMEOUT_MS`) | The per-GraphQL-call time box, overridable so a test can exercise the retry "in milliseconds instead of waiting out a 6s box," per the source's own comment. |
| `RAILWAY_CALL_ATTEMPTS` (module constant) | `number` | `2` | Total attempts (one original plus one retry) for the project listing and for each project's poll, on our own timeout only. Not exposed on `env`. |
| `RAILWAY_PROJECT_CONCURRENCY` (module constant) | `number` | `5` | Fixed fan-out limit for per-project polls via `mapLimit`. Not exposed on `env`. |
| `RAILWAY_ENV_PAGE_SIZE` (module constant) | `number` | `200` | Pinned page size (the `first` variable) for the per-project `environments` query. Not exposed on `env`. |
| `RAILWAY_LOG_TAIL_LINES` (module constant) | `number` | `40` | Trailing line count `buildLogTail` keeps. Not exposed on `env`. |
| `RAILWAY_LOG_MAX_CHARS` (module constant) | `number` | `4_000` | Character cap `buildLogTail` applies to its joined tail. Not exposed on `env`. |
| `RAILWAY_LOG_FULL_LINES` (module constant) | `number` | `10_000` | The `limit` argument `fetchRailwayBuildLog` sends to the `buildLogs` query for the on-demand full read. Not exposed on `env`. |
| `RAILWAY_NO_BUILD_TEXT` (exported constant) | `string` | `(no build logs — the deployment has no associated build)` | The permanent placeholder both build-log fetchers return for a deployment Railway reports as never having had a build. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only issues outbound GraphQL `fetch` calls to Railway's API and returns in-memory `ProviderDeploy` rows or build-log strings.

## Localization

- **Data collected**: this file introduces one user-facing (details-pane-visible) hardcoded English string, `RAILWAY_NO_BUILD_TEXT`, persisted as a deploy's `error_text` by its caller (`enrich-deploy-errors.ts`, external) and surfaced to whoever views that deploy's details. It is not routed through any localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string, no key) | `(no build logs — the deployment has no associated build)` | Persisted `error_text` / returned build-log text for a Railway deployment with no associated build, shown in the details pane and the `GET /deployments/:id/log` response. |

Every other string this file emits (`console.error` diagnostic lines) is developer/operator-facing in server logs, not end-user-facing, and is documented under Logging rather than here.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; whether it runs at all is gated entirely by the presence of `RAILWAY_API_TOKEN` (noop-missing-token) and the shared cooldown registry (cooldown-gate-on-entry), both already documented under Behavioral Requirements and Configuration, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only observability output is the `console.error` lines documented under Logging.

## Privacy

- **Data collected**: this file transmits the caller-supplied Railway API token as a Bearer credential on every GraphQL call it makes (via the vendored `gqlPost`); it reads back deployment ids, timestamps, commit metadata (`commitHash`, `commitMessage`, `branch`, `repo`), and — for the two build-log fetchers — the raw text of a deployment's build log, which may itself contain whatever the monitored project's own build process printed. It collects no data from, and about, an end user of the monitored product.
- **Storage**: none in this file — it holds the token and every fetched row or log string only in local variables and the returned value for the duration of one call; persistence of deploy rows is the caller's responsibility (`storage.deploy.upsertDeployments`, `sync.ts`, external), and persistence of a build-log tail as `error_text` is `enrich-deploy-errors.ts`'s responsibility (external).
- **Transmission**: the token is sent as `Authorization: Bearer <token>` on every request to `backboard.railway.app` (the vendored `gqlPost`'s hardcoded GraphQL endpoint), over HTTPS. No other destination ever receives the token. Railway's own response, including commit metadata and build-log text, is received over the same HTTPS connection.
- **Retention**: not applicable to this file directly — it retains nothing after a call returns. How long a persisted deploy row or a persisted `error_text` value survives is governed by the caller's storage layer, external to this file.

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| Per-project environments fetch returned non-ok | error (`console.error`) | `` Railway environments <projectId> <status> `` |
| Per-project environments response carried GraphQL errors or no `environments` payload | error (`console.error`) | `` Railway environments <projectId> unusable: <messages, or "no environments payload"> `` |
| Per-project environments response returned a full page (possible truncation) | error (`console.error`) | `` Railway environments <projectId> returned a FULL page (<count>) — the env map may be truncated and deploys in unlisted environments will be dropped `` |
| Per-project deployments fetch returned non-ok | error (`console.error`) | `` Railway <projectId> <status> `` |
| Per-project deployments response carried GraphQL errors | error (`console.error`) | `` Railway <projectId> GraphQL errors: <messages> `` |
| A deployment's `createdAt` failed `toValidDate` | error (`console.error`) | `` Railway deployment <id> has unparseable createdAt <JSON-stringified value> — skipping `` |
| A deployment's `environmentId` was absent from the resolved map | error (`console.error`) | `` Railway deployment <id> references unknown environment <JSON-stringified environmentId> — skipping `` |
| A per-project fetch threw for a reason other than our own abort | error (`console.error`) | `` Railway fetch `` (plus the caught error, as a second argument) |
| A project timed out on every retry attempt | error (`console.error`) | `` Railway <projectId> timed out on all <RAILWAY_CALL_ATTEMPTS> attempts `` |
| A build-log fetch returned non-ok | error (`console.error`) | `` Railway buildLogs <deploymentId> <status> `` |
| A build-log fetch's response carried GraphQL errors other than the permanent "no associated build" case | error (`console.error`) | `` Railway buildLogs <deploymentId> GraphQL errors: <messages> `` |
| A build-log fetch threw | error (`console.error`) | `` Railway buildLogs <deploymentId> fetch failed `` (plus the caught error) |

A fully successful poll (every project fetched, no 429, budget not exhausted, no truncated environment page) produces no log output from this file at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this polling pattern would model `{ ok: Bool; deploys: [ProviderDeploy] }` as a `Sendable` `struct`, the bounded project fan-out as a `TaskGroup` capped to 5 concurrent child tasks (Swift's structured concurrency has no direct `mapLimit` equivalent, so the cap must be enforced by hand — e.g. releasing a semaphore-style gate before adding the next child task), and each GraphQL call's own-timeout-then-one-retry contract as a small helper that races a `Task` against `Task.sleep` cancellation and inspects whether the loss was ITS OWN cancellation (retry) versus a real thrown/decoded error (do not retry) — the same distinction this file's `aborted` flag preserves through `pollProject`'s return value.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the project fan-out with `kotlinx.coroutines`'s `Semaphore(5)` guarding a `coroutineScope { projects.map { async { ... } } }` (closer to `mapLimit`'s worker-pool shape than a raw `Dispatchers.IO.limitedParallelism`, which limits the dispatcher rather than one specific batch of work), and the own-timeout-then-one-retry contract via `withTimeoutOrNull` wrapping each call, retrying only on the `null` (timed-out) result and never on a caught `Exception` representing a real GraphQL/HTTP answer.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/fetch-railway.ts` as five plain exports on the Node status backend, consumed by `sync.ts`'s poll cycle, `enrich-deploy-errors.ts`, and `routes/deploy-logs.ts` (all external). It depends on two sibling in-repo modules (`./deploy-status` for `railwayPhases`, `./format` for `shortSha`/`commitFullMessage`, `./provider-deploy` for `toValidDate`/`ProviderDeploy`) and three exports of the vendored `@agentic-toolkit/deploy-platform` package (`util`'s `mapLimit`, `cooldown`'s `rateLimitedUntil`, `providers`'s `gqlPost`/`listRailwayProjects`/`RailwayProject`) — none of it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no Node-`Worker`-per-thread module-duplication concern the way the cooldown registry's own design note (external, `provider-cooldown.ts`) worries about; a Swift `actor` wrapping the cooldown slots would be a single shared instance regardless of which thread calls into it, so the cross-thread `SharedArrayBuffer`/`Atomics` mechanism this file's dependency uses has no direct analogue to port — an `actor` already gives the same guarantee for free.
- **WinUI 3**: a .NET port models `ProviderDeploy` as a `record` with the same fields this file populates (`Id`, `Platform`, `ProjectName`, `ProviderProjectId`, `BuildPhase` nullable, `DeployPhase`, `Environment`, `CommitHash`, `CommitMessage`, `Branch`, `CommitRepo`, `Url`, `CreatedAt`), issues each GraphQL call via `HttpClient.PostAsync` against `https://backboard.railway.app/graphql/v2` with a `CancellationTokenSource` per call whose `CancelAfter` is computed from the same shared deadline this file recomputes as `remaining` before each call — not `HttpClient.Timeout`, which is static per client. The bounded project fan-out is `Task.WhenAll` over a `SemaphoreSlim(5, 5)`-gated set of tasks (the direct `mapLimit` analogue: acquire before starting a project's `Task`, release in a `finally`). The own-timeout-then-one-retry contract is a small loop around each call that inspects whether the caught exception is a `TaskCanceledException` caused by ITS OWN `CancellationTokenSource` (retry, bounded by `RAILWAY_CALL_ATTEMPTS`) versus any other exception or a successfully-decoded GraphQL error body (do not retry). Railway's JSON bodies deserialize via `System.Text.Json` records shaped like `RailwayEnvironmentsResponse`/`RailwayDeploymentsResponse`/`RailwayBuildLogsResponse`; `toValidDate`'s accept-ISO-string-or-epoch-number-or-Date, reject-anything-else contract is worth porting explicitly, since `DateTime.Parse` throws by default rather than returning a sentinel the way `toValidDate` returns `null`. The shared cross-thread cooldown registry has no direct .NET analogue needed if the Windows App SDK host runs this poll on a single process without Node-style per-`Worker` module duplication; a `static` field guarded by `Interlocked`/`lock` suffices for a single-process host, but a multi-process host would need an out-of-process store (e.g. a named memory-mapped file) to preserve the "every caller sees the same cooldown" guarantee.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/fetch-railway.ts` |

## Design Decisions

- **Decision**: retry the project-listing call and each project's own poll exactly ONCE, and only when the retried attempt lost to OUR OWN timeout box — never on a real answer, including an error answer.
  **Rationale**: stated directly in the source comments on `RAILWAY_CALL_TIMEOUT_MS`/`RAILWAY_CALL_ATTEMPTS`: measured from inside the prod container, the per-project GraphQL query's latency tail is "INDEPENDENT per request, not sticky to a slow project," so a second attempt lands in the fast median; a longer single timeout instead "would make a genuinely stuck project hold its concurrency slot for that much longer, spending the overall budget on the one project least likely to answer." Retrying a real answer (including "Not Authorized") would just burn shared budget repeating a verdict that will not change.
  **Approved**: pending
- **Decision**: start the overall budget's deadline before the project-listing call, not after it.
  **Rationale**: stated directly in the source comment — the listing call is part of the poll and its time must count against the deadline; computing the deadline after the listing (an earlier version) let the worst case run past `guard`'s 20-second cap in `sync.ts`, which then discarded the whole (mostly successful) poll as unreachable.
  **Approved**: pending
- **Decision**: poll projects with bounded concurrency of exactly 5 (`RAILWAY_PROJECT_CONCURRENCY`), not serially and not fully unbounded.
  **Rationale**: stated directly in the source comment on the `mapLimit` call — a serial `for..of` loop made total time `N × 6s`, which "with enough projects and a degraded Railway API alone blows the cycle budget and wedges the whole monitor."
  **Approved**: pending
- **Decision**: when the overall budget is spent BEFORE a project's first attempt, mark the poll `skipped` (not an error); when it is spent before a RETRY the project already started, count that project as an `error`.
  **Rationale**: stated directly in the source comment — "Before the FIRST attempt this project was never polled — a partial, exactly as before. Before a RETRY it WAS polled and timed out, which is the provider failing us rather than a project we chose not to start."
  **Approved**: pending
- **Decision**: treat a project's environments-fetch failure as failing the WHOLE project (no rows at all), routed to the same error path as any other provider failure, rather than falling back to keying rows by the raw `environmentId`.
  **Rationale**: stated directly in the source comment — Railway is "the ONE platform whose board target carries the environment segment," so a project polled without its env map previously produced rows keyed by a raw UUID that "matched no roster entry in either index," making every one of that project's deploys invisible; "an absence of data" must never "render as health," so erroring the project routes it to the existing platform-unreachable debounce instead.
  **Approved**: pending
- **Decision**: pin an explicit, large page size (`RAILWAY_ENV_PAGE_SIZE = 200`) on the environments query rather than accepting the server's default, and log — but do not error — when a project's environment count reaches that pinned size.
  **Rationale**: stated directly in the source comment — the per-row environment-id-to-name lookup below is sound only because the map is COMPLETE; an unpinned page size would silently drop deploys in any environment that fell off an undersized default page, "one row at a time," and the drop and a genuine deletion are otherwise indistinguishable. Logging (not erroring) a full page is deliberate: the project answered normally and is reachable, so routing it to the platform-unreachable path would report the wrong kind of outage.
  **Approved**: pending
- **Decision**: keep the row's `url` as the Railway dashboard project link (`https://railway.com/project/<id>`), not the deployment's own `staticUrl`.
  **Rationale**: stated directly in the source comment — the `url` field is "the SOURCE link target," i.e. where a developer goes to debug the deploy, not the public/live URL; the public/live host is resolved elsewhere (from `liveHost`, stamped from config in `sync.ts`, external), so this file deliberately does not attempt to supply it.
  **Approved**: pending
- **Decision**: persist `RAILWAY_NO_BUILD_TEXT` as a real value for a deployment Railway reports as having no associated build, rather than leaving its error text `null`.
  **Rationale**: stated directly in the source comment on `RAILWAY_NO_BUILD_TEXT` — writing a real value "takes the row out of the enrichment candidate set," because otherwise the caller (`enrich-deploy-errors.ts`, external) would re-fetch and re-log the same "does not have an associated build" GraphQL error every cycle for a deployment that will never have logs.
  **Approved**: pending
- **Decision**: share one network call and one error-classification helper (`railwayBuildLogMessages`) between `fetchRailwayBuildLogTail` and `fetchRailwayBuildLog`, differing only in the requested `limit` and the shaping function applied to the result.
  **Rationale**: stated directly in the source comment — the tail (enrichment) and the full read (the on-demand log route) "differ only in how many lines they ask for and how they shape the result," and sharing the fetch and error classification means "the CLI and the details pane would [not] disagree about the same deployment" on whether it is buildless or transiently unreachable.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `railway-deployments.test.ts` exercises the no-op precondition, both branches of the blind-spot-vs-empty-account distinction, the happy-path listing-then-fetch, the configured-projects fallback, the budget-exhaustion partial, the environment-fetch-failure-drops-everything cases (GraphQL error and non-200), the unresolvable-environment row drop, the pinned page size, the full-page log, the genuinely-empty-environments case, the listing-spends-the-budget contract, and all four retry-vs-no-retry branches; `deploy-error-shaping.test.ts` exercises `buildLogTail`, `buildLogFull`, and both build-log fetchers' permanent-sentinel and transient-null branches; `provider-cooldown.test.ts` exercises the cross-call cooldown gate. `separation-of-concerns` passes: this file owns exactly one concern (fetching and mapping Railway deploys, and fetching/shaping Railway build logs); it delegates the GraphQL transport and its own 429 side-effect to `gqlPost`, project enumeration to `listRailwayProjects`, bounded fan-out to `mapLimit`, cooldown state to the shared registry, phase derivation to `railwayPhases`, and persistence entirely to its callers, none of which this file reimplements. `explicit-error-handling` passes: every failure path (a non-ok or GraphQL-error environments/deployments/buildLogs response, a thrown fetch, an unparseable `createdAt`, an unresolvable `environmentId`) is caught and logged with a distinguishing message, and is reflected in the returned `ok`/`deploys` shape or the `null`/`RAILWAY_NO_BUILD_TEXT` return value — nothing fails silently with no trace. `timeout-configuration` passes: the listing call, every per-project call, and every build-log call carry an `AbortController` deadline derived from the overall budget or the caller's own signal. `rate-limit-handling` passes: `fetchRailwayDeployments` checks `rateLimitedUntil("railway")` before doing any work, and the vendored `gqlPost` every one of its GraphQL calls goes through notes a 429 via `noteRateLimited`, honoring `Retry-After`. `retry-with-backoff` fails as literally written: this file DOES retry the listing call and each project's own poll once (see Design Decisions), but that retry fires immediately with no delay and no jitter — it is not exponential backoff, and no failure OTHER than our own timeout (a real error answer, or a build-log fetch failure) is retried at all within this function; the check's own wording requires "exponential backoff and jitter," which this file's one-retry-on-timeout-only design deliberately does not implement, for the reason recorded in Design Decisions above. `graceful-degradation` passes: a missing token is a full no-op rather than an error, a partial poll keeps and returns whatever rows were successfully fetched rather than discarding them, an unresolvable per-deployment field drops only that one deployment rather than the whole project, and every failure mode resolves to a well-formed `{ ok, deploys }` or `string | null` value rather than throwing out of an exported function.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
