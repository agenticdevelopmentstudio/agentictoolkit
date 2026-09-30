<!-- leaf: implement-status-web-hooks/use-portfolio-indicator · source: status-web-hooks-use-portfolio-indicator.md -->

**Rules** (cite as `implement-status-web-hooks/use-portfolio-indicator#<slug>`):

- `hook-signature` MUST
- `pill-key-type` MUST
- `count-type` MUST
- `no-text-output` MUST
- `board-input` MUST
- `live-input` MUST
- `board-null-trusted` MUST
- `snapshot-stale-rule` MUST
- `snapshot-null-not-stale` MUST
- `shared-staleness-rule` MUST
- `freshness-no-probe` MUST
- `freshness-window` MUST
- `freshness-lag` MUST
- `freshness-threshold` MUST
- `freshness-unparseable` MUST
- `unknown-when-offline` MUST
- `unknown-when-blind` MUST
- `unknown-when-no-board` MUST
- `unknown-when-snapshot-stale` MUST
- `independent-feeds` MUST
- `mapped-verdict` MUST
- `server-verdict-only` MUST
- `count-from-board` MUST
- `count-no-board` MUST
- `pure-derivation` MUST
- `no-memoisation` MUST
- `render-thread` MUST
- `provider-precondition` MUST

# usePortfolioIndicator

## Overview

`usePortfolioIndicator` (`packages/web/packages/status-web/src/hooks/use-portfolio-indicator.ts`) is the single derivation of the whole-portfolio status sign. Per its doc comment it is "shared by the header pill (StatusHeader) and the /home landing sign (BoardShell)"; in the current tree its callers are `BoardShell` and `WallboardStatus`. It reads two independent feeds: the server-derived board from useBoard ("for what's wrong") and the live snapshot transport from `useLiveSnapshot` ("for whether the data backing that claim is fresh"). It returns a `PortfolioIndicator` holding a glyph key (`pillKey`) and a problem count (`count`).

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| (none) | — | — | The hook takes no parameters. |
| `SNAPSHOT_STALE_FLOOR_MS` | `number` constant | `300000` | Floor of the snapshot stale window, in `lib/snapshot-staleness.ts`; also the window when the backend omits `probeIntervalMs`. |
| `snapshot.probeIntervalMs` | `number \| null \| undefined` (server-supplied) | treated as `0` | Probe cadence; the stale window is 5 times this, floored at `SNAPSHOT_STALE_FLOOR_MS`. |
| `useBoard` | injected hook | — | Supplies `board: Board \| null`; carries its own polling, retry and board staleness configuration. |
| `useLiveSnapshot` | injected hook | — | Supplies `snapshot`, `offline` and `blind`; carries its own transport configuration. |
| `QueryClientProvider` and status API context | React providers | — | Required by the two input hooks; the hook must render beneath them. |

## Platform Notes

- **SwiftUI**: Expose the result as a computed property on an `@Observable` `@MainActor` store that already holds `board: Board?` and the live snapshot state (`snapshot`, `offline`, `blind`), returning a `struct PortfolioIndicator: Sendable, Equatable { let pillKey: PillKey; let count: Int }` where `PillKey` is an `enum` with cases `ok`, `warn`, `down`, `unknown`. Parse the ISO timestamps with `ISO8601DateFormatter` (with fractional seconds) or `Date.ISO8601FormatStyle`; a failed parse must fall through to fresh to mirror the NaN rule. Views observing the store re-read the computed property automatically; there is no hook, so never cache the last value.
- **Compose**: Derive with `combine(boardFlow, liveFlow) { board, live -> ... }` in a `ViewModel`, exposed as `StateFlow<PortfolioIndicator>` via `stateIn`, with `PortfolioIndicator` a `data class` and the key a `enum class`. Parse timestamps with `java.time.Instant.parse` inside `runCatching`, treating failure as fresh. Because `combine` re-emits whenever either input emits, the "never the last verdict" rule holds as long as a null board is emitted, not filtered.
- **React/Web**: Source platform. `hooks/use-portfolio-indicator.ts` composes `useBoard` (`hooks/use-board.ts`) and `useLiveSnapshot` (`hooks/use-live-snapshot.ts`), applies `snapshotFreshness` from `lib/snapshot-staleness.ts`, and maps through `INDICATOR_STATE` in `lib/overview.ts`. It relies on `useBoard` having already folded board staleness into `board: null`. Tests mock both input hooks at the module boundary with `vi.mock` (`use-portfolio-indicator.dom.test.tsx`) and exercise the real `useBoard` in `use-board.dom.test.tsx`.
- **AppKit / UIKit**: Same computed property on a `@MainActor` store as SwiftUI; with no render pass, recompute when the board or live state changes and publish through `@Published` or `withObservationTracking` so the header item and landing view update together.
- **WinUI 3**: Implement a `PortfolioIndicatorViewModel` deriving from CommunityToolkit.Mvvm `ObservableObject` (or implementing `INotifyPropertyChanged` directly) that takes the `BoardStore` and `LiveSnapshotStore` singletons by constructor injection (`Microsoft.Extensions.DependencyInjection`). Subscribe to both stores' `PropertyChanged` and recompute `PillKey` (a C# `enum PillKey { Ok, Warn, Down, Unknown }`) and `Count` (`int`) on every change, raising `PropertyChanged` for both; a `record struct PortfolioIndicator(PillKey PillKey, int Count)` works as an immutable result. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`, and treat a failed parse as fresh to match the NaN rule; compute the lag as `(generatedAt - lastCycleAt).TotalMilliseconds` and the window as `Math.Max((probeIntervalMs ?? 0) * 5, 300_000)`. There is no render-driven recomputation as in React, so the recompute must be wired explicitly; run it on the UI thread (marshal store changes with `DispatcherQueue.TryEnqueue`). Bind the header and landing views with `x:Bind ViewModel.PillKey` through an `IValueConverter` or `VisualStateManager` states per key, and format headline text in the view layer, never in the view model. Register the view model as a singleton so both signs read one instance.

