<!-- leaf: implement-status-web-src/telemetry--part-2 · source: status-web-src-telemetry.md -->

# Status Web Telemetry — continued (part 2)

## Privacy

- **Data collected**: None by the client. It only displays error-issue summaries (`title`, `culprit`, `count`, `userCount`, `permalink`) and anonymous aggregate KPIs that the server provides.
- **Storage**: The latest `TelemetrySnapshot`, stored as JSON in browser localStorage under `adh-telemetry-v1`.
- **Transmission**: HTTP GETs to the status API through `StatusApiClient`. Nothing is sent upstream.
- **Retention**: The cached entry lasts until the next successful `save` overwrites it, or until the user clears site data. There is no expiry.

## Platform Notes

- **SwiftUI**: Model the DTOs as `Codable, Sendable` structs (`ErrorDTO`, `AnalyticsMetricDTO`, `TelemetrySnapshot` with `static let empty`). Express the ports as protocols: `TelemetrySource` with `func get(api: StatusAPIClient) async throws -> TelemetrySnapshot` and a `SnapshotCache` protocol. A `UserDefaults`-backed cache that uses `JSONDecoder` gives the null-on-failure parse via `try?`. Note that `Codable` validates each field, which is stricter than the source's top-level gate. Fire the Turso requests in parallel with `async let`. Hold the selected source as a `let` in a composition-root enum.
- **Compose**: Use Kotlin `@Serializable data class` DTOs and `interface TelemetrySource { suspend fun get(api: StatusApiClient): TelemetrySnapshot }`. Back the cache with `SharedPreferences` or DataStore, and parse with `Json { ignoreUnknownKeys = true }` wrapped in `runCatching` to return `null`. Run the Turso requests in parallel with `coroutineScope { async { } }`. Put the composition root in an `object TelemetryClient`.
- **React/Web**: This is the source: `src/telemetry/types.ts`, `ports.ts`, `client.ts`, `sources/live.ts`, `sources/turso.ts`, `stores/local-cache.ts`, and the vitest suite `stores/local-cache.test.ts`. Its specifics are `typeof window` SSR guards, `localStorage` try/catch, `Promise.all` for Turso, and `as` casts on response JSON. The server keeps its own copy of the types and ports in `status-server/src/telemetry/`.
- **AppKit / UIKit**: The same Swift DTOs and protocols as the SwiftUI note, placed in a shared framework. Use `URLSession.data(for:)` behind the API client, `UserDefaults.standard` for the cache, and a `withThrowingTaskGroup` alternative to `async let` if more sources are added.
- **WinUI 3**: Port the DTOs as C# `record`s (`public sealed record ErrorDTO(string Id, string IssueKey, string Project, string Title, string? Culprit, string? Level, int Count, int UserCount, string? FirstSeen, string? LastSeen, string? Permalink)`) and serialize them with `System.Text.Json` using `JsonSerializerDefaults.Web` so camelCase names match. Define `interface ITelemetrySource { Task<TelemetrySnapshot> GetAsync(IStatusApiClient api, CancellationToken ct = default); }` and `interface ISnapshotCache { TelemetrySnapshot? Load(); void Save(TelemetrySnapshot s); }`. Implement the live source with `HttpClient.GetAsync("telemetry")`, throw `HttpRequestException($"telemetry {(int)r.StatusCode}")` when the status is not a success, and then call `ReadFromJsonAsync<TelemetrySnapshot>()`. Implement the Turso source with `Task.WhenAll` over the two GETs, checking `/errors` before `/analytics`. Implement the cache with `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value, so a large snapshot may need a `LocalFolder` file via `FileIO.WriteTextAsync`) or a file in `LocalFolder`. Wrap `JsonSerializer.Deserialize` in try/catch and return `null`, then check the three members for non-null to match the top-level gate. There is no SSR, so drop the `window` guard. Register the composition root in DI (`services.AddSingleton<ITelemetrySource, LiveTelemetrySource>()`) instead of using a module constant. The view model that consumes it exposes the snapshot through `INotifyPropertyChanged`, and the lists through `ObservableCollection<ErrorDTO>` and `ObservableCollection<AnalyticsMetricDTO>`.

## Design Decisions

**Decision**: Hide every concrete backend behind ports, and select adapters only in the composition root `client.ts`.
**Rationale**: Per the `ports.ts` and `client.ts` comments, reconnecting the Turso backend means changing one line (`SOURCES.live` to `SOURCES.turso`), and the hook, cache and panels do not change because both sources honor the same `TelemetrySnapshot` contract.
**Approved**: pending

**Decision**: Wire the live `/telemetry` source by default instead of the database-backed one.
**Rationale**: `live.ts` states that there is "No database anywhere on this path: a Turso outage cannot affect the dashboard's errors/analytics".
**Approved**: pending

**Decision**: Persist the last snapshot in localStorage, and make saving best-effort.
**Rationale**: The cache gives instant paint on reload and a last-known view during a brief source outage. The in-memory query result stays the live truth, so a failed write loses only the reload shortcut.
**Approved**: pending

**Decision**: Gate stored snapshots only at the top level, and project them to the three known fields.
**Rationale**: The comment "Defensive, shape-gated parse" favors never throwing over full validation. The `-v1` key suffix allows a future shape change to start clean. The pure `parseSnapshot` is split out so it can be tested without a browser.
**Approved**: pending

**Decision**: `FetchResult.ok = false` must never clear a store.
**Rationale**: The `ports.ts` doc comment warns that an empty list from a failed poll is not "no data", and wiping the store during a temporary provider outage would blank the band.
**Approved**: pending

**Decision**: `tursoSource` stamps `generatedAt` on the client.
**Rationale**: `/errors` and `/analytics` return no snapshot timestamp, so the source records when it assembled the snapshot. As a result, Turso-path `generatedAt` values follow client-clock semantics, while live-path values follow the server clock.
**Approved**: pending
