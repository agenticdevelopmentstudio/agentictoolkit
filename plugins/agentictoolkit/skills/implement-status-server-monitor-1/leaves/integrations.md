<!-- leaf: implement-status-server-monitor-1/integrations · source: status-server-monitor-integrations.md -->

**Rules** (cite as `implement-status-server-monitor-1/integrations#<slug>`):

- `integration-check-reexport` MUST
- `check-state-signature` MUST
- `overall-state-signature` MUST
- `run-integrations-check-signature` MUST
- `reset-self-check-stability-test-hook` MUST
- `probe-per-attempt-timeout` MUST
- `probe-bounded-retry-count` MUST
- `probe-retry-on-transient-throw` MUST
- `probe-retry-on-retryable-value` MUST
- `is-transient-classification` MUST
- `stats-store-check` MUST
- `stats-freshness-uses-wall-clock-not-caller-nowms` MUST
- `stats-freshness-no-checks-yet` MUST
- `stats-freshness-stale-is-error` MUST
- `stats-freshness-fresh-is-ok` MUST

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

