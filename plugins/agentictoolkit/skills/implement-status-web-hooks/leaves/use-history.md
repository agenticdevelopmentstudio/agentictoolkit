<!-- leaf: implement-status-web-hooks/use-history · source: status-web-hooks-use-history.md -->

**Rules** (cite as `implement-status-web-hooks/use-history#<slug>`):

- `hook-signature` MUST
- `return-value` MUST
- `client-source` MUST
- `query-key` MUST
- `disabled-without-slug` MUST
- `enabled-with-slug` MUST
- `request-path` MUST
- `slug-encoding` MUST
- `fixed-window` MUST
- `request-init` MUST
- `raw-fetch-not-json-helper` MUST
- `non-ok-error` MUST
- `error-detail-dropped` MUST
- `success-body` MUST
- `parse-failure` MUST
- `network-failure` MUST
- `no-hook-level-policy` MUST
- `no-timeout` MUST
- `no-persistence` MUST
- `client-only-module` MUST
- `single-threaded-ordering` MUST
- `react-web` MUST — The source is packages/web/packages/status-web/src/hooks/use-history.ts, a thin useQuery wrapper. It depends on …
- `rationale` MUST — The hook sets only queryKey, queryFn, and enabled. Tests in the package build their QueryClient with retry: false, and …

# useHistory

## Overview

`useHistory` is a React hook in the status dashboard (`status-web/src/hooks/use-history.ts`) that loads the last 24 hours of health checks for a single monitored service. It wraps one TanStack React Query `useQuery` call keyed by the service slug, requests `/history?service=<slug>&hours=24` through the dashboard's `StatusApiClient` (see status-web-api), and returns the query result typed as `HistoryResponse`. Passing `null` leaves the query disabled, so a detail pane can call the hook unconditionally before any service is selected. Its one caller in the package is `DetailPanel`, which feeds `data.checks` into the response-time chart and status strip and shows `loading…` while `isLoading` is true.

## Behavioral Requirements

- **hook-signature**: The hook MUST accept exactly one argument, `slug: string | null`, identifying the service whose history is requested.
- **return-value**: The hook MUST return the React Query `UseQueryResult<HistoryResponse>` object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`), adding no fields of its own.
- **client-source**: The hook MUST obtain its HTTP client from `useStatusApi()`, which returns the `StatusApiClient` supplied by the nearest `StatusApiProvider`, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the key `["history", slug]`, so each distinct slug (including `null`) has its own cache entry.
- **disabled-without-slug**: When `slug` is `null` or the empty string, the query MUST be disabled (`enabled: !!slug`) and MUST NOT issue any request.
- **enabled-with-slug**: When `slug` is a non-empty string, the query MUST be enabled and MUST fetch according to the host `QueryClient`'s policy.
- **request-path**: Each fetch MUST call `api.fetch` with the relative path `/history?service=<encoded slug>&hours=24`, which the client resolves against its base path (by default producing `/api/history?service=<encoded slug>&hours=24`).
- **slug-encoding**: The slug MUST be passed through `encodeURIComponent` before being placed in the `service` query parameter.
- **fixed-window**: The `hours` query parameter MUST always be the literal `24`; the hook exposes no way to request a different window.
- **request-init**: Each fetch MUST be issued with no `RequestInit` argument, so it is a default GET with no added headers, body, or abort signal from the hook.
- **raw-fetch-not-json-helper**: The hook MUST use the client's raw `fetch` method, not its `json` helper, so the `json` helper's `Content-Type` header, its error-detail extraction, and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the query function MUST throw `Error` with the message `history <status>` (for example `history 503`), placing the query in its error state.
- **error-detail-dropped**: On a non-ok response the hook MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the thrown error.
- **success-body**: When the response is ok, the query function MUST resolve with the result of `response.json()`, typed as `HistoryResponse` without runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the rejection from `response.json()` MUST propagate as the query's error.
- **network-failure**: When `api.fetch` rejects (network failure or unreachable host), the rejection MUST propagate unchanged as the query's error.
- **history-response-shape**: A successful result is declared as `HistoryResponse` with fields `service: string`, `hours: number`, and `checks: HistoryCheck[]`.
- **history-check-shape**: Each `HistoryCheck` is declared with fields `status: HealthStatus | "unknown"` (where `HealthStatus` is `"healthy" | "degraded" | "down"`), `responseTimeMs: number | null`, `statusCode: number | null`, `error: string | null`, and `checkedAt: string`.
- **no-hook-level-policy**: The hook MUST NOT set `staleTime`, `gcTime`, `retry`, `refetchInterval`, or `refetchOnWindowFocus`; caching, retry, and refetch behavior MUST come entirely from the host `QueryClient` defaults and React Query's library defaults.
- **no-timeout**: The hook MUST NOT impose its own request timeout; a request that never settles leaves the query pending until the client or browser ends it.
- **no-persistence**: The hook MUST NOT write history to any durable store; results live only in the in-memory React Query cache.
- **client-only-module**: The module MUST be marked `"use client"`, so it runs only in client components under a React Server Components host.
- **single-threaded-ordering**: The hook runs on the JavaScript main thread; concurrent calls with the same slug MUST share one cache entry and are deduplicated by React Query rather than by the hook.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `slug` | `string \| null` | — (required) | Service identifier; a falsy value disables the query. |
| `hours` | number (hard-coded) | `24` | History window sent in the `hours` query parameter; not configurable. |
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | default client, base path `/api` | Injected through React context; determines where `/history` is resolved and allows a test double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`; controls retry, stale time, cache lifetime, and refetch triggers. |

## Localization

The hook produces one hard-coded English string, surfaced as the query's `Error.message` rather than rendered by the hook. Its one caller, `DetailPanel`, does not display it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `history <status>` | Message of the `Error` thrown on a non-ok response, for example `history 503` |

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-history.ts`, a thin `useQuery` wrapper. It depends on `useStatusApi` from `src/api/client.ts` and on `HistoryResponse`/`HistoryCheck` from `src/types.ts`. React Query supplies caching, deduplication, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` model (or `@MainActor` class) holding `HistoryResponse?`, an error, and a loading flag. Load with `URLSession.shared.data(for:)` inside `.task(id: slug)`, which cancels and restarts when the slug changes; this is the equivalent of the `["history", slug]` key. Build the query with `URLComponents`/`URLQueryItem`, which encodes values for you. Decode with `JSONDecoder` into `Codable` structs. Unlike the source, decoding validates the shape. There is no built-in query cache, so add a dictionary keyed by slug if you need to keep React Query's cache-per-slug behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`. Collect a `slug` flow with `flatMapLatest` or `mapLatest`, and use Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. `flatMapLatest` cancels the previous slug's request. React Query does not; there, the stale request simply lands in its own cache key.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a view controller or a `@MainActor` model that cancels the prior `Task` when the selection changes, and `NSCache` or a dictionary keyed by slug for caching.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `HistoryResponse? History`, `bool IsLoading`, and `Exception? Error`. Fetch with a shared `HttpClient.GetAsync($"{basePath}/history?service={Uri.EscapeDataString(slug)}&hours=24")` inside an `async Task`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"history {(int)response.StatusCode}")`. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<HistoryResponse>` using `JsonSerializerDefaults.Web` for camelCase. Expose `checks` as `ObservableCollection<HistoryCheck>` or a `List` for chart binding, and marshal updates through the `DispatcherQueue`. A null or empty slug skips the call. The differences from the source: .NET has no query cache or deduplication, so keep a `Dictionary<string, HistoryResponse>` and a `CancellationTokenSource` per selection; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout; and retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because React Query's default retry does not carry over.

## Design Decisions

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source chooses the raw method and throws its own short `history <status>` message. As a result, it drops the server's error detail and treats a 204 as a parse failure. Both are deliberate consequences of that choice, recorded here so ports keep them.

**Approved**: pending

---

**Decision**: The history window is fixed at 24 hours.

**Rationale**: The consuming pane labels itself `Response time · 24h`, and the hook hard-codes `hours=24` to match. A different window would need a new parameter.

**Approved**: pending

---

**Decision**: Cache, retry, and refetch policy are left to the host `QueryClient`.

**Rationale**: The hook sets only `queryKey`, `queryFn`, and `enabled`. Tests in the package build their `QueryClient` with `retry: false`, and production hosts supply their own defaults. A port MUST get its retry and staleness from the equivalent app-level policy rather than hard-coding them in the hook.

**Approved**: pending
