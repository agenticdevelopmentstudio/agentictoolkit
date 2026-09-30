<!-- leaf: implement-status-server-monitor-1/deploy-status--part-2 · source: status-server-monitor-deploy-status.md -->

# Status Server Monitor Deploy Status — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-1/deploy-status--part-2#<slug>`):

- `deploy-status-values` MUST
- `build-phase-values` MUST
- `deploy-phase-values` MUST
- `phases-shape` MUST
- `build-phase-null-meaning` MUST
- `unknown-phase-terminal` MUST
- `in-flight-build-phases-list` MUST
- `in-flight-deploy-phase-value` MUST
- `is-in-flight-definition` MUST
- `is-in-flight-null-safe` MUST
- `in-flight-build-order` MUST
- `in-flight-sql-shape` MUST
- `in-flight-sql-default-prefix` MUST
- `column-overwritable-sql-per-column` MUST
- `webhook-keeps-stored-verdict-guard` MUST
- `webhook-keeps-stored-backwards-guard` MUST
- `webhook-keeps-stored-terminal-exempt` MUST
- `collapse-build-sql` MUST
- `collapse-deploy-sql` MUST
- `collapse-sql-evaluates-current-row` MUST
- `vercel-ready-to-built` MUST
- `vercel-error-to-failed` MUST
- `vercel-canceled-deleted-to-canceled` MUST
- `vercel-queued-to-queued` MUST
- `vercel-fallback-to-building` MUST
- `vercel-deploy-production-gated` MUST
- `vercel-deploy-substate-mapping` MUST
- `railway-building-initializing` MUST
- `railway-deploying` MUST
- `railway-success-crashed` MUST
- `railway-failed` MUST
- `railway-waiting-needsapproval` MUST
- `railway-removed-skipped` MUST
- `railway-unrecognized-fallback` MUST

## Behavioral Requirements

### Data Shape

- **deploy-status-values**: `DeployStatus` MUST be exactly one of `"success"`, `"failed"`, `"building"`, `"queued"`, `"canceled"`, or `"unknown"`.
- **build-phase-values**: `BuildPhase` MUST be exactly one of `"queued"`, `"building"`, `"built"`, `"failed"`, `"canceled"`, or `"unknown"`.
- **deploy-phase-values**: `DeployPhase` MUST be exactly one of `"none"`, `"deploying"`, `"deployed"`, `"failed"`, or `"unknown"`.
- **phases-shape**: A `Phases` value MUST carry exactly two fields: `buildPhase: BuildPhase | null` and `deployPhase: DeployPhase`.
- **build-phase-null-meaning**: A `buildPhase` of `null` MUST be produced, and only produced, by a provider mapper for a platform that reports no build lifecycle of its own — per the type's own doc comment, Cloudflare Workers is the documented example, because it lists only already-live deployments; `crunchyPhases` (Crunchy Bridge has no build/deploy CI lifecycle at all) is this file's own such mapper.
- **unknown-phase-terminal**: A `BuildPhase` or `DeployPhase` value of `"unknown"` MUST be treated as terminal — an in-flight phase the monitor could not re-confirm before its expiry window elapsed (`expireUnconfirmedDeploys`, external to this file) — and MUST NOT be treated as a good or bad verdict; per the type's own doc comment it is, like `"canceled"`, the ABSENCE of a verdict, but unlike `"canceled"` it MUST NOT be read as a claim that the provider itself stopped the work, and fresh provider truth (a poll or by-id re-fetch, external to this file) MUST be free to overwrite it.

### In-Flight Vocabulary

- **in-flight-build-phases-list**: `IN_FLIGHT_BUILD_PHASES` MUST be exactly the two-element array `["building", "queued"]`.
- **in-flight-deploy-phase-value**: `IN_FLIGHT_DEPLOY_PHASE` MUST be exactly `"deploying"`.
- **is-in-flight-definition**: `isInFlight(buildPhase, deployPhase)` MUST return `true` if and only if `buildPhase` is a member of `IN_FLIGHT_BUILD_PHASES` OR `deployPhase` equals `IN_FLIGHT_DEPLOY_PHASE`; this is, per the function's own doc comment, THE definition of "still in flight" — the row states that can still change, with every other combination terminal.
- **is-in-flight-null-safe**: `isInFlight` MUST return `false` for a `null` `buildPhase` when `deployPhase` is not `IN_FLIGHT_DEPLOY_PHASE`, because `null` is never a member of `IN_FLIGHT_BUILD_PHASES`.
- **in-flight-build-order**: `IN_FLIGHT_BUILD_ORDER` MUST list `"queued"` before `"building"`, reflecting that, per the constant's own doc comment, a build enters the queue once and leaves it once, so `"building"` is strictly later than `"queued"` and nothing walks that back; `deploy_phase` MUST have no equivalent ordering constant, because `"deploying"` is its only in-flight value and so has nothing to be out of order with.

### SQL Predicate Builders

- **in-flight-sql-shape**: `inFlightSql(prefix)` MUST return the SQL boolean expression `(<prefix>build_phase IN ('building', 'queued') OR <prefix>deploy_phase = 'deploying')`, interpolating only the fixed literals of `IN_FLIGHT_BUILD_PHASES` and `IN_FLIGHT_DEPLOY_PHASE` — never a caller-supplied value — so this fragment can never drift from `isInFlight`.
- **in-flight-sql-default-prefix**: `inFlightSql` called with no argument MUST default `prefix` to `""` (the stored row); passing `"excluded."` MUST produce the identical expression shape addressed at an upsert's incoming row instead.
- **column-overwritable-sql-per-column**: `columnOverwritableSql(col, prefix)` MUST return a predicate testing only the single named column (`build_phase` or `deploy_phase`) against its own in-flight values OR `'unknown'`, and MUST NOT reference the sibling column; per the function's own doc comment, this is deliberately PER-COLUMN so a real verdict on one lifecycle keeps its protection when the sibling lifecycle is `unknown` or in flight, rather than a whole-row predicate stripping that protection the moment either lifecycle is unknown.
- **webhook-keeps-stored-verdict-guard**: `webhookKeepsStoredSql(col)` MUST include the term `(<incoming col is in flight> AND NOT <stored col is overwritable per columnOverwritableSql>)`, so a late in-flight webhook event landing on a row whose named column already holds a settled verdict MUST NOT overwrite that column.
- **webhook-keeps-stored-backwards-guard**: For `col === "build_phase"` only, `webhookKeepsStoredSql` MUST also include one term per pair of `IN_FLIGHT_BUILD_ORDER` positions where the incoming value is earlier and the stored value is later (i.e. `(excluded.build_phase = 'queued' AND build_phase = 'building')`), derived from `IN_FLIGHT_BUILD_ORDER` rather than hand-listed; `col === "deploy_phase"` MUST produce no backwards-guard terms at all, because `"deploying"` is `deploy_phase`'s only in-flight value.
- **webhook-keeps-stored-terminal-exempt**: An incoming event whose value for `col` is itself terminal (not in `IN_FLIGHT_BUILD_PHASES`/not equal to `IN_FLIGHT_DEPLOY_PHASE`) MUST NOT be blocked by either term of `webhookKeepsStoredSql`, because the verdict-guard term requires the incoming value to be in flight and the backwards-guard term only ever matches two in-flight build values; per the function's own doc comment, a terminal event is the provider's current truth, and a re-promotion back into flight (e.g. `built` → `ROLLING`) is a legitimate move this predicate MUST permit.
- **collapse-build-sql**: `collapseInFlightBuildSql(to)` MUST return `CASE WHEN build_phase IN ('building', 'queued') THEN '<to>' ELSE build_phase END`, leaving a settled (non-in-flight) `build_phase` unchanged.
- **collapse-deploy-sql**: `collapseInFlightDeploySql(to)` MUST return `CASE WHEN deploy_phase = 'deploying' THEN '<to>' ELSE deploy_phase END`, leaving a settled `deploy_phase` unchanged.
- **collapse-sql-evaluates-current-row**: Both collapse builders MUST be expressed as a SQL `CASE` evaluated against the row's column value AT UPDATE TIME, not a value captured earlier by the caller; per `collapseInFlightBuildSql`'s own doc comment, this means a concurrent write landing between an external candidate `SELECT` and this `UPDATE` is never clobbered.

### Provider Phase Mappers — Vercel

- **vercel-ready-to-built**: `vercelPhases` MUST map `readyState === "READY"` to `buildPhase: "built"`.
- **vercel-error-to-failed**: `vercelPhases` MUST map `readyState === "ERROR"` to `buildPhase: "failed"`.
- **vercel-canceled-deleted-to-canceled**: `vercelPhases` MUST map `readyState === "CANCELED"` or `readyState === "DELETED"` to `buildPhase: "canceled"`.
- **vercel-queued-to-queued**: `vercelPhases` MUST map `readyState === "QUEUED"` to `buildPhase: "queued"`.
- **vercel-fallback-to-building**: `vercelPhases` MUST map every `readyState` value not covered above — `BUILDING`, `INITIALIZING`, `BLOCKED`, or any other string — to `buildPhase: "building"`, per the mapping's own inline comment naming exactly this fallthrough set.
- **vercel-deploy-production-gated**: `vercelPhases` MUST leave `deployPhase: "none"` unless `buildPhase` resolved to `"built"` AND `target === "production"`; per the function's own inline comment, a build that is `"built"` on a non-production target is STAGED — built but never promoted — so it MUST get no deploy entry at all.
- **vercel-deploy-substate-mapping**: When `buildPhase` is `"built"` and `target === "production"`, `vercelPhases` MUST map `readySubstate === "PROMOTED"` to `deployPhase: "deployed"`, `readySubstate === "ROLLING"` to `deployPhase: "deploying"`, and every other `readySubstate` value (including `null`/`undefined`) to `deployPhase: "none"`.

### Provider Phase Mappers — Railway

- **railway-building-initializing**: `railwayPhases` MUST map status `"BUILDING"` or `"INITIALIZING"` to `{ buildPhase: "building", deployPhase: "none" }`.
- **railway-deploying**: `railwayPhases` MUST map status `"DEPLOYING"` to `{ buildPhase: "built", deployPhase: "deploying" }`.
- **railway-success-crashed**: `railwayPhases` MUST map status `"SUCCESS"` or `"CRASHED"` to `{ buildPhase: "built", deployPhase: "deployed" }`; per the switch's own inline comment on the `"CRASHED"` case, this is deliberate — a runtime crash after a successful build+deploy is a health concern, not a deploy failure.
- **railway-failed**: `railwayPhases` MUST map status `"FAILED"` to `{ buildPhase: "failed", deployPhase: "none" }`; per the switch's own inline comment, Railway's enum cannot separate a build failure from a deploy failure, and treating it as a build failure is the documented choice because build failure is the common case.
- **railway-waiting-needsapproval**: `railwayPhases` MUST map status `"WAITING"` or `"NEEDSAPPROVAL"` to `{ buildPhase: "queued", deployPhase: "none" }`.
- **railway-removed-skipped**: `railwayPhases` MUST map status `"REMOVED"` or `"SKIPPED"` to `{ buildPhase: "canceled", deployPhase: "none" }`.
- **railway-unrecognized-fallback**: `railwayPhases` MUST map every status value not covered by the six cases above to `{ buildPhase: "building", deployPhase: "none" }` (the `switch` statement's own `default` branch).

