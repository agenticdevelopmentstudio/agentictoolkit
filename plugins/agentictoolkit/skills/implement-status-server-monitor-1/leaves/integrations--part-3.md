<!-- leaf: implement-status-server-monitor-1/integrations--part-3 · source: status-server-monitor-integrations.md -->

# Status Server Monitor Integrations — continued (part 3)

**Rules** (cite as `implement-status-server-monitor-1/integrations--part-3#<slug>`):

- `fixed-check-order` MUST
- `positional-fallback-on-unexpected-rejection` MUST
- `stabilization-uses-callers-nowms` MUST
- `response-shape` MUST
- `stabilizer-is-a-process-wide-singleton` MUST
- `immediate-recovery-no-debounce` MUST
- `debounce-until-confirmed` MUST
- `correlated-downgrade` MUST
- `single-confirmed-failure-stays-red` MUST
- `stabilizer-reset-test-hook` MUST

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

