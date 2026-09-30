<!-- leaf: implement-status-web-hooks/use-board--part-2 · source: status-web-hooks-use-board.md -->

# useBoard — continued (part 2)

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `board fetch failed: <status>` | `Error.message` of a non-OK board response, exposed on `UseBoardResult.error`; a hardcoded English string with no localization lookup |

The `BoardUnavailableReason` values are machine identifiers, not display strings; consumers word their own per-cause messages.

## Platform Notes

- **SwiftUI**: Model it as an `@Observable` `@MainActor` class exposing `board: Board?`, `reason: BoardUnavailableReason?` (a `String`-backed enum), `error: Error?` and `refetch()`. Fetch with `URLSession.shared.data(for:)` and decode with `JSONDecoder` (unlike the source, decoding validates shape and throws on mismatch). Drive the poll with a `Task` loop using `Task.sleep(for: .seconds(60))`, and the live-frame refetch with an `AsyncStream` subscription. Recompute the verdict from a stored `nowMs` refreshed by a 30 s `Timer.publish` or `TimelineView(.periodic)`. There is no React Query, so the single-retry, in-flight cancellation and cross-view sharing must be written explicitly (for example one shared store in the environment).
- **Compose**: A `ViewModel` exposing `StateFlow<BoardResult>`; poll with a `viewModelScope` coroutine using `delay(60_000)`, fetch with Ktor or Retrofit plus `kotlinx.serialization`, and model the reason as a `sealed interface` or `enum class`. Combine the fetched board flow with a ticking `nowMs` flow (`flow { while (true) { emit(System.currentTimeMillis()); delay(30_000) } }`) via `combine` so the verdict re-evaluates as time passes. Cancel the previous fetch `Job` on each live frame to mirror `cancelRefetch`.
- **React/Web**: Source platform. `hooks/use-board.ts` uses `@tanstack/react-query` v5 `useQuery` (key `["board"]`, `refetchInterval`, `retry: 1`) and relies on its retention of the last successful `data` across failures, which is why the verdict must re-judge `data` on every render. `subscribeLiveFrames` comes from `hooks/use-live-snapshot.ts`, `useNow` from `hooks/use-now.ts`, and the rules from `lib/board-staleness.ts` (itself built on `lib/snapshot-staleness.ts`). `Board` is a hand mirror of the server type in `lib/board-types.ts`.
- **AppKit / UIKit**: The same `@MainActor` store as SwiftUI, observed through `withObservationTracking` or Combine `@Published`; use `URLSession` with `JSONDecoder`, and drive the poll and 30 s clock with `Timer.scheduledTimer` or a `Task` loop. There is no render pass to recompute from, so recompute the verdict when the board, the error or the clock tick changes and push the result to observers.
- **WinUI 3**: Implement a `BoardStore` class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`) exposing `Board? Board`, `BoardUnavailableReason? Reason`, `Exception? Error` and a `RefetchCommand` (`IAsyncRelayCommand`). Fetch with a shared `HttpClient.GetAsync("board")` against a `BaseAddress` of the host's API base, checking `IsSuccessStatusCode` and throwing `new HttpRequestException($"board fetch failed: {(int)status}")`, and deserialize with `System.Text.Json` `JsonSerializer.DeserializeAsync<Board>` (which, unlike the source's cast, fails on type mismatch but still tolerates missing properties unless `JsonRequired` is set). Poll with `PeriodicTimer(TimeSpan.FromSeconds(60))` in an `async Task` loop, and keep a `CancellationTokenSource` per request so each live frame calls `Cancel()` on the in-flight read before starting a new one. Tick the client clock with a `DispatcherQueueTimer` (`Interval = 30s`) on the UI thread and recompute `Reason` on every tick and every fetch completion, raising `PropertyChanged` for `Board` and `Reason` together; there is no React Query, so the one-retry policy, retention of the last good board and sharing across pages (register `BoardStore` as a singleton in `Microsoft.Extensions.DependencyInjection`) are all explicit. Marshal results back with `DispatcherQueue.TryEnqueue` if fetching off the UI thread. Model `BoardUnavailableReason` as a C# `enum` and map it to per-cause text in the view (for example with `x:Bind` to a converter), never to a boolean `IsLoading`.

## Design Decisions

**Decision**: Fold read staleness, data freezing and absent observations into `board === null` inside the hook, instead of leaving `isBoardStale` for each consumer to call.
**Rationale**: Per "Fix Round 3 item 1", three separate rounds produced the same bug: a consumer checked `board === null` but not staleness and rendered a confident verdict off a frozen read. Making null mean "cannot back a current claim" gives every consumer the right answer by construction.
**Approved**: pending

**Decision**: Keep `stale`, `frozen` and `no-data` as distinct reasons even though all three produce a null board.
**Rationale**: Per the `BoardUnavailableReason` doc comment, they send a human to different places (the API, the monitor process, the config); `no-data` was split out ("Fix Round 2 item C3") because it is the normal state of a roster with nothing to observe and was misreported as a wedged monitor.
**Approved**: pending

**Decision**: Expose no `isLoading` flag; `reason === "loading"` is the only loading signal.
**Rationale**: A second way to ask the same question is the shape that caused the three-round bug above (doc comment on `reason`).
**Approved**: pending

**Decision**: Retry a failed read once (`retry: 1`) instead of React Query's default three retries with backoff.
**Rationale**: Per "Fix Round 2 item 5", the board already polls every 60 s, so extra retries only delay surfacing a down backend behind a longer spinner; one retry absorbs a single transient blip, and it matches the sibling `useLiveSnapshot` feed that gates the same loading screen.
**Approved**: pending

**Decision**: Judge the read clock against the client clock but the data clock server-against-server, using the cadence carried on the board being judged.
**Rationale**: The client clock keeps moving when every server feed has died, which is the failure the read check exists to catch; the data check compares two server timestamps so it is immune to client skew and throttled timers. The cadence used to come from the live-snapshot singleton, which was null for consumers that never open the SSE stream and silently widened the window ("One board, one answer").
**Approved**: pending

**Decision**: Hold no durable client state (no `localStorage`).
**Rationale**: Per the `useBoard` doc comment, a durable client store let a fixed problem survive in one browser tab forever, because a server-side fix could not reach into the tab's saved state.
**Approved**: pending

**Decision**: Use live frames as the fast path and the 60 s poll as the floor, without opening a second connection.
**Rationale**: The board and the snapshot change at the same moments and "one connection per tab is the existing contract" (`subscribeLiveFrames` doc comment); the poll keeps the board updating when the stream is down.
**Approved**: pending
