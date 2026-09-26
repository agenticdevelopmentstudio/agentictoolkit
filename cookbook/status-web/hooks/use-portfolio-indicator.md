---
id: 43d93a67-c469-40d1-8465-076cd782e1b2
title: usePortfolioIndicator
domain: agentictoolkit://cookbook/status-web/hooks/use-portfolio-indicator
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook deriving the whole-portfolio status glyph key and problem count,
  falling back to unknown when feeds are offline, blind or stale
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status-web/hooks/use-board
related:
- agentictoolkit://cookbook/status-web/hooks/use-board
references: []
approved-by: ''
approved-date: ''
---

# usePortfolioIndicator

## Overview

`usePortfolioIndicator` (`packages/web/packages/status-web/src/hooks/use-portfolio-indicator.ts`) is the single derivation of the whole-portfolio status sign. Per its doc comment it is "shared by the header pill (StatusHeader) and the /home landing sign (BoardShell)"; in the current tree its callers are `BoardShell` and `WallboardStatus`. It reads two independent feeds: the server-derived board from [useBoard](agentictoolkit://cookbook/status-web/hooks/use-board) ("for what's wrong") and the live snapshot transport from `useLiveSnapshot` ("for whether the data backing that claim is fresh"). It returns a `PortfolioIndicator` holding a glyph key (`pillKey`) and a problem count (`count`).

The hook exists so that the rule for "when is status unknown" lives in one place and the signs that show portfolio status can never disagree. It does not format text: "Callers format their own headline text from `pillKey`/`count`" (for example with `headlineFor` in `lib/overview.ts`).

Use it anywhere a view needs to show one portfolio-wide status verdict. Do not re-derive the unknown rule, the snapshot staleness rule, or the board staleness rule in a caller.

## Behavioral Requirements

### Public shape

- **hook-signature**: `usePortfolioIndicator` MUST take no arguments and MUST return a `PortfolioIndicator` object with exactly the fields `pillKey` and `count`.
- **pill-key-type**: `PortfolioIndicator.pillKey` MUST be one of `"ok"`, `"warn"`, `"down"` (the `IndicatorState` union from `lib/overview.ts`) or `"unknown"`.
- **count-type**: `PortfolioIndicator.count` MUST be a non-negative integer, the "Problem count backing the sign".
- **no-text-output**: The hook MUST NOT return headline text, labels or colours; formatting is the caller's responsibility.

### Inputs read

- **board-input**: The hook MUST read the board from `useBoard()` and MUST use only its `board` field (`Board | null`); it MUST NOT read `reason`, `error` or `refetch`.
- **live-input**: The hook MUST read `snapshot`, `offline` and `blind` from `useLiveSnapshot()`.
- **board-null-trusted**: The hook MUST treat `board === null` as "nothing current has come back" regardless of why `useBoard` returned null (not yet loaded, fetch failed, stale, frozen or no data), and MUST NOT compute its own board-staleness term; per the source comment, `useBoard` "now folds a STALE board ... into this same `null`".

### Snapshot staleness

- **snapshot-stale-rule**: The live snapshot MUST be judged stale exactly when `snapshot` is non-null and `snapshotFreshness(snapshot.lastCycleAt, snapshot.generatedAt, snapshot.probeIntervalMs)` returns anything other than `"fresh"` (that is, `"stale"` or `"very-stale"`).
- **snapshot-null-not-stale**: A null `snapshot` (no live read yet) MUST NOT count as stale.
- **shared-staleness-rule**: The snapshot staleness verdict MUST come from the shared `snapshotFreshness` in `lib/snapshot-staleness.ts`, the same rule the board-wide `SnapshotStaleBanner` uses, so the sign and the banner agree.
- **freshness-no-probe**: Per `snapshotFreshness`, a missing or empty `lastCycleAt` or `generatedAt` MUST yield `"fresh"` ("No probe yet ... nothing to judge; no alarm").
- **freshness-window**: Per `snapshotFreshness`, the stale window MUST be `max(probeIntervalMs × 5, 300 000 ms)`, with a null or missing `probeIntervalMs` treated as 0 (so the window is the 300 000 ms floor, `SNAPSHOT_STALE_FLOOR_MS`).
- **freshness-lag**: Per `snapshotFreshness`, the lag MUST be measured as `Date.parse(generatedAt) - Date.parse(lastCycleAt)`, both server clocks, and MUST NOT involve the client's current time.
- **freshness-threshold**: Per `snapshotFreshness`, a lag not strictly greater than the window MUST be `"fresh"`; a lag greater than the window MUST be `"stale"`, escalating to `"very-stale"` when greater than three times the window. Both non-fresh verdicts count as stale for this hook.
- **freshness-unparseable**: Per `snapshotFreshness`, an unparseable date (a NaN lag) MUST yield `"fresh"`, because the comparison is written `!(ageMs > staleMs)`.

### Derivation

- **unknown-when-offline**: `pillKey` MUST be `"unknown"` when `useLiveSnapshot().offline` is true.
- **unknown-when-blind**: `pillKey` MUST be `"unknown"` when `useLiveSnapshot().blind` is true (the last snapshot monitored no endpoints).
- **unknown-when-no-board**: `pillKey` MUST be `"unknown"` when `board` is null.
- **unknown-when-snapshot-stale**: `pillKey` MUST be `"unknown"` when the snapshot is stale per **snapshot-stale-rule**.
- **independent-feeds**: Any single one of the four unknown conditions MUST be sufficient on its own; the source comment states "the live transport and the board poll fail independently, and either one alone going stale is real information the other can't stand in for".
- **mapped-verdict**: When none of the unknown conditions holds, `pillKey` MUST be `INDICATOR_STATE[board.indicator]`: `"operational"` maps to `"ok"`, `"degraded"` to `"warn"`, and `"outage"` to `"down"`.
- **server-verdict-only**: The hook MUST NOT compute the colour from the problems list; the non-unknown `pillKey` MUST come solely from the server-assigned `board.indicator`.
- **count-from-board**: `count` MUST be `board.problems.length` whenever `board` is non-null, including when `pillKey` is `"unknown"` because the live feed is offline, blind or stale.
- **count-no-board**: `count` MUST be `0` when `board` is null.

### Execution, caching and side effects

- **pure-derivation**: The hook MUST perform no side effects of its own: no fetches, timers, storage writes, logging or subscriptions beyond those `useBoard` and `useLiveSnapshot` perform.
- **no-memoisation**: The hook MUST recompute `pillKey` and `count` on every render and MUST NOT cache or retain a previous verdict; a null board renders `"unknown"`, "never the last verdict".
- **render-thread**: The hook MUST run synchronously during React render on the single JavaScript thread; it has no asynchronous work and no ordering concerns of its own.
- **provider-precondition**: The hook MUST be called inside the React component tree under the providers its two input hooks require (a React Query `QueryClientProvider` and the status API context used by `useBoard`); this is a caller precondition inherited from those hooks.

## Appearance

Not applicable — this is a React state-derivation hook, not a visual component.

## States

Not applicable — this is a React state-derivation hook, not a visual component.

## Accessibility

Not applicable — this is a React state-derivation hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| portfolio-001 | mapped-verdict, snapshot-null-not-stale | `snapshot: null`, `offline: false`, `blind: false`, board `{ indicator: "operational", problems: [] }` | `pillKey === "ok"`, `count === 0` (from `use-portfolio-indicator.dom.test.tsx`, "a present board backs its own verdict") |
| portfolio-002 | unknown-when-no-board, count-no-board, board-null-trusted | `snapshot: null`, `offline: false`, `blind: false`, `board: null` | `pillKey === "unknown"`, `count === 0` (from "board === null renders unknown, never the last verdict") |
| portfolio-003 | unknown-when-offline, count-from-board | `offline: true`, board `{ indicator: "operational", problems: [p1] }` | `pillKey === "unknown"`, `count === 1` |
| portfolio-004 | unknown-when-blind | `blind: true`, `offline: false`, board `{ indicator: "degraded", problems: [p1, p2] }` | `pillKey === "unknown"`, `count === 2` |
| portfolio-005 | mapped-verdict | fresh snapshot, board `{ indicator: "degraded", problems: [p1, p2] }` | `pillKey === "warn"`, `count === 2` |
| portfolio-006 | mapped-verdict | fresh snapshot, board `{ indicator: "outage", problems: [p1] }` | `pillKey === "down"`, `count === 1` |
| portfolio-007 | unknown-when-snapshot-stale, snapshot-stale-rule, freshness-window, freshness-threshold | snapshot `{ lastCycleAt: T, generatedAt: T + 301 000 ms, probeIntervalMs: 60 000 }`, board `{ indicator: "operational", problems: [] }` | stale window is 300 000 ms, lag 301 000 ms, verdict `"stale"`: `pillKey === "unknown"`, `count === 0` |
| portfolio-008 | freshness-threshold | snapshot `{ lastCycleAt: T, generatedAt: T + 300 000 ms, probeIntervalMs: 60 000 }`, board `{ indicator: "operational" }` | lag equals window, verdict `"fresh"`: `pillKey === "ok"` |
| portfolio-009 | freshness-window | snapshot `{ lastCycleAt: T, generatedAt: T + 400 000 ms, probeIntervalMs: 120 000 }`, board `{ indicator: "operational" }` | window is 600 000 ms, verdict `"fresh"`: `pillKey === "ok"` |
| portfolio-010 | freshness-threshold, unknown-when-snapshot-stale | snapshot `{ lastCycleAt: T, generatedAt: T + 901 000 ms, probeIntervalMs: 60 000 }`, board `{ indicator: "operational" }` | verdict `"very-stale"`: `pillKey === "unknown"` |
| portfolio-011 | freshness-no-probe, snapshot-stale-rule | snapshot `{ lastCycleAt: null, generatedAt: T }`, board `{ indicator: "operational" }` | verdict `"fresh"`: `pillKey === "ok"` |
| portfolio-012 | freshness-unparseable | snapshot `{ lastCycleAt: "not-a-date", generatedAt: T }`, board `{ indicator: "operational" }` | NaN lag, verdict `"fresh"`: `pillKey === "ok"` |
| portfolio-013 | board-null-trusted, independent-feeds | Real `useBoard` fed a board `{ indicator: "operational", problems: [] }` whose `generatedAt` is `BOARD_STALE_MS + 5 000` ms old; `useLiveSnapshot` inert (`snapshot: null`, `offline: false`, `blind: false`) | `pillKey === "unknown"`, and `GlobalPanel` on the same `QueryClient` shows "status unknown" (from `use-board.dom.test.tsx`, "the pill (usePortfolioIndicator) and GlobalPanel agree a stale board is unknown") |
| portfolio-014 | no-memoisation | Render with board `{ indicator: "operational" }` (`pillKey === "ok"`), then re-render with `board: null` | Second render returns `pillKey === "unknown"`, not `"ok"` |
| portfolio-015 | hook-signature, no-text-output | Any input | Returned object's own keys are exactly `pillKey` and `count` |

## Edge Cases

- **No data yet**: Before either feed has answered (`snapshot: null`, `board: null`), `pillKey` MUST be `"unknown"` and `count` MUST be `0`; the source comment explains that without this the pill "would render a false green 'operational' off nothing before the first read lands".
- **Board present, snapshot not yet read**: With a non-null board and `snapshot: null`, the hook MUST return the board's mapped verdict, since a null snapshot is neither offline, blind nor stale.
- **Zero-endpoint monitor**: A snapshot with an empty `services` list sets `blind`, so `pillKey` MUST be `"unknown"` even if the board reports `"operational"`.
- **Zero problems**: A non-null board with an empty `problems` array MUST yield `count === 0`; the colour still comes from `board.indicator`, not from the count.
- **Unknown with a count**: When the live feed is offline, blind or stale but the board is current, the hook MUST return `"unknown"` together with the board's non-zero problem count; callers that print a number next to an unknown glyph see the board's count.
- **Stale window boundary**: A lag exactly equal to the stale window MUST be fresh; one millisecond more MUST be stale (portfolio-007, portfolio-008).
- **Missing probe interval**: A snapshot from an older backend with no `probeIntervalMs` MUST be judged against the 300 000 ms floor.
- **Malformed timestamps**: An unparseable `lastCycleAt` or `generatedAt` MUST be treated as fresh, so it never forces `"unknown"` on its own; this is the deliberate behaviour of `snapshotFreshness`.
- **Client clock skew or sleeping tab**: The snapshot verdict MUST be unaffected, since it compares two server timestamps only. The board staleness verdict applied inside `useBoard` is that hook's contract, not this one's.
- **Unmapped indicator**: A `board.indicator` outside `"operational" | "degraded" | "outage"` is excluded by the `Indicator` type; the hook does no runtime check and would return `undefined` as `pillKey`. The board shape is owned by the server and mirrored in `lib/board-types.ts`.
- **Network failure or unreachable server**: The hook MUST NOT handle transport errors itself; a failed board read surfaces as `board: null` from `useBoard` and a dead live feed surfaces as `offline: true` from `useLiveSnapshot`, and both MUST yield `"unknown"`.
- **Timeouts, cancellation and retries**: The hook has none; any timeout, retry or cancellation belongs to `useBoard` and `useLiveSnapshot`.
- **Concurrent calls**: Multiple components MAY call the hook at once; each call derives independently from the same shared React Query caches and live store, so callers under one `QueryClient` MUST see the same verdict in the same render pass. JavaScript is single-threaded, so there is no interleaving within the hook.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| (none) | — | — | The hook takes no parameters. |
| `SNAPSHOT_STALE_FLOOR_MS` | `number` constant | `300000` | Floor of the snapshot stale window, in `lib/snapshot-staleness.ts`; also the window when the backend omits `probeIntervalMs`. |
| `snapshot.probeIntervalMs` | `number \| null \| undefined` (server-supplied) | treated as `0` | Probe cadence; the stale window is 5 times this, floored at `SNAPSHOT_STALE_FLOOR_MS`. |
| `useBoard` | injected hook | — | Supplies `board: Board \| null`; carries its own polling, retry and board staleness configuration. |
| `useLiveSnapshot` | injected hook | — | Supplies `snapshot`, `offline` and `blind`; carries its own transport configuration. |
| `QueryClientProvider` and status API context | React providers | — | Required by the two input hooks; the hook must render beneath them. |

## Deep Linking

Not applicable: the hook only derives a value from two data hooks and exposes no route or URL.

## Localization

Not applicable: the hook returns only the machine keys `"ok"`, `"warn"`, `"down"` and `"unknown"` and a number; headline text is formatted by callers.

## Accessibility Options

Not applicable: the hook renders nothing and reads no display preference.

## Feature Flags

Not applicable: the source reads no flag and the derivation is unconditional.

## Analytics

Not applicable: the source emits no events.

## Privacy

Not applicable: the hook reads only monitor status data already fetched by `useBoard` and `useLiveSnapshot`, stores nothing and transmits nothing.

## Logging

Not applicable: the source contains no logging calls.

## Platform Notes

- **SwiftUI**: Expose the result as a computed property on an `@Observable` `@MainActor` store that already holds `board: Board?` and the live snapshot state (`snapshot`, `offline`, `blind`), returning a `struct PortfolioIndicator: Sendable, Equatable { let pillKey: PillKey; let count: Int }` where `PillKey` is an `enum` with cases `ok`, `warn`, `down`, `unknown`. Parse the ISO timestamps with `ISO8601DateFormatter` (with fractional seconds) or `Date.ISO8601FormatStyle`; a failed parse must fall through to fresh to mirror the NaN rule. Views observing the store re-read the computed property automatically; there is no hook, so never cache the last value.
- **Compose**: Derive with `combine(boardFlow, liveFlow) { board, live -> ... }` in a `ViewModel`, exposed as `StateFlow<PortfolioIndicator>` via `stateIn`, with `PortfolioIndicator` a `data class` and the key a `enum class`. Parse timestamps with `java.time.Instant.parse` inside `runCatching`, treating failure as fresh. Because `combine` re-emits whenever either input emits, the "never the last verdict" rule holds as long as a null board is emitted, not filtered.
- **React/Web**: Source platform. `hooks/use-portfolio-indicator.ts` composes `useBoard` (`hooks/use-board.ts`) and `useLiveSnapshot` (`hooks/use-live-snapshot.ts`), applies `snapshotFreshness` from `lib/snapshot-staleness.ts`, and maps through `INDICATOR_STATE` in `lib/overview.ts`. It relies on `useBoard` having already folded board staleness into `board: null`. Tests mock both input hooks at the module boundary with `vi.mock` (`use-portfolio-indicator.dom.test.tsx`) and exercise the real `useBoard` in `use-board.dom.test.tsx`.
- **AppKit / UIKit**: Same computed property on a `@MainActor` store as SwiftUI; with no render pass, recompute when the board or live state changes and publish through `@Published` or `withObservationTracking` so the header item and landing view update together.
- **WinUI 3**: Implement a `PortfolioIndicatorViewModel` deriving from CommunityToolkit.Mvvm `ObservableObject` (or implementing `INotifyPropertyChanged` directly) that takes the `BoardStore` and `LiveSnapshotStore` singletons by constructor injection (`Microsoft.Extensions.DependencyInjection`). Subscribe to both stores' `PropertyChanged` and recompute `PillKey` (a C# `enum PillKey { Ok, Warn, Down, Unknown }`) and `Count` (`int`) on every change, raising `PropertyChanged` for both; a `record struct PortfolioIndicator(PillKey PillKey, int Count)` works as an immutable result. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`, and treat a failed parse as fresh to match the NaN rule; compute the lag as `(generatedAt - lastCycleAt).TotalMilliseconds` and the window as `Math.Max((probeIntervalMs ?? 0) * 5, 300_000)`. There is no render-driven recomputation as in React, so the recompute must be wired explicitly; run it on the UI thread (marshal store changes with `DispatcherQueue.TryEnqueue`). Bind the header and landing views with `x:Bind ViewModel.PillKey` through an `IValueConverter` or `VisualStateManager` states per key, and format headline text in the view layer, never in the view model. Register the view model as a singleton so both signs read one instance.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-portfolio-indicator.ts` |

## Design Decisions

**Decision**: The "status unknown" rule lives in one shared hook used by every portfolio-wide sign.
**Rationale**: The doc comment states that sharing the derivation "keeps the 'when is status unknown' rule in ONE place so the two signs can never disagree".
**Approved**: pending

**Decision**: Snapshot staleness and board staleness are separate unknown conditions.
**Rationale**: The source comment states the live transport and the board poll "fail independently, and either one alone going stale is real information the other can't stand in for".
**Approved**: pending

**Decision**: The hook trusts `board === null` and computes no board-staleness term of its own.
**Rationale**: Fix Round 3 item 1 moved board staleness into `useBoard`, so "`board === null` already covers both 'never arrived' and 'gone stale' by construction, the same way every other consumer of `useBoard` now does"; a second check here would be a consumer re-deriving a rule its input already applies.
**Approved**: pending

**Decision**: A null snapshot counts as fresh, not unknown.
**Rationale**: The source comment states "null lastCycleAt (no probe yet) is fresh, so a healthy monitor is unaffected"; the board, not the snapshot, is the thing that must have come back before a colour is claimed.
**Approved**: pending

**Decision**: `count` is taken from the board even when `pillKey` is `"unknown"`.
**Rationale**: The expression `board?.problems.length ?? 0` is independent of the unknown test; callers decide whether to show a count beside an unknown glyph.
**Approved**: pending

**Decision**: Staleness compares two server timestamps rather than the client clock.
**Rationale**: `snapshotFreshness` documents that measuring `generatedAt - lastCycleAt` is "immune to client clock skew and to `setInterval`-based client timers being throttled while a tab sleeps".
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
