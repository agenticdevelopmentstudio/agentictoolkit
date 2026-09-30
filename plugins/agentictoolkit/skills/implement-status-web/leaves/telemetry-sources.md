<!-- leaf: implement-status-web/telemetry-sources · source: status-web-telemetry-sources.md -->

**Rules** (cite as `implement-status-web/telemetry-sources#<slug>`):

- `source-shape` MUST
- `api-injection` MUST
- `get-only-requests` MUST
- `stateless` MUST
- `no-cache` MUST
- `interchangeable` MUST
- `error-propagation` MUST
- `network-rejection` MUST
- `json-parse-rejection` MUST
- `no-timeout` MUST
- `no-retry` MUST
- `response-shape-trusted` MAY
- `live-endpoint` MUST
- `live-status-check` MUST
- `live-passthrough` MUST
- `live-no-database` MUST
- `turso-endpoints` MUST
- `turso-parallel` MUST
- `turso-network-rejection-order` MUST
- `turso-errors-status` MUST
- `turso-analytics-status` MUST
- `turso-status-precedence` MUST
- `turso-body-order` MUST
- `turso-errors-projection` MUST
- `turso-analytics-projection` MUST
- `turso-generated-at` MUST
- `turso-snapshot-keys` MUST
- `default-source` MUST
- `single-threaded` MUST

# Status Web Telemetry Sources

## Overview

`liveSource` and `tursoSource` are the two client-side adapters behind the
`TelemetrySource` port (`telemetry/ports.ts`): an object with one method,
`get(api: StatusApiClient): Promise<TelemetrySnapshot>`. Each reads one
`TelemetrySnapshot` (`generatedAt`, `errors: ErrorDTO[]`,
`analytics: AnalyticsMetricDTO[]`, defined in `telemetry/types.ts`) from the
dashboard backend through the caller's `StatusApiClient`, so the consumer never
knows whether the data is live or persisted.

- **`liveSource`** (`sources/live.ts`) reads `/telemetry`, where the server
  polls GlitchTip and PostHog and returns DTOs directly. Its authoring comment
  states "No database anywhere on this path: a Turso outage cannot affect the
  dashboard's errors/analytics." It is the source wired today.
- **`tursoSource`** (`sources/turso.ts`) reads the persisted store via
  `/errors` and `/analytics` in parallel and assembles the snapshot itself. Its
  comment calls it the "reconnect the Turso backend later" target.

The composition root `telemetry/client.ts` holds both in
`const SOURCES = { live: liveSource, turso: tursoSource }` and exports
`source = SOURCES.live`; switching to Turso is a one-line change there. The only
consumer is `useTelemetry` (`hooks/use-telemetry.ts`), which calls
`source.get(api)` as its query function.

## Behavioral Requirements

### Shared contract

- **source-shape**: Each source MUST be an object exposing exactly one async operation, `get(api)`, that takes a `StatusApiClient` and resolves to a `TelemetrySnapshot`.
- **api-injection**: Each source MUST issue every HTTP request through the injected `api.fetch(path)` with a path relative to the client's base (for example `/telemetry`), never through a global `fetch` or an absolute URL.
- **get-only-requests**: Each source MUST call `api.fetch` with a path and no `init` argument, so every request is a plain GET with no custom headers or body.
- **stateless**: Each source MUST hold no state between calls; every `get` issues fresh requests and returns a new snapshot.
- **no-cache**: A source MUST NOT read or write the snapshot cache; caching belongs to the `SnapshotCache` port and the `useTelemetry` hook.
- **interchangeable**: Both sources MUST resolve to the same `TelemetrySnapshot` shape so the composition root can swap one for the other with no change to any consumer.
- **error-propagation**: A source MUST reject the returned promise on failure rather than resolving to an empty or partial snapshot; it MUST NOT catch or log errors itself.
- **network-rejection**: When `api.fetch` rejects (network failure, aborted request), the source's `get` MUST reject with that same error, unwrapped.
- **json-parse-rejection**: When a response with a 2xx status carries a body that is not valid JSON, `get` MUST reject with the error thrown by `Response.json()`.
- **no-timeout**: A source MUST NOT impose its own timeout or cancellation; a request that never settles leaves `get` pending.
- **no-retry**: A source MUST NOT retry a failed request; retry policy belongs to the caller (`useTelemetry` passes `retry: 1` to React Query).
- **response-shape-trusted**: Both sources trust the status-server response contract: they cast the parsed JSON with `as` and never check its shape, so a 2xx body missing `errors`, `analytics`, `metrics` or `generatedAt` resolves as a snapshot whose fields are `undefined`, with no error. Guaranteeing the shape is the backend's (status-server's) job; a port MAY add validation but the source does not.

### liveSource

- **live-endpoint**: `liveSource.get` MUST issue exactly one request, to `/telemetry`.
- **live-status-check**: When the `/telemetry` response has `ok === false` (status outside 200–299), `liveSource.get` MUST reject with an `Error` whose message is `telemetry ${status}` (for example `telemetry 503`), without reading the body.
- **live-passthrough**: On an `ok` response, `liveSource.get` MUST resolve to the parsed JSON body unchanged, including the server-supplied `generatedAt`.
- **live-no-database**: `liveSource` MUST depend only on `/telemetry`; it MUST NOT call `/errors` or `/analytics`.

### tursoSource

- **turso-endpoints**: `tursoSource.get` MUST issue exactly two requests, `/errors` and `/analytics`.
- **turso-parallel**: `tursoSource.get` MUST start both requests concurrently and wait for both responses (`Promise.all`) before checking either status.
- **turso-network-rejection-order**: When either request rejects, `tursoSource.get` MUST reject with the first rejection to settle (`Promise.all` semantics) and MUST NOT check any status.
- **turso-errors-status**: When the `/errors` response is not `ok`, `tursoSource.get` MUST reject with an `Error` whose message is `errors ${status}`.
- **turso-analytics-status**: When the `/errors` response is `ok` and the `/analytics` response is not, `tursoSource.get` MUST reject with an `Error` whose message is `analytics ${status}`.
- **turso-status-precedence**: When both responses are not `ok`, `tursoSource.get` MUST reject with the `errors ${status}` message; the `/analytics` status is not reported.
- **turso-body-order**: `tursoSource.get` MUST check both statuses before parsing either body, then parse `/errors` before `/analytics`.
- **turso-errors-projection**: `tursoSource.get` MUST take the snapshot's `errors` from the `errors` property of the `/errors` body (`{ errors: ErrorDTO[] }`) and discard any other properties.
- **turso-analytics-projection**: `tursoSource.get` MUST take the snapshot's `analytics` from the `metrics` property of the `/analytics` body (`{ metrics: AnalyticsMetricDTO[] }`), renaming `metrics` to `analytics`, and discard any other properties.
- **turso-generated-at**: `tursoSource.get` MUST set `generatedAt` to the client's clock at assembly time, as `new Date().toISOString()`, not to any server-supplied time.
- **turso-snapshot-keys**: The snapshot `tursoSource.get` resolves MUST contain exactly the keys `generatedAt`, `errors` and `analytics`.

### Composition

- **default-source**: The composition root MUST export `source` as `liveSource` today; changing the one marked line to `SOURCES.turso` MUST be the only edit required to switch backends.
- **single-threaded**: Both sources run on the browser's single JavaScript thread; concurrent `get` calls MUST NOT share state and MAY interleave freely, each resolving independently.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api` | `StatusApiClient` (argument to `get`) | none; required | The injected client that resolves relative paths against its base (default base `/api`, via `createStatusApiClient`) and performs the request |
| `source` (in `telemetry/client.ts`) | `TelemetrySource` | `SOURCES.live` | Which adapter the dashboard reads through; set to `SOURCES.turso` to serve from the database |
| Endpoint paths | string literals | `/telemetry`; `/errors`, `/analytics` | Hard-coded in each source; not configurable |

## Platform Notes

- **SwiftUI**: Model `TelemetrySource` as a `Sendable` protocol with `func get(api: StatusAPIClient) async throws -> TelemetrySnapshot`, and each adapter as a `struct`. Decode with `JSONDecoder` into `Codable` DTOs (which also closes the response-shape question), check `HTTPURLResponse.statusCode` in 200...299, and run the Turso pair with `async let` so both requests start before either is awaited. `async let` cancels the sibling on a throw, which differs from `Promise.all` leaving the other request running.
- **Compose**: A Kotlin `interface TelemetrySource { suspend fun get(api: StatusApiClient): TelemetrySnapshot }` with Ktor or Retrofit plus `kotlinx.serialization`. Use `coroutineScope { val e = async { ... }; val a = async { ... } }` for the Turso pair; structured concurrency cancels the sibling on failure. Throw an `IOException` subclass carrying `"telemetry $status"`.
- **React/Web**: The source platform. `sources/live.ts` is a single `api.fetch` plus an `ok` check; `sources/turso.ts` uses `Promise.all` and renames `metrics` to `analytics`. Both use TypeScript `as` casts, which are erased at runtime, and `Response.ok`. The port lives in `telemetry/ports.ts`, the DTOs in `telemetry/types.ts`, and the selection in `telemetry/client.ts`.
- **AppKit / UIKit**: The same Swift adapters as the SwiftUI note, driven from a view controller `Task` or a Combine publisher wrapping `URLSession.dataTask`; no UI-framework-specific code is involved.
- **WinUI 3**: Define `public interface ITelemetrySource { Task<TelemetrySnapshot> GetAsync(IStatusApiClient api, CancellationToken ct = default); }` with `LiveTelemetrySource` and `TursoTelemetrySource` classes. Issue requests through a shared `HttpClient` (`GetAsync(relativeUri)` against a `BaseAddress` standing in for the base path), test `response.IsSuccessStatusCode`, and throw `HttpRequestException($"telemetry {(int)response.StatusCode}")`. Deserialize with `System.Text.Json` (`JsonSerializer.DeserializeAsync<TelemetrySnapshot>` with `JsonSerializerOptions { PropertyNameCaseInsensitive = true }` or `[JsonPropertyName]` attributes), and for Turso read `/analytics` into a `record AnalyticsResponse(List<AnalyticsMetricDto> Metrics)` before mapping to `Analytics`. Run the pair with `Task.WhenAll(errorsTask, analyticsTask)`; unlike `Promise.all`, `WhenAll` waits for both tasks even if one faults, and its awaited exception is the first faulted task in argument order. Stamp `GeneratedAt` with `DateTimeOffset.UtcNow.ToString("O")`. `HttpClient.Timeout` defaults to 100 seconds, unlike the browser's no-timeout fetch. Select the adapter at the composition root through DI (`services.AddSingleton<ITelemetrySource, LiveTelemetrySource>()`), and let the view model marshal results onto the UI thread with `DispatcherQueue` before updating an `INotifyPropertyChanged` or `ObservableCollection` binding.

