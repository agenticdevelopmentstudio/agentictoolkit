---
id: ba5855cd-bd4c-49be-b7d3-4c3f7f35434e
title: Overview Projections
domain: agentictoolkit://cookbook/status/dashboard/logic/overview
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure client projections of the server board: sign indicator, headline, deploy
  tallies, window caption and real-environment deploy predicate'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/logic/board-types
related:
- agentictoolkit://cookbook/status/dashboard/logic/deploy-view
- agentictoolkit://cookbook/status/dashboard/state/portfolio-indicator
references: []
approved-by: ''
approved-date: ''
---

# Overview Projections

## Overview

This module holds the status dashboard's rendering projections of the server-owned board. Its header comment is explicit that it derives nothing the server owns: row construction lives in a separate module, problem derivation and indicator state belong to the server's board, and a row's environment tier is stamped by the server before the row ships. What remains here are small, pure, synchronous helpers:

- the sign / pill vocabulary — a sign state (one of three values) plus a count.
- the problems-to-indicator operation — sign state and count over the problems a pane is showing, transcribed from the server's own indicator rule.
- the wire-indicator translation map — the one translation from the server's wire-level indicator vocabulary (`operational`/`degraded`/`outage`) to the sign-state vocabulary.
- the deploy-counts operation — build/deploy/failure tallies for the stats strip.
- the activity-window-caption operation — the "24h" / "7d" caption for the window the server chose.
- the headline operation — the headline shared by the mobile hero sign and the desktop top-bar pill.
- the real-environment-deploy predicate (a record form and a platform/environment form) — excludes preview builds from a specific deploy provider.

Consumers read the problems-to-indicator operation and the wire-indicator translation map for the overview tab and the portfolio indicator; the deploy-counts operation and the activity-window-caption operation for the stats strip; the headline operation for the hero sign, the top-bar pill and the wallboard pill; and the sign-state vocabulary for the status sign and its sublabel. The record form of the real-environment-deploy predicate has no caller in the client outside this module and its own test; the server carries its own copy of the same rule. Types come from Board Types (the activity row, indicator and problem shapes) and the module's own deployment-record shape.

## Behavioral Requirements

### Types

- **indicator-state-union**: The sign-state value MUST be exactly one of `"ok"`, `"warn"` or `"down"`.
- **indicator-shape**: An indicator value MUST carry a sign state and a count (a whole number).

### Problems-to-indicator operation

- **indicator-signature**: The problems-to-indicator operation MUST take a list of problems and MUST return an indicator value.
- **indicator-count**: The returned count MUST equal the number of problems given.
- **indicator-empty-ok**: For an empty list the operation MUST return sign state `"ok"` with count `0`.
- **indicator-critical-down**: When at least one problem has severity `"critical"`, the operation MUST return sign state `"down"`.
- **indicator-otherwise-warn**: When the list is non-empty and no problem has severity `"critical"` (only `"major"` and/or `"minor"`), the operation MUST return sign state `"warn"`.
- **indicator-server-parity**: On any problem set, the problems-to-indicator operation MUST produce the sign state that results from translating the server's own indicator rule through the wire-indicator translation map, with a count equal to the number of problems given. The doc comment calls it "a rendering projection of severities the server already assigned — not a second opinion"; a parity test pins the two on empty, minor-only, major-only and critical-bearing sets.
- **indicator-filtered-input**: The operation MUST judge only the problems it is given. A caller applying an active filter passes only the filtered subset of problems; otherwise a caller uses the server's own indicator, translated through the wire-indicator translation map directly.

### Wire-indicator translation map

- **indicator-map-values**: The wire-indicator translation map MUST map `operational` to `"ok"`, `degraded` to `"warn"` and `outage` to `"down"`.
- **indicator-map-exhaustive**: The wire-indicator translation map MUST have exactly the three keys `degraded`, `operational` and `outage` — one per member of the server's wire-level indicator vocabulary, with no extras.
- **indicator-map-sole-translation**: The wire-indicator translation map MUST be the only place that translates the wire indicator into a sign state; the doc comment names it "The ONLY translation between the two."

### Deploy-counts operation

- **counts-signature**: The deploy-counts operation MUST take a list of activity rows and a window-start time, and MUST return a build count, a deploy count and a failure count.
- **counts-deploy-kind-only**: Rows whose kind is not `"deploy"` (`"probe"`, `"platform"`) MUST NOT contribute to any count.
- **counts-window-cutoff**: A deploy row whose parsed timestamp is strictly earlier than the window-start time MUST NOT contribute to any count; a row exactly at the window-start time MUST be counted.
- **counts-builds**: Each counted row with step `"build"` MUST add 1 to the build count.
- **counts-deploys**: Each counted row with step `"deploy"` MUST add 1 to the deploy count.
- **counts-null-step**: A counted row with no step MUST add to neither the build count nor the deploy count.
- **counts-failures**: Each counted row with tone `"bad"` MUST add 1 to the failure count, independently of its step, so a failed build row counts as one build and one failure.
- **counts-server-window**: The caller MUST pass the board's own activity-window start as the window-start time; the doc comment states "the client never picks the window".
- **counts-no-rejudging**: The operation MUST read a row's step and tone as they arrive on the wire and MUST NOT recompute them.

### Activity-window-caption operation

- **window-signature**: The activity-window-caption operation MUST take a window-start time and a window-end time and MUST return a text caption.
- **window-hours**: The operation MUST compute the span in hours as the duration between the two times divided by 3,600,000 (milliseconds per hour), rounded to the nearest whole number, with a minimum of 1.
- **window-days**: When the hour count is 48 or more and is a whole multiple of 24, the operation MUST return the caption formed by dividing the hour count by 24 followed by the letter `d` (for example `"7d"`).
- **window-hours-label**: Otherwise the operation MUST return the caption formed by the hour count followed by the letter `h` (for example `"24h"`, `"47h"`).
- **window-min-one-hour**: A window shorter than 30 minutes, zero, or negative MUST be captioned `"1h"`, never `"0h"`.
- **window-server-boundary**: The caller MUST derive both bounds from the board's own reported activity window rather than a hardcoded span; the doc comment forbids a hardcoded caption because the server owns the window's length.

### Headline operation

- **headline-signature**: The headline operation MUST take a sign state and a count and MUST return a text headline.
- **headline-ok**: For sign state `"ok"` the operation MUST return `"ALL SYSTEMS OPERATIONAL"`, ignoring count.
- **headline-warn-singular**: For sign state `"warn"` and count `1` it MUST return `"1 SERVICE NEEDS ATTENTION"`.
- **headline-warn-plural**: For sign state `"warn"` and any other count it MUST return the count followed by `" SERVICES NEED ATTENTION"`.
- **headline-down-singular**: For sign state `"down"` and count `1` it MUST return `"1 PROBLEM"`.
- **headline-down-plural**: For sign state `"down"` and any other count it MUST return the count followed by `" PROBLEMS"`.
- **headline-single-wording**: Every surface that announces the sign's headline (hero sign, top-bar pill accessible name, wallboard pill) MUST obtain it from the headline operation, so they cannot word it differently. An "unknown" state is outside the sign-state vocabulary; callers word that case themselves (for example, showing "Status unknown" or "UNKNOWN").

### Real-environment-deploy predicate

- **real-env-row-signature**: The platform/environment form of the predicate MUST take a platform identifier and an environment value (which may be absent) and MUST return true or false.
- **real-env-vercel-preview**: The predicate MUST return `false` when the platform is `"vercel"` and the environment is absent or the empty string.
- **real-env-vercel-target**: The predicate MUST return `true` when the platform is `"vercel"` and the environment is any non-empty string.
- **real-env-other-platforms**: The predicate MUST return `true` for every platform other than the exact string `"vercel"`, whatever the environment is (including absent).
- **real-env-dto-delegates**: The record form of the predicate MUST return the same result as the platform/environment form, applied to a deployment record's own platform and environment fields.
- **real-env-case-sensitive**: The platform comparison MUST be exact and case-sensitive; `"Vercel"` is treated as a non-Vercel platform.
- **real-env-server-agreement**: The doc comment says the predicate is "Shared so the issue recorder and the UI can never disagree", but the server maintains its own textual copy of the same predicate, and the client's copy has no caller in the client outside this module's own test. No parity check pins the two copies (unlike the problems-to-indicator operation). A port keeps one definition that the server and the UI both use.

### Purity and concurrency

- **pure-functions**: Every exported operation MUST be synchronous and pure: no I/O, no logging, no mutation of its inputs, no module state. The result depends only on the arguments.
- **no-throw**: No operation throws on inputs of its declared shapes; malformed values degrade as described under Edge Cases rather than raising.
- **single-threaded**: The module holds no state, so calls cannot interleave and no ordering rule is needed.

## Appearance

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## States

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## Accessibility

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## Conformance Test Vectors

Vectors 001–006 are traced to the module's own test suite; 007–010 to a parity test suite; the rest to the operations' own bodies. `H` = 3,600,000 ms (one hour). A "deploy row" below is an activity row with kind `"deploy"`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| overview-001 | real-env-vercel-preview, real-env-dto-delegates | The record form of the predicate on a deployment record with platform `"vercel"`, environment absent, status `"failed"` | `false` |
| overview-002 | real-env-vercel-target, real-env-dto-delegates | The record form of the predicate on a deployment record with platform `"vercel"`, environment `"production"` | `true` |
| overview-003 | real-env-other-platforms | The record form of the predicate on a deployment record with platform `"cloudflare-pages"`, environment absent | `true` |
| overview-004 | real-env-row-signature, real-env-vercel-preview, real-env-vercel-target, real-env-other-platforms | The platform/environment form of the predicate on `("vercel", absent)`, `("vercel", "")`, `("vercel", "production")`, `("railway", absent)`, `("cloudflare-pages", absent)` | `false`, `false`, `true`, `true`, `true` |
| overview-005 | window-hours, window-hours-label, window-days | The activity-window-caption operation on spans of `24H`, `7×24H` and `47H`, each from time `0` | `"24h"`; `"7d"`; `"47h"` |
| overview-006 | window-min-one-hour | The activity-window-caption operation on a span of `60000` ms, from time `0` | `"1h"` |
| overview-007 | indicator-map-exhaustive, indicator-map-values | Sorted keys of the wire-indicator translation map; its values | `["degraded","operational","outage"]`; `"warn"`, `"ok"`, `"down"` |
| overview-008 | indicator-empty-ok, indicator-server-parity | The problems-to-indicator operation on an empty list | sign state `"ok"`, count `0` |
| overview-009 | indicator-otherwise-warn, indicator-count | The operation on problems with severities `minor, minor`; then `major, minor` | sign state `"warn"`, count `2`, both times |
| overview-010 | indicator-critical-down, indicator-count | The operation on problems with severities `minor, major, critical` | sign state `"down"`, count `3` |
| overview-011 | headline-ok | The headline operation with sign state `"ok"` and count `5` | `"ALL SYSTEMS OPERATIONAL"` |
| overview-012 | headline-warn-singular, headline-warn-plural | The headline operation with sign state `"warn"` and count `1`; then count `3` | `"1 SERVICE NEEDS ATTENTION"`; `"3 SERVICES NEED ATTENTION"` |
| overview-013 | headline-down-singular, headline-down-plural | The headline operation with sign state `"down"` and count `1`; then count `4` | `"1 PROBLEM"`; `"4 PROBLEMS"` |
| overview-014 | counts-builds, counts-deploys, counts-failures | The deploy-counts operation over deploy rows at the window-start time or later: step `"build"`/tone `"good"`; step `"build"`/tone `"bad"`; step `"deploy"`/tone `"good"` | build count `2`, deploy count `1`, failure count `1` |
| overview-015 | counts-deploy-kind-only, counts-window-cutoff | The operation with a probe-kind row (tone `"bad"`), a deploy row one millisecond before the window-start time, and a deploy build row exactly at the window-start time | build count `1`, deploy count `0`, failure count `0` |
| overview-016 | counts-null-step, counts-failures | The operation with one deploy row, no step, tone `"bad"`, inside the window | build count `0`, deploy count `0`, failure count `1` |
| overview-017 | window-days, window-hours-label | The caption operation on spans of `48H`, `72H` and `24H`, each from time `0` | `"2d"`; `"3d"`; `"24h"` (stays hours) |
| overview-018 | window-min-one-hour | The caption operation from time `10H` to time `0` (a negative span) | `"1h"` |
| overview-019 | real-env-case-sensitive | The platform/environment form of the predicate on `("Vercel", absent)` | `true` |

## Edge Cases

- **Empty problem list**: The problems-to-indicator operation on an empty list MUST return sign state `"ok"`, count `0`. A caller guards the case where "ok" would be a false "ALL SYSTEMS OPERATIONAL" claim (for example, no data yet loaded); the module itself does not.
- **Unknown severity**: A problem whose severity is none of the recognized values counts toward the count and MUST yield `"warn"` unless another problem has severity `"critical"`.
- **Empty activity**: The deploy-counts operation on an empty list, for any window-start time, MUST return all counts as zero.
- **Unparseable time stamp**: An unparseable row time stamp is treated as no less than the window-start time (an invalid-time comparison is never true), so the row MUST be counted as inside the window. A row's time field is documented as an ISO-8601 time supplied by the server, so this is a caller precondition, not validation the module performs.
- **Invalid window-start time**: If the window-start time itself is invalid, every comparison against it is false, so every deploy row MUST be counted.
- **Non-integer or huge windows**: The activity-window-caption operation rounds to the nearest hour (for example 23.6h to `"24h"`); a whole-day multiple of 48h or more MUST switch to days, and 24h MUST stay `"24h"`.
- **Invalid bounds**: If either bound given to the caption operation is invalid (for example from an unparseable time stamp upstream), the reference implementation performs no guard and returns the caption `"NaNh"`; a port whose numeric type has no equivalent invalid-number propagation should pick its own fallback (see Platform Notes).
- **Negative or zero window**: The activity-window-caption operation MUST return `"1h"`.
- **Headline with count 0 and a non-ok state**: The headline operation MUST return `"0 SERVICES NEED ATTENTION"` or `"0 PROBLEMS"`; the operation trusts the caller's pairing of state and count.
- **Negative or fractional count**: The headline operation MUST interpolate it verbatim with the plural form (for example `"-1 PROBLEMS"`).
- **Vercel environment of whitespace**: The platform/environment form of the predicate on platform `"vercel"` and environment `" "` (a single space) MUST return `true`; only an absent environment or the empty string count as a preview.
- **Concurrent access**: Not applicable. The module is stateless, so calls cannot interleave.
- **Error states and offline**: Not applicable. The module performs no I/O; a missing or stale board is handled by its callers, which map it to an "unknown" state before the wire-indicator translation map is consulted.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `problems` | a list of problems | none (required) | The problems a pane is showing, as assigned severities by the server. |
| `activity` | a list of activity rows | none (required) | The board's activity rows. |
| `sinceMs` | a number | none (required) | Window-start time; the caller passes the board's own activity-window start. |
| `fromMs` / `toMs` | a number | none (required) | Window bounds; the caller passes the board's own reported window start and end. |
| `state` / `count` | a sign state / a number | none (required) | Inputs to the headline operation. |
| `platform` / `environment` | a text value / a text value or absent | none (required) | Deploy provider and environment target. |
| 48-hour day threshold | constant | 48 | Minimum hours before the caption switches to days, compiled in. |

The module reads no environment variables or settings keys and takes no injected dependencies. It imports only shapes/types from elsewhere.

## Deep Linking

Not applicable: the module exports pure operations and has no navigable surface.

## Localization

The headline operation returns hardcoded, uppercase English strings with no localization layer: `"ALL SYSTEMS OPERATIONAL"`, `"1 SERVICE NEEDS ATTENTION"`, `"{count} SERVICES NEED ATTENTION"`, `"1 PROBLEM"`, `"{count} PROBLEMS"`. Pluralization is a binary count-equals-one test. The activity-window-caption operation returns the English unit suffixes `h` and `d`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `ALL SYSTEMS OPERATIONAL` | Headline when state is ok |
| (none; literal) | `1 SERVICE NEEDS ATTENTION` | Headline, warn, one problem |
| (none; literal) | `{count} SERVICES NEED ATTENTION` | Headline, warn, other counts |
| (none; literal) | `1 PROBLEM` | Headline, down, one problem |
| (none; literal) | `{count} PROBLEMS` | Headline, down, other counts |
| (none; literal) | `{n}h` / `{n}d` | Activity window caption |

## Accessibility Options

Not applicable: the module renders nothing, so display options have nothing to act on. (The headline operation supplies the pill's accessible name, but the module does not respond to any display setting.)

## Feature Flags

Not applicable: the source reads no flag.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles problem severities, activity rows and deploy platform/environment strings; it stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum OverviewProjection`. Model the sign-state vocabulary as `enum IndicatorState: String { case ok, warn, down }` and the indicator shape as a `Sendable` struct. The wire-indicator translation map becomes a `switch` over a wire `enum BoardIndicator`, which the compiler checks for exhaustiveness. For the deploy-counts operation, parse the row time with `ISO8601DateFormatter` (fractional seconds); it returns `nil` rather than NaN, so decide explicitly whether a `nil` row is counted (the reference implementation counts it). Use `String(localized:)` with a plural variant if the headline is localized.
- **Compose**: Use a Kotlin `object` with an `enum class IndicatorState` and a `data class Indicator`. The wire-indicator translation map becomes an exhaustive `when`. `Instant.parse` throws instead of returning NaN, so wrap it to preserve the "count on unparseable" behavior. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/overview.ts`, tested by `src/lib/overview.test.ts` and `src/lib/board-types-parity.test.ts` (the latter imports the server's `indicatorFor` from `@agentic-toolkit/status-server/activity`). `IndicatorState`, `Indicator` and the wire `Indicator` union are TypeScript types; `INDICATOR_STATE` is typed `Record<BoardIndicator, IndicatorState>`, so a compile error catches a member removed from the wire union without a matching map key, or vice versa — the same guarantee the parity test's key check backs at runtime. `deployCounts`'s window cutoff and the caption's bounds check both lean on `Date.parse` returning `NaN` for an unparseable string and `NaN` comparisons always being `false`; the caption's hour computation is `Math.max(1, Math.round((toMs - fromMs) / 3_600_000))`, and an invalid `toMs`/`fromMs` propagates to the caption `"NaNh"` because template-literal interpolation of `NaN` is the string `"NaN"`. `isRealEnvDeployRow`'s preview check treats `null`, `undefined` and `""` alike with `environment == null || environment === ""`. Callers: `OverviewTab.tsx` (`indicatorFromProblems`, `INDICATOR_STATE`), `use-portfolio-indicator.ts` (`INDICATOR_STATE`, and its own fallback to an "unknown" state for a missing board), `OverviewStats.tsx` (`deployCounts`, `activityWindowLabel`, passing `board.activityFromMs` and `Date.parse(board.generatedAt)`), `BigIndicator.tsx`, `BoardShell.tsx` (`headlineFor`, wording its own "unknown" state as `"Status unknown"`) and `WallboardStatus.tsx` (`headlineFor`, wording its own "unknown" state as `"UNKNOWN"`), and `StatusSign.tsx` / `status-sublabel.ts` (the `IndicatorState` type). `isRealEnvDeploy`/`isRealEnvDeployRow` have no caller in `status-web` outside this module's own test; the server carries its own textual copy in `status-server/src/monitor/deploy-view.ts`, whose `ACTIVITY_WINDOW_MS` is the server's window-length constant referenced by the window-caption contract. The module holds no state and runs on the single JavaScript thread, so calls cannot interleave.
- **AppKit / UIKit**: Same pure Swift port as SwiftUI, placed in a shared framework target; nothing is UI-bound.
- **WinUI 3**: Port as a `public static class OverviewProjection` in C#. The sign-state vocabulary becomes `public enum IndicatorState { Ok, Warn, Down }` (serialise lower-case with `JsonStringEnumConverter` and `JsonNamingPolicy.CamelCase` if it crosses `System.Text.Json`); the indicator shape becomes a `public readonly record struct Indicator(IndicatorState State, int Count)`. The wire-indicator translation map becomes a switch expression over a `BoardIndicator` enum, or a `FrozenDictionary<BoardIndicator, IndicatorState>`. The deploy-counts operation loops a `IReadOnlyList<ActivityRow>` and parses the row time with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`; a `false` result has no NaN analogue, so count the row explicitly to match the reference implementation. The caption operation uses `Math.Round(x, MidpointRounding.AwayFromZero)` because the reference implementation's rounding rounds .5 up while .NET defaults to banker's rounding. The predicate uses `string.IsNullOrEmpty(environment)` and an ordinal `platform == "vercel"`. Headline strings go in `.resw` resources through `ResourceLoader` if localized. The view model binding the headline raises `INotifyPropertyChanged`; the operations stay synchronous, with no `Task`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/overview.ts` |

## Design Decisions

**Decision**: The client mirrors the server's indicator rule instead of computing its own.
**Rationale**: The doc comment calls `indicatorFromProblems` a rendering projection, "not a second opinion about what a problem is". It exists only because a filtered pane needs the rule over a subset; `board-types-parity.test.ts` pins it to the server's `indicatorFor` so it cannot drift again.
**Approved**: pending

**Decision**: `INDICATOR_STATE` is the single wire-to-sign translation.
**Rationale**: One typed `Record<BoardIndicator, IndicatorState>` is exhaustive at compile time, and a key test catches a member removed from both union and map together.
**Approved**: pending

**Decision**: Derive the window caption from the board's own bounds instead of hardcoding "24h".
**Rationale**: The server owns `ACTIVITY_WINDOW_MS`; a hardcoded caption would keep stating the old figure after a server change, "a label that lies without anything failing". Days are used only for whole-day windows of 48h or more, so 47h is never rounded to a window nobody configured.
**Approved**: pending

**Decision**: Tally deploy counts on the client.
**Rationale**: The doc comment allows it because the counts are a tally of rows the server already judged: `step` and `tone` arrive on the wire and the window start is the board's `activityFromMs`.
**Approved**: pending

**Decision**: One `headlineFor` shared by the hero sign and the top-bar pill.
**Rationale**: Sharing the function makes it impossible for the two surfaces to word the same state differently.
**Approved**: pending

**Decision**: Treat Vercel deploys with no environment target as preview builds and exclude them.
**Rationale**: Vercel previews report `environment=null`; they are CI artifacts, and counting a failed preview as "deploy failed" under the project's prod/staging label was a real false positive. The duplicated server copy is described under real-env-server-agreement.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

**Separation of concerns.** The module holds only presentation projections; derivation stays on the server and row construction in a separate module.

**Unit test coverage.** The module's own test suite covers the real-environment predicate and the window caption, and a parity test suite covers the problems-to-indicator operation and the wire-indicator translation map. The deploy-counts operation and the headline operation have no direct tests.

**Explicit error handling.** Nothing throws, but unparseable timestamps are not guarded: an unparseable time stamp is counted inside the window and an invalid bound yields a `"NaNh"` caption.

**Data integrity.** The indicator rule is pinned to the server by a parity test, but the real-environment predicate exists as two unpinned copies (web and server) despite a doc comment promising they cannot disagree.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
