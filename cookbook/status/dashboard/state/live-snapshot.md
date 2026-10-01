---
id: ca7205d2-31c0-424a-95a2-a356bed30187
title: Live Snapshot
domain: agentictoolkit://cookbook/status/dashboard/state/live-snapshot
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Cached state, shared per API client, that feeds the latest live snapshot
  from a server-push stream with a 60 s poll fallback.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/api
- agentictoolkit://cookbook/status/dashboard/state/board
references: []
approved-by: ''
approved-date: ''
---

# Live Snapshot

## Overview

Live Snapshot is the status dashboard's transport for the latest `LiveSnapshot` — "what did the last probe cycle see" (services, deployments, `lastCycleAt`, `probeIntervalMs`, `monitorVersion`, `configDegraded`). It is used by several views at once (the header pill, the overview view, the dashboard view, the board shell, the stale banners, the portfolio indicator state), so its state lives in one store per API client, not per view.

The primary feed is one reference-counted server-push stream connection to `/live/stream`, over which the backend pushes a snapshot notification on every cycle and webhook plus a schedule notification with the next cycle time. The fallback is a poll of the shared cache against `GET /live` every 60 s, gated off while the stream is connected. Live Snapshot also exposes a manual full check (`refresh`, `POST /live/check`) whose spinner holds until the caller's own result lands, and a cheap reachability re-read (`reconnect`).

Live Snapshot does not fold notifications into a durable model; the board state answers "what is wrong" and piggybacks on this feed through frame subscription rather than opening a second connection.

## Behavioral Requirements

### Named configuration

- **poll-interval-export**: Live Snapshot MUST define a named interval constant, `POLL_INTERVAL_MS`, with the value 60,000.
- **same-snapshot-null**: The same-snapshot check MUST return false when the first snapshot compared is null.
- **same-snapshot-identity**: The same-snapshot check MUST return true when the two snapshots compared are the same object.
- **same-snapshot-clock**: The same-snapshot check MUST return true when the two snapshots are distinct objects with equal `generatedAt` strings, and false when their `generatedAt` strings differ.
- **frame-subscribe**: Frame subscription MUST add a callback to a shared subscriber set and MUST return a function that removes it.
- **frame-subscribers-module-wide**: The frame subscriber set MUST be shared by every store, so a subscriber is called for a snapshot ingested by any client's store.
- **frame-not-connection-state**: Frame subscribers MUST be called only when a snapshot is ingested, never on a connection-state change (stream open, error, schedule notification).
- **test-reset**: The test-reset operation MUST reset every store and then empty the store registry.
- **test-reset-keeps-frames**: The test-reset operation MUST NOT clear the frame subscriber set, because clearing it would silently unsubscribe a mounted board state.

### Store registry

- **store-per-client**: Every use of Live Snapshot MUST resolve its store by the identity of the client returned from the app's API context, creating the store on first use and reusing it afterward.
- **store-client-fixed**: A store MUST talk only through the client it was constructed with; the client is never reassigned later.
- **store-lookup-before-subscribe**: Live Snapshot MUST resolve its store before subscribing, because subscribing may open the stream in the same step.
- **fresh-view**: A new store's view MUST be `{ snapshot: null, streamConnected: false, nextCheckAt: null, awaitingCheck: false, liveError: null }`.
- **server-view-stable**: A store's server-rendering view MUST return the initial view object for the store's whole life, so a universal-rendering pass and the first client paint match.
- **patch-no-op**: A view update whose every field is strictly equal to the current value MUST NOT replace the view object or notify listeners.
- **patch-copy**: A view update that changes any field MUST replace the view with a new object and notify every listener once.

### Stream lifecycle

- **stream-ref-count**: Each store subscription MUST increment a stream reference count and open the stream connection; each unsubscribe MUST decrement it.
- **stream-single**: A store MUST hold at most one open stream connection; opening while one exists MUST do nothing.
- **stream-no-window**: The store MUST NOT open a stream connection when no live client execution environment for streaming is available (during server rendering).
- **stream-path**: The stream connection MUST be opened by asking the client for a stream connection to `/live/stream`, which resolves to `/api/live/stream` with the default client.
- **stream-open-event**: The stream connection becoming open MUST set `streamConnected` to true.
- **stream-transient-error**: A transient connection error (one that leaves the connection not permanently closed) MUST set `streamConnected` to false and MUST NOT close or recreate the connection; the underlying transport auto-retries.
- **stream-closed-error**: A terminal connection error (one that leaves the connection permanently closed) MUST close the connection, drop it from the store, and set `streamConnected` to false and `nextCheckAt` to null.
- **stream-reopen**: After a terminal connection error the store MUST open a new connection `STREAM_REOPEN_MS` (3,000 ms) later, provided the reference count is still above zero at that moment.
- **stream-reopen-single**: A reopen MUST NOT be scheduled while one is already pending or while the reference count is zero or less.
- **stream-release**: When the reference count drops to zero or below it MUST be clamped to zero, any pending reopen cancelled, the connection closed and dropped, and `streamConnected` set to false and `nextCheckAt` to null.

### Notifications and ingestion

- **snapshot-frame**: A snapshot notification's payload MUST be parsed as JSON and ingested as a `LiveSnapshot`.
- **snapshot-frame-malformed**: A snapshot notification whose payload fails to parse MUST be dropped without changing the view or raising an error (the next notification, or the poll fallback, recovers).
- **schedule-frame**: A schedule notification's payload MUST be parsed as an object with a `nextCheckAt` field (a date string or null), and MUST set `nextCheckAt` to that value's parsed timestamp when present, and to null otherwise.
- **schedule-frame-malformed**: A schedule notification whose payload fails to parse MUST be ignored, leaving `nextCheckAt` unchanged.
- **ingest-once**: Snapshot ingestion MUST do nothing when the incoming snapshot is the same as the last ingested one, under the same-snapshot check.
- **ingest-update**: Otherwise, ingestion MUST record the incoming snapshot as last ingested, set the view's `snapshot` to it, and then notify every frame subscriber once.
- **ingest-shape-precondition**: Snapshot bodies from the stream and the poll MUST be treated as conforming to `LiveSnapshot` by precondition — assumed rather than verified at runtime.
- **poll-ingest**: Every non-empty poll result MUST be passed through snapshot ingestion, so a poll result and a stream push for the same cycle are folded into one update.

### Poll fallback

- **poll-query-key**: The poll MUST be cached under the key `["live"]`, reading through the store's live-read operation.
- **poll-interval**: The poll MUST refetch every `POLL_INTERVAL_MS` while `streamConnected` is false and MUST NOT refetch on an interval while it is true.
- **poll-auto-triggers**: Refresh on returning focus, on first use, and on network reconnection MUST be enabled exactly when `streamConnected` is false.
- **poll-retry**: A failed poll MUST be retried once before the query reports an error.
- **fetch-request**: The live read MUST issue a request to `/live` with no added options.
- **fetch-http-error**: A response that is not successful MUST fail with an error whose message is `live <status>` (for example `live 503`).
- **fetch-success-clears-error**: A successful read MUST set `liveError` to null and resolve with the parsed body.
- **fetch-failure-sets-error**: A failed read (an unsuccessful response, a network failure, or a parse failure) MUST set `liveError` to that failure's message text and propagate the failure.
- **live-error-sticky**: `liveError` MUST change only on a completed read, so it stays set across in-flight refetches until a read succeeds.
- **stream-loss-refetch**: Whenever `streamConnected` is false after Live Snapshot's state is re-evaluated (including the first time), it MUST trigger a re-read of the live cache key.
- **per-client-poll-isolation**: NEEDS REVIEW: Not implemented in source. The module header promises "two stores, never a store whose transport is re-pointed at whichever provider rendered last", but the poll's query key is `["live"]` for every client, so two stores under one `QueryClient` share one cache entry: one client's poll result is ingested into both stores, and `liveError` is recorded only in the store whose `fetchLive` ran. Settled by the owner deciding whether the key must include a client identity, and a two-provider test.

### Manual check

- **check-start**: The manual check operation MUST cancel any pending check safety timer, record the current time as the check's request time, set `awaitingCheck` to true, and send a POST request to `/live/check`.
- **check-post-sync**: The request MUST be issued synchronously within the manual check operation, before any other asynchronous step.
- **check-no-idempotency**: Each manual check MUST send one POST with no body and no idempotency key; debouncing and coalescing are the backend route's behavior, reported back as `ran: false`.
- **check-ran**: The check MUST count as started when the response is OK and its JSON body does not have `ran` strictly equal to false (a missing or unparseable body counts as started).
- **check-not-ran**: When the response is not OK, the request fails, or the body has `ran: false`, the store MUST clear the request time and set `awaitingCheck` to false.
- **check-not-ran-refetch**: In the not-started case the store MUST call the poll re-read only when `streamConnected` is false.
- **check-started-no-refetch**: In the started case the store MUST NOT re-read `/live` immediately; it MUST wait for the cycle's snapshot.
- **check-resolve**: An ingested snapshot MUST clear `awaitingCheck` and the safety timer only when a check is pending and the snapshot's `generatedAt` timestamp is greater than or equal to the check's request time.
- **check-unrelated-push**: An ingested snapshot with a `generatedAt` before the check's request time MUST update `snapshot` but MUST leave `awaitingCheck` true.
- **check-safety**: In the started case, if no resolving snapshot arrives within `CHECK_SAFETY_MS` (200,000 ms), the store MUST clear the request time, set `awaitingCheck` to false, and call the poll re-read once.
- **check-no-error-surface**: A failed check MUST NOT set `liveError` or expose any error; it is indistinguishable to the caller from a debounced check.
- **overlapping-check-requests**: NEEDS REVIEW: Not implemented in source. A second `refresh()` while the first POST is still in flight has no ordering rule: the first call's completion may clear `awaitingCheck` and the request time belonging to the second, and each started call assigns its own safety timer without clearing the other's, so an earlier timer can clear the later check's spinner and only the last-assigned timer is cancelled on resolve or reset. Settled by the owner choosing an ordering rule (ignore, supersede, or queue) and a test that fires two clicks with interleaved responses.

### Reconnect

- **reconnect-read**: The reconnect operation MUST trigger a re-read of the live cache key and MUST NOT send a POST to `/live/check`.
- **reconnect-stable**: The reconnect operation MUST keep a stable identity while the shared cache context is unchanged, and the manual check operation MUST keep a stable identity while the store and reconnect operation are unchanged.

### Returned value

- **result-shape**: Live Snapshot MUST take no arguments and return a result with exactly the fields `snapshot`, `offline`, `disconnected`, `blind`, `offlineDetail`, `polling`, `nextPollAt`, `refresh` and `reconnect`.
- **result-snapshot**: `snapshot` MUST be the store view's last ingested snapshot, or null before any ingestion.
- **result-offline**: `offline` MUST be true exactly when `liveError` is non-null, `streamConnected` is false, and the poll read is not in flight.
- **result-disconnected**: `disconnected` MUST be true exactly when `liveError` is non-null and `streamConnected` is false, regardless of whether a read is in flight.
- **result-blind**: `blind` MUST be true exactly when `snapshot` is non-null and `snapshot.services` is empty.
- **result-offline-detail**: `offlineDetail` MUST equal `liveError` when `disconnected` is true and null otherwise.
- **result-polling**: `polling` MUST be true when a poll read is in flight or `awaitingCheck` is true.
- **result-next-poll-streaming**: While `streamConnected` is true, `nextPollAt` MUST be `nextCheckAt` when it is non-null, and the client estimate otherwise.
- **result-next-poll-fallback**: While `streamConnected` is false, `nextPollAt` MUST be the client estimate.
- **client-estimate**: The client estimate MUST be the poll's last successful read time plus `POLL_INTERVAL_MS` when that time is known, and null otherwise.

### Threading, persistence, side effects

- **single-thread**: All store mutation MUST run on a single execution thread, from event callbacks, timers and asynchronous continuations; store code cannot interleave with itself.
- **no-persistence**: Live Snapshot MUST NOT persist any of its state to durable storage; all state is in memory for as long as the app runs, and is lost on reload.
- **no-timeout**: Neither the live read nor the check request MUST apply a client request timeout or cancellation signal; only the check's safety timer bounds the spinner.
- **side-effects**: The only network side effects MUST be the stream connection to `/live/stream`, a GET to `/live`, and a POST to `/live/check`, all through the injected client.

## Appearance

Not applicable — this is cached state with no rendered output, not a visual component.

## States

Not applicable — this is cached state whose runtime connection and check states are listed under Behavioral Requirements, not a visual component.

## Accessibility

Not applicable — this is cached state with no rendered output, not a visual component.

## Conformance Test Vectors

Vectors 001–004 exercise the same-snapshot check directly. 005–020 assume a test double for the stream connection and the read transport, with the store reset between cases.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-live-snapshot-001 | same-snapshot-null | The same-snapshot check compares null against a snapshot with `generatedAt` `2026-06-30T00:00:00.000Z` | `false` |
| use-live-snapshot-002 | same-snapshot-identity | The same-snapshot check compares a snapshot against itself | `true` |
| use-live-snapshot-003 | same-snapshot-clock | Two distinct snapshot objects, both `generatedAt` `2026-06-30T00:00:00.000Z` | `true` |
| use-live-snapshot-004 | same-snapshot-clock | `generatedAt` `2026-06-30T00:00:00.000Z` vs `2026-06-30T00:01:00.000Z` | `false` |
| use-live-snapshot-005 | stream-path, stream-open-event, snapshot-frame, ingest-update | Use Live Snapshot; the stream opens, then delivers a snapshot with `generatedAt` `2030-01-01T00:00:00.000Z` and one service | Stream opened at `/api/live/stream`; `snapshot.generatedAt` equals that value; `snapshot.services` has length 1 |
| use-live-snapshot-006 | schedule-frame, result-next-poll-streaming | The stream opens, then delivers a schedule notification with `nextCheckAt` `"2030-06-01T00:00:00.000Z"` | `nextPollAt` equals the parsed timestamp of `2030-06-01T00:00:00.000Z` |
| use-live-snapshot-007 | check-start, check-post-sync, result-polling, check-resolve | Stream open, initial poll settled; call the manual check; then deliver a snapshot generated 5 s in the future | POST to `/api/live/check` sent synchronously; `polling` true; after the snapshot arrives, `polling` false |
| use-live-snapshot-008 | check-safety | With simulated time, call the manual check (reported as started); advance time 60,000 ms; then deliver a snapshot generated 90 s in the future | `polling` still true after 60 s; false after the snapshot arrives |
| use-live-snapshot-009 | check-started-no-refetch | No stream connection; poll settled; clear the record of requests; call the manual check (reported as started) | Zero GET requests to `/api/live` after the POST |
| use-live-snapshot-010 | stream-closed-error, stream-reopen | With simulated time; use Live Snapshot; report a terminal connection error; advance time 3,000 ms | 2 stream connections created in total |
| use-live-snapshot-011 | stream-transient-error | With simulated time; use Live Snapshot; report a transient connection error; advance time 10,000 ms | 1 stream connection in total |
| use-live-snapshot-012 | check-not-ran, check-not-ran-refetch | Stream not connected; call the manual check; the response reports `ran: false` | `polling` returns to false once the poll settles; one GET to `/api/live` issued after the POST |
| use-live-snapshot-013 | fetch-http-error, fetch-failure-sets-error, result-offline, result-disconnected, result-offline-detail | No stream; every GET to `/api/live` returns 503; the poll settles | `offline` true; `disconnected` true; `offlineDetail` is `"live 503"` |
| use-live-snapshot-014 | fetch-success-clears-error, live-error-sticky | After 013, the next GET to `/api/live` returns 200 with a snapshot | `offlineDetail` becomes null; `disconnected` becomes false; during the in-flight retry `disconnected` stayed true while `offline` was false |
| use-live-snapshot-015 | result-blind | Ingest a snapshot with `services: []` | `blind` true; with one service `blind` false; before any snapshot `blind` false |
| use-live-snapshot-016 | check-unrelated-push | Call the manual check (reported as started); deliver a snapshot generated one minute before the call | `snapshot` updated; `polling` stays true |
| use-live-snapshot-017 | snapshot-frame-malformed | The stream delivers a snapshot notification whose payload is not valid JSON | No error raised; `snapshot` unchanged; no frame subscriber called |
| use-live-snapshot-018 | ingest-once, frame-subscribe | Subscribe a counter to frame notifications; ingest the same snapshot once from the stream and once from the poll | Counter is 1 |
| use-live-snapshot-019 | stream-ref-count, stream-single, stream-release | Use Live Snapshot twice under one client; stop using it once; then stop using it again | 1 stream connection in total; still open after the first stop; closed after the second |
| use-live-snapshot-020 | client-estimate, result-next-poll-fallback | No stream; the poll succeeds with its last-success time at T | `nextPollAt` equals T + 60,000 |

## Edge Cases

- **Nothing received yet**: `snapshot` MUST be null, `blind` false, `offline` false, and `nextPollAt` null until the first poll completes.
- **Server rendering**: No stream connection MUST open, because no live client execution environment for streaming is present; the server-rendering view returns the fresh view, so a universal-rendering pass shows the pre-anything state.
- **Stream open before first schedule notification**: `nextPollAt` MUST fall back to the client estimate.
- **Schedule notification with `nextCheckAt: null`**: `nextCheckAt` MUST become null, and `nextPollAt` falls back to the client estimate.
- **Schedule notification with an unparseable date string**: The payload parses, but the date does not resolve to a valid timestamp, and `nextPollAt` MUST become that invalid-timestamp value (the fallback applies only to a missing value, not an invalid one); because an invalid timestamp never equals itself, each such notification MUST re-notify listeners.
- **Snapshot with an unparseable `generatedAt`**: It MUST be ingested, but it cannot resolve a pending check, since an invalid timestamp never compares as greater than or equal to the check's request time; the safety timer clears the spinner.
- **Malformed snapshot or schedule notification**: MUST be dropped silently, as declared for this concept; recovery comes from the next notification or the poll.
- **Re-delivered notification**: A notification with the same `generatedAt` as the last ingested MUST be skipped, including a poll result racing a stream push of the same cycle.
- **Out-of-order notifications**: A snapshot with an older `generatedAt` than the last ingested MUST still replace `snapshot`; only equality is checked.
- **Backend unreachable (network error)**: The poll MUST set `liveError` to the failure's message after one retry; with the stream down, `disconnected` is true and `offline` is true between probes.
- **Auth expiry or 5xx on stream connect**: The underlying transport closes the connection; the store MUST reopen it every 3,000 ms for as long as it is referenced, with no backoff growth and no retry limit.
- **Transient network drop on the stream**: The underlying transport reconnects on its own; the store MUST only mark `streamConnected` false, which re-enables the poll and triggers an immediate re-read.
- **Last subscriber stops using it during a pending reopen**: The reopen MUST be cancelled and no new connection opened.
- **Check request fails (network or non-OK)**: The spinner MUST clear at once; no error is surfaced to the caller.
- **Check request OK with a non-JSON body**: MUST count as started, since there is no body from which to read `ran: false`.
- **Check started but its snapshot never arrives (stream wedged)**: The spinner MUST clear after 200,000 ms and a re-read MUST be issued.
- **Two overlapping manual checks**: See the open question on overlapping-check-requests.
- **Two providers under one shared cache context**: See the open question on per-client-poll-isolation.
- **Running the test-reset operation with a check in flight**: The in-flight request's continuation is not cancelled; when it completes it MAY patch the fresh view and MAY start a new safety timer that later calls the captured re-read.
- **Hung `GET /live` or check request**: No client timeout MUST apply; `polling` stays true while the read is in flight.
- **Concurrent access**: Single execution thread; synchronous store code cannot interleave, and the only asynchronous overlaps are those two open questions.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| Status API client | injected dependency | same-origin client, base path `/api` | Resolves `/live`, `/live/check` and `/live/stream`; also the store key |
| Shared cache context | injected dependency | none (required) | Holds the `["live"]` poll cache |
| `POLL_INTERVAL_MS` | named constant (ms) | `60000` | Fallback poll cadence and client-estimate offset |
| `CHECK_SAFETY_MS` | named constant (ms) | `200000` | Spinner backstop for a started check (the backend's cycle budget is max(3× probe interval, 2 min), plus margin) |
| `STREAM_REOPEN_MS` | named constant (ms) | `3000` | Delay before recreating a permanently closed stream connection |
| Poll retry count | number | `1` | Poll retries before an error is reported |
| Streaming support | environment capability | platform-provided | Absent (server rendering, some test environments) means no stream connection and poll only |

## Deep Linking

Not applicable: Live Snapshot has no route or URL of its own; it only calls the `/live`, `/live/check` and `/live/stream` API paths.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `live <status>` | Message text of an unsuccessful `GET /live`, surfaced as `offlineDetail` for the reconnect overlay's detail line; a hardcoded English string with no localization lookup |

## Accessibility Options

Not applicable: Live Snapshot renders nothing and responds to no display settings.

## Feature Flags

Not applicable: Live Snapshot reads no feature flag.

## Analytics

Not applicable: Live Snapshot emits no analytics events.

## Privacy

Not applicable: Live Snapshot attaches no credentials, identifiers or request body of its own and persists nothing on the client; snapshots are held only in memory for as long as the app runs.

## Logging

Not applicable: Live Snapshot makes no log calls; failures surface only through `liveError`, `offline`, `disconnected` and `offlineDetail`.

## Platform Notes

- **SwiftUI**: A `@MainActor @Observable` store per API client (a dictionary keyed by `ObjectIdentifier`), exposing the same fields. Consume the stream with `URLSession.bytes(for:)` and parse SSE lines yourself (there is no `EventSource`), decoding with `JSONDecoder`; the ref count maps to `.task` start and cancellation. Run the fallback poll as a `Task` loop with `Task.sleep(for: .seconds(60))` gated on `streamConnected`, and model the safety and reopen timers as cancellable `Task`s. There is no React Query, so the one-retry policy, `isFetching` and `dataUpdatedAt` must be tracked explicitly.
- **Compose**: A singleton-per-client repository exposing `StateFlow<LiveView>`; OkHttp's `okhttp-sse` `EventSources.createFactory` for the stream, Ktor or Retrofit plus `kotlinx.serialization` for `/live` and `/live/check`. Ref-count collectors with `shareIn(scope, SharingStarted.WhileSubscribed())`, which also closes the stream when the last collector leaves. Poll with a coroutine `delay(60_000)` loop and use `Job`s for the 200 s and 3 s timers.
- **React/Web**: Source platform. `hooks/use-live-snapshot.ts` bridges a closure store into React with `useSyncExternalStore` (subscribe opens the stream) and runs the fallback with `@tanstack/react-query` v5 `useQuery`. The client comes from `api/client.ts` (`useStatusApi`, `createStatusApiClient`), the types from `lib/live-types.ts`, and `useBoard` consumes `subscribeLiveFrames`. The stream is a browser `EventSource` on `/live/stream`; "transient" versus "terminal" connection errors correspond to its `readyState` being anything other than `CLOSED` versus exactly `CLOSED`, and "no live client execution environment" corresponds to `window`/`EventSource` being undefined (server rendering). Notification payloads are parsed with `JSON.parse` on the event's `data`; the schedule notification's timestamp is `Date.parse(nextCheckAt)`, which yields `NaN` for an unparseable string — and `NaN !== NaN` is exactly why such a frame re-notifies listeners every time. The poll re-reads call `queryClient.refetchQueries({ queryKey: ["live"] })`; the client estimate reads the query's `dataUpdatedAt` and `isFetching` fields. The store's own functions are `isSameSnapshot`, `ingestOnce`, `fetchLive`, `subscribeLiveFrames` and `__resetStoreForTests`; the live-read request is `apiClient.fetch("/live")`, and the manual check is `apiClient.fetch("/live/check", { method: "POST" })`. Vectors 001–004 come from `use-live-snapshot.test.ts`; 005–011 from `use-live-snapshot.dom.test.tsx` (a mock `EventSource`, stubbed `fetch`, `__resetStoreForTests()` after each case); the rest are derived from the source.
- **AppKit / UIKit**: The same `@MainActor` store as SwiftUI, observed via `withObservationTracking` or Combine `@Published`; ref-count from view-controller appearance or explicit `acquire`/`release`. Use `Timer` or `Task` for the poll, safety and reopen timers.
- **WinUI 3**: A `LiveSnapshotStore` class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), one instance per API client held in a `ConcurrentDictionary<ApiClient, LiveSnapshotStore>` or registered in `Microsoft.Extensions.DependencyInjection`. .NET has no `EventSource`, so read the stream with `HttpClient.GetStreamAsync("live/stream")` (or `SendAsync` with `HttpCompletionOption.ResponseHeadersRead`) and parse `event:`/`data:` lines with a `StreamReader` (or `System.Net.ServerSentEvents.SseParser` on .NET 9+); you must implement both reconnect paths yourself, since nothing auto-retries. Deserialize with `System.Text.Json` `JsonSerializer.Deserialize<LiveSnapshot>` (which, unlike the source's cast, throws on type mismatch). Poll with `PeriodicTimer(TimeSpan.FromSeconds(60))` in an `async Task` loop gated on `StreamConnected`, send the check with `HttpClient.PostAsync("live/check", null)`, and model the 200 s safety and 3 s reopen timers with `Task.Delay` plus a `CancellationTokenSource` per timer. Ref-count with `Acquire()`/`Release()` called from each page's `Loaded`/`Unloaded`. Raise `PropertyChanged` on the UI thread via `DispatcherQueue.TryEnqueue`, and expose `Refresh` and `Reconnect` as `IRelayCommand`s. Keying the poll by client is up to you here, so the shared-`["live"]`-key issue does not carry over by default.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-live-snapshot.ts` |

## Design Decisions

**Decision**: Keep one store per API client in a shared registry instead of per-view state.
**Rationale**: Live Snapshot is used by several views; per-view state would fork the store and open one connection each. Keying by client identity lets a host with two backends get two stores (module header comment).
**Approved**: pending

**Decision**: Treat the server-push stream as the primary feed and gate every poll trigger off while it is connected.
**Rationale**: The backend pushes on every cycle and webhook; polling alongside it is redundant work. Idempotent ingestion makes a stray poll harmless (comment on the poll's read step).
**Approved**: pending

**Decision**: Recreate the stream connection after a terminal connection error, but not after a transient one.
**Rationale**: The underlying transport auto-retries network drops but never a non-200 connect (auth expiry, 5xx); without the recreate the tab is "stuck on the poll forever". This decision is specific to platforms whose streaming transport does not itself distinguish and auto-retry these two cases (the web platform's `EventSource`); a platform-native implementation should keep the same two-case distinction.
**Approved**: pending

**Decision**: Own `liveError` in the store instead of reading the shared cache's own error flag.
**Rationale**: On a cold board the shared cache resets to pending at each refetch, so an error flag held too briefly for the reconnect overlay's 1.2 s show delay and the board sat on "Loading…" through a redeploy (doc comment on `liveError`).
**Approved**: pending

**Decision**: Expose both `offline` (drops during an in-flight read) and `disconnected` (stable across reads).
**Rationale**: `offline` drives the stop sign; the reconnect overlay needs a signal that does not strobe during each probe so its outage clock keeps accumulating (doc comment on `disconnected`).
**Approved**: pending

**Decision**: Hold the manual-check spinner until a snapshot built at or after the click lands, with a 200,000 ms backstop, and do not re-read immediately on a started check.
**Rationale**: The check-start request returns as soon as the detached cycle starts, so an immediate re-read fetches the pre-cycle snapshot. The old 12 s backstop fired on nearly every check while providers were still being polled (doc comment on `CHECK_SAFETY_MS`).
**Approved**: pending

**Decision**: Separate `refresh` (full check) from `reconnect` (re-read).
**Rationale**: An auto-retry loop over a down backend has to stay a light read, never a repeated provider fan-out (comment on `reconnect`).
**Approved**: pending

**Decision**: Publish notifications through a shared frame-subscription set instead of the store's listener set.
**Rationale**: The board state refetches on notifications without opening a second connection ("one connection per tab is the existing contract"). The store's listeners also fire on connection-state changes, which should not trigger a board refetch.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | performance |

**Unit Test Coverage**: The tests cover `isSameSnapshot`, stream open and snapshot ingestion, the schedule frame, the manual-check spinner and its long backstop, the absence of an immediate re-read after a started check, and the `CLOSED` versus `CONNECTING` reconnect paths. Nothing asserts `liveError`, `offline`, `disconnected`, `blind`, overlapping checks, or two-client isolation.

**Separation of Concerns**: Transport sits behind `StatusApiClient`, caching behind React Query, and board derivation in `useBoard`. This module only moves snapshots and connection state.

**Explicit Error Handling**: Poll failures are recorded in `liveError` and surfaced. Malformed frames are dropped by declared design, and a failed manual check is folded into the not-started path with no signal to the caller.

**Graceful Degradation and Error Recovery**: A dead stream falls back to the poll with an immediate re-read, and a permanently closed stream is recreated every 3 s while referenced.

**Idempotent Operations**: `ingestOnce` folds re-delivered and duplicated frames exactly once across all mounted hooks and StrictMode double effects.

**Timeout Handling**: The check spinner is bounded by `CHECK_SAFETY_MS`, but neither request has a client timeout.

**Resource Efficiency**: One ref-counted connection per client, the poll gated off while streaming, and `reconnect` kept as a GET so retry loops never trigger a provider fan-out.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-live-snapshot.ts` |
</content>
