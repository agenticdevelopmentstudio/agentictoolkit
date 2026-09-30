<!-- leaf: implement-status-server-monitor-1/overall · source: status-server-monitor-overall.md -->

**Rules** (cite as `implement-status-server-monitor-1/overall#<slug>`):

- `overall-status-values` MUST
- `health-status-input` MUST
- `empty-statuses-is-unknown` MUST
- `all-down-is-major-outage` MUST
- `any-down-or-degraded-is-degraded` MUST
- `all-healthy-is-operational` MUST
- `compute-overall-check-order` MUST
- `public-overall-base` MUST
- `non-endpoint-problem-degrades-operational` MUST
- `non-endpoint-problem-never-escalates-past-degraded` MUST
- `non-endpoint-problem-never-lifts-unknown` MUST
- `non-endpoint-problem-never-overrides-major-outage` MUST
- `non-endpoint-problem-never-overrides-existing-degraded` MUST
- `no-problem-leaves-base-unchanged` MUST
- `pure-synchronous-functions` MUST
- `exported-surface` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statuses` (parameter of `computeOverall`) | `HealthStatus[]` | none — required | The per-endpoint health verdicts to roll up into one `OverallStatus`. |
| `statuses` (parameter of `publicOverall`) | `HealthStatus[]` | none — required | The same per-endpoint health verdicts, passed unchanged into `computeOverall` as the base rollup. |
| `hasNonEndpointProblem` (parameter of `publicOverall`) | `boolean` | none — required | Whether the caller has an open non-endpoint problem (e.g. a failed build or an unreachable platform API) to fold into the public headline. |

Neither function reads an environment variable, a settings key, or an injected dependency; both take their entire input as direct arguments, and `overall.ts` imports nothing at runtime beyond the type-only `HealthStatus` import from `./health`.

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
