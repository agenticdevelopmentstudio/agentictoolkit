---
id: aa2f3a92-8bac-4a0f-8e61-382958ab53ef
title: Uptime Math
domain: agentictoolkit://recipes/status-web-src-lib-uptime
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure uptime arithmetic: per-day uptime percent, per-day HealthStatus from
  check counts, and the portfolio-wide mean uptime percent'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-src-lib-health
related:
- agentictoolkit://recipes/status-server-monitor-uptime
- agentictoolkit://recipes/status-web-hooks-use-uptime
references: []
approved-by: ''
approved-date: ''
---

# Uptime Math

## Overview

`uptime.ts` (`packages/web/packages/status-web/src/lib/uptime.ts`) is the status-web client's copy of the uptime arithmetic. It has no I/O, no state and no dependencies beyond the `HealthStatus` type from the sibling `health.ts` (see [Health Classification](agentictoolkit://recipes/status-web-src-lib-health)). It exports:

- `Counts` — an interface of four numbers: `total`, `healthy`, `degraded`, `down`.
- `uptimePercent(c: Counts): number | null` — the share of checks that were up (healthy or degraded), as a percentage rounded to two decimals, or `null` when there were no checks.
- `dayStatus(c: Counts): HealthStatus` — collapses a day's counts to one `"healthy"`, `"degraded"` or `"down"` verdict.
- `overallUptimePercent(services): number | null` — the portfolio-wide uptime, the simple unweighted mean of each service's own `uptimePercent`, rounded to two decimals, or `null` when no service has data.

Within status-web only `overallUptimePercent` is called at runtime: `OverviewTab.tsx` passes it `uptimeQuery.data?.services ?? []` (the `UptimeService[]` from [useUptime](agentictoolkit://recipes/status-web-hooks-use-uptime)) and renders the result in `OverviewStats`. The per-day `uptimePercent` and `status` values arrive already computed from the status server, whose `monitor/uptime.ts` (see [Status Server Monitor Uptime](agentictoolkit://recipes/status-server-monitor-uptime)) carries the same three functions and backs the `/uptime` read route. The two files differ only in comments and line wrapping.

Use this component whenever a port must reproduce the status page's uptime numbers exactly: the rounding and the "degraded counts as up" rule are what make the numbers match.

## Behavioral Requirements

### Data shapes

- **counts-shape**: `Counts` MUST carry exactly four numeric fields named `total`, `healthy`, `degraded` and `down`.
- **counts-not-validated**: The module MUST NOT reject or correct a `Counts` whose `healthy + degraded + down` differs from `total`, or whose fields are negative, fractional or `NaN`; each function MUST compute directly on the values given.
- **service-input-shape**: `overallUptimePercent` MUST accept any array of objects that carry an `uptimePercent` field of type `number | null`; other fields on the objects MUST be ignored.

### uptimePercent

- **uptime-null-when-no-checks**: `uptimePercent` MUST return `null` when `total` is less than or equal to 0.
- **uptime-degraded-counts-as-up**: `uptimePercent` MUST count both `healthy` and `degraded` checks as up; `down` MUST NOT enter the numerator.
- **uptime-denominator-total**: `uptimePercent` MUST divide by `total`, not by the sum of the three bucket counts.
- **uptime-two-decimal-rounding**: `uptimePercent` MUST return `(healthy + degraded) / total × 100` rounded to two decimal places by multiplying the ratio by 10000, rounding to the nearest integer with halves rounding toward positive infinity, then dividing by 100.
- **uptime-no-clamp**: `uptimePercent` MUST NOT clamp its result to the range 0–100; inconsistent counts (for example `healthy` greater than `total`) produce a value above 100.

### dayStatus

- **day-down-majority**: `dayStatus` MUST return `"down"` when `down` is greater than 0 and `down / total` is strictly greater than 0.5.
- **day-down-minority**: `dayStatus` MUST return `"degraded"` when `down` is greater than 0 and `down / total` is less than or equal to 0.5.
- **day-degraded**: `dayStatus` MUST return `"degraded"` when `down` is 0 or less and `degraded` is greater than 0.
- **day-healthy**: `dayStatus` MUST return `"healthy"` when neither `down` nor `degraded` is greater than 0, regardless of `total` and `healthy`.
- **day-down-checked-first**: `dayStatus` MUST evaluate the `down` count before the `degraded` count, so any day with a down check is never reported `"healthy"`.
- **day-zero-total-with-down**: `dayStatus` MUST return `"down"` when `total` is 0 and `down` is greater than 0, because the ratio evaluates to positive infinity; it performs no zero-total guard.

### overallUptimePercent

- **overall-ignores-null**: `overallUptimePercent` MUST drop every entry whose `uptimePercent` is `null` or `undefined` before averaging.
- **overall-null-when-no-data**: `overallUptimePercent` MUST return `null` when the input array is empty or every entry's `uptimePercent` is `null`.
- **overall-unweighted-mean**: `overallUptimePercent` MUST return the arithmetic mean of the remaining values, each service weighted equally regardless of its check count or monitoring span.
- **overall-two-decimal-rounding**: `overallUptimePercent` MUST round the mean to two decimal places by multiplying by 100, rounding to the nearest integer with halves rounding toward positive infinity, then dividing by 100.
- **overall-nan-propagates**: `overallUptimePercent` MUST return `NaN` when any retained entry's `uptimePercent` is `NaN`, because `NaN` is a number and passes the null filter.

### Purity, ordering and side effects

- **pure-functions**: Every exported function MUST be pure: it MUST NOT mutate its argument, read or write any storage, perform network or file I/O, log, or depend on the clock.
- **synchronous**: Every exported function MUST return synchronously; the module holds no state, so concurrent calls on single-threaded JavaScript cannot interleave or affect each other.
- **no-errors-raised**: Every exported function MUST NOT throw for any input matching its type signature; "no data" is signalled by a `null` return, not an error.

## Appearance

Not applicable — this is a pure arithmetic module, not a visual component.

## States

Not applicable — this is a pure arithmetic module, not a visual component.

## Accessibility

Not applicable — this is a pure arithmetic module, not a visual component.

## Conformance Test Vectors

Vectors 001–009 are the assertions in `uptime.test.ts`; the rest are derived from the source arithmetic.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| uptime-001 | uptime-degraded-counts-as-up, uptime-two-decimal-rounding | `uptimePercent({ total: 100, healthy: 90, degraded: 5, down: 5 })` | `95` |
| uptime-002 | uptime-null-when-no-checks | `uptimePercent({ total: 0, healthy: 0, degraded: 0, down: 0 })` | `null` |
| uptime-003 | day-down-majority | `dayStatus({ total: 10, healthy: 2, degraded: 0, down: 8 })` | `"down"` |
| uptime-004 | day-down-minority | `dayStatus({ total: 10, healthy: 7, degraded: 0, down: 3 })` | `"degraded"` |
| uptime-005 | day-degraded | `dayStatus({ total: 10, healthy: 8, degraded: 2, down: 0 })` | `"degraded"` |
| uptime-006 | day-healthy | `dayStatus({ total: 10, healthy: 10, degraded: 0, down: 0 })` | `"healthy"` |
| uptime-007 | overall-unweighted-mean | `overallUptimePercent([{ uptimePercent: 100 }, { uptimePercent: 90 }])` | `95` |
| uptime-008 | overall-ignores-null | `overallUptimePercent([{ uptimePercent: 99 }, { uptimePercent: null }, { uptimePercent: 95 }])` | `97` |
| uptime-009 | overall-null-when-no-data | `overallUptimePercent([])` and `overallUptimePercent([{ uptimePercent: null }])` | `null` for both |
| uptime-010 | uptime-two-decimal-rounding | `uptimePercent({ total: 3, healthy: 2, degraded: 0, down: 1 })` | `66.67` |
| uptime-011 | uptime-null-when-no-checks | `uptimePercent({ total: -1, healthy: 0, degraded: 0, down: 0 })` | `null` |
| uptime-012 | uptime-denominator-total, uptime-no-clamp | `uptimePercent({ total: 4, healthy: 5, degraded: 0, down: 0 })` | `125` |
| uptime-013 | day-down-minority | `dayStatus({ total: 10, healthy: 5, degraded: 0, down: 5 })` (exactly half down) | `"degraded"` |
| uptime-014 | day-down-checked-first | `dayStatus({ total: 10, healthy: 0, degraded: 9, down: 1 })` | `"degraded"` |
| uptime-015 | day-zero-total-with-down | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 1 })` | `"down"` |
| uptime-016 | day-healthy | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 0 })` | `"healthy"` |
| uptime-017 | overall-two-decimal-rounding | `overallUptimePercent([{ uptimePercent: 33.33 }, { uptimePercent: 33.33 }, { uptimePercent: 33.34 }])` | `33.33` |
| uptime-018 | overall-nan-propagates | `overallUptimePercent([{ uptimePercent: NaN }, { uptimePercent: 90 }])` | `NaN` |
| uptime-019 | service-input-shape, overall-unweighted-mean | `overallUptimePercent([{ uptimePercent: 100, totalChecks: 1000 }, { uptimePercent: 50, totalChecks: 2 }])` | `75` (check volume has no effect) |
| uptime-020 | pure-functions | Call `uptimePercent`, `dayStatus` and `overallUptimePercent` on frozen input objects and arrays | No exception; inputs unchanged |

## Edge Cases

- **Empty input — no checks**: `uptimePercent` with `total` 0 MUST return `null`; `dayStatus` with all counts 0 MUST return `"healthy"`. The two functions therefore disagree on a no-data day: one says "no data", the other says "healthy". Callers that need a "no data" day state MUST check `total` themselves.
- **Empty input — no services**: `overallUptimePercent([])` MUST return `null`, as MUST an array whose every entry is `null`.
- **Missing field**: an entry whose `uptimePercent` is `undefined` (outside the type, but possible from untyped JSON) MUST be dropped like `null`, because the filter uses loose `!= null`.
- **Boundary — exactly half down**: `down / total` equal to 0.5 MUST yield `"degraded"`, not `"down"`; the comparison is strictly greater than.
- **Boundary — negative total**: `uptimePercent` MUST return `null` for any `total` below 0.
- **Boundary — zero total with down checks**: `dayStatus` MUST return `"down"`, because a positive number divided by 0 is positive infinity.
- **Malformed input — inconsistent counts**: when the bucket counts do not sum to `total`, `uptimePercent` MUST still divide by `total` and MAY return values above 100 or below 0; no validation or clamping occurs (see counts-not-validated). The counts are produced by the status server, which owns their consistency.
- **Malformed input — NaN**: a `NaN` count makes `uptimePercent` return `NaN` (unless `total` itself is `NaN`, which fails the `total <= 0` test and also yields `NaN`); a `NaN` `uptimePercent` in the service list makes `overallUptimePercent` return `NaN`.
- **Floating-point rounding**: rounding goes through binary floating point, so a value whose exact decimal half lies just below the representable boundary MAY round down; ports MUST use IEEE 754 double arithmetic and the same multiply-round-divide sequence to match the reference output digit for digit.
- **Concurrent access**: not applicable — the functions are pure and hold no state, so any number of calls may run in any order with identical results.
- **Error states and offline**: not applicable — the module performs no I/O and has no dependency that can fail or disconnect.
- **Cancellation and timeouts**: not applicable — every call completes synchronously in constant time for `uptimePercent` and `dayStatus`, and linear time in the array length for `overallUptimePercent`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `c` (argument to `uptimePercent`, `dayStatus`) | `Counts` | none — required | The day's check counts: `total`, `healthy`, `degraded`, `down`. |
| `services` (argument to `overallUptimePercent`) | `{ uptimePercent: number \| null }[]` | none — required | One entry per service; in status-web the `UptimeService[]` from the `/uptime` response, or `[]` while loading. |
| Down-majority threshold | constant | `0.5` | Hardcoded in `dayStatus`; strictly greater than this share of down checks makes the day `"down"`. Not configurable. |
| Rounding precision | constant | 2 decimal places | Hardcoded in both percent functions. Not configurable. |

The module reads no environment variables, settings keys or injected dependencies.

## Deep Linking

Not applicable: `uptime.ts` exports only arithmetic functions and registers no route or URL.

## Localization

Not applicable: the module returns numbers, `null` and the `HealthStatus` literal strings `"healthy"`, `"degraded"` and `"down"`, which are machine identifiers rather than user-facing text; formatting the percentage for display happens in `OverviewStats`.

## Accessibility Options

Not applicable: the module has no visual output and responds to no display setting.

## Feature Flags

Not applicable: no function in `uptime.ts` reads a flag or branches on configuration.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only aggregate check counts and percentages, stores nothing and transmits nothing.

## Logging

Not applicable: no function in `uptime.ts` logs.

## Platform Notes

- **SwiftUI**: Port as free functions or static members of a `Sendable` value-type namespace (`enum UptimeMath`), with `struct Counts: Sendable, Equatable` of `Int` fields and a `HealthStatus` `String`-backed enum. Return `Double?` for the percentages. Reproduce the rounding as `(ratio * 10000).rounded(.toNearestOrAwayFromZero) / 100`; for non-negative values this matches JavaScript `Math.round` (halves up). With `Int` counts, compute the `dayStatus` ratio in `Double` so a zero-total day with down checks yields positive infinity (and `"down"`) as in the source, instead of trapping on integer division by zero. The status-server copy in `monitor/uptime.ts` is the same contract.
- **Compose**: Kotlin top-level functions in an `object UptimeMath`, `data class Counts(val total: Int, val healthy: Int, val degraded: Int, val down: Int)`, and `enum class HealthStatus`. Use `Double` division; avoid `kotlin.math.round`, which rounds halves to even, and use `roundToLong()` (halves toward positive infinity) to match JavaScript `Math.round`. `filterNotNull().average()` gives the unweighted mean; return `null` when the filtered list is empty rather than `average()`'s `NaN`.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/uptime.ts` holds the functions; `uptime.test.ts` beside it is the Vitest suite; `OverviewTab.tsx` is the only runtime caller (of `overallUptimePercent`). `packages/web/packages/status-server/src/monitor/uptime.ts` is the server twin that computes the per-day values the client receives. Specific to TypeScript: the `filter((p): p is number => p != null)` type guard also drops `undefined`, and `Math.round` rounds halves toward positive infinity.
- **AppKit / UIKit**: Same Swift port as SwiftUI — the module is UI-free; share it from a framework target so both app flavors and any server-side Swift use one implementation. Format the returned `Double` for display with `NumberFormatter` or `FormatStyle` in the view layer, not in this module.
- **WinUI 3**: Port to a C# `static class UptimeMath` in a .NET class library with `public readonly record struct Counts(int Total, int Healthy, int Degraded, int Down)` and `public enum HealthStatus { Healthy, Degraded, Down }`; return `double?`. Match JavaScript rounding with `Math.Round(ratio * 10000, MidpointRounding.AwayFromZero) / 100` — the default `Math.Round` uses banker's rounding (`MidpointRounding.ToEven`) and would diverge on halves. Cast to `double` before dividing (`(double)c.Down / c.Total`) so integer division does not truncate, and so a zero total yields `double.PositiveInfinity` rather than a `DivideByZeroException`. `services.Select(s => s.UptimePercent).Where(p => p.HasValue).Select(p => p!.Value)` then `Average()` gives the mean; check `Any()` first because `Average()` on an empty sequence throws. When the input is deserialized with `System.Text.Json` from the `/uptime` response, map `uptimePercent` to `double?`. Nothing here needs `Task`/`async`, `ObservableCollection` or `INotifyPropertyChanged`: call the functions from the view model that owns the uptime data and expose the result as a bound property there.

## Design Decisions

**Decision**: Portfolio-wide uptime is the unweighted mean of each service's own uptime percent.
**Rationale**: The source's doc comment on `overallUptimePercent` states that volume-weighting "was misleading: a service checked more often, or simply monitored for longer, would dominate the number even though it's just one of the things we watch." Each service counts equally.
**Approved**: pending

**Decision**: Degraded checks count as up in `uptimePercent`.
**Rationale**: A degraded check answered successfully but slowly (see the `DEGRADED_THRESHOLD_MS` rule in `health.ts`); the service was reachable, so the numerator is `healthy + degraded`.
**Approved**: pending

**Decision**: A day is `"down"` only when more than half its checks were down; any down check below that makes it `"degraded"`.
**Rationale**: `dayStatus` checks `down > 0` first and then compares `down / total > 0.5`, so a single failed check cannot mark a whole day as an outage, yet any failure still keeps the day from showing `"healthy"`.
**Approved**: pending

**Decision**: Percentages are rounded to two decimals inside the module, not at display time.
**Rationale**: Both functions apply the multiply-round-divide step, and the status-server copy is documented as keeping "numbers match the old route exactly"; rounding in one shared place keeps the server's per-day values and the client's overall value consistent.
**Approved**: pending

**Decision**: No input validation and no zero-total guard in `dayStatus`.
**Rationale**: The module is pure arithmetic over counts the status server produces from its own check records; it trusts them. The observable consequences — values above 100 from inconsistent counts, `"down"` for a zero-total day with down checks, `"healthy"` for an empty day — are recorded as requirements and edge cases so ports reproduce them.
**Approved**: pending

**Decision**: The client keeps a duplicate of the server's uptime module.
**Rationale**: `status-server/src/monitor/uptime.ts` and this file are identical apart from comments and wrapping; the client needs `overallUptimePercent` to aggregate the per-service values it receives. Any change to the rounding or rules must land in both copies.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |

`uptime.ts` is pure arithmetic with no I/O, rendering or state, separated from the hook that fetches the data and the component that displays it, so separation-of-concerns passes. `uptime.test.ts` covers every exported function, including the null paths and each `dayStatus` branch, with small independent Vitest cases, so unit-test-coverage and good-test-properties pass. explicit-error-handling is partial: "no data" is signalled explicitly with `null`, but inconsistent or `NaN` counts pass through unvalidated and surface as out-of-range or `NaN` percentages rather than being rejected; the boundary cases (exactly half down, zero total with down checks, negative total) are not in the test suite.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
