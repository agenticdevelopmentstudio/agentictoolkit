---
id: da69d02d-a3a9-4018-a90a-becee268624a
title: Monitor Overall Status
domain: agentictoolkit://cookbook/status/service/monitor/overall
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure rollup deriving the four-value overall-status verdict from per-endpoint health checks, plus the public headline fold for non-endpoint problems.
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
- agentictoolkit://cookbook/status/service/monitor/health
references:
- packages/web/packages/status-server/src/monitor/overall.ts (agentictoolkit)
- packages/web/packages/status-server/test/overall.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/app.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Monitor Overall Status

## Overview

This module is the status backend's endpoint-health-to-headline rollup step. It exports the four-value overall-status vocabulary (`operational`, `degraded`, `major_outage`, `unknown`) and two pure operations. The base rollup folds a list of per-endpoint health values (the three-value vocabulary defined by the sibling health-classification module: `healthy`, `degraded`, `down`) into a single overall-status verdict: no endpoints reporting is `unknown`, every endpoint `down` is `major_outage`, any endpoint `down` or `degraded` short of all-down is `degraded`, and otherwise `operational`. The public headline fold computes the same base verdict via the base rollup and then folds in a second, non-endpoint signal: a live site can keep serving a successful response while its latest build or deploy fails, or while its deploy platform's API can't be polled — problems that never appear in the per-endpoint list — so the public headline fold takes a flag for whether a non-endpoint problem exists and, when the endpoint rollup is otherwise `operational`, lifts it to `degraded` rather than let the public headline claim "All systems operational" while a deploy is red. The fold never manufactures a full outage and never overrides an existing `major_outage` or `unknown` verdict. The base rollup is consumed directly by the authenticated status route and internally by the public headline fold; the public headline fold is consumed by the snapshot-building logic (external to this module), which supplies the non-endpoint-problem flag from any open board problem whose target is not a monitored endpoint slug, and whose result in turn drives the public wallboard text built by the host application (external to this module).

## Behavioral Requirements

### Data Shape

- **overall-status-values**: An overall status MUST be exactly one of `"operational"`, `"degraded"`, `"major_outage"`, or `"unknown"`.
- **health-status-input**: The per-endpoint list given to both the base rollup and the public headline fold MUST be a list whose elements are health values as defined by the health-classification module (`"healthy"`, `"degraded"`, or `"down"`); `"unknown"` is not a member of that vocabulary and therefore MUST NOT appear as an element of the list.

### Base Rollup

- **empty-statuses-is-unknown**: The base rollup MUST return `"unknown"` when the per-endpoint list is empty, independent of any other condition.
- **all-down-is-major-outage**: The base rollup MUST return `"major_outage"` when the per-endpoint list is non-empty and every element equals `"down"`.
- **any-down-or-degraded-is-degraded**: The base rollup MUST return `"degraded"` when the per-endpoint list is non-empty, not every element equals `"down"`, and at least one element equals `"down"` or `"degraded"`.
- **all-healthy-is-operational**: The base rollup MUST return `"operational"` when the per-endpoint list is non-empty and no element equals `"down"` or `"degraded"` — that is, every element equals `"healthy"`.
- **compute-overall-check-order**: The base rollup MUST evaluate its four conditions in exactly this order, returning on the first match: (1) empty list; (2) every element `"down"`; (3) some element `"down"` or `"degraded"`; (4) otherwise. This order is observable at the all-down boundary: an all-`"down"` list satisfies both condition (2) and condition (3), and condition (2) MUST take precedence, yielding `"major_outage"` rather than `"degraded"`.

### Public Headline Fold

- **public-overall-base**: The public headline fold MUST compute its base verdict by running the base rollup over the per-endpoint list with no transformation of it.
- **non-endpoint-problem-degrades-operational**: The public headline fold MUST return `"degraded"` when the base verdict is `"operational"` AND the non-endpoint-problem flag is `true`.
- **non-endpoint-problem-never-escalates-past-degraded**: when the base verdict is `"operational"` and the non-endpoint-problem flag is `true`, the public headline fold MUST return `"degraded"`, and MUST NOT return `"major_outage"` on the basis of that flag alone.
- **non-endpoint-problem-never-lifts-unknown**: The public headline fold MUST return `"unknown"` unchanged when the base verdict is `"unknown"`, regardless of the non-endpoint-problem flag.
- **non-endpoint-problem-never-overrides-major-outage**: The public headline fold MUST return `"major_outage"` unchanged when the base verdict is `"major_outage"`, regardless of the non-endpoint-problem flag.
- **non-endpoint-problem-never-overrides-existing-degraded**: The public headline fold MUST return `"degraded"` unchanged when the base verdict is already `"degraded"`, regardless of the non-endpoint-problem flag.
- **no-problem-leaves-base-unchanged**: The public headline fold MUST return the base verdict unchanged, for any base verdict, when the non-endpoint-problem flag is `false`.

### Purity and Exports

- **pure-synchronous-functions**: The base rollup and the public headline fold MUST be synchronous, side-effect-free operations whose return value is computed only from their arguments; neither MUST perform I/O, logging, or mutation of the per-endpoint list.
- **exported-surface**: The overall-status vocabulary MUST be exported as a type, and the base rollup and the public headline fold MUST both be exported as named operations, from this module.

## Appearance

Not applicable — this is a pure status-rollup function, not a visual component.

## States

Not applicable — this is a pure status-rollup function, not a visual component; the four-value overall-status outputs (`operational`, `degraded`, `major_outage`, `unknown`) are specified under Behavioral Requirements, not the visual-state table.

## Accessibility

Not applicable — this is a pure status-rollup function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-overall-001 | empty-statuses-is-unknown | The base rollup given an empty list | `'unknown'` |
| status-server-monitor-overall-002 | all-healthy-is-operational | ...given `['healthy', 'healthy']` | `'operational'` |
| status-server-monitor-overall-003 | any-down-or-degraded-is-degraded | ...given `['healthy', 'degraded']` | `'degraded'` |
| status-server-monitor-overall-004 | any-down-or-degraded-is-degraded | ...given `['healthy', 'down']` | `'degraded'` |
| status-server-monitor-overall-005 | all-down-is-major-outage, compute-overall-check-order | ...given `['down', 'down']` | `'major_outage'` — this input also satisfies any-down-or-degraded-is-degraded's condition, so this vector confirms check-order's precedence rather than only the final value |
| status-server-monitor-overall-006 | non-endpoint-problem-degrades-operational, public-overall-base | The public headline fold given `['healthy', 'healthy']` and a non-endpoint-problem flag of `true` | `'degraded'` |
| status-server-monitor-overall-007 | no-problem-leaves-base-unchanged | ...given `['healthy', 'healthy']` and a flag of `false` | `'operational'` |
| status-server-monitor-overall-008 | non-endpoint-problem-degrades-operational, non-endpoint-problem-never-escalates-past-degraded | ...given `['healthy']` and a flag of `true` | `'degraded'` — a non-endpoint problem never manufactures a full outage |
| status-server-monitor-overall-009 | non-endpoint-problem-never-overrides-major-outage | ...given `['down', 'down']` and a flag of `true` | `'major_outage'` — an all-endpoints-down verdict stands even with non-endpoint problems |
| status-server-monitor-overall-010 | non-endpoint-problem-never-overrides-existing-degraded | ...given `['healthy', 'down']` and a flag of `true` | `'degraded'` — an already-degraded endpoint rollup is unchanged by a non-endpoint problem |
| status-server-monitor-overall-011 | non-endpoint-problem-never-lifts-unknown | ...given an empty list and a flag of `true` | `'unknown'` — an unknown (no-signal) rollup is never lifted to degraded by a problem flag |
| status-server-monitor-overall-012 | overall-status-values | The four literals returned across the base rollup's and the public headline fold's branches | each is one of `'operational'`, `'degraded'`, `'major_outage'`, `'unknown'` — traced to the overall-status vocabulary's own declaration and the return literals used throughout the source |
| status-server-monitor-overall-013 | health-status-input | The per-endpoint list's element type is declared as the health vocabulary | construction-time rejection of an `"unknown"` element — traced to that declaration and the health vocabulary's three-value union; no runtime test exercises this since the type system enforces it at construction time |
| status-server-monitor-overall-014 | pure-synchronous-functions | Two sequential, independent calls to the base rollup given `['down']`, then again given `['down']` | both calls return `'degraded'` with neither call's result affected by the other — traced to the absence of any module-level mutable state or suspension point in the source |
| status-server-monitor-overall-015 | exported-surface | Import the base rollup, the public headline fold, and the overall-status type together | the import resolves all three names — traced to each declaration being exported |

## Edge Cases

- **Null and empty input**: an empty per-endpoint list MUST yield `"unknown"` from the base rollup, and from the public headline fold regardless of the non-endpoint-problem flag (empty-statuses-is-unknown, public-overall-base, non-endpoint-problem-never-lifts-unknown; status-server-monitor-overall-001, -011) — MUST. The per-endpoint list is typed as a list of health values, so there is no absent-element case at the type level; the non-endpoint-problem flag is a required boolean with no default, and the source performs no runtime check that a caller actually supplied a boolean — this is a caller precondition enforced by the type signature, not unvalidated input this operation's purpose calls for validating, since the public headline fold has exactly one caller in this codebase (external), which always supplies a computed boolean — MUST.
- **Boundary values**: a single-element per-endpoint list is the minimum non-empty boundary; `["down"]` MUST return `"major_outage"` from the base rollup (a match-all check over one element is trivially satisfied by all-down-is-major-outage), and `["degraded"]` or `["healthy"]` MUST return `"degraded"` or `"operational"` respectively (any-down-or-degraded-is-degraded, all-healthy-is-operational) — MUST. There is no declared maximum length on the per-endpoint list; the source imposes no upper-bound check, and both the match-all and match-any checks are evaluated over the full list regardless of length — MUST (no length ceiling exists to violate).
- **Concurrent access**: The base rollup and the public headline fold are synchronous, pure computations over their own arguments, with no shared mutable state, no module-level variable, and no suspension point of their own; any number of concurrent callers MUST NOT interleave in a way that changes any single call's result (pure-synchronous-functions) — MUST.
- **Error states**: neither operation contains an exception boundary, a raised error, or a dependency of its own — no network call, no database access, no file I/O — so there is no error path in this module for either operation to raise or swallow; under any input satisfying the declared parameter types, neither operation MUST throw — MUST.
- **Offline or disconnected state**: not applicable — the base rollup and the public headline fold make no network connection of their own to lose; they consume already-computed health values and a boolean flag that a caller external to this module derives from network- and database-backed state before calling either operation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Per-endpoint list (input to the base rollup) | a list of health values | none — required | The per-endpoint health verdicts to roll up into one overall status. |
| Per-endpoint list (input to the public headline fold) | a list of health values | none — required | The same per-endpoint health verdicts, passed unchanged into the base rollup. |
| Non-endpoint-problem flag (input to the public headline fold) | boolean | none — required | Whether the caller has an open non-endpoint problem (e.g. a failed build or an unreachable platform API) to fold into the public headline. |

Neither operation reads an environment variable, a settings key, or an injected dependency; both take their entire input as direct arguments, and this module imports nothing at runtime beyond the health vocabulary's type.

## Deep Linking

Not applicable: this module defines no route, URL pattern, or endpoint of its own; it exports only a type and two pure operations, consumed by route handlers external to this module (e.g. the status and snapshot handlers).

## Localization

Not applicable: this module emits no user-facing string; the base rollup and the public headline fold return only the internal overall-status literals (`operational`, `degraded`, `major_outage`, `unknown`), never displayed text — any operator- or public-facing label built from these values (e.g. the public wallboard's "experiencing issues" copy) is composed by callers external to this module.

## Accessibility Options

Not applicable: this module has no user interface and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this module consults no feature-flag system of any kind; the base rollup's and the public headline fold's behavior is unconditional for every input.

## Analytics

Not applicable: this module emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this module collects, stores, and transmits no data of its own; it receives already-computed health values and a boolean flag as plain arguments and returns an overall-status literal, retaining nothing between calls.

## Logging

Not applicable: this module contains no logging call of any kind; the base rollup and the public headline fold are pure synchronous operations with no side effects of their own.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `OverallStatus` as a `Sendable`, `String`-backed `enum` with cases `operational`, `degraded`, `majorOutage`, and `unknown`, and `computeOverall`/`publicOverall` as pure, non-isolated, synchronous top-level or static functions taking `[HealthStatus]` (per the sibling `status-server-monitor-health` recipe's Swift mapping) and, for the latter, a `Bool` — no `actor` or `@MainActor` isolation is needed because both functions are stateless and take no dependency.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `OverallStatus` as an `enum class`, and `computeOverall`/`publicOverall` as top-level functions using Kotlin's `List<HealthStatus>.all { }` and `.any { }` in place of the source's `Array.prototype.every`/`.some`, preserving the same four-branch, ordered early-return structure.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/overall.ts` as a plain ESM module on the Node status backend, importing only the `HealthStatus` type from the sibling `./health` module; `routes/reads.ts` imports `computeOverall`, `publicOverall`, and the `OverallStatus` type for its `/status` and `/snapshot` handlers, and `app.ts` consumes `buildSnapshot`'s resulting `overall` field (external to this file) when rendering the public wallboard.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern applies, and this file's statelessness means there is nothing to duplicate per-window or per-controller either.
- **WinUI 3**: a .NET port models `OverallStatus` as a C# `enum` (`Operational`, `Degraded`, `MajorOutage`, `Unknown`), and `ComputeOverall`/`PublicOverall` as `static` methods (e.g. on an `OverallStatusCalculator` class) using `IEnumerable<HealthStatus>.All(...)`/`.Any(...)` LINQ extension methods in place of the source's `.every`/`.some`, with `PublicOverall` taking a plain `bool hasNonEndpointProblem` parameter exactly as the source does. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed for this file specifically, since both methods are pure, synchronous, and hold no observable state — those APIs belong to the port of `routes/reads.ts` and `app.ts`, external to this recipe's given source.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/overall.ts` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
