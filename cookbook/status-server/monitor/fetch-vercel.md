---
id: c7b38706-a6bc-4ad6-852c-425a4ed11a27
title: Status Server Monitor Fetch Vercel
domain: agentictoolkit://cookbook/status-server/monitor/fetch-vercel
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Paginates Vercel's deployments API within a bounded budget into ProviderDeploy
  rows, then composes and fetches one deployment's failure reason and full build
  log on demand; a no-op absent a token, and cools down after a 429.
platforms:
- typescript
- web
tags:
- monitor
- vercel
- deploy
- fetcher
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related:
- agentictoolkit://cookbook/status-server/monitor/alerts
- agentictoolkit://cookbook/status-server/monitor/deploy-status
references:
- packages/web/packages/status-server/src/monitor/fetch-vercel.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/format.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/status-server/test/vercel-deploys-pagination.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-error-shaping.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/provider-cooldown.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Fetch Vercel

## Overview

`fetch-vercel.ts` (`packages/web/packages/status-server/src/monitor/fetch-vercel.ts`) is the Vercel provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external, invoked through its `guard` wrapper). It exports five functions in two groups. The poll group, `fetchVercelDeployments`, paginates Vercel's team-wide deployments list within a bounded overall budget and maps the results into `ProviderDeploy` rows (`./provider-deploy`, external) for the caller to upsert; per its own comment it shares "the same shape (and partial contract) as `fetchVercelProductionStates` and the Railway / Cloudflare fetchers" (`fetch-vercel-projects.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, all external) — a partial poll is handed back with `ok: false` rather than discarded. The on-demand group serves two human-facing reads that the poll never performs: `composeVercelDeployError`/`fetchVercelDeployError` fetch and shape the one-line failure reason for a single failed deployment (consumed by `enrich-deploy-errors.ts`, external, to fill in `error_text` once per failed deploy), and `composeVercelBuildLog`/`fetchVercelBuildLog` fetch and shape that deployment's complete build log (consumed by `routes/deploy-logs.ts`, external, behind `GET /deployments/:id/log`). Each pair splits a pure, directly-unit-tested "compose" half from an async "fetch" half that calls Vercel and delegates shaping to the compose half.

## Behavioral Requirements

### Signature and No-Op Preconditions

- **env-shape**: `fetchVercelDeployments` MUST accept one `env` object with optional fields `VERCEL_API_TOKEN?: string`, `VERCEL_TEAM_ID?: string`, and `overallBudgetMs?: number`, and MUST return a `Promise` resolving to `{ ok: boolean; deploys: ProviderDeploy[] }`.
- **noop-missing-token**: When `env.VERCEL_API_TOKEN` is falsy (absent or empty string), `fetchVercelDeployments` MUST return `{ ok: true, deploys: [] }` immediately, performing no network call.
- **cooldown-gate-on-entry**: Before any network call, `fetchVercelDeployments` MUST check `rateLimitedUntil("vercel")` (`@agentic-toolkit/deploy-platform/cooldown`, external) and, when it returns a truthy cooldown expiry, MUST return `{ ok: false, deploys: [] }` immediately, performing no network call. This check runs even when the caller's own `guard()` wrapper (`sync.ts`, external) has already checked the identical shared registry before invoking this function, as demonstrated by `provider-cooldown.test.ts`'s "vercel: a 429 poll opens the cooldown; the next poll never touches the network" test, which calls `fetchVercelDeployments` directly, twice, with no `guard` in between.

### Pagination Budget and Page Fetch

- **overall-budget-default**: `fetchVercelDeployments` MUST default `overallBudgetMs` to 12,000 (`DEPLOYS_OVERALL_BUDGET_MS`) when `env.overallBudgetMs` is not supplied.
- **deadline-computed-once**: The overall deadline (`Date.now() + overallBudgetMs`) MUST be computed exactly once, before the pagination loop's first iteration.
- **page-cap**: `fetchVercelDeployments` MUST NOT execute more than 5 (`MAX_PAGES`) page-fetch iterations in one call, regardless of remaining budget or whether the lookback window has been covered.
- **budget-exhaustion-before-page**: At the top of each pagination iteration, `fetchVercelDeployments` MUST compute `remaining` as the deadline minus the current time and, when `remaining <= 0`, MUST set the local `skipped` flag to `true` and stop iterating without starting that page's fetch.
- **per-page-call-timeout**: Each page's fetch MUST be aborted via `AbortSignal.timeout(Math.min(8_000, remaining))` (`DEPLOYS_CALL_TIMEOUT_MS` is 8,000), where `remaining` is recomputed immediately before that page's fetch call.
- **pagination-query-params**: Each page's request MUST target `https://api.vercel.com/v6/deployments` with the query parameter `limit` set to `"100"`; MUST include a `teamId` query parameter equal to `env.VERCEL_TEAM_ID` when it is set; and MUST include an `until` query parameter equal to the previous page's `pagination.next` value once a previous page supplied one (omitted on the first page).
- **auth-header**: Every deployments-list request MUST carry an `Authorization` header of `` Bearer <VERCEL_API_TOKEN> ``.
- **first-page-failure-definitive**: When the page-0 fetch resolves with `res.ok === false`, `fetchVercelDeployments` MUST return `{ ok: false, deploys: [] }` immediately, without attempting or considering any later page. Per the source's own comment, "Page 0 failing is definitive (nothing fetched)."
- **later-page-failure-keeps-partial**: When a fetch for page 1 or later resolves with `res.ok === false`, `fetchVercelDeployments` MUST set `skipped = true` and stop iterating, but MUST keep and map every deployment already collected from earlier successful pages rather than discarding them. Per the source's own comment, "A later page failing must NOT wipe the pages already fetched — keep them and hand back a partial."
- **rate-limit-note-on-429**: Whenever a page-fetch response has status `429` (on any page index), `fetchVercelDeployments` MUST call `noteRateLimited("vercel", res.headers.get("retry-after"))` before falling into the standard first-page/later-page non-ok handling for that response.
- **non-ok-logged**: Whenever a page-fetch response is not `ok`, `fetchVercelDeployments` MUST log `` Vercel API <status> `` via `console.error`.
- **thrown-fetch-first-page**: When the page-0 fetch call throws (including its own `AbortController` firing), `fetchVercelDeployments` MUST catch it, log `` Vercel deployments fetch failed: <message> `` via `console.error` (using the caught error's `message` when it is an `Error`, otherwise its string form), and return `{ ok: false, deploys: [] }`. Per the source's own comment, this is "concise, no stack: an aborted/stalled poll is expected transient noise."
- **thrown-fetch-later-page**: When a fetch call for page 1 or later throws, `fetchVercelDeployments` MUST log the identical message format as thrown-fetch-first-page, set `skipped = true`, and stop iterating while keeping every deployment already collected from earlier pages.
- **lookback-window-stop**: After a page's deployments are collected, `fetchVercelDeployments` MUST compute the minimum `created` value among that page's deployments (when the page returned at least one) and, once that minimum is a finite number no greater than `Date.now() - 1_800_000` (`DEPLOYS_LOOKBACK_MS` is 30 minutes), MUST stop iterating without fetching any further page. Per the source's own comment, "the poll only needs to see deploys new enough to still be in flight; older history is the reconcile's problem."
- **next-cursor-stop**: When a page's `pagination.next` value is falsy, `fetchVercelDeployments` MUST stop iterating (history exhausted), independent of whether the lookback window has been covered.
- **next-cursor-carry**: When a page's `pagination.next` value is truthy and neither the lookback window nor the page cap has stopped iteration, `fetchVercelDeployments` MUST set the cursor used for the next page's `until` parameter to that value.

### Row Mapping

- **row-created-at-validated**: For each raw deployment collected across all fetched pages, `fetchVercelDeployments` MUST compute `createdAt` via `toValidDate(d.created)` (`./provider-deploy`, external); when that call returns `null`, it MUST log `` Vercel deployment <uid> has unparseable created <JSON-stringified value> — skipping `` via `console.error` and MUST exclude that one deployment from the mapped rows, while still mapping every other collected deployment. Per the source's own comment, "an Invalid Date poisons the upsert (failing the whole cycle). Drop THAT deploy, keep the rest — the poll repeats."
- **row-id-prefix**: Each mapped row's `id` field MUST be the literal string `` vc_ `` concatenated with the raw deployment's `uid` field.
- **row-platform-literal**: Each mapped row's `platform` field MUST be the literal string `"vercel"`.
- **row-project-name**: Each mapped row's `projectName` field MUST be the raw deployment's `name` field.
- **row-provider-project-id**: Each mapped row's `providerProjectId` field MUST be the raw deployment's `projectId` field when present, otherwise `null`.
- **row-phases-delegated**: Each mapped row's `buildPhase` and `deployPhase` fields MUST be the two properties of the object returned by `vercelPhases(d.state, d.readySubstate, d.target ?? null)` (`./deploy-status`, external; see the Status Server Monitor Deploy Status recipe for that function's own contract), spread directly into the row with no additional transformation in this file.
- **row-environment**: Each mapped row's `environment` field MUST be the raw deployment's `target` field when present, otherwise `null`.
- **row-commit-hash**: Each mapped row's `commitHash` field MUST be `shortSha(d.meta?.githubCommitSha)` (`./format`, external — a 7-character truncation, or `null` when the source value is absent).
- **row-commit-message**: Each mapped row's `commitMessage` field MUST be `commitFullMessage(d.meta?.githubCommitMessage)` (`./format`, external — the whole message capped at 4,000 characters with trailing whitespace stripped, or `null` when the source value is absent or reduces to empty).
- **row-branch**: Each mapped row's `branch` field MUST be the raw deployment's `meta.githubCommitRef` field when present, otherwise `null`.
- **row-commit-repo**: Each mapped row's `commitRepo` field MUST be the string `` <githubCommitOrg>/<githubCommitRepo> `` when both `d.meta?.githubCommitOrg` and `d.meta?.githubCommitRepo` are truthy, otherwise `null`.
- **row-url**: Each mapped row's `url` field MUST be the raw deployment's `inspectorUrl` field when present; otherwise, when the raw deployment's `url` field is present, it MUST be that value prefixed with the literal `` https:// ``; otherwise it MUST be `null`.

### Return Value

- **deploys-array-partial-kept**: `fetchVercelDeployments` MUST return every successfully mapped row collected before pagination stopped, in the `deploys` array, regardless of whether the returned `ok` is `true` or `false`.
- **ok-composition**: For every branch that reaches the function's final return (i.e. excluding the two first-page-failure early returns), the returned `ok` field MUST be `!skipped` — `true` only when the page cap, a later-page failure, and a later-page throw all never set the `skipped` flag during that call.

### Deploy Error Composition and Fetch

- **compose-deploy-error-signature**: `composeVercelDeployError` MUST accept one object with optional fields `errorMessage?: string | null`, `errorStep?: string | null`, `readyStateReason?: string | null`, and MUST return `string | null` synchronously, performing no network call.
- **compose-deploy-error-reason**: `composeVercelDeployError` MUST compute its reason as `d.errorMessage?.trim() || d.readyStateReason?.trim() || null` — preferring a non-empty, trimmed `errorMessage` over a non-empty, trimmed `readyStateReason`, and returning `null` when neither yields a non-empty string.
- **compose-deploy-error-step-prefix**: When the computed reason is non-null and `d.errorStep?.trim()` is a non-empty string, `composeVercelDeployError` MUST return `` [<step>] <reason> ``; otherwise, when the reason is non-null, it MUST return the reason unprefixed.
- **fetch-deploy-error-noop-token**: `fetchVercelDeployError` MUST return `null` immediately, with no network call, when `env.VERCEL_API_TOKEN` is falsy.
- **fetch-deploy-error-cooldown**: `fetchVercelDeployError` MUST return `null` immediately, with no network call, when `rateLimitedUntil("vercel")` is truthy.
- **fetch-deploy-error-request**: `fetchVercelDeployError` MUST issue a `GET` request to `` https://api.vercel.com/v13/deployments/<encodeURIComponent(uid)> ``, MUST include a `teamId` query parameter equal to `env.VERCEL_TEAM_ID` when set, MUST carry the same `Authorization: Bearer <token>` header as auth-header, and MUST abort the request using the caller-supplied `signal` when provided, or `AbortSignal.timeout(8_000)` otherwise.
- **fetch-deploy-error-429**: When the response status is `429`, `fetchVercelDeployError` MUST call `noteRateLimited("vercel", res.headers.get("retry-after"))` and return `null`, performing no further processing of that response.
- **fetch-deploy-error-non-ok**: When the response is not `ok` and not a `429`, `fetchVercelDeployError` MUST log `` Vercel deployment <uid> detail <status> `` via `console.error` and return `null`.
- **fetch-deploy-error-success**: When the response is `ok`, `fetchVercelDeployError` MUST parse it as JSON and return `composeVercelDeployError` applied to that parsed body.
- **fetch-deploy-error-thrown**: When the fetch call throws (including the request's own abort firing), `fetchVercelDeployError` MUST catch it, log `` Vercel deployment <uid> detail fetch failed: <message> `` via `console.error`, and return `null`.

### Build Log Composition and Fetch

- **compose-build-log-filter**: `composeVercelBuildLog` MUST accept an array of objects each with an optional `payload?: { text?: string | null } | null` field and MUST keep, in their original array order, only the entries whose `payload.text` is a string that is non-empty after trimming.
- **compose-build-log-trim**: For each kept entry, `composeVercelBuildLog` MUST strip only trailing whitespace from its `payload.text` (via the pattern one-or-more-whitespace-characters anchored at the end of the string) before joining, leaving leading and internal whitespace unchanged.
- **compose-build-log-join**: `composeVercelBuildLog` MUST join the kept, trimmed lines with a newline character and return the result; when zero entries qualify, it MUST return `null` rather than an empty string.
- **fetch-build-log-noop-token**: `fetchVercelBuildLog` MUST return `null` immediately, with no network call, when `env.VERCEL_API_TOKEN` is falsy.
- **fetch-build-log-cooldown**: `fetchVercelBuildLog` MUST return `null` immediately, with no network call, when `rateLimitedUntil("vercel")` is truthy.
- **fetch-build-log-request**: `fetchVercelBuildLog` MUST issue a `GET` request to `` https://api.vercel.com/v3/deployments/<encodeURIComponent(uid)>/events `` with query parameters `builds=1`, `direction=forward`, and `limit=-1`; MUST include a `teamId` query parameter equal to `env.VERCEL_TEAM_ID` when set; MUST carry the same `Authorization: Bearer <token>` header as auth-header; and MUST abort the request using the caller-supplied `signal` when provided, or `AbortSignal.timeout(20_000)` (`BUILD_LOG_CALL_TIMEOUT_MS`) otherwise.
- **fetch-build-log-429**: When the response status is `429`, `fetchVercelBuildLog` MUST call `noteRateLimited("vercel", res.headers.get("retry-after"))` and return `null`.
- **fetch-build-log-non-ok**: When the response is not `ok` and not a `429`, `fetchVercelBuildLog` MUST log `` Vercel deployment <uid> events <status> `` via `console.error` and return `null`.
- **fetch-build-log-success**: When the response is `ok`, `fetchVercelBuildLog` MUST parse it as JSON and return `composeVercelBuildLog` applied to that body when it is an array, or applied to an empty array when the parsed body is not an array — a non-array response body MUST NOT throw.
- **fetch-build-log-thrown**: When the fetch call throws, `fetchVercelBuildLog` MUST catch it, log `` Vercel deployment <uid> events fetch failed: <message> `` via `console.error`, and return `null`.

## Appearance

Not applicable — this is a server-side Vercel deployment-polling and on-demand-detail-fetching module, not a visual component.

## States

Not applicable — this is a server-side Vercel deployment-polling and on-demand-detail-fetching module, not a visual component; its runtime state (no-op, cooling down, paginating, budget-exhausted, per-detail fetch) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side Vercel deployment-polling and on-demand-detail-fetching module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-fetch-vercel-001 | noop-missing-token, env-shape | `fetchVercelDeployments({})` | Resolves `{ ok: true, deploys: [] }` with no `fetch` call — traced directly to the source's `if (!env.VERCEL_API_TOKEN) return { ok: true, deploys: [] };` guard, which runs before any other statement |
| status-server-monitor-fetch-vercel-002 | rate-limit-note-on-429, cooldown-gate-on-entry | `fetchVercelDeployments({ VERCEL_API_TOKEN: 'tok' })` called once against a `fetch` mock that resolves HTTP 429 with a `retry-after: 30` header, then called a second time immediately with the same token | The first call resolves `ok: false` and `fetch` is called exactly once; the second call also resolves `ok: false` and `fetch` is still called exactly once (no new request) — `provider-cooldown.test.ts` › "vercel: a 429 poll opens the cooldown; the next poll never touches the network" |
| status-server-monitor-fetch-vercel-003 | pagination-query-params, next-cursor-carry, deploys-array-partial-kept, ok-composition | Page 1 returns 100 deployments with `pagination.next: 123`; page 2 returns 35 more with `pagination.next: null`; called with a valid token and no `overallBudgetMs` | `out.ok === true`; `out.deploys` has length 135 (the whole burst, not just the first page); exactly 2 `fetch` calls are made, and the second call's URL contains `until=123` — `vercel-deploys-pagination.test.ts` › "pages past the first 100 so a burst is fully visible" |
| status-server-monitor-fetch-vercel-004 | lookback-window-stop | Page 1 returns two deployments, one 45 minutes old and one 1 minute old, with `pagination.next: 999`; a second page would supply more deployments if fetched | `out.ok === true`; only 1 `fetch` call is made — the 45-minute-old deployment's age exceeds the 30-minute lookback, stopping pagination before the second page — `vercel-deploys-pagination.test.ts` › "stops once the lookback window is covered rather than walking all history" |
| status-server-monitor-fetch-vercel-005 | budget-exhaustion-before-page, ok-composition, deploys-array-partial-kept | Every page returns one deployment 1 minute old with `pagination.next: 1` (never satisfying the lookback window and always offering another page); called with `overallBudgetMs: 1` and each `fetch` call artificially delayed 5ms | `out.ok === false`; `out.deploys.length` is 0 or more (never throws) — only the shared overall budget, not the lookback or page cap, stops an otherwise-endless pagination — `vercel-deploys-pagination.test.ts` › "returns a partial with ok:false when the budget is spent mid-pagination" |
| status-server-monitor-fetch-vercel-006 | first-page-failure-definitive, non-ok-logged | `fetch` resolves HTTP 500 on the very first call; called with a valid token | Resolves exactly `{ ok: false, deploys: [] }` — `vercel-deploys-pagination.test.ts` › "a FIRST-page failure is definitive (nothing fetched → unreachable)" |
| status-server-monitor-fetch-vercel-007 | later-page-failure-keeps-partial, row-id-prefix, deploys-array-partial-kept | Page 1 succeeds with one deployment `uid: 'kept'` and `pagination.next: 42`; page 2 resolves HTTP 500 | `out.ok === false`; `out.deploys.map(d => d.id)` equals `['vc_kept']` — the already-fetched page is kept, not wiped, by the later failure — `vercel-deploys-pagination.test.ts` › "a LATER-page failure keeps the pages already fetched" |
| status-server-monitor-fetch-vercel-008 | row-created-at-validated | One page returns a deployment whose `created` field is not a finite number or parseable date (e.g. `NaN` or a garbage string) alongside one deployment with a valid `created` | The valid deployment appears in `out.deploys`; the invalid one is excluded; `console.error` is called with a message containing `has unparseable created` and that deployment's `uid` — traced to the `toValidDate` boundary-validation branch in the row-mapping loop |
| status-server-monitor-fetch-vercel-009 | compose-deploy-error-step-prefix | `composeVercelDeployError({ errorMessage: 'Command "next build" exited with 1', errorStep: 'buildStep' })` | Returns the exact string `` [buildStep] Command "next build" exited with 1 `` — `deploy-error-shaping.test.ts` › "prefixes the failing build step onto the error message" |
| status-server-monitor-fetch-vercel-010 | compose-deploy-error-reason | `composeVercelDeployError({ errorMessage: 'boom' })` | Returns `'boom'` — `deploy-error-shaping.test.ts` › "uses the error message alone when no step is named" |
| status-server-monitor-fetch-vercel-011 | compose-deploy-error-reason | `composeVercelDeployError({ readyStateReason: 'deployment blocked' })` | Returns `'deployment blocked'` — `deploy-error-shaping.test.ts` › "falls back to readyStateReason when errorMessage is absent" |
| status-server-monitor-fetch-vercel-012 | compose-deploy-error-reason | `composeVercelDeployError({ errorMessage: '   ', readyStateReason: '' })` and `composeVercelDeployError({})` | Both return `null` — `deploy-error-shaping.test.ts` › "returns null when there is no reason at all (empty/whitespace)" |
| status-server-monitor-fetch-vercel-013 | compose-build-log-filter, compose-build-log-join | `composeVercelBuildLog([{ payload: { text: 'installing' } }, { payload: { text: 'building' } }, { payload: { text: 'failed' } }])` | Returns `'installing\nbuilding\nfailed'` — `deploy-error-shaping.test.ts` › "joins every event that carries text, in order" |
| status-server-monitor-fetch-vercel-014 | compose-build-log-filter | `composeVercelBuildLog` given a mix of events including one with no `payload`, one `{ type: 'deployment-state', payload: null }`, and two with text | Returns only the two events' text, joined, in original order, skipping the textless entries — `deploy-error-shaping.test.ts` › "skips events with no text (deployment-state, metrics)" |
| status-server-monitor-fetch-vercel-015 | compose-build-log-trim | `composeVercelBuildLog([{ payload: { text: 'one\n' } }, { payload: { text: 'two\n' } }])` | Returns `'one\ntwo'`, not `'one\n\ntwo\n'` — `deploy-error-shaping.test.ts` › "trims each event's trailing newline so the join does not double-space" |
| status-server-monitor-fetch-vercel-016 | compose-build-log-join | `composeVercelBuildLog` given 500 events each carrying distinct text | Returns all 500 lines joined, in order, with none dropped or truncated — `deploy-error-shaping.test.ts` › "keeps a log far longer than the enrichment tail — nothing is truncated" |
| status-server-monitor-fetch-vercel-017 | compose-build-log-join | `composeVercelBuildLog([])` and `composeVercelBuildLog` given only textless/blank-text events | Both return `null` — `deploy-error-shaping.test.ts` › "returns null when nothing carried text" |
| status-server-monitor-fetch-vercel-018 | fetch-deploy-error-429, fetch-deploy-error-non-ok | `fetchVercelDeployError('d1', { VERCEL_API_TOKEN: 'tok' })` against a `fetch` mock resolving HTTP 429 with a `retry-after` header, then against one resolving HTTP 500 (separate call) | Both resolve `null`; the 429 case additionally causes the shared cooldown registry's `vercel` slot to become rate-limited, verifiable via a subsequent `rateLimitedUntil('vercel')` returning a truthy expiry — traced directly to the `if (res.status === 429) { noteRateLimited(...); return null; }` branch, mirroring rate-limit-note-on-429's per-call behavior |
| status-server-monitor-fetch-vercel-019 | fetch-build-log-success | `fetchVercelBuildLog('d1', { VERCEL_API_TOKEN: 'tok' })` against a `fetch` mock resolving `ok: true` with a JSON body that is an object (not an array), e.g. `{ error: 'not an array' }` | Resolves `null` rather than throwing — traced directly to `composeVercelBuildLog(Array.isArray(body) ? (body as VercelBuildEvent[]) : [])`, which substitutes an empty array for a non-array body |

## Edge Cases

- **Null and empty input**: `env.VERCEL_API_TOKEN` absent or an empty string MUST produce the `{ ok: true, deploys: [] }` no-op (noop-missing-token) — MUST. `env.VERCEL_TEAM_ID` absent MUST omit the `teamId` query parameter from every request rather than sending it empty (pagination-query-params, fetch-deploy-error-request, fetch-build-log-request) — MUST. A page whose `deployments` field is absent MUST be treated as zero deployments via `body.deployments ?? []`, and a page with zero deployments MUST leave the lookback-window-stop comparison unevaluated for that page (no deployments to take a minimum `created` from) while still consulting `pagination.next` — MUST. A raw deployment with no `meta` object at all MUST map `commitHash`, `commitMessage`, `branch`, and `commitRepo` all to `null` (row-commit-hash, row-commit-message, row-branch, row-commit-repo) — MUST.
- **Boundary values**: exactly 5 (`MAX_PAGES`) page-fetch iterations may run in one call; a would-be 6th iteration never starts regardless of remaining budget or an uncovered lookback window (page-cap) — MUST. A page's oldest deployment `created` value exactly equal to `Date.now() - 1_800_000` satisfies the `<=` comparison in lookback-window-stop and stops pagination — MUST, per the source's literal `<=` operator. `limit=100` is Vercel's fixed page size for every request in this file's pagination loop and is never varied — MUST.
- **Concurrent access**: this function has no internal mutable state shared across separate calls to `fetchVercelDeployments`, `fetchVercelDeployError`, or `fetchVercelBuildLog` — each call's `list`, `deadline`, `skipped`, and `until` (for the poll) are freshly created local variables. The provider-cooldown registry these functions read and write (`rateLimitedUntil`, `noteRateLimited`, `@agentic-toolkit/deploy-platform/cooldown`, external) IS shared cross-thread by design — that module's own header comment states it uses a `SharedArrayBuffer` with `Atomics` reads/writes because the monitor cycle and the API thread's `enrich-deploy-errors.ts`/`routes/deploy-logs.ts` callers run on different Node `Worker` threads and must agree on the same cooldown state. A 429 noted by any one of these functions is visible to every other caller's next `rateLimitedUntil("vercel")` check, by construction of the shared registry — MUST.
- **Error states**: a non-`ok` page-0 response is definitive and returns `{ ok: false, deploys: [] }` (first-page-failure-definitive) — MUST. A non-`ok` later-page response or a thrown fetch on any page keeps every already-collected page's mapped rows and reports `ok: false` (later-page-failure-keeps-partial, thrown-fetch-later-page) — MUST. `fetchVercelDeployError` and `fetchVercelBuildLog` both collapse every one of a missing token, an active cooldown, a 429, a non-`ok` response, and a thrown fetch to the identical `null` return, with no distinct error signal reaching their callers — MUST, per each function's own doc comment stating the caller renders `null` as "no log available" / retries enrichment next cycle rather than treating it as an exceptional error.
- **Offline / disconnected state**: every network call in this file — each page fetch, the deploy-error fetch, and the build-log fetch — carries its own `AbortSignal` timeout (per-page-call-timeout, fetch-deploy-error-request's 8-second default, fetch-build-log-request's 20-second default), so a fully offline or unresponsive Vercel API degrades to the same abort-then-log-then-`null`/partial path as any other unreachable-host failure rather than hanging indefinitely — MUST. This file implements no retry of any kind on any failure path; the poll's next cycle (external, `sync.ts`'s cadence) or the next human request (for the on-demand pair) is the only retry — SHOULD NOT be assumed to recover an offline call within the same invocation; see the retry-with-backoff Compliance result and Design Decisions below.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `VERCEL_API_TOKEN` | `string \| undefined` (field of `env`) | none — required for a non-no-op call | The Vercel API Bearer token, read only from the `env` object passed in by each function; none of the three exported async functions reads `process.env` itself. |
| `VERCEL_TEAM_ID` | `string \| undefined` (field of `env`) | none — `teamId` query parameter omitted when absent | The Vercel team id, added as a `teamId` query parameter to every request this file issues when set. |
| `overallBudgetMs` | `number \| undefined` (field of `env`, `fetchVercelDeployments` only) | `12_000` (`DEPLOYS_OVERALL_BUDGET_MS`) | The pagination loop's overall wall-clock budget, computed once before the first page fetch (deadline-computed-once). Per the source's own comment, "self-bound like the projects poll: sync's `guard` abandons a provider at 20s WITHOUT cancelling it, so an unbounded loop keeps paginating behind the next cycle." |
| `signal` | `AbortSignal \| undefined` (parameter, `fetchVercelDeployError` and `fetchVercelBuildLog` only) | `AbortSignal.timeout(8_000)` for `fetchVercelDeployError`; `AbortSignal.timeout(20_000)` for `fetchVercelBuildLog` | A caller-supplied abort signal for the single on-demand request; both callers (`enrich-deploy-errors.ts`, `routes/deploy-logs.ts`, both external) supply their own shared-deadline signal in practice. |
| `DEPLOYS_CALL_TIMEOUT_MS` (module constant) | `number` | `8_000` | Per-page call timeout inside `fetchVercelDeployments`'s pagination loop; not exposed on `env`. Per the source's own comment, "Vercel's `fetch` has NO default timeout — without this an unresponsive API hangs the poll indefinitely." |
| `DEPLOYS_LOOKBACK_MS` (module constant) | `number` | `1_800_000` (30 minutes) | How far back a poll must see before it may stop paginating (lookback-window-stop); not exposed on `env`. Per the source's own comment, derived from an observed 225-deployment burst whose newest 100 spanned only 74 seconds, which otherwise left older deploys invisible to the poll for roughly 9 minutes. |
| `MAX_PAGES` (module constant) | `number` | `5` | Hard page cap (page-cap); not exposed on `env`. Per the source's own comment, "so a pathological history can't spin." |
| `BUILD_LOG_CALL_TIMEOUT_MS` (module constant) | `number` | `20_000` | Default abort timeout for `fetchVercelBuildLog` when no `signal` is supplied; not exposed on `env`. Per the source's own comment, "give it more room than the 8s poll timeout without letting it hang." |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only issues outbound `fetch` calls to Vercel's REST API and returns in-memory `ProviderDeploy` rows or strings.

## Localization

- **error-text-not-localized**: `composeVercelDeployError`'s returned string (surfaced by `enrich-deploy-errors.ts`, external, into the persisted `error_text` field the details pane and CLI display, per that file's own doc comment) is composed verbatim from Vercel's own `errorMessage`, `readyStateReason`, and `errorStep` fields, with no localization mechanism of any kind applied by this file — whatever language Vercel's API returns those fields in is what the end user sees.
- **build-log-not-localized**: `composeVercelBuildLog`'s returned string (surfaced by `routes/deploy-logs.ts`, external, as the `log` field of its JSON response, read by a human debugging a failed build) is likewise composed verbatim from Vercel's build-event `payload.text` values, with no localization mechanism of any kind applied by this file.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; whether each function performs a network call at all is gated entirely by the presence of `VERCEL_API_TOKEN` (noop-missing-token, fetch-deploy-error-noop-token, fetch-build-log-noop-token) and the shared cooldown registry (cooldown-gate-on-entry, fetch-deploy-error-cooldown, fetch-build-log-cooldown), both already documented under Behavioral Requirements, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only observability output is the `console.error` lines documented under Logging.

## Privacy

- **Data collected**: this file transmits the caller-supplied Vercel API token as a Bearer credential on every request it makes; it reads back deployment ids, timestamps, states, and commit metadata (`githubCommitSha`, `githubCommitMessage`, `githubCommitRef`, `githubCommitOrg`/`githubCommitRepo`) that Vercel itself already recorded from the account's own deploys, plus, for the on-demand functions, a deployment's failure reason and its complete build log — which, being raw build stdout/stderr, may itself contain whatever the build process printed (including a secret accidentally logged by the monitored project's own build, though this file neither inspects nor redacts build-log content). It collects no data from, and about, an end user of the monitored product itself.
- **Storage**: none in this file — it holds the token and every fetched value only in local variables and the returned `deploys` array or string for the duration of one call; persistence of the poll's rows is entirely the caller's responsibility (`storage.deploy.upsertDeployments`, `sync.ts`, external), and the on-demand functions' results are not persisted by this file at all (the build log route reads from Vercel fresh on every request; `enrich-deploy-errors.ts` persists the composed error text itself, external to this file).
- **Transmission**: the token is sent as `Authorization: Bearer <token>` on every request to `api.vercel.com`, over HTTPS (every URL in this file is a hardcoded `https://` literal); no other destination ever receives the token. Vercel's own responses, including commit metadata, failure reasons, and build-log text, are received over the same HTTPS connections.
- **Retention**: not applicable to this file directly — it retains nothing after any call returns; how long the poll's mapped rows persist once upserted, and whether an enriched `error_text` is ever cleared, is governed entirely by the caller's storage layer, external to this file.

## Logging

This file uses plain `console.error` calls with no structured subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| A page-fetch response is not `ok` | error (`console.error`) | `` Vercel API <status> `` |
| A page fetch call threw | error (`console.error`) | `` Vercel deployments fetch failed: <message> `` |
| A deployment's `created` failed `toValidDate` | error (`console.error`) | `` Vercel deployment <uid> has unparseable created <JSON-stringified value> — skipping `` |
| `fetchVercelDeployError`'s detail response is not `ok` (and not 429) | error (`console.error`) | `` Vercel deployment <uid> detail <status> `` |
| `fetchVercelDeployError`'s fetch call threw | error (`console.error`) | `` Vercel deployment <uid> detail fetch failed: <message> `` |
| `fetchVercelBuildLog`'s events response is not `ok` (and not 429) | error (`console.error`) | `` Vercel deployment <uid> events <status> `` |
| `fetchVercelBuildLog`'s fetch call threw | error (`console.error`) | `` Vercel deployment <uid> events fetch failed: <message> `` |

A fully successful poll or a fully successful on-demand fetch produces no log output from this file at any level.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this polling pattern would model the poll's return shape as a `Sendable` `struct { ok: Bool; deploys: [ProviderDeploy] }`, the pagination loop as a plain `while` loop over an `AsyncSequence`-free `URLSession` request per iteration (Vercel's cursor-based `pagination.next` has no built-in Swift analogue the way `URLSession` handles `Link`-header pagination), and each request's timeout via a per-request `URLRequest.timeoutInterval` derived from the same recomputed `remaining` budget this file uses, rather than one static session-wide timeout.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the pagination loop with a `while` loop over `kotlinx.coroutines`, computing `remaining` before each page the same way, and each request's timeout via `withTimeoutOrNull` composed with the shared overall deadline — Ktor/OkHttp's own per-call timeout config is static per client rather than computed per call the way this file recomputes `remaining` before every page and every on-demand request.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/fetch-vercel.ts` as three plain async functions (plus two pure helpers) on the Node status backend, imported by `sync.ts`'s poll cycle, `enrich-deploy-errors.ts`, and `routes/deploy-logs.ts` (all external); it depends on two sibling in-repo modules (`./deploy-status`, `./format`, `./provider-deploy`) and two exports of the vendored `@agentic-toolkit/deploy-platform` package (`cooldown`'s `noteRateLimited`/`rateLimitedUntil`) — none of it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no Node-`Worker`-per-thread module-duplication concern the way the cooldown registry's own design note (external, `provider-cooldown.ts`) worries about; a Swift `actor` wrapping the cooldown slots would be a single shared instance regardless of which thread calls into it, so the cross-thread `SharedArrayBuffer`/`Atomics` mechanism this file's dependency uses has no direct analogue to port — an `actor` already gives the same guarantee for free.
- **WinUI 3**: a .NET port models `ProviderDeploy` as a `record` with the same fields this file populates (`Id`, `Platform`, `ProjectName`, `ProviderProjectId` nullable, `BuildPhase` nullable, `DeployPhase`, `Environment`, `CommitHash`, `CommitMessage`, `Branch`, `CommitRepo`, `Url`, `CreatedAt`), the pagination loop as a `while` loop issuing `HttpClient.GetAsync` calls with a `CancellationTokenSource` per call whose `CancelAfter` is computed from the same shared deadline this file recomputes as `remaining` before every page — not `HttpClient.Timeout`, which is static per client and cannot express "whatever time is left in the overall budget." Vercel's JSON bodies deserialize via `System.Text.Json` records shaped like `VercelDeployment`/`VercelDeploymentsBody`/`VercelDeploymentDetail`/`VercelBuildEvent`; the boundary-validation pattern in `toValidDate` (accept ISO string, epoch number, or `DateTime`, reject anything that fails to parse, returning a sentinel rather than throwing) is worth porting explicitly, since `DateTime.Parse` throws by default. The on-demand `fetchVercelDeployError`/`fetchVercelBuildLog` pair maps to two `HttpClient` calls each guarded by a caller-supplied `CancellationToken` (mirroring the optional `signal` parameter) falling back to a fixed `CancelAfter` when the caller supplies none. The shared cross-thread cooldown registry (`SharedArrayBuffer`/`Atomics` in the source) has no direct .NET analogue needed if the Windows App SDK host runs this poll on a single process without a Node-style per-`Worker` module duplication; a `static` field guarded by `Interlocked`/`lock` suffices for a single-process host, but a multi-process host would need an out-of-process store (e.g. a named memory-mapped file or a shared cache) to preserve the "every caller sees the same cooldown" guarantee this file's dependency provides.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/fetch-vercel.ts` |

## Design Decisions

- **Decision**: default `overallBudgetMs` to 12,000ms and compute the deadline once, before the pagination loop's first iteration, rather than per-page.
  **Rationale**: stated directly in the source comment — "self-bound like the projects poll: sync's `guard` abandons a provider at 20s WITHOUT cancelling it, so an unbounded loop keeps paginating behind the next cycle. Observed cost is ~0.75s for 3 pages," meaning the 12-second figure is deliberately well under the caller's 20-second `guard` timeout so this function's own partial-result path fires first.
  **Approved**: pending
- **Decision**: set the lookback window to 30 minutes (`DEPLOYS_LOOKBACK_MS`) as the stopping condition for pagination, rather than stopping after a fixed number of pages or a fixed count of deployments.
  **Rationale**: stated directly in the source comment — one page is only the newest 100 deployments team-wide, and a measured 225-deployment burst (135 projects, a push touching a shared path rebuilding ~90 sites at once) had its newest 100 span just 74 seconds; every older deploy in that burst was then permanently invisible to the poll, leaving rows stuck reading `building` for roughly 9 minutes until the by-id reconcile caught them at 10 per 60-second tick. 30 minutes was chosen because it "spans any burst this repo can produce."
  **Approved**: pending
- **Decision**: cap pagination at exactly 5 pages (`MAX_PAGES`, 500 deployments) regardless of budget or lookback state.
  **Rationale**: stated directly in the source comment — "so a pathological history can't spin." This is a hard ceiling layered on top of, not instead of, the budget and lookback stopping conditions.
  **Approved**: pending
- **Decision**: on a page-0 failure (non-ok response or thrown fetch), return `{ ok: false, deploys: [] }` immediately, while a page-1-or-later failure instead keeps every already-mapped row and reports `ok: false`.
  **Rationale**: stated directly in the source comment — "Page 0 failing is definitive (nothing fetched). A later page failing must NOT wipe the pages already fetched — keep them and hand back a partial." The same `ok:false`-with-partial-`deploys` contract is stated to be shared with `fetchVercelProductionStates` and the Railway/Cloudflare fetchers (all external).
  **Approved**: pending
- **Decision**: check `rateLimitedUntil("vercel")` at the top of `fetchVercelDeployments`, `fetchVercelDeployError`, and `fetchVercelBuildLog` themselves, even though the poll's caller (`sync.ts`'s `guard` wrapper, external) already performs the identical check before invoking `fetchVercelDeployments` during the normal poll cycle.
  **Rationale**: not spelled out in an inline comment on these specific checks, but demonstrated as deliberate by the test suite — `provider-cooldown.test.ts`'s "vercel: a 429 poll opens the cooldown; the next poll never touches the network" test calls `fetchVercelDeployments` directly, twice, with no `guard` wrapper in between, and asserts the second call makes no additional request. `fetchVercelDeployError` and `fetchVercelBuildLog` are never wrapped by `guard` at all (their callers, `enrich-deploy-errors.ts` and `routes/deploy-logs.ts`, call them directly), so the cooldown check inside each function is these two functions' only protection against hammering an already-throttled account.
  **Approved**: pending
- **Decision**: give `fetchVercelBuildLog` a longer default abort timeout (20,000ms) than the 8,000ms used for the poll's page fetches and for `fetchVercelDeployError`.
  **Rationale**: stated directly in the source comment on `BUILD_LOG_CALL_TIMEOUT_MS` — "a full build log is far bigger than the single-field reads, and is fetched on demand by a human waiting on the answer — give it more room than the 8s poll timeout without letting it hang."
  **Approved**: pending
- **Decision**: `composeVercelBuildLog` keeps every qualifying line with no truncation, unlike a bounded tail.
  **Rationale**: stated directly in the source comment — "deliberately NOT truncated (unlike the Railway tail used for enrichment): this feeds an on-demand read, and a build failure's cause is often hundreds of lines above the final 'exited with 1' — the reason the one-line `error_text` is not enough to diagnose a failure from."
  **Approved**: pending
- **Decision**: implement no retry of any kind for a failed page fetch, a failed on-demand detail fetch, a failed build-log fetch, or a 429 — each failure is logged (or, for a 429, cooled down) once and the call moves on or returns.
  **Rationale**: not stated in an inline comment as a deliberate tradeoff, but demonstrated as a fact of the code: no fetch call in this file is wrapped in any retry loop. Recorded here per this recipe's authoring rules as a fact to state, not a gap to excuse — the poll relies entirely on its next cycle (external, `sync.ts`'s cadence) as its retry mechanism, `fetchVercelDeployError` relies on `enrich-deploy-errors.ts` re-attempting an un-enriched row on a later cycle per its own doc comment ("enrichment simply retries next cycle"), and `fetchVercelBuildLog` relies on the human simply asking again.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [pagination-support](agenticdevelopercookbook://compliance/access-patterns#pagination-support) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` is partial: `vercel-deploys-pagination.test.ts` exercises `fetchVercelDeployments`'s pagination, lookback-stop, budget-exhaustion, and first/later-page failure contracts directly; `provider-cooldown.test.ts` exercises its cross-call cooldown gate; `deploy-error-shaping.test.ts` exercises both pure compose halves (`composeVercelDeployError`, `composeVercelBuildLog`) directly and exhaustively. However, neither `fetchVercelDeployError` nor `fetchVercelBuildLog` — the two async network-calling wrappers around those compose halves — has a test anywhere in `packages/web/packages/status-server/test/` that invokes them directly; their request construction, 429/non-ok/thrown-error branches, and default-timeout behavior are exercised only indirectly, if at all, through whatever integration coverage exists for their callers (`enrich-deploy-errors.ts`, `routes/deploy-logs.ts`). `separation-of-concerns` passes: this file owns exactly one concern per exported symbol (paginated listing-and-mapping, single-deployment error composition, single-deployment build-log composition); it delegates phase computation to `vercelPhases`, commit formatting to `./format`, timestamp validation to `toValidDate`, and cooldown state to the shared registry, none of which it reimplements. `explicit-error-handling` passes: every failure path (non-ok response, thrown fetch, unparseable `created`, 429) is caught and logged via `console.error` with a distinguishing message, and is reflected in the returned value's shape — nothing fails silently with no trace. `timeout-configuration` passes: every one of the poll's page fetches and both on-demand fetches carries an `AbortSignal` deadline. `rate-limit-handling` passes: a 429 from any of the three network-calling functions is recorded via `noteRateLimited` honoring `Retry-After`, and `rateLimitedUntil` is checked before each one does any work. `pagination-support` passes: `fetchVercelDeployments` follows Vercel's `pagination.next` cursor across up to 5 pages, bounded independently by a lookback window, an overall time budget, and a hard page cap. `retry-with-backoff` fails as written: no failed call of any kind is retried within this file, a deliberate tradeoff recorded as fact in Design Decisions above, not a defended pass. `graceful-degradation` passes: a missing token is a full no-op (or a `null` return) rather than an error, a partial poll keeps and returns whatever rows were successfully fetched, and every failure mode of all three async functions resolves to a well-formed value rather than throwing out of the function.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
