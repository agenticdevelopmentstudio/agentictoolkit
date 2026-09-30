<!-- leaf: implement-status-web-hooks/use-uptime · source: status-web-hooks-use-uptime.md -->

**Rules** (cite as `implement-status-web-hooks/use-uptime#<slug>`):

- `hook-signature` MUST
- `days-default` MUST
- `return-value` MUST
- `client-source` MUST
- `query-key` MUST
- `always-enabled` MUST
- `request-path` MUST
- `days-interpolation` MUST
- `request-init` MUST
- `raw-fetch-not-json-helper` MUST
- `non-ok-error` MUST
- `error-detail-dropped` MUST
- `success-body` MUST
- `parse-failure` MUST
- `network-failure` MUST
- `pass-through` MUST
- `no-polling` MUST
- `no-other-hook-policy` MUST
- `no-timeout` MUST
- `no-persistence` MUST
- `client-only-module` MUST
- `single-threaded-ordering` MUST
- `react-web` MUST — The source is packages/web/packages/status-web/src/hooks/use-uptime.ts, a thin useQuery wrapper whose types …

# useUptime

## Overview

`useUptime` is a React hook in the status dashboard (`status-web/src/hooks/use-uptime.ts`) that loads per-service daily uptime over the last `days` days. It wraps one TanStack React Query `useQuery` call keyed by the window length, requests `/uptime?days=<days>` through the dashboard's `StatusApiClient` (see status-web-api), and returns the query result typed as `UptimeResponse` from `src/types.ts`. Unlike its sibling status-web-hooks-use-response-history, it sets no `refetchInterval`, so it does not poll. It has two callers in the package, both passing `90`: `Dashboard`, which builds a `uptimeBySlug` map from `data.services` and picks the selected service's entry, and `OverviewTab`, which reduces `data.services` to one portfolio percentage with `overallUptimePercent`. The numbers themselves are computed by the backend `/uptime` route in `status-server` (see status-server-monitor-uptime).

## Behavioral Requirements

- **hook-signature**: The hook MUST accept one optional argument, `days: number`, the length of the uptime window in days.
- **days-default**: When `days` is omitted or `undefined`, the hook MUST use `90`.
- **return-value**: The hook MUST return the React Query `UseQueryResult<UptimeResponse>` object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`), adding no fields of its own.
- **client-source**: The hook MUST obtain its HTTP client from `useStatusApi()`, which returns the `StatusApiClient` supplied by the nearest `StatusApiProvider`, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the key `["uptime", days]`, so each distinct window length has its own cache entry.
- **always-enabled**: The query MUST NOT set an `enabled` condition; it fetches whenever the hook is mounted, for any `days` value.
- **request-path**: Each fetch MUST call `api.fetch` with the relative path `/uptime?days=<days>`, which the client resolves against its base path (by default producing `/api/uptime?days=<days>`).
- **days-interpolation**: The `days` value MUST be interpolated into the query string by JavaScript template-string conversion, with no `encodeURIComponent`, rounding, or range check (so `30` becomes `days=30` and `1.5` becomes `days=1.5`).
- **request-init**: Each fetch MUST be issued with no `RequestInit` argument, so it is a default GET with no added headers, body, or abort signal from the hook.
- **raw-fetch-not-json-helper**: The hook MUST use the client's raw `fetch` method, not its `json` helper, so the `json` helper's `Content-Type` header, its error-detail extraction, and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the query function MUST throw `Error` with the message `uptime <status>` (for example `uptime 401`), placing the query in its error state.
- **error-detail-dropped**: On a non-ok response the hook MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the thrown error.
- **success-body**: When the response is ok, the query function MUST resolve with the result of `response.json()`, typed as `UptimeResponse` without runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the rejection from `response.json()` MUST propagate as the query's error.
- **network-failure**: When `api.fetch` rejects (network failure or unreachable host), the rejection MUST propagate unchanged as the query's error.
- **uptime-response-shape**: A successful result is declared as `UptimeResponse` with fields `services: UptimeService[]` and `days: number`.
- **uptime-service-shape**: Each `UptimeService` is declared with `slug: string`, `name: string`, `uptimePercent: number | null`, `totalChecks: number`, and `daily: UptimeDay[]`.
- **uptime-day-shape**: Each `UptimeDay` is declared with `day: string`, `status: HealthStatus` (one of `"healthy"`, `"degraded"`, `"down"`), and `uptimePercent: number | null`.
- **pass-through**: The hook MUST return the service list and each service's `daily` list in the order the backend sent them, without sorting, filtering, filling missing days, or recomputing percentages.
- **no-polling**: The query MUST NOT set `refetchInterval`; after the first successful load, refetches happen only through React Query's default triggers (remount of a stale query, window refocus, reconnect) or an explicit `refetch()`.
- **no-other-hook-policy**: The hook MUST NOT set `staleTime`, `gcTime`, `retry`, `refetchOnWindowFocus`, or `refetchOnReconnect`; those behaviors MUST come from the host `QueryClient` defaults and React Query's library defaults.
- **no-timeout**: The hook MUST NOT impose its own request timeout; a request that never settles leaves the query fetching until the client or browser ends it.
- **no-persistence**: The hook MUST NOT write uptime data to any durable store; results live only in the in-memory React Query cache.
- **client-only-module**: The module MUST be marked `"use client"`, so it runs only in client components under a React Server Components host.
- **single-threaded-ordering**: The hook runs on the JavaScript main thread; concurrent calls with the same `days` MUST share one cache entry and are deduplicated by React Query rather than by the hook, so `Dashboard` and `OverviewTab` both calling `useUptime(90)` under one `QueryClient` issue one request.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `days` | `number` | `90` | Uptime window length, sent as the `days` query parameter and used in the cache key. |
| `refetchInterval` | — (not set) | no polling | The hook never polls; refreshes come only from React Query's default triggers or `refetch()`. |
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | default client, base path `/api` | Injected through React context; determines where `/uptime` is resolved and allows a test double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`; controls retry, stale time, cache lifetime, focus refetch, and reconnect refetch. |

## Localization

The hook produces one hard-coded English string, surfaced as the query's `Error.message` rather than rendered by the hook. Neither caller, `Dashboard` nor `OverviewTab`, displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `uptime <status>` | Message of the `Error` thrown on a non-ok response, for example `uptime 401` |

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-uptime.ts`, a thin `useQuery` wrapper whose types (`UptimeResponse`, `UptimeService`, `UptimeDay`) live in `src/types.ts` and whose `HealthStatus` comes from `src/lib/health.ts`. It depends on `useStatusApi` from `src/api/client.ts`. React Query supplies caching, deduplication, focus and reconnect refetch, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `UptimeResponse?` (`Codable` structs with `uptimePercent: Double?` and a `HealthStatus` `String` enum), an error, and a loading flag. Load once inside `.task(id: days)` with `URLSession.shared.data(for:)`, building the query with `URLComponents`. There is no built-in query cache or focus refetch, so share one model between the two consuming views to get the source's single-request deduplication, and reload on `scenePhase` becoming `.active` if refocus refresh matters. `JSONDecoder` validates the shape, unlike the source.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`, loading once in `viewModelScope.launch` with Ktor `HttpClient` or Retrofit and `kotlinx.serialization` (`Double?` for percentages). Share the `ViewModel` between the dashboard and overview screens to match the one-request deduplication. Refresh on `Lifecycle.Event.ON_RESUME` to approximate React Query's window-focus refetch.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a `@MainActor` model shared by the view controllers, loading once and reloading on `NSApplication.didBecomeActiveNotification` / `UIApplication.willEnterForegroundNotification` to mirror the focus refetch.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) exposing `UptimeResponse? Uptime`, `bool IsLoading`, and `Exception? Error`, with records `UptimeResponse(List<UptimeService> Services, int Days)`, `UptimeService(string Slug, string Name, double? UptimePercent, int TotalChecks, List<UptimeDay> Daily)`, and `UptimeDay(string Day, string Status, double? UptimePercent)`. Load once in an `async Task LoadAsync(int days = 90)` using a shared `HttpClient.GetAsync($"{basePath}/uptime?days={days}")`; when `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"uptime {(int)response.StatusCode}")`, otherwise deserialize with `JsonSerializer.DeserializeAsync<UptimeResponse>` using `JsonSerializerDefaults.Web`. Expose `Services` as an `ObservableCollection<UptimeService>` for `ItemsRepeater` or `ListView` binding and marshal updates through the `DispatcherQueue`. The differences from the source: .NET has no query cache or deduplication, so register the view model as a singleton shared by both pages; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has none; a failed reload should keep the previous `Uptime` to match React Query; and the focus refetch needs an explicit handler on `Window.Activated`.

## Design Decisions

**Decision**: The hook does not poll.

**Rationale**: Unlike `useResponseHistory` (60-second `refetchInterval`), `useUptime` sets no interval. Daily uptime over 90 days changes slowly, and the source relies only on React Query's default refetch triggers.

**Approved**: pending

---

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source chooses the raw method and throws its own short `uptime <status>` message. As a result it drops the server's error detail and treats a 204 as a parse failure; both follow from that choice, and it matches the sibling `useResponseHistory` hook.

**Approved**: pending

---

**Decision**: `days` defaults to 90 and is passed through without validation.

**Rationale**: The parameter is typed `number` with a default of `90`, matching the backend route's own default, and both callers pass `90`. Bounding the value (1–365) is owned by the backend `/uptime` route.

**Approved**: pending
