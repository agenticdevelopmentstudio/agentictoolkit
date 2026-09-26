---
id: ca7205d2-31c0-424a-95a2-a356bed30187
title: useLiveSnapshot
domain: agentictoolkit://cookbook/status-web/hooks/use-live-snapshot
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook and per-client transport store that feeds the latest live snapshot
  from an SSE stream with a 60 s poll fallback
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/api
- agentictoolkit://cookbook/status-web/hooks/use-board
references: []
approved-by: ''
approved-date: ''
---

# useLiveSnapshot

## Overview

`useLiveSnapshot` (`packages/web/packages/status-web/src/hooks/use-live-snapshot.ts`) is the status dashboard's transport for the latest `LiveSnapshot` — "what did the last probe cycle see" (services, deployments, `lastCycleAt`, `probeIntervalMs`, `monitorVersion`, `configDegraded`). It is mounted by several views at once (the header pill, `OverviewTab`, `Dashboard`, `BoardShell`, the stale banners, `usePortfolioIndicator`), so its state lives in one store per `StatusApiClient`, not per component.

The primary feed is one ref-counted `EventSource` on `/live/stream`, over which the backend pushes a `snapshot` frame on every cycle and webhook plus a `schedule` frame with the next cycle time. The fallback is a React Query poll of `GET /live` every 60 s, gated off while the stream is connected. The hook also exposes a manual full check (`refresh`, `POST /live/check`) whose spinner holds until the user's own result lands, and a cheap reachability re-read (`reconnect`).

Per the module's header comment it "does NOT fold frames into a durable model any more"; the board (`useBoard`) answers "what is wrong" and piggybacks on this feed through `subscribeLiveFrames` rather than opening a second connection.

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

### Reconnect

- **reconnect-read**: `reconnect()` MUST call `queryClient.refetchQueries({ queryKey: ["live"] })` and MUST NOT send `POST /live/check`.
- **reconnect-stable**: `reconnect` MUST keep its identity while the `QueryClient` is unchanged, and `refresh` while the store and `reconnect` are unchanged.

### Returned value

- **result-shape**: `useLiveSnapshot()` MUST take no arguments and return a `LiveSnapshotStore` with exactly `snapshot`, `offline`, `disconnected`, `blind`, `offlineDetail`, `polling`, `nextPollAt`, `refresh` and `reconnect`.
- **result-snapshot**: `snapshot` MUST be the store view's last ingested snapshot, or null before any ingestion.
- **result-offline**: `offline` MUST be true exactly when `liveError` is non-null, `streamConnected` is false, and the poll query is not fetching.
- **result-disconnected**: `disconnected` MUST be true exactly when `liveError` is non-null and `streamConnected` is false, regardless of whether a fetch is in flight.
- **result-blind**: `blind` MUST be true exactly when `snapshot` is non-null and `snapshot.services` is empty.
- **result-offline-detail**: `offlineDetail` MUST equal `liveError` when `disconnected` is true and null otherwise.
- **result-polling**: `polling` MUST be true when the poll query is fetching or `awaitingCheck` is true.
- **result-next-poll-streaming**: While `streamConnected` is true, `nextPollAt` MUST be `nextCheckAt` when it is non-null, and the client estimate otherwise.
- **result-next-poll-fallback**: While `streamConnected` is false, `nextPollAt` MUST be the client estimate.
- **client-estimate**: The client estimate MUST be `dataUpdatedAt + POLL_INTERVAL_MS` when the query's `dataUpdatedAt` is greater than 0, and null otherwise.

### Threading, persistence, side effects

- **single-thread**: All store mutation MUST run on the browser's single JavaScript thread from event listeners, timers and promise continuations; synchronous store code cannot interleave.
- **no-persistence**: The store MUST NOT write to `localStorage` or any durable store; all state is in memory for the page's lifetime.
- **no-timeout**: Neither `fetchLive` nor the check POST MUST apply a client request timeout or abort signal; only the check's safety timer bounds the spinner.
- **side-effects**: The only network side effects MUST be the `EventSource` on `/live/stream`, `GET /live`, and `POST /live/check`, all through the injected `StatusApiClient`.

## Appearance

Not applicable — this is a React data hook and transport store with no rendered output, not a visual component.

## States

Not applicable — this is a React data hook whose runtime connection and check states are listed under Behavioral Requirements, not a visual component.

## Accessibility

Not applicable — this is a React data hook with no rendered output, not a visual component.

## Conformance Test Vectors

Vectors 001–004 come from `use-live-snapshot.test.ts`; 005–011 from `use-live-snapshot.dom.test.tsx` (a mock `EventSource`, stubbed `fetch`, `__resetStoreForTests()` after each case); the rest are derived from the source.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-live-snapshot-001 | same-snapshot-null | `isSameSnapshot(null, snap("2026-06-30T00:00:00.000Z"))` | `false` |
| use-live-snapshot-002 | same-snapshot-identity | `isSameSnapshot(s, s)` | `true` |
| use-live-snapshot-003 | same-snapshot-clock | two distinct snapshots, both `generatedAt` `2026-06-30T00:00:00.000Z` | `true` |
| use-live-snapshot-004 | same-snapshot-clock | `generatedAt` `2026-06-30T00:00:00.000Z` vs `2026-06-30T00:01:00.000Z` | `false` |
| use-live-snapshot-005 | stream-path, stream-open-event, snapshot-frame, ingest-update | mount; stream fires `open` then `snapshot` with `generatedAt` `2030-01-01T00:00:00.000Z` and one service | stream URL `/api/live/stream`; `snapshot.generatedAt` equals that value; `snapshot.services` length 1 |
| use-live-snapshot-006 | schedule-frame, result-next-poll-streaming | stream `open`, then `schedule` with `{"nextCheckAt":"2030-06-01T00:00:00.000Z"}` | `nextPollAt` equals `Date.parse("2030-06-01T00:00:00.000Z")` |
| use-live-snapshot-007 | check-start, check-post-sync, result-polling, check-resolve | stream open, initial poll settled; call `refresh()`; then push a snapshot with `generatedAt` now + 5 s | `fetch` called with `("/api/live/check", { method: "POST" })` synchronously; `polling` true; after the push `polling` false |
| use-live-snapshot-008 | check-safety | fake timers; `refresh()` with `ran: true`; advance 60 000 ms; then push a snapshot built now + 90 s | `polling` still true after 60 s; false after the push |
| use-live-snapshot-009 | check-started-no-refetch | no stream opened; poll settled; `fetch` mock cleared; `refresh()` with `ran: true` | zero `GET /api/live` calls after the POST |
| use-live-snapshot-010 | stream-closed-error, stream-reopen | fake timers; mount; fire `error` with `readyState` `CLOSED`; advance 3 000 ms | 2 `EventSource` instances created |
| use-live-snapshot-011 | stream-transient-error | fake timers; mount; fire `error` with `readyState` `CONNECTING`; advance 10 000 ms | 1 `EventSource` instance |
| use-live-snapshot-012 | check-not-ran, check-not-ran-refetch | stream not connected; `refresh()`; POST returns 200 `{ "ran": false }` | `polling` returns to false once the poll settles; one `GET /api/live` issued after the POST |
| use-live-snapshot-013 | fetch-http-error, fetch-failure-sets-error, result-offline, result-disconnected, result-offline-detail | no stream; `GET /api/live` returns 503 on every call; query settles | `offline` true; `disconnected` true; `offlineDetail` `"live 503"` |
| use-live-snapshot-014 | fetch-success-clears-error, live-error-sticky | after 013, next `GET /api/live` returns 200 with a snapshot | `offlineDetail` null; `disconnected` false; during the in-flight retry `disconnected` stayed true while `offline` was false |
| use-live-snapshot-015 | result-blind | ingest a snapshot with `services: []` | `blind` true; with one service `blind` false; before any snapshot `blind` false |
| use-live-snapshot-016 | check-unrelated-push | `refresh()` with `ran: true`; push a snapshot with `generatedAt` one minute before the click | `snapshot` updated; `polling` stays true |
| use-live-snapshot-017 | snapshot-frame-malformed | stream fires `snapshot` with data `not json` | no throw; `snapshot` unchanged; no frame subscriber called |
| use-live-snapshot-018 | ingest-once, frame-subscribe | subscribe a counter via `subscribeLiveFrames`; ingest the same snapshot from the stream and then from the poll | counter is 1 |
| use-live-snapshot-019 | stream-ref-count, stream-single, stream-release | mount two hooks under one client; unmount one; unmount the other | 1 `EventSource`; still open after the first unmount; closed after the second |
| use-live-snapshot-020 | client-estimate, result-next-poll-fallback | no stream; poll succeeds with `dataUpdatedAt` T | `nextPollAt` equals T + 60 000 |

## Edge Cases

- **Nothing received yet**: `snapshot` MUST be null, `blind` false, `offline` false, and `nextPollAt` null until the first poll completes.
- **Server rendering**: No stream MUST open (no `window`); `getServerView()` returns the fresh view, so SSR shows the pre-anything state.
- **Stream open before first schedule frame**: `nextPollAt` MUST fall back to the client estimate.
- **Schedule frame with `nextCheckAt: null`**: `nextCheckAt` MUST become null, and `nextPollAt` falls back to the client estimate.
- **Schedule frame with an unparseable date string**: The JSON parses, `Date.parse` yields `NaN`, and `nextPollAt` MUST be `NaN` (the `??` fallback does not replace `NaN`); because `NaN !== NaN`, each such frame MUST re-notify listeners.
- **Snapshot with an unparseable `generatedAt`**: It MUST be ingested, but it cannot resolve a pending check (`NaN >= t` is false); the safety timer clears the spinner.
- **Malformed snapshot or schedule frame**: MUST be dropped silently, as declared in the source comments; recovery comes from the next frame or the poll.
- **Re-delivered frame**: A frame with the same `generatedAt` as the last ingested MUST be skipped, including a poll result racing a stream push of the same cycle.
- **Out-of-order frames**: A snapshot with an older `generatedAt` than the last ingested MUST still replace `snapshot`; only equality is checked.
- **Backend unreachable (network error)**: The poll MUST set `liveError` to the fetch error's message after one retry; with the stream down, `disconnected` is true and `offline` is true between probes.
- **Auth expiry or 5xx on stream connect**: The browser closes the source; the store MUST reopen it every 3 000 ms for as long as it is referenced, with no backoff growth and no retry limit.
- **Transient network drop on the stream**: The browser reconnects on its own; the store MUST only mark `streamConnected` false, which re-enables the poll and triggers an immediate re-read.
- **Last subscriber unmounts during a pending reopen**: The reopen MUST be cancelled and no new source opened.
- **Check POST fails (network or non-OK)**: The spinner MUST clear at once; no error is surfaced to the caller.
- **Check POST OK with a non-JSON body**: MUST count as started (`body` is null, so `ran` is not false).
- **Check started but its snapshot never arrives (stream wedged)**: The spinner MUST clear after 200 000 ms and a re-read MUST be issued.
- **Two overlapping `refresh()` calls**: See the open question on overlapping-check-requests.
- **Two providers under one `QueryClient`**: See the open question on per-client-poll-isolation.
- **`reset()` with a check in flight**: The in-flight POST continuation is not cancelled; when it completes it MAY patch the fresh view and MAY start a new safety timer that later calls the captured re-read.
- **Hung `GET /live` or POST**: No client timeout MUST apply; `polling` stays true while the query fetches.
- **Concurrent access**: Single-threaded JS; synchronous store code cannot interleave, and the only async overlaps are those two open questions.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiClient` (via `StatusApiProvider` / `useStatusApi()`) | injected dependency | same-origin client, base path `/api` | Resolves `/live`, `/live/check` and `/live/stream`; also the store key |
| `QueryClient` (via `QueryClientProvider`) | injected dependency | none (required) | Holds the `["live"]` poll cache |
| `POLL_INTERVAL_MS` | exported constant (ms) | `60000` | Fallback poll cadence and client-estimate offset |
| `CHECK_SAFETY_MS` | module constant (ms) | `200000` | Spinner backstop for a started check (the backend's cycle budget is max(3× probe interval, 2 min), plus margin) |
| `STREAM_REOPEN_MS` | module constant (ms) | `3000` | Delay before recreating a permanently closed stream |
| `retry` | React Query option | `1` | Poll retries before an error is reported |
| `EventSource` | browser global | platform | Absent (SSR, some test environments) means no stream and poll only |

## Deep Linking

Not applicable: the hook has no route or URL of its own; it only calls the `/live`, `/live/check` and `/live/stream` API paths.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `live <status>` | `Error.message` of a non-OK `GET /live`, surfaced as `offlineDetail` for the reconnect overlay's detail line; a hardcoded English string with no localization lookup |

## Accessibility Options

Not applicable: the hook renders nothing and responds to no display settings.

## Feature Flags

Not applicable: the source reads no feature flag.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: the hook attaches no credentials, identifiers or request body of its own and persists nothing on the client; snapshots are held only in memory for the page's lifetime.

## Logging

Not applicable: the source contains no log calls; failures surface only through `liveError`, `offline`, `disconnected` and `offlineDetail`.

## Platform Notes

- **SwiftUI**: A `@MainActor @Observable` store per API client (a dictionary keyed by `ObjectIdentifier`), exposing the same fields. Consume the stream with `URLSession.bytes(for:)` and parse SSE lines yourself (there is no `EventSource`), decoding with `JSONDecoder`; the ref count maps to `.task` start and cancellation. Run the fallback poll as a `Task` loop with `Task.sleep(for: .seconds(60))` gated on `streamConnected`, and model the safety and reopen timers as cancellable `Task`s. There is no React Query, so the one-retry policy, `isFetching` and `dataUpdatedAt` must be tracked explicitly.
- **Compose**: A singleton-per-client repository exposing `StateFlow<LiveView>`; OkHttp's `okhttp-sse` `EventSources.createFactory` for the stream, Ktor or Retrofit plus `kotlinx.serialization` for `/live` and `/live/check`. Ref-count collectors with `shareIn(scope, SharingStarted.WhileSubscribed())`, which also closes the stream when the last collector leaves. Poll with a coroutine `delay(60_000)` loop and use `Job`s for the 200 s and 3 s timers.
- **React/Web**: Source platform. `hooks/use-live-snapshot.ts` bridges a closure store into React with `useSyncExternalStore` (subscribe opens the stream) and runs the fallback with `@tanstack/react-query` v5 `useQuery`. The client comes from `api/client.ts` (`useStatusApi`, `createStatusApiClient`), the types from `lib/live-types.ts`, and `useBoard` consumes `subscribeLiveFrames`.
- **AppKit / UIKit**: The same `@MainActor` store as SwiftUI, observed via `withObservationTracking` or Combine `@Published`; ref-count from view-controller appearance or explicit `acquire`/`release`. Use `Timer` or `Task` for the poll, safety and reopen timers.
- **WinUI 3**: A `LiveSnapshotStore` class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), one instance per API client held in a `ConcurrentDictionary<ApiClient, LiveSnapshotStore>` or registered in `Microsoft.Extensions.DependencyInjection`. .NET has no `EventSource`, so read the stream with `HttpClient.GetStreamAsync("live/stream")` (or `SendAsync` with `HttpCompletionOption.ResponseHeadersRead`) and parse `event:`/`data:` lines with a `StreamReader` (or `System.Net.ServerSentEvents.SseParser` on .NET 9+); you must implement both reconnect paths yourself, since nothing auto-retries. Deserialize with `System.Text.Json` `JsonSerializer.Deserialize<LiveSnapshot>` (which, unlike the source's cast, throws on type mismatch). Poll with `PeriodicTimer(TimeSpan.FromSeconds(60))` in an `async Task` loop gated on `StreamConnected`, send the check with `HttpClient.PostAsync("live/check", null)`, and model the 200 s safety and 3 s reopen timers with `Task.Delay` plus a `CancellationTokenSource` per timer. Ref-count with `Acquire()`/`Release()` called from each page's `Loaded`/`Unloaded`. Raise `PropertyChanged` on the UI thread via `DispatcherQueue.TryEnqueue`, and expose `Refresh` and `Reconnect` as `IRelayCommand`s. Keying the poll by client is up to you here, so the shared-`["live"]`-key issue does not carry over by default.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-live-snapshot.ts` |

## Design Decisions

**Decision**: Keep one store per `StatusApiClient` in a module registry instead of per-component state.
**Rationale**: The hook is mounted by several views; per-component state would fork the store and open one connection each. Keying by client identity lets a host with two backends get two stores (module header comment).
**Approved**: pending

**Decision**: Treat SSE as the primary feed and gate every poll trigger off while it is connected.
**Rationale**: The backend pushes on every cycle and webhook; polling alongside it is redundant work. The idempotent `ingestOnce` makes a stray poll harmless (comment on the `useQuery` call).
**Approved**: pending

**Decision**: Recreate the `EventSource` after a `CLOSED` error, but not after a `CONNECTING` one.
**Rationale**: The browser auto-retries network drops but never a non-200 connect (auth expiry, 5xx); without the recreate the tab is "stuck on the poll forever".
**Approved**: pending

**Decision**: Own `liveError` in the store instead of reading React Query's `isError`.
**Rationale**: On a cold board the query resets to pending at each refetch, so `isError` held too briefly for the reconnect overlay's 1.2 s show delay and the board sat on "Loading…" through a redeploy (doc comment on `liveError`).
**Approved**: pending

**Decision**: Expose both `offline` (drops during an in-flight read) and `disconnected` (stable across reads).
**Rationale**: `offline` drives the stop sign; the reconnect overlay needs a signal that does not strobe during each probe so its outage clock keeps accumulating (doc comment on `disconnected`).
**Approved**: pending

**Decision**: Hold the manual-check spinner until a snapshot built at or after the click lands, with a 200 000 ms backstop, and do not re-read immediately on a started check.
**Rationale**: `POST /live/check` returns as soon as the detached cycle starts, so an immediate re-read fetches the pre-cycle snapshot. The old 12 s backstop fired on nearly every check while providers were still being polled (doc comment on `CHECK_SAFETY_MS`).
**Approved**: pending

**Decision**: Separate `refresh` (POST full check) from `reconnect` (GET re-read).
**Rationale**: An auto-retry loop over a down backend has to stay a light GET, never a repeated provider fan-out (comment on `reconnect`).
**Approved**: pending

**Decision**: Publish frames through a module-wide `subscribeLiveFrames` set instead of the store's listener set.
**Rationale**: `useBoard` refetches on frames without opening a second connection ("one connection per tab is the existing contract"). The store's listeners also fire on connection-state changes, which should not trigger a board refetch.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-live-snapshot.ts` |
