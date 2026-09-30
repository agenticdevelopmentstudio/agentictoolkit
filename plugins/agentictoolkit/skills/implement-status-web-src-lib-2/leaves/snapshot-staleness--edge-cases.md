<!-- leaf: implement-status-web-src-lib-2/snapshot-staleness--edge-cases · source: status-web-src-lib-snapshot-staleness.md -->

# Snapshot Staleness

**Rules** (cite as `implement-status-web-src-lib-2/snapshot-staleness--edge-cases#<slug>`):

- `null-undefined-or-empty-lastcycleat` MUST — MUST return "fresh". A zero-endpoint monitor, or an older backend that predates the field, never shows the banner.
- `null-undefined-or-empty-generatedat` MUST — MUST return "fresh".
- `unparseable-timestamp` MUST — Date.parse yields NaN, every comparison is false, and the result MUST be "fresh" (fail open). This deliberately differs …
- `lag-exactly-equal-to-the-window` MUST — MUST be "fresh"; the comparison is strict greater-than.
- `lag-exactly-equal-to-three-times-the-window` MUST — MUST be "stale", not "very-stale".
- `negative-lag` MUST — MUST be "fresh"; there is no lower bound.
- `probeintervalms-of-0-or-negative` MUST — The window MUST floor to 300 000 ms through Math.max.
- `probeintervalms-of-nan` MUST — NaN * 5 is NaN and Math.max returns NaN, so the window is NaN and snapshotFreshness MUST return "fresh" for every lag. …
- `very-large-or-infinite-probeintervalms` MUST — The window MUST scale linearly as probeIntervalMs * 5 with no cap. An infinite interval yields an infinite window, so …
- `client-clock-skew-or-a-sleeping-tab` MUST — MUST NOT affect the verdict; the client clock is never read.
- `wedged-poller` MUST — Each re-pulled snapshot carries a newer generatedAt while lastCycleAt stays frozen, so the lag MUST keep growing and …

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
