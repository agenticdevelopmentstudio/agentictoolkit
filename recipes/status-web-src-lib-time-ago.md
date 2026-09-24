---
id: 66b7f642-d41d-4d84-aea7-624a5f47eef3
title: Status Web Time Ago
domain: agentictoolkit://recipes/status-web-src-lib-time-ago
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure, synchronous function turning an ISO timestamp and a caller-supplied
  clock reading into a compact just-now/m/h/d elapsed-time label for the dashboard.
platforms:
- typescript
- web
tags:
- formatting
- pure-function
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-time-ago
- agentictoolkit://recipes/status-web-hooks-use-now
- agentictoolkit://recipes/status-web-src
references:
- packages/web/packages/status-web/src/lib/time-ago.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/time-ago.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Web Time Ago

## Overview

`time-ago.ts` (`packages/web/packages/status-web/src/lib/time-ago.ts`) is the status
dashboard's single pure function for turning one absolute timestamp into a compact,
human-readable elapsed-time label. It exports one function, `timeAgo(iso, nowMs)`, whose
doc comment states its purpose: "Format elapsed time as a compact string. nowMs is passed
in for testability." Its callers are dashboard components (`DeployList`, `Dashboard`,
`GlobalPanel`, `FleetView`, `StatusMatrix`, `StaleMonitorsBanner`, `SnapshotStaleBanner`,
`configure/ProjectBrowser`); most take `nowMs` from the `useNow` hook, and
`SnapshotStaleBanner` passes `Date.parse(snapshot.generatedAt)` instead. The function body
is byte-for-byte identical to the status server's
[Status Server Monitor Time Ago](agentictoolkit://recipes/status-server-monitor-time-ago);
the two copies share one contract and differ only in their callers and in the web copy
having a test file (`time-ago.test.ts`).

## Behavioral Requirements

### timeAgo

- **elapsed-seconds-computation**: `timeAgo(iso, nowMs)` MUST compute `diffMs` as
  `nowMs - new Date(iso).getTime()` and `diffSecs` as `Math.floor(diffMs / 1000)`, and MUST
  choose its result from `diffSecs` and successive floor-divisions of it.
- **just-now-bucket**: `timeAgo` MUST return the literal string `just now` whenever
  `diffSecs` is strictly less than `60`, which includes every negative `diffSecs` (an `iso`
  later than `nowMs`).
- **minutes-bucket**: `timeAgo` MUST return `diffMins` immediately followed by `m`, where
  `diffMins` is `Math.floor(diffSecs / 60)`, whenever `diffSecs` is at least `60` and
  `diffMins` is strictly less than `60`.
- **hours-bucket**: `timeAgo` MUST return `diffHours` immediately followed by `h`, where
  `diffHours` is `Math.floor(diffMins / 60)`, whenever `diffMins` is at least `60` and
  `diffHours` is strictly less than `24`.
- **days-bucket**: `timeAgo` MUST return `Math.floor(diffHours / 24)` immediately followed
  by `d` whenever `diffHours` is at least `24`.
- **days-unbounded**: The days bucket MUST have no upper bound; the function MUST NOT roll
  over to a week, month or year unit (365 days returns `365d`).
- **bucket-evaluation-order**: `timeAgo` MUST test the buckets in the fixed order seconds,
  minutes, hours, days, and MUST return on the first threshold satisfied.
- **no-suffix-composition**: `timeAgo` MUST NOT append `ago`, a plural form, or a space to
  the unit letter; the result is exactly the number followed by `m`, `h` or `d`, or the
  literal `just now`. Callers compose surrounding text themselves (`Dashboard` builds
  "updated {value} ago"; `ProjectBrowser` appends " ago").
- **caller-supplied-clock**: `timeAgo` MUST take "now" only from its `nowMs` argument and
  MUST NOT read the system clock; the doc comment says `nowMs` "is passed in for
  testability."
- **synchronous-purity**: `timeAgo` MUST run synchronously and return a result determined
  by `iso` and `nowMs` alone, with no I/O, no logging, and no mutation of shared state.
- **no-throw**: `timeAgo` MUST NOT throw for any `string` `iso` and any `number` `nowMs`;
  every path returns a string.
- **iso-precondition**: The caller MUST pass an `iso` string that `new Date` can parse, as
  the parameter name `iso` and its `string` type document; `timeAgo` does not validate it.
  When `new Date(iso).getTime()` or `nowMs` is `NaN`, every comparison is false and the
  function MUST return the literal string `NaNd`. The web callers guard only against a
  missing value (`FleetView`, `StatusMatrix` and `ProjectBrowser` test truthiness, and
  `Dashboard` uses optional chaining before calling), so a malformed API timestamp renders
  `NaNd` visibly rather than vanishing.

## Appearance

Not applicable — this is a time-elapsed formatting function, not a visual component.

## States

Not applicable — this is a time-elapsed formatting function, not a visual component.

## Accessibility

Not applicable — this is a time-elapsed formatting function, not a visual component.

## Conformance Test Vectors

`BASE` is `new Date("2024-06-01T12:00:00Z").getTime()`, as in `time-ago.test.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-time-ago-001 | just-now-bucket | `iso` = `BASE - 30000` as ISO, `nowMs` = `BASE` | `just now` (test "returns just now for less than 60 seconds") |
| status-web-time-ago-002 | just-now-bucket | `iso` = `BASE` as ISO, `nowMs` = `BASE` | `just now` (test "exactly 0 seconds") |
| status-web-time-ago-003 | minutes-bucket, bucket-evaluation-order | `iso` = `BASE - 60000`, `nowMs` = `BASE` | `1m` (test "boundary: exactly 60s") |
| status-web-time-ago-004 | minutes-bucket | `iso` = `BASE - 12 * 60000`, `nowMs` = `BASE` | `12m` (test "less than 1 hour") |
| status-web-time-ago-005 | hours-bucket, bucket-evaluation-order | `iso` = `BASE - 60 * 60000`, `nowMs` = `BASE` | `1h` (test "boundary: exactly 60 minutes") |
| status-web-time-ago-006 | hours-bucket | `iso` = `BASE - 3 * 3600000`, `nowMs` = `BASE` | `3h` (test "less than 1 day") |
| status-web-time-ago-007 | days-bucket, bucket-evaluation-order | `iso` = `BASE - 24 * 3600000`, `nowMs` = `BASE` | `1d` (test "boundary: exactly 24 hours") |
| status-web-time-ago-008 | days-bucket | `iso` = `BASE - 2 * 86400000`, `nowMs` = `BASE` | `2d` (test "1 day or more") |
| status-web-time-ago-009 | just-now-bucket | `iso` = `BASE - 59999`, `nowMs` = `BASE` | `just now` (upper edge; derived from `diffSecs < 60`) |
| status-web-time-ago-010 | minutes-bucket | `iso` = `BASE - 3599000`, `nowMs` = `BASE` | `59m` (derived from source) |
| status-web-time-ago-011 | hours-bucket | `iso` = `BASE - 86399000`, `nowMs` = `BASE` | `23h` (derived from source) |
| status-web-time-ago-012 | days-unbounded | `iso` = `BASE - 365 * 86400000`, `nowMs` = `BASE` | `365d`, no larger unit (derived from source) |
| status-web-time-ago-013 | just-now-bucket | `iso` = `BASE + 300000` (5 minutes in the future), `nowMs` = `BASE` | `just now` (negative `diffSecs`; derived from source) |
| status-web-time-ago-014 | iso-precondition, no-throw | `iso` = `not-a-date`, `nowMs` = `BASE` | `NaNd`, no exception (derived from source) |
| status-web-time-ago-015 | iso-precondition, no-throw | `iso` = empty string, `nowMs` = `BASE` | `NaNd`, no exception (`new Date("")` is invalid) |
| status-web-time-ago-016 | caller-supplied-clock, synchronous-purity, no-suffix-composition | Call vectors 001-008 with `Date.now` and `console` spied | Zero spy calls; every result matches exactly, with no trailing `ago` or space |

## Edge Cases

- **Null and empty input**: `iso` and `nowMs` are required parameters with no runtime
  check. An empty `iso` parses to an invalid date and the function MUST return `NaNd`
  (vector 015). Callers that may hold a missing timestamp guard it themselves before
  calling (for example `StatusMatrix` renders an em dash when there is no deploy).
- **Malformed input**: an unparseable `iso`, or a `nowMs` of `NaN` (possible in
  `SnapshotStaleBanner` if `snapshot.generatedAt` does not parse), MUST produce `NaNd` and
  MUST NOT throw, per `iso-precondition`.
- **Boundary values**: 59 s MUST give `just now` and 60 s MUST give `1m`; 59 min MUST give
  `59m` and 60 min MUST give `1h`; 23 h MUST give `23h` and 24 h MUST give `1d`. Sub-second
  remainders are floored away at every step.
- **Future timestamps**: an `iso` later than `nowMs` (clock skew between the server and the
  browser) MUST give `just now` for any magnitude, because the only lower test is
  `diffSecs < 60`.
- **Large values**: the days count MUST grow without bound (`365d`, `3650d`).
- **Concurrent access**: not applicable; the function is pure, synchronous JavaScript with
  no shared mutable state, so calls cannot interleave.
- **Error states**: the function has no dependency that can fail and never throws; its only
  failure signal is the `NaNd` string.
- **Offline / disconnected state**: not applicable; the function performs no network call.
  Callers already hold the timestamp from fetched dashboard data.
- **Cancellation and timeouts**: not applicable; the call is synchronous and O(1).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `iso` | `string` | none (required) | Timestamp of the event, parsed with `new Date(iso)`; not validated. |
| `nowMs` | `number` | none (required) | "Now" in epoch milliseconds, supplied by the caller (usually the `useNow` hook, which refreshes every 30 s by default). |

## Deep Linking

Not applicable: `timeAgo` is a formatting function with no route or URL.

## Localization

`timeAgo` returns hardcoded English text with no message catalog or `Intl` lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| none (hardcoded) | `just now` | Elapsed time under 60 seconds, or negative |
| none (hardcoded) | number followed by `m` | Elapsed minutes under 60 |
| none (hardcoded) | number followed by `h` | Elapsed hours under 24 |
| none (hardcoded) | number followed by `d` | 24 hours or more |

## Accessibility Options

Not applicable: `timeAgo` has no user interface and responds to no display option.

## Feature Flags

Not applicable: `timeAgo` consults no feature flag.

## Analytics

Not applicable: `timeAgo` emits no analytics event.

## Privacy

Not applicable: `timeAgo` receives only a timestamp and a clock reading, and stores or
transmits nothing.

## Logging

Not applicable: `time-ago.ts` contains no logging call.

| Event | Level | Message |
|-------|-------|---------|
| none | none | `timeAgo` emits no log line. |

## Platform Notes

- **SwiftUI**: a free function taking `Date` values, or `Date.RelativeFormatStyle` if exact
  output parity is not needed. Parse `iso` with `Date.ISO8601FormatStyle`, which throws
  rather than yielding `NaN`, so a port has to choose explicitly whether to return `NaNd`.
  Drive "now" from `TimelineView(.periodic(from:by: 30))` to match `useNow`.
- **Compose**: a top-level `fun timeAgo(iso: String, nowMs: Long): String` using
  `java.time.Instant.parse` (throws `DateTimeParseException`) and `Long` floor division;
  supply `nowMs` from a `produceState` loop with a 30 s `delay`.
- **React/Web** (source platform): `src/lib/time-ago.ts` with vitest coverage in
  `src/lib/time-ago.test.ts`; components pair it with the `useNow` hook so labels re-render
  on a 30 s tick instead of calling `Date.now()` during render. A copy with the same body
  lives in the status server.
- **AppKit / UIKit**: the same Swift function feeds an `NSTextField` or `UILabel`; refresh
  it with a repeating `Timer` rather than on each layout pass.
- **WinUI 3**: a `public static string TimeAgo(string iso, long nowMs)` in a plain C#
  helper class. Parse with `DateTimeOffset.TryParse` (returning `false` is the port's cue
  to emit `NaNd` for parity) and compute seconds with integer division, or subtract
  `DateTimeOffset` values and use `TimeSpan.TotalSeconds` with `Math.Floor`. Bind the
  label through an `x:Bind` function binding against a view-model `Now` property that
  raises `INotifyPropertyChanged.PropertyChanged` from a `DispatcherQueueTimer` ticking
  every 30 s. `HttpClient`, `System.Text.Json`, `Windows.Storage` and `Task`/`async` are
  not needed, since the function has no I/O.

## Design Decisions

- **Decision**: take `nowMs` as a parameter rather than reading the clock.
  **Rationale**: the doc comment says it is "passed in for testability"; it also lets
  callers share one `useNow` tick so labels stay stable between re-renders.
  **Approved**: pending
- **Decision**: a single `diffSecs < 60` test with no `>= 0` check, so future timestamps
  show `just now`.
  **Rationale**: not stated in source; recorded as a fact. It hides server/browser clock
  skew instead of showing a negative age.
  **Approved**: pending
- **Decision**: four buckets with no unit above days and no `ago` suffix.
  **Rationale**: the compact token fits the dense dashboard cells it feeds, and callers
  such as `Dashboard` and `ProjectBrowser` add their own wording.
  **Approved**: pending
- **Decision**: duplicate the function in status-web and status-server instead of sharing
  one module.
  **Rationale**: not stated in source; the two packages are deployed separately. A port
  must keep the two copies' behavior identical.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |

`unit-test-coverage` passes: `time-ago.test.ts` asserts every bucket and every bucket
boundary. `separation-of-concerns` passes: the file only formats, and it leaves the clock
to `useNow` and the surrounding wording to the components. `good-test-properties` passes:
the tests use a fixed `BASE` instant and no real clock, so they are fast, isolated and
repeatable. `explicit-error-handling` is partial: an unparseable timestamp is not checked
and instead comes out as the visible string `NaNd`, which is never thrown or reported to
the caller, and no test covers that path.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 |  |  | Initial creation |
