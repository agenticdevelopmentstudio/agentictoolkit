<!-- leaf: implement-status-web-hooks/use-live-snapshot--part-3 · source: status-web-hooks-use-live-snapshot.md -->

# useLiveSnapshot — continued (part 3)

**Rules** (cite as `implement-status-web-hooks/use-live-snapshot--part-3#<slug>`):

- `reconnect-read` MUST
- `reconnect-stable` MUST
- `result-shape` MUST
- `result-snapshot` MUST
- `result-offline` MUST
- `result-disconnected` MUST
- `result-blind` MUST
- `result-offline-detail` MUST
- `result-polling` MUST
- `result-next-poll-streaming` MUST
- `result-next-poll-fallback` MUST
- `client-estimate` MUST
- `single-thread` MUST
- `no-persistence` MUST
- `no-timeout` MUST
- `side-effects` MUST

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

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `live <status>` | `Error.message` of a non-OK `GET /live`, surfaced as `offlineDetail` for the reconnect overlay's detail line; a hardcoded English string with no localization lookup |

## Platform Notes

- **SwiftUI**: A `@MainActor @Observable` store per API client (a dictionary keyed by `ObjectIdentifier`), exposing the same fields. Consume the stream with `URLSession.bytes(for:)` and parse SSE lines yourself (there is no `EventSource`), decoding with `JSONDecoder`; the ref count maps to `.task` start and cancellation. Run the fallback poll as a `Task` loop with `Task.sleep(for: .seconds(60))` gated on `streamConnected`, and model the safety and reopen timers as cancellable `Task`s. There is no React Query, so the one-retry policy, `isFetching` and `dataUpdatedAt` must be tracked explicitly.
- **Compose**: A singleton-per-client repository exposing `StateFlow<LiveView>`; OkHttp's `okhttp-sse` `EventSources.createFactory` for the stream, Ktor or Retrofit plus `kotlinx.serialization` for `/live` and `/live/check`. Ref-count collectors with `shareIn(scope, SharingStarted.WhileSubscribed())`, which also closes the stream when the last collector leaves. Poll with a coroutine `delay(60_000)` loop and use `Job`s for the 200 s and 3 s timers.
- **React/Web**: Source platform. `hooks/use-live-snapshot.ts` bridges a closure store into React with `useSyncExternalStore` (subscribe opens the stream) and runs the fallback with `@tanstack/react-query` v5 `useQuery`. The client comes from `api/client.ts` (`useStatusApi`, `createStatusApiClient`), the types from `lib/live-types.ts`, and `useBoard` consumes `subscribeLiveFrames`.
- **AppKit / UIKit**: The same `@MainActor` store as SwiftUI, observed via `withObservationTracking` or Combine `@Published`; ref-count from view-controller appearance or explicit `acquire`/`release`. Use `Timer` or `Task` for the poll, safety and reopen timers.
- **WinUI 3**: A `LiveSnapshotStore` class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), one instance per API client held in a `ConcurrentDictionary<ApiClient, LiveSnapshotStore>` or registered in `Microsoft.Extensions.DependencyInjection`. .NET has no `EventSource`, so read the stream with `HttpClient.GetStreamAsync("live/stream")` (or `SendAsync` with `HttpCompletionOption.ResponseHeadersRead`) and parse `event:`/`data:` lines with a `StreamReader` (or `System.Net.ServerSentEvents.SseParser` on .NET 9+); you must implement both reconnect paths yourself, since nothing auto-retries. Deserialize with `System.Text.Json` `JsonSerializer.Deserialize<LiveSnapshot>` (which, unlike the source's cast, throws on type mismatch). Poll with `PeriodicTimer(TimeSpan.FromSeconds(60))` in an `async Task` loop gated on `StreamConnected`, send the check with `HttpClient.PostAsync("live/check", null)`, and model the 200 s safety and 3 s reopen timers with `Task.Delay` plus a `CancellationTokenSource` per timer. Ref-count with `Acquire()`/`Release()` called from each page's `Loaded`/`Unloaded`. Raise `PropertyChanged` on the UI thread via `DispatcherQueue.TryEnqueue`, and expose `Refresh` and `Reconnect` as `IRelayCommand`s. Keying the poll by client is up to you here, so the shared-`["live"]`-key issue does not carry over by default.

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
