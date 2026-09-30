<!-- leaf: implement-status-server-monitor-fetch/vercel--part-2 · source: status-server-monitor-fetch-vercel.md -->

# Status Server Monitor Fetch Vercel — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-fetch/vercel--part-2#<slug>`):

- `env-shape` MUST
- `noop-missing-token` MUST
- `cooldown-gate-on-entry` MUST
- `overall-budget-default` MUST
- `deadline-computed-once` MUST
- `page-cap` MUST
- `budget-exhaustion-before-page` MUST
- `per-page-call-timeout` MUST
- `pagination-query-params` MUST
- `auth-header` MUST
- `first-page-failure-definitive` MUST
- `later-page-failure-keeps-partial` MUST
- `rate-limit-note-on-429` MUST
- `non-ok-logged` MUST
- `thrown-fetch-first-page` MUST
- `thrown-fetch-later-page` MUST
- `lookback-window-stop` MUST
- `next-cursor-stop` MUST
- `next-cursor-carry` MUST
- `row-created-at-validated` MUST
- `row-id-prefix` MUST
- `row-platform-literal` MUST
- `row-project-name` MUST
- `row-provider-project-id` MUST
- `row-phases-delegated` MUST
- `row-environment` MUST
- `row-commit-hash` MUST
- `row-commit-message` MUST
- `row-branch` MUST
- `row-commit-repo` MUST
- `row-url` MUST
- `deploys-array-partial-kept` MUST
- `ok-composition` MUST

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

