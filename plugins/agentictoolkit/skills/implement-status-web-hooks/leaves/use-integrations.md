<!-- leaf: implement-status-web-hooks/use-integrations · source: status-web-hooks-use-integrations.md -->

**Rules** (cite as `implement-status-web-hooks/use-integrations#<slug>`):

- `hook-signature` MUST
- `return-value` MUST
- `client-source` MUST
- `query-key` MUST
- `always-enabled` MUST
- `request-path` MUST
- `request-init` MUST
- `raw-fetch-not-json-helper` MUST
- `non-ok-error` MUST
- `error-detail-dropped` MUST
- `success-body` MUST
- `parse-failure` MUST
- `network-failure` MUST
- `refetch-on-focus` MUST
- `shared-interval-refresh` MUST
- `no-hook-level-policy` MUST
- `no-timeout` MUST
- `no-persistence` MUST
- `client-only-module` MUST
- `single-threaded-ordering` MUST
- `react-web` MUST — The source is packages/web/packages/status-web/src/hooks/use-integrations.ts, a thin useQuery wrapper. It depends on …

# useIntegrations

## Overview

`useIntegrations` is a React hook in the status dashboard (`status-web/src/hooks/use-integrations.ts`) that loads the monitor's integration self-check snapshot: one entry per provider integration, saying whether it is configured, reachable and healthy. It wraps one TanStack React Query `useQuery` call under the fixed key `["integrations"]`. It requests `/integrations` through the dashboard's `StatusApiClient` (see status-web-api) and returns the query result typed as `IntegrationsResponse`. The hook turns on refetch-on-window-focus. It takes no arguments and is always enabled.

It has two callers. `OverviewTab` passes `data` to `SelfCheckBanner`, so a failed or degraded self-check shows on the default wallboard. `Dashboard` passes `data` to `computeSelfCheck` for the header self-check pill. Both callers read only `data`.

## Behavioral Requirements

- **hook-signature**: The hook MUST take no arguments.
- **return-value**: The hook MUST return the React Query `UseQueryResult<IntegrationsResponse>` object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`). It MUST NOT add fields of its own.
- **client-source**: The hook MUST get its HTTP client from `useStatusApi()`. That returns the `StatusApiClient` from the nearest `StatusApiProvider`, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the fixed key `["integrations"]`, so every caller in one `QueryClient` shares a single cache entry.
- **always-enabled**: The query MUST NOT set an `enabled` gate. It MUST fetch as soon as a component that calls the hook mounts, following the host `QueryClient`'s policy.
- **request-path**: Each fetch MUST call `api.fetch` with the relative path `/integrations`. The client resolves it against its base path, which by default gives `/api/integrations`.
- **request-init**: Each fetch MUST be issued with no `RequestInit` argument. It is a default GET, and the hook adds no headers, body, cache mode or abort signal.
- **raw-fetch-not-json-helper**: The hook MUST use the client's raw `fetch` method, not its `json` helper. So the `json` helper's `Content-Type` header, its error-detail extraction and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the query function MUST throw `Error` with the message `status <status>` (for example `status 502`), which puts the query in its error state.
- **error-detail-dropped**: On a non-ok response the hook MUST NOT read the response body. Any `error` or `message` detail the server returns is left out of the thrown error.
- **success-body**: When the response is ok, the query function MUST resolve with the result of `response.json()`, typed as `IntegrationsResponse`. There is no runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the rejection from `response.json()` MUST propagate as the query's error.
- **network-failure**: When `api.fetch` rejects (a network failure or an unreachable host), the rejection MUST propagate unchanged as the query's error.
- **refetch-on-focus**: The query MUST set `refetchOnWindowFocus: true`. When the browser window regains focus and the cached data is stale under the host `QueryClient`'s `staleTime`, React Query refetches it.
- **shared-interval-refresh**: The hook MUST NOT set its own `refetchInterval`. Periodic refresh comes from `useRefreshAll`, which refetches every enabled query whose first key segment is not `"live"` (this one included) on one shared interval, 60,000 ms by default.
- **no-hook-level-policy**: Apart from `refetchOnWindowFocus`, the hook MUST NOT set `staleTime`, `gcTime`, `retry` or `refetchInterval`. Staleness, cache lifetime and retry come from the host `QueryClient` defaults and React Query's library defaults.
- **integrations-response-shape**: A successful result is declared as `IntegrationsResponse` with fields `generatedAt: string`, `overall: CheckState` and `checks: IntegrationCheck[]`. `CheckState` is `"ok" | "warn" | "error"`.
- **integration-check-shape**: Each `IntegrationCheck` is declared with the required fields `id: string`, `label: string`, `configured: boolean`, `ok: boolean`, `state: CheckState` and `detail: string`.
- **integration-check-optional-fields**: `IntegrationCheck` also declares three optional fields. `missingEnv?: string[]` lists expected env vars found unset. `unreachable?: boolean` means the probe got no HTTP response. `correlated?: boolean` means the check was confirmed unreachable together with other providers in the same run. The hook passes all of them through untouched.
- **no-timeout**: The hook MUST NOT impose its own request timeout. A request that never settles leaves the query fetching until the client or browser ends it.
- **no-persistence**: The hook MUST NOT write the snapshot to any durable store. Results live only in the in-memory React Query cache and are lost on page reload.
- **client-only-module**: The module MUST be marked `"use client"`, so under a React Server Components host it runs only in client components.
- **single-threaded-ordering**: The hook runs on the JavaScript main thread. Concurrent callers (`OverviewTab` and `Dashboard`) MUST share the one `["integrations"]` cache entry, and React Query, not the hook, deduplicates their in-flight requests.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | Default client, base path `/api` | Injected through React context. Sets where `/integrations` is resolved and lets a test inject a double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`. Controls retry, stale time and cache lifetime. |
| `refetchOnWindowFocus` | boolean (hard-coded) | `true` | Refetches stale data when the window regains focus. Not configurable. |
| `useRefreshAll` `intervalMs` | number | `60000` | Shared refresh interval that also refetches this query. Set by whoever calls `useRefreshAll`, not by this hook. |

## Localization

The hook produces one hard-coded English string. It becomes the query's `Error.message`; the hook itself renders nothing. Neither caller displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `status <status>` | Message of the `Error` thrown on a non-ok response, for example `status 502` |

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-integrations.ts`, a thin `useQuery` wrapper. It depends on `useStatusApi` from `src/api/client.ts` and on `IntegrationsResponse`, `IntegrationCheck` and `CheckState` from `src/types.ts`. React Query provides caching, deduplication, retry, focus refetch and the loading/error state machine, and `useRefreshAll` provides the periodic refresh. A host MUST mount a `QueryClientProvider` and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `IntegrationsResponse?`, an error and a loading flag. Load with `URLSession.shared.data(for:)` in `.task` and decode with `JSONDecoder` into `Codable` structs, with a `CheckState` enum and optional `missingEnv`, `unreachable` and `correlated`. Unlike the source, decoding validates the shape, and an unknown `state` fails unless you add a fallback case. For focus refetch, observe `scenePhase` becoming `.active`. For the shared interval, use a `Timer` publisher or an `AsyncStream` loop in one app-level refresher. There is no query cache, so share one model instance between the views to keep the single-entry behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`, with Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. Share one repository-level `StateFlow` between screens to mirror the shared cache key. Refetch on `Lifecycle.Event.ON_RESUME` (through `repeatOnLifecycle(STARTED)`) to stand in for window focus, and use a `while (isActive) { delay(60_000) }` loop for the shared interval.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a `@MainActor` model. Refetch on `NSApplication.didBecomeActiveNotification` (AppKit) or `UIApplication.didBecomeActiveNotification` (UIKit) as the focus equivalent.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `IntegrationsResponse? Integrations`, `bool IsLoading` and `Exception? Error`. Register it as a singleton so both views share one instance, which stands in for the single `["integrations"]` cache entry. Fetch in an `async Task` with a shared `HttpClient.GetAsync($"{basePath}/integrations")`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"status {(int)response.StatusCode}")` without reading the body. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<IntegrationsResponse>` using `JsonSerializerDefaults.Web` for camelCase. Model `CheckState` as a string or an enum with `JsonStringEnumConverter`, keeping in mind that an unknown value throws where the source passes it through. Expose `Checks` as an `ObservableCollection<IntegrationCheck>` and marshal updates through `DispatcherQueue.TryEnqueue`. For focus refetch, handle `Window.Activated` and refetch when `WindowActivationState` is not `Deactivated`. For the shared refresh, use a `DispatcherQueueTimer` with `Interval = TimeSpan.FromSeconds(60)`. Three things differ from the source. .NET has no request deduplication, so guard against overlapping fetches with an in-flight `Task` field. `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout. Retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because React Query's default retry does not carry over.

