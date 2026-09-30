<!-- leaf: implement-status-web-hooks/use-board--test-vectors · source: status-web-hooks-use-board.md -->

# useBoard

## Conformance Test Vectors

All vectors mount the hook under a fresh `QueryClient` with `subscribeLiveFrames` mocked and the global `fetch` stubbed, as `use-board.dom.test.tsx` does. "Fresh" below means `generatedAt` = now and `dataAsOfMs` = now; `probeIntervalMs` is 60 000.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-board-001 | fetch-body-passthrough, verdict-current, reason-board-exclusive | Server returns a fresh board with one problem | `board` deep-equals the server payload; `reason` null (use-board.dom.test.tsx "renders the server's board verbatim") |
| use-board-002 | no-durable-state | Fresh board fetched successfully | `localStorage.length` is 0 after `board` is non-null |
| use-board-003 | server-removal-propagates, refetch-field | First read has 1 problem; server switched to `problems: []`, `indicator: "operational"`; caller invokes `refetch()` | `board.problems` becomes `[]` |
| use-board-004 | frame-subscription, frame-no-second-connection | Hook mounted, first fetch done; every registered frame subscriber is invoked once | `fetch` has been called exactly 2 times; no `EventSource` created |
| use-board-005 | verdict-stale, stale-threshold, error-independent-of-board | Server returns 200 with `generatedAt` = now − `BOARD_STALE_MS` − 5 000 ms | `board` null; `reason` `"stale"`; `error` null |
| use-board-006 | verdict-frozen, frozen-threshold, frozen-server-clock | Server returns fresh `generatedAt`, `dataAsOfMs` = now − `boardDataStaleMs()` − 5 000 ms, green indicator, no problems | `board` null; `reason` `"frozen"` (not `"stale"`); `error` null |
| use-board-007 | verdict-no-data | Server returns fresh `generatedAt`, `dataAsOfMs: null` | `board` null; `reason` `"no-data"` |
| use-board-008 | verdict-current | Server returns fresh `generatedAt`, `dataAsOfMs` = now − 1 000 ms, `indicator: "operational"` | `reason` null; `board.indicator` `"operational"` |
| use-board-009 | verdict-loading, single-loading-signal | `fetch` stubbed to a promise that never resolves; read result immediately after mount | `board` null; `reason` `"loading"`; result has no `isLoading` key |
| use-board-010 | fetch-http-error, verdict-unavailable, error-field, retry-once | `fetch` always returns status 500; wait for the query to settle | `fetch` called 2 times (initial + one retry); `board` null; `reason` `"unavailable"`; `error.message` is `board fetch failed: 500` |
| use-board-011 | fetch-request, query-key | Any mount | first `fetch` call has URL `/api/board` and headers `{ accept: "application/json" }` |
| use-board-012 | stale-unparseable-clock | Server returns `generatedAt: "not-a-date"`, `dataAsOfMs` = now | `board` null; `reason` `"stale"` |
| use-board-013 | stale-over-frozen | Server returns `generatedAt` = now − 200 000 ms, `dataAsOfMs` = now − 900 000 ms | `reason` `"stale"` |
| use-board-014 | frozen-threshold | `isBoardStale` false; `probeIntervalMs` 3 600 000; lag between `generatedAt` and `dataAsOfMs` = 30 000 000 ms | `reason` null (window is 36 000 000 ms); with lag 36 000 001 ms, `reason` `"frozen"` |
| use-board-015 | fetch-parse-error, verdict-unavailable | `fetch` returns status 200 with body `not json` on every call | `board` null; `reason` `"unavailable"`; `error` is a `SyntaxError` |
| use-board-016 | frame-unsubscribe | Mount then unmount the hook | the mocked frame subscriber set no longer contains the hook's callback |
| use-board-017 | retained-data-ages-out | First read returns a fresh board; every later read returns 500; advance clock past `generatedAt` + `BOARD_STALE_MS` + 30 000 ms | `board` null; `reason` `"stale"`; `error` non-null |

Vectors 001–008 are taken from assertions in `use-board.dom.test.tsx`; 012–014 are derived from `isBoardStale`, `boardDataFreshness` and `boardDataStaleMs` in `lib/board-staleness.ts` (covered by `board-staleness.test.ts`); 009–011 and 015–017 are derived from the hook source.
