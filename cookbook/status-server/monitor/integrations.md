---
id: da0c6c07-d0f4-4c6c-a1ef-51b696910c72
title: Status Server Monitor Integrations
domain: agentictoolkit://cookbook/status-server/monitor/integrations
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Runs seven self-checks in parallel — stats-store freshness plus Vercel,
  Cloudflare, Railway, GlitchTip, and PostHog reachability — with one bounded retry
  each, then debounces and correlates unreachable-kind failures across runs before
  the /integrations route serves them.
platforms:
- typescript
- web
tags:
- monitor
- integrations
- self-check
- retry
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
- agenticdevelopercookbook://guidelines/implementing/observability/logging
related:
- agentictoolkit://cookbook/status-server/monitor/fetch-cloudflare
- agentictoolkit://cookbook/status-server/config
- agentictoolkit://cookbook/status-server/auth
references:
- packages/web/packages/status-server/src/monitor/integrations.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/self-check-stability.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/time-ago.ts (agentictoolkit)
- packages/web/packages/status-server/test/integrations-retry.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/integrations-missing-env.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/integrations-telemetry.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Integrations

## Overview

`integrations.ts` (`packages/web/packages/status-server/src/monitor/integrations.ts`) exports `runIntegrationsCheck`, the self-check the status backend runs behind its own `/integrations` route (`routes/reads.ts`, external, cached 30s via `cachedSingleFlight`, gated by `requireAuth` for any authenticated tier — not admin-only). It fans out seven independent checks — the health-samples store and its own freshness, plus reachability of three deploy providers (Vercel, Cloudflare, Railway) and two telemetry providers (GlitchTip, PostHog) — through `Promise.allSettled`, each network probe wrapped in a shared retry primitive (`probe`) that tolerates exactly one transient blip before giving up. A companion module, `self-check-stability.ts` (whose only consumer is this file), debounces a `no-HTTP-response` failure across `CONFIRM_RUNS` calls spanning `CONFIRM_WINDOW_MS` before it is allowed to surface as red, and downgrades several simultaneously-confirmed failures into a single monitor-side "Connectivity" warning rather than a wall of provider errors.

## Behavioral Requirements

### Public Surface

- **integration-check-reexport**: The module MUST re-export the `IntegrationCheck` type from `./types` for callers that need only the shape, not the derivation functions.
- **check-state-signature**: `checkState(configured, ok)` MUST return `"warn"` when `configured` is falsy, `"error"` when `configured` is true and `ok` is false, and `"ok"` when both are true.
- **overall-state-signature**: `overallState(checks)` MUST return `"error"` when any check's `state` is `"error"`, else `"warn"` when any check's `state` is `"warn"`, else `"ok"` — including for an empty array, which MUST return `"ok"`.
- **run-integrations-check-signature**: `runIntegrationsCheck(storage, config, nowMs?)` MUST accept a `Storage` port, a `StatusConfig` port, and an optional `nowMs` defaulting to `Date.now()`, and MUST return a `Promise` resolving to `{ generatedAt: string; overall: CheckState; checks: IntegrationCheck[] }`.
- **reset-self-check-stability-test-hook**: `_resetSelfCheckStability()` MUST clear the module-level `selfCheckStability` singleton's failure-tracking state and return nothing; it exists so tests can isolate runs from each other, and production callers MUST NOT call it.

### Retry Primitive (`probe`, `isTransient`, `delay`)

- **probe-per-attempt-timeout**: `probe(fn, isRetryableValue?)` MUST create a fresh `withTimeout(TIMEOUT_MS)` deadline (6,000ms) for each attempt rather than one deadline shared across attempts, and MUST call the timer's `done()` after every attempt regardless of outcome.
- **probe-bounded-retry-count**: `probe` MUST make at most `PROBE_RETRIES + 1` (2) total calls to `fn` — the first attempt plus exactly one retry — never more.
- **probe-retry-on-transient-throw**: When `fn` throws on an attempt numbered less than `PROBE_RETRIES` and `isTransient(err)` is true, `probe` MUST wait `RETRY_BACKOFF_MS` (300ms, a fixed pause, not exponential backoff) via `delay` and then retry; on the final attempt, or when `isTransient(err)` is false, `probe` MUST rethrow immediately with no further retry.
- **probe-retry-on-retryable-value**: When `fn` resolves and `isRetryableValue(value)` (default: always `false`) is true on an attempt numbered less than `PROBE_RETRIES`, `probe` MUST wait `RETRY_BACKOFF_MS` and retry rather than returning that value immediately; on the final attempt, `probe` MUST return the value as-is even when `isRetryableValue` still reports it retryable.
- **is-transient-classification**: `isTransient(err)` MUST return `true` only for an `Error` instance whose `name` is `"AbortError"` or `"TimeoutError"`, or whose message plus its `cause`'s `code` field matches a transient-network pattern (`fetch failed`, `network`, `socket`, `ECONN`, `EAI_AGAIN`, `ENOTFOUND`, `ETIMEDOUT`, `UND_ERR`, case-insensitively); it MUST return `false` for any non-`Error` thrown value. A real HTTP response (401/403/5xx) is never routed through `isTransient` at all, because a resolved `Response` is not a throw.

### Stats Store and Freshness Checks

- **stats-store-check**: `checkStatsStore(storage)` MUST call `storage.health.checksSummary()`, MUST always report `id: "stats"`, `configured: true`, `ok: true`, `state: "ok"`, and MUST set `detail` to `` persistent · <samples> samples across <services> services `` from the returned counts; it applies no timeout of its own to this call, and any thrown error propagates to `runIntegrationsCheck`'s `Promise.allSettled` fallback rather than being caught here.
- **stats-freshness-uses-wall-clock-not-caller-nowms**: `checkStatsFreshness(storage)` MUST compute its own age using its own internal `Date.now()` call; the `nowMs` the caller passed to `runIntegrationsCheck` has no effect on this check's staleness computation, unlike `runIntegrationsCheck`'s forwarding of that same `nowMs` into the stabilizer.
- **stats-freshness-no-checks-yet**: When `storage.health.lastCheckedAtMs()` resolves `null`, `checkStatsFreshness` MUST report `id: "cron"`, `configured: true`, `ok: false`, `state: "warn"` (not `"error"`), and `detail: "first poll pending — no checks yet"`.
- **stats-freshness-stale-is-error**: When the age since the last checked time is strictly greater than `CRON_STALE_MS` (180,000ms), `checkStatsFreshness` MUST report `state: "error"` (via `checkState(true, false)`, which maps a configured-but-failing check to `"error"`, not `"warn"`) and `detail: "stale — last <ageLabel> ago"`, formatting `ageLabel` with `timeAgo` (`./time-ago`).
- **stats-freshness-fresh-is-ok**: When the age is within `CRON_STALE_MS` (equal to it or less), `checkStatsFreshness` MUST report `state: "ok"` and `detail: "last check <ageLabel> ago"`.

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

### Aggregation and Isolation (`runIntegrationsCheck`)

- **fixed-check-order**: `runIntegrationsCheck` MUST run all seven checks — stats store, stats freshness, Vercel, Cloudflare, Railway, GlitchTip, PostHog, in that order — through one `Promise.allSettled`, so one check's latency never blocks another's and a rejection from any one of them never aborts the batch.
- **positional-fallback-on-unexpected-rejection**: When a settled result is rejected (an unexpected throw escaping one of the seven functions' own try/catch), `runIntegrationsCheck` MUST synthesize a placeholder check using the SAME positional index into parallel `ids`/`labels` arrays that mirror the seven-call order above, reporting `configured: false`, `ok: false`, `state: "error"`, and `detail` from the rejection reason. This identification is positional, not name-based — the source's own comment on this mapping states plainly that "order must match the Promise.allSettled array above" — so reordering the seven calls without reordering the parallel arrays in lockstep would silently mislabel this placeholder. None of the seven functions given here is expected to reject, since each already returns a well-formed error-state object from its own try/catch; this fallback exists only for an unanticipated crash, a fact worth recording rather than a behavior any given test exercises.
- **stabilization-uses-callers-nowms**: `runIntegrationsCheck` MUST pass the SAME `nowMs` it received or defaulted into `selfCheckStability.stabilize(checks, nowMs)`, in contrast to `checkStatsFreshness`, which ignores it — so a caller-supplied `nowMs` controls the stabilizer's debounce/correlation timing but not the cron-freshness check's own staleness computation.
- **response-shape**: `runIntegrationsCheck` MUST return `generatedAt` as `new Date(nowMs).toISOString()`, `overall` as `overallState(stabilized)`, and `checks` as the stabilized array.

### Cross-Run Stabilization (`self-check-stability.ts`, sole consumer of this file)

- **stabilizer-is-a-process-wide-singleton**: `selfCheckStability` MUST be created exactly once at module load via `createSelfCheckStabilizer()`, at module scope, so its internal failure-tracking map persists across every separate call to `runIntegrationsCheck` for the lifetime of the process — because, per the source's own comment, "the check runs per `/integrations` request and the streaks must survive between them."
- **immediate-recovery-no-debounce**: For any check that is NOT both `unreachable: true` and `state: "error"`, `stabilize` MUST clear that check's id from its failure-tracking map and pass the check through unmodified — recovery from a failing streak is immediate, never debounced.
- **debounce-until-confirmed**: For a check that IS `unreachable: true` and `state: "error"`, `stabilize` MUST track a running-failure streak per check id and MUST NOT surface it as a real error until the streak has reached `CONFIRM_RUNS` (2) separate calls AND spanned at least `CONFIRM_WINDOW_MS` (90,000ms) since the streak's first failure; until confirmed, `stabilize` MUST override the check to `ok: true`, `state: "ok"`, `detail: "recheck pending — <original detail>"`, while preserving its other fields, including `unreachable: true`, which remains present on an object now reporting `state: "ok"`.
- **correlated-downgrade**: Once at least `CORRELATED_MIN` (2) distinct checks are confirmed-failing within the same `stabilize` call, every confirmed check MUST be downgraded from `state: "error"` to `state: "warn"` with `correlated: true` added, and a synthetic check MUST be appended with `id: "connectivity"`, `label: "Connectivity"`, `configured: true`, `ok: false`, `state: "warn"`, and `detail: "<n> providers unreachable at once — likely monitor-side connectivity, not provider outages"`.
- **single-confirmed-failure-stays-red**: When fewer than `CORRELATED_MIN` checks are confirmed-failing in the same call, each confirmed check MUST remain `state: "error"` with no `correlated` flag, and no synthetic connectivity check is appended.
- **stabilizer-reset-test-hook**: `createSelfCheckStabilizer()`'s returned `reset()` MUST clear its failure-tracking map with no other side effect; `runIntegrationsCheck` itself never calls `reset()` — only `_resetSelfCheckStability()`, a thin wrapper around it, does, and only tests call that.

## Appearance

Not applicable — this is a server-side integrations self-check module, not a visual component.

## States

Not applicable — this is a server-side integrations self-check module, not a visual component; its runtime states (missing-credential warn, retrying probe, debounced-pending, confirmed error, correlated warn) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side integrations self-check module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-integrations-001 | probe-retry-on-transient-throw, vercel-probes-user-endpoint, railway-probes-graphql-projects-query, cloudflare-probes-worker-scripts-with-value-based-retry | `fetch` stubbed so the first call to each of Vercel/Cloudflare/Railway throws an `AbortError`, then the retry succeeds | `by("vercel").state === "ok"`, `by("railway").state === "ok"`, `by("cloudflare").ok === true`, `overall !== "error"` — `integrations-retry.test.ts` › "recovers a provider that fails once then succeeds — no false red banner" |
| status-server-monitor-integrations-002 | debounce-until-confirmed, cloudflare-result-error-branches | `fetch` stubbed to always throw `AbortError` for every provider; `runIntegrationsCheck` called once (default `nowMs`) | `by("vercel").state === "ok"` with `detail === "recheck pending — This operation was aborted"`; `by("cloudflare").state === "ok"` with `detail === "recheck pending — workers/scripts unreachable (This operation was aborted)"`; `overall !== "error"` — `integrations-retry.test.ts` › "does NOT go red on the first run of hard failures — suppressed pending confirmation" |
| status-server-monitor-integrations-003 | correlated-downgrade | `fetch` stubbed to always throw; called twice, at `t0` and at `t0 + CONFIRM_WINDOW_MS + 1000` | For `vercel`, `cloudflare`, `railway`: `state === "warn"` and `correlated === true`; a `connectivity` check exists with `state === "warn"` and `detail` containing `3 providers unreachable at once`; `overall === "warn"` (never `"error"` for a correlated outage) — `integrations-retry.test.ts` › "confirms a persistent all-provider outage but correlates it as monitor-side — amber, not red" |
| status-server-monitor-integrations-004 | single-confirmed-failure-stays-red | `fetch` stubbed so only Vercel's URL throws on every call; Cloudflare and Railway succeed; called twice, at `t0` and at `t0 + CONFIRM_WINDOW_MS + 1000` | `by("vercel").state === "error"` with `correlated` undefined; `by("railway").state === "ok"`; no `connectivity` check is present — `integrations-retry.test.ts` › "confirms a SINGLE persistently-unreachable provider as a real red error" |
| status-server-monitor-integrations-005 | vercel-probes-user-endpoint, vercel-response-detail | `fetch` stubbed so Vercel's endpoint returns HTTP 401 on every call; Cloudflare and Railway succeed | `by("vercel").state === "error"`, `detail` contains `token invalid`, and the mocked `fetch` is called exactly once for Vercel's host — a 401 is a real state, never retried — `integrations-retry.test.ts` › "does NOT retry a real HTTP response (401 token-invalid surfaces immediately)" |
| status-server-monitor-integrations-006 | vercel-missing-token-warns, cloudflare-missing-token-warns, railway-missing-token-warns, glitchtip-missing-env-warns, posthog-missing-env-warns | All ten provider credential env vars unset; `fetch` stubbed to throw if called at all | `by("vercel").missingEnv` equals `["VERCEL_API_TOKEN"]`; `by("cloudflare").missingEnv` equals `["CLOUDFLARE_API_TOKEN"]`; `by("railway").missingEnv` equals `["RAILWAY_API_TOKEN"]`; `by("glitchtip").missingEnv` equals `["GLITCHTIP_URL", "GLITCHTIP_API_TOKEN", "GLITCHTIP_ORG"]` with `state === "warn"`; `by("posthog").missingEnv` equals `["POSTHOG_HOST", "POSTHOG_API_KEY", "POSTHOG_PROJECT_ID"]` with `state === "warn"`; no `fetch` call occurs — `integrations-missing-env.test.ts` › "names each provider's missing token by exact env var" |
| status-server-monitor-integrations-007 | cloudflare-account-unresolvable-is-error | `CLOUDFLARE_API_TOKEN` set, `CLOUDFLARE_ACCOUNT_ID` unset, and account discovery fails (the stubbed `fetch` throws) | `cf.missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID"]`; `cf.state === "error"`; `cf.detail === "CLOUDFLARE_ACCOUNT_ID not set and could not auto-discover"` — `integrations-missing-env.test.ts` › "errors (red) when the account is neither set nor auto-discoverable" |
| status-server-monitor-integrations-008 | cloudflare-auto-discovery-is-warn | `CLOUDFLARE_API_TOKEN` set, `CLOUDFLARE_ACCOUNT_ID` unset; the stubbed account-listing call resolves exactly one account and `listWorkerScripts` then succeeds | `cf.state === "warn"`, `cf.ok === true`, `cf.missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID"]`, `cf.detail` contains `auto-discovered` — `integrations-missing-env.test.ts` › "warns (amber, recoverable) when the account auto-discovers from the token" |
| status-server-monitor-integrations-009 | stats-store-check | All provider env vars unset (no network call possible); a real, migrated database is supplied | `checks.find(c => c.id === "stats").missingEnv` is `undefined` — `integrations-missing-env.test.ts` › "omits missingEnv on checks that have nothing missing (stats store)" |
| status-server-monitor-integrations-010 | glitchtip-probes-organization-endpoint, posthog-probes-hogql-query-endpoint, reachability-helper | GlitchTip and PostHog fully configured; every stubbed `fetch` call resolves HTTP 200 with `{}`; deploy-provider credentials unset | `by("glitchtip").state === "ok"` with `detail === "reachable"`; `by("posthog").state === "ok"` with `detail === "reachable"` — `integrations-telemetry.test.ts` › "reports both reachable (ok) on a 200 from the authed probe" |
| status-server-monitor-integrations-011 | glitchtip-probes-organization-endpoint, posthog-probes-hogql-query-endpoint | Same configuration as vector 010, recording every requested URL | The recorded URLs contain exactly `https://errors.example.com/api/0/organizations/acme/` (GlitchTip) and `https://ph.example.com/api/projects/42/query/` (PostHog) — `integrations-telemetry.test.ts` › "probes GlitchTip org-metadata (not the heavy issues query) and PostHog's real query API" |
| status-server-monitor-integrations-012 | reachability-helper, glitchtip-thrown-error-is-unreachable | GlitchTip's endpoint returns HTTP 401; PostHog's endpoint returns HTTP 200 | `by("glitchtip").state === "error"` with `detail` containing `token invalid`; `by("posthog").state === "ok"` — the two telemetry checks fail and succeed independently — `integrations-telemetry.test.ts` › "marks a provider error (red) on a 401 — an invalid token/key surfaces immediately" |
| status-server-monitor-integrations-013 | stats-freshness-no-checks-yet | `storage.health.lastCheckedAtMs()` resolves `null` (a freshly booted database with no recorded checks) | `checkStatsFreshness` returns `configured: true`, `ok: false`, `state: "warn"`, `detail: "first poll pending — no checks yet"` — traced directly to the `last === null` branch in `checkStatsFreshness`, not exercised by a dedicated assertion in the three given test files |
| status-server-monitor-integrations-014 | overall-state-signature | `overallState([])` | Returns `"ok"` — traced directly to `overallState`'s `some()`-over-empty-array short-circuit, which is `false` for both the error and warn checks |

## Edge Cases

- **Null and empty input**: Any of `VERCEL_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, or `RAILWAY_API_TOKEN` being absent, `undefined`, or an empty string all satisfy the same falsy check and trigger that provider's missing-token warn with no network call — MUST. GlitchTip and PostHog each require all three of their own credentials present; any one missing routes through `missingWarn` naming only the missing ones — MUST. `storage.health.lastCheckedAtMs()` resolving `null` is treated as "first poll pending," not as an error — MUST.
- **Boundary values**: A failure streak that has reached exactly `CONFIRM_RUNS` (2) runs AND spans exactly `CONFIRM_WINDOW_MS` (90,000ms) or more is confirmed; one run short, or the same two runs closer together in time than 90,000ms, stays suppressed as "recheck pending" — MUST. Exactly `CORRELATED_MIN` (2) simultaneously-confirmed providers is the minimum that triggers the correlated downgrade and synthetic connectivity check; exactly one confirmed provider alone stays a real, uncorrelated red error — MUST. An age exactly equal to `CRON_STALE_MS` is NOT stale, because the staleness comparison is strictly greater-than — MUST.
- **Concurrent access**: `selfCheckStability` is a single process-wide singleton whose failure-tracking `Map` is read and written by every call to `runIntegrationsCheck` for the life of the process, with no locking of its own; Node's single-threaded, run-to-completion execution model serializes each `stabilize()` call's synchronous body end-to-end, so two overlapping `/integrations` requests cannot interleave a read/write of the same map entry mid-update — a fact of the runtime, not a race, per this recipe's authoring rules for single-threaded JavaScript — MUST. The Cloudflare account-discovery cache this file reads through `resolveCfAccountId` is a separate module external to this file and is not managed here.
- **Error states**: A probe error that survives the bounded retry is caught inside each provider function's own try/catch and mapped to a well-formed error-state `IntegrationCheck` — it is never rethrown to `runIntegrationsCheck` — MUST. An unexpected rejection escaping one of the seven check functions entirely (not exercised by any check given here, each of which already returns a value from its own catch) is caught by `Promise.allSettled` and mapped to the positional placeholder described in positional-fallback-on-unexpected-rejection, rather than crashing the whole call — MUST.
- **Offline / disconnected state**: Every network call in every provider check carries a per-attempt timeout — `TIMEOUT_MS` (6,000ms) via `probe`, or, for Cloudflare's account resolution, a dedicated `withTimeout` window of the same length — so a fully unresponsive provider degrades to a caught, timed-out probe error rather than hanging indefinitely — MUST. This file performs no retry beyond `probe`'s single bounded attempt per call to `runIntegrationsCheck`; the caller's 30-second `cachedSingleFlight` cache window and the next inbound request to `/integrations` are the only further retries — an offline provider SHOULD NOT be assumed to recover within the same cache window.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `VERCEL_API_TOKEN` | `string \| undefined` (`config.credentials`) | none — triggers warn no-op | Bearer token for `checkVercel`'s probe of `api.vercel.com/v2/user`. |
| `VERCEL_TEAM_ID` | `string \| undefined` (`config.credentials`) | none | When unset, `checkVercel` appends an advisory note to `detail` regardless of probe outcome; never itself sent on the request. |
| `CLOUDFLARE_API_TOKEN` | `string \| undefined` (`config.credentials`) | none — triggers warn no-op | Bearer token for account resolution and the Worker-scripts probe. |
| `CLOUDFLARE_ACCOUNT_ID` | `string \| undefined` (`config.credentials`) | none — auto-discovered via the token when unset | When unset and auto-discovery succeeds, the check still passes but as `"warn"` with an advisory `missingEnv`; when auto-discovery fails, the check is `"error"`. |
| `RAILWAY_API_TOKEN` | `string \| undefined` (`config.credentials`) | none — triggers warn no-op | Bearer token for `checkRailway`'s GraphQL `projects` query against `backboard.railway.app`; must be an account/team token, not a project-scoped one. |
| `GLITCHTIP_URL`, `GLITCHTIP_API_TOKEN`, `GLITCHTIP_ORG` | `string \| undefined` each (`config.credentials`) | none — all three required together | `checkGlitchtip` requires all three before probing; any subset missing names only the missing ones via `missingWarn`. |
| `POSTHOG_HOST`, `POSTHOG_API_KEY`, `POSTHOG_PROJECT_ID` | `string \| undefined` each (`config.credentials`) | none — all three required together | `checkPosthog` requires all three before probing; any subset missing names only the missing ones via `missingWarn`. |
| `nowMs` (parameter of `runIntegrationsCheck`) | `number \| undefined` | `Date.now()` | Forwarded only into `selfCheckStability.stabilize`; has no effect on `checkStatsFreshness`'s own staleness computation. |
| `TIMEOUT_MS` (module constant) | `number` | `6_000` | Per-attempt timeout for every `probe`'d network call and for Cloudflare's account-resolution window. |
| `CRON_STALE_MS` (module constant) | `number` | `180_000` | Age threshold (3 minutes) beyond which `checkStatsFreshness` reports `"error"` instead of `"ok"`. |
| `PROBE_RETRIES` (module constant) | `number` | `1` | Maximum number of retries `probe` performs after the first attempt. |
| `RETRY_BACKOFF_MS` (module constant) | `number` | `300` | Fixed pause `probe` waits before its one retry. |
| `CONFIRM_RUNS` (`self-check-stability.ts` constant) | `number` | `2` | Minimum consecutive failing runs before an unreachable-kind failure is confirmed. |
| `CONFIRM_WINDOW_MS` (`self-check-stability.ts` constant) | `number` | `90_000` | Minimum wall-clock span the failure streak must cover before confirmation. |
| `CORRELATED_MIN` (`self-check-stability.ts` constant) | `number` | `2` | Minimum simultaneously-confirmed providers before the correlated-connectivity downgrade applies. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own; it is called by `routes/reads.ts`'s `/integrations` route (external), which owns the actual HTTP path.

## Localization

This file and `self-check-stability.ts` use no localization mechanism; every `detail` string they produce is a hardcoded English literal returned in the `/integrations` API response and rendered on the integrations panel for any authenticated user — a user-facing string, not a server log line, per this recipe's authoring rules a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — `stats` ok | `persistent · <samples> samples across <services> services` | `checkStatsStore`, always |
| n/a — `cron` pending | `first poll pending — no checks yet` | `checkStatsFreshness`, no prior recorded check |
| n/a — `cron` stale | `stale — last <ageLabel> ago` | `checkStatsFreshness`, age beyond `CRON_STALE_MS` |
| n/a — `cron` fresh | `last check <ageLabel> ago` | `checkStatsFreshness`, age within `CRON_STALE_MS` |
| n/a — provider missing token | `<ENV_VAR> not set` | `checkVercel`/`checkCloudflare`/`checkRailway`, no configured credential |
| n/a — telemetry missing env | `<names, comma-joined> not set` | `missingWarn`, GlitchTip/PostHog missing one or more credentials |
| n/a — reachable | `reachable` (optionally suffixed) | Every provider's ok branch |
| n/a — HTTP 401 (Vercel) | `HTTP <status> — token invalid` | `checkVercel`, `status === 401` |
| n/a — Cloudflare account unresolved | `CLOUDFLARE_ACCOUNT_ID not set and could not auto-discover` | `checkCloudflare`, no resolvable account |
| n/a — Cloudflare account discovered | `reachable (<n> scripts; account auto-discovered — set CLOUDFLARE_ACCOUNT_ID to pin it)` | `checkCloudflare`, auto-discovered account |
| n/a — Railway not authorized | An explanatory sentence naming a revoked, invalid, or project-scoped token | `checkRailway`, GraphQL error message exactly `Not Authorized` |
| n/a — reachability helper invalid credential | `HTTP <status> — <token or key> invalid` | `reachability`, `status` 401 or 403 |
| n/a — recheck pending | `recheck pending — <original detail>` | `self-check-stability.ts`, an unconfirmed failure streak |
| n/a — connectivity | `<n> providers unreachable at once — likely monitor-side connectivity, not provider outages` | `self-check-stability.ts`, correlated downgrade |

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: neither this file nor `self-check-stability.ts` consults a feature-flag system; whether a given check runs at all is gated entirely by the presence of its own credentials (documented under Behavioral Requirements and Configuration), not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind; its only output is the `IntegrationCheck[]` it returns to its caller.

## Privacy

- **Data collected**: this file transmits five different caller-supplied provider credentials (`VERCEL_API_TOKEN`, `CLOUDFLARE_API_TOKEN`, `RAILWAY_API_TOKEN`, `GLITCHTIP_API_TOKEN`, `POSTHOG_API_KEY`) as Bearer credentials on their respective probe requests, and reads back only reachability signals (an HTTP status, or, for Cloudflare, a script count) — it collects no data from, and about, an end user of the monitored product.
- **Storage**: none in `integrations.ts` itself — credentials and probe results live only in local variables for the duration of one call. `self-check-stability.ts` retains a small in-memory failure-tracking map (check id, run count, first-failed timestamp) for the life of the process; it retains no credential and no response body, only the `detail` string and `unreachable` flag already destined for the API response.
- **Transmission**: each credential is sent as `Authorization: Bearer <credential>` (plus, for the two telemetry providers, an operator-configured `GLITCHTIP_URL`/`POSTHOG_HOST` base) over HTTPS, to that one provider's own API host; no credential is ever sent to any other destination, logged, or included in a `detail` string.
- **Retention**: not applicable to `integrations.ts` directly — it retains nothing after a call returns. `self-check-stability.ts`'s in-memory streak entries are cleared for a given check id the moment that check next reports healthy (immediate-recovery-no-debounce), and the whole map is cleared on process restart or by the `_resetSelfCheckStability` test hook; there is no persistent (on-disk) retention of any credential or failure history in this file.

## Logging

Neither `integrations.ts` nor `self-check-stability.ts` calls `console.*` or any other logger at any point. Every failure surfaces exclusively through the returned `IntegrationCheck`'s own `state`/`detail`/`unreachable`/`correlated` fields, consumed by the `/integrations` route and rendered on the integrations panel — there is no server-log side channel for this component's own failures, in contrast to sibling deploy fetchers (e.g. the Cloudflare and Railway deploy pollers, external) that do log via `console.error`. A fully healthy run produces no log output from this component at any level, because it produces no log output from this component at ANY level, healthy or not.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this self-check pattern would model each of the seven checks as an `async throws -> IntegrationCheck` function that internally catches its own errors (mirroring this file's own catch-and-return shape) rather than letting `TaskGroup`'s default cancel-siblings-on-throw behavior fire; the fan-out itself maps to `withTaskGroup` (not `withThrowingTaskGroup`, since nothing should escape as a throw) collecting all seven results the way `Promise.allSettled` does, and each probe's per-attempt timeout maps to a `Task` racing a `Task.sleep(for:)` cancellation via `withTimeout`-style helper, mirroring the fresh-`AbortController`-per-attempt shape of `probe`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the seven-check fan-out with `coroutineScope { checks.map { async { runCatching { it() } } } }.awaitAll()` (each check's own `runCatching` standing in for this file's per-function try/catch, so one check's exception cannot cancel the sibling coroutines the way a bare `async` failure would), and each probe's timeout via `withTimeoutOrNull`, with the debounce/correlation state held in a `ConcurrentHashMap` if the host process is genuinely multi-threaded (unlike this file's single-threaded Node runtime).
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/integrations.ts`, a plain async function on the Node status backend, called by `routes/reads.ts`'s `/integrations` route through a 30-second `cachedSingleFlight` wrapper; it depends on one sibling in-repo module (`./self-check-stability`, plus `./time-ago` and the storage/config ports) and two exports of the vendored `@agentic-toolkit/deploy-platform` package (`util`'s `withTimeout`, `providers`'s `resolveCfAccountId`/`listWorkerScripts`) — none of it is client-side React.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this pattern has no Node-`Worker`-per-thread module-duplication concern; a Swift `actor` wrapping the failure-tracking map from `self-check-stability.ts` would give every caller, on any thread, the same single shared instance for free, without this file's reliance on a single-threaded event loop to make its unlocked `Map` mutation safe.
- **WinUI 3**: a .NET port models each of the seven checks as an `async Task<IntegrationCheck>` method using a single shared `HttpClient` with a fresh `CancellationTokenSource` (`CancelAfter(TimeSpan.FromMilliseconds(6000))`) allocated per attempt — never `HttpClient.Timeout`, which is static per client and cannot express "a fresh 6s window for THIS attempt only," the same distinction `probe`'s per-attempt `withTimeout` draws. The seven checks fan out via `Task.WhenAll` over tasks that each catch their own exceptions internally (mirroring this file's per-function try/catch, since a bare `Task.WhenAll` surfaces only the first exception rather than `Promise.allSettled`'s full per-item outcome). Provider JSON bodies deserialize via `System.Text.Json` records shaped like the Vercel `/v2/user`, Cloudflare `listWorkerScripts`, and Railway GraphQL response shapes this file reads ad hoc. The `self-check-stability.ts` failure-tracking map ports to a `ConcurrentDictionary<string, FailTrack>`, since a WinUI process's UI thread and a background polling `Task` calling this self-check concurrently is a real possibility this file's own single-threaded Node runtime never has to consider — a `lock` or `Interlocked` update around each `stabilize`-equivalent call is needed where this file gets that guarantee for free from the event loop. Neither this file nor a WinUI port needs `Windows.Storage`: nothing here persists past one call, and the failure-tracking streaks are deliberately in-memory-only and fail-soft on restart (per the source's own comment on the module-level singleton); an `ObservableCollection<IntegrationCheck>` and `INotifyPropertyChanged` would matter only to a UI surface that renders these results, which is outside this component's own boundary.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/integrations.ts` |

## Design Decisions

- **Decision**: retry a failed probe exactly once, after a fixed 300ms pause, rather than with no retry at all or with exponential backoff and jitter.
  **Rationale**: stated directly in the source's own comments on `PROBE_RETRIES` and `RETRY_BACKOFF_MS` — retrying once tolerates "a single momentary stall (cron-burst event-loop pressure, a GC pause, a restart cold-start, a brief egress hiccup)" without flipping "the whole status page red," and the fixed pause exists "so the retry doesn't re-hit the same burst." Demonstrated by `integrations-retry.test.ts` › "recovers a provider that fails once then succeeds — no false red banner."
  **Approved**: pending
- **Decision**: distinguish a "no HTTP response at all" failure (tagged `unreachable: true`) from a definitive HTTP/API error, and debounce and correlate only the former.
  **Rationale**: stated directly in the source's own comment inside `checkCloudflare` — "Only a NO-RESPONSE failure is 'unreachable' (debounced as transient). A definitive HTTP/API error (401 revoked token, 403 missing scope) is an immediate, actionable error — not a network blip." Demonstrated by `integrations-retry.test.ts` › "does NOT retry a real HTTP response (401 token-invalid surfaces immediately)."
  **Approved**: pending
- **Decision**: give Cloudflare's account-id resolution its own timeout window, separate from the subsequent Worker-scripts probe's window.
  **Rationale**: stated directly in the source's own comment — "Discovery and the scripts probe each get their OWN window so a slow /accounts call can't eat the scripts call's budget and false-alarm 'unreachable.'"
  **Approved**: pending
- **Decision**: treat `listWorkerScripts`'s returned error-flagged VALUE, not only a thrown error, as retryable for Cloudflare's probe.
  **Rationale**: stated directly in the source's own comment — "listWorkerScripts swallows failures into an error result (not a throw), so retry on error — a transient blip recovers, a real outage stays failed and goes red."
  **Approved**: pending
- **Decision**: debounce a single unreachable provider for `CONFIRM_RUNS` runs spanning `CONFIRM_WINDOW_MS`, but once several providers are confirmed-unreachable in the same run, downgrade them to a correlated warning plus a synthetic Connectivity check rather than ever fully suppressing them.
  **Rationale**: stated directly in `self-check-stability.ts`'s own module doc comment — an unreachable failure "is reported as healthy-with-a-note until it has persisted CONFIRM_RUNS consecutive runs spanning CONFIRM_WINDOW_MS," and "when several providers are confirmed-unreachable in the SAME run, the outage is almost certainly ours, not theirs," so each is "downgraded to a correlated warn" with "a single synthetic Connectivity check" naming "the real suspect." Demonstrated by `integrations-retry.test.ts` › "confirms a persistent all-provider outage but correlates it as monitor-side — amber, not red" and its single-provider counterpart.
  **Approved**: pending
- **Decision**: have `checkStatsFreshness` compute staleness from its own internal `Date.now()` call rather than accepting the `nowMs` `runIntegrationsCheck` received, while `runIntegrationsCheck` forwards that same `nowMs` into the stabilizer.
  **Rationale**: not stated as a deliberate tradeoff in an inline comment; demonstrated as a fact of the code. `timeAgo`'s own doc comment states "nowMs is passed in for testability," yet `checkStatsFreshness` never receives an outer `nowMs` to pass to it, computing its own internally instead — a caller cannot control this specific check's staleness boundary through `runIntegrationsCheck`'s `nowMs` parameter the way it can control the stabilizer's debounce/correlation timing, per stats-freshness-uses-wall-clock-not-caller-nowms and stabilization-uses-callers-nowms above. Recorded here per source-fidelity as fact, not endorsement.
  **Approved**: pending
- **Decision**: identify a `Promise.allSettled` rejection's check by array POSITION against parallel `ids`/`labels` arrays, rather than by a name carried in the rejection itself.
  **Rationale**: stated directly in the source's own comment on the mapping — "Order must match the Promise.allSettled array above." Recorded here as a fact and an acknowledged invariant rather than a marker, per positional-fallback-on-unexpected-rejection: no test in the three given test files exercises an actual rejection from any of the seven check functions, since each already resolves to a well-formed error-state object from its own try/catch, so this fallback path protects against an unanticipated crash rather than a documented, tested contract.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | failed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |

`unit-test-coverage` passes: `integrations-retry.test.ts` exercises the transient-recovery retry, the first-run debounce suppression, the correlated multi-provider downgrade, the single-provider persistent red, and the never-retry-a-real-401 contract; `integrations-missing-env.test.ts` exercises every provider's exact missing-credential naming, the Cloudflare account-unresolvable error, the Cloudflare account-auto-discovered warn, and the stats check's clean `missingEnv`; `integrations-telemetry.test.ts` exercises both telemetry providers' happy path, their exact probed URLs, and an independent-failure case — twelve `it` blocks across three files covering every state branch except the two boundary vectors this recipe traces directly to source (status-server-monitor-integrations-013, -014). `separation-of-concerns` passes: this file owns exactly one concern (running and aggregating the seven self-checks); it delegates cross-run debounce/correlation entirely to `self-check-stability.ts`, account/script discovery to the vendored `deploy-platform` package, and persistence/serving to its caller, none of which it reimplements. `explicit-error-handling` passes: every provider function's own try/catch maps a thrown error to a well-formed `state: "error"` check with a populated `detail`, and the outer `Promise.allSettled` maps even an unanticipated rejection to a placeholder check — nothing fails silently with no trace in the returned response. `timeout-configuration` passes: every network call — five provider probes plus Cloudflare's separate account-resolution call — carries an explicit `AbortController`-backed deadline via `probe` or `withTimeout`; none can hang indefinitely. `retry-with-backoff` fails as written: `probe` retries at most once, after a FIXED 300ms pause, not the exponential-backoff-with-jitter this check's guideline requires — a deliberate tradeoff recorded as fact in Design Decisions above ("tolerates a single momentary stall," not a general-purpose retry strategy), not a defended pass. `rate-limit-handling` fails as written for this file's own four direct-`fetch` checks (Vercel, Railway, GlitchTip, PostHog): each treats a 429 as an ordinary non-ok status via `res.ok`/`reachability`, with no `Retry-After` inspection or cooldown of its own; only Cloudflare's underlying `listWorkerScripts` call (external to this file, in the vendored `deploy-platform` package) special-cases a 429 through the shared cooldown registry, which this file benefits from incidentally but does not implement. `graceful-degradation` passes: a missing credential is a soft warn rather than a thrown error for every one of the seven checks, a single check's failure never aborts the other six (`Promise.allSettled`), and a monitor-side connectivity blip is actively distinguished from a real provider outage rather than paging on both alike. `health-observability` passes: this component's entire purpose is emitting a structured, per-provider health signal — the seven-check `IntegrationsResponse` this file assembles is precisely what the guideline calls for from a long-lived monitoring process, consumed directly by the `/integrations` route with no additional transformation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
