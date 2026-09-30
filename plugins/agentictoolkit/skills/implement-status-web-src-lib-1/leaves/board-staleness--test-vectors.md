<!-- leaf: implement-status-web-src-lib-1/board-staleness--test-vectors · source: status-web-src-lib-board-staleness.md -->

# Board Staleness

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
