---
id: 88dabdf6-14a3-44eb-ab0d-ae18007c683e
title: Monitor Uptime
domain: agentictoolkit://cookbook/status/service/monitor/uptime
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure per-day uptime-percentage and health-verdict arithmetic over check counts, plus the unweighted mean that rolls per-service percentages into one portfolio number.
platforms:
- typescript
- web
tags:
- monitor
- uptime
- rollup
- pure-function
- server
depends-on: []
related:
- agentictoolkit://cookbook/status/service/monitor/health
- agentictoolkit://cookbook/status/service/monitor/overall
references:
- packages/web/packages/status-server/src/monitor/uptime.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/reads.ts (agentictoolkit)
- packages/web/packages/status-server/test/reads.int.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/uptime.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/uptime.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/components/OverviewTab.tsx (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Monitor Uptime

## Overview

This component is the status backend's pure uptime-arithmetic step: it turns
a day's (or a totals accumulation's) check tally — `total`, `healthy`,
`degraded`, `down` check counts for one endpoint — into a rounded uptime
percentage and a health status verdict, and separately turns a list of
per-service uptime percentages into one unweighted portfolio-wide
percentage. It performs no I/O of its own. It declares the check-tally shape
and three calculations: the uptime-percentage calculation, the day-status
classification, and the overall-uptime mean. The uptime-percentage
calculation and the day-status classification are consumed by the route
builder that produces the uptime response from stored daily counts; the
overall-uptime mean has no caller within this component's own host — see
Platform Notes for where each calculation is actually used and independently
duplicated.

## Behavioral Requirements

### Data Shape

- **counts-shape**: The check tally MUST carry exactly four numeric fields — `total`, `healthy`, `degraded`, and `down` — each an aggregated count of checks for one endpoint over one accounting period (one day, or a summed range of days).
- **health-status-return**: The day-status classification MUST return one of exactly the three health status string literals — `"healthy"`, `"degraded"`, or `"down"` — and no other value.

### Uptime-Percentage Calculation

- **uptime-percent-formula**: When the total check count is greater than `0`, the uptime-percentage calculation MUST return the healthy-plus-degraded share of total checks, expressed as a percentage rounded to two decimal places (numerically, `round(((healthy + degraded) / total) * 10000) / 100`).
- **uptime-percent-degraded-counts-as-up**: The uptime-percentage calculation MUST count a `degraded` check together with a `healthy` check as up-time; only a `down` check reduces the returned percentage.
- **uptime-percent-no-data**: The uptime-percentage calculation MUST return `null`, without evaluating any ratio, whenever the total check count is less than or equal to `0`.

### Day-Status Classification

- **day-status-down-majority**: The day-status classification MUST return `"down"` when the down count is greater than `0` and the down-to-total ratio is strictly greater than `0.5`.
- **day-status-down-minority**: The day-status classification MUST return `"degraded"` when the down count is greater than `0` and the down-to-total ratio is `0.5` or less.
- **day-status-degraded-only**: The day-status classification MUST return `"degraded"` when the down count is `0` and the degraded count is greater than `0`.
- **day-status-healthy-default**: The day-status classification MUST return `"healthy"` when both the down and degraded counts are `0`, regardless of the value of the total or healthy count.
- **day-status-no-zero-total-guard**: The day-status classification MUST NOT special-case a total of zero or less the way the uptime-percentage calculation does; a day with zero checks of every kind MUST fall through to the same `"healthy"` result as a day that was actually checked and found fully healthy.

### Overall-Uptime Mean

- **overall-uptime-mean**: The overall-uptime mean MUST return the arithmetic mean, rounded to two decimal places, of the uptime-percentage field across every service entry whose uptime percentage is not `null`.
- **overall-uptime-excludes-null**: The overall-uptime mean MUST exclude any entry whose uptime-percentage field is `null` from both the sum and the divisor used to compute the mean; a service with no data MUST NOT be treated as a `0` and MUST NOT change the count of averaged entries.
- **overall-uptime-no-data**: The overall-uptime mean MUST return `null` when the service list is empty, or when every entry's uptime percentage is `null`.
- **overall-uptime-order-independent**: The overall-uptime mean's result MUST be independent of the order of the service list, since it computes an unweighted arithmetic mean over the entries that qualify.

### Purity and Concurrency

- **pure-computation**: The uptime-percentage calculation, the day-status classification, and the overall-uptime mean MUST perform no I/O and MUST mutate no argument, computing their return value solely from the arguments passed on that call.
- **concurrency-safety**: Because none of the three calculations read or write any shared state, they MUST be safely callable concurrently, in any order, from multiple callers (for example the same process handling several requests at once) without one call's result depending on another's.

## Appearance

Not applicable — this is a pure uptime and status arithmetic component, not a visual component.

## States

Not applicable — this is a pure uptime and status arithmetic component, not a visual component; its runtime behavior (the zero-total branch in the uptime-percentage calculation, the down/degraded/healthy branches in the day-status classification, and the null-filtering branch in the overall-uptime mean) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a pure uptime and status arithmetic component, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-uptime-001 | uptime-percent-formula, uptime-percent-degraded-counts-as-up | The uptime-percentage calculation given a tally of `{ total: 100, healthy: 90, degraded: 5, down: 5 }` | `95` |
| status-server-monitor-uptime-002 | uptime-percent-no-data | The uptime-percentage calculation given a tally of `{ total: 0, healthy: 0, degraded: 0, down: 0 }` | `null` |
| status-server-monitor-uptime-003 | uptime-percent-formula | The uptime-percentage calculation given a tally of `{ total: 3, healthy: 1, degraded: 1, down: 1 }` | `66.67` (2 of 3 checks up, rounded to two decimal places) |
| status-server-monitor-uptime-004 | day-status-down-majority | The day-status classification given a tally of `{ total: 10, healthy: 2, degraded: 0, down: 8 }` | `"down"` (`8/10 = 0.8`, greater than `0.5`) |
| status-server-monitor-uptime-005 | day-status-down-minority | The day-status classification given a tally of `{ total: 10, healthy: 7, degraded: 0, down: 3 }` | `"degraded"` (`3/10 = 0.3`, not greater than `0.5`) |
| status-server-monitor-uptime-006 | day-status-degraded-only | The day-status classification given a tally of `{ total: 10, healthy: 8, degraded: 2, down: 0 }` | `"degraded"` |
| status-server-monitor-uptime-007 | day-status-healthy-default | The day-status classification given a tally of `{ total: 10, healthy: 10, degraded: 0, down: 0 }` | `"healthy"` |
| status-server-monitor-uptime-008 | day-status-no-zero-total-guard | The day-status classification given a tally of `{ total: 0, healthy: 0, degraded: 0, down: 0 }` | `"healthy"` (the default fall-through); contrast with vector 002, the identical input returning `null` from the uptime-percentage calculation |
| status-server-monitor-uptime-009 | overall-uptime-mean | The overall-uptime mean given `[{ uptimePercent: 100 }, { uptimePercent: 90 }]` | `95` |
| status-server-monitor-uptime-010 | overall-uptime-excludes-null | The overall-uptime mean given `[{ uptimePercent: 99 }, { uptimePercent: null }, { uptimePercent: 95 }]` | `97` (mean of `99` and `95` only; the divisor is `2`, not `3`) |
| status-server-monitor-uptime-011 | overall-uptime-no-data | The overall-uptime mean given an empty list | `null` |
| status-server-monitor-uptime-012 | overall-uptime-no-data | The overall-uptime mean given `[{ uptimePercent: null }]` | `null` |
| status-server-monitor-uptime-013 | uptime-percent-formula (caller integration) | A request for a 90-day uptime window against seeded per-day check rows for one configured endpoint | The first service's uptime percentage is `50` — integration evidence for the same formula reached through the route that calls it |
| status-server-monitor-uptime-014 | pure-computation, concurrency-safety | The uptime-percentage calculation and the day-status classification both called on the same tally `{ total: 10, healthy: 10, degraded: 0, down: 0 }`, repeated and interleaved with calls using other tallies | Every call returns the same value for the same input every time (`100` and `"healthy"`), and the tally's own fields are unchanged after any call |
| status-server-monitor-uptime-015 | counts-shape, health-status-return | The day-status classification's return value inspected across vectors 004–008 | Every returned value is one of exactly `"healthy"`, `"degraded"`, or `"down"` |

## Edge Cases

- **Null and empty input**: the overall-uptime mean given an empty list MUST return `null` (overall-uptime-no-data). A check tally with every field `0` MUST return `null` from the uptime-percentage calculation (uptime-percent-no-data) and `"healthy"` from the day-status classification (day-status-no-zero-total-guard) — the SAME input yields two different-looking answers depending on which calculation is applied — MUST.
- **Boundary values**: the strictly-greater-than-a-half comparison in the day-status classification is strict, so a down-ratio of EXACTLY `0.5` (for example `{ total: 10, healthy: 0, degraded: 5, down: 5 }`) MUST return `"degraded"`, not `"down"` — MUST. The uptime-percentage calculation's rounding can land on a repeating fraction (vector 003, `2/3`); the rounding rule always resolves such a value to a definite two-decimal-place number rather than leaving extra precision — MUST.
- **Concurrent access**: none of the three calculations read or write shared state, so concurrent or repeated calls — from multiple requests handled by the same process, or from a separately maintained copy running elsewhere entirely — can never interleave in a way that corrupts a result; each call is isolated to its own arguments (pure-computation, concurrency-safety) — MUST.
- **Error states**: none of the three calculations can throw, reject, or return an error value for any input conforming to their declared shape — there is no failure path anywhere in this component. A caller that passes a tally or service list not conforming to the declared shape (for example a missing field) is not guarded against at runtime; ordinary arithmetic on a missing value produces a non-numeric result, which propagates through the rounding step rather than throwing — this is a SHOULD-level caller precondition enforced only by the declared shape, not a runtime validation this component performs; the one caller that builds a tally always does so from a reduction over already-numeric database rows, so the malformed-shape case does not occur in the traced call path.
- **Offline / disconnected state**: not applicable — this component makes no network call and no database call of any kind; nothing in it can be affected by a lost connection.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| the check tally (the uptime-percentage calculation's and day-status classification's argument) | a four-field numeric record (`{ total, healthy, degraded, down }`) | none — required on every call | The per-endpoint check counts to score. Supplied fresh by the caller on each call; never defaulted, cached, or read from configuration by this component. |
| the service list (the overall-uptime mean's argument) | a list of records each carrying a nullable `uptimePercent` | none — required on every call | The list of already-computed per-service uptime percentages to average. Supplied fresh by the caller on each call; never defaulted, cached, or read from configuration by this component. |

This component reads no environment variable, consults no settings or feature-flag store, and receives no injected dependency of any kind — every value it needs arrives as a plain argument on that call.

## Deep Linking

Not applicable: this component defines no route and no URL scheme of its own — it exposes three pure calculations and one data shape, consumed in-process by the route that builds the uptime response and by a separately maintained copy elsewhere.

## Localization

Not applicable: the component returns only numbers (or `null`) and one of three fixed health status string literals (`"healthy"`, `"degraded"`, `"down"`) — internal status codes, not natural-language, end-user-facing text; it defines no localizable string of its own. Any user-facing label derived from these values is the caller's responsibility, outside this component.

## Accessibility Options

Not applicable: this is a pure arithmetic component with no UI; it responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the component consults no feature-flag system; its only conditional gating — the zero-or-less-total check in the uptime-percentage calculation — is plain data-driven arithmetic, not a flag lookup.

## Analytics

Not applicable: the component emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this component collects, stores, transmits, and retains nothing on its own — it computes derived numbers from caller-supplied, already-aggregated integer check counts and percentages; none of the check tally's fields or the computed percentages carry personal or sensitive data.

## Logging

Not applicable: the component contains no logging statement of any kind.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models the check tally as a `Sendable` `struct` with four `Int` fields (`total`, `healthy`, `degraded`, `down`), and health status as a `Sendable` `enum` with three cases rather than a bare string union. The two percentage calculations become free functions returning `Double?` for the null-when-no-data case; rounding to two decimal places uses `(value * 100).rounded() / 100`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the check tally as a `data class` with `Int` fields, health status as a `sealed class` or `enum class`, and the two percentage calculations as top-level `fun`s returning `Double?`; `kotlin.math.round` matches round-half-up behavior closely enough for this domain, since every ratio here is non-negative.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/uptime.ts` as three synchronous, side-effect-free exported functions plus the `Counts` interface, consumed server-side by `buildUptime` in `../routes/reads.ts`. The source's own header comment notes it was originally ported from the standalone status site (`websites/main/status/src/lib/uptime.ts`) specifically so its numbers would match that site's old route exactly, and that it performs "No DB/IO." A byte-for-byte-identical `Counts`/`uptimePercent`/`dayStatus`/`overallUptimePercent` quartet is maintained independently in the browser bundle at `packages/web/packages/status-web/src/lib/uptime.ts` (consumed by `OverviewTab.tsx`), because that package cannot import the Node-only server package — the two copies are not linked at build time.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no `NSViewController`/`UIViewController` concept applies. A macOS/iOS agent embedding this arithmetic has no per-thread module-duplication concern to solve, unlike some sibling monitor modules — these functions hold no module-scope state at all, so a single shared implementation is trivially safe to call from any GCD queue or Swift `Task`.
- **WinUI 3**: a .NET port models the check tally as a `record struct Counts(int Total, int Healthy, int Degraded, int Down)`, health status as a C# `enum HealthStatus { Healthy, Degraded, Down }`, and the three calculations as `static` methods on a plain helper class returning `double?` for the no-data cases. `Math.Round(value, 2, MidpointRounding.AwayFromZero)` reproduces the round-half-away-from-zero behavior for the non-negative percentages this domain always produces. No `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or `INotifyPropertyChanged` is needed anywhere in this port; unlike the networked monitor siblings, this module has no I/O and no async boundary — it is three pure, synchronous static methods a WinUI view-model calls directly and assigns straight into whatever bound property already exists.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/uptime.ts` |

## Design Decisions

- **Decision**: count a `degraded` check together with a `healthy` check as up-time in the uptime-percentage calculation, so only a `down` check reduces the returned percentage.
  **Rationale**: not explained beyond the file's own framing as ported arithmetic kept deliberately identical to "the old route"; recorded here as a fact of the ported formula — a slow-but-responding endpoint still counts as available time, and only a definite outage removes uptime credit.
  **Approved**: pending
- **Decision**: leave a zero-total day falling through the day-status classification's default branch to `"healthy"`, rather than adding an early return for a total of zero or less the way the uptime-percentage calculation has.
  **Rationale**: not stated inline; recorded here as a fact of the code's structure — the day-status classification has no zero-total guard, so a day with no checks at all reports the same `"healthy"` value as a day that was checked and found fully healthy. A consumer must read that same day's uptime percentage (`null`) to learn "no data," not the day-status classification.
  **Approved**: pending
- **Decision**: compute portfolio-wide uptime in the overall-uptime mean as the simple, unweighted mean of each service's OWN uptime percentage, rather than summing raw check counts across every service first.
  **Rationale**: stated directly in the source's own doc comment — "so every service counts equally" — a service checked far more often than another, or monitored for longer, must not dominate the headline number. The `status-web` duplicate's own comment on this same formula adds: "Volume-weighting was misleading: a service checked more often, or simply monitored for longer, would dominate the number even though it's just one of the things we watch."
  **Approved**: pending
- **Decision**: maintain an independent, byte-for-byte-identical copy of `Counts`, `uptimePercent`, `dayStatus`, and `overallUptimePercent` in the browser-bundled `status-web` package instead of importing this server-side file directly.
  **Rationale**: not stated inline in either file; recorded here as a fact of the repo's structure — `status-web` runs in the browser and cannot import a Node-only server package, so the same arithmetic contract is maintained as two separately authored and separately tested source files. Nothing in either file enforces that a future change to the rounding or threshold logic is mirrored in the other.
  **Approved**: pending
- **Decision**: export `overallUptimePercent` from this server-side module even though no route or caller inside `status-server` itself currently invokes it (`uptimePercent` and `dayStatus` are the two consumed by `buildUptime` in `../routes/reads.ts`).
  **Rationale**: not stated inline; recorded here as a fact — the function's only live caller is the separate `status-web` package's own copy of this file, consumed by `OverviewTab.tsx`. Within `status-server` itself, `overallUptimePercent` is currently unused.
  **Approved**: pending
- **Decision**: keep this recipe's Behavioral Requirements list much shorter than sibling monitor recipes such as Status Server Monitor Fetch Vercel Projects.
  **Rationale**: warranted by a genuine complexity difference, not under-authoring — `uptime.ts` is three pure, synchronous, side-effect-free functions with no I/O, network calls, retries, caching, or concurrency-sensitive shared state, against a paginating network fetcher with budgets, retries, and multiple TTL caches. Per the cross-recipe-consistency guideline, comparable depth applies to comparable complexity, and this component's complexity is genuinely smaller.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`unit-test-coverage` is marked partial: `uptime.ts` has no dedicated `*.test.ts` file of its own inside `status-server` — its only coverage in this package is the indirect assertion in `test/reads.int.test.ts` ("/uptime aggregates daily counts for the configured endpoint," asserting `body.services[0].uptimePercent === 50` through the caller `buildUptime`). The identical formula IS directly and thoroughly unit-tested, but only in the separate `status-web` package's byte-for-byte duplicate (`src/lib/uptime.test.ts`), which this file neither imports nor shares; `dayStatus`'s zero-total fallthrough and `overallUptimePercent`'s null-filtering behavior have no test coverage of any kind written against THIS file. `separation-of-concerns` passes: this file does exactly one thing — turn already-aggregated check counts into a percentage and a verdict, and average per-service percentages into one number — delegating nothing to, and duplicating nothing from, its sibling `health.ts` beyond importing the `HealthStatus` type it returns. `explicit-error-handling` passes: the one arithmetic hazard the module could hit, dividing by a zero or negative `total`, is explicitly guarded by the `c.total <= 0` check in `uptimePercent` before any division runs; no other branch in the file can divide, throw, or reject. `data-integrity` passes: every returned percentage is deterministically derived from its input with no mutation of the caller's `Counts` or `services` objects, and the same input always produces the same rounded output.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
