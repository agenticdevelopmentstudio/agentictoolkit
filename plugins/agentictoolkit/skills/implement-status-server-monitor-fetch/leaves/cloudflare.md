<!-- leaf: implement-status-server-monitor-fetch/cloudflare · source: status-server-monitor-fetch-cloudflare.md -->

**Rules** (cite as `implement-status-server-monitor-fetch/cloudflare#<slug>`):

- `env-shape` MUST
- `noop-missing-credentials` MUST
- `cooldown-gate-on-entry` MUST
- `overall-budget-default` MUST
- `deadline-starts-before-listing` MUST
- `listing-timeout` MUST
- `per-script-timeout` MUST
- `budget-exhaustion-stops-new-fetches` MUST
- `prefer-live-listing` MUST
- `fallback-to-configured-scripts` MUST
- `blind-spot-vs-empty-account` MUST
- `bounded-concurrency-five` MUST
- `429-stops-remaining-queue` MUST
- `non-ok-response-is-error` MUST
- `thrown-error-is-error` MUST
- `deployments-slice-five` MUST
- `row-id-prefix` MUST
- `row-platform-literal` MUST
- `row-project-name-is-script-id` MUST
- `row-build-phase-null` MUST
- `row-deploy-phase-deployed` MUST
- `row-environment-production` MUST
- `row-created-at-validated` MUST
- `row-commit-hash-shortened` MUST
- `row-commit-message-full` MUST
- `row-branch-passthrough` MUST
- `row-commit-repo-always-null` MUST
- `row-url-always-null` MUST
- `deploys-array-always-populated` MUST
- `ok-composition` MUST

# Status Server Monitor Fetch Cloudflare

## Overview

`fetch-cloudflare.ts` (`packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts`) exports one function, `fetchCloudflareDeployments`, the Cloudflare Workers provider adapter behind the status server's deploy-monitor poll cycle (`sync.ts`, external). Given a Cloudflare API token and account id, it lists every Worker script the token can see (falling back to a caller-configured list when the listing fails), fetches each script's deployment history with bounded concurrency, and maps the results into `ProviderDeploy` rows (`./provider-deploy`, external) that the caller upserts into the deploy store. It shares its overall-budget-then-bounded-fan-out shape, its rate-limit cooldown gate, and its blind-spot-vs-healthy-empty-account distinction with the sibling Railway fetcher (`fetch-railway.ts`, external) — several of its own comments say so directly, citing the Railway fetcher as the precedent the identical bug or fix was already solved for.

## Behavioral Requirements

### Signature and No-Op Preconditions

- **env-shape**: `fetchCloudflareDeployments` MUST accept one `env` object with optional fields `CLOUDFLARE_API_TOKEN?: string`, `CLOUDFLARE_ACCOUNT_ID?: string`, `workerScripts?: readonly string[]`, and `overallBudgetMs?: number`, and MUST return a `Promise` resolving to `{ ok: boolean; deploys: ProviderDeploy[] }`.
- **noop-missing-credentials**: When `env.CLOUDFLARE_API_TOKEN` or `env.CLOUDFLARE_ACCOUNT_ID` is falsy (absent, empty string, or otherwise falsy), `fetchCloudflareDeployments` MUST return `{ ok: true, deploys: [] }` immediately, performing no network call.
- **cooldown-gate-on-entry**: Before any network call, `fetchCloudflareDeployments` MUST check `rateLimitedUntil("cloudflare")` (`@agentic-toolkit/deploy-platform/cooldown`, external) and, when it returns a truthy cooldown expiry, MUST return `{ ok: false, deploys: [] }` immediately, performing no network call. This precondition is checked on every call and is independent of the caller-side `guard()` wrapper in `sync.ts` (external), which checks the identical shared registry before invoking this function at all — the check inside this file is a self-contained precondition, not a workaround for `guard` occasionally being bypassed (unit tests, and the second call in the `provider-cooldown.test.ts` cooldown assertions, invoke this function directly without `guard`).

### Budget

- **overall-budget-default**: `fetchCloudflareDeployments` MUST default `overallBudgetMs` to 18,000 (18 seconds) when `env.overallBudgetMs` is not supplied.
- **deadline-starts-before-listing**: The overall deadline (`Date.now() + overallBudgetMs`) MUST be computed before the Worker-script listing call, so the listing's own elapsed time counts against the budget. Per the source's own comment, this mirrors "the same off-by-a-listing fix as the Railway fetcher" — computing the deadline after the listing let the real worst case run past the caller's 20-second `guard` timeout (`PROVIDER_POLL_TIMEOUT_MS` in `sync.ts`, external), causing the whole poll to be discarded as unreachable rather than returning the partial result it had already fetched.
- **listing-timeout**: The Worker-script listing call MUST be aborted after `Math.min(6_000, overallBudgetMs)` milliseconds via an `AbortController`.
- **per-script-timeout**: Each per-script deployments fetch MUST be aborted after `Math.min(6_000, remaining)` milliseconds, where `remaining` is the deadline minus the current time evaluated immediately before that script's fetch starts inside the `mapLimit` worker.
- **budget-exhaustion-stops-new-fetches**: Once the overall deadline has passed (`remaining <= 0`) or any earlier script set the module-local `skipped` flag, `fetchCloudflareDeployments` MUST NOT start a fetch for any further script in the `mapLimit` iteration; it MUST set `skipped = true` and return for that script without incrementing the error count.

### Script Listing and Fallback

- **prefer-live-listing**: `fetchCloudflareDeployments` MUST call `listWorkerScripts(accountId, token, signal)` (`@agentic-toolkit/deploy-platform/providers`, external) to enumerate every Worker script the account exposes, preferring it over any caller-supplied list.
- **fallback-to-configured-scripts**: When the result of `listWorkerScripts` does not carry a `scripts` field (its `WorkerScriptsResult` union's error branch), `fetchCloudflareDeployments` MUST fall back to `(env.workerScripts ?? []).slice()`.
- **blind-spot-vs-empty-account**: When the resulting `scripts` array has length zero, `fetchCloudflareDeployments` MUST return `deploys: []` and MUST set `ok` to `false` when the listing result carried an `error` field, or `true` when the listing genuinely succeeded with zero scripts (`{ scripts: [] }`) and no fallback was needed. Per the source's own comment, a failed listing with no configured fallback is "a BLIND SPOT (we hold a token yet can see nothing), not a healthy empty account," so it MUST surface as `ok: false` to fire the platform-health issue the same way the Railway fetcher's identical case does; a genuine authorized zero-Worker account MUST stay `ok: true`.

### Bounded Concurrent Fan-Out

- **bounded-concurrency-five**: `fetchCloudflareDeployments` MUST fetch each script's deployments through `mapLimit` (`@agentic-toolkit/deploy-platform/util`, external) with a concurrency limit of 5 (`CF_SCRIPT_CONCURRENCY`), never serially and never fully unbounded. Per the source's own comment, a prior serial `for`-loop made total time N scripts times up to 6 seconds, which "chronically blew the budget and returned partials every cycle" on a many-worker account — the same shape the Railway fetcher already fixed with `mapLimit`.
- **429-stops-remaining-queue**: When a per-script fetch receives an HTTP 429 response, `fetchCloudflareDeployments` MUST call `noteRateLimited("cloudflare", res.headers.get("retry-after"))` and MUST set the module-local `skipped` flag to `true`, so that every script not yet started in the `mapLimit` fan-out is also skipped for the remainder of this call. Per the source's own comment, cooling down "means not hammering the rest of the account this cycle either," not only refusing new calls on the NEXT cycle.

### Per-Script Response Handling

- **non-ok-response-is-error**: When a per-script deployments fetch resolves with `res.ok === false` (for any status, including 429), `fetchCloudflareDeployments` MUST log `` Cloudflare Workers <script> <status> `` via `console.error` and MUST set the module-local `anyError` flag to `true`, contributing no rows for that script and continuing to the next script rather than aborting the whole call.
- **thrown-error-is-error**: When a per-script fetch call throws (including the per-script `AbortController` firing), `fetchCloudflareDeployments` MUST catch it, log `` Cloudflare Workers fetch <script> `` plus the error via `console.error`, and set `anyError` to `true`, contributing no rows for that script.
- **deployments-slice-five**: On a successful per-script response, `fetchCloudflareDeployments` MUST read `body.result?.deployments ?? []` and MUST take only the first 5 entries (`.slice(0, 5)`) as the candidate rows for that script.

### Row Mapping

- **row-id-prefix**: Each mapped `ProviderDeploy.id` MUST be the literal string `` cf_ `` concatenated with the Cloudflare deployment's `id` field.
- **row-platform-literal**: Each mapped row's `platform` field MUST be the literal string `cloudflare-pages`, per the source's own comment, "kept as 'cloudflare-pages' — type/glyph/summary maps key on this value" (i.e. this is a deliberate cross-module key, not a mislabeling of a Cloudflare Worker as a Cloudflare Pages deployment).
- **row-project-name-is-script-id**: Each mapped row's `projectName` field MUST be the Worker script id being polled, not any value read from the deployment or its metadata.
- **row-build-phase-null**: Each mapped row's `buildPhase` field MUST be `null`, per the source's own comment, because "Workers deployments are live; no failed-build concept" exists for this provider.
- **row-deploy-phase-deployed**: Each mapped row's `deployPhase` field MUST be the literal `"deployed"`, unconditionally, because every deployment `listWorkerScripts`'s companion deployments endpoint returns is already live.
- **row-environment-production**: Each mapped row's `environment` field MUST be the literal string `"production"`, unconditionally; Cloudflare's Worker deployments endpoint carries no per-deployment environment signal this function reads.
- **row-created-at-validated**: Each mapped row's `createdAt` field MUST be the result of `toValidDate(dep.created_on)` (`./provider-deploy`, external); when that call returns `null` (an unparseable or missing `created_on`), `fetchCloudflareDeployments` MUST log `` Cloudflare deployment <id> has unparseable created_on <value> — skipping `` via `console.error` and MUST exclude that one deployment from the returned rows entirely (via `flatMap` returning `[]` for it), without dropping any other deployment from the same script or failing the script's fetch.
- **row-commit-hash-shortened**: When `dep.metadata?.commit_hash` is a `string`, the mapped row's `commitHash` field MUST be `shortSha(meta.commit_hash)` (`./format`, external, a 7-character truncation); otherwise it MUST be `null`.
- **row-commit-message-full**: When `dep.metadata?.commit_message` is a `string`, the mapped row's `commitMessage` field MUST be `commitFullMessage(meta.commit_message)` (`./format`, external, the whole message capped at 4,000 characters, whitespace-trimmed); otherwise it MUST be `null`.
- **row-branch-passthrough**: When `dep.metadata?.branch` is a `string`, the mapped row's `branch` field MUST be that string unchanged; otherwise it MUST be `null`.
- **row-commit-repo-always-null**: Each mapped row's `commitRepo` field MUST be `null`, unconditionally, per the source's own comment, because "Workers deployment metadata doesn't carry the repo."
- **row-url-always-null**: Each mapped row's `url` field MUST be `null`, unconditionally; unlike the Railway fetcher (external), this function supplies no dashboard-link fallback for `url`.

### Return Value

- **deploys-array-always-populated**: `fetchCloudflareDeployments` MUST return every successfully mapped row from every script's fetch in the `deploys` array, regardless of whether `ok` is `true` or `false` — a partial poll's already-fetched rows MUST NOT be discarded.
- **ok-composition**: The returned `ok` field, for the branch where at least one script was listed and polled, MUST be `!anyError && !skipped` — `true` only when every polled script's fetch succeeded, no 429 was received, and no script was left unpolled for lack of remaining budget.

