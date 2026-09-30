<!-- leaf: implement-status-web-src-lib-2/uptime · source: status-web-src-lib-uptime.md -->

**Rules** (cite as `implement-status-web-src-lib-2/uptime#<slug>`):

- `counts-shape` MUST
- `counts-not-validated` MUST
- `service-input-shape` MUST
- `uptime-null-when-no-checks` MUST
- `uptime-degraded-counts-as-up` MUST
- `uptime-denominator-total` MUST
- `uptime-two-decimal-rounding` MUST
- `uptime-no-clamp` MUST
- `day-down-majority` MUST
- `day-down-minority` MUST
- `day-degraded` MUST
- `day-healthy` MUST
- `day-down-checked-first` MUST
- `day-zero-total-with-down` MUST
- `overall-ignores-null` MUST
- `overall-null-when-no-data` MUST
- `overall-unweighted-mean` MUST
- `overall-two-decimal-rounding` MUST
- `overall-nan-propagates` MUST
- `pure-functions` MUST
- `synchronous` MUST
- `no-errors-raised` MUST

# Uptime Math

## Overview

`uptime.ts` (`packages/web/packages/status-web/src/lib/uptime.ts`) is the status-web client's copy of the uptime arithmetic. It has no I/O, no state and no dependencies beyond the `HealthStatus` type from the sibling `health.ts` (see Health Classification). It exports:

- `Counts` — an interface of four numbers: `total`, `healthy`, `degraded`, `down`.
- `uptimePercent(c: Counts): number | null` — the share of checks that were up (healthy or degraded), as a percentage rounded to two decimals, or `null` when there were no checks.
- `dayStatus(c: Counts): HealthStatus` — collapses a day's counts to one `"healthy"`, `"degraded"` or `"down"` verdict.
- `overallUptimePercent(services): number | null` — the portfolio-wide uptime, the simple unweighted mean of each service's own `uptimePercent`, rounded to two decimals, or `null` when no service has data.

Within status-web only `overallUptimePercent` is called at runtime: `OverviewTab.tsx` passes it `uptimeQuery.data?.services ?? []` (the `UptimeService[]` from useUptime) and renders the result in `OverviewStats`. The per-day `uptimePercent` and `status` values arrive already computed from the status server, whose `monitor/uptime.ts` (see Status Server Monitor Uptime) carries the same three functions and backs the `/uptime` read route. The two files differ only in comments and line wrapping.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `c` (argument to `uptimePercent`, `dayStatus`) | `Counts` | none — required | The day's check counts: `total`, `healthy`, `degraded`, `down`. |
| `services` (argument to `overallUptimePercent`) | `{ uptimePercent: number \| null }[]` | none — required | One entry per service; in status-web the `UptimeService[]` from the `/uptime` response, or `[]` while loading. |
| Down-majority threshold | constant | `0.5` | Hardcoded in `dayStatus`; strictly greater than this share of down checks makes the day `"down"`. Not configurable. |
| Rounding precision | constant | 2 decimal places | Hardcoded in both percent functions. Not configurable. |

The module reads no environment variables, settings keys or injected dependencies.

## Platform Notes

- **SwiftUI**: Port as free functions or static members of a `Sendable` value-type namespace (`enum UptimeMath`), with `struct Counts: Sendable, Equatable` of `Int` fields and a `HealthStatus` `String`-backed enum. Return `Double?` for the percentages. Reproduce the rounding as `(ratio * 10000).rounded(.toNearestOrAwayFromZero) / 100`; for non-negative values this matches JavaScript `Math.round` (halves up). With `Int` counts, compute the `dayStatus` ratio in `Double` so a zero-total day with down checks yields positive infinity (and `"down"`) as in the source, instead of trapping on integer division by zero. The status-server copy in `monitor/uptime.ts` is the same contract.
- **Compose**: Kotlin top-level functions in an `object UptimeMath`, `data class Counts(val total: Int, val healthy: Int, val degraded: Int, val down: Int)`, and `enum class HealthStatus`. Use `Double` division; avoid `kotlin.math.round`, which rounds halves to even, and use `roundToLong()` (halves toward positive infinity) to match JavaScript `Math.round`. `filterNotNull().average()` gives the unweighted mean; return `null` when the filtered list is empty rather than `average()`'s `NaN`.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/uptime.ts` holds the functions; `uptime.test.ts` beside it is the Vitest suite; `OverviewTab.tsx` is the only runtime caller (of `overallUptimePercent`). `packages/web/packages/status-server/src/monitor/uptime.ts` is the server twin that computes the per-day values the client receives. Specific to TypeScript: the `filter((p): p is number => p != null)` type guard also drops `undefined`, and `Math.round` rounds halves toward positive infinity.
- **AppKit / UIKit**: Same Swift port as SwiftUI — the module is UI-free; share it from a framework target so both app flavors and any server-side Swift use one implementation. Format the returned `Double` for display with `NumberFormatter` or `FormatStyle` in the view layer, not in this module.
- **WinUI 3**: Port to a C# `static class UptimeMath` in a .NET class library with `public readonly record struct Counts(int Total, int Healthy, int Degraded, int Down)` and `public enum HealthStatus { Healthy, Degraded, Down }`; return `double?`. Match JavaScript rounding with `Math.Round(ratio * 10000, MidpointRounding.AwayFromZero) / 100` — the default `Math.Round` uses banker's rounding (`MidpointRounding.ToEven`) and would diverge on halves. Cast to `double` before dividing (`(double)c.Down / c.Total`) so integer division does not truncate, and so a zero total yields `double.PositiveInfinity` rather than a `DivideByZeroException`. `services.Select(s => s.UptimePercent).Where(p => p.HasValue).Select(p => p!.Value)` then `Average()` gives the mean; check `Any()` first because `Average()` on an empty sequence throws. When the input is deserialized with `System.Text.Json` from the `/uptime` response, map `uptimePercent` to `double?`. Nothing here needs `Task`/`async`, `ObservableCollection` or `INotifyPropertyChanged`: call the functions from the view model that owns the uptime data and expose the result as a bound property there.

