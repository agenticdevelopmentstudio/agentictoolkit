<!-- leaf: implement-status-server-monitor-1/integrations--part-2 · source: status-server-monitor-integrations.md -->

# Status Server Monitor Integrations — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-1/integrations--part-2#<slug>`):

- `vercel-missing-token-warns` MUST
- `vercel-probes-user-endpoint` MUST
- `vercel-team-id-advisory-note` MUST
- `vercel-response-detail` MUST
- `vercel-thrown-error-is-unreachable` MUST
- `cloudflare-missing-token-warns` MUST
- `cloudflare-account-resolution-own-timeout-window` MUST
- `cloudflare-account-unresolvable-is-error` MUST
- `cloudflare-probes-worker-scripts-with-value-based-retry` MUST
- `cloudflare-result-error-branches` MUST
- `cloudflare-auto-discovery-is-warn` MUST
- `cloudflare-configured-account-is-ok` MUST
- `cloudflare-thrown-error-is-unreachable` MUST
- `railway-missing-token-warns` MUST
- `railway-probes-graphql-projects-query` MUST
- `railway-outer-catch-is-unreachable` MUST
- `railway-non-ok-http-is-definitive-error` MUST
- `railway-not-authorized-detail` MUST
- `railway-parse-failure-is-definitive-error` MUST
- `railway-success-detail` MUST
- `missing-warn-helper` MUST
- `reachability-helper` MUST
- `glitchtip-missing-env-warns` MUST
- `glitchtip-probes-organization-endpoint` MUST
- `glitchtip-thrown-error-is-unreachable` MUST
- `posthog-missing-env-warns` MUST
- `posthog-probes-hogql-query-endpoint` MUST
- `posthog-thrown-error-is-unreachable` MUST

### Deploy Provider Checks (Vercel, Cloudflare, Railway)

- **vercel-missing-token-warns**: `checkVercel(config)` MUST report `configured: false`, `ok: false`, `state: "warn"`, `detail: "VERCEL_API_TOKEN not set"`, and `missingEnv: ["VERCEL_API_TOKEN"]` when `config.credentials.VERCEL_API_TOKEN` is falsy, performing no network call.
- **vercel-probes-user-endpoint**: When a token is configured, `checkVercel` MUST `probe` a single `GET https://api.vercel.com/v2/user` request with an `Authorization: Bearer <token>` header and no `isRetryableValue` override, so only a thrown transient error is retried — a resolved non-ok response such as 401 is never retried.
- **vercel-team-id-advisory-note**: When `config.credentials.VERCEL_TEAM_ID` is unset, `checkVercel` MUST append the literal suffix `` (VERCEL_TEAM_ID not set — team-scoped ops may fail) `` to `detail`, whether the probe succeeded or returned a non-ok status.
- **vercel-response-detail**: On an ok response, `checkVercel` MUST set `detail` to `reachable` plus the team-id suffix when applicable; on a non-ok response, it MUST set `detail` to `` HTTP <status> — token invalid `` when `status` is 401, or `` HTTP <status> — unexpected error `` for any other status, again plus the team-id suffix when applicable; `state` MUST be `checkState(true, res.ok)`.
- **vercel-thrown-error-is-unreachable**: When the probe throws after exhausting its bounded retry, `checkVercel` MUST catch it and report `ok: false`, `state: "error"` (hardcoded, not derived via `checkState`), `detail` set to the caught error's message (or its stringified form for a non-`Error` throw), and `unreachable: true`.
- **cloudflare-missing-token-warns**: `checkCloudflare(config)` MUST report `configured: false`, `state: "warn"`, `detail: "CLOUDFLARE_API_TOKEN not set"`, and `missingEnv: ["CLOUDFLARE_API_TOKEN"]` when `config.credentials.CLOUDFLARE_API_TOKEN` is falsy, before attempting any account resolution.
- **cloudflare-account-resolution-own-timeout-window**: When a token is present, `checkCloudflare` MUST resolve the account id via `resolveCfAccountId(configuredAccountId, token, signal)` under its own, separate `withTimeout(TIMEOUT_MS)` window, distinct from the subsequent `probe`'s per-attempt window around `listWorkerScripts`, so a slow account-discovery call cannot consume the scripts probe's own budget; this account-resolution call is not itself wrapped in `probe` and so is never retried by this file on a transient failure.
- **cloudflare-account-unresolvable-is-error**: When no account id can be resolved (neither configured nor auto-discoverable — the token sees zero or several accounts), `checkCloudflare` MUST report `configured: false`, `state: "error"`, `detail: "CLOUDFLARE_ACCOUNT_ID not set and could not auto-discover"`, and `missingEnv: ["CLOUDFLARE_ACCOUNT_ID"]`.
- **cloudflare-probes-worker-scripts-with-value-based-retry**: `checkCloudflare` MUST call `probe(signal => listWorkerScripts(accountId, token, signal), value => "error" in value)`, so a first attempt that resolves with an `error` field (rather than throwing) still gets exactly one retry, in addition to `probe`'s default thrown-transient-error retry.
- **cloudflare-result-error-branches**: When the (possibly retried) `listWorkerScripts` result carries an `error` field and `unreachable: true`, `checkCloudflare` MUST report `state: "error"`, `detail: "workers/scripts unreachable (<error>)"`, and propagate `unreachable: true` on the check (subject to cross-run stabilization); when the result carries an `error` field with no `unreachable` flag, `checkCloudflare` MUST report `state: "error"` and `detail: "workers/scripts <error>"` with no `unreachable` flag, surfacing a definitive API error immediately, uncorrelated and undebounced.
- **cloudflare-auto-discovery-is-warn**: When the result carries `scripts` and `config.credentials.CLOUDFLARE_ACCOUNT_ID` was blank or unset (the resolved account id was auto-discovered, not configured), `checkCloudflare` MUST report `state: "warn"`, `detail: "reachable (<n> scripts; account auto-discovered — set CLOUDFLARE_ACCOUNT_ID to pin it)"`, and `missingEnv: ["CLOUDFLARE_ACCOUNT_ID"]`, even though `configured` is `true` and the call succeeded.
- **cloudflare-configured-account-is-ok**: When the result carries `scripts` and the account id was explicitly configured, `checkCloudflare` MUST report `state: "ok"` and `detail: "reachable (<n> scripts)"` with no `missingEnv`.
- **cloudflare-thrown-error-is-unreachable**: When either the account-resolution call or the probed `listWorkerScripts` call throws, `checkCloudflare` MUST catch it and report `configured: true`, `ok: false`, `state: "error"`, `detail` from the error, and `unreachable: true`.
- **railway-missing-token-warns**: `checkRailway(config)` MUST report `configured: false`, `state: "warn"`, `detail: "RAILWAY_API_TOKEN not set"`, and `missingEnv: ["RAILWAY_API_TOKEN"]` when `config.credentials.RAILWAY_API_TOKEN` is falsy.
- **railway-probes-graphql-projects-query**: When a token is present, `checkRailway` MUST `probe` a single `POST https://backboard.railway.app/graphql/v2` request with `Authorization: Bearer <token>`, `Content-Type: application/json`, and a body containing the GraphQL query text for the first project edge's id.
- **railway-outer-catch-is-unreachable**: When the probed fetch itself throws after its bounded retry, `checkRailway` MUST catch it and report `ok: false`, `state: "error"`, `detail` from the error, and `unreachable: true` — this outer catch wraps only the network call, not the subsequent response parsing.
- **railway-non-ok-http-is-definitive-error**: When the fetch resolves but `res.ok` is false, `checkRailway` MUST report `state: "error"` and `detail: "HTTP <status>"` with no `unreachable` flag — a definitive HTTP-level rejection, uncorrelated and undebounced, distinct from a network-level throw.
- **railway-not-authorized-detail**: When the parsed GraphQL body's first error message is exactly `Not Authorized`, `checkRailway` MUST set `detail` to an explanatory message stating that the token may be revoked, invalid, or project-scoped, and that a valid account- or team-level token is required because project-scoped tokens cannot authorize this query.
- **railway-parse-failure-is-definitive-error**: When parsing the successful HTTP response's JSON body throws — an inner catch distinct from the outer network-call catch — `checkRailway` MUST report `state: "error"` and `detail` from that parse error, with no `unreachable` flag.
- **railway-success-detail**: When the response is ok and the parsed body's `data.projects` is present, `checkRailway` MUST report `state: checkState(true, true)` (`"ok"`) and `detail: "reachable"`.

### Telemetry Provider Checks (GlitchTip, PostHog) and Shared Helpers

- **missing-warn-helper**: `missingWarn(id, label, missing)` MUST return `configured: false`, `ok: false`, `state: "warn"`, `detail` set to the comma-joined missing env names followed by `not set`, and `missingEnv: missing`.
- **reachability-helper**: `reachability(id, label, res, invalidWord)` MUST report `configured: true`, `ok: res.ok`, `state: checkState(true, res.ok)`, `detail: "reachable"` when `res.ok`; otherwise `` HTTP <status> `` optionally suffixed with `` — <invalidWord> invalid `` when `status` is 401 or 403.
- **glitchtip-missing-env-warns**: `checkGlitchtip(config)` MUST call `missingWarn` naming whichever of `GLITCHTIP_URL`, `GLITCHTIP_API_TOKEN`, `GLITCHTIP_ORG` is unset, checking all three before any network call.
- **glitchtip-probes-organization-endpoint**: When all three credentials are present, `checkGlitchtip` MUST strip trailing slashes from `GLITCHTIP_URL` and `probe` a single `GET <base>/api/0/organizations/<GLITCHTIP_ORG>/` request with `Authorization: Bearer <GLITCHTIP_API_TOKEN>`, then derive its result via `reachability(..., "token")` — a deliberately cheap organization-metadata call, not the heavier issues query the errors band uses.
- **glitchtip-thrown-error-is-unreachable**: When the probed fetch throws, `checkGlitchtip` MUST catch it and report `configured: true`, `ok: false`, `state: "error"`, `detail` from the error, and `unreachable: true`.
- **posthog-missing-env-warns**: `checkPosthog(config)` MUST call `missingWarn` naming whichever of `POSTHOG_HOST`, `POSTHOG_API_KEY`, `POSTHOG_PROJECT_ID` is unset, checking all three before any network call.
- **posthog-probes-hogql-query-endpoint**: When all three credentials are present, `checkPosthog` MUST strip trailing slashes from `POSTHOG_HOST` and `probe` a single `POST <base>/api/projects/<POSTHOG_PROJECT_ID>/query/` request with `Authorization: Bearer <POSTHOG_API_KEY>` and a trivial HogQL `SELECT 1` query body, then derive its result via `reachability(..., "key")` — the same query API the analytics band uses, deliberately not the project-metadata endpoint the personal API key is not scoped to read.
- **posthog-thrown-error-is-unreachable**: When the probed fetch throws, `checkPosthog` MUST catch it and report `configured: true`, `ok: false`, `state: "error"`, `detail` from the error, and `unreachable: true`.

