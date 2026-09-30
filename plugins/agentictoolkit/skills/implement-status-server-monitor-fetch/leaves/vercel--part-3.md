<!-- leaf: implement-status-server-monitor-fetch/vercel--part-3 · source: status-server-monitor-fetch-vercel.md -->

# Status Server Monitor Fetch Vercel — continued (part 3)

**Rules** (cite as `implement-status-server-monitor-fetch/vercel--part-3#<slug>`):

- `compose-deploy-error-signature` MUST
- `compose-deploy-error-reason` MUST
- `compose-deploy-error-step-prefix` MUST
- `fetch-deploy-error-noop-token` MUST
- `fetch-deploy-error-cooldown` MUST
- `fetch-deploy-error-request` MUST
- `fetch-deploy-error-429` MUST
- `fetch-deploy-error-non-ok` MUST
- `fetch-deploy-error-success` MUST
- `fetch-deploy-error-thrown` MUST
- `compose-build-log-filter` MUST
- `compose-build-log-trim` MUST
- `compose-build-log-join` MUST
- `fetch-build-log-noop-token` MUST
- `fetch-build-log-cooldown` MUST
- `fetch-build-log-request` MUST
- `fetch-build-log-429` MUST
- `fetch-build-log-non-ok` MUST
- `fetch-build-log-success` MUST
- `fetch-build-log-thrown` MUST

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

## Localization

- **error-text-not-localized**: `composeVercelDeployError`'s returned string (surfaced by `enrich-deploy-errors.ts`, external, into the persisted `error_text` field the details pane and CLI display, per that file's own doc comment) is composed verbatim from Vercel's own `errorMessage`, `readyStateReason`, and `errorStep` fields, with no localization mechanism of any kind applied by this file — whatever language Vercel's API returns those fields in is what the end user sees.
- **build-log-not-localized**: `composeVercelBuildLog`'s returned string (surfaced by `routes/deploy-logs.ts`, external, as the `log` field of its JSON response, read by a human debugging a failed build) is likewise composed verbatim from Vercel's build-event `payload.text` values, with no localization mechanism of any kind applied by this file.

