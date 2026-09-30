<!-- leaf: implement-status-web-hooks/use-live-snapshot--part-2 · source: status-web-hooks-use-live-snapshot.md -->

# useLiveSnapshot — continued (part 2)

**Rules** (cite as `implement-status-web-hooks/use-live-snapshot--part-2#<slug>`):

- `poll-interval-export` MUST
- `same-snapshot-null` MUST
- `same-snapshot-identity` MUST
- `same-snapshot-clock` MUST
- `frame-subscribe` MUST
- `frame-subscribers-module-wide` MUST
- `frame-not-connection-state` MUST
- `test-reset` MUST
- `test-reset-keeps-frames` MUST
- `store-per-client` MUST
- `store-client-fixed` MUST
- `store-lookup-before-subscribe` MUST
- `fresh-view` MUST
- `server-view-stable` MUST
- `patch-no-op` MUST
- `patch-copy` MUST
- `stream-ref-count` MUST
- `stream-single` MUST
- `stream-no-window` MUST
- `stream-path` MUST
- `stream-open-event` MUST
- `stream-transient-error` MUST
- `stream-closed-error` MUST
- `stream-reopen` MUST
- `stream-reopen-single` MUST
- `stream-release` MUST
- `snapshot-frame` MUST
- `snapshot-frame-malformed` MUST
- `schedule-frame` MUST
- `schedule-frame-malformed` MUST
- `ingest-once` MUST
- `ingest-update` MUST
- `ingest-shape-precondition` MUST
- `poll-ingest` MUST
- `poll-query-key` MUST
- `poll-interval` MUST
- `poll-auto-triggers` MUST
- `poll-retry` MUST
- `fetch-request` MUST
- `fetch-http-error` MUST
- `fetch-success-clears-error` MUST
- `fetch-failure-sets-error` MUST
- `live-error-sticky` MUST
- `stream-loss-refetch` MUST
- `check-start` MUST
- `check-post-sync` MUST
- `check-no-idempotency` MUST
- `check-ran` MUST
- `check-not-ran` MUST
- `check-not-ran-refetch` MUST
- `check-started-no-refetch` MUST
- `check-resolve` MUST
- `check-unrelated-push` MUST
- `check-safety` MUST
- `check-no-error-surface` MUST

## Behavioral Requirements

### Module exports

- **poll-interval-export**: The module MUST export `POLL_INTERVAL_MS` with the value 60 000.
- **same-snapshot-null**: `isSameSnapshot(a, b)` MUST return false when `a` is null.
- **same-snapshot-identity**: `isSameSnapshot(a, b)` MUST return true when `a` and `b` are the same object.
- **same-snapshot-clock**: `isSameSnapshot(a, b)` MUST return true when `a` and `b` are distinct objects with equal `generatedAt` strings, and false when their `generatedAt` strings differ.
- **frame-subscribe**: `subscribeLiveFrames(cb)` MUST add `cb` to a module-wide subscriber set and MUST return a function that removes it.
- **frame-subscribers-module-wide**: The frame subscriber set MUST be shared by every store, so a subscriber is called for a frame ingested by any `StatusApiClient`'s store.
- **frame-not-connection-state**: Frame subscribers MUST be called only when a snapshot is ingested, never on a connection-state change (stream open, error, schedule frame).
- **test-reset**: `__resetStoreForTests()` MUST call `reset()` on every store and then empty the store registry.
- **test-reset-keeps-frames**: `__resetStoreForTests()` MUST NOT clear the frame subscriber set (per its doc comment, clearing it "would silently unsubscribe a mounted `useBoard`").

### Store registry

- **store-per-client**: Every hook call MUST resolve its store by the identity of the `StatusApiClient` returned by `useStatusApi()`, creating the store on first use and reusing it afterwards.
- **store-client-fixed**: A store MUST talk only through the client it was constructed with; the client is never reassigned by a later render.
- **store-lookup-before-subscribe**: The hook MUST resolve its store before subscribing, because subscribing may open the stream on the same tick.
- **fresh-view**: A new store's view MUST be `{ snapshot: null, streamConnected: false, nextCheckAt: null, awaitingCheck: false, liveError: null }`.
- **server-view-stable**: `getServerView()` MUST return the initial view object for the store's whole life, so server rendering and the first client paint match.
- **patch-no-op**: A view update whose every field is strictly equal (`===`) to the current value MUST NOT replace the view object or notify listeners.
- **patch-copy**: A view update that changes any field MUST replace the view with a new object and notify every listener once.

### Stream lifecycle

- **stream-ref-count**: Each store subscription MUST increment a stream reference count and open the stream; each unsubscribe MUST decrement it.
- **stream-single**: A store MUST hold at most one `EventSource`; opening while one exists MUST do nothing.
- **stream-no-window**: The store MUST NOT open a stream when `window` or `EventSource` is undefined (server rendering).
- **stream-path**: The stream MUST be opened with `apiClient.eventSource("/live/stream")`, which resolves to `/api/live/stream` with the default client.
- **stream-open-event**: An `open` event MUST set `streamConnected` to true.
- **stream-transient-error**: An `error` event while the source's `readyState` is not `CLOSED` MUST set `streamConnected` to false and MUST NOT close or recreate the source (the browser auto-retries).
- **stream-closed-error**: An `error` event while `readyState` is `CLOSED` MUST close the source, drop it from the store, and set `streamConnected` to false and `nextCheckAt` to null.
- **stream-reopen**: After a `CLOSED` error the store MUST open a new source `STREAM_REOPEN_MS` (3 000 ms) later, provided the reference count is still above zero at that moment.
- **stream-reopen-single**: A reopen MUST NOT be scheduled while one is already pending or while the reference count is zero or less.
- **stream-release**: When the reference count drops to zero or below it MUST be clamped to zero, any pending reopen cancelled, the source closed and dropped, and `streamConnected` set to false and `nextCheckAt` to null.

### Frames and ingestion

- **snapshot-frame**: A `snapshot` event's `data` MUST be parsed as JSON and ingested as a `LiveSnapshot`.
- **snapshot-frame-malformed**: A `snapshot` event whose `data` fails to parse MUST be dropped without changing the view or throwing (per the comment "the next frame (or the poll fallback) recovers").
- **schedule-frame**: A `schedule` event's `data` MUST be parsed as `{ nextCheckAt: string | null }` and MUST set `nextCheckAt` to `Date.parse(nextCheckAt)` when the value is truthy and to null otherwise.
- **schedule-frame-malformed**: A `schedule` event whose `data` fails to parse MUST be ignored, leaving `nextCheckAt` unchanged.
- **ingest-once**: `ingestOnce(snap)` MUST do nothing when `isSameSnapshot(lastIngested, snap)` is true.
- **ingest-update**: Otherwise `ingestOnce` MUST record `snap` as last ingested, set the view's `snapshot` to `snap`, and then call every frame subscriber once.
- **ingest-shape-precondition**: Snapshot bodies from the stream and the poll MUST be treated as conforming to `LiveSnapshot` by precondition: they are cast, not validated.
- **poll-ingest**: Every non-empty poll result (`data`) MUST be passed to `ingestOnce`, so a poll and a stream push of the same cycle are folded once.

### Poll fallback

- **poll-query-key**: The poll MUST be a React Query under the key `["live"]` whose query function is the store's `fetchLive`.
- **poll-interval**: The poll MUST refetch every `POLL_INTERVAL_MS` while `streamConnected` is false and MUST NOT refetch on an interval while it is true.
- **poll-auto-triggers**: Refetch on window focus, on mount and on network reconnect MUST be enabled exactly when `streamConnected` is false.
- **poll-retry**: A failed poll MUST be retried once (`retry: 1`) before the query reports an error.
- **fetch-request**: `fetchLive` MUST issue `apiClient.fetch("/live")` with no init options.
- **fetch-http-error**: A response whose `ok` is false MUST reject with an `Error` whose message is `live <status>` (for example `live 503`).
- **fetch-success-clears-error**: A successful read MUST set `liveError` to null and resolve with the parsed body.
- **fetch-failure-sets-error**: A failed read (HTTP error, network error or JSON parse error) MUST set `liveError` to the error's `message` (or `String(e)` for a non-`Error`) and rethrow.
- **live-error-sticky**: `liveError` MUST change only on a completed read, so it stays set across in-flight refetches until a read succeeds.
- **stream-loss-refetch**: Whenever `streamConnected` is false after a render (including the first render), the hook MUST call `queryClient.refetchQueries({ queryKey: ["live"] })`.
- **per-client-poll-isolation**: NEEDS REVIEW: Not implemented in source. The module header promises "two stores, never a store whose transport is re-pointed at whichever provider rendered last", but the poll's query key is `["live"]` for every client, so two stores under one `QueryClient` share one cache entry: one client's poll result is ingested into both stores, and `liveError` is recorded only in the store whose `fetchLive` ran. Settled by the owner deciding whether the key must include a client identity, and a two-provider test.

### Manual check

- **check-start**: `refresh()` MUST cancel any pending check safety timer, record the current time as the check's request time, set `awaitingCheck` to true, and send `apiClient.fetch("/live/check", { method: "POST" })`.
- **check-post-sync**: The POST MUST be issued synchronously within the `refresh()` call (before its first await).
- **check-no-idempotency**: Each `refresh()` call MUST send one POST with no body and no idempotency key; debouncing and coalescing are the backend route's behavior, reported back as `ran: false`.
- **check-ran**: The check MUST count as started when the response is OK and its JSON body does not have `ran` strictly equal to false (a missing or unparseable body counts as started).
- **check-not-ran**: When the response is not OK, the request throws, or the body has `ran: false`, the store MUST clear the request time and set `awaitingCheck` to false.
- **check-not-ran-refetch**: In the not-started case the store MUST call the poll re-read only when `streamConnected` is false.
- **check-started-no-refetch**: In the started case the store MUST NOT re-read `/live` immediately; it MUST wait for the cycle's snapshot.
- **check-resolve**: An ingested snapshot MUST clear `awaitingCheck` and the safety timer only when a check is pending and `Date.parse(snap.generatedAt)` is greater than or equal to the check's request time.
- **check-unrelated-push**: An ingested snapshot built before the check's request time MUST update `snapshot` but MUST leave `awaitingCheck` true.
- **check-safety**: In the started case, if no resolving snapshot arrives within `CHECK_SAFETY_MS` (200 000 ms), the store MUST clear the request time, set `awaitingCheck` to false, and call the poll re-read once.
- **check-no-error-surface**: A failed check MUST NOT set `liveError` or expose any error; it is indistinguishable to the caller from a debounced check.
- **overlapping-check-requests**: NEEDS REVIEW: Not implemented in source. A second `refresh()` while the first POST is still in flight has no ordering rule: the first call's completion may clear `awaitingCheck` and the request time belonging to the second, and each started call assigns its own safety timer without clearing the other's, so an earlier timer can clear the later check's spinner and only the last-assigned timer is cancelled on resolve or reset. Settled by the owner choosing an ordering rule (ignore, supersede, or queue) and a test that fires two clicks with interleaved responses.

