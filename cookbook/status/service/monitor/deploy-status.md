---
id: 96009fcc-e32e-4a40-9b3c-8b4f83f1cfec
title: Monitor Deploy Status
domain: agentictoolkit://cookbook/status/service/monitor/deploy-status
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
- agentictoolkit://cookbook/status/service/board
- agentictoolkit://cookbook/status/service/storage/libsql
references:
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-status.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/reconcile-stuck-deploys.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/deploy-status-parity.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Monitor Deploy Status

## Overview

This module is the status backend's platform-independent vocabulary for a deployment's build and deploy lifecycle. It defines the build-phase, deploy-phase and combined deploy-status vocabularies and the phases shape every provider fetcher normalizes its provider-specific status into; three pure phase mappers perform that normalization for Vercel, Railway, and Crunchy Bridge; a combining function reduces a phases pair to the single deploy status the Details matrix, KPI strip, and deploy-issue recorder read; and an in-flight check plus five SQL-fragment builders give every SQL caller across the storage layer — the upsert's webhook regression guard, the reconcile sweep's gone-collapse, the schema's partial index, the unconfirmed-deploy expiry sweep (external to this module) — one shared, unquestionable definition of "still in flight" so no query can drift from the in-flight check itself. Every exported function here is synchronous, pure, and free of I/O; this module performs no network call, no database read or write, and no logging of its own — it is consumed by fetchers, webhook handlers, and storage-layer files that are all external to it. The module is also re-exported at a dedicated subpath and is the pinned original half of a cross-package drift guard: a parity test imports this module alongside a hand-maintained mirror copy in the dashboard package and asserts the in-flight vocabulary and the combining function agree across the full phase space, because the two packages share no build and the mirror is a hand copy, not an import.

## Behavioral Requirements

### Data Shape

- **deploy-status-values**: A deploy status MUST be exactly one of `"success"`, `"failed"`, `"building"`, `"queued"`, `"canceled"`, or `"unknown"`.
- **build-phase-values**: A build phase MUST be exactly one of `"queued"`, `"building"`, `"built"`, `"failed"`, `"canceled"`, or `"unknown"`.
- **deploy-phase-values**: A deploy phase MUST be exactly one of `"none"`, `"deploying"`, `"deployed"`, `"failed"`, or `"unknown"`.
- **phases-shape**: A phases pair MUST carry exactly two fields: a build phase, which may be absent, and a deploy phase.
- **build-phase-null-meaning**: An absent build phase MUST be produced, and only produced, by a provider mapper for a platform that reports no build lifecycle of its own — a platform that lists only already-live deployments is the documented example; the Crunchy Bridge phase mapper (Crunchy Bridge has no build/deploy CI lifecycle at all) is this module's own such mapper.
- **unknown-phase-terminal**: A build phase or deploy phase value of `"unknown"` MUST be treated as terminal — an in-flight phase the monitor could not re-confirm before its expiry window elapsed (handled external to this module) — and MUST NOT be treated as a good or bad verdict; it is, like `"canceled"`, the absence of a verdict, but unlike `"canceled"` it MUST NOT be read as a claim that the provider itself stopped the work, and fresh provider truth (a poll or by-id re-fetch, external to this module) MUST be free to overwrite it.

### In-Flight Vocabulary

- **in-flight-build-phases-list**: The in-flight build-phase list MUST be exactly the two-element list `["building", "queued"]`.
- **in-flight-deploy-phase-value**: The in-flight deploy-phase value MUST be exactly `"deploying"`.
- **is-in-flight-definition**: The in-flight check, given a build phase and a deploy phase, MUST return `true` if and only if the build phase is a member of the in-flight build-phase list OR the deploy phase equals the in-flight deploy-phase value; this is THE definition of "still in flight" — the row states that can still change, with every other combination terminal.
- **is-in-flight-null-safe**: The in-flight check MUST return `false` for an absent build phase when the deploy phase is not the in-flight deploy-phase value, because an absent build phase is never a member of the in-flight build-phase list.
- **in-flight-build-order**: The build-phase ordering MUST list `"queued"` before `"building"`, reflecting that a build enters the queue once and leaves it once, so `"building"` is strictly later than `"queued"` and nothing walks that back; the deploy phase MUST have no equivalent ordering, because `"deploying"` is its only in-flight value and so has nothing to be out of order with.

### SQL Predicate Builders

- **in-flight-sql-shape**: The in-flight SQL-fragment builder, given a column prefix, MUST return the SQL boolean expression `(<prefix>build_phase IN ('building', 'queued') OR <prefix>deploy_phase = 'deploying')`, interpolating only the fixed literals of the in-flight vocabulary — never a caller-supplied value — so this fragment can never drift from the in-flight check.
- **in-flight-sql-default-prefix**: The in-flight SQL-fragment builder called with no argument MUST default the prefix to `""` (the stored row); passing `"excluded."` MUST produce the identical expression shape addressed at an upsert's incoming row instead.
- **column-overwritable-sql-per-column**: The per-column overwritable-predicate builder, given a column name and a prefix, MUST return a predicate testing only the single named column (`build_phase` or `deploy_phase`) against its own in-flight values OR `'unknown'`, and MUST NOT reference the sibling column; this is deliberately per-column so a real verdict on one lifecycle keeps its protection when the sibling lifecycle is `unknown` or in flight, rather than a whole-row predicate stripping that protection the moment either lifecycle is unknown.
- **webhook-keeps-stored-verdict-guard**: The webhook-guard predicate builder, given a column name, MUST include the term `(<incoming column is in flight> AND NOT <stored column is overwritable per the per-column predicate>)`, so a late in-flight webhook event landing on a row whose named column already holds a settled verdict MUST NOT overwrite that column.
- **webhook-keeps-stored-backwards-guard**: For the `build_phase` column only, the webhook-guard predicate builder MUST also include one term per pair of build-phase-ordering positions where the incoming value is earlier and the stored value is later (i.e. `(excluded.build_phase = 'queued' AND build_phase = 'building')`), derived from the build-phase ordering rather than hand-listed; for the `deploy_phase` column it MUST produce no backwards-guard terms at all, because `"deploying"` is that column's only in-flight value.
- **webhook-keeps-stored-terminal-exempt**: An incoming event whose value for the named column is itself terminal (not in the in-flight build-phase list / not equal to the in-flight deploy-phase value) MUST NOT be blocked by either term of the webhook-guard predicate, because the verdict-guard term requires the incoming value to be in flight and the backwards-guard term only ever matches two in-flight build values; a terminal event is the provider's current truth, and a re-promotion back into flight (e.g. `built` → rolling out again) is a legitimate move this predicate MUST permit.
- **collapse-build-sql**: The build-phase collapse builder, given a terminal value, MUST return `CASE WHEN build_phase IN ('building', 'queued') THEN '<value>' ELSE build_phase END`, leaving a settled (non-in-flight) build phase unchanged.
- **collapse-deploy-sql**: The deploy-phase collapse builder, given a terminal value, MUST return `CASE WHEN deploy_phase = 'deploying' THEN '<value>' ELSE deploy_phase END`, leaving a settled deploy phase unchanged.
- **collapse-sql-evaluates-current-row**: Both collapse builders MUST be expressed as a SQL `CASE` evaluated against the row's column value at update time, not a value captured earlier by the caller; this means a concurrent write landing between an external candidate read and this update is never clobbered.

### Provider Phase Mappers — Vercel

- **vercel-ready-to-built**: The Vercel phase mapper MUST map a ready state of `"READY"` to a build phase of `"built"`.
- **vercel-error-to-failed**: The Vercel phase mapper MUST map a ready state of `"ERROR"` to a build phase of `"failed"`.
- **vercel-canceled-deleted-to-canceled**: The Vercel phase mapper MUST map a ready state of `"CANCELED"` or `"DELETED"` to a build phase of `"canceled"`.
- **vercel-queued-to-queued**: The Vercel phase mapper MUST map a ready state of `"QUEUED"` to a build phase of `"queued"`.
- **vercel-fallback-to-building**: The Vercel phase mapper MUST map every ready-state value not covered above — `BUILDING`, `INITIALIZING`, `BLOCKED`, or any other string — to a build phase of `"building"`, per the mapping's documented fallthrough set.
- **vercel-deploy-production-gated**: The Vercel phase mapper MUST leave the deploy phase at `"none"` unless the build phase resolved to `"built"` AND the target is `"production"`; a build that is `"built"` on a non-production target is staged — built but never promoted — so it MUST get no deploy entry at all.
- **vercel-deploy-substate-mapping**: When the build phase is `"built"` and the target is `"production"`, the Vercel phase mapper MUST map a ready substate of `"PROMOTED"` to a deploy phase of `"deployed"`, a ready substate of `"ROLLING"` to a deploy phase of `"deploying"`, and every other ready-substate value (including absent) to a deploy phase of `"none"`.

### Provider Phase Mappers — Railway

- **railway-building-initializing**: The Railway phase mapper MUST map status `"BUILDING"` or `"INITIALIZING"` to a build phase of `"building"` and a deploy phase of `"none"`.
- **railway-deploying**: The Railway phase mapper MUST map status `"DEPLOYING"` to a build phase of `"built"` and a deploy phase of `"deploying"`.
- **railway-success-crashed**: The Railway phase mapper MUST map status `"SUCCESS"` or `"CRASHED"` to a build phase of `"built"` and a deploy phase of `"deployed"`; this is deliberate — a runtime crash after a successful build and deploy is a health concern, not a deploy failure.
- **railway-failed**: The Railway phase mapper MUST map status `"FAILED"` to a build phase of `"failed"` and a deploy phase of `"none"`; Railway's status vocabulary cannot separate a build failure from a deploy failure, and treating it as a build failure is the documented choice because build failure is the common case.
- **railway-waiting-needsapproval**: The Railway phase mapper MUST map status `"WAITING"` or `"NEEDSAPPROVAL"` to a build phase of `"queued"` and a deploy phase of `"none"`.
- **railway-removed-skipped**: The Railway phase mapper MUST map status `"REMOVED"` or `"SKIPPED"` to a build phase of `"canceled"` and a deploy phase of `"none"`.
- **railway-unrecognized-fallback**: The Railway phase mapper MUST map every status value not covered by the six cases above to a build phase of `"building"` and a deploy phase of `"none"` (the mapper's own documented default case).

### Provider Phase Mapper — Crunchy Bridge

- **crunchy-no-build-lifecycle**: The Crunchy Bridge phase mapper MUST always return an absent build phase, because Crunchy Bridge clusters have no build/deploy CI lifecycle — health is the cluster state alone.
- **crunchy-bad-state-detection**: The Crunchy Bridge phase mapper MUST return a deploy phase of `"failed"` when the suspended flag is `true`, OR when the cluster state is `"failed"`, `"creation_failed"`, or `"suspended"` (the three documented bad states), and MUST return a deploy phase of `"deployed"` otherwise.
- **crunchy-healthy-default**: Every cluster-state value other than the three documented bad states — including `"ready"`, every documented routine/transient operation (`creating`, `restarting`, `resizing`, `resuming`, `starting`, `upgrading`, `restoring`, `finalizing`, `replaying`, `destroying`, `suspending`), an empty string, and any unrecognized future value — MUST map to a deploy phase of `"deployed"`; this is a deliberate, owner-chosen "quieter" model: routine maintenance MUST NOT page, and an unrecognized state MUST NOT be assumed bad.
- **crunchy-phases-terminal**: Both fields the Crunchy Bridge phase mapper returns MUST always be terminal (the build phase is always absent, never an in-flight build phase; the deploy phase is always `"failed"` or `"deployed"`, never `"deploying"` or `"unknown"`), so that a caller's stuck-deploy check (external to this module) never misfires on a Crunchy Bridge cluster's arbitrarily old creation time.

### Combined Status Derivation

- **combined-status-evaluation-order**: The combining function MUST evaluate its rules in exactly this order, as a sequence of early returns rather than independent conditions, because a phases pair can match more than one rule and only the first matched rule's result is correct: failed, then canceled, then unknown, then deployed, then deploying, then built, then queued, then the default.
- **combined-status-failed-precedence**: The combining function MUST return `"failed"` when the build phase is `"failed"` OR the deploy phase is `"failed"`, checked before every other rule, so a failure verdict on one lifecycle wins even when the other lifecycle is `"unknown"`.
- **combined-status-canceled**: The combining function MUST return `"canceled"` when the build phase is `"canceled"`, checked after failed and before unknown.
- **combined-status-unknown-precedence**: The combining function MUST return `"unknown"` when the build phase is `"unknown"` OR the deploy phase is `"unknown"`, checked before the in-flight (`"deploying"`) and built/queued fallthrough rules, so a row whose lifecycle expired unconfirmable MUST NOT re-read as `"building"`.
- **combined-status-deployed-success**: The combining function MUST return `"success"` when the deploy phase is `"deployed"`.
- **combined-status-deploying-building**: The combining function MUST return `"building"` when the deploy phase is `"deploying"`.
- **combined-status-built-staged-success**: The combining function MUST return `"success"` when the build phase is `"built"` and none of the preceding rules matched — this is a build with no separate deploy step (non-production or staged).
- **combined-status-queued**: The combining function MUST return `"queued"` when the build phase is `"queued"` and none of the preceding rules matched.
- **combined-status-default-building**: The combining function MUST return `"building"` for every remaining combination — a build phase of `"building"`, an absent build phase with no matching deploy-phase rule, or any other combination not covered above.

## Appearance

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component.

## States

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component; its runtime lifecycle values (a build phase, a deploy phase, a deploy status) are data this module models and derives, not a visual-state table, and are specified under Behavioral Requirements.

## Accessibility

Not applicable — this is a status/deploy-phase vocabulary and SQL-fragment module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-deploy-status-001 | vercel-deploy-substate-mapping | The Vercel phase mapper given ready state `READY`, substate `PROMOTED`, target `production` | `{ build phase: 'built', deploy phase: 'deployed' }` |
| status-server-monitor-deploy-status-002 | vercel-error-to-failed | ...given ready state `ERROR`, no substate, no target | `{ build phase: 'failed', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-003 | vercel-deploy-production-gated | ...given ready state `READY`, no substate, no target (non-production) | `{ build phase: 'built', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-004 | vercel-canceled-deleted-to-canceled | ...given ready state `CANCELED`, no substate, no target | `{ build phase: 'canceled', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-005 | vercel-fallback-to-building | ...given ready state `BUILDING`, no substate, no target | `{ build phase: 'building', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-006 | vercel-queued-to-queued | ...given ready state `QUEUED`, no substate, no target | `{ build phase: 'queued', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-007 | vercel-deploy-substate-mapping | ...given ready state `READY`, substate `ROLLING`, target `production` | `{ build phase: 'built', deploy phase: 'deploying' }` |
| status-server-monitor-deploy-status-008 | railway-success-crashed | The Railway phase mapper given status `SUCCESS` | `{ build phase: 'built', deploy phase: 'deployed' }` |
| status-server-monitor-deploy-status-009 | railway-failed | ...given status `FAILED` | `{ build phase: 'failed', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-010 | railway-building-initializing | ...given status `BUILDING` | `{ build phase: 'building', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-011 | railway-deploying | ...given status `DEPLOYING` | `{ build phase: 'built', deploy phase: 'deploying' }` |
| status-server-monitor-deploy-status-012 | railway-removed-skipped | ...given status `REMOVED` | `{ build phase: 'canceled', deploy phase: 'none' }` |
| status-server-monitor-deploy-status-013 | railway-success-crashed | ...given status `CRASHED` | `{ build phase: 'built', deploy phase: 'deployed' }` — a runtime crash is not a deploy failure |
| status-server-monitor-deploy-status-014 | combined-status-deployed-success | The combining function given `{ build phase: 'built', deploy phase: 'deployed' }` | `'success'` |
| status-server-monitor-deploy-status-015 | combined-status-failed-precedence | ...given `{ build phase: 'failed', deploy phase: 'none' }` | `'failed'` |
| status-server-monitor-deploy-status-016 | combined-status-default-building | ...given `{ build phase: 'building', deploy phase: 'none' }` | `'building'` |
| status-server-monitor-deploy-status-017 | combined-status-queued | ...given `{ build phase: 'queued', deploy phase: 'none' }` | `'queued'` |
| status-server-monitor-deploy-status-018 | combined-status-canceled | ...given `{ build phase: 'canceled', deploy phase: 'none' }` | `'canceled'` |
| status-server-monitor-deploy-status-019 | combined-status-built-staged-success | ...given `{ build phase: 'built', deploy phase: 'none' }` | `'success'` |
| status-server-monitor-deploy-status-020 | combined-status-deploying-building | ...given `{ build phase: 'built', deploy phase: 'deploying' }` | `'building'` |
| status-server-monitor-deploy-status-021 | combined-status-unknown-precedence | ...given `{ build phase: 'unknown', deploy phase: 'none' }`; given `{ build phase: 'built', deploy phase: 'unknown' }` | Both `'unknown'` — an expired lifecycle never re-reads as building |
| status-server-monitor-deploy-status-022 | combined-status-evaluation-order, combined-status-failed-precedence | ...given `{ build phase: 'unknown', deploy phase: 'failed' }` | `'failed'` — a failure verdict still wins over an expired other lifecycle |
| status-server-monitor-deploy-status-023 | crunchy-bad-state-detection, crunchy-no-build-lifecycle | The Crunchy Bridge phase mapper given state `ready`, not suspended | `{ build phase: absent, deploy phase: 'deployed' }` |
| status-server-monitor-deploy-status-024 | crunchy-bad-state-detection | ...given state `ready`, suspended | `{ build phase: absent, deploy phase: 'failed' }` |
| status-server-monitor-deploy-status-025 | crunchy-bad-state-detection | ...given state `failed`, `creation_failed`, and `suspended` in turn, none suspended | All three `{ build phase: absent, deploy phase: 'failed' }` |
| status-server-monitor-deploy-status-026 | crunchy-healthy-default | ...given state `restarting`; given state `destroying`, neither suspended | Both `{ build phase: absent, deploy phase: 'deployed' }` — routine maintenance is not a problem |
| status-server-monitor-deploy-status-027 | crunchy-healthy-default | ...given an empty state string; given state `weird_unknown`, neither suspended | Both `{ build phase: absent, deploy phase: 'deployed' }` — an unrecognized state is not assumed bad |
| status-server-monitor-deploy-status-028 | is-in-flight-definition, is-in-flight-null-safe | The in-flight check given (`building`, `none`); given (`built`, `deployed`); given (an absent build phase, `deployed`) | `true`; `false`; `false` |
| status-server-monitor-deploy-status-029 | in-flight-sql-shape, in-flight-sql-default-prefix | The in-flight SQL-fragment builder with no argument | Exactly `"(build_phase IN ('building', 'queued') OR deploy_phase = 'deploying')"`, traced directly to the function body (no test asserts the literal string; see Compliance) |
| status-server-monitor-deploy-status-030 | collapse-build-sql | The build-phase collapse builder given the terminal value `canceled` | Exactly `"CASE WHEN build_phase IN ('building', 'queued') THEN 'canceled' ELSE build_phase END"`, traced directly to the function body |
| status-server-monitor-deploy-status-031 | is-in-flight-definition | The in-flight check as computed by each of the two independently maintained implementations, for every (build phase, deploy phase) pair over the full cross-product | All pairs equal |
| status-server-monitor-deploy-status-032 | combined-status-evaluation-order | The combining function as computed by each of the two independently maintained implementations, for every (build phase, deploy phase) pair over the full cross-product | All pairs equal |

## Edge Cases

- **Null and empty input**: an absent build phase MUST be accepted by the in-flight check, the combining function, and both SQL builders as a valid, terminal, non-matching value (build-phase-null-meaning, is-in-flight-null-safe) — MUST. The Crunchy Bridge phase mapper MUST treat an empty state string identically to any other unrecognized value — mapped to deploy phase `"deployed"` (crunchy-healthy-default, status-server-monitor-deploy-status-027) — MUST. None of the three provider phase mappers validates that its status argument is non-empty or a recognized literal before use; an empty or unrecognized value is not rejected, it is routed through each mapper's own documented fallback branch (vercel-fallback-to-building, railway-unrecognized-fallback, crunchy-healthy-default) — this is the mapper's declared contract, not an unvalidated-input gap.
- **Boundary values**: this module defines no numeric constraint; its only ordered boundary is the build-phase ordering's two positions, where `"queued"` MUST be treated as strictly earlier than `"building"` and nothing may reorder them (in-flight-build-order, webhook-keeps-stored-backwards-guard) — MUST.
- **Concurrent access**: every exported operation is a synchronous, pure computation over its arguments with no shared mutable state and no suspension point, so calls from any number of callers MUST NOT interleave in a way that changes any single call's result — MUST. The concurrency concern this module exists to resolve lives one layer down, in the SQL it builds: the build-phase and deploy-phase collapse builders MUST express their collapse as a conditional expression over the row's value at update time so a write racing between an external candidate read and that update is never clobbered (collapse-sql-evaluates-current-row), and the webhook-guard predicate builder MUST resolve out-of-order webhook delivery — documented as the ordinary case, not an exotic one — via the verdict guard and the build-phase backwards guard rather than any lock (webhook-keeps-stored-verdict-guard, webhook-keeps-stored-backwards-guard) — MUST.
- **Error states**: this module has no dependency of its own — no network call, no database access, no file I/O — so it has no error path to swallow, log, or surface; every operation returns a value for every input via an exhaustive branch structure with an explicit default/fallback branch, never a thrown exception. What a caller's own dependency (a provider's API; the storage layer that executes the SQL this module builds) does on failure is those callers' concern, external to this module.
- **Offline / disconnected state**: not applicable — this module makes no network connection of its own to lose; the fetchers that call the provider phase mappers (external to this module) own whatever happens when their own outbound call fails, and simply never call these pure mappers in that case.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Ready state, ready substate, target (inputs to the Vercel phase mapper) | string, optional string, optional string | none — caller-supplied per call | The Vercel deployment fields the caller (external) already fetched or received via webhook. |
| Status (input to the Railway phase mapper) | string | none — caller-supplied per call | The Railway deployment status field the caller already fetched or received via webhook. |
| State, suspended flag (inputs to the Crunchy Bridge phase mapper) | string, boolean | none — caller-supplied per call | The Crunchy Bridge cluster's documented state string and its compute-is-off flag, as fetched by the caller (external). |
| Prefix (input to the in-flight and per-column overwritable-predicate builders) | one of an empty prefix or an incoming-row alias prefix | empty prefix | Selects whether the built predicate reads the stored row (empty prefix) or an upsert's incoming row (the incoming-row alias). |
| Column (input to the per-column overwritable-predicate and webhook-guard predicate builders) | one of the two lifecycle column names | none — required | Selects which single lifecycle column the built predicate evaluates; the type itself is the only validation — no other value is accepted at construction time. |
| Target value (input to the build-phase and deploy-phase collapse builders) | a build phase / a deploy phase | none — required | The terminal value the built conditional expression collapses an in-flight column to. |

## Deep Linking

Not applicable: this module defines no application URL scheme or route of its own — it exports only vocabularies, constants, pure mapper functions, and SQL-fragment strings.

## Localization

Not applicable: this module emits no user-facing string; its literal vocabulary values (`success`, `failed`, `building`, `queued`, `canceled`, `unknown`, and the build-phase/deploy-phase members) are internal status codes that a UI layer external to this module is responsible for rendering and localizing.

## Accessibility Options

Not applicable: this module has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system of any kind.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: none of this module's own — it receives already-fetched provider status strings and cluster metadata as plain arguments from callers external to this module; it collects nothing itself.
- **Storage**: none. This module holds no state between calls and writes nothing; the SQL fragments it builds are executed by the storage layer, external to this module.
- **Transmission**: none. This module performs no network or database call; every SQL fragment it returns is a string handed back to its caller, which decides whether and how to execute it.
- **Retention**: not applicable — this module holds no data across calls.

## Logging

Not applicable: this module contains no logging call of any kind — every exported operation is a pure synchronous mapper or SQL-fragment builder with no side effects.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
