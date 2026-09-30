<!-- leaf: implement-status-server-monitor-2/uptime · source: status-server-monitor-uptime.md -->

**Rules** (cite as `implement-status-server-monitor-2/uptime#<slug>`):

- `counts-shape` MUST
- `health-status-return` MUST
- `uptime-percent-formula` MUST
- `uptime-percent-degraded-counts-as-up` MUST
- `uptime-percent-no-data` MUST
- `day-status-down-majority` MUST
- `day-status-down-minority` MUST
- `day-status-degraded-only` MUST
- `day-status-healthy-default` MUST
- `day-status-no-zero-total-guard` MUST
- `overall-uptime-mean` MUST
- `overall-uptime-excludes-null` MUST
- `overall-uptime-no-data` MUST
- `overall-uptime-order-independent` MUST
- `pure-computation` MUST
- `concurrency-safety` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `c` (parameter of `uptimePercent`, `dayStatus`) | `Counts` (`{ total: number; healthy: number; degraded: number; down: number }`) | none — required on every call | The per-endpoint check tallies to score. Supplied fresh by the caller on each call (`buildUptime` in `../routes/reads.ts`, external); never defaulted, cached, or read from configuration by this file. |
| `services` (parameter of `overallUptimePercent`) | `{ uptimePercent: number \| null }[]` | none — required on every call | The list of already-computed per-service uptime percentages to average. Supplied fresh by the caller on each call (`OverviewTab.tsx` in the `status-web` duplicate, external); never defaulted, cached, or read from configuration by this file. |

This module reads no environment variable, consults no settings or feature-flag store, and receives no injected dependency of any kind — every value it needs arrives as a plain function argument on that call.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `Counts` as a `Sendable` `struct` with four `Int` fields (`total`, `healthy`, `degraded`, `down` — the source's untyped `number` fields hold whole check counts), and `HealthStatus` as a `Sendable` `enum` with three cases rather than a bare string union. The two percentage functions become free functions returning `Double?` for the null-when-no-data case; rounding to two decimal places uses `(value * 100).rounded() / 100`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `Counts` as a `data class` with `Int` fields, `HealthStatus` as a `sealed class` or `enum class`, and the two percentage functions as top-level `fun`s returning `Double?`; `kotlin.math.round` matches `Math.round`'s round-half-up behavior closely enough for this domain, since every ratio here is non-negative.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/uptime.ts` as three synchronous, side-effect-free exported functions plus the `Counts` interface, consumed server-side by `buildUptime` in `../routes/reads.ts`. A byte-for-byte-identical `Counts`/`uptimePercent`/`dayStatus`/`overallUptimePercent` quartet is maintained independently in the browser bundle at `packages/web/packages/status-web/src/lib/uptime.ts` (consumed by `OverviewTab.tsx`), because that package cannot import the Node-only server package — the two copies are not linked at build time.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no `NSViewController`/`UIViewController` concept applies. A macOS/iOS agent embedding this arithmetic has no per-thread module-duplication concern to solve, unlike some sibling monitor modules — these functions hold no module-scope state at all, so a single shared implementation is trivially safe to call from any GCD queue or Swift `Task`.
- **WinUI 3**: a .NET port models `Counts` as a `record struct Counts(int Total, int Healthy, int Degraded, int Down)`, `HealthStatus` as a C# `enum HealthStatus { Healthy, Degraded, Down }`, and the three functions as `static` methods on a plain helper class returning `double?` for the no-data cases. `Math.Round(value, 2, MidpointRounding.AwayFromZero)` reproduces `Math.round(x * 100) / 100`'s round-half-away-from-zero behavior for the non-negative percentages this domain always produces — JavaScript's `Math.round` rounds a positive `.5` up, matching `AwayFromZero` rather than .NET's default `ToEven`. No `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or `INotifyPropertyChanged` is needed anywhere in this port; unlike the networked monitor siblings, this module has no I/O and no async boundary — it is three pure, synchronous static methods a WinUI view-model calls directly and assigns straight into whatever bound property already exists.

