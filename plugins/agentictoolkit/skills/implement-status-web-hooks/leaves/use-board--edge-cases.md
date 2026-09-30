<!-- leaf: implement-status-web-hooks/use-board--edge-cases · source: status-web-hooks-use-board.md -->

# useBoard

**Rules** (cite as `implement-status-web-hooks/use-board--edge-cases#<slug>`):

- `empty-cache-request-pending` MUST — MUST report board: null, reason: "loading".
- `empty-cache-request-failed-twice` MUST — MUST report board: null, reason: "unavailable" with error set; the poll keeps retrying every 60 000 ms.
- `unreachable-server` MUST — The rejected fetch MUST surface through error after one retry; with no cached board reason is "unavailable", and with a …
- `browser-offline` MUST — React Query pauses the fetch (fetch status paused, not fetching), so with no cached board reason MUST be "unavailable", …
- `permanently-failing-api-board-after-a-success` MUST — The last good board MUST remain the judged data and MUST read "stale" once older than BOARD_STALE_MS; it MUST NOT be …
- `wedged-monitor-healthy-api` MUST — A board re-stamped with a fresh generatedAt over an old dataAsOfMs MUST read "frozen".
- `nothing-configured-to-observe` MUST — dataAsOfMs: null MUST read "no-data", never a green board; distinguishing a fresh install from a broken monitor is left …
- `unparseable-generatedat` MUST — MUST read "stale" (fail closed in isBoardStale).
- `missing-dataasofms-field` MUST — The strict === null check does not match, the lag is NaN, and the data clock MUST read "frozen".
- `missing-probeintervalms` MUST — boardDataStaleMs MUST fall back to the widest window, 300 000 × 2 = 600 000 ms, so an unknown cadence can only delay …
- `boundary-at-exactly-board-stale-ms` MUST — An age equal to 180 000 ms MUST NOT be stale (the comparison is strictly greater than).
- `boundary-at-exactly-the-data-window` MUST — A lag equal to boardDataStaleMs(probeIntervalMs) MUST read "current".
- `client-clock-skew` MUST — A client clock running more than BOARD_STALE_MS fast MUST false-trip a healthy board to "stale"; one running more than …
- `burst-of-live-frames` MUST — Each frame MUST trigger a refetch; an in-flight read is cancelled and replaced, so a burst of N frames produces up to N …
- `several-mounted-callers` MUST — Callers sharing a QueryClient MUST share one cached board and one poll; each mounted caller adds its own frame …

## Edge Cases

- **Empty cache, request pending**: MUST report `board: null, reason: "loading"`.
- **Empty cache, request failed twice**: MUST report `board: null, reason: "unavailable"` with `error` set; the poll keeps retrying every 60 000 ms.
- **Unreachable server (network error)**: The rejected `fetch` MUST surface through `error` after one retry; with no cached board `reason` is `"unavailable"`, and with a cached board the verdict continues to judge that board until it goes stale.
- **Browser offline**: React Query pauses the fetch (fetch status paused, not fetching), so with no cached board `reason` MUST be `"unavailable"`, not `"loading"`.
- **Permanently failing `/api/board` after a success**: The last good board MUST remain the judged `data` and MUST read `"stale"` once older than `BOARD_STALE_MS`; it MUST NOT be reported as current forever.
- **Wedged monitor, healthy API**: A board re-stamped with a fresh `generatedAt` over an old `dataAsOfMs` MUST read `"frozen"`.
- **Nothing configured to observe**: `dataAsOfMs: null` MUST read `"no-data"`, never a green board; distinguishing a fresh install from a broken monitor is left to the consumer (for example `OverviewTab` pairing it with the live snapshot's `blind`).
- **Unparseable `generatedAt`**: MUST read `"stale"` (fail closed in `isBoardStale`).
- **Missing `dataAsOfMs` field (undefined rather than null)**: The strict `=== null` check does not match, the lag is NaN, and the data clock MUST read `"frozen"`.
- **Missing `probeIntervalMs`**: `boardDataStaleMs` MUST fall back to the widest window, `300 000 × 2` = 600 000 ms, so an unknown cadence can only delay the frozen verdict.
- **Boundary at exactly `BOARD_STALE_MS`**: An age equal to 180 000 ms MUST NOT be stale (the comparison is strictly greater than).
- **Boundary at exactly the data window**: A lag equal to `boardDataStaleMs(probeIntervalMs)` MUST read `"current"`.
- **Client clock skew**: A client clock running more than `BOARD_STALE_MS` fast MUST false-trip a healthy board to `"stale"`; one running more than `BOARD_STALE_MS` slow masks a stale board. This exposure is accepted and uncorrected (per the `board-staleness.ts` header); the data-clock check is immune because it uses only server timestamps.
- **Burst of live frames**: Each frame MUST trigger a refetch; an in-flight read is cancelled and replaced, so a burst of N frames produces up to N requests with only the last completing.
- **Several mounted callers**: Callers sharing a `QueryClient` MUST share one cached board and one poll; each mounted caller adds its own frame subscriber, so one frame calls `refetch` once per mounted caller, and React Query's cancel-and-refetch leaves one read completing.
- **Concurrent access**: Not applicable beyond the burst cases above — the hook runs on the browser's single JavaScript thread, so callbacks cannot interleave with the verdict computation.
- **Malformed but parseable body**: A JSON body that does not match `Board` is passed through unvalidated; only the three clock fields are checked, and they fail closed (`"stale"` or `"frozen"`) when unparseable. Conformance of the rest is the server's contract, guarded at compile time by `board-types-parity.test.ts`.
- **Hung request**: No client timeout exists; the request stays in flight until the transport ends it or a frame-triggered refetch cancels it. With a cached board, the verdict still ages the board to `"stale"` because it is judged from `useNow()`, not from request completion.
