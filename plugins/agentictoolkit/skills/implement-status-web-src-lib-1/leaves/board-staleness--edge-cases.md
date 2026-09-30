<!-- leaf: implement-status-web-src-lib-1/board-staleness--edge-cases · source: status-web-src-lib-board-staleness.md -->

# Board Staleness

**Rules** (cite as `implement-status-web-src-lib-1/board-staleness--edge-cases#<slug>`):

- `unparseable-generatedat` MUST — Date.parse returns NaN. isBoardStale MUST return true and boardDataFreshness MUST return "frozen" (fail closed).
- `empty-string-generatedat` MUST — Date.parse("") is NaN, so it takes the same fail-closed path as unparseable input and MUST read as stale or frozen.
- `null-dataasofms` MUST — The result MUST be "no-data" whatever generatedAt and probeIntervalMs are, including garbage generatedAt.
- `dataasofms-that-is-nan-or-infinite` MUST — The lag is non-finite, so boardDataFreshness MUST return "frozen".
- `nowms-that-is-nan` MUST — The age is non-finite, so isBoardStale MUST return true.
- `exact-thresholds` MUST — An age of exactly 180 000 ms, or a lag exactly equal to boardDataStaleMs, MUST read as not stale (false or "current"). …
- `clock-ahead` MUST — A generatedAt ahead of nowMs, or a dataAsOfMs ahead of generatedAt, MUST read as fresh or current. Neither function …
- `client-clock-skew-beyond-180-000-ms` MUST — A fast client clock MUST make isBoardStale return true for a healthy board. A slow one MUST make it return false for a …
- `missing-null-or-zero-probeintervalms` MUST — The data window MUST fall back to 600 000 ms. A negative interval also floors to 600 000 ms through Math.max.
- `very-large-probeintervalms` MUST — The window MUST scale linearly as probeIntervalMs * 10, with no upper cap.

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
