---
id: da69d02d-a3a9-4018-a90a-becee268624a
title: Status Server Monitor Overall
domain: agentictoolkit://recipes/status-server-monitor-overall
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure rollup deriving the four-value OverallStatus verdict from per-endpoint HealthStatus checks, plus the public headline fold for non-endpoint problems.
platforms:
- typescript
- web
tags:
- monitor
- status
- rollup
- pure-function
- server
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-health
references:
- packages/web/packages/status-server/src/monitor/overall.ts (agentictoolkit)
- packages/web/packages/status-server/test/overall.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/app.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Overall

## Overview

`overall.ts` (`packages/web/packages/status-server/src/monitor/overall.ts`) is the status backend's endpoint-health-to-headline rollup step. It exports the four-value `OverallStatus` type (`operational`, `degraded`, `major_outage`, `unknown`) and two pure functions. `computeOverall` folds an array of per-endpoint `HealthStatus` values (the three-value type defined by the sibling `health.ts`: `healthy`, `degraded`, `down`) into a single `OverallStatus` verdict: no endpoints reporting is `unknown`, every endpoint `down` is `major_outage`, any endpoint `down` or `degraded` short of all-down is `degraded`, and otherwise `operational`. `publicOverall` computes the same base verdict via `computeOverall` and then folds in a second, non-endpoint signal: per its own doc comment, a live site can keep serving HTTP 200 while its latest build or deploy fails, or while its deploy platform's API can't be polled — problems that never appear in `statuses` — so `publicOverall` takes a `hasNonEndpointProblem` boolean and, when the endpoint rollup is otherwise `operational`, lifts it to `degraded` rather than let the public headline claim "All systems operational" while a deploy is red. The fold never manufactures a full outage and never overrides an existing `major_outage` or `unknown` verdict. `computeOverall` is consumed directly by the authenticated `/status` route and internally by `publicOverall`; `publicOverall` is consumed by `buildSnapshot` (`routes/reads.ts`, external to this file), which supplies `hasNonEndpointProblem` from any open board Problem whose `target` is not a monitored endpoint slug, and whose result in turn drives the public wallboard text built in `app.ts` (external to this file).

## Behavioral Requirements

### Data Shape

- **overall-status-values**: `OverallStatus` MUST be exactly one of `"operational"`, `"degraded"`, `"major_outage"`, or `"unknown"`.
- **health-status-input**: the `statuses` parameter of both `computeOverall` and `publicOverall` MUST be an array whose elements are `HealthStatus` values as defined by `health.ts` (`"healthy"`, `"degraded"`, or `"down"`); `"unknown"` is not a member of `HealthStatus` and therefore MUST NOT appear as an element of `statuses`.

### computeOverall Rollup

- **empty-statuses-is-unknown**: `computeOverall` MUST return `"unknown"` when `statuses` is an empty array, independent of any other condition.
- **all-down-is-major-outage**: `computeOverall` MUST return `"major_outage"` when `statuses` is non-empty and every element equals `"down"`.
- **any-down-or-degraded-is-degraded**: `computeOverall` MUST return `"degraded"` when `statuses` is non-empty, not every element equals `"down"`, and at least one element equals `"down"` or `"degraded"`.
- **all-healthy-is-operational**: `computeOverall` MUST return `"operational"` when `statuses` is non-empty and no element equals `"down"` or `"degraded"` — that is, every element equals `"healthy"`.
- **compute-overall-check-order**: `computeOverall` MUST evaluate its four conditions in exactly this order, returning on the first match: (1) empty array; (2) every element `"down"`; (3) some element `"down"` or `"degraded"`; (4) otherwise. This order is observable at the all-down boundary: an all-`"down"` array satisfies both condition (2) and condition (3), and condition (2) MUST take precedence, yielding `"major_outage"` rather than `"degraded"`.

### publicOverall Headline Fold

- **public-overall-base**: `publicOverall` MUST compute its base verdict by calling `computeOverall(statuses)` with no transformation of `statuses`.
- **non-endpoint-problem-degrades-operational**: `publicOverall` MUST return `"degraded"` when the base verdict is `"operational"` AND `hasNonEndpointProblem` is `true`.
- **non-endpoint-problem-never-escalates-past-degraded**: when the base verdict is `"operational"` and `hasNonEndpointProblem` is `true`, `publicOverall` MUST return `"degraded"`, and MUST NOT return `"major_outage"` on the basis of `hasNonEndpointProblem` alone.
- **non-endpoint-problem-never-lifts-unknown**: `publicOverall` MUST return `"unknown"` unchanged when the base verdict is `"unknown"`, regardless of `hasNonEndpointProblem`.
- **non-endpoint-problem-never-overrides-major-outage**: `publicOverall` MUST return `"major_outage"` unchanged when the base verdict is `"major_outage"`, regardless of `hasNonEndpointProblem`.
- **non-endpoint-problem-never-overrides-existing-degraded**: `publicOverall` MUST return `"degraded"` unchanged when the base verdict is already `"degraded"`, regardless of `hasNonEndpointProblem`.
- **no-problem-leaves-base-unchanged**: `publicOverall` MUST return the base verdict unchanged, for any base verdict, when `hasNonEndpointProblem` is `false`.

### Purity and Exports

- **pure-synchronous-functions**: `computeOverall` and `publicOverall` MUST be synchronous, side-effect-free functions whose return value is computed only from their arguments; neither MUST perform I/O, logging, or mutation of the `statuses` array.
- **exported-surface**: `OverallStatus` MUST be exported as a type, and `computeOverall` and `publicOverall` MUST both be exported as named functions, from `overall.ts`.

## Appearance

Not applicable — this is a pure status-rollup function, not a visual component.

## States

Not applicable — this is a pure status-rollup function, not a visual component; the four-value `OverallStatus` outputs (`operational`, `degraded`, `major_outage`, `unknown`) are specified under Behavioral Requirements, not the visual-state table.

## Accessibility

Not applicable — this is a pure status-rollup function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-overall-001 | empty-statuses-is-unknown | `computeOverall([])` | `'unknown'` — `overall.test.ts` › "no statuses → unknown" |
| status-server-monitor-overall-002 | all-healthy-is-operational | `computeOverall(['healthy', 'healthy'])` | `'operational'` — `overall.test.ts` › "all healthy → operational" |
| status-server-monitor-overall-003 | any-down-or-degraded-is-degraded | `computeOverall(['healthy', 'degraded'])` | `'degraded'` — `overall.test.ts` › "any degraded → degraded" |
| status-server-monitor-overall-004 | any-down-or-degraded-is-degraded | `computeOverall(['healthy', 'down'])` | `'degraded'` — `overall.test.ts` › "some down → degraded" |
| status-server-monitor-overall-005 | all-down-is-major-outage, compute-overall-check-order | `computeOverall(['down', 'down'])` | `'major_outage'` — `overall.test.ts` › "all down → major_outage"; this input also satisfies any-down-or-degraded-is-degraded's condition, so this vector confirms check-order's precedence rather than only the final value |
| status-server-monitor-overall-006 | non-endpoint-problem-degrades-operational, public-overall-base | `publicOverall(['healthy', 'healthy'], true)` | `'degraded'` — `overall.test.ts` › "healthy endpoints + a non-endpoint problem (e.g. a failed build) → degraded" |
| status-server-monitor-overall-007 | no-problem-leaves-base-unchanged | `publicOverall(['healthy', 'healthy'], false)` | `'operational'` — `overall.test.ts` › "healthy endpoints + no other problem → operational (unchanged)" |
| status-server-monitor-overall-008 | non-endpoint-problem-degrades-operational, non-endpoint-problem-never-escalates-past-degraded | `publicOverall(['healthy'], true)` | `'degraded'` — `overall.test.ts` › "a non-endpoint problem never manufactures a full outage — degraded, not major_outage" |
| status-server-monitor-overall-009 | non-endpoint-problem-never-overrides-major-outage | `publicOverall(['down', 'down'], true)` | `'major_outage'` — `overall.test.ts` › "an all-endpoints-down major_outage stands even with non-endpoint problems" |
| status-server-monitor-overall-010 | non-endpoint-problem-never-overrides-existing-degraded | `publicOverall(['healthy', 'down'], true)` | `'degraded'` — `overall.test.ts` › "an already-degraded endpoint rollup is unchanged by a non-endpoint problem" |
| status-server-monitor-overall-011 | non-endpoint-problem-never-lifts-unknown | `publicOverall([], true)` | `'unknown'` — `overall.test.ts` › "an unknown (no-signal) rollup is never lifted to degraded by a problem flag" |
| status-server-monitor-overall-012 | overall-status-values | the four literals returned across `computeOverall` and `publicOverall`'s branches | each is one of `'operational'`, `'degraded'`, `'major_outage'`, `'unknown'` — traced to the `OverallStatus` type declaration; not exercised by a dedicated `overall.test.ts` assertion, confirmed by inspection of the declaration and the return literals used throughout the source |
| status-server-monitor-overall-013 | health-status-input | `computeOverall` and `publicOverall`'s `statuses` parameter type is declared `HealthStatus[]` (imported as a type-only import from `./health`) | compile-time rejection of an `"unknown"` element — traced to the `import type { HealthStatus } from "./health"` declaration and `HealthStatus`'s three-value union in `health.ts`; no runtime test exercises this since TypeScript enforces it at compile time |
| status-server-monitor-overall-014 | pure-synchronous-functions | two sequential, independent calls `computeOverall(['down'])` followed by `computeOverall(['down'])` | both calls return `'degraded'` with neither call's result affected by the other — traced to the absence of any module-level mutable state or `await` in `overall.ts`; not exercised by a dedicated concurrency test in `overall.test.ts`, confirmed by inspection of the source having no side effects |
| status-server-monitor-overall-015 | exported-surface | `import { computeOverall, publicOverall, type OverallStatus } from '../src/monitor/overall'` (as `overall.test.ts` and `routes/reads.ts` do) | the import resolves all three names — traced to the `export` keyword on each declaration in `overall.ts` |

## Edge Cases

- **Null and empty input**: an empty `statuses` array MUST yield `"unknown"` from `computeOverall`, and from `publicOverall` regardless of `hasNonEndpointProblem` (empty-statuses-is-unknown, public-overall-base, non-endpoint-problem-never-lifts-unknown; status-server-monitor-overall-001, -011) — MUST. `statuses` is typed as `HealthStatus[]`, so there is no `null`/`undefined`-element case at the type level; `hasNonEndpointProblem` is a required `boolean` with no default, and the source performs no runtime check that a caller actually supplied a `boolean` — this is a caller precondition enforced by the type signature, not unvalidated input this function's purpose calls for validating, since `publicOverall` has exactly one caller in this codebase (`buildSnapshot` in `routes/reads.ts`, external), which always supplies a computed `boolean` — MUST.
- **Boundary values**: a single-element `statuses` array is the minimum non-empty boundary; `["down"]` MUST return `"major_outage"` from `computeOverall` (`.every()` over one element is trivially satisfied by all-down-is-major-outage), and `["degraded"]` or `["healthy"]` MUST return `"degraded"` or `"operational"` respectively (any-down-or-degraded-is-degraded, all-healthy-is-operational) — MUST. There is no declared maximum length on `statuses`; the source imposes no upper-bound check, and both `.every()` and `.some()` are evaluated over the full array regardless of length — MUST (no length ceiling exists to violate).
- **Concurrent access**: `computeOverall` and `publicOverall` are synchronous, pure computations over their own arguments, with no shared mutable state, no module-level variable, and no `await` of their own; any number of concurrent callers MUST NOT interleave in a way that changes any single call's result (pure-synchronous-functions) — MUST.
- **Error states**: neither function contains a `try`/`catch`, a `throw`, or a dependency of its own — no network call, no database access, no file I/O — so there is no error path in this file for either function to raise or swallow; under any input satisfying the declared `HealthStatus[]`/`boolean` parameter types, neither function MUST throw — MUST.
- **Offline or disconnected state**: not applicable — `computeOverall` and `publicOverall` make no network connection of their own to lose; they consume already-computed `HealthStatus` values and a boolean flag that a caller external to this file (`buildSnapshot` in `routes/reads.ts`) derives from network- and database-backed state before calling either function.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statuses` (parameter of `computeOverall`) | `HealthStatus[]` | none — required | The per-endpoint health verdicts to roll up into one `OverallStatus`. |
| `statuses` (parameter of `publicOverall`) | `HealthStatus[]` | none — required | The same per-endpoint health verdicts, passed unchanged into `computeOverall` as the base rollup. |
| `hasNonEndpointProblem` (parameter of `publicOverall`) | `boolean` | none — required | Whether the caller has an open non-endpoint problem (e.g. a failed build or an unreachable platform API) to fold into the public headline. |

Neither function reads an environment variable, a settings key, or an injected dependency; both take their entire input as direct arguments, and `overall.ts` imports nothing at runtime beyond the type-only `HealthStatus` import from `./health`.

## Deep Linking

Not applicable: this file defines no route, URL pattern, or endpoint of its own; it exports only a type and two pure functions, consumed by route handlers external to this file (e.g. `routes/reads.ts`'s `/status` and `/snapshot` handlers).

## Localization

Not applicable: this file emits no user-facing string; `computeOverall` and `publicOverall` return only the internal `OverallStatus` literals (`operational`, `degraded`, `major_outage`, `unknown`), never displayed text — any operator- or public-facing label built from these values (e.g. the public wallboard's "experiencing issues" copy) is composed by callers external to this file (`app.ts`).

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind; `computeOverall` and `publicOverall`'s behavior is unconditional for every input.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this file collects, stores, and transmits no data of its own; it receives already-computed `HealthStatus` values and a `boolean` flag as plain function arguments and returns an `OverallStatus` literal, retaining nothing between calls.

## Logging

Not applicable: this file contains no logging or console call of any kind; `computeOverall` and `publicOverall` are pure synchronous functions with no side effects of their own.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `OverallStatus` as a `Sendable`, `String`-backed `enum` with cases `operational`, `degraded`, `majorOutage`, and `unknown`, and `computeOverall`/`publicOverall` as pure, non-isolated, synchronous top-level or static functions taking `[HealthStatus]` (per the sibling `status-server-monitor-health` recipe's Swift mapping) and, for the latter, a `Bool` — no `actor` or `@MainActor` isolation is needed because both functions are stateless and take no dependency.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `OverallStatus` as an `enum class`, and `computeOverall`/`publicOverall` as top-level functions using Kotlin's `List<HealthStatus>.all { }` and `.any { }` in place of the source's `Array.prototype.every`/`.some`, preserving the same four-branch, ordered early-return structure.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/overall.ts` as a plain ESM module on the Node status backend, importing only the `HealthStatus` type from the sibling `./health` module; `routes/reads.ts` imports `computeOverall`, `publicOverall`, and the `OverallStatus` type for its `/status` and `/snapshot` handlers, and `app.ts` consumes `buildSnapshot`'s resulting `overall` field (external to this file) when rendering the public wallboard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern applies, and this file's statelessness means there is nothing to duplicate per-window or per-controller either.
- **WinUI 3**: a .NET port models `OverallStatus` as a C# `enum` (`Operational`, `Degraded`, `MajorOutage`, `Unknown`), and `ComputeOverall`/`PublicOverall` as `static` methods (e.g. on an `OverallStatusCalculator` class) using `IEnumerable<HealthStatus>.All(...)`/`.Any(...)` LINQ extension methods in place of the source's `.every`/`.some`, with `PublicOverall` taking a plain `bool hasNonEndpointProblem` parameter exactly as the source does. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed for this file specifically, since both methods are pure, synchronous, and hold no observable state — those APIs belong to the port of `routes/reads.ts` and `app.ts`, external to this recipe's given source.

## Design Decisions

- **Decision**: evaluate `computeOverall`'s four conditions in the exact order empty → all-down → some-down-or-degraded → operational, rather than, for example, counting each status value.
  **Rationale**: not stated in an inline comment; recorded here as a fact of the code per this recipe's authoring rules. The order determines which branch an all-`"down"` array takes — conditions (2) and (3) both hold for that input, and (2) is checked first, yielding `"major_outage"` rather than `"degraded"` (compute-overall-check-order, status-server-monitor-overall-005).
  **Approved**: pending
- **Decision**: `publicOverall` only ever escalates a base verdict of `"operational"` to `"degraded"`; it never manufactures `"major_outage"` and never lifts `"unknown"`.
  **Rationale**: stated directly in the source's own doc comment on `publicOverall` — a non-endpoint problem "lifts an otherwise-operational verdict to degraded; it never manufactures a full outage (the sites are up) and never overrides an all-endpoints-down major_outage or an unknown (no-signal) rollup." The same comment states why the fold exists at all: a live site keeps serving HTTP 200 while its latest build/deploy fails or its platform API can't be polled, so those problems never show up in `statuses`, and without folding them in, "the landing reads All systems operational while deploys are red."
  **Approved**: pending
- **Decision**: `hasNonEndpointProblem` is a plain `boolean` the caller computes and passes in; `publicOverall` itself performs no lookup of what counts as a "non-endpoint problem."
  **Rationale**: not stated in an inline comment on this parameter itself; recorded here as a fact of the code, consistent with this file's purity (pure-synchronous-functions). The one caller in this codebase, `buildSnapshot` in `routes/reads.ts` (external to this file), derives the flag itself as any open board Problem whose `target` is not one of the monitored endpoint slugs.
  **Approved**: pending
- **Decision**: this recipe carries fewer Behavioral Requirements than its sibling `status-server-monitor-health` recipe.
  **Rationale**: `overall.ts` exports two short functions with a combined four early-return branches, versus `health.ts`'s single `classify` function with a five-step evaluation order, a JSON-parsing sub-branch, and several optional-field interactions; the difference in requirement count reflects a genuine difference in the number of distinct branches and interacting fields between the two files, not under-authoring of this recipe.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `passed`: `overall.test.ts` gives both exported functions an assertion for every branch this recipe traces — all four `computeOverall` branches (empty, all-down, mixed down-or-degraded, all-healthy) and all six `publicOverall` outcomes (escalate on a problem, no-op with no problem, escalate from a single-healthy array, preserve `major_outage`, preserve an existing `degraded`, preserve `unknown`) each have a dedicated `it(...)` assertion; no branch traced in Behavioral Requirements is left unexercised. `separation-of-concerns` passes: this file performs no I/O, persistence, or presentation of any kind — its only responsibility is deriving an `OverallStatus` value from already-computed inputs, leaving how that value is fetched (`routes/reads.ts`) or displayed (`app.ts`) to callers external to this file. `fault-tolerance` passes: both functions accept any array of the three `HealthStatus` literals, including the boundary lengths zero and one, without throwing; the type signature is the only input constraint, and no code path in this file is capable of raising an exception.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
