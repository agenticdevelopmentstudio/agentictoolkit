<!-- leaf: implement-status-web-hooks/use-board · source: status-web-hooks-use-board.md -->

**Rules** (cite as `implement-status-web-hooks/use-board#<slug>`):

- `hook-signature` MUST
- `board-field` MUST
- `reason-field` MUST
- `reason-board-exclusive` MUST
- `single-loading-signal` MUST
- `error-field` MUST
- `refetch-field` MUST
- `poll-interval-export` MUST
- `fetch-request` MUST
- `fetch-http-error` MUST
- `fetch-body-passthrough` MUST
- `fetch-parse-error` MUST
- `query-key` MUST
- `poll-cadence` MUST
- `retry-once` MUST
- `no-timeout` MUST
- `frame-subscription` MUST
- `frame-source-agnostic` MUST
- `frame-no-second-connection` MUST
- `frame-unsubscribe` MUST
- `frame-no-throttle` MUST
- `verdict-loading` MUST
- `verdict-unavailable` MUST
- `verdict-stale` MUST
- `stale-threshold` MUST
- `stale-unparseable-clock` MUST
- `stale-client-clock` MUST
- `verdict-no-data` MUST
- `verdict-frozen` MUST
- `frozen-threshold` MUST
- `frozen-unparseable-lag` MUST
- `frozen-server-clock` MUST
- `verdict-current` MUST
- `stale-over-frozen` MUST
- `error-independent-of-board` MUST
- `retained-data-ages-out` MUST
- `no-durable-state` MUST
- `server-removal-propagates` MUST
- `no-derivation` MUST
- `render-thread` MUST
- `response-shape-precondition` MUST

# useBoard

## Overview

`useBoard` (`packages/web/packages/status-web/src/hooks/use-board.ts`) is the status dashboard's one source for the server-derived `Board`. It fetches `GET /board` through the injected `StatusApiClient`, polls every `BOARD_POLL_INTERVAL_MS` (60 000 ms), and refetches immediately whenever the live transport ingests a frame. Per its doc comment it "fetches and renders; it does not derive, accumulate, or persist."

Its defining contract is that `board` is non-null only when the board can back a current claim. A board that has not arrived, whose request failed, whose read clock (`generatedAt`) has gone old, whose data clock (`dataAsOfMs`) lags the read clock past a cadence-scaled window, or that rests on no observation at all, is returned as `board: null` together with a `BoardUnavailableReason` naming which of those it is. Consumers get the staleness verdict by construction instead of each re-deriving it. The rules and thresholds themselves live in `lib/board-staleness.ts`; this hook is the single call site that applies them.

Use it anywhere a view needs the portfolio board (the overview, the header pill via `usePortfolioIndicator`, `GlobalPanel`). Word the "unknown" message per cause from `reason`; never re-apply `isBoardStale` downstream.

## Behavioral Requirements

### Public shape

- **hook-signature**: `useBoard` MUST take no arguments and MUST return a `UseBoardResult` object with exactly the fields `board`, `reason`, `error` and `refetch`.
- **board-field**: `UseBoardResult.board` MUST be of type `Board | null`.
- **reason-field**: `UseBoardResult.reason` MUST be one of `"loading"`, `"unavailable"`, `"stale"`, `"frozen"`, `"no-data"`, or `null` (the `BoardUnavailableReason` union plus null).
- **reason-board-exclusive**: `reason` MUST be null exactly when `board` is non-null, and `board` MUST be null exactly when `reason` is non-null.
- **single-loading-signal**: The hook MUST NOT expose a separate loading flag; a caller wanting a spinner MUST test `reason === "loading"` (per the doc comment on `reason`: "a separate `isLoading` would be a second way to ask one question").
- **error-field**: `UseBoardResult.error` MUST be the query's last error as an `Error`, or null when there is none.
- **refetch-field**: `UseBoardResult.refetch` MUST be a zero-argument function that triggers a refetch of the board query and returns nothing (the underlying promise is discarded with `void`).
- **poll-interval-export**: The module MUST re-export `BOARD_POLL_INTERVAL_MS` (60 000) from `lib/board-staleness.ts`.

### Fetching

- **fetch-request**: Each board read MUST issue one request for path `/board` through the `StatusApiClient` from `useStatusApi()` (resolved against the client's base path, `/api` by default), with header `accept: application/json` and no other init options.
- **fetch-http-error**: A response whose `ok` is false MUST reject the read with an `Error` whose message is exactly `board fetch failed: <status>` (for example `board fetch failed: 500`); the response body is not read.
- **fetch-body-passthrough**: A successful response MUST be returned as the parsed JSON body, unmodified, as the `Board` (the test "renders the server's board verbatim" asserts deep equality with the server payload).
- **fetch-parse-error**: A body that is not valid JSON MUST reject the read with the parse error raised by `Response.json()`.
- **query-key**: The board MUST be held in the React Query cache under the key `["board"]`, so every `useBoard` caller sharing a `QueryClient` shares one cached board and one fetch.
- **poll-cadence**: The query MUST refetch every `BOARD_POLL_INTERVAL_MS` (60 000 ms) while mounted, independent of whether the live stream is connected.
- **retry-once**: A failed read MUST be retried exactly once before the query reports an error (`retry: 1`), using React Query's default retry delay.
- **no-timeout**: The hook MUST NOT apply its own request timeout or abort signal; a hung request stays in flight until the transport ends it or a subsequent refetch cancels it.

### Live-frame refetch

- **frame-subscription**: While mounted, the hook MUST subscribe to `subscribeLiveFrames` and MUST call the query's `refetch` once for every live frame delivered.
- **frame-source-agnostic**: The frame subscription MUST fire for a frame ingested by any `StatusApiClient`'s live store, because the subscriber set is module-wide (per the comment on `frameSubscribers` in `use-live-snapshot.ts`).
- **frame-no-second-connection**: The hook MUST NOT open its own `EventSource`; it piggybacks on the live snapshot's existing feed ("one connection per tab is the existing contract").
- **frame-unsubscribe**: On unmount, and before re-subscribing when the `refetch` function identity changes, the hook MUST remove its frame subscriber.
- **frame-no-throttle**: The hook MUST NOT debounce or coalesce frames; each frame calls `refetch`, and React Query's default `cancelRefetch` behavior cancels any in-flight board read in favor of the new one.

### Availability verdict

The verdict is computed on every render from the cached `data` (the last successful board, which React Query retains across later failures) and `nowMs` from `useNow()`. The branches are evaluated in this order and the first match wins:

- **verdict-loading**: When there is no cached board and the query is in its initial load (`isLoading`: pending and fetching), `reason` MUST be `"loading"`.
- **verdict-unavailable**: When there is no cached board and the query is not in its initial load (the fetch failed after its retry, or the fetch is paused), `reason` MUST be `"unavailable"`.
- **verdict-stale**: When a cached board exists and `isBoardStale(board.generatedAt, nowMs)` is true, `reason` MUST be `"stale"`.
- **stale-threshold**: `isBoardStale` MUST return true when `nowMs - Date.parse(generatedAt)` is greater than `BOARD_STALE_MS` (180 000 ms, three poll cycles), and false when it is less than or equal.
- **stale-unparseable-clock**: `isBoardStale` MUST return true (fail closed) when `generatedAt` does not parse to a finite age.
- **stale-client-clock**: The read-clock check MUST be judged against the client's wall clock as sampled by `useNow()` at its default 30 000 ms refresh, so a board is reported stale no later than about 30 s after it crosses `BOARD_STALE_MS`.
- **verdict-no-data**: When the board is not stale and `board.dataAsOfMs` is null, `reason` MUST be `"no-data"`.
- **verdict-frozen**: When the board is not stale and `boardDataFreshness(board.dataAsOfMs, board.generatedAt, board.probeIntervalMs)` returns `"frozen"`, `reason` MUST be `"frozen"`.
- **frozen-threshold**: The data clock MUST read `"frozen"` when `Date.parse(generatedAt) - dataAsOfMs` is greater than `boardDataStaleMs(probeIntervalMs)`, which equals `max(probeIntervalMs × 5, 300 000) × 2` ms (600 000 ms at the default 60 000 ms cadence).
- **frozen-unparseable-lag**: The data clock MUST read `"frozen"` when the lag between `generatedAt` and `dataAsOfMs` is not a finite number.
- **frozen-server-clock**: The data-clock check MUST compare two server timestamps carried on the board being judged (`generatedAt` and `dataAsOfMs`), using the cadence carried on that same board (`probeIntervalMs`), and MUST NOT depend on the client clock or on the live snapshot.
- **verdict-current**: When the board is not stale and its data clock reads `"current"`, `reason` MUST be null and `board` MUST be the cached board object, unmodified.
- **stale-over-frozen**: When a board is both stale and frozen, `reason` MUST be `"stale"`, because the read-clock check is evaluated first.
- **error-independent-of-board**: `error` MUST reflect the query's error state independently of the verdict, so a board that is still current from an earlier successful read MAY be returned alongside a non-null `error` from a later failed poll.
- **retained-data-ages-out**: A board retained from an earlier success while later polls fail MUST keep being judged on each render, and MUST become `board: null, reason: "stale"` once its `generatedAt` crosses `BOARD_STALE_MS`.

### State and persistence

- **no-durable-state**: The hook MUST NOT write to `localStorage` or any other durable client store (the test "writes NOTHING to localStorage" asserts `localStorage.length` stays 0); the only board storage is the in-memory React Query cache.
- **server-removal-propagates**: A problem absent from the next server read MUST be absent from the returned board after that read, with no client-side accumulation.
- **no-derivation**: The hook MUST NOT derive, merge or filter board contents; all content derivation belongs to the server.
- **render-thread**: All verdict computation MUST run synchronously during render on the browser's single JavaScript thread; the live-frame callback, the poll timer and the `useNow` interval MUST only schedule React state updates and cannot interleave with a render.
- **response-shape-precondition**: The hook MUST treat the response body's conformance to `Board` as a caller precondition: the body is cast, not validated, and the `Board` type is kept in step with the server's type by the compile-time drift guard in `board-types-parity.test.ts`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiClient` (via `StatusApiProvider` / `useStatusApi()`) | injected dependency | same-origin client with base path `/api` | Resolves `/board` against the host's base path; a test double can be injected |
| `QueryClient` (via `QueryClientProvider`) | injected dependency | none (required) | Holds the `["board"]` cache; callers sharing it share one board |
| `BOARD_POLL_INTERVAL_MS` | constant (ms) | `60000` | Poll cadence (`refetchInterval`) |
| `BOARD_STALE_MS` | constant (ms) | `180000` | Read-clock staleness threshold (3 × poll cadence) |
| `BOARD_DATA_STALE_CYCLES` | constant | `2` | Multiplier on `snapshotStaleMs` for the data-clock window |
| `SNAPSHOT_STALE_FLOOR_MS` | constant (ms) | `300000` | Floor of `snapshotStaleMs`, and the window used when `probeIntervalMs` is missing |
| `retry` | React Query option | `1` | Retries before an error is reported |
| `useNow` interval | number (ms) | `30000` | Client clock refresh used for the read-clock check (default argument, not overridden by this hook) |
| `Board.probeIntervalMs` | server-supplied field | — | Cadence that scales the data-clock window, taken from the board being judged |

