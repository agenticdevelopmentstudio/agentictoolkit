---
id: 839f5416-d1e3-43fb-91a0-4829abdff427
title: Status Server Monitor Time Ago
domain: agentictoolkit://cookbook/status-server/monitor/time-ago
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure, synchronous function turning an ISO timestamp and a caller-supplied
  clock reading into a compact just-now/m/h/d elapsed-time label.
platforms:
- typescript
- web
tags:
- monitor
- formatting
- pure-function
- server
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/monitor/time-ago.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/integrations.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-vercel-projects.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a time-elapsed formatting function, not a visual component.

## States

Not applicable — this is a time-elapsed formatting function, not a visual component; it
holds no runtime state of its own to enumerate.

## Accessibility

Not applicable — this is a time-elapsed formatting function, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-time-ago-001 | just-now-bucket | `timeAgo(iso, nowMs)` where `nowMs - new Date(iso).getTime() = 0` ms | Resolves `'just now'` — traced to `diffSecs < 60`; the given source tree has no dedicated test file for `timeAgo`, so every vector below is derived by reading `time-ago.ts` directly |
| status-server-monitor-time-ago-002 | just-now-bucket | `nowMs` set so `diffSecs = 59` | Resolves `'just now'` — the upper edge of the just-now bucket |
| status-server-monitor-time-ago-003 | minutes-bucket, bucket-evaluation-order | `nowMs` set so `diffSecs = 60` (`diffMins = 1`) | Resolves `'1m'` — the just-now/minutes boundary |
| status-server-monitor-time-ago-004 | minutes-bucket | `nowMs` set so `diffSecs = 3599` (`diffMins = 59`) | Resolves `'59m'` — the upper edge of the minutes bucket |
| status-server-monitor-time-ago-005 | hours-bucket, bucket-evaluation-order | `nowMs` set so `diffSecs = 3600` (`diffMins = 60`, `diffHours = 1`) | Resolves `'1h'` — the minutes/hours boundary |
| status-server-monitor-time-ago-006 | hours-bucket | `nowMs` set so `diffHours = 23` | Resolves `'23h'` — the upper edge of the hours bucket |
| status-server-monitor-time-ago-007 | days-bucket, bucket-evaluation-order | `nowMs` set so `diffHours = 24` | Resolves `'1d'` — the hours/days boundary |
| status-server-monitor-time-ago-008 | days-bucket | `nowMs` set so `diffHours = 240` (10 days) | Resolves `'10d'` — demonstrates the days bucket's lack of a week/month/year rollover |
| status-server-monitor-time-ago-009 | just-now-bucket | `iso` set 5 minutes after `nowMs` (`diffSecs = -300`) | Resolves `'just now'` — traced to the unconditional `diffSecs < 60` comparison, which is also true for every negative value |
| status-server-monitor-time-ago-010 | no-iso-validation | `timeAgo('not-a-date', Date.now())` | Resolves the literal string `'NaNd'` — traced to `new Date('not-a-date').getTime()` returning `NaN`, which propagates through every comparison as `false` until the final branch; per `no-iso-validation` |
| status-server-monitor-time-ago-011 | synchronous-purity, no-throw-on-well-formed-input | Call `timeAgo` for every input in vectors 001–010 with global `Date.now`, `console.*`, and `fetch` spied | Zero recorded calls on any spy across all eleven calls; none of the eleven calls throws |

## Edge Cases

- **Null and empty input**: `iso` and `nowMs` are both declared as required, non-optional
  parameters (`string` and `number`); the source performs no runtime check for `null`,
  `undefined`, or an empty string on either. Passing `iso: ''` produces
  `new Date('').getTime()`, which is `NaN`, taking the same `NaN`-propagation path
  described under `no-iso-validation` — the function falls through to the days bucket and
  returns `'NaNd'` — MUST (see `no-iso-validation`).
- **Boundary values**: at `diffSecs = 59` the result is `'just now'`; at `diffSecs = 60` it
  is `'1m'` — MUST. At `diffMins = 59` the result is `'59m'`; at `diffMins = 60` it is
  `'1h'` — MUST. At `diffHours = 23` the result is `'23h'`; at `diffHours = 24` it is
  `'1d'` — MUST. There is no upper boundary on the days bucket: an elapsed time of, for
  example, 3650 days returns `'3650d'` unchanged, with no rollover to a larger unit — MUST.
- **Concurrent access**: not a synchronization concern by construction — `timeAgo` is a
  pure, synchronous function that reads only its own two arguments and holds no
  module-level or shared mutable state, so any number of concurrent callers may call it in
  any order or in parallel with no possibility of interleaved corruption — MUST.
- **Error states**: `timeAgo` has no dependency (network, database, file system) that can
  fail, and it never throws for any input reachable through its declared parameter types.
  A malformed `iso` does not raise an error; instead it silently produces the incorrect
  string `'NaNd'`, per `no-iso-validation` — MUST.
  Validating `iso` is the caller's job.
- **Offline / disconnected state**: not applicable — this file issues no network call and
  has no connectivity of its own to lose. Both call sites (`integrations.ts`,
  `fetch-vercel-projects.ts`) already hold their own timestamp — from local storage or an
  already-fetched deploy record — before calling `timeAgo`, so a caller's own network
  reachability is entirely external to this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `iso` | `string` | none — required positional argument | ISO-8601 timestamp string of the event being measured; passed to `new Date(iso).getTime()` with no validation of its format. |
| `nowMs` | `number` | none — required positional argument | The caller-supplied "current time" in epoch milliseconds, against which `iso` is compared; per the source's own doc comment, this is passed in rather than read from `Date.now()` internally "for testability." |

## Deep Linking

Not applicable: `timeAgo` is a pure formatting function with no application route, URL, or
deep-link target of any kind.

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

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion,
Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: `timeAgo` consults no feature-flag system; it is unconditionally available
with no flag gating any part of its behavior.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: `timeAgo` receives only a timestamp (`iso`) and a caller-supplied clock
reading (`nowMs`) as plain arguments — infrastructure event metadata, not end-user or
credential data — collects, stores, and transmits nothing of its own, and returns a
formatted string with no persistence.

## Logging

This file contains no logging or console call of any kind; `timeAgo` is a pure synchronous
function with no side effects of its own.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log line at any level; `timeAgo` produces no observable output beyond its own return value. |

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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/time-ago.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `failed`: the given source tree contains no dedicated test file for
`time-ago.ts`, and neither of its two callers' test files (`integrations-retry.test.ts`,
`vercel-conclusive-backfill.test.ts`, `vercel-deploys-pagination.test.ts`) asserts on the
`ageLabel`/`age`/`detail` string values that `timeAgo` produces — every requirement above
is derived from reading `time-ago.ts` directly, with zero passing assertions behind it.
`separation-of-concerns` passes: this file's only responsibility is elapsed-time
formatting; it performs no I/O, no persistence, and no HTTP work of its own, leaving
timestamp collection to its callers. `explicit-error-handling` is `failed`: a malformed
`iso` produces an implicit error state (`NaN`, propagated silently through every
comparison) that the function never checks for or handles explicitly — it is not caught,
not validated, and not surfaced to the caller, per
`no-iso-validation`. `fault-tolerance` passes: `timeAgo` never throws or crashes for any
input reachable through its declared parameter types, including the malformed-`iso` case;
it degrades to an incorrect but non-crashing string rather than raising an exception.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 |  |  | Initial creation |
