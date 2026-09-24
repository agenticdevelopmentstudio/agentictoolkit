---
id: ba5855cd-bd4c-49be-b7d3-4c3f7f35434e
title: Overview Projections
domain: agentictoolkit://recipes/status-web-src-lib-overview
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- agentictoolkit://recipes/status-web-src-lib-board-types
related:
- agentictoolkit://recipes/status-web-src-lib-deploy-view
- agentictoolkit://recipes/status-web-hooks-use-portfolio-indicator
references: []
approved-by: ''
approved-date: ''
---

# Overview Projections

## Overview

`overview.ts` (`packages/web/packages/status-web/src/lib/overview.ts`) holds the status dashboard's rendering projections of the server-owned `Board`. Its header comment is explicit that it derives nothing the server owns: row construction lives in `row-model.ts`, problem derivation and indicator state belong to the server's `Board`, and a row's environment tier is stamped by the server (`deployEnv` in `src/monitor/deploy-view.ts`) before the row ships. What remains here are small, pure, synchronous helpers:

- `IndicatorState` and `Indicator` — the sign / pill vocabulary (`"ok" | "warn" | "down"` plus a count).
- `indicatorFromProblems(problems)` — sign state and count over the problems a pane is showing, transcribed from the server's `indicatorFor`.
- `INDICATOR_STATE` — the one translation from the wire `Indicator` (`operational`/`degraded`/`outage`) to `IndicatorState`.
- `deployCounts(activity, sinceMs)` — build/deploy/failure tallies for the stats strip.
- `activityWindowLabel(fromMs, toMs)` — the "24h" / "7d" caption for the window the server chose.
- `headlineFor(state, count)` — the headline shared by the mobile hero sign and the desktop top-bar pill.
- `isRealEnvDeploy(d)` and `isRealEnvDeployRow(platform, environment)` — the predicate that excludes Vercel preview builds.

Callers: `OverviewTab.tsx` (`indicatorFromProblems`, `INDICATOR_STATE`), `use-portfolio-indicator.ts` (`INDICATOR_STATE`), `OverviewStats.tsx` (`deployCounts`, `activityWindowLabel`), `BigIndicator.tsx`, `BoardShell.tsx` and `WallboardStatus.tsx` (`headlineFor`), and `StatusSign.tsx` / `status-sublabel.ts` (the `IndicatorState` type). No file in `status-web` calls `isRealEnvDeploy` or `isRealEnvDeployRow` outside this module and its test; the server carries its own copy in `status-server/src/monitor/deploy-view.ts`. Types come from [Board Types](agentictoolkit://recipes/status-web-src-lib-board-types) (`ActivityRow`, `Indicator`, `Problem`) and `../types` (`DeploymentDTO`).

## Behavioral Requirements

### Types

- **indicator-state-union**: `IndicatorState` MUST be exactly the string union `"ok" | "warn" | "down"`.
- **indicator-shape**: `Indicator` MUST be an object with `state: IndicatorState` and `count: number`.

### indicatorFromProblems

- **indicator-signature**: `indicatorFromProblems` MUST take `problems: Problem[]` and MUST return an `Indicator`.
- **indicator-count**: The returned `count` MUST equal `problems.length`.
- **indicator-empty-ok**: For an empty array the function MUST return `{ state: "ok", count: 0 }`.
- **indicator-critical-down**: When at least one problem has `severity === "critical"`, the function MUST return `state: "down"`.
- **indicator-otherwise-warn**: When the array is non-empty and no problem is `"critical"` (only `"major"` and/or `"minor"`), the function MUST return `state: "warn"`.
- **indicator-server-parity**: On any problem set, `indicatorFromProblems(problems)` MUST equal `{ state: INDICATOR_STATE[indicatorFor(problems)], count: problems.length }`, where `indicatorFor` is the server rule in `status-server/src/board/derive-activity.ts`. The doc comment calls it "a rendering projection of severities the server already assigned — not a second opinion"; `board-types-parity.test.ts` pins the two on empty, minor-only, major-only and critical-bearing sets.
- **indicator-filtered-input**: The function MUST judge only the problems it is given. `OverviewTab` passes a filtered subset (`board.problems.filter(keep)`) when a filter is active and otherwise uses the server's `board.indicator` through `INDICATOR_STATE`.

### INDICATOR_STATE

- **indicator-map-values**: `INDICATOR_STATE` MUST map `operational` to `"ok"`, `degraded` to `"warn"` and `outage` to `"down"`.
- **indicator-map-exhaustive**: `INDICATOR_STATE` MUST have exactly the three keys `degraded`, `operational`, `outage` — one per member of the wire `Indicator` union, with no extras (typed as `Record<BoardIndicator, IndicatorState>` and checked by key in `board-types-parity.test.ts`).
- **indicator-map-sole-translation**: `INDICATOR_STATE` MUST be the only place that translates the wire indicator into `IndicatorState`; the doc comment names it "The ONLY translation between the two."

### deployCounts

- **counts-signature**: `deployCounts` MUST take `activity: ActivityRow[]` and `sinceMs: number` and MUST return `{ builds: number; deploys: number; failures: number }`.
- **counts-deploy-kind-only**: Rows whose `kind` is not `"deploy"` (`"probe"`, `"platform"`) MUST NOT contribute to any count.
- **counts-window-cutoff**: A deploy row whose `Date.parse(at)` is strictly less than `sinceMs` MUST NOT contribute to any count; a row exactly at `sinceMs` MUST be counted.
- **counts-builds**: Each counted row with `step === "build"` MUST add 1 to `builds`.
- **counts-deploys**: Each counted row with `step === "deploy"` MUST add 1 to `deploys`.
- **counts-null-step**: A counted row with `step === null` MUST add to neither `builds` nor `deploys`.
- **counts-failures**: Each counted row with `tone === "bad"` MUST add 1 to `failures`, independently of its `step`, so a failed build row counts as one build and one failure.
- **counts-server-window**: The caller MUST pass the board's own `activityFromMs` as `sinceMs`; the doc comment states "the client never picks the window". `OverviewStats` passes `board.activityFromMs`.
- **counts-no-rejudging**: The function MUST read `step` and `tone` as they arrive on the wire and MUST NOT recompute them.

### activityWindowLabel

- **window-signature**: `activityWindowLabel` MUST take `fromMs: number` and `toMs: number` and MUST return a string.
- **window-hours**: The function MUST compute `hours = Math.max(1, Math.round((toMs - fromMs) / 3_600_000))`.
- **window-days**: When `hours >= 48` and `hours` is a whole multiple of 24, the function MUST return `` `${hours / 24}d` `` (for example `"7d"`).
- **window-hours-label**: Otherwise the function MUST return `` `${hours}h` `` (for example `"24h"`, `"47h"`).
- **window-min-one-hour**: A window shorter than 30 minutes, zero, or negative MUST be captioned `"1h"`, never `"0h"`.
- **window-server-boundary**: The caller MUST derive both bounds from the board (`OverviewStats` passes `board.activityFromMs` and `Date.parse(board.generatedAt)`); the doc comment forbids a hardcoded caption because the server owns `ACTIVITY_WINDOW_MS`.

### headlineFor

- **headline-signature**: `headlineFor` MUST take `state: IndicatorState` and `count: number` and MUST return a string.
- **headline-ok**: For `state === "ok"` the function MUST return `"ALL SYSTEMS OPERATIONAL"`, ignoring `count`.
- **headline-warn-singular**: For `state === "warn"` and `count === 1` it MUST return `"1 SERVICE NEEDS ATTENTION"`.
- **headline-warn-plural**: For `state === "warn"` and any other count it MUST return `` `${count} SERVICES NEED ATTENTION` ``.
- **headline-down-singular**: For `state === "down"` and `count === 1` it MUST return `"1 PROBLEM"`.
- **headline-down-plural**: For `state === "down"` and any other count it MUST return `` `${count} PROBLEMS` ``.
- **headline-single-wording**: Every surface that announces the sign's headline (hero sign, top-bar pill accessible name, wallboard pill) MUST obtain it from `headlineFor`, so they cannot word it differently. The "unknown" state is outside `IndicatorState`; callers word it themselves (`BoardShell` uses `"Status unknown"`, `WallboardStatus` uses `"UNKNOWN"`).

### isRealEnvDeploy / isRealEnvDeployRow

- **real-env-row-signature**: `isRealEnvDeployRow` MUST take `platform: string` and `environment: string | null` and MUST return a boolean.
- **real-env-vercel-preview**: `isRealEnvDeployRow` MUST return `false` when `platform === "vercel"` and `environment` is `null`, `undefined` or `""`.
- **real-env-vercel-target**: `isRealEnvDeployRow` MUST return `true` when `platform === "vercel"` and `environment` is any non-empty string.
- **real-env-other-platforms**: `isRealEnvDeployRow` MUST return `true` for every platform other than the exact string `"vercel"`, whatever `environment` is (including `null`).
- **real-env-dto-delegates**: `isRealEnvDeploy(d)` MUST return `isRealEnvDeployRow(d.platform, d.environment)` for a `DeploymentDTO`.
- **real-env-case-sensitive**: The platform comparison MUST be exact and case-sensitive; `"Vercel"` is treated as a non-Vercel platform.
- **real-env-server-agreement**: The doc comment says the predicate is "Shared so the issue recorder and the UI can never disagree", but `status-server/src/monitor/deploy-view.ts` defines its own textual copy of `isRealEnvDeploy` / `isRealEnvDeployRow`, and the web copy has no caller in `status-web`. No parity test pins the two copies (unlike `indicatorFromProblems`). A port keeps one definition that the server and the UI both use.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be synchronous and pure: no I/O, no logging, no mutation of its inputs, no module state. The result depends only on the arguments.
- **no-throw**: No function throws on inputs of its declared types; malformed values degrade as described under Edge Cases rather than raising.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so calls cannot interleave and no ordering rule is needed.

## Appearance

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## States

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## Accessibility

Not applicable — this is a pure projection-and-predicate module, not a visual component.

## Conformance Test Vectors

Vectors 001–006 are traced to `overview.test.ts`; 007–010 to `board-types-parity.test.ts`; the rest to the function bodies. `H` = 3 600 000 ms. `deploy(...)` is an `ActivityRow` with `kind: "deploy"`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| overview-001 | real-env-vercel-preview, real-env-dto-delegates | `isRealEnvDeploy` of a DTO with `platform: "vercel"`, `environment: null`, `status: "failed"` | `false` |
| overview-002 | real-env-vercel-target, real-env-dto-delegates | `isRealEnvDeploy` of a DTO with `platform: "vercel"`, `environment: "production"` | `true` |
| overview-003 | real-env-other-platforms | `isRealEnvDeploy` of a DTO with `platform: "cloudflare-pages"`, `environment: null` | `true` |
| overview-004 | real-env-row-signature, real-env-vercel-preview, real-env-vercel-target, real-env-other-platforms | `isRealEnvDeployRow` with ("vercel", null), ("vercel", ""), ("vercel", "production"), ("railway", null), ("cloudflare-pages", null) | `false`, `false`, `true`, `true`, `true` |
| overview-005 | window-hours, window-hours-label, window-days | `activityWindowLabel(0, 24*H)`; `activityWindowLabel(0, 7*24*H)`; `activityWindowLabel(0, 47*H)` | `"24h"`; `"7d"`; `"47h"` |
| overview-006 | window-min-one-hour | `activityWindowLabel(0, 60000)` | `"1h"` |
| overview-007 | indicator-map-exhaustive, indicator-map-values | Sorted keys of `INDICATOR_STATE`; its values | `["degraded","operational","outage"]`; `"warn"`, `"ok"`, `"down"` |
| overview-008 | indicator-empty-ok, indicator-server-parity | `indicatorFromProblems([])` | `{ state: "ok", count: 0 }` |
| overview-009 | indicator-otherwise-warn, indicator-count | problems with severities `minor, minor`; then `major, minor` | `{ state: "warn", count: 2 }` both times |
| overview-010 | indicator-critical-down, indicator-count | problems with severities `minor, major, critical` | `{ state: "down", count: 3 }` |
| overview-011 | headline-ok | `headlineFor("ok", 5)` | `"ALL SYSTEMS OPERATIONAL"` |
| overview-012 | headline-warn-singular, headline-warn-plural | `headlineFor("warn", 1)`; `headlineFor("warn", 3)` | `"1 SERVICE NEEDS ATTENTION"`; `"3 SERVICES NEED ATTENTION"` |
| overview-013 | headline-down-singular, headline-down-plural | `headlineFor("down", 1)`; `headlineFor("down", 4)` | `"1 PROBLEM"`; `"4 PROBLEMS"` |
| overview-014 | counts-builds, counts-deploys, counts-failures | `deployCounts` over deploy rows at `sinceMs` or later: `step "build", tone "good"`; `step "build", tone "bad"`; `step "deploy", tone "good"` | `{ builds: 2, deploys: 1, failures: 1 }` |
| overview-015 | counts-deploy-kind-only, counts-window-cutoff | `deployCounts` with a `kind: "probe"` row (`tone "bad"`), a deploy row at `sinceMs - 1`, and a deploy build row exactly at `sinceMs` | `{ builds: 1, deploys: 0, failures: 0 }` |
| overview-016 | counts-null-step, counts-failures | `deployCounts` with one deploy row, `step: null`, `tone: "bad"`, inside the window | `{ builds: 0, deploys: 0, failures: 1 }` |
| overview-017 | window-days, window-hours-label | `activityWindowLabel(0, 48*H)`; `activityWindowLabel(0, 72*H)`; `activityWindowLabel(0, 24*H)` stays hours | `"2d"`; `"3d"`; `"24h"` |
| overview-018 | window-min-one-hour | `activityWindowLabel(10*H, 0)` (negative span) | `"1h"` |
| overview-019 | real-env-case-sensitive | `isRealEnvDeployRow("Vercel", null)` | `true` |

## Edge Cases

- **Empty problem list**: `indicatorFromProblems([])` MUST return `{ state: "ok", count: 0 }`. `OverviewTab` guards the case where "ok" would be a false "ALL SYSTEMS OPERATIONAL" claim; the module itself does not.
- **Unknown severity**: A problem whose `severity` is none of the typed values counts toward `count` and MUST yield `"warn"` unless another problem is `"critical"`.
- **Empty activity**: `deployCounts([], anySinceMs)` MUST return all zeros.
- **Unparseable `at`**: `Date.parse` returns `NaN`, `NaN < sinceMs` is `false`, so the row MUST be counted as inside the window. `ActivityRow.at` is documented as an ISO time supplied by the server, so this is a caller precondition, not validation the module performs.
- **`sinceMs` of `NaN`**: Every comparison is `false`, so every deploy row MUST be counted.
- **Non-integer or huge windows**: `activityWindowLabel` rounds to the nearest hour (e.g. 23.6h to `"24h"`); a whole-day multiple of 48h or more MUST switch to days, and 24h MUST stay `"24h"`.
- **`NaN` bounds**: If either bound is `NaN` (e.g. an unparseable `generatedAt` at the call site), `Math.max(1, NaN)` is `NaN` and the function MUST return `"NaNh"`; it performs no guard.
- **Negative or zero window**: `activityWindowLabel` MUST return `"1h"`.
- **`headlineFor` with count 0 and non-ok state**: MUST return `"0 SERVICES NEED ATTENTION"` or `"0 PROBLEMS"`; the function trusts the caller's pairing of state and count.
- **Negative or fractional count**: `headlineFor` MUST interpolate it verbatim with the plural form (e.g. `"-1 PROBLEMS"`).
- **Vercel environment of whitespace**: `isRealEnvDeployRow("vercel", " ")` MUST return `true`; only `null`, `undefined` and `""` count as a preview.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O; a missing or stale board is handled by its callers (`use-portfolio-indicator` maps it to `"unknown"` before `INDICATOR_STATE` is consulted).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `problems` | `Problem[]` | none (required) | The problems a pane is showing, as assigned severities by the server. |
| `activity` | `ActivityRow[]` | none (required) | The board's activity rows. |
| `sinceMs` | `number` | none (required) | Window start; the caller passes `board.activityFromMs`. |
| `fromMs` / `toMs` | `number` | none (required) | Window bounds; the caller passes `board.activityFromMs` and `Date.parse(board.generatedAt)`. |
| `state` / `count` | `IndicatorState` / `number` | none (required) | Inputs to `headlineFor`. |
| `platform` / `environment` | `string` / `string \| null` | none (required) | Deploy provider and environment target. |
| 48-hour day threshold | constant | 48 | Minimum hours before the caption switches to days, compiled in. |

The module reads no environment variables or settings keys and takes no injected dependencies. It imports only types.

## Deep Linking

Not applicable: the module exports pure functions and has no navigable surface.

## Localization

`headlineFor` returns hardcoded, uppercase English strings with no localization layer: `"ALL SYSTEMS OPERATIONAL"`, `"1 SERVICE NEEDS ATTENTION"`, `"{count} SERVICES NEED ATTENTION"`, `"1 PROBLEM"`, `"{count} PROBLEMS"`. Pluralization is a binary `count === 1` test. `activityWindowLabel` returns the English unit suffixes `h` and `d`.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal) | `ALL SYSTEMS OPERATIONAL` | Headline when state is ok |
| (none; literal) | `1 SERVICE NEEDS ATTENTION` | Headline, warn, one problem |
| (none; literal) | `{count} SERVICES NEED ATTENTION` | Headline, warn, other counts |
| (none; literal) | `1 PROBLEM` | Headline, down, one problem |
| (none; literal) | `{count} PROBLEMS` | Headline, down, other counts |
| (none; literal) | `{n}h` / `{n}d` | Activity window caption |

## Accessibility Options

Not applicable: the module renders nothing, so display options have nothing to act on. (`headlineFor` supplies the pill's accessible name, but the module does not respond to any display setting.)

## Feature Flags

Not applicable: the source reads no flag.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles problem severities, activity rows and deploy platform/environment strings; it stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls.

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum OverviewProjection`. Model `IndicatorState` as `enum IndicatorState: String { case ok, warn, down }` and `Indicator` as a `Sendable` struct. `INDICATOR_STATE` becomes a `switch` over a wire `enum BoardIndicator`, which the compiler checks for exhaustiveness. For `deployCounts`, parse `at` with `ISO8601DateFormatter` (fractional seconds); it returns `nil` rather than NaN, so decide explicitly whether a `nil` row is counted (the source counts it). Use `String(localized:)` with a plural variant if the headline is localized.
- **Compose**: Use a Kotlin `object` with an `enum class IndicatorState` and a `data class Indicator`. `INDICATOR_STATE` becomes an exhaustive `when`. `Instant.parse` throws instead of returning NaN, so wrap it to preserve the "count on unparseable" behavior. Plurals map to `pluralStringResource` if localized.
- **React/Web**: This is the source: `src/lib/overview.ts`, tested by `src/lib/overview.test.ts` and `src/lib/board-types-parity.test.ts` (the latter imports the server's `indicatorFor` from `@agentic-toolkit/status-server/activity`). Behavior leans on JavaScript specifics: `Date.parse` returning `NaN`, `NaN` comparisons being `false`, and `== null` matching both `null` and `undefined`.
- **AppKit / UIKit**: Same pure Swift port as SwiftUI, placed in a shared framework target; nothing is UI-bound.
- **WinUI 3**: Port as a `public static class OverviewProjection` in C#. `IndicatorState` becomes `public enum IndicatorState { Ok, Warn, Down }` (serialise lower-case with `JsonStringEnumConverter` and `JsonNamingPolicy.CamelCase` if it crosses `System.Text.Json`); `Indicator` becomes a `public readonly record struct Indicator(IndicatorState State, int Count)`. `INDICATOR_STATE` becomes a switch expression over a `BoardIndicator` enum, or a `FrozenDictionary<BoardIndicator, IndicatorState>`. `deployCounts` loops a `IReadOnlyList<ActivityRow>` and parses `at` with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`; a `false` result has no NaN analogue, so count the row explicitly to match the source. `activityWindowLabel` uses `Math.Round(x, MidpointRounding.AwayFromZero)` because JavaScript `Math.round` rounds .5 up while .NET defaults to banker's rounding. `isRealEnvDeployRow` uses `string.IsNullOrEmpty(environment)` and an ordinal `platform == "vercel"`. Headline strings go in `.resw` resources through `ResourceLoader` if localized. The view model binding the headline raises `INotifyPropertyChanged`; the functions stay synchronous, with no `Task`.

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

**Separation of concerns.** The module holds only presentation projections; derivation stays on the server and row construction in `row-model.ts`.

**Unit test coverage.** `overview.test.ts` covers the real-environment predicate and the window caption, and `board-types-parity.test.ts` covers `indicatorFromProblems` and `INDICATOR_STATE`. `deployCounts` and `headlineFor` have no direct tests.

**Explicit error handling.** Nothing throws, but unparseable timestamps are not guarded: an unparseable `at` is counted inside the window and a `NaN` bound yields a `"NaNh"` caption.

**Data integrity.** The indicator rule is pinned to the server by a parity test, but the real-environment predicate exists as two unpinned copies (web and server) despite a doc comment promising they cannot disagree.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from source |
