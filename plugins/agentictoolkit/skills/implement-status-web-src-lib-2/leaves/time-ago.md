<!-- leaf: implement-status-web-src-lib-2/time-ago · source: status-web-src-lib-time-ago.md -->

**Rules** (cite as `implement-status-web-src-lib-2/time-ago#<slug>`):

- `elapsed-seconds-computation` MUST
- `just-now-bucket` MUST
- `minutes-bucket` MUST
- `hours-bucket` MUST
- `days-bucket` MUST
- `days-unbounded` MUST
- `bucket-evaluation-order` MUST
- `no-suffix-composition` MUST
- `caller-supplied-clock` MUST
- `synchronous-purity` MUST
- `no-throw` MUST
- `iso-precondition` MUST

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
Status Server Monitor Time Ago;
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `iso` | `string` | none (required) | Timestamp of the event, parsed with `new Date(iso)`; not validated. |
| `nowMs` | `number` | none (required) | "Now" in epoch milliseconds, supplied by the caller (usually the `useNow` hook, which refreshes every 30 s by default). |

## Localization

`timeAgo` returns hardcoded English text with no message catalog or `Intl` lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| none (hardcoded) | `just now` | Elapsed time under 60 seconds, or negative |
| none (hardcoded) | number followed by `m` | Elapsed minutes under 60 |
| none (hardcoded) | number followed by `h` | Elapsed hours under 24 |
| none (hardcoded) | number followed by `d` | 24 hours or more |

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
