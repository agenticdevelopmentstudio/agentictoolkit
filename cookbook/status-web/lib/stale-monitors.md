---
id: 9d2d3132-0853-4e3a-8e81-503356e4585d
title: Stale Monitors
domain: agentictoolkit://cookbook/status-web/lib/stale-monitors
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure selection of monitors continuously down for at least 7 days, offered
  to the operator as retire candidates, longest-down first
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status-web/lib/live-types
related:
- agentictoolkit://cookbook/status-web/lib/board-staleness
references: []
approved-by: ''
approved-date: ''
---

# Stale Monitors

## Overview

`stale-monitors.ts` (`packages/web/packages/status-web/src/lib/stale-monitors.ts`) owns the rule that picks which monitors the status dashboard offers for a one-click retire. It exports one constant, `STALE_MONITOR_MS` (7 days), one output type, `StaleMonitor`, and one pure function, `selectStaleMonitors(services, nowMs, thresholdMs?)`.

Per the module header, this is "the AMBIGUOUS half of ghost cleanup, and only that half". A monitor whose project or host provably stopped existing is deleted by the backend cycle (`retireUnclaimedMonitors` in the status server's `src/monitor/sync`) and never reaches this function. What remains is a monitor still claimed by a live deploy project but DOWN for a week: that may be a site nobody turned off or an outage nobody fixed, so it is surfaced for the operator to decide rather than removed. DNS resolution selects nothing in either direction; it is carried through only so the UI can word its confirm prompt.

The input rows are `LiveServiceDTO` values from the live snapshot ([Live Types](agentictoolkit://cookbook/status-web/lib/live-types)). The sole production call site is the `StaleMonitorsBanner` component, which calls the function with a day-floored clock and turns each row into a retire button backed by `deleteEndpoint(slug)`.

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

## Appearance

Not applicable — this is a pure selection function over live-service data, not a visual component.

## States

Not applicable — this is a pure selection function over live-service data, not a visual component.

## Accessibility

Not applicable — this is a pure selection function over live-service data, not a visual component.

## Conformance Test Vectors

All vectors use `NOW = Date.parse("2026-06-26T00:00:00.000Z")` and a base service with `slug "ep1"`, `name "Site"`, `url "https://site.example.com"`, `environment "production"`, `status "down"`, `statusCode null`, `error "HTTP 500"`, `dnsOk true` and `downSince` 30 days before `NOW`, with the named fields overridden. Vectors 001 to 010 are traced to the assertions in `stale-monitors.test.ts`; 011 to 017 are traced to the function body.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stale-monitors-001 | select-down-only, row-slug, row-dns-ok, row-detail-error, row-age | Base service | One row: `slug "ep1"`, `dnsOk true`, `detail "HTTP 500"`, `ageMs` = 2 592 000 000 |
| stale-monitors-002 | select-dns-neutral, select-sort-order | `gone` (down 90 days, error "DNS: does not resolve"), `also-gone` (down 9 days), `alive` (healthy, `downSince null`); run once with `dnsOk false` and once with `dnsOk true` | Both runs return slugs `["gone", "also-gone"]` |
| stale-monitors-003 | row-dns-ok | Base service with `dnsOk false` | One row with `dnsOk false` |
| stale-monitors-004 | select-inclusive-threshold | Base service down 2 days | `[]` |
| stale-monitors-005 | select-down-only, select-requires-down-since | `h` healthy with `downSince null`; `d` degraded down 40 days; `x` down with `downSince null` | `[]` |
| stale-monitors-006 | select-non-finite-age | Base service with `downSince "not-a-date"` | `[]` |
| stale-monitors-007 | row-detail-status-code | Base service with `error null`, `statusCode 503` | One row with `detail "HTTP 503"` |
| stale-monitors-008 | select-sort-order | `newer` down 8 days, then `older` down 90 days | Slugs `["older", "newer"]` |
| stale-monitors-009 | stale-threshold-default | Read `STALE_MONITOR_MS` | 604 800 000 |
| stale-monitors-010 | select-inclusive-threshold, select-default-threshold | Base service down exactly 7 days; separately, down 6 days | One row; `[]` |
| stale-monitors-011 | row-detail-fallback | Base service with `error null`, `statusCode null` | One row with `detail "down"` |
| stale-monitors-012 | row-environment | Base service with `environment ""` | One row with `environment null` |
| stale-monitors-013 | select-empty-input | `selectStaleMonitors([], NOW)` | `[]` |
| stale-monitors-014 | select-requires-down-since | Base service with `downSince ""` | `[]` |
| stale-monitors-015 | select-signature, select-inclusive-threshold | Base service down 2 days, `thresholdMs` = 86 400 000 | One row with `ageMs` = 172 800 000 |
| stale-monitors-016 | row-projection, row-down-since, row-name-url | Base service | Row keys are exactly `slug, name, url, environment, detail, dnsOk, downSince, ageMs`; `downSince` equals the input string |
| stale-monitors-017 | select-no-mutation | Freeze the input array and each service, then call | No exception; input unchanged |

## Edge Cases

- **Empty services**: The result MUST be `[]`. The banner then renders nothing.
- **`downSince` null or empty**: A `"down"` service MUST be skipped, since the onset is unknown.
- **Malformed `downSince`**: `Date.parse` returns `NaN`, the age is non-finite, and the service MUST be skipped. The explicit `Number.isFinite` guard exists because `NaN < thresholdMs` is `false` and would otherwise let the row through.
- **`downSince` in the future**: The age is negative, which is below any non-negative threshold, so the service MUST be skipped.
- **Age exactly at threshold**: The service MUST be included (the comparison is strict less-than for exclusion).
- **`nowMs` that is `NaN`**: Every age is non-finite, so the result MUST be `[]`.
- **`thresholdMs` of 0 or negative**: Every down service whose finite age is at least `thresholdMs` MUST be selected (with 0, every onset at or before `nowMs`); the function does not validate the threshold. The sole caller never passes one.
- **`thresholdMs` of `NaN`**: `ageMs < NaN` is `false`, so every down service with a finite age MUST be selected. This is a fact of the comparison; the argument is typed `number` and the only caller uses the default.
- **`thresholdMs` of `Infinity`**: No service MUST be selected.
- **Empty-string `error`**: `detail` MUST be `""`, not the status-code or `"down"` fallback, because `??` only replaces `null` and `undefined`.
- **Equal ages**: Rows MUST keep their relative input order.
- **Host that no longer resolves**: The row MUST still be offered, with `dnsOk false`; DNS is explanatory only.
- **Concurrent access**: Not applicable. The function is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The function performs no I/O. A failed retire is the caller's `deleteEndpoint` error, which the banner surfaces as `"Retire failed: …"`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services` | `readonly LiveServiceDTO[]` | none (required) | The live snapshot's services. The banner passes `store.snapshot?.services ?? []`. |
| `nowMs` | `number` | none (required) | Reference time in epoch ms. The banner passes the client clock floored to the day. |
| `thresholdMs` | `number` | `STALE_MONITOR_MS` | Minimum continuous down time before a monitor is offered. |
| `STALE_MONITOR_MS` | constant | 604 800 000 (7 days) | Compiled-in default threshold. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. Its only import is the `LiveServiceDTO` type from `./live-types`.

## Deep Linking

Not applicable: the module exports a pure function, a type and a constant, and has no navigable surface.

## Localization

Not applicable: the only strings the module produces are the `detail` values `"HTTP <code>"` and `"down"`, which are fixed English status tokens passed through to the banner; the user-facing sentences around them are composed in `StaleMonitorsBanner`, not here.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and the selection rule always applies.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only monitor metadata (names, URLs, status codes, timestamps) already on the board, and stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as a free function or a caseless `enum StaleMonitors` namespace returning `[StaleMonitor]`, with `StaleMonitor` a `Sendable` struct and `static let staleMonitorMs: Int64 = 7 * 24 * 60 * 60 * 1000`. Parse `downSince` with `ISO8601DateFormatter` (with `.withFractionalSeconds`) or `Date(_:strategy: .iso8601)`; a failed parse yields `nil`, so map `nil` explicitly to "skip" to keep the non-finite-age rule. Sort with `sorted { $0.ageMs > $1.ageMs }`, noting Swift's `sort` is not guaranteed stable, so add the input index as a tie-breaker to preserve input order. Call it from a view model keyed to a day-floored clock.
- **Compose**: Use a Kotlin top-level function returning `List<StaleMonitor>` with a `data class StaleMonitor` and `const val STALE_MONITOR_MS = 7L * 24 * 60 * 60 * 1000`. `Instant.parse` throws `DateTimeParseException` instead of returning NaN, so catch it and skip the row. `sortedByDescending { it.ageMs }` is stable, matching the source. Remember the result with `remember(services, dayMs)`.
- **React/Web**: This is the source: `src/lib/stale-monitors.ts`, tested by `src/lib/stale-monitors.test.ts` (vitest) and called only by `src/components/StaleMonitorsBanner.tsx` inside `useMemo` keyed to `[services, dayMs]`. The non-finite guard depends on `Date.parse` returning `NaN`; tie order depends on ES2019 stable `Array.prototype.sort`; `environment` normalisation depends on `||` and `detail` on `??`.
- **AppKit / UIKit**: Use the same pure Swift function as the SwiftUI port, placed in a shared framework target since nothing in it is UI-bound. Drive the day-floored `nowMs` from a `Timer` or the app's clock and re-run on snapshot change.
- **WinUI 3**: Port as a `public static class StaleMonitors` with `public const long StaleMonitorMs = 7L * 24 * 60 * 60 * 1000;`, a `public sealed record StaleMonitor(string Slug, string Name, string Url, string? Environment, string Detail, bool DnsOk, string DownSince, long AgeMs);` and `public static IReadOnlyList<StaleMonitor> Select(IReadOnlyList<LiveServiceDto> services, long nowMs, long thresholdMs = StaleMonitorMs)`. Parse with `DateTimeOffset.TryParse(s.DownSince, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and skip on `false`, since .NET has no NaN parse result; compute `nowMs - t.ToUnixTimeMilliseconds()`. Use LINQ `OrderByDescending(m => m.AgeMs)`, which is stable like the source (`List<T>.Sort` is not). Map the empty-string environment with `string.IsNullOrEmpty(env) ? null : env` and the detail with `s.Error ?? (s.StatusCode is int c ? $"HTTP {c}" : "down")`. The DTOs deserialise with `System.Text.Json` (camelCase naming policy). The view model that owns the banner would hold the result in an `ObservableCollection<StaleMonitor>` refreshed when the snapshot changes or a `DispatcherQueueTimer` crosses a day boundary, raising `INotifyPropertyChanged`; the function itself stays synchronous with no `Task`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/stale-monitors.ts` |

## Design Decisions

**Decision**: Offer only down-for-a-week monitors that the backend has not already deleted, and never delete automatically.
**Rationale**: The backend cycle deletes a monitor no platform inventory claims. What remains is still claimed, so it is ambiguous (abandoned site or unfixed outage), and only the operator can decide; the banner arms a per-row destructive confirm.
**Approved**: pending

**Decision**: Use a 7-day threshold, inclusive.
**Rationale**: The `STALE_MONITOR_MS` doc comment says a genuine outage lasting a week is essentially unheard of, so an endpoint still failing at that age is almost always abandoned. It is purely a view threshold.
**Approved**: pending

**Decision**: DNS resolution selects nothing and is carried through only for the confirm wording.
**Rationale**: The header says a name that stopped resolving is not evidence the deployment was deleted, nor is resolving evidence it exists. The test notes DNS once gated this list in both directions on a 7-day DNS clock; that was removed with the clock, because withholding a row would leave it unremovable.
**Approved**: pending

**Decision**: Skip rows whose age is not finite, rather than treating them as old.
**Rationale**: A malformed or absent `downSince` means the age "can't judge"; skipping ensures a bad timestamp never offers a live monitor for retirement, and the explicit guard avoids the `NaN < x` quirk.
**Approved**: pending

**Decision**: Project to a minimal row with no site or ownership data.
**Rationale**: Retiring is a single `deleteEndpoint(slug)` call, and the backend drops an emptied site atomically, so the view needs only the fields it displays plus the slug.
**Approved**: pending

**Decision**: Keep the function pure over `(services, now)`.
**Rationale**: The header states this makes the rule unit-testable; the caller supplies a day-floored clock so ages and memoisation stay stable between ticks.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of concerns.** The module owns only the selection rule; rendering, confirmation and deletion live in `StaleMonitorsBanner` and the API client.

**Unit test coverage.** `stale-monitors.test.ts` covers inclusion, the inclusive 7-day boundary, status and missing-onset exclusion, malformed timestamps, DNS neutrality, the status-code detail and sort order.

**Explicit error handling.** A malformed timestamp is handled by an explicit `Number.isFinite` guard rather than an exception or a silent pass-through.

**Data integrity.** A row is offered only on a parseable server-truth `downSince`, so no live monitor can be surfaced for deletion on data the function cannot judge.

**Graceful degradation.** Missing onset, unknown status or empty input yields fewer or no rows, never an error; the banner then renders nothing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
