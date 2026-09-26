---
id: 88dabdf6-14a3-44eb-ab0d-ae18007c683e
title: Status Server Monitor Uptime
domain: agentictoolkit://cookbook/status-server/monitor/uptime
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/status-server/monitor/health
- agentictoolkit://cookbook/status-server/monitor/overall
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

# Status Server Monitor Uptime

## Overview

`uptime.ts` (`packages/web/packages/status-server/src/monitor/uptime.ts`) is the status backend's pure uptime-arithmetic step: it turns a day's (or a totals accumulation's) `Counts` — `total`, `healthy`, `degraded`, `down` check tallies for one endpoint — into a rounded uptime percentage and a `HealthStatus` verdict, and separately turns a list of per-service uptime percentages into one unweighted portfolio-wide percentage. Its own header comment states it is "ported from the standalone status site (`websites/main/status/src/lib/uptime.ts`)" specifically "so its numbers match the old route exactly," and that it performs "No DB/IO." It exports the `Counts` interface and three functions: `uptimePercent`, `dayStatus`, and `overallUptimePercent`. Inside `status-server`, `uptimePercent` and `dayStatus` are consumed by `buildUptime` (`../routes/reads.ts`, external), which builds the `GET /uptime` and equivalent MCP-tool response from `storage.history.dailyCounts`; `overallUptimePercent` has no caller inside `status-server` itself. A byte-for-byte-identical copy of this file's `Counts`, `uptimePercent`, `dayStatus`, and `overallUptimePercent` is maintained independently in the browser bundle `packages/web/packages/status-web/src/lib/uptime.ts`, where `overallUptimePercent` IS consumed, by `OverviewTab.tsx`'s portfolio headline — that duplicate carries this recipe's only direct unit-test coverage of the shared formula (`uptime.test.ts`).

## Behavioral Requirements

### Data Shape

- **counts-shape**: `Counts` MUST carry exactly four numeric fields — `total`, `healthy`, `degraded`, and `down` — each an aggregated count of checks for one endpoint over one accounting period (one day, or a summed range of days).
- **health-status-return**: `dayStatus` MUST return one of exactly the three `HealthStatus` string literals defined by `./health` — `"healthy"`, `"degraded"`, or `"down"` — and no other value.

### uptimePercent

- **uptime-percent-formula**: When `c.total > 0`, `uptimePercent(c)` MUST return `Math.round(((c.healthy + c.degraded) / c.total) * 10000) / 100` — the healthy-plus-degraded share of total checks, expressed as a percentage rounded to two decimal places.
- **uptime-percent-degraded-counts-as-up**: `uptimePercent` MUST count a `degraded` check together with a `healthy` check as up-time; only a `down` check reduces the returned percentage.
- **uptime-percent-no-data**: `uptimePercent(c)` MUST return `null`, without evaluating any ratio, whenever `c.total` is less than or equal to `0`.

### dayStatus

- **day-status-down-majority**: `dayStatus(c)` MUST return `"down"` when `c.down > 0` and `c.down / c.total` is strictly greater than `0.5`.
- **day-status-down-minority**: `dayStatus(c)` MUST return `"degraded"` when `c.down > 0` and `c.down / c.total` is `0.5` or less.
- **day-status-degraded-only**: `dayStatus(c)` MUST return `"degraded"` when `c.down` is `0` and `c.degraded` is greater than `0`.
- **day-status-healthy-default**: `dayStatus(c)` MUST return `"healthy"` when both `c.down` and `c.degraded` are `0`, regardless of the value of `c.total` or `c.healthy`.
- **day-status-no-zero-total-guard**: `dayStatus` MUST NOT special-case `c.total <= 0` the way `uptimePercent` does; a day with zero checks of every kind MUST fall through to the same `"healthy"` result as a day that was actually checked and found fully healthy.

### overallUptimePercent

- **overall-uptime-mean**: `overallUptimePercent(services)` MUST return the arithmetic mean, rounded via `Math.round(mean * 100) / 100`, of the `uptimePercent` field across every entry of `services` whose `uptimePercent` is not `null`.
- **overall-uptime-excludes-null**: `overallUptimePercent` MUST exclude any entry whose `uptimePercent` field is `null` from both the sum and the divisor used to compute the mean; a service with no data MUST NOT be treated as a `0` and MUST NOT change the count of averaged entries.
- **overall-uptime-no-data**: `overallUptimePercent` MUST return `null` when `services` is empty, or when every entry's `uptimePercent` is `null`.
- **overall-uptime-order-independent**: `overallUptimePercent`'s result MUST be independent of the order of the `services` array, since it computes an unweighted arithmetic mean over the entries that qualify.

### Purity and Concurrency

- **pure-computation**: `uptimePercent`, `dayStatus`, and `overallUptimePercent` MUST perform no I/O and MUST mutate no argument, computing their return value solely from the arguments passed on that call, per the source's own header comment "No DB/IO."
- **concurrency-safety**: Because none of the three functions read or write any module-scope or shared state, they MUST be safely callable concurrently, in any order, from multiple callers (for example the same `status-server` process handling several HTTP requests at once) without one call's result depending on another's.

## Appearance

Not applicable — this is a pure uptime and status arithmetic module, not a visual component.

## States

Not applicable — this is a pure uptime and status arithmetic module, not a visual component; its runtime behavior (the total-is-zero branch in `uptimePercent`, the down/degraded/healthy branches in `dayStatus`, and the null-filtering branch in `overallUptimePercent`) is captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a pure uptime and status arithmetic module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-uptime-001 | uptime-percent-formula, uptime-percent-degraded-counts-as-up | `uptimePercent({ total: 100, healthy: 90, degraded: 5, down: 5 })` | Returns `95` — `status-web/src/lib/uptime.test.ts` › "counts healthy+degraded as up" (evidence source for the byte-identical formula, per Design Decisions) |
| status-server-monitor-uptime-002 | uptime-percent-no-data | `uptimePercent({ total: 0, healthy: 0, degraded: 0, down: 0 })` | Returns `null` — same test file › "null when no checks" |
| status-server-monitor-uptime-003 | uptime-percent-formula | `uptimePercent({ total: 3, healthy: 1, degraded: 1, down: 1 })` | Returns `66.67` — traced directly to `Math.round(((2/3) * 10000)) / 100` in the source (2 of 3 checks up, rounded to two decimal places) |
| status-server-monitor-uptime-004 | day-status-down-majority | `dayStatus({ total: 10, healthy: 2, degraded: 0, down: 8 })` | Returns `"down"` (`8/10 = 0.8`, greater than `0.5`) — `status-web/src/lib/uptime.test.ts` › "day status: >50% down is down" |
| status-server-monitor-uptime-005 | day-status-down-minority | `dayStatus({ total: 10, healthy: 7, degraded: 0, down: 3 })` | Returns `"degraded"` (`3/10 = 0.3`, not greater than `0.5`) — same test file › "day status: some down <=50% is degraded" |
| status-server-monitor-uptime-006 | day-status-degraded-only | `dayStatus({ total: 10, healthy: 8, degraded: 2, down: 0 })` | Returns `"degraded"` — same test file › "day status: degraded only is degraded" |
| status-server-monitor-uptime-007 | day-status-healthy-default | `dayStatus({ total: 10, healthy: 10, degraded: 0, down: 0 })` | Returns `"healthy"` — same test file › "day status: all healthy is healthy" |
| status-server-monitor-uptime-008 | day-status-no-zero-total-guard | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 0 })` | Returns `"healthy"` — traced directly to the source's fallthrough (`c.down > 0` is false, `c.degraded > 0` is false, default `"healthy"`); contrast with vector 002, the identical input returning `null` from `uptimePercent` |
| status-server-monitor-uptime-009 | overall-uptime-mean | `overallUptimePercent([{ uptimePercent: 100 }, { uptimePercent: 90 }])` | Returns `95` — `status-web/src/lib/uptime.test.ts` › "is the simple mean of each service's uptime (every service counts equally)" |
| status-server-monitor-uptime-010 | overall-uptime-excludes-null | `overallUptimePercent([{ uptimePercent: 99 }, { uptimePercent: null }, { uptimePercent: 95 }])` | Returns `97` (mean of `99` and `95` only; the divisor is `2`, not `3`) — same test file › "ignores services with null uptime (no data), averaging the rest equally" |
| status-server-monitor-uptime-011 | overall-uptime-no-data | `overallUptimePercent([])` | Returns `null` — same test file › "is null when there's no data" |
| status-server-monitor-uptime-012 | overall-uptime-no-data | `overallUptimePercent([{ uptimePercent: null }])` | Returns `null` — same test file |
| status-server-monitor-uptime-013 | uptime-percent-formula (caller integration) | `GET /uptime?days=90` against seeded per-day check rows for one configured endpoint | `body.services[0].uptimePercent === 50` — `test/reads.int.test.ts` › "/uptime aggregates daily counts for the configured endpoint" (integration evidence for the same formula reached through the caller `buildUptime`) |
| status-server-monitor-uptime-014 | pure-computation, concurrency-safety | `uptimePercent(c)` and `dayStatus(c)` both called on the same `Counts` object `c = { total: 10, healthy: 10, degraded: 0, down: 0 }`, repeated and interleaved with calls using other `Counts` values | Every call returns the same value for the same input every time (`100` and `"healthy"` for `c`), and `c`'s own fields are unchanged after any call — traced to the source's complete absence of module-scope variables or mutation of the `c` parameter |
| status-server-monitor-uptime-015 | counts-shape, health-status-return | `dayStatus`'s return value inspected across vectors 004–008 | Every returned value is one of exactly `"healthy"`, `"degraded"`, or `"down"` (`HealthStatus`, `./health`); the function's TypeScript return type makes any other string a compile error at the call site — traced to the `import type { HealthStatus } from "./health"` and the function's `: HealthStatus` return annotation |

## Edge Cases

- **Null and empty input**: `overallUptimePercent([])` MUST return `null` (overall-uptime-no-data). A `Counts` object with every field `0` MUST return `null` from `uptimePercent` (uptime-percent-no-data) and `"healthy"` from `dayStatus` (day-status-no-zero-total-guard) — the SAME input yields two different-looking answers depending on which function is called — MUST.
- **Boundary values**: the `> 0.5` comparison in `dayStatus` is strict, so a down-ratio of EXACTLY `0.5` (for example `{ total: 10, healthy: 0, degraded: 5, down: 5 }`) MUST return `"degraded"`, not `"down"` — MUST. `uptimePercent`'s rounding can land on a repeating fraction (vector 003, `2/3`); the source's `Math.round(x * 10000) / 100` always resolves such a value to a definite two-decimal-place number rather than leaving extra precision — MUST.
- **Concurrent access**: none of the three functions read or write module-scope state, so concurrent or repeated calls — from multiple requests handled by the same `status-server` process, or from the separate `status-web` copy running in a different browser tab entirely — can never interleave in a way that corrupts a result; each call is isolated to its own arguments (pure-computation, concurrency-safety) — MUST.
- **Error states**: none of the three functions can throw, reject, or return an error value for any input conforming to their declared TypeScript signatures — there is no `throw`, `try`/`catch`, or rejected `Promise` anywhere in the source. A runtime caller that passes a `Counts` or `services` argument NOT conforming to the declared type (for example a missing field evaluating to `undefined`) is not guarded against at runtime; ordinary arithmetic on `undefined` produces `NaN`, which propagates through `Math.round`/`Number` operations rather than throwing — this is a SHOULD-level caller precondition enforced only by TypeScript's compile-time type signature (`total: number; healthy: number; degraded: number; down: number`), not a runtime validation this file performs; the only in-repo caller (`buildUptime` in `../routes/reads.ts`) always builds `Counts` from a `reduce` over already-numeric database rows, so the malformed-shape case does not occur in the traced call path.
- **Offline / disconnected state**: not applicable — this module makes no network call and no database call of any kind, per its own header comment "No DB/IO"; nothing in it can be affected by a lost connection.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `c` (parameter of `uptimePercent`, `dayStatus`) | `Counts` (`{ total: number; healthy: number; degraded: number; down: number }`) | none — required on every call | The per-endpoint check tallies to score. Supplied fresh by the caller on each call (`buildUptime` in `../routes/reads.ts`, external); never defaulted, cached, or read from configuration by this file. |
| `services` (parameter of `overallUptimePercent`) | `{ uptimePercent: number \| null }[]` | none — required on every call | The list of already-computed per-service uptime percentages to average. Supplied fresh by the caller on each call (`OverviewTab.tsx` in the `status-web` duplicate, external); never defaulted, cached, or read from configuration by this file. |

This module reads no environment variable, consults no settings or feature-flag store, and receives no injected dependency of any kind — every value it needs arrives as a plain function argument on that call.

## Deep Linking

Not applicable: this file defines no route and no URL scheme of its own — it exports three pure functions and one type, consumed in-process by `buildUptime` (`../routes/reads.ts`) and by the `status-web` duplicate's `OverviewTab.tsx`.

## Localization

Not applicable: the source returns only numbers (`number | null`) and one of three fixed `HealthStatus` string literals (`"healthy"`, `"degraded"`, `"down"`) — internal status codes, not natural-language, end-user-facing text; it defines no localizable string of its own. Any user-facing label derived from these values is the caller's responsibility, outside this file.

## Accessibility Options

Not applicable: this is a pure arithmetic module with no UI; it responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: the source consults no feature-flag system; its only conditional gating — the `c.total <= 0` check in `uptimePercent` — is plain data-driven arithmetic, not a flag lookup.

## Analytics

Not applicable: the source emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this module collects, stores, transmits, and retains nothing on its own — it computes derived numbers from caller-supplied, already-aggregated integer check counts and percentages; none of `Counts`' fields or the computed percentages carry personal or sensitive data.

## Logging

Not applicable: the source contains no `console.*` call or other logging statement of any kind — traced to the complete absence of any log line in `uptime.ts`.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `Counts` as a `Sendable` `struct` with four `Int` fields (`total`, `healthy`, `degraded`, `down` — the source's untyped `number` fields hold whole check counts), and `HealthStatus` as a `Sendable` `enum` with three cases rather than a bare string union. The two percentage functions become free functions returning `Double?` for the null-when-no-data case; rounding to two decimal places uses `(value * 100).rounded() / 100`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `Counts` as a `data class` with `Int` fields, `HealthStatus` as a `sealed class` or `enum class`, and the two percentage functions as top-level `fun`s returning `Double?`; `kotlin.math.round` matches `Math.round`'s round-half-up behavior closely enough for this domain, since every ratio here is non-negative.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/uptime.ts` as three synchronous, side-effect-free exported functions plus the `Counts` interface, consumed server-side by `buildUptime` in `../routes/reads.ts`. A byte-for-byte-identical `Counts`/`uptimePercent`/`dayStatus`/`overallUptimePercent` quartet is maintained independently in the browser bundle at `packages/web/packages/status-web/src/lib/uptime.ts` (consumed by `OverviewTab.tsx`), because that package cannot import the Node-only server package — the two copies are not linked at build time.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no `NSViewController`/`UIViewController` concept applies. A macOS/iOS agent embedding this arithmetic has no per-thread module-duplication concern to solve, unlike some sibling monitor modules — these functions hold no module-scope state at all, so a single shared implementation is trivially safe to call from any GCD queue or Swift `Task`.
- **WinUI 3**: a .NET port models `Counts` as a `record struct Counts(int Total, int Healthy, int Degraded, int Down)`, `HealthStatus` as a C# `enum HealthStatus { Healthy, Degraded, Down }`, and the three functions as `static` methods on a plain helper class returning `double?` for the no-data cases. `Math.Round(value, 2, MidpointRounding.AwayFromZero)` reproduces `Math.round(x * 100) / 100`'s round-half-away-from-zero behavior for the non-negative percentages this domain always produces — JavaScript's `Math.round` rounds a positive `.5` up, matching `AwayFromZero` rather than .NET's default `ToEven`. No `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or `INotifyPropertyChanged` is needed anywhere in this port; unlike the networked monitor siblings, this module has no I/O and no async boundary — it is three pure, synchronous static methods a WinUI view-model calls directly and assigns straight into whatever bound property already exists.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/uptime.ts` |

## Design Decisions

- **Decision**: count a `degraded` check together with a `healthy` check as up-time in `uptimePercent`, so only a `down` check reduces the returned percentage.
  **Rationale**: not explained beyond the file's own framing as ported arithmetic kept deliberately identical to "the old route"; recorded here as a fact of the ported formula — a slow-but-responding endpoint still counts as available time, and only a definite outage removes uptime credit.
  **Approved**: pending
- **Decision**: leave a zero-total day falling through `dayStatus`'s default branch to `"healthy"`, rather than adding an early return for `c.total <= 0` the way `uptimePercent` has.
  **Rationale**: not stated inline; recorded here as a fact of the code's structure — `dayStatus` has no zero-total guard, so a day with no checks at all reports the same `"healthy"` value as a day that was checked and found fully healthy. A consumer must read that same day's `uptimePercent` (`null`) to learn "no data," not `dayStatus`.
  **Approved**: pending
- **Decision**: compute portfolio-wide uptime in `overallUptimePercent` as the simple, unweighted mean of each service's OWN uptime percentage, rather than summing raw check counts across every service first.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
