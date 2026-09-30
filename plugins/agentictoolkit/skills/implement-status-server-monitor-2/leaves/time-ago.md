<!-- leaf: implement-status-server-monitor-2/time-ago · source: status-server-monitor-time-ago.md -->

**Rules** (cite as `implement-status-server-monitor-2/time-ago#<slug>`):

- `elapsed-seconds-computation` MUST
- `just-now-bucket` MUST
- `minutes-bucket` MUST
- `hours-bucket` MUST
- `days-bucket` MUST
- `bucket-evaluation-order` MUST
- `no-suffix-composition` MUST
- `caller-supplied-clock` MUST
- `synchronous-purity` MUST
- `no-throw-on-well-formed-input` MUST

# Status Server Monitor Time Ago

## Overview

`time-ago.ts` (`packages/web/packages/status-server/src/monitor/time-ago.ts`) is the
status server's single pure function for turning one absolute timestamp into a compact,
human-readable elapsed-time label. It exports one function, `timeAgo(iso, nowMs)`, whose
own doc comment states its purpose directly: "Format elapsed time as a compact string.
nowMs is passed in for testability." It has two callers in the given source tree:
`integrations.ts`'s freshness check for the last stored health-check timestamp
(`ageLabel`, folded into a `"stale — last {ageLabel} ago"` / `"last check {ageLabel} ago"`
detail string), and `fetch-vercel-projects.ts`'s `staleDetail`, which folds the age of a
stale production project's last live build into a `"... live build {age} old"` message.
Both callers derive `iso` from a `Date` they already checked is valid or non-null before
calling `timeAgo`, and both pass a `Date.now()`-derived value for `nowMs`.

## Behavioral Requirements

### timeAgo

- **elapsed-seconds-computation**: `timeAgo(iso, nowMs)` MUST compute `diffMs` as
  `nowMs - new Date(iso).getTime()` and `diffSecs` as `Math.floor(diffMs / 1000)`, and MUST
  select its return value from `diffSecs` and the successive floor-divisions of it, never
  from `diffMs` directly.
- **just-now-bucket**: `timeAgo` MUST return the literal string `just now` whenever
  `diffSecs` is strictly less than `60`; because the comparison is unconditional, this
  range covers every value from `0` through `59` and every negative `diffSecs` as well.
- **minutes-bucket**: `timeAgo` MUST return the string formed by `diffMins` followed by the
  literal letter `m` (`` `${diffMins}m` ``), where `diffMins` is `Math.floor(diffSecs / 60)`,
  whenever `diffSecs` is `60` or greater and `diffMins` is strictly less than `60`.
- **hours-bucket**: `timeAgo` MUST return the string formed by `diffHours` followed by the
  literal letter `h` (`` `${diffHours}h` ``), where `diffHours` is
  `Math.floor(diffMins / 60)`, whenever `diffMins` is `60` or greater and `diffHours` is
  strictly less than `24`.
- **days-bucket**: `timeAgo` MUST return the string formed by `Math.floor(diffHours / 24)`
  followed by the literal letter `d` (`` `${Math.floor(diffHours / 24)}d` ``) whenever
  `diffHours` is `24` or greater; this bucket has no upper bound — an elapsed time of ten
  years MUST still be returned as a single `d`-suffixed number (approximately `3650d`)
  rather than switching to a week/month/year unit.
- **bucket-evaluation-order**: `timeAgo` MUST evaluate the four buckets in the fixed order
  seconds → minutes → hours → days and MUST return on the first threshold satisfied,
  never evaluating a later bucket once an earlier one has matched.
- **no-suffix-composition**: `timeAgo` MUST NOT append `"ago"`, a plural suffix, or any
  separator to the unit letter; its return value is exactly the numeric bucket value
  immediately followed by `m`, `h`, or `d` with no space, or the fixed literal `just now`.
  Composing a sentence such as `"last {value} ago"` (per `integrations.ts`) or
  `"live build {value} old"` (per `fetch-vercel-projects.ts`) is each caller's own concern,
  external to this file.
- **caller-supplied-clock**: `timeAgo` MUST take its notion of "now" exclusively from its
  `nowMs` argument and MUST NOT call `Date.now()` or read the system clock internally;
  per the source's own doc comment, `nowMs` "is passed in for testability."
- **synchronous-purity**: `timeAgo` MUST execute synchronously and MUST compute its result
  deterministically from `iso` and `nowMs` alone, performing no I/O, no logging, and no
  mutation of either argument.
- **no-throw-on-well-formed-input**: `timeAgo` MUST NOT throw for any `iso` string that
  `new Date` parses to a valid timestamp and any finite `nowMs` number; every branch it can
  take returns a string value.
- **no-iso-validation**: `timeAgo` expects its caller to pass a parseable ISO-8601 timestamp, as its parameter name `iso` states, and does not validate it. When `new Date(iso).getTime()` returns `NaN`, every threshold comparison evaluates `false`, the function falls through to the days branch and returns the literal string `'NaNd'`. It never throws. Both callers (`integrations.ts` and `fetch-vercel-projects.ts`) build `iso` with `Date.prototype.toISOString()`, which throws on an invalid date, so neither can pass it a malformed string.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `iso` | `string` | none — required positional argument | ISO-8601 timestamp string of the event being measured; passed to `new Date(iso).getTime()` with no validation of its format. |
| `nowMs` | `number` | none — required positional argument | The caller-supplied "current time" in epoch milliseconds, against which `iso` is compared; per the source's own doc comment, this is passed in rather than read from `Date.now()` internally "for testability." |

## Localization

`timeAgo` returns four hardcoded English literals with no lookup through any i18n/l10n
mechanism (a message catalog, `Intl`, or similar):

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — hardcoded literal, no key | `just now` | Returned when elapsed time is under 60 seconds, or negative |
| n/a — hardcoded template literal, no key | `` `${diffMins}m` `` | Returned when elapsed minutes is under 60 |
| n/a — hardcoded template literal, no key | `` `${diffHours}h` `` | Returned when elapsed hours is under 24 |
| n/a — hardcoded template literal, no key | `` `${days}d` `` | Returned when elapsed hours is 24 or greater, unbounded |

Neither the fixed phrase `just now` nor the unit letters `m`/`h`/`d` would render correctly
for a non-English-reading caller; both are baked directly into the function body rather
than resolved from any translatable source.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port has no natural class or actor
  to attach to — it is one free function, `func timeAgo(iso: String, nowMs: Double) -> String`
  (or, more idiomatically, one that takes a `Date` "now" rather than raw milliseconds); the
  four-bucket threshold chain (`< 60`, `< 60`, `< 24`) ports directly with integer division
  and `floor`. Parsing `iso` requires `ISO8601DateFormatter` (or `Date.ISO8601FormatStyle`),
  which returns `nil` on an unparseable string — unlike the source's silent `NaN`
  fall-through, a Swift port is forced to consciously decide what to do with that `nil`,
  which `no-iso-validation` leaves to the caller in the source.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `timeAgo` as a
  top-level `fun timeAgo(iso: String, nowMs: Long): String`, parsing `iso` with
  `java.time.Instant.parse` (which throws `DateTimeParseException` on malformed input,
  again forcing an explicit decision the source's silent fall-through avoids), then the
  same floor-divide bucket chain using `Long` arithmetic.
- **React/Web** (source platform): lives at
  `packages/web/packages/status-server/src/monitor/time-ago.ts` on the Node status
  backend. Its only two callers in the given source tree are `integrations.ts` (labeling
  the freshness of the last stored health-check timestamp) and `fetch-vercel-projects.ts`
  (labeling the age of a stale production project's last live build); no dedicated test
  file exercises `timeAgo` anywhere in the given source tree.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; no windowing or view-layer concern
  applies. Any label (`UILabel`/`NSTextField`) that displays `timeAgo`'s output does so
  verbatim, with no additional truncation or styling needed since the string is already a
  short, fixed-format token.
- **WinUI 3**: a .NET port models `timeAgo` as a `static` method — for example
  `public static string TimeAgo(DateTimeOffset iso, DateTimeOffset now)` — preferring
  `DateTimeOffset` subtraction (`(now - iso).TotalSeconds`) over round-tripping through raw
  milliseconds, then the same floor-divide bucket chain via `Math.Floor`.
  `DateTimeOffset.Parse` throws `FormatException` on a malformed `iso` string — again an
  explicit decision a WinUI 3 port must make where the source silently falls through to
  `NaNd`. None of `HttpClient`, `Task`/`async`, `Windows.Storage`, `ObservableCollection`,
  or `INotifyPropertyChanged` is needed: this is a synchronous, non-UI-bound,
  side-effect-free string-formatting utility with no I/O, no asynchronous operation, and no
  persistence.

## Design Decisions

- **Decision**: use a single `diffSecs < 60` comparison for the just-now bucket rather than
  additionally checking `diffSecs >= 0`, so any negative `diffSecs` (an `iso` timestamp that
  is later than `nowMs`) also formats as `'just now'` rather than being rejected or given a
  distinct label.
  **Rationale**: not stated in source; recorded here as a fact of the code per this
  recipe's authoring rules. Both real callers derive `iso` from a timestamp that has
  already happened relative to their own `nowMs`, so a negative `diffSecs` does not
  currently surface in practice, but nothing in the function itself prevents it.
  **Approved**: pending
- **Decision**: cap output granularity at four buckets — just now, minutes, hours, days —
  with no week/month/year unit and no upper bound on how large the day count can grow.
  **Rationale**: not stated in source; the compact single-value format matches the
  space-constrained detail lines it feeds (`"last {ageLabel} ago"`, `"live build {age}
  old"`), where the values in practice describe recent health-check and deploy activity
  rather than long-past archival timestamps, but the source itself imposes no bound on the
  days figure.
  **Approved**: pending
- **Decision**: return the bucket value with no `"ago"` suffix or unit-name pluralization,
  leaving sentence composition entirely to the caller.
  **Rationale**: demonstrated by both call sites, which each append their own wording
  around the returned value (`"last {ageLabel} ago"` in `integrations.ts`, `"live build
  {age} old"` in `fetch-vercel-projects.ts`) rather than expecting `timeAgo` to produce a
  complete sentence; keeping the function's output caller-composed lets each caller choose
  its own surrounding wording.
  **Approved**: pending
