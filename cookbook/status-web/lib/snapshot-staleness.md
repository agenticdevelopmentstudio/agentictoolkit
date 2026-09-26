---
id: ac044c52-64bb-4e4f-b0d8-56dd88ab7d47
title: Snapshot Staleness
domain: agentictoolkit://cookbook/status-web/lib/snapshot-staleness
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure server-clock rule grading the live snapshot as fresh, stale or very-stale
  from its newest probe lag
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/lib/board-staleness
- agentictoolkit://cookbook/status-web/hooks/use-portfolio-indicator
- agentictoolkit://cookbook/status-web/hooks/use-live-snapshot
references: []
approved-by: ''
approved-date: ''
---

# Snapshot Staleness

## Overview

`snapshot-staleness.ts` (`packages/web/packages/status-web/src/lib/snapshot-staleness.ts`) is the status dashboard's single staleness rule for the live snapshot: "how stale the displayed status data is". It exports a three-valued `SnapshotFreshness` type, the constant `SNAPSHOT_STALE_FLOOR_MS`, the window function `snapshotStaleMs`, and the verdict function `snapshotFreshness`.

The doc comment calls it "the ONE staleness rule". It is shared by the board-wide `SnapshotStaleBanner` component and the [usePortfolioIndicator](agentictoolkit://cookbook/status-web/hooks/use-portfolio-indicator) hook, so the banner and the header/home status sign can never disagree. Both callers read `lastCycleAt`, `generatedAt` and `probeIntervalMs` off the snapshot held by [useLiveSnapshot](agentictoolkit://cookbook/status-web/hooks/use-live-snapshot). The sibling [Board Staleness](agentictoolkit://cookbook/status-web/lib/board-staleness) module derives its data-clock window from `snapshotStaleMs`.

The lag is measured server clock against server clock: the snapshot's `generatedAt` (stamped at read time) minus its newest persisted probe `lastCycleAt`. The window mirrors the backend scheduler's `staleAfterMs` (`max(interval×5, 5min)` in `status-server/src/scheduler.ts`). The module has no state, no I/O and no side effects.

## Behavioral Requirements

### Types and constants

- **freshness-type**: `SnapshotFreshness` MUST be the string union `"fresh" | "stale" | "very-stale"`.
- **stale-floor**: `SNAPSHOT_STALE_FLOOR_MS` MUST equal 300 000 ms (`5 * 60_000`). It is both the window floor and the window used when the backend reports no interval (an older backend that predates the `probeIntervalMs` field).

### snapshotStaleMs

- **window-signature**: `snapshotStaleMs` MUST take an optional `probeIntervalMs?: number | null` and MUST return a number of milliseconds.
- **window-formula**: `snapshotStaleMs` MUST return `Math.max((probeIntervalMs ?? 0) * 5, SNAPSHOT_STALE_FLOOR_MS)`.
- **window-unknown-interval**: `snapshotStaleMs` MUST return 300 000 when `probeIntervalMs` is `undefined` or `null`.
- **window-small-interval**: `snapshotStaleMs` MUST return 300 000 for any `probeIntervalMs` at or below 60 000 (including `0` and negative values), because five times it does not exceed the floor.
- **window-scaling**: `snapshotStaleMs` MUST return exactly `probeIntervalMs * 5` for any `probeIntervalMs` above 60 000, with no upper cap.
- **window-mirrors-scheduler**: The window formula MUST stay identical to the backend scheduler's default `staleAfterMs` (`Math.max(intervalMs * 5, 300_000)`), so a raised `PROBE_INTERVAL_SECONDS` does not make one skipped cycle trip the verdict. The backend value is owned by `status-server/src/scheduler.ts`; this module duplicates the formula rather than importing it.

### snapshotFreshness

- **freshness-signature**: `snapshotFreshness` MUST take `lastCycleAt: string | null | undefined`, `generatedAt: string | null | undefined` and an optional `probeIntervalMs?: number | null`, and MUST return a `SnapshotFreshness`.
- **missing-last-cycle**: `snapshotFreshness` MUST return `"fresh"` when `lastCycleAt` is `null`, `undefined` or the empty string, before parsing either timestamp. Per the source comment this is "no probe yet (zero-endpoint monitor)": nothing to judge, so no alarm.
- **missing-generated-at**: `snapshotFreshness` MUST return `"fresh"` when `generatedAt` is `null`, `undefined` or the empty string ("no read clock").
- **lag-computation**: `snapshotFreshness` MUST compute the lag as `Date.parse(generatedAt) - Date.parse(lastCycleAt)`.
- **server-clock-only**: `snapshotFreshness` MUST NOT read the client clock (`Date.now()` or a timer). Its verdict depends only on its arguments, which makes it immune to client clock skew and to throttled timers in a sleeping tab.
- **fresh-at-or-below-window**: `snapshotFreshness` MUST return `"fresh"` when the lag is less than or equal to `snapshotStaleMs(probeIntervalMs)`. The comparison is strict, so a lag exactly equal to the window is fresh.
- **negative-lag-fresh**: `snapshotFreshness` MUST return `"fresh"` when the lag is negative (the probe timestamp is newer than the read clock). The function applies no lower bound.
- **nan-fails-open**: `snapshotFreshness` MUST return `"fresh"` when the lag is `NaN`, which happens when either timestamp is unparseable. The source tests `!(ageMs > staleMs)` rather than `ageMs <= staleMs` precisely so a `NaN` comparison falls through to `"fresh"` instead of showing a banner.
- **stale-band**: `snapshotFreshness` MUST return `"stale"` when the lag is strictly greater than the window and less than or equal to three times the window.
- **very-stale-band**: `snapshotFreshness` MUST return `"very-stale"` when the lag is strictly greater than three times the window.
- **not-cycle-health**: `snapshotFreshness` judges only the freshness of the newest persisted probe. It MUST NOT be used as the scheduler's cycle-completion health, which the backend reports separately at `/health`. The doc comment notes a downstream cycle stage can hang after probes were written while the on-screen data is still current.

### Caller contract

- **caller-banner-tone**: A caller that renders a banner MUST map `"stale"` to the amber tone and `"very-stale"` to the red tone, and render nothing for `"fresh"`. This is how `SnapshotStaleBanner` consumes the verdict.
- **caller-indicator-unknown**: A caller that renders an overall status sign MUST treat any verdict other than `"fresh"` as "cannot back a confident status claim". `usePortfolioIndicator` folds it into its unknown state.
- **refresh-by-repoll**: The verdict only grows while the poller is wedged because the client re-pulls `/live` on its own interval and each fresh snapshot re-stamps `generatedAt`, while `lastCycleAt` stays frozen. The module itself MUST NOT schedule anything; re-evaluation is the caller's job on each new snapshot.

### Purity and concurrency

- **pure-functions**: Both exported functions MUST be pure and synchronous. They MUST NOT perform I/O, log, throw on any input of the declared types, or mutate state.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so concurrent calls cannot interleave and it needs no ordering rule.

## Appearance

Not applicable — this is a pure staleness-rule module, not a visual component.

## States

Not applicable — this is a pure staleness-rule module, not a visual component.

## Accessibility

Not applicable — this is a pure staleness-rule module, not a visual component.

## Conformance Test Vectors

All vectors use `GEN = "2024-06-01T12:00:00.000Z"` and `lag(ms)` = the ISO string `ms` milliseconds before `GEN`. Vectors 001 to 013 are traced to the assertions in `snapshot-staleness.test.ts`. Vectors 014 to 018 are traced to the function bodies (strict comparisons, the `?? 0` fallback and the falsy guard).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| snapshot-staleness-001 | window-unknown-interval, stale-floor | `snapshotStaleMs(undefined)`; `snapshotStaleMs(null)` | 300 000 for both |
| snapshot-staleness-002 | window-small-interval | `snapshotStaleMs(60000)` | 300 000 |
| snapshot-staleness-003 | window-scaling, window-formula | `snapshotStaleMs(120000)` | 600 000 |
| snapshot-staleness-004 | missing-last-cycle | `snapshotFreshness(null, GEN, 60000)`; `snapshotFreshness(undefined, GEN)` | `"fresh"` for both |
| snapshot-staleness-005 | missing-generated-at | `snapshotFreshness(lag(600000), null)` | `"fresh"` |
| snapshot-staleness-006 | fresh-at-or-below-window, lag-computation | `snapshotFreshness(lag(240000), GEN, 60000)` | `"fresh"` |
| snapshot-staleness-007 | stale-band | `snapshotFreshness(lag(360000), GEN, 60000)` | `"stale"` |
| snapshot-staleness-008 | very-stale-band | `snapshotFreshness(lag(960000), GEN, 60000)` | `"very-stale"` |
| snapshot-staleness-009 | window-scaling, fresh-at-or-below-window | `snapshotFreshness(lag(360000), GEN, 120000)` | `"fresh"` |
| snapshot-staleness-010 | window-scaling, stale-band | `snapshotFreshness(lag(660000), GEN, 120000)` | `"stale"` |
| snapshot-staleness-011 | nan-fails-open | `snapshotFreshness("not-a-date", GEN, 60000)` | `"fresh"` |
| snapshot-staleness-012 | nan-fails-open | `snapshotFreshness(lag(1200000), "not-a-date", 60000)` | `"fresh"` |
| snapshot-staleness-013 | negative-lag-fresh | `snapshotFreshness` with lastCycleAt = GEN plus 30 000 ms, `GEN`, `60000` | `"fresh"` |
| snapshot-staleness-014 | fresh-at-or-below-window | `snapshotFreshness(lag(300000), GEN, 60000)` (lag exactly the window) | `"fresh"` |
| snapshot-staleness-015 | stale-band | `snapshotFreshness(lag(900000), GEN, 60000)` (lag exactly three times the window) | `"stale"` |
| snapshot-staleness-016 | very-stale-band | `snapshotFreshness(lag(900001), GEN, 60000)` | `"very-stale"` |
| snapshot-staleness-017 | missing-last-cycle | `snapshotFreshness("", GEN, 60000)` | `"fresh"` |
| snapshot-staleness-018 | window-small-interval | `snapshotStaleMs(0)`; `snapshotStaleMs(-1000)` | 300 000 for both |
| snapshot-staleness-019 | server-clock-only | `snapshotFreshness(lag(360000), GEN, 60000)` evaluated with the system clock set one day ahead | `"stale"` (unchanged) |
| snapshot-staleness-020 | freshness-type | Every return value across vectors 004 to 017 | One of `"fresh"`, `"stale"`, `"very-stale"` |

## Edge Cases

- **Null, undefined or empty `lastCycleAt`**: MUST return `"fresh"`. A zero-endpoint monitor, or an older backend that predates the field, never shows the banner.
- **Null, undefined or empty `generatedAt`**: MUST return `"fresh"`.
- **Unparseable timestamp**: `Date.parse` yields `NaN`, every comparison is false, and the result MUST be `"fresh"` (fail open). This deliberately differs from `board-staleness.ts`, which fails closed.
- **Lag exactly equal to the window**: MUST be `"fresh"`; the comparison is strict greater-than.
- **Lag exactly equal to three times the window**: MUST be `"stale"`, not `"very-stale"`.
- **Negative lag (probe newer than read clock)**: MUST be `"fresh"`; there is no lower bound.
- **`probeIntervalMs` of `0` or negative**: The window MUST floor to 300 000 ms through `Math.max`.
- **`probeIntervalMs` of `NaN`**: `NaN * 5` is `NaN` and `Math.max` returns `NaN`, so the window is `NaN` and `snapshotFreshness` MUST return `"fresh"` for every lag. The declared type is `number | null`, and the value comes from the backend snapshot; this module does not validate it.
- **Very large or infinite `probeIntervalMs`**: The window MUST scale linearly as `probeIntervalMs * 5` with no cap. An infinite interval yields an infinite window, so the verdict is always `"fresh"`.
- **Client clock skew or a sleeping tab**: MUST NOT affect the verdict; the client clock is never read.
- **Wedged poller**: Each re-pulled snapshot carries a newer `generatedAt` while `lastCycleAt` stays frozen, so the lag MUST keep growing and escalate from `"fresh"` to `"stale"` to `"very-stale"` across re-polls.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O. A `/live` feed that stops arriving leaves the caller holding the last snapshot, whose lag this module cannot see growing; detecting a feed that has stopped arriving belongs to `isBoardStale` in `board-staleness.ts` and to the live transport.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `lastCycleAt` | `string \| null \| undefined` (ISO 8601) | none (required argument) | Server-clock time of the newest persisted probe. Missing means no probe yet. |
| `generatedAt` | `string \| null \| undefined` (ISO 8601) | none (required argument) | Server-clock time the snapshot was read, re-stamped on every read. |
| `probeIntervalMs` | `number \| null \| undefined` | `undefined`, which gives the 300 000 ms window | The backend's probe interval (derived from `PROBE_INTERVAL_SECONDS` on the server), read off the snapshot. |
| `SNAPSHOT_STALE_FLOOR_MS` | constant | 300 000 | Window floor, compiled in. |
| Very-stale multiplier | literal | 3 | Hardcoded in `snapshotFreshness`; not exported. |
| Window multiplier | literal | 5 | Hardcoded in `snapshotStaleMs`; not exported. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. It has no imports.

## Deep Linking

Not applicable: the module exports pure functions and a constant and has no navigable surface.

## Localization

Not applicable: the module returns fixed string-union tokens (`"fresh"`, `"stale"`, `"very-stale"`), not user-facing text; the banner copy lives in `SnapshotStaleBanner`.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and the rule always applies.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only two timestamps and a probe interval, and stores or transmits nothing.

## Logging

Not applicable: the module makes no log calls; its verdict reaches the user through the caller's banner or status sign.

## Platform Notes

- **SwiftUI**: Port as a caseless `enum SnapshotStaleness` namespace with `static let staleFloorMs: Int64 = 300_000` and `enum SnapshotFreshness: String { case fresh, stale, veryStale = "very-stale" }`. Parse with `ISO8601DateFormatter` (add `.withFractionalSeconds`). A failed parse returns `nil` rather than NaN, so map `nil` explicitly to `.fresh` to keep the fail-open rule. Take `lastCycleAt`/`generatedAt` as `String?` so the missing-input guard is a plain optional check.
- **Compose**: Use a Kotlin `object SnapshotStaleness` with `const val STALE_FLOOR_MS = 300_000L` and `enum class SnapshotFreshness`. `Instant.parse` throws `DateTimeParseException`, so catch it and return `FRESH`. Use `maxOf((probeIntervalMs ?: 0L) * 5, STALE_FLOOR_MS)` for the window. Note that Kotlin `Long` has no NaN, so the NaN-interval edge case disappears.
- **React/Web**: This is the source: `src/lib/snapshot-staleness.ts`, exercised by `src/lib/snapshot-staleness.test.ts` (vitest). Consumed by `src/components/SnapshotStaleBanner.tsx` and `src/hooks/use-portfolio-indicator.ts`, and reused by `src/lib/board-staleness.ts`. The fail-open behavior relies on `Date.parse` returning `NaN` and the negated comparison `!(ageMs > staleMs)`.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port, placed in a shared framework target since nothing is UI-bound. The banner equivalent re-evaluates whenever the live snapshot model publishes a new value; no `Timer` is needed because the rule never reads the client clock.
- **WinUI 3**: Port as a `public static class SnapshotStaleness` in C# with `public const long StaleFloorMs = 5 * 60_000;`, `public static long StaleMs(long? probeIntervalMs) => Math.Max((probeIntervalMs ?? 0) * 5, StaleFloorMs);`, and `public enum SnapshotFreshness { Fresh, Stale, VeryStale }` (add `[JsonStringEnumMemberName("very-stale")]` if it crosses `System.Text.Json`). Parse each timestamp with `DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`; since .NET has no NaN parse result, a `false` return must map to `Fresh` to preserve the fail-open rule. Compute the lag with `ToUnixTimeMilliseconds()` on both values; `long` arithmetic removes the NaN-interval case. Keep the functions synchronous with no `Task` and no `DateTimeOffset.UtcNow`. The view model that owns the live snapshot recomputes the verdict when a new snapshot arrives and raises `INotifyPropertyChanged` for a derived `Freshness` property, which an `InfoBar` binds to (`IsOpen` when not `Fresh`, `Severity="Warning"` for `Stale`, `Severity="Error"` for `VeryStale`).

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/snapshot-staleness.ts` |

## Design Decisions

**Decision**: Measure the lag server clock against server clock (`generatedAt` minus `lastCycleAt`), never against the client's `Date.now()`.
**Rationale**: Per the doc comment, comparing against the client clock would false-trip on client clock skew or on `setInterval` timers throttled while a tab sleeps. Because the client re-pulls `/live`, a wedged poller still shows a growing lag.
**Approved**: pending

**Decision**: Scale the window to five times the probe interval, floored at five minutes.
**Rationale**: It mirrors the backend scheduler's own `staleAfterMs`, so raising `PROBE_INTERVAL_SECONDS` does not make a single skipped cycle false-trip the banner. The floor also serves older backends that report no interval.
**Approved**: pending

**Decision**: Escalate to `"very-stale"` at three times the window.
**Rationale**: The doc comment states `very-stale` escalates the banner tone from amber to red, separating a briefly paused monitor from one that has been down for a long time.
**Approved**: pending

**Decision**: Missing or unparseable timestamps fail open to `"fresh"`.
**Rationale**: No probe yet (a zero-endpoint monitor) or no read clock means there is nothing to judge, and a garbage date must not raise a false "monitoring paused" banner. This is the opposite of `board-staleness.ts`, which fails closed because an unjudgeable board must not render as healthy.
**Approved**: pending

**Decision**: Keep one shared rule for the banner and the portfolio indicator.
**Rationale**: The doc comment names the goal: the banner and the header/home status sign "can never disagree", which would happen if each computed its own threshold.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | partial | reliability |

**Separation of concerns.** The module holds only the rule and its thresholds, with no React, I/O or rendering; the banner and hook apply it.

**Unit test coverage.** `snapshot-staleness.test.ts` covers the floor and scaling of `snapshotStaleMs`, the missing-input, fresh, stale, very-stale, interval-scaling, NaN and negative-lag paths of `snapshotFreshness`.

**Explicit error handling.** Unparseable dates are handled by a deliberate negated comparison documented in the source, never by an exception.

**Graceful degradation.** An older backend with no `probeIntervalMs`, or a monitor with no probes, degrades to the floor window or to no banner rather than a false alarm.

**Health observability.** Partial: the rule surfaces data freshness to the user, but by design it fails open on unparseable or `NaN` inputs, so a malformed snapshot produces no staleness signal; cycle-completion health is left to the backend's `/health`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
