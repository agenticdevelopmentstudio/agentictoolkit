<!-- leaf: implement-status-web-hooks/use-portfolio-indicator--test-vectors · source: status-web-hooks-use-portfolio-indicator.md -->

# usePortfolioIndicator

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
