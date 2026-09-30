<!-- leaf: implement-status-web-hooks/use-telemetry--part-2 · source: status-web-hooks-use-telemetry.md -->

# useTelemetry — continued (part 2)

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor final class TelemetryStore` holding `snapshot: TelemetrySnapshot` (a `Codable`, `Sendable` struct). On init, decode the cached value from `UserDefaults` (or a file in Application Support) with `JSONDecoder`, gated like `parseSnapshot`; then run a polling `Task` that `await`s `source.get(api)` via `URLSession.data(from:)`, retries once, and sleeps `60` seconds with `Task.sleep(for:)`. Refresh on `scenePhase == .active` to mirror focus refetch, and cancel the task when the scene backgrounds. Share one store through the environment to replace react-query's shared query. SwiftUI has no SSR, so "hydrate after mount" reduces to loading the cache before the first fetch.
- **Compose**: A `ViewModel` exposing `StateFlow<TelemetrySnapshot>`; seed it from a DataStore or `SharedPreferences` JSON blob parsed with `kotlinx.serialization` (return `null` on any `SerializationException`), then poll with a `while (isActive) { runCatching { fetch() }; delay(60_000) }` loop in `viewModelScope`, retrying once per poll. Use `repeatOnLifecycle(Lifecycle.State.STARTED)` to pause the poll while backgrounded, the analogue of react-query's hidden-tab pause.
- **React/Web**: Source platform. `hooks/use-telemetry.ts` uses `@tanstack/react-query` v5 `useQuery` plus two `useEffect`s (cache hydration on mount, cache save on data change). It depends on `telemetry/client.ts` (composition root), `telemetry/ports.ts` (`SnapshotCache`, `TelemetrySource`), `telemetry/types.ts` (DTOs and `emptySnapshot`), `telemetry/sources/live.ts`, `telemetry/stores/local-cache.ts` (tested by `local-cache.test.ts`) and `api/client.ts` (`useStatusApi`). The hook itself has no direct test; `TelemetrySections.dom.test.tsx` mocks it.
- **AppKit / UIKit**: Same `TelemetryStore` as SwiftUI, observed via Observation tracking or Combine `@Published`; refresh on `NSApplication.didBecomeActiveNotification` / `UIApplication.didBecomeActiveNotification` to mirror focus refetch.
- **WinUI 3**: Implement a singleton `TelemetryService : INotifyPropertyChanged` registered in the DI container (the stand-in for the shared `QueryClient` query), exposing `Snapshot` as an immutable `record TelemetrySnapshot(string GeneratedAt, IReadOnlyList<ErrorDto> Errors, IReadOnlyList<AnalyticsMetricDto> Analytics)`. On start, read the cached JSON from `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-telemetry-v1"]` (or a file in `LocalFolder` if the snapshot can exceed the 8 KB per-setting limit) and parse it with `System.Text.Json` `JsonSerializer.Deserialize` inside `try/catch (JsonException)`, rejecting a null `GeneratedAt` or null arrays to match `parseSnapshot`. Poll with a `PeriodicTimer(TimeSpan.FromSeconds(60))` loop in an `async Task`, calling a shared `HttpClient.GetAsync("…/telemetry")`, throwing on `!response.IsSuccessStatusCode`, and retrying once; on success set `Snapshot` and write the cache inside a `try/catch` that swallows storage failures. Marshal the property change to the UI thread with `DispatcherQueue.TryEnqueue`. Refetch on `Window.Activated` to mirror `refetchOnWindowFocus`, and pause the timer when the window is minimized if the hidden-tab pause is wanted. Unlike react-query, nothing deduplicates concurrent loads or keeps data on error automatically: keep one in-flight `Task` and leave `Snapshot` unchanged on failure. There is no SSR, so hydration can run before the first fetch.

## Design Decisions

**Decision**: Hydrate from the cache in a post-mount effect, not during render or as react-query `initialData`.
**Rationale**: The source comment says this keeps "SSR and the first client paint" identical; reading `localStorage` during render would produce a hydration mismatch. The cost is one render of the empty snapshot before the cached one appears.
**Approved**: pending

**Decision**: Return a plain snapshot with fixed precedence live, then cached, then empty.
**Rationale**: "Live data wins; the cached snapshot covers the gap before the first poll lands (and a brief source outage); empty until either arrives." Consumers never handle `undefined`. The trade-off, recorded as the open question on telemetry-failure-signal, is that no error or staleness signal reaches consumers. In practice react-query retains the last data on error, so within one session an outage is covered by retained query data rather than by the cache; the cache covers the gap after a reload.
**Approved**: pending

**Decision**: Depend only on the `TelemetrySource` and `SnapshotCache` ports, composed in `telemetry/client.ts`.
**Rationale**: The source says swapping the backend (live poll versus Turso) is a one-line change in the composition root that "leaves it untouched"; `ports.ts` states that "nothing above the port moves".
**Approved**: pending

**Decision**: Treat the `localStorage` write as best-effort and the stored value as untrusted.
**Rationale**: `local-cache.ts` says "the in-memory query result is the live truth", so a failed write is silently ignored; `parseSnapshot` is a "defensive, shape-gated parse" because a stored value may be stale, from an older build, or corrupt.
**Approved**: pending

**Decision**: Poll every 60 seconds with one retry and focus refetch.
**Rationale**: `TELEMETRY_POLL_MS = 60_000` with `retry: 1` bounds each poll to at most two requests to `/telemetry`, which on the live path makes the server poll GlitchTip and PostHog; the source records no further rationale for the specific values.
**Approved**: pending
