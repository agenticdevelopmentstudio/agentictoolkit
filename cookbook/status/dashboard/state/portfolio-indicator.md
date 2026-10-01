---
id: 43d93a67-c469-40d1-8465-076cd782e1b2
title: Portfolio Indicator
domain: agentictoolkit://cookbook/status/dashboard/state/portfolio-indicator
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State deriving the whole-portfolio status glyph key and problem count,
  falling back to unknown when feeds are offline, blind or stale.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/state/board
related:
- agentictoolkit://cookbook/status/dashboard/state/board
references: []
approved-by: ''
approved-date: ''
---

# Portfolio Indicator

## Overview

Portfolio Indicator is the single derivation of the whole-portfolio status sign, shared by the status header's pill and the landing sign in the board shell; in the current tree its callers are the board shell and the wallboard status view. It reads two independent feeds: the board state (for what's wrong) and Live Snapshot (for whether the data backing that claim is fresh). It returns a result holding a glyph key (`pillKey`) and a problem count (`count`).

Portfolio Indicator exists so that the rule for "when is status unknown" lives in one place and the signs that show portfolio status can never disagree. It does not format text: callers format their own headline text from `pillKey`/`count`.

Use it anywhere a view needs to show one portfolio-wide status verdict. Do not re-derive the unknown rule, the snapshot staleness rule, or the board staleness rule in a caller.

## Behavioral Requirements

### Public shape

- **hook-signature**: Portfolio Indicator MUST take no arguments and MUST return a result with exactly the fields `pillKey` and `count`.
- **pill-key-type**: `pillKey` MUST be one of `"ok"`, `"warn"`, `"down"` or `"unknown"`.
- **count-type**: `count` MUST be a non-negative integer, the problem count backing the sign.
- **no-text-output**: Portfolio Indicator MUST NOT return headline text, labels or colours; formatting is the caller's responsibility.

### Inputs read

- **board-input**: Portfolio Indicator MUST read the board from the board state and MUST use only its board value; it MUST NOT read the board state's reason, error or refetch fields.
- **live-input**: Portfolio Indicator MUST read `snapshot`, `offline` and `blind` from Live Snapshot.
- **board-null-trusted**: Portfolio Indicator MUST treat a null board as "nothing current has come back" regardless of why the board state returned null (not yet loaded, fetch failed, stale, frozen or no data), and MUST NOT compute its own board-staleness term; the board state already folds a stale board into this same null value.

### Snapshot staleness

- **snapshot-stale-rule**: The live snapshot MUST be judged stale exactly when `snapshot` is non-null and the shared snapshot-freshness check (given the snapshot's `lastCycleAt`, `generatedAt` and `probeIntervalMs`) returns anything other than `"fresh"` (that is, `"stale"` or `"very-stale"`).
- **snapshot-null-not-stale**: A null `snapshot` (no live read yet) MUST NOT count as stale.
- **shared-staleness-rule**: The snapshot staleness verdict MUST come from one shared snapshot-freshness check, the same rule the board-wide stale-snapshot banner uses, so the sign and the banner agree.
- **freshness-no-probe**: Under the shared check, a missing or empty `lastCycleAt` or `generatedAt` MUST yield `"fresh"` — no probe yet means nothing to judge, so no alarm.
- **freshness-window**: Under the shared check, the stale window MUST be `max(probeIntervalMs × 5, 300,000 ms)`, with a null or missing `probeIntervalMs` treated as 0 (so the window is the 300,000 ms floor).
- **freshness-lag**: Under the shared check, the lag MUST be measured as the parsed timestamp of `generatedAt` minus the parsed timestamp of `lastCycleAt`, both server clocks, and MUST NOT involve the client's current time.
- **freshness-threshold**: Under the shared check, a lag not strictly greater than the window MUST be `"fresh"`; a lag greater than the window MUST be `"stale"`, escalating to `"very-stale"` when greater than three times the window. Both non-fresh verdicts count as stale for Portfolio Indicator.
- **freshness-unparseable**: Under the shared check, an unparseable date (an invalid lag) MUST yield `"fresh"`, because a comparison against an invalid value defaults to not-stale.

### Derivation

- **unknown-when-offline**: `pillKey` MUST be `"unknown"` when Live Snapshot's `offline` is true.
- **unknown-when-blind**: `pillKey` MUST be `"unknown"` when Live Snapshot's `blind` is true (the last snapshot monitored no endpoints).
- **unknown-when-no-board**: `pillKey` MUST be `"unknown"` when `board` is null.
- **unknown-when-snapshot-stale**: `pillKey` MUST be `"unknown"` when the snapshot is stale per **snapshot-stale-rule**.
- **independent-feeds**: Any single one of the four unknown conditions MUST be sufficient on its own: the live transport and the board poll fail independently, and either one alone going stale is real information the other can't stand in for.
- **mapped-verdict**: When none of the unknown conditions holds, `pillKey` MUST be the mapped value of `board.indicator`: `"operational"` maps to `"ok"`, `"degraded"` to `"warn"`, and `"outage"` to `"down"`.
- **server-verdict-only**: Portfolio Indicator MUST NOT compute the colour from the problems list; the non-unknown `pillKey` MUST come solely from the server-assigned `board.indicator`.
- **count-from-board**: `count` MUST be `board.problems.length` whenever `board` is non-null, including when `pillKey` is `"unknown"` because the live feed is offline, blind or stale.
- **count-no-board**: `count` MUST be `0` when `board` is null.

### Execution, caching and side effects

- **pure-derivation**: Portfolio Indicator MUST perform no side effects of its own: no fetches, timers, storage writes, logging or subscriptions beyond those the board state and Live Snapshot perform.
- **no-memoisation**: Portfolio Indicator MUST recompute `pillKey` and `count` every time its inputs are read and MUST NOT cache or retain a previous verdict; a null board renders `"unknown"`, never the last verdict.
- **render-thread**: Portfolio Indicator MUST run synchronously, on a single execution thread; it has no asynchronous work and no ordering concerns of its own.
- **provider-precondition**: Portfolio Indicator MUST be used only where the shared cache context and the status API context its two inputs require are available; this is a caller precondition inherited from the board state and Live Snapshot.

## Appearance

Not applicable — this is a state-derivation concept, not a visual component.

## States

Not applicable — this is a state-derivation concept, not a visual component.

## Accessibility

Not applicable — this is a state-derivation concept, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| portfolio-001 | mapped-verdict, snapshot-null-not-stale | `snapshot: null`, `offline: false`, `blind: false`, board `{ indicator: "operational", problems: [] }` | `pillKey` is `"ok"`, `count` is `0` |
| portfolio-002 | unknown-when-no-board, count-no-board, board-null-trusted | `snapshot: null`, `offline: false`, `blind: false`, `board: null` | `pillKey` is `"unknown"`, `count` is `0` |
| portfolio-003 | unknown-when-offline, count-from-board | `offline: true`, board `{ indicator: "operational", problems: [p1] }` | `pillKey` is `"unknown"`, `count` is `1` |
| portfolio-004 | unknown-when-blind | `blind: true`, `offline: false`, board `{ indicator: "degraded", problems: [p1, p2] }` | `pillKey` is `"unknown"`, `count` is `2` |
| portfolio-005 | mapped-verdict | fresh snapshot, board `{ indicator: "degraded", problems: [p1, p2] }` | `pillKey` is `"warn"`, `count` is `2` |
| portfolio-006 | mapped-verdict | fresh snapshot, board `{ indicator: "outage", problems: [p1] }` | `pillKey` is `"down"`, `count` is `1` |
| portfolio-007 | unknown-when-snapshot-stale, snapshot-stale-rule, freshness-window, freshness-threshold | snapshot `{ lastCycleAt: T, generatedAt: T + 301,000 ms, probeIntervalMs: 60,000 }`, board `{ indicator: "operational", problems: [] }` | Stale window is 300,000 ms, lag 301,000 ms, verdict `"stale"`: `pillKey` is `"unknown"`, `count` is `0` |
| portfolio-008 | freshness-threshold | snapshot `{ lastCycleAt: T, generatedAt: T + 300,000 ms, probeIntervalMs: 60,000 }`, board `{ indicator: "operational" }` | Lag equals window, verdict `"fresh"`: `pillKey` is `"ok"` |
| portfolio-009 | freshness-window | snapshot `{ lastCycleAt: T, generatedAt: T + 400,000 ms, probeIntervalMs: 120,000 }`, board `{ indicator: "operational" }` | Window is 600,000 ms, verdict `"fresh"`: `pillKey` is `"ok"` |
| portfolio-010 | freshness-threshold, unknown-when-snapshot-stale | snapshot `{ lastCycleAt: T, generatedAt: T + 901,000 ms, probeIntervalMs: 60,000 }`, board `{ indicator: "operational" }` | Verdict `"very-stale"`: `pillKey` is `"unknown"` |
| portfolio-011 | freshness-no-probe, snapshot-stale-rule | snapshot `{ lastCycleAt: null, generatedAt: T }`, board `{ indicator: "operational" }` | Verdict `"fresh"`: `pillKey` is `"ok"` |
| portfolio-012 | freshness-unparseable | snapshot `{ lastCycleAt: "not-a-date", generatedAt: T }`, board `{ indicator: "operational" }` | Invalid lag, verdict `"fresh"`: `pillKey` is `"ok"` |
| portfolio-013 | board-null-trusted, independent-feeds | The board state fed a board `{ indicator: "operational", problems: [] }` whose `generatedAt` is `BOARD_STALE_MS + 5,000` ms old; Live Snapshot inert (`snapshot: null`, `offline: false`, `blind: false`) | `pillKey` is `"unknown"`, and the global panel sharing the same cache context shows "status unknown" |
| portfolio-014 | no-memoisation | Evaluate with board `{ indicator: "operational" }` (`pillKey` is `"ok"`), then re-evaluate with `board: null` | Second evaluation returns `pillKey` `"unknown"`, not `"ok"` |
| portfolio-015 | hook-signature, no-text-output | Any input | The returned object's own keys are exactly `pillKey` and `count` |

## Edge Cases

- **No data yet**: Before either feed has answered (`snapshot: null`, `board: null`), `pillKey` MUST be `"unknown"` and `count` MUST be `0`; without this the pill would render a false green "operational" off nothing before the first read lands.
- **Board present, snapshot not yet read**: With a non-null board and `snapshot: null`, Portfolio Indicator MUST return the board's mapped verdict, since a null snapshot is neither offline, blind nor stale.
- **Zero-endpoint monitor**: A snapshot with an empty `services` list sets `blind`, so `pillKey` MUST be `"unknown"` even if the board reports `"operational"`.
- **Zero problems**: A non-null board with an empty `problems` array MUST yield `count` `0`; the colour still comes from `board.indicator`, not from the count.
- **Unknown with a count**: When the live feed is offline, blind or stale but the board is current, Portfolio Indicator MUST return `"unknown"` together with the board's non-zero problem count; callers that print a number next to an unknown glyph see the board's count.
- **Stale window boundary**: A lag exactly equal to the stale window MUST be fresh; one millisecond more MUST be stale (portfolio-007, portfolio-008).
- **Missing probe interval**: A snapshot from an older backend with no `probeIntervalMs` MUST be judged against the 300,000 ms floor.
- **Malformed timestamps**: An unparseable `lastCycleAt` or `generatedAt` MUST be treated as fresh, so it never forces `"unknown"` on its own; this is the deliberate behavior of the shared snapshot-freshness check.
- **Client clock skew or sleeping tab**: The snapshot verdict MUST be unaffected, since it compares two server timestamps only. The board staleness verdict applied inside the board state is that state's own contract, not this one's.
- **Unmapped indicator**: A `board.indicator` value outside `"operational"`, `"degraded"` or `"outage"` is excluded by the board's declared shape; Portfolio Indicator does no runtime check and would return an undefined `pillKey`. The board shape is owned by the server.
- **Network failure or unreachable server**: Portfolio Indicator MUST NOT handle transport errors itself; a failed board read surfaces as a null board from the board state and a dead live feed surfaces as `offline` true from Live Snapshot, and both MUST yield `"unknown"`.
- **Timeouts, cancellation and retries**: Portfolio Indicator has none; any timeout, retry or cancellation belongs to the board state and Live Snapshot.
- **Concurrent calls**: Multiple callers MAY use Portfolio Indicator at once; each derives independently from the same shared cache and live store, so callers sharing one cache context MUST see the same verdict at the same evaluation. Execution is single-threaded, so there is no interleaving within Portfolio Indicator.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| (none) | — | — | Portfolio Indicator takes no parameters. |
| `SNAPSHOT_STALE_FLOOR_MS` | number constant | `300000` | Floor of the snapshot stale window; also the window when the backend omits `probeIntervalMs`. |
| `snapshot.probeIntervalMs` | number, null, or absent (server-supplied) | treated as `0` | Probe cadence; the stale window is 5 times this, floored at `SNAPSHOT_STALE_FLOOR_MS`. |
| Board state | injected dependency | — | Supplies the board (or null); carries its own polling, retry and board staleness configuration. |
| Live Snapshot | injected dependency | — | Supplies `snapshot`, `offline` and `blind`; carries its own transport configuration. |
| Shared cache context and status API context | required context | — | Required by the two inputs; Portfolio Indicator must be used where they are available. |

## Deep Linking

Not applicable: Portfolio Indicator only derives a value from two other state concepts and exposes no route or URL.

## Localization

Not applicable: Portfolio Indicator returns only the machine keys `"ok"`, `"warn"`, `"down"` and `"unknown"` and a number; headline text is formatted by callers.

## Accessibility Options

Not applicable: Portfolio Indicator renders nothing and reads no display preference.

## Feature Flags

Not applicable: the source reads no flag and the derivation is unconditional.

## Analytics

Not applicable: the source emits no events.

## Privacy

Not applicable: Portfolio Indicator reads only monitor status data already fetched by its two inputs, stores nothing and transmits nothing.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: Expose the result as a computed property on an `@Observable` `@MainActor` store that already holds `board: Board?` and the live snapshot state (`snapshot`, `offline`, `blind`), returning a `struct PortfolioIndicator: Sendable, Equatable { let pillKey: PillKey; let count: Int }` where `PillKey` is an `enum` with cases `ok`, `warn`, `down`, `unknown`. Parse the ISO timestamps with `ISO8601DateFormatter` (with fractional seconds) or `Date.ISO8601FormatStyle`; a failed parse must fall through to fresh to mirror the invalid-lag rule. Views observing the store re-read the computed property automatically; there is no hook, so never cache the last value.
- **Compose**: Derive with `combine(boardFlow, liveFlow) { board, live -> ... }` in a `ViewModel`, exposed as `StateFlow<PortfolioIndicator>` via `stateIn`, with `PortfolioIndicator` a `data class` and the key an `enum class`. Parse timestamps with `java.time.Instant.parse` inside `runCatching`, treating failure as fresh. Because `combine` re-emits whenever either input emits, the "never the last verdict" rule holds as long as a null board is emitted, not filtered.
- **React/Web**: Source platform. `hooks/use-portfolio-indicator.ts` composes `useBoard` (`hooks/use-board.ts`) and `useLiveSnapshot` (`hooks/use-live-snapshot.ts`), applies `snapshotFreshness` from `lib/snapshot-staleness.ts`, and maps through `INDICATOR_STATE` (the `IndicatorState` union) in `lib/overview.ts`. It relies on `useBoard` having already folded board staleness into `board: null`. The board shape is declared in `lib/board-types.ts`. Dates are compared with `Date.parse`, and an unparseable one yields `NaN`, whose comparison `!(ageMs > staleMs)` defaults to fresh. Tests mock both input hooks at the module boundary with `vi.mock` (`use-portfolio-indicator.dom.test.tsx`) and exercise the real `useBoard` in `use-board.dom.test.tsx`, where it is checked against `GlobalPanel` on the same `QueryClient`.
- **AppKit / UIKit**: Same computed property on a `@MainActor` store as SwiftUI; with no render pass, recompute when the board or live state changes and publish through `@Published` or `withObservationTracking` so the header item and landing view update together.
- **WinUI 3**: Implement a `PortfolioIndicatorViewModel` deriving from CommunityToolkit.Mvvm `ObservableObject` (or implementing `INotifyPropertyChanged` directly) that takes the `BoardStore` and `LiveSnapshotStore` singletons by constructor injection (`Microsoft.Extensions.DependencyInjection`). Subscribe to both stores' `PropertyChanged` and recompute `PillKey` (a C# `enum PillKey { Ok, Warn, Down, Unknown }`) and `Count` (`int`) on every change, raising `PropertyChanged` for both; a `record struct PortfolioIndicator(PillKey PillKey, int Count)` works as an immutable result. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`, and treat a failed parse as fresh to match the invalid-lag rule; compute the lag as `(generatedAt - lastCycleAt).TotalMilliseconds` and the window as `Math.Max((probeIntervalMs ?? 0) * 5, 300_000)`. There is no render-driven recomputation as in React, so the recompute must be wired explicitly; run it on the UI thread (marshal store changes with `DispatcherQueue.TryEnqueue`). Bind the header and landing views with `x:Bind ViewModel.PillKey` through an `IValueConverter` or `VisualStateManager` states per key, and format headline text in the view layer, never in the view model. Register the view model as a singleton so both signs read one instance.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-portfolio-indicator.ts` |

## Design Decisions

**Decision**: The "status unknown" rule lives in one shared concept used by every portfolio-wide sign.
**Rationale**: Sharing the derivation keeps the "when is status unknown" rule in one place so the two signs can never disagree.
**Approved**: pending

**Decision**: Snapshot staleness and board staleness are separate unknown conditions.
**Rationale**: The live transport and the board poll fail independently, and either one alone going stale is real information the other can't stand in for.
**Approved**: pending

**Decision**: Portfolio Indicator trusts a null board and computes no board-staleness term of its own.
**Rationale**: Board staleness was moved into the board state, so a null board already covers both "never arrived" and "gone stale" by construction, the same way every other consumer of the board state now does; a second check here would be a consumer re-deriving a rule its input already applies.
**Approved**: pending

**Decision**: A null snapshot counts as fresh, not unknown.
**Rationale**: A null `lastCycleAt` (no probe yet) is fresh, so a healthy monitor is unaffected; the board, not the snapshot, is the thing that must have come back before a colour is claimed.
**Approved**: pending

**Decision**: `count` is taken from the board even when `pillKey` is `"unknown"`.
**Rationale**: The board's problem count is independent of the unknown test; callers decide whether to show a count beside an unknown glyph.
**Approved**: pending

**Decision**: Staleness compares two server timestamps rather than the client clock.
**Rationale**: Measuring `generatedAt - lastCycleAt` is immune to client clock skew and to client timers being throttled while a tab sleeps. This rationale applies as written to a client that has such a timer-throttling concern (the web platform); a port on a platform without it keeps the two-server-timestamp comparison regardless, since it is also immune to simple client clock skew.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |

**Separation of Concerns**: Fetching and board staleness sit in `useBoard`, the live transport in `useLiveSnapshot`, the snapshot staleness rule in `lib/snapshot-staleness.ts`, and the server-to-glyph mapping in `lib/overview.ts`; the hook only composes them, and text formatting stays with callers.

**Unit Test Coverage**: `use-portfolio-indicator.dom.test.tsx` covers a present board backing its verdict and a null board rendering unknown; `use-board.dom.test.tsx` covers the hook agreeing with `GlobalPanel` on a stale board. The offline, blind and stale-snapshot branches, the `"warn"` and `"down"` mappings and the `count` value are not asserted by the hook's own tests, though `snapshotFreshness` has its own test file.

**Graceful Degradation**: Any missing, failed, blind or stale input degrades the sign to `"unknown"` instead of a false green.

**Data Integrity**: The colour is the server's `board.indicator` mapped one-to-one; the hook never recomputes severity and never shows a retained verdict.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
