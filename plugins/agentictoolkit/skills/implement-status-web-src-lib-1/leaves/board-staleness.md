<!-- leaf: implement-status-web-src-lib-1/board-staleness · source: status-web-src-lib-board-staleness.md -->

**Rules** (cite as `implement-status-web-src-lib-1/board-staleness#<slug>`):

- `board-poll-interval` MUST
- `board-stale-threshold` MUST
- `data-stale-cycles` MUST
- `read-stale-signature` MUST
- `read-stale-age` MUST
- `read-stale-strict-threshold` MUST
- `read-stale-at-threshold` MUST
- `read-stale-fail-closed` MUST
- `read-stale-future-age` MUST
- `read-stale-client-clock` MUST
- `read-stale-no-skew-correction` MUST
- `read-stale-precondition` MUST
- `data-window-signature` MUST
- `data-window-formula` MUST
- `data-window-unknown-cadence` MUST
- `data-window-exceeds-cadence` MUST
- `freshness-type` MUST
- `freshness-signature` MUST
- `freshness-no-data` MUST
- `freshness-lag` MUST
- `freshness-fail-closed` MUST
- `freshness-frozen` MUST
- `freshness-current` MUST
- `freshness-skew-immune` MUST
- `pure-functions` MUST

# Board Staleness

## Overview

`board-staleness.ts` (`packages/web/packages/status-web/src/lib/board-staleness.ts`) is the status dashboard's single owner of the rules that decide whether a `Board` read can still back a current claim. It exports two constants for the board's poll cadence and read-staleness threshold, a constant and a function for the cadence-scaled data-clock window, a three-valued `BoardDataFreshness` type, and two pure predicates:

- `isBoardStale(generatedAt, nowMs)` catches a board read that has stopped ARRIVING. It compares the board's `generatedAt` against the client clock.
- `boardDataFreshness(dataAsOfMs, generatedAt, probeIntervalMs?)` catches a board that keeps arriving over frozen FACTS. It compares two server clocks: `generatedAt` minus `dataAsOfMs`.

Per the module's doc comment, the two rules compose and "neither can substitute for the other". The module has no state, no I/O and no side effects. Its one call site is the `useBoard` hook (useBoard), which folds both verdicts into `board === null` with a reason. The data-clock window is derived from `snapshotStaleMs` in the sibling `snapshot-staleness.ts`, so board and snapshot freshness share one "how old is too old" rule.

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

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum BoardStaleness` namespace. Use `static let` constants, `TimeInterval` or `Int64` milliseconds, and an `enum BoardDataFreshness: String { case current, frozen, noData = "no-data" }`. Parse `generatedAt` with `ISO8601DateFormatter` (with `.withFractionalSeconds`). Unlike `Date.parse`, a failed parse returns `nil`, so the `nil` branch has to map explicitly to stale or `.frozen` to keep the fail-closed rule. Supply `nowMs` from the view's ticking clock (for example `TimelineView` or a published `Date`).
- **Compose**: Use a Kotlin `object BoardStaleness` with `const val` constants and an `enum class BoardDataFreshness`. `Instant.parse` throws `DateTimeParseException` rather than returning NaN, so catch it and return stale or `FROZEN`. Take `nowMs` from `System.currentTimeMillis()` or a ticking `State<Long>`.
- **React/Web**: This is the source: `src/lib/board-staleness.ts`, exercised by `src/lib/board-staleness.test.ts` and applied only by `src/hooks/use-board.ts`. It depends on `snapshotStaleMs` and `SNAPSHOT_STALE_FLOOR_MS` in `src/lib/snapshot-staleness.ts`. The fail-closed behavior relies on `Date.parse` returning `NaN` and the `Number.isFinite` guard.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port. Drive `nowMs` from a `Timer` or the UI layer's clock. Nothing in the module is UI-bound, so the code belongs in a shared framework target.
- **WinUI 3**: Port as a `public static class BoardStaleness` in C#. Use `public const long BoardPollIntervalMs = 60_000;`, `BoardStaleMs = 3 * BoardPollIntervalMs`, `BoardDataStaleCycles = 2`, and a `public enum BoardDataFreshness { Current, Frozen, NoData }`. Serialise it to `"no-data"` with `[JsonStringEnumMemberName]` or a converter if it crosses `System.Text.Json`. Parse with `DateTimeOffset.TryParse(generatedAt, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and treat `false` as stale or `Frozen`, since .NET has no NaN parse result. Compute ms with `t.ToUnixTimeMilliseconds()`. Take the client clock from `DateTimeOffset.UtcNow` or an injected `TimeProvider`, so tests can pin it. `dataAsOfMs` becomes `long?` and `probeIntervalMs` becomes `long?`. The view model that calls these (the `useBoard` equivalent) would re-evaluate on a `DispatcherQueueTimer` tick and raise `INotifyPropertyChanged` for the derived reason. The functions themselves stay synchronous and pure, with no `Task`.

