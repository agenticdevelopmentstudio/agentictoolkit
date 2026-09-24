---
id: 01f6f7b6-4bc5-4f35-a46a-1e80fe470097
title: Board Staleness
domain: agentictoolkit://recipes/status-web-src-lib-board-staleness
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure rules judging whether the status board's read clock and data clock can
  still back a current claim
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-board
references: []
approved-by: ''
approved-date: ''
---

# Board Staleness

## Overview

`board-staleness.ts` (`packages/web/packages/status-web/src/lib/board-staleness.ts`) is the status dashboard's single owner of the rules that decide whether a `Board` read can still back a current claim. It exports two constants for the board's poll cadence and read-staleness threshold, a constant and a function for the cadence-scaled data-clock window, a three-valued `BoardDataFreshness` type, and two pure predicates:

- `isBoardStale(generatedAt, nowMs)` catches a board read that has stopped ARRIVING. It compares the board's `generatedAt` against the client clock.
- `boardDataFreshness(dataAsOfMs, generatedAt, probeIntervalMs?)` catches a board that keeps arriving over frozen FACTS. It compares two server clocks: `generatedAt` minus `dataAsOfMs`.

Per the module's doc comment, the two rules compose and "neither can substitute for the other". The module has no state, no I/O and no side effects. Its one call site is the `useBoard` hook ([useBoard](agentictoolkit://recipes/status-web-hooks-use-board)), which folds both verdicts into `board === null` with a reason. The data-clock window is derived from `snapshotStaleMs` in the sibling `snapshot-staleness.ts`, so board and snapshot freshness share one "how old is too old" rule.

## Behavioral Requirements

### Constants

- **board-poll-interval**: `BOARD_POLL_INTERVAL_MS` MUST equal 60 000 ms. It is the board's own poll cadence. The module owns it so that the threshold derivation does not reach into the hook file, and `useBoard` imports it as its `refetchInterval`.
- **board-stale-threshold**: `BOARD_STALE_MS` MUST equal `3 * BOARD_POLL_INTERVAL_MS`, which is 180 000 ms (three missed poll cycles).
- **data-stale-cycles**: `BOARD_DATA_STALE_CYCLES` MUST equal 2. The doc comment requires it to be at least 2, because a window equal to one write cadence is crossed at the tail of every cycle.

### isBoardStale

- **read-stale-signature**: `isBoardStale` MUST take `generatedAt: string` (the board's own read timestamp) and `nowMs: number` (epoch milliseconds from the caller's clock), and MUST return a `boolean`.
- **read-stale-age**: `isBoardStale` MUST compute age as `nowMs - Date.parse(generatedAt)`.
- **read-stale-strict-threshold**: `isBoardStale` MUST return `true` when the age is strictly greater than `BOARD_STALE_MS`.
- **read-stale-at-threshold**: `isBoardStale` MUST return `false` when the age is exactly `BOARD_STALE_MS`.
- **read-stale-fail-closed**: `isBoardStale` MUST return `true` when the age is not a finite number, which happens when `generatedAt` is unparseable. The doc comment says an unparseable clock means "we cannot tell", and an absence of a judgeable claim must never render as health.
- **read-stale-future-age**: `isBoardStale` MUST return `false` for a negative age, when `generatedAt` is ahead of `nowMs`. The function applies no lower bound.
- **read-stale-client-clock**: The caller MUST supply `nowMs` from the client clock (`useNow()` at the sole call site), not from another server timestamp. The doc comment says the client clock is the one timestamp that keeps moving when every server-side feed has died.
- **read-stale-no-skew-correction**: `isBoardStale` MUST NOT attempt to detect or correct client clock skew. The doc comment deliberately accepts that a client clock running more than `BOARD_STALE_MS` fast false-trips a healthy board to stale, and that one running more than `BOARD_STALE_MS` slow masks a frozen board.
- **read-stale-precondition**: `isBoardStale` only judges a board that has arrived. Per its doc comment, callers MUST check `board === null` (no board at all) first, as the separate and stronger signal.

### boardDataStaleMs

- **data-window-signature**: `boardDataStaleMs` MUST take an optional `probeIntervalMs?: number | null` and MUST return a number of milliseconds.
- **data-window-formula**: `boardDataStaleMs` MUST return `snapshotStaleMs(probeIntervalMs) * BOARD_DATA_STALE_CYCLES`. `snapshotStaleMs` is `Math.max((probeIntervalMs ?? 0) * 5, SNAPSHOT_STALE_FLOOR_MS)`, and `SNAPSHOT_STALE_FLOOR_MS` is 300 000 ms.
- **data-window-unknown-cadence**: `boardDataStaleMs` MUST return 600 000 ms (the floor times two) when `probeIntervalMs` is `undefined`, `null` or `0`. An unknown cadence can only delay the verdict, never false-trip it.
- **data-window-exceeds-cadence**: For every positive `probeIntervalMs`, `boardDataStaleMs` MUST return a value strictly greater than the backend's platform-sample cadence `max(300_000, probeIntervalMs * 5)`.

### boardDataFreshness

- **freshness-type**: `BoardDataFreshness` MUST be the string union `"current" | "frozen" | "no-data"`.
- **freshness-signature**: `boardDataFreshness` MUST take `dataAsOfMs: number | null`, `generatedAt: string` and an optional `probeIntervalMs?: number | null`, and MUST return a `BoardDataFreshness`.
- **freshness-no-data**: `boardDataFreshness` MUST return `"no-data"` whenever `dataAsOfMs` is `null`, before it parses `generatedAt` or reads `probeIntervalMs`. The doc comment says "no-data" means the board rests on no observation at all. That is never health, but it is not evidence of a fault either.
- **freshness-lag**: `boardDataFreshness` MUST compute lag as `Date.parse(generatedAt) - dataAsOfMs`, which compares a server clock against a server clock.
- **freshness-fail-closed**: `boardDataFreshness` MUST return `"frozen"` when the lag is not finite, for example when `generatedAt` is unparseable. This matches `isBoardStale`.
- **freshness-frozen**: `boardDataFreshness` MUST return `"frozen"` when the lag is strictly greater than `boardDataStaleMs(probeIntervalMs)`.
- **freshness-current**: `boardDataFreshness` MUST return `"current"` when the lag is finite and less than or equal to `boardDataStaleMs(probeIntervalMs)`. That range includes a negative lag, when the data clock is slightly ahead of `generatedAt`.
- **freshness-skew-immune**: `boardDataFreshness` MUST NOT read the client clock. Its verdict depends only on its arguments.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be pure and synchronous. They MUST NOT perform I/O, log, throw on any input of the declared types, or mutate state.
- **single-threaded**: The module holds no state and runs on the single JavaScript thread, so concurrent calls cannot interleave and it needs no ordering rule.

## Appearance

Not applicable — this is a pure staleness-rule module, not a visual component.

## States

Not applicable — this is a pure staleness-rule module, not a visual component.

## Accessibility

Not applicable — this is a pure staleness-rule module, not a visual component.

## Conformance Test Vectors

All vectors use `now = Date.parse("2026-08-02T12:00:00.000Z")` and `generatedAt = "2026-08-02T12:00:00.000Z"` (so `genMs = now`). Vectors 001 to 016 are traced to the assertions in `board-staleness.test.ts`. Vectors 017 and 018 are traced to the constant declarations and to the `isBoardStale` body, which has no lower bound.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| board-staleness-001 | read-stale-strict-threshold, read-stale-age | `isBoardStale` with generatedAt = now minus 1 000 ms | `false` |
| board-staleness-002 | read-stale-at-threshold | `isBoardStale` with generatedAt = now minus 180 000 ms | `false` |
| board-staleness-003 | read-stale-strict-threshold | `isBoardStale` with generatedAt = now minus 180 001 ms | `true` |
| board-staleness-004 | read-stale-fail-closed | `isBoardStale("not-a-date", now)` | `true` |
| board-staleness-005 | freshness-current, freshness-lag | `boardDataFreshness(genMs - 1000, generatedAt)` | `"current"` |
| board-staleness-006 | freshness-current, data-window-unknown-cadence | `boardDataFreshness(genMs - 600000, generatedAt)` | `"current"` |
| board-staleness-007 | freshness-frozen | `boardDataFreshness(genMs - 600001, generatedAt)`; also `isBoardStale(generatedAt, genMs)` | `"frozen"`; `isBoardStale` returns `false` |
| board-staleness-008 | freshness-fail-closed | `boardDataFreshness(genMs, "not-a-date")` | `"frozen"` |
| board-staleness-009 | freshness-current | `boardDataFreshness(genMs + 500, generatedAt)` | `"current"` |
| board-staleness-010 | freshness-no-data | `boardDataFreshness(null, generatedAt)`; `boardDataFreshness(null, generatedAt, 3600000)`; `boardDataFreshness(null, "not-a-date")` | `"no-data"` for all three |
| board-staleness-011 | data-window-formula | `boardDataStaleMs(3600000)`; `boardDataFreshness(genMs - 600000, generatedAt, 3600000)` | 36 000 000; `"current"` |
| board-staleness-012 | data-window-formula, freshness-frozen | `boardDataFreshness(genMs - 600001, generatedAt, 60000)` | `"frozen"` |
| board-staleness-013 | data-window-exceeds-cadence | `boardDataStaleMs(p)` for p in 1 000, 15 000, 60 000, 300 000, 3 600 000 | Strictly greater than `max(300000, p * 5)` in every case |
| board-staleness-014 | data-window-exceeds-cadence, freshness-current | `boardDataFreshness(genMs - 300000, generatedAt, 60000)` (lag of one full platform-sample cadence) | `"current"` |
| board-staleness-015 | data-window-unknown-cadence | `boardDataStaleMs()`, `boardDataStaleMs(null)`, `boardDataStaleMs(0)` | 600 000 for each |
| board-staleness-016 | data-stale-cycles | `BOARD_DATA_STALE_CYCLES` | 2 (at least 2) |
| board-staleness-017 | board-poll-interval, board-stale-threshold | `BOARD_POLL_INTERVAL_MS`, `BOARD_STALE_MS` | 60 000 and 180 000 |
| board-staleness-018 | read-stale-future-age | `isBoardStale` with generatedAt = now plus 10 000 ms | `false` |

## Edge Cases

- **Unparseable `generatedAt`**: `Date.parse` returns `NaN`. `isBoardStale` MUST return `true` and `boardDataFreshness` MUST return `"frozen"` (fail closed).
- **Empty-string `generatedAt`**: `Date.parse("")` is `NaN`, so it takes the same fail-closed path as unparseable input and MUST read as stale or frozen.
- **Null `dataAsOfMs`**: The result MUST be `"no-data"` whatever `generatedAt` and `probeIntervalMs` are, including garbage `generatedAt`.
- **`dataAsOfMs` that is `NaN` or infinite**: The lag is non-finite, so `boardDataFreshness` MUST return `"frozen"`.
- **`nowMs` that is `NaN`**: The age is non-finite, so `isBoardStale` MUST return `true`.
- **Exact thresholds**: An age of exactly 180 000 ms, or a lag exactly equal to `boardDataStaleMs`, MUST read as not stale (`false` or `"current"`). Both comparisons are strict greater-than.
- **Clock ahead**: A `generatedAt` ahead of `nowMs`, or a `dataAsOfMs` ahead of `generatedAt`, MUST read as fresh or current. Neither function checks a lower bound.
- **Client clock skew beyond 180 000 ms**: A fast client clock MUST make `isBoardStale` return `true` for a healthy board. A slow one MUST make it return `false` for a frozen board. The module deliberately does not correct skew.
- **Missing, null or zero `probeIntervalMs`**: The data window MUST fall back to 600 000 ms. A negative interval also floors to 600 000 ms through `Math.max`.
- **Very large `probeIntervalMs`**: The window MUST scale linearly as `probeIntervalMs * 10`, with no upper cap.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O. A board feed that has stopped responding reaches it only as a `generatedAt` that ages past `BOARD_STALE_MS`, which is how this module detects an outage.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `generatedAt` | `string` (ISO 8601) | none (required) | The board read's own server timestamp, re-stamped on every read. |
| `nowMs` | `number` | none (required) | The client clock in epoch ms. The sole call site passes `useNow()`. |
| `dataAsOfMs` | `number \| null` | none (required) | The server-clock time of the board's newest underlying observation. `null` means no observation. |
| `probeIntervalMs` | `number \| null \| undefined` | `undefined`, which gives the 600 000 ms window | The backend's probe interval, read by the call site off the board being judged. |
| `BOARD_POLL_INTERVAL_MS` | constant | 60 000 | The board poll cadence, compiled in. |
| `BOARD_STALE_MS` | constant | 180 000 | The read-staleness threshold, compiled in. |
| `BOARD_DATA_STALE_CYCLES` | constant | 2 | The data-window multiplier, compiled in. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. Its one import is `snapshotStaleMs` from `./snapshot-staleness`.

## Deep Linking

Not applicable: the module exports pure functions and constants and has no navigable surface.

## Localization

Not applicable: the module returns booleans and fixed string-union tokens (`"current"`, `"frozen"`, `"no-data"`), not user-facing text.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and both rules always apply.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only timestamps and a probe interval. It stores and transmits nothing.

## Logging

Not applicable: the module makes no log calls. Its verdicts reach the user through the call site's `reason`.

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum BoardStaleness` namespace. Use `static let` constants, `TimeInterval` or `Int64` milliseconds, and an `enum BoardDataFreshness: String { case current, frozen, noData = "no-data" }`. Parse `generatedAt` with `ISO8601DateFormatter` (with `.withFractionalSeconds`). Unlike `Date.parse`, a failed parse returns `nil`, so the `nil` branch has to map explicitly to stale or `.frozen` to keep the fail-closed rule. Supply `nowMs` from the view's ticking clock (for example `TimelineView` or a published `Date`).
- **Compose**: Use a Kotlin `object BoardStaleness` with `const val` constants and an `enum class BoardDataFreshness`. `Instant.parse` throws `DateTimeParseException` rather than returning NaN, so catch it and return stale or `FROZEN`. Take `nowMs` from `System.currentTimeMillis()` or a ticking `State<Long>`.
- **React/Web**: This is the source: `src/lib/board-staleness.ts`, exercised by `src/lib/board-staleness.test.ts` and applied only by `src/hooks/use-board.ts`. It depends on `snapshotStaleMs` and `SNAPSHOT_STALE_FLOOR_MS` in `src/lib/snapshot-staleness.ts`. The fail-closed behavior relies on `Date.parse` returning `NaN` and the `Number.isFinite` guard.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port. Drive `nowMs` from a `Timer` or the UI layer's clock. Nothing in the module is UI-bound, so the code belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class BoardStaleness` in C#. Use `public const long BoardPollIntervalMs = 60_000;`, `BoardStaleMs = 3 * BoardPollIntervalMs`, `BoardDataStaleCycles = 2`, and a `public enum BoardDataFreshness { Current, Frozen, NoData }`. Serialise it to `"no-data"` with `[JsonStringEnumMemberName]` or a converter if it crosses `System.Text.Json`. Parse with `DateTimeOffset.TryParse(generatedAt, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and treat `false` as stale or `Frozen`, since .NET has no NaN parse result. Compute ms with `t.ToUnixTimeMilliseconds()`. Take the client clock from `DateTimeOffset.UtcNow` or an injected `TimeProvider`, so tests can pin it. `dataAsOfMs` becomes `long?` and `probeIntervalMs` becomes `long?`. The view model that calls these (the `useBoard` equivalent) would re-evaluate on a `DispatcherQueueTimer` tick and raise `INotifyPropertyChanged` for the derived reason. The functions themselves stay synchronous and pure, with no `Task`.

## Design Decisions

**Decision**: Judge read staleness against the client clock, not a server timestamp.
**Rationale**: The board and live feeds usually freeze together in the same backend outage, so a server-to-server comparison goes blind in the common failure. The client clock keeps moving no matter which feed died. Skew beyond `BOARD_STALE_MS` is accepted and left uncorrected.
**Approved**: pending

**Decision**: Judge data staleness server clock against server clock (`generatedAt` minus `dataAsOfMs`).
**Rationale**: A wedged monitor keeps re-stamping `generatedAt` while its facts stay frozen, so `isBoardStale` cannot see it. Comparing two server clocks is immune to client skew and to throttled timers in a sleeping tab.
**Approved**: pending

**Decision**: An unparseable `generatedAt` fails closed, reading as stale or `"frozen"`.
**Rationale**: This mirrors `deployDtoUnconfirmed` in `row-model.ts`. An absence of a judgeable claim must never render as health, and it deliberately differs from `snapshotFreshness`, which treats a missing clock as fresh.
**Approved**: pending

**Decision**: Derive the data window from `snapshotStaleMs` times 2, rather than using a fixed constant.
**Rationale**: Fix Round 2 item C2. A fixed 5-minute window made the whole board permanently unknown at `PROBE_INTERVAL_SECONDS=3600`. On a fleet with no HTTP endpoints it also made the board flap once per cycle, because the window exactly equalled the platform-sample cadence. Two cycles of headroom absorb one missed cycle.
**Approved**: pending

**Decision**: Use three freshness states, keeping `"no-data"` distinct from `"frozen"`.
**Rationale**: Fix Round 2 item C3. A roster with nothing to observe, or a monitor that has not finished its first cycle, is expected and not a fault. Reporting it as frozen sent fresh installs to debug a working monitor.
**Approved**: pending

**Decision**: Set the read threshold at three poll cycles (180 000 ms).
**Rationale**: One missed poll must not false-trip the check, but a permanently failing `/api/board` has to be caught within a wallboard viewer's attention span.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |

**Separation of concerns.** The module holds only the rules and thresholds, with no I/O or React. The hook applies them.

**Unit test coverage.** `board-staleness.test.ts` covers every exported function at, below and above each threshold, plus the fail-closed and no-data paths.

**Explicit error handling.** Unparseable timestamps are handled by an explicit `Number.isFinite` guard, never by an exception.

**Graceful degradation.** An unknown probe cadence widens the window rather than narrowing it.

**Data integrity.** Garbage clocks fail closed, so a board is never claimed healthy on data the module cannot judge.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from source |
