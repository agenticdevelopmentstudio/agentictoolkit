<!-- leaf: implement-status-web-src-lib-2/snapshot-staleness · source: status-web-src-lib-snapshot-staleness.md -->

**Rules** (cite as `implement-status-web-src-lib-2/snapshot-staleness#<slug>`):

- `freshness-type` MUST
- `stale-floor` MUST
- `window-signature` MUST
- `window-formula` MUST
- `window-unknown-interval` MUST
- `window-small-interval` MUST
- `window-scaling` MUST
- `window-mirrors-scheduler` MUST
- `freshness-signature` MUST
- `missing-last-cycle` MUST
- `missing-generated-at` MUST
- `lag-computation` MUST
- `server-clock-only` MUST
- `fresh-at-or-below-window` MUST
- `negative-lag-fresh` MUST
- `nan-fails-open` MUST
- `stale-band` MUST
- `very-stale-band` MUST
- `not-cycle-health` MUST
- `caller-banner-tone` MUST
- `caller-indicator-unknown` MUST
- `refresh-by-repoll` MUST
- `pure-functions` MUST

# Snapshot Staleness

## Overview

`snapshot-staleness.ts` (`packages/web/packages/status-web/src/lib/snapshot-staleness.ts`) is the status dashboard's single staleness rule for the live snapshot: "how stale the displayed status data is". It exports a three-valued `SnapshotFreshness` type, the constant `SNAPSHOT_STALE_FLOOR_MS`, the window function `snapshotStaleMs`, and the verdict function `snapshotFreshness`.

The doc comment calls it "the ONE staleness rule". It is shared by the board-wide `SnapshotStaleBanner` component and the usePortfolioIndicator hook, so the banner and the header/home status sign can never disagree. Both callers read `lastCycleAt`, `generatedAt` and `probeIntervalMs` off the snapshot held by useLiveSnapshot. The sibling Board Staleness module derives its data-clock window from `snapshotStaleMs`.

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

## Platform Notes

- **SwiftUI**: Port as a caseless `enum SnapshotStaleness` namespace with `static let staleFloorMs: Int64 = 300_000` and `enum SnapshotFreshness: String { case fresh, stale, veryStale = "very-stale" }`. Parse with `ISO8601DateFormatter` (add `.withFractionalSeconds`). A failed parse returns `nil` rather than NaN, so map `nil` explicitly to `.fresh` to keep the fail-open rule. Take `lastCycleAt`/`generatedAt` as `String?` so the missing-input guard is a plain optional check.
- **Compose**: Use a Kotlin `object SnapshotStaleness` with `const val STALE_FLOOR_MS = 300_000L` and `enum class SnapshotFreshness`. `Instant.parse` throws `DateTimeParseException`, so catch it and return `FRESH`. Use `maxOf((probeIntervalMs ?: 0L) * 5, STALE_FLOOR_MS)` for the window. Note that Kotlin `Long` has no NaN, so the NaN-interval edge case disappears.
- **React/Web**: This is the source: `src/lib/snapshot-staleness.ts`, exercised by `src/lib/snapshot-staleness.test.ts` (vitest). Consumed by `src/components/SnapshotStaleBanner.tsx` and `src/hooks/use-portfolio-indicator.ts`, and reused by `src/lib/board-staleness.ts`. The fail-open behavior relies on `Date.parse` returning `NaN` and the negated comparison `!(ageMs > staleMs)`.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port, placed in a shared framework target since nothing is UI-bound. The banner equivalent re-evaluates whenever the live snapshot model publishes a new value; no `Timer` is needed because the rule never reads the client clock.
- **WinUI 3**: Port as a `public static class SnapshotStaleness` in C# with `public const long StaleFloorMs = 5 * 60_000;`, `public static long StaleMs(long? probeIntervalMs) => Math.Max((probeIntervalMs ?? 0) * 5, StaleFloorMs);`, and `public enum SnapshotFreshness { Fresh, Stale, VeryStale }` (add `[JsonStringEnumMemberName("very-stale")]` if it crosses `System.Text.Json`). Parse each timestamp with `DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)`; since .NET has no NaN parse result, a `false` return must map to `Fresh` to preserve the fail-open rule. Compute the lag with `ToUnixTimeMilliseconds()` on both values; `long` arithmetic removes the NaN-interval case. Keep the functions synchronous with no `Task` and no `DateTimeOffset.UtcNow`. The view model that owns the live snapshot recomputes the verdict when a new snapshot arrives and raises `INotifyPropertyChanged` for a derived `Freshness` property, which an `InfoBar` binds to (`IsOpen` when not `Fresh`, `Severity="Warning"` for `Stale`, `Severity="Error"` for `VeryStale`).

