<!-- leaf: implement-status-server-monitor-fetch/vercel-projects--part-3 · source: status-server-monitor-fetch-vercel-projects.md -->

# Status Server Monitor Fetch Vercel Projects — continued (part 3)

**Rules** (cite as `implement-status-server-monitor-fetch/vercel-projects--part-3#<slug>`):

- `missing-production-target-skipped` MUST
- `inspector-link-targets-serving-deploy` MUST
- `source-url-requires-slug` MUST
- `detail-only-when-stale` MUST
- `live-url-always-null` MUST
- `deploys-array-always-populated` MUST
- `ok-reflects-tracked-truncation-only` MUST
- `unexpected-exception-discards-partial-progress` MUST

### Per-Project State Assembly

- **missing-production-target-skipped**: In the per-project loop, `fetchVercelProductionStates` MUST skip a project entirely (push no `VercelProdState` entry) when `p.targets?.production` is falsy (absent, `null`, or `undefined`); such a project MUST still have a `VercelProjectMeta` entry from the earlier metadata step.
- **inspector-link-targets-serving-deploy**: `sourceUrl`, when non-null, MUST be built from the deployment actually judged (`evaluateProdStaleness`'s returned `serving.id`, with any leading `dpl_` prefix stripped), never from `live.id` directly, so the link points at the offending deployment even when `live` is an Ignored-Build-Step skip; when `serving.id` is empty or missing, the URL's path segment MUST fall back to the literal `deployments`.
- **source-url-requires-slug**: `sourceUrl` MUST be `null` for every project in a poll cycle where the team slug could not be resolved (cache empty, no team match, budget starved before the lookup), and MUST otherwise be `` https://vercel.com/<slug>/<url-encoded projectName>/<deployId or "deployments"> ``.
- **detail-only-when-stale**: `detail` MUST be `null` when `stale` is `false`, and MUST be the result of `staleDetail(errored, behind, liveCreated, now)` when `stale` is `true`.
- **live-url-always-null**: Each `VercelProdState`'s `liveUrl` field MUST be the literal `null`, unconditionally; per the source's own comment, it is "resolved from the matched endpoint in sync (explicit config)" — this file never attempts that resolution itself.

### Return Value Composition

- **deploys-array-always-populated**: `fetchVercelProductionStates` MUST return every successfully mapped row from project enumeration and the blind-project backfill in the `deploys` array regardless of whether `ok` is `true` or `false` — a partial poll's already-fetched rows MUST NOT be discarded.
- **ok-reflects-tracked-truncation-only**: The returned `ok` field, for the branch that reaches the return statement normally, MUST be `!truncated` — `true` only when none of the three tracked truncation causes (`"budget"`, `"page-error"`, `"page-timeout"`) fired during pagination. Reaching the fixed 50-page iteration cap while `pagination.next` is still non-null MUST NOT set `truncated` and therefore MUST NOT be reflected in `ok`.
- **unexpected-exception-discards-partial-progress**: When any statement between the page loop and the final return throws — including a malformed `p.link`, `p.targets`, or `latestDeployments` shape reaching `evaluateProdStaleness`, `toProviderDeploy`, or the metadata mapping, none of which run inside a per-item `try`/`catch` the way each network call does — the OUTER `try`/`catch` MUST log `` Vercel projects fetch failed: <message> `` via `console.error` and MUST return `{ ok: false, states: [], meta: [], deploys: [] }`, discarding every project, state, and deploy row already assembled in that call, unlike a page-level HTTP failure or timeout, which preserves the pages already fetched.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `VERCEL_API_TOKEN` | `string \| undefined` (field of `env`) | none — required for a non-no-op poll | The Vercel API Bearer token. Absent or empty triggers the no-op branch (noop-missing-token). Read only from the `env` object passed in, never from `process.env` directly by this file. |
| `VERCEL_TEAM_ID` | `string \| undefined` (field of `env`) | none | The Vercel team id to scope project enumeration, the team-slug lookup, and every provider call to. When unset, calls omit `teamId` entirely and the slug fallback takes the first team the token can see. |
| `overallBudgetMs` | `number \| undefined` (field of `env`) | `18_000` (`PROJECTS_OVERALL_BUDGET_MS`) | The overall poll budget in milliseconds, counted from before the enumeration loop starts (deadline-computed-once). Deliberately under the caller's 20-second `guard` timeout (`PROVIDER_POLL_TIMEOUT_MS`, `sync.ts`, external) so this function's own partial-result path fires first. Overridable "for tests/tuning" per the source comment. |
| `metaOnly` | `boolean \| undefined` (field of `env`) | `false` | When `true`, fetches only the project list for callers reconciling `deploy_project_meta` (external); skips the deployment-window fetch depth, the deploy derivation, the blind-project backfill, and the team-slug lookup entirely, returning `states: []` and `deploys: []` unconditionally (not as a partial). |
| `callTimeoutMs` | `number \| undefined` (field of `env`) | `6_000` (`PROJECTS_CALL_TIMEOUT_MS`) | Per-page-request timeout in milliseconds, overridable "so a test can exercise the page retry in milliseconds instead of waiting out a 6s box," per the source comment. |
| `PROJECTS_CALL_ATTEMPTS` (module constant) | `number` | `2` | Fixed per-page retry count; not exposed on `env` and not configurable per call. |
| `LATEST_DEPLOYMENTS_DEPTH` (module constant) | `number` | `10` | Fixed `latestDeployments` query depth for a non-`metaOnly` call; not configurable per call. |
| `CONCLUSIVE_CALL_TIMEOUT_MS` (module constant) | `number` | `5_000` | Fixed per-project timeout for the blind-project backfill's `/v6/deployments` call; not configurable per call. |
| `TEAM_SLUG_CACHE_TTL_MS` (module constant) | `number` | `3_600_000` (1 hour) | Fixed memoization window for the resolved team slug; not configurable per call. |
| `MIN_SLUG_CALL_MS` (module constant) | `number` | `500` | Fixed minimum remaining-budget window below which a team-slug sub-call is skipped rather than issued; not configurable per call. |
| `DOMAIN_CACHE_TTL_MS` (module constant) | `number` | `3_600_000` (1 hour) | Fixed memoization window per project for the resolved custom-domain list; not configurable per call. |

## Localization

This file's `staleDetail` function produces hardcoded, unlocalized English strings that ARE end-user-facing — they populate the `detail` field of every stale `VercelProdState`, which the caller surfaces on the status board for whoever is monitoring deploys. None of the four base reason strings, nor the `` · live build <age> old `` suffix (built from `timeAgo`'s hardcoded `"just now"`/`"<n>m"`/`"<n>h"`/`"<n>d"` outputs, `./time-ago`, external), route through any localization mechanism.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no key) | `production not updated to the latest build` | `staleDetail` base reason when `errored` is false |
| (none — no key) | `live production build errored` | `staleDetail` base reason when `errored` is true and `behind` is false |
| (none — no key) | `live production build errored; newer build not promoted` | `staleDetail` base reason when both `errored` and `behind` are true |
| (none — no key) | `<reason> · live build <age> old` | `staleDetail`'s age-qualified form, appended only when `liveCreated` resolves to a valid, non-zero date |

Every `console.error`/`console.log` diagnostic line elsewhere in this file (the truncation reasons, the per-deploy `createdAt` warning, the team-lookup failure, the blind-backfill notice) is operator-facing server-log text, not shown to an end user of the monitored product, and is documented under Logging rather than here.

## Privacy

- **Data collected**: this file transmits the caller-supplied Vercel API token as a Bearer credential on every request it makes; it reads back project ids, names, framework/root-directory config, linked Git org/repo/branch, custom domains, and deployment metadata (commit sha, commit message, branch) that Vercel itself already recorded from the account's own projects and builds. It collects no data from, and about, an end user of the monitored product.
- **Storage**: none in this file for the token or the per-call results — those live only in local variables and the returned result for the duration of one call; persistence is entirely the caller's responsibility (`storage.deploy.upsertDeployments`, `sync.ts`, external). Two module-scope, in-memory-only caches (`teamSlugCache`, `domainListCache`) persist for up to 1 hour EACH within one Node process/thread but hold no token — only the resolved slug string and the resolved domain lists, both already public-facing Vercel project configuration.
- **Transmission**: the token is sent as `Authorization: Bearer <token>` on every request to `api.vercel.com`, over HTTPS (every URL in this file is a hardcoded `https://` literal); no other destination ever receives the token. Vercel's own responses, including commit metadata and domain names, are received over the same HTTPS connection.
- **Retention**: not applicable to this file directly for the per-call result — it retains nothing after the call returns beyond the two bounded, non-token caches described under Storage; how long the mapped rows persist once upserted is governed by the caller's storage layer, external to this file.

