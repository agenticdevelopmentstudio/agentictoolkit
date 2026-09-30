<!-- leaf: implement-status-web-src-lib-2/stale-monitors · source: status-web-src-lib-stale-monitors.md -->

**Rules** (cite as `implement-status-web-src-lib-2/stale-monitors#<slug>`):

- `stale-threshold-default` MUST
- `stale-threshold-view-only` MUST
- `row-slug` MUST
- `row-name-url` MUST
- `row-environment` MUST
- `row-detail-error` MUST
- `row-detail-status-code` MUST
- `row-detail-fallback` MUST
- `row-dns-ok` MUST
- `row-down-since` MUST
- `row-age` MUST
- `row-projection` MUST
- `select-signature` MUST
- `select-default-threshold` MUST
- `select-down-only` MUST
- `select-requires-down-since` MUST
- `select-non-finite-age` MUST
- `select-inclusive-threshold` MUST
- `select-dns-neutral` MUST
- `select-sort-order` MUST
- `select-sort-ties` MUST
- `select-empty-input` MUST
- `select-no-mutation` MUST
- `pure-function` MUST
- `no-deletion` MUST
- `caller-clock` MUST

# Stale Monitors

## Overview

`stale-monitors.ts` (`packages/web/packages/status-web/src/lib/stale-monitors.ts`) owns the rule that picks which monitors the status dashboard offers for a one-click retire. It exports one constant, `STALE_MONITOR_MS` (7 days), one output type, `StaleMonitor`, and one pure function, `selectStaleMonitors(services, nowMs, thresholdMs?)`.

Per the module header, this is "the AMBIGUOUS half of ghost cleanup, and only that half". A monitor whose project or host provably stopped existing is deleted by the backend cycle (`retireUnclaimedMonitors` in the status server's `src/monitor/sync`) and never reaches this function. What remains is a monitor still claimed by a live deploy project but DOWN for a week: that may be a site nobody turned off or an outage nobody fixed, so it is surfaced for the operator to decide rather than removed. DNS resolution selects nothing in either direction; it is carried through only so the UI can word its confirm prompt.

The input rows are `LiveServiceDTO` values from the live snapshot (Live Types). The sole production call site is the `StaleMonitorsBanner` component, which calls the function with a day-floored clock and turns each row into a retire button backed by `deleteEndpoint(slug)`.

## Behavioral Requirements

### Constant

- **stale-threshold-default**: `STALE_MONITOR_MS` MUST equal `7 * 24 * 60 * 60 * 1000`, which is 604 800 000 ms.
- **stale-threshold-view-only**: `STALE_MONITOR_MS` MUST only decide what is offered. Per its doc comment it is "Purely a VIEW threshold"; nothing the backend deletes depends on it.

### StaleMonitor shape

- **row-slug**: `StaleMonitor.slug` MUST be the input service's `slug`, which is the endpoint id and the delete target.
- **row-name-url**: `StaleMonitor.name` and `StaleMonitor.url` MUST be copied unchanged from the input service.
- **row-environment**: `StaleMonitor.environment` MUST be the input `environment` when it is truthy, and `null` when it is an empty string (the source uses `s.environment || null`).
- **row-detail-error**: `StaleMonitor.detail` MUST be the input `error` whenever `error` is neither `null` nor `undefined`, including an empty string (the source uses `??`).
- **row-detail-status-code**: When `error` is `null` or `undefined` and `statusCode` is not `null` or `undefined`, `StaleMonitor.detail` MUST be `"HTTP "` followed by the status code (for example `"HTTP 503"`).
- **row-detail-fallback**: When both `error` and `statusCode` are `null` or `undefined`, `StaleMonitor.detail` MUST be the literal `"down"`.
- **row-dns-ok**: `StaleMonitor.dnsOk` MUST be copied unchanged from the input `dnsOk`.
- **row-down-since**: `StaleMonitor.downSince` MUST be the input `downSince` string unchanged (an ISO timestamp that is server truth).
- **row-age**: `StaleMonitor.ageMs` MUST equal `nowMs - Date.parse(downSince)`.
- **row-projection**: The output row MUST carry only `slug`, `name`, `url`, `environment`, `detail`, `dnsOk`, `downSince` and `ageMs`. The other `LiveServiceDTO` fields (`group`, `platform`, `deployProject`, `responseTimeMs`, `lastCheckedAt`, `status`, `statusCode`, `error`) are deliberately dropped; the doc comment says no site or ownership data is needed because retiring is a single `deleteEndpoint(slug)` call.

### selectStaleMonitors

- **select-signature**: `selectStaleMonitors` MUST take `services: readonly LiveServiceDTO[]`, `nowMs: number` (epoch ms) and an optional `thresholdMs: number`, and MUST return a new `StaleMonitor[]`.
- **select-default-threshold**: When `thresholdMs` is omitted, the function MUST use `STALE_MONITOR_MS`.
- **select-down-only**: The function MUST skip every service whose `status` is not exactly `"down"` (so `"healthy"`, `"degraded"` and `"unknown"` are never selected).
- **select-requires-down-since**: The function MUST skip a `"down"` service whose `downSince` is falsy (`null` or an empty string), because an unknown onset cannot be judged.
- **select-non-finite-age**: The function MUST skip a service whose computed age is not finite (a malformed `downSince` that `Date.parse` returns `NaN` for), so a bad timestamp never surfaces a monitor as a retire candidate.
- **select-inclusive-threshold**: The function MUST include a service whose age is exactly `thresholdMs`; only an age strictly less than `thresholdMs` is excluded.
- **select-dns-neutral**: The function MUST select the same rows whatever each service's `dnsOk` value is. DNS neither triggers nor withholds the offer.
- **select-sort-order**: The returned array MUST be sorted by `ageMs` descending (longest-down first).
- **select-sort-ties**: Rows with equal `ageMs` MUST keep their input order, because `Array.prototype.sort` is stable.
- **select-empty-input**: An empty `services` array MUST return an empty array.
- **select-no-mutation**: The function MUST NOT mutate `services` or any service object; it builds a fresh output array.

### Purity and concurrency

- **pure-function**: `selectStaleMonitors` MUST be synchronous and MUST NOT perform I/O, log, read the clock or throw on any input of the declared types. Its result depends only on `(services, nowMs, thresholdMs)`, which the header states is so "the rule is unit-testable".
- **no-deletion**: The module MUST NOT delete, retire or otherwise act on any monitor. Retiring is the caller's `deleteEndpoint` call, and the backend owns the atomic removal of an emptied site.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so concurrent calls cannot interleave and it needs no ordering rule.
- **caller-clock**: The caller MUST supply `nowMs`. The sole call site passes the client clock floored to the day (`Math.floor(nowMs / 86_400_000) * 86_400_000`), so ages are stable between 30-second ticks and the memoised result only recomputes once a day or when the services change.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services` | `readonly LiveServiceDTO[]` | none (required) | The live snapshot's services. The banner passes `store.snapshot?.services ?? []`. |
| `nowMs` | `number` | none (required) | Reference time in epoch ms. The banner passes the client clock floored to the day. |
| `thresholdMs` | `number` | `STALE_MONITOR_MS` | Minimum continuous down time before a monitor is offered. |
| `STALE_MONITOR_MS` | constant | 604 800 000 (7 days) | Compiled-in default threshold. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. Its only import is the `LiveServiceDTO` type from `./live-types`.

## Platform Notes

- **SwiftUI**: Port as a free function or a caseless `enum StaleMonitors` namespace returning `[StaleMonitor]`, with `StaleMonitor` a `Sendable` struct and `static let staleMonitorMs: Int64 = 7 * 24 * 60 * 60 * 1000`. Parse `downSince` with `ISO8601DateFormatter` (with `.withFractionalSeconds`) or `Date(_:strategy: .iso8601)`; a failed parse yields `nil`, so map `nil` explicitly to "skip" to keep the non-finite-age rule. Sort with `sorted { $0.ageMs > $1.ageMs }`, noting Swift's `sort` is not guaranteed stable, so add the input index as a tie-breaker to preserve input order. Call it from a view model keyed to a day-floored clock.
- **Compose**: Use a Kotlin top-level function returning `List<StaleMonitor>` with a `data class StaleMonitor` and `const val STALE_MONITOR_MS = 7L * 24 * 60 * 60 * 1000`. `Instant.parse` throws `DateTimeParseException` instead of returning NaN, so catch it and skip the row. `sortedByDescending { it.ageMs }` is stable, matching the source. Remember the result with `remember(services, dayMs)`.
- **React/Web**: This is the source: `src/lib/stale-monitors.ts`, tested by `src/lib/stale-monitors.test.ts` (vitest) and called only by `src/components/StaleMonitorsBanner.tsx` inside `useMemo` keyed to `[services, dayMs]`. The non-finite guard depends on `Date.parse` returning `NaN`; tie order depends on ES2019 stable `Array.prototype.sort`; `environment` normalisation depends on `||` and `detail` on `??`.
- **AppKit / UIKit**: Use the same pure Swift function as the SwiftUI port, placed in a shared framework target since nothing in it is UI-bound. Drive the day-floored `nowMs` from a `Timer` or the app's clock and re-run on snapshot change.
- **WinUI 3**: Port as a `public static class StaleMonitors` with `public const long StaleMonitorMs = 7L * 24 * 60 * 60 * 1000;`, a `public sealed record StaleMonitor(string Slug, string Name, string Url, string? Environment, string Detail, bool DnsOk, string DownSince, long AgeMs);` and `public static IReadOnlyList<StaleMonitor> Select(IReadOnlyList<LiveServiceDto> services, long nowMs, long thresholdMs = StaleMonitorMs)`. Parse with `DateTimeOffset.TryParse(s.DownSince, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and skip on `false`, since .NET has no NaN parse result; compute `nowMs - t.ToUnixTimeMilliseconds()`. Use LINQ `OrderByDescending(m => m.AgeMs)`, which is stable like the source (`List<T>.Sort` is not). Map the empty-string environment with `string.IsNullOrEmpty(env) ? null : env` and the detail with `s.Error ?? (s.StatusCode is int c ? $"HTTP {c}" : "down")`. The DTOs deserialise with `System.Text.Json` (camelCase naming policy). The view model that owns the banner would hold the result in an `ObservableCollection<StaleMonitor>` refreshed when the snapshot changes or a `DispatcherQueueTimer` crosses a day boundary, raising `INotifyPropertyChanged`; the function itself stays synchronous with no `Task`.

