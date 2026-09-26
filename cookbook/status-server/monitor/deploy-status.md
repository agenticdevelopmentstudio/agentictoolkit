---
id: 96009fcc-e32e-4a40-9b3c-8b4f83f1cfec
title: Status Server Monitor Deploy Status
domain: agentictoolkit://cookbook/status-server/monitor/deploy-status
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Platform-independent build/deploy phase vocabulary, per-provider phase mappers,
  and the SQL predicate fragments that keep the storage layer's in-flight/webhook-ordering
  rules from drifting apart.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- status
- pure-function
- server
depends-on:
- agenticdevelopercookbook://principles/idempotency
related:
- agentictoolkit://cookbook/status-server/board
- agentictoolkit://cookbook/status-server/libsql
references:
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-status.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/reconcile-stuck-deploys.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/deploy-status-parity.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Deploy Status

## Overview

`deploy-status.ts` (`packages/web/packages/status-server/src/monitor/deploy-status.ts`) is the status backend's platform-independent vocabulary for a deployment's build and deploy lifecycle. It defines the `DeployStatus`, `BuildPhase`, and `DeployPhase` unions and the `Phases` shape every provider fetcher normalizes its provider-specific status into; three pure mapper functions (`vercelPhases`, `railwayPhases`, `crunchyPhases`) perform that normalization for Vercel, Railway, and Crunchy Bridge; `combinedStatus` reduces a `Phases` pair to the single `DeployStatus` the Details matrix, KPI strip, and deploy-issue recorder read; and `isInFlight` plus five SQL-fragment builders (`inFlightSql`, `columnOverwritableSql`, `webhookKeepsStoredSql`, `collapseInFlightBuildSql`, `collapseInFlightDeploySql`) give every SQL caller across the storage layer — the upsert's webhook regression guard, the reconcile sweep's gone-collapse, the schema's partial index, `expireUnconfirmedDeploys` (`reconcile-stuck-deploys.ts`, external) — one shared, unquestionable definition of "still in flight" so no query can drift from `isInFlight` itself. Every exported function here is synchronous, pure, and free of I/O; this file performs no network call, no database read or write, and no logging of its own — it is consumed by fetchers, webhook handlers, and storage-layer files that are all external to it. The module is also re-exported as the package's `./deploy-status` subpath (`@agentic-toolkit/status-server/deploy-status`) and is the pinned original half of a cross-package drift guard: `status-web/src/lib/deploy-status-parity.test.ts` imports this file alongside a hand-maintained mirror copy at `status-web/src/lib/deploy-status.ts` and asserts `IN_FLIGHT_BUILD_PHASES`, `IN_FLIGHT_DEPLOY_PHASE`, `isInFlight`, and `combinedStatus` agree across the full phase space, because the two packages share no build and the mirror is a hand copy, not an import.

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

### Provider Phase Mapper — Crunchy Bridge

- **crunchy-no-build-lifecycle**: `crunchyPhases` MUST always return `buildPhase: null`, per its own doc comment stating Crunchy Bridge clusters have no build/deploy CI lifecycle — health is the cluster `state` alone.
- **crunchy-bad-state-detection**: `crunchyPhases` MUST return `deployPhase: "failed"` when `isSuspended` is `true`, OR when `state` is `"failed"`, `"creation_failed"`, or `"suspended"` (the module-level `CRUNCHY_BAD_STATES` set), and MUST return `deployPhase: "deployed"` otherwise.
- **crunchy-healthy-default**: Every `state` value other than the three documented bad states — including `"ready"`, every documented routine/transient operation (`creating`, `restarting`, `resizing`, `resuming`, `starting`, `upgrading`, `restoring`, `finalizing`, `replaying`, `destroying`, `suspending`), an empty string, and any unrecognized future value — MUST map to `deployPhase: "deployed"`; per the function's own doc comment, this is a deliberate, owner-chosen "quieter" model: routine maintenance MUST NOT page, and an unrecognized state MUST NOT be assumed bad.
- **crunchy-phases-terminal**: Both fields `crunchyPhases` returns MUST always be terminal (`buildPhase` is always `null`, never an in-flight `BuildPhase`; `deployPhase` is always `"failed"` or `"deployed"`, never `"deploying"` or `"unknown"`), so that, per the doc comment, a caller's stuck-deploy check (`deployIsStuck`, external to this file) never misfires on a Crunchy cluster's arbitrarily old `createdAt`.

### Combined Status Derivation

- **combined-status-evaluation-order**: `combinedStatus` MUST evaluate its rules in exactly this order, as a sequence of early returns rather than independent conditions, because a `Phases` value can match more than one rule and only the first matched rule's result is correct: failed, then canceled, then unknown, then deployed, then deploying, then built, then queued, then the default.
- **combined-status-failed-precedence**: `combinedStatus` MUST return `"failed"` when `buildPhase === "failed"` OR `deployPhase === "failed"`, checked before every other rule, so a failure verdict on one lifecycle wins even when the other lifecycle is `"unknown"`.
- **combined-status-canceled**: `combinedStatus` MUST return `"canceled"` when `buildPhase === "canceled"`, checked after failed and before unknown.
- **combined-status-unknown-precedence**: `combinedStatus` MUST return `"unknown"` when `buildPhase === "unknown"` OR `deployPhase === "unknown"`, checked before the in-flight (`"deploying"`) and built/queued fallthrough rules, so a row whose lifecycle expired unconfirmable MUST NOT re-read as `"building"`.
- **combined-status-deployed-success**: `combinedStatus` MUST return `"success"` when `deployPhase === "deployed"`.
- **combined-status-deploying-building**: `combinedStatus` MUST return `"building"` when `deployPhase === "deploying"`.
- **combined-status-built-staged-success**: `combinedStatus` MUST return `"success"` when `buildPhase === "built"` and none of the preceding rules matched — per the branch's own inline comment, this is a build with no separate deploy step (non-production or staged).
- **combined-status-queued**: `combinedStatus` MUST return `"queued"` when `buildPhase === "queued"` and none of the preceding rules matched.
- **combined-status-default-building**: `combinedStatus` MUST return `"building"` for every remaining combination — `buildPhase === "building"`, `buildPhase === null` with no matching `deployPhase` rule, or any other combination not covered above.

## Appearance

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component.

## States

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component; its runtime lifecycle values (`BuildPhase`, `DeployPhase`, `DeployStatus`) are data this module models and derives, not a visual-state table, and are specified under Behavioral Requirements.

## Accessibility

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-deploy-status-001 | vercel-deploy-substate-mapping | `vercelPhases('READY', 'PROMOTED', 'production')` | `{ buildPhase: 'built', deployPhase: 'deployed' }` — `deploy-status.test.ts` › "maps READY + PROMOTED on production to built+deployed" |
| status-server-monitor-deploy-status-002 | vercel-error-to-failed | `vercelPhases('ERROR', null, null)` | `{ buildPhase: 'failed', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps ERROR to failed build with no deploy" |
| status-server-monitor-deploy-status-003 | vercel-deploy-production-gated | `vercelPhases('READY', null, null)` | `{ buildPhase: 'built', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps READY on non-production (preview) to built+none" |
| status-server-monitor-deploy-status-004 | vercel-canceled-deleted-to-canceled | `vercelPhases('CANCELED', null, null)` | `{ buildPhase: 'canceled', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps CANCELED to canceled+none" |
| status-server-monitor-deploy-status-005 | vercel-fallback-to-building | `vercelPhases('BUILDING', null, null)` | `{ buildPhase: 'building', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps BUILDING to building+none" |
| status-server-monitor-deploy-status-006 | vercel-queued-to-queued | `vercelPhases('QUEUED', null, null)` | `{ buildPhase: 'queued', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps QUEUED to queued+none" |
| status-server-monitor-deploy-status-007 | vercel-deploy-substate-mapping | `vercelPhases('READY', 'ROLLING', 'production')` | `{ buildPhase: 'built', deployPhase: 'deploying' }` — `deploy-status.test.ts` › "maps READY + ROLLING on production to built+deploying" |
| status-server-monitor-deploy-status-008 | railway-success-crashed | `railwayPhases('SUCCESS')` | `{ buildPhase: 'built', deployPhase: 'deployed' }` — `deploy-status.test.ts` › "maps SUCCESS to built+deployed" |
| status-server-monitor-deploy-status-009 | railway-failed | `railwayPhases('FAILED')` | `{ buildPhase: 'failed', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps FAILED to failed+none" |
| status-server-monitor-deploy-status-010 | railway-building-initializing | `railwayPhases('BUILDING')` | `{ buildPhase: 'building', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps BUILDING to building+none" |
| status-server-monitor-deploy-status-011 | railway-deploying | `railwayPhases('DEPLOYING')` | `{ buildPhase: 'built', deployPhase: 'deploying' }` — `deploy-status.test.ts` › "maps DEPLOYING to built+deploying" |
| status-server-monitor-deploy-status-012 | railway-removed-skipped | `railwayPhases('REMOVED')` | `{ buildPhase: 'canceled', deployPhase: 'none' }` — `deploy-status.test.ts` › "maps REMOVED to canceled+none" |
| status-server-monitor-deploy-status-013 | railway-success-crashed | `railwayPhases('CRASHED')` | `{ buildPhase: 'built', deployPhase: 'deployed' }` — `deploy-status.test.ts` › "maps CRASHED to built+deployed (runtime crash is not a deploy failure)" |
| status-server-monitor-deploy-status-014 | combined-status-deployed-success | `combinedStatus({ buildPhase: 'built', deployPhase: 'deployed' })` | `'success'` — `deploy-status.test.ts` › "returns success when deploy phase is deployed" |
| status-server-monitor-deploy-status-015 | combined-status-failed-precedence | `combinedStatus({ buildPhase: 'failed', deployPhase: 'none' })` | `'failed'` — `deploy-status.test.ts` › "returns failed when build phase is failed" |
| status-server-monitor-deploy-status-016 | combined-status-default-building | `combinedStatus({ buildPhase: 'building', deployPhase: 'none' })` | `'building'` — `deploy-status.test.ts` › "returns building when build phase is building" |
| status-server-monitor-deploy-status-017 | combined-status-queued | `combinedStatus({ buildPhase: 'queued', deployPhase: 'none' })` | `'queued'` — `deploy-status.test.ts` › "returns queued when build phase is queued" |
| status-server-monitor-deploy-status-018 | combined-status-canceled | `combinedStatus({ buildPhase: 'canceled', deployPhase: 'none' })` | `'canceled'` — `deploy-status.test.ts` › "returns canceled when build phase is canceled" |
| status-server-monitor-deploy-status-019 | combined-status-built-staged-success | `combinedStatus({ buildPhase: 'built', deployPhase: 'none' })` | `'success'` — `deploy-status.test.ts` › "returns success for a built non-prod (staged) deploy with no separate deploy step" |
| status-server-monitor-deploy-status-020 | combined-status-deploying-building | `combinedStatus({ buildPhase: 'built', deployPhase: 'deploying' })` | `'building'` — `deploy-status.test.ts` › "returns building for in-flight deploy phase" |
| status-server-monitor-deploy-status-021 | combined-status-unknown-precedence | `combinedStatus({ buildPhase: 'unknown', deployPhase: 'none' })`; `combinedStatus({ buildPhase: 'built', deployPhase: 'unknown' })` | Both `'unknown'` — `deploy-status.test.ts` › "returns unknown when EITHER lifecycle expired unconfirmable — never re-reads as building" |
| status-server-monitor-deploy-status-022 | combined-status-evaluation-order, combined-status-failed-precedence | `combinedStatus({ buildPhase: 'unknown', deployPhase: 'failed' })` | `'failed'` — `deploy-status.test.ts` › "a failure verdict still wins over an expired other lifecycle" |
| status-server-monitor-deploy-status-023 | crunchy-bad-state-detection, crunchy-no-build-lifecycle | `crunchyPhases('ready', false)` | `{ buildPhase: null, deployPhase: 'deployed' }` — `deploy-status.test.ts` › "ready + not suspended → deployed" |
| status-server-monitor-deploy-status-024 | crunchy-bad-state-detection | `crunchyPhases('ready', true)` | `{ buildPhase: null, deployPhase: 'failed' }` — `deploy-status.test.ts` › "suspended flag → failed even when state is ready" |
| status-server-monitor-deploy-status-025 | crunchy-bad-state-detection | `crunchyPhases('failed', false)`; `crunchyPhases('creation_failed', false)`; `crunchyPhases('suspended', false)` | All three `{ buildPhase: null, deployPhase: 'failed' }` — `deploy-status.test.ts` › "documented problem states → failed" |
| status-server-monitor-deploy-status-026 | crunchy-healthy-default | `crunchyPhases('restarting', false)`; `crunchyPhases('destroying', false)` | Both `{ buildPhase: null, deployPhase: 'deployed' }` — `deploy-status.test.ts` › "routine/transient states → deployed (quieter: maintenance is not a problem)" |
| status-server-monitor-deploy-status-027 | crunchy-healthy-default | `crunchyPhases('', false)`; `crunchyPhases('weird_unknown', false)` | Both `{ buildPhase: null, deployPhase: 'deployed' }` — `deploy-status.test.ts` › "unknown / empty state → deployed (unrecognised is not assumed bad)" |
| status-server-monitor-deploy-status-028 | is-in-flight-definition, is-in-flight-null-safe | `isInFlight('building', 'none')` → `true`; `isInFlight('built', 'deployed')` → `false`; `isInFlight(null, 'deployed')` → `false` | `reconcile-stuck-deploys.test.ts` › `isInFlight` describe block |
| status-server-monitor-deploy-status-029 | in-flight-sql-shape, in-flight-sql-default-prefix | `inFlightSql()` | Exactly `"(build_phase IN ('building', 'queued') OR deploy_phase = 'deploying')"`, traced directly to the function body (no test asserts the literal string; see Compliance) |
| status-server-monitor-deploy-status-030 | collapse-build-sql | `collapseInFlightBuildSql('canceled')` | Exactly `"CASE WHEN build_phase IN ('building', 'queued') THEN 'canceled' ELSE build_phase END"`, traced directly to the function body |
| status-server-monitor-deploy-status-031 | is-in-flight-definition | `web.isInFlight(b, d) === server.isInFlight(b, d)` for every `(b, d)` pair over the full `BUILD_PHASES`/`DEPLOY_PHASES` cross-product | All pairs equal — `deploy-status-parity.test.ts` › "isInFlight agrees for every (build, deploy) phase pair" |
| status-server-monitor-deploy-status-032 | combined-status-evaluation-order | `web.combinedStatus(phases) === server.combinedStatus(phases)` for every `(buildPhase, deployPhase)` pair over the full cross-product | All pairs equal — `deploy-status-parity.test.ts` › "combinedStatus agrees for every (build, deploy) phase pair" |

## Edge Cases

- **Null and empty input**: `buildPhase: null` MUST be accepted by `isInFlight`, `combinedStatus`, and both SQL builders as a valid, terminal, non-matching value (build-phase-null-meaning, is-in-flight-null-safe) — MUST. `crunchyPhases` MUST treat an empty-string `state` identically to any other unrecognized value — mapped to `deployPhase: "deployed"` (crunchy-healthy-default, status-server-monitor-deploy-status-027) — MUST. None of `vercelPhases`, `railwayPhases`, or `crunchyPhases` validates that its string argument is non-empty or a recognized literal before use; an empty or unrecognized string is not rejected, it is routed through each function's own documented fallback branch (vercel-fallback-to-building, railway-unrecognized-fallback, crunchy-healthy-default) — this is the function's declared contract, not an unvalidated-input gap.
- **Boundary values**: this module defines no numeric constraint; its only ordered boundary is `IN_FLIGHT_BUILD_ORDER`'s two positions, where `"queued"` MUST be treated as strictly earlier than `"building"` and nothing may reorder them (in-flight-build-order, webhook-keeps-stored-backwards-guard) — MUST.
- **Concurrent access**: every exported function in this file is a synchronous, pure computation over its arguments with no shared mutable state and no `await`, so calls from any number of callers MUST NOT interleave in a way that changes any single call's result — MUST. The concurrency concern this file exists to resolve lives one layer down, in the SQL it builds: `collapseInFlightBuildSql`/`collapseInFlightDeploySql` MUST express their collapse as a `CASE` over the row's value AT UPDATE TIME so a write racing between an external candidate `SELECT` and that `UPDATE` is never clobbered (collapse-sql-evaluates-current-row), and `webhookKeepsStoredSql` MUST resolve out-of-order webhook delivery — documented in its own doc comment as the ordinary case, not an exotic one — via the verdict guard and the build-phase backwards guard rather than any lock (webhook-keeps-stored-verdict-guard, webhook-keeps-stored-backwards-guard) — MUST.
- **Error states**: this file has no dependency of its own — no network call, no database access, no file I/O — so it has no error path to swallow, log, or surface; every function returns a value for every input via an exhaustive `switch`/ternary chain with an explicit default/fallback branch, never a thrown exception. What a caller's own dependency (Vercel's, Railway's, or Crunchy's API; the storage layer that executes the SQL this file builds) does on failure is those callers' concern, external to this file.
- **Offline / disconnected state**: not applicable — this file makes no network connection of its own to lose; the fetchers that call `vercelPhases`/`railwayPhases`/`crunchyPhases` (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-crunchy.ts`, all external to this file) own whatever happens when their own outbound call fails, and simply never call these pure mappers in that case.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `readyState`, `readySubstate`, `target` (parameters to `vercelPhases`) | `string`, `string \| null \| undefined`, `string \| null \| undefined` | none — caller-supplied per call | The Vercel deployment fields the caller (`fetch-vercel.ts`, `webhook-events.ts`, `reconcile-stuck-deploys.ts`, all external) already fetched or received via webhook. |
| `status` (parameter to `railwayPhases`) | `string` | none — caller-supplied per call | The Railway deployment status field the caller already fetched or received via webhook. |
| `state`, `isSuspended` (parameters to `crunchyPhases`) | `string`, `boolean` | none — caller-supplied per call | The Crunchy Bridge cluster's documented state string and its `is_suspended` compute-is-off flag, as fetched by `fetch-crunchy.ts` (external). |
| `prefix` (parameter to `inFlightSql`, `columnOverwritableSql`) | `"" \| "excluded."` | `""` | Selects whether the built predicate reads the stored row (`""`) or an upsert's incoming row (`"excluded."`, the SQLite `ON CONFLICT` alias). |
| `col` (parameter to `columnOverwritableSql`, `webhookKeepsStoredSql`) | `"build_phase" \| "deploy_phase"` | none — required | Selects which single lifecycle column the built predicate evaluates; the TypeScript union type itself is the only validation — no other string is accepted at compile time. |
| `to` (parameter to `collapseInFlightBuildSql`, `collapseInFlightDeploySql`) | `BuildPhase` / `DeployPhase` | none — required | The terminal value the built `CASE` expression collapses an in-flight column to. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it exports only types, constants, pure mapper functions, and SQL-fragment strings.

## Localization

Not applicable: this file emits no user-facing string; its literal union values (`success`, `failed`, `building`, `queued`, `canceled`, `unknown`, and the `BuildPhase`/`DeployPhase` members) are internal status codes that a UI layer external to this file (`board/derive-activity.ts`, `board/derive-problems.ts`) is responsible for rendering and localizing.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: none of this file's own — it receives already-fetched provider status strings (`readyState`, `status`, cluster `state`) and cluster metadata (`is_suspended`) as plain function arguments from callers external to this file; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing; the SQL fragments it builds are executed by the storage layer (`libsql/schema.ts`, `libsql/stores/*.ts`), external to this file.
- **Transmission**: none. This file performs no network or database call; every SQL fragment it returns is a `string` handed back to its caller, which decides whether and how to execute it.
- **Retention**: not applicable — this file holds no data across calls.

## Logging

Not applicable: this file contains no logging call of any kind — every exported function is a pure synchronous mapper or SQL-fragment builder with no side effects.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `DeployStatus`, `BuildPhase`, and `DeployPhase` as `Sendable`, `String`-backed `enum`s and `Phases` as a `Sendable struct`; because every function here is a pure, synchronous, non-isolated computation, the ported functions need no `actor` or `@MainActor` isolation at all — plain top-level or static functions are the direct equivalent.
- **Compose**: same non-UI framing. A Kotlin port models the three unions as `enum class`es and the mapper/derivation functions as top-level functions using `when` expressions in place of this file's ternary chains and `switch` statement; the SQL-fragment builders would more idiomatically return a query-builder DSL fragment (Room/SQLDelight `WHERE` clause) rather than a raw interpolated `String`, though the safety property is the same either way since only fixed enum literals are interpolated, never caller input.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/deploy-status.ts` as a plain ESM module on the Node status backend, re-exported at the package's `./deploy-status` subpath (`@agentic-toolkit/status-server/deploy-status`); it has a hand-maintained mirror copy at `packages/web/packages/status-web/src/lib/deploy-status.ts` (external to this file, the two packages share no build) whose drift against this file is asserted only for `IN_FLIGHT_BUILD_PHASES`, `IN_FLIGHT_DEPLOY_PHASE`, `isInFlight`, and `combinedStatus` by `deploy-status-parity.test.ts` — the provider mappers (`vercelPhases`, `railwayPhases`, `crunchyPhases`) and the five SQL-fragment builders have no such cross-package parity guard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no `Worker`-style per-thread module duplication concern applies to a Swift port the way it might to a Node file with mutable module state, but this file in particular has no mutable state to duplicate in the first place — every function is stateless.
- **WinUI 3**: a .NET port models `DeployStatus`, `BuildPhase`, and `DeployPhase` as C# `enum`s and `Phases` as a `readonly record struct { BuildPhase? BuildPhase; DeployPhase DeployPhase }`, with `VercelPhases`, `RailwayPhases`, `CrunchyPhases`, and `CombinedStatus` as `static` methods (e.g. on a `DeployStatusMapper` class) using C# `switch` expressions in place of this file's ternary chains. For the SQL-fragment builders, a port against the same libSQL/SQLite store via `Microsoft.Data.Sqlite` or EF Core's `FromSqlRaw` can keep this file's literal-interpolation approach with the same safety property — only the module's own fixed enum literals are interpolated, never external input — but where the surrounding query already uses `DbCommand.Parameters`/EF Core parameterization for other values, the port SHOULD interpolate through a small internal helper that still emits only these fixed literals rather than mixing raw string concatenation into an otherwise-parameterized query, to keep the codebase's SQL construction convention consistent.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/deploy-status.ts` |

## Design Decisions

- **Decision**: derive `IN_FLIGHT_BUILD_ORDER`'s backwards-guard SQL terms programmatically from the ordering array (`buildPhaseBackwardsSql`, module-private) rather than hand-listing the disallowed `(incoming, stored)` pairs.
  **Rationale**: stated directly in the source comment on `buildPhaseBackwardsSql` — deriving from the ordering means "inserting a phase can't leave a stale hand-written pair behind." This is why `webhook-keeps-stored-backwards-guard`'s SHOULD companion (`build-order-extension`, below) exists: the safety property depends on every future in-flight `BuildPhase` addition also being added to `IN_FLIGHT_BUILD_ORDER`.
  **Approved**: pending
- **Decision**: make `columnOverwritableSql` and the resulting `webhookKeepsStoredSql` guard evaluate PER-COLUMN rather than as one whole-row predicate.
  **Rationale**: stated directly in the source comment — a whole-row predicate, overwritable the moment EITHER lifecycle is unknown/in-flight, would strip protection from a settled build or deploy verdict it should keep, regressing e.g. a `built`+`unknown` row's real `built` back to `building` on a stale webhook.
  **Approved**: pending
- **Decision**: treat `"unknown"` as a terminal, non-verdict phase distinct from both a real verdict and from `"canceled"`, and check it in `combinedStatus` before the in-flight fallthrough rules.
  **Rationale**: stated directly in the source comments on `BuildPhase` and `combinedStatus` — `"unknown"` is the monitor's own gave-up marker for an in-flight phase nothing could re-confirm before its expiry window, never a claim that the provider stopped the work (unlike `"canceled"`); checking it before the in-flight fallthroughs is what keeps an expired row from silently re-reading as `"building"`.
  **Approved**: pending
- **Decision**: give `railwayPhases`'s `"FAILED"` case a build-failure verdict rather than a deploy-failure verdict, and give its `"CRASHED"` case a full success verdict (`built`+`deployed`) rather than any failure.
  **Rationale**: both stated directly in the switch's own inline comments — Railway's status enum cannot distinguish a build failure from a deploy failure, and build failure is the documented common case; a runtime crash after a successful build and deploy is a health concern for a separate system to surface, not a deploy failure this module should report.
  **Approved**: pending
- **Decision**: give `crunchyPhases` a "quieter" health model where only three documented bad states (plus the `isSuspended` flag) map to `failed`, and every routine/transient/unrecognized state maps to `deployed`.
  **Rationale**: stated directly in the source comment as an owner-chosen tradeoff — routine maintenance operations (resizing, restarting, upgrading, etc.) must not page on-call, and an unrecognized or future state is deliberately not assumed bad rather than defaulted to a failure.
  **Approved**: pending
- **Decision**: `build-order-extension` (SHOULD): when a new in-flight `BuildPhase` value is added to this module, `IN_FLIGHT_BUILD_ORDER` SHOULD be updated to include it in its correct relative position.
  **Rationale**: `buildPhaseBackwardsSql` derives every backwards-guard pair from `IN_FLIGHT_BUILD_ORDER`'s contents (webhook-keeps-stored-backwards-guard); an addition to `IN_FLIGHT_BUILD_PHASES` that is never added to `IN_FLIGHT_BUILD_ORDER` would silently leave that phase's backwards moves unguarded against a stale, redelivered webhook, with no compile-time or test signal pointing at the omission.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`unit-test-coverage` is `partial`: `deploy-status.test.ts` gives `vercelPhases`, `railwayPhases`, `crunchyPhases`, and `combinedStatus` thorough branch coverage with meaningful assertions, `reconcile-stuck-deploys.test.ts` separately unit-tests `isInFlight`, and `deploy-status-parity.test.ts` exhaustively cross-checks `isInFlight` and `combinedStatus` against the hand-mirrored web copy — but none of the five SQL-fragment builders (`inFlightSql`, `columnOverwritableSql`, `webhookKeepsStoredSql`, `collapseInFlightBuildSql`, `collapseInFlightDeploySql`) has a test that asserts its generated SQL string directly; they are exercised only indirectly, at runtime, through the storage-layer files that call them (`libsql/schema.ts`, `libsql/stores/board-store.ts`, `libsql/stores/deploy-store.ts`). `separation-of-concerns` passes: this file's only responsibility is the deploy-status vocabulary, its provider-specific normalization, and the SQL predicates derived from that same vocabulary; it performs no I/O, no persistence, and no presentation of its own, leaving those to files external to it. `idempotent-operations` passes: `webhookKeepsStoredSql` is precisely the mechanism that makes a redelivered (retried) webhook event produce the same stored result regardless of delivery order, per its own doc comment describing out-of-order webhook redelivery as the ordinary case this guard exists to handle. `data-integrity` passes: this file's SQL-fragment builders exist specifically to keep every SQL caller across the storage layer from drifting apart on what "in flight" or "overwritable" means, deriving every fragment from the single `IN_FLIGHT_BUILD_PHASES`/`IN_FLIGHT_DEPLOY_PHASE` source of truth rather than letting each caller redefine it; the actual read/write and durability guarantees are owned by the storage-layer files that execute these fragments, external to this one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
