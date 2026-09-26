---
id: e322fd0c-1552-4bd9-b129-3c809af3a972
title: useUptime
domain: agentictoolkit://cookbook/status-web/hooks/use-uptime
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React Query hook that loads per-service daily uptime for the last N days
  (default 90) from the status backend, fetched once with no polling
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status-web/api
related:
- agentictoolkit://cookbook/status-web/hooks/use-response-history
- agentictoolkit://cookbook/status-server/monitor/uptime
references: []
approved-by: ''
approved-date: ''
---

# useUptime

## Overview

`useUptime` is a React hook in the status dashboard (`status-web/src/hooks/use-uptime.ts`) that loads per-service daily uptime over the last `days` days. It wraps one TanStack React Query `useQuery` call keyed by the window length, requests `/uptime?days=<days>` through the dashboard's `StatusApiClient` (see [status-web-api](agentictoolkit://cookbook/status-web/api)), and returns the query result typed as `UptimeResponse` from `src/types.ts`. Unlike its sibling [status-web-hooks-use-response-history](agentictoolkit://cookbook/status-web/hooks/use-response-history), it sets no `refetchInterval`, so it does not poll. It has two callers in the package, both passing `90`: `Dashboard`, which builds a `uptimeBySlug` map from `data.services` and picks the selected service's entry, and `OverviewTab`, which reduces `data.services` to one portfolio percentage with `overallUptimePercent`. The numbers themselves are computed by the backend `/uptime` route in `status-server` (see [status-server-monitor-uptime](agentictoolkit://cookbook/status-server/monitor/uptime)).

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

## Appearance

Not applicable — this is a data-fetching React hook, not a visual component.

## States

Not applicable — this is a data-fetching React hook, not a visual component.

## Accessibility

Not applicable — this is a data-fetching React hook, not a visual component.

## Conformance Test Vectors

No test file exists beside `use-uptime.ts`; the package's `Dashboard.dom.test.tsx` and `OverviewTab.dom.test.tsx` mock the hook out entirely (returning `{ data: undefined, isLoading: false }`), so these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-uptime-001 | days-default, always-enabled, request-path, request-init, client-source | `useUptime()` with the default client; stub returns `200` and `{"services":[],"days":90}` | Exactly one `fetch` to `/api/uptime?days=90` with no init argument |
| use-uptime-002 | success-body, uptime-response-shape, uptime-service-shape, uptime-day-shape, pass-through | `useUptime(90)`; stub returns `200` and `{"services":[{"slug":"b","name":"B","uptimePercent":null,"totalChecks":0,"daily":[]},{"slug":"a","name":"A","uptimePercent":99.5,"totalChecks":200,"daily":[{"day":"2026-09-23","status":"degraded","uptimePercent":99}]}],"days":90}` | `data` deep-equals the body; service `b` stays first and its `null` percentage is unchanged |
| use-uptime-003 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useUptime(30)` | The requested URL is `/proxy/uptime?days=30` |
| use-uptime-004 | days-interpolation | `useUptime(1.5)` | The requested path is `/api/uptime?days=1.5` |
| use-uptime-005 | non-ok-error, error-detail-dropped | `useUptime(90)`; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `uptime 401`; the body text does not appear in the message |
| use-uptime-006 | parse-failure | `useUptime(90)`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-uptime-007 | network-failure | `useUptime(90)`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-uptime-008 | no-polling | `useUptime(90)` with fake timers; first fetch succeeds; window keeps focus | Advancing time by 600,000 ms triggers no second `fetch` |
| use-uptime-009 | query-key | Render `useUptime(90)`, then rerender with `useUptime(30)` | Two fetches, one per window; returning to `90` within the cache's lifetime serves the cached 90-day data |
| use-uptime-010 | raw-fetch-not-json-helper | `useUptime(90)`; inspect the request | No `Content-Type` header is added by the hook |
| use-uptime-011 | single-threaded-ordering | Two components both call `useUptime(90)` under one `QueryClient` | One `fetch` is made; both receive the same `data` |
| use-uptime-012 | return-value | `useUptime(90)` before the stub resolves | The result has `isLoading` true and `data` undefined, and exposes no keys beyond React Query's own |

## Edge Cases

- **zero-or-negative-days**: `useUptime(0)` or a negative value MUST still fetch, sending `days=0` or `days=-5` as-is. The backend `/uptime` route (`status-server/src/routes/reads.ts`) owns the response: its `intParam` maps `0` or an unparsable value to its default of 90, and its `clamp` bounds the result to 1–365, so `-5` becomes 1; the hook surfaces whatever arrives.
- **fractional-days**: `useUptime(1.5)` MUST send `days=1.5` and cache under `["uptime", 1.5]`; the backend's `parseInt` reads it as 1, so the response `days` field is `1` while the cache key holds `1.5`.
- **non-finite-days**: `NaN` or `Infinity` MUST be sent as the literal text `days=NaN` or `days=Infinity` and cached under a key holding that value; the hook performs no numeric validation, and both callers pass the constant `90`.
- **large-window**: A `days` value above 365 MUST be sent unchanged; the backend clamps it to 365, and the hook does not compare the requested and returned `days`.
- **days-mismatch**: If the backend's `days` field differs from the requested value, the hook MUST return the body unchanged.
- **empty-services**: A successful response with `services: []` MUST resolve as data; the hook applies no emptiness check (`overallUptimePercent` then yields `null`).
- **null-percentages**: A service or day whose `uptimePercent` is `null` (the backend's value when a service has zero checks) MUST resolve unchanged; the hook does not fill or drop it.
- **malformed-body**: A body that is valid JSON but not shaped like `UptimeResponse` (for example missing `services`) MUST resolve as data unchanged; the hook performs no shape validation, and both callers guard with `data?.services ?? []`.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state.
- **server-error**: A non-2xx status, including the `401` the route's OpenAPI entry documents, MUST produce `Error("uptime <status>")`; retries follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting; with no polling, the query stays in error until a default React Query trigger or `refetch()` runs it again.
- **error-after-success**: When a refetch fails after an earlier success, React Query MUST keep the previous `data` alongside the new `error`, so callers keep showing the last good uptime.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state indefinitely.
- **days-change-mid-flight**: When `days` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **stale-data**: Because the hook sets no `refetchInterval`, uptime shown on a dashboard left open and focused MUST stay at the first-loaded values until a refocus, reconnect, remount, or `refetch()` triggers a new fetch.
- **unmount**: When the last component using a given `days` unmounts, the cached result MUST remain until the host `QueryClient`'s garbage-collection time elapses.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `days` | `number` | `90` | Uptime window length, sent as the `days` query parameter and used in the cache key. |
| `refetchInterval` | — (not set) | no polling | The hook never polls; refreshes come only from React Query's default triggers or `refetch()`. |
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | default client, base path `/api` | Injected through React context; determines where `/uptime` is resolved and allows a test double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`; controls retry, stale time, cache lifetime, focus refetch, and reconnect refetch. |

## Deep Linking

Not applicable: the hook reads no URL and registers no route; `days` is passed in by the caller.

## Localization

The hook produces one hard-coded English string, surfaced as the query's `Error.message` rather than rendered by the hook. Neither caller, `Dashboard` nor `OverviewTab`, displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `uptime <status>` | Message of the `Error` thrown on a non-ok response, for example `uptime 401` |

## Accessibility Options

Not applicable: the hook renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the hook reads no flags and has no `enabled` gate.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook sends only the `days` window, attaches no credentials or tokens itself (the route's bearer security is satisfied by the host's proxy behind the `StatusApiClient` base path), receives only aggregate check counts and percentages per monitored service, and stores results only in the in-memory query cache.

## Logging

Not applicable: the hook makes no log calls; failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-uptime.ts`, a thin `useQuery` wrapper whose types (`UptimeResponse`, `UptimeService`, `UptimeDay`) live in `src/types.ts` and whose `HealthStatus` comes from `src/lib/health.ts`. It depends on `useStatusApi` from `src/api/client.ts`. React Query supplies caching, deduplication, focus and reconnect refetch, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `UptimeResponse?` (`Codable` structs with `uptimePercent: Double?` and a `HealthStatus` `String` enum), an error, and a loading flag. Load once inside `.task(id: days)` with `URLSession.shared.data(for:)`, building the query with `URLComponents`. There is no built-in query cache or focus refetch, so share one model between the two consuming views to get the source's single-request deduplication, and reload on `scenePhase` becoming `.active` if refocus refresh matters. `JSONDecoder` validates the shape, unlike the source.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`, loading once in `viewModelScope.launch` with Ktor `HttpClient` or Retrofit and `kotlinx.serialization` (`Double?` for percentages). Share the `ViewModel` between the dashboard and overview screens to match the one-request deduplication. Refresh on `Lifecycle.Event.ON_RESUME` to approximate React Query's window-focus refetch.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a `@MainActor` model shared by the view controllers, loading once and reloading on `NSApplication.didBecomeActiveNotification` / `UIApplication.willEnterForegroundNotification` to mirror the focus refetch.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) exposing `UptimeResponse? Uptime`, `bool IsLoading`, and `Exception? Error`, with records `UptimeResponse(List<UptimeService> Services, int Days)`, `UptimeService(string Slug, string Name, double? UptimePercent, int TotalChecks, List<UptimeDay> Daily)`, and `UptimeDay(string Day, string Status, double? UptimePercent)`. Load once in an `async Task LoadAsync(int days = 90)` using a shared `HttpClient.GetAsync($"{basePath}/uptime?days={days}")`; when `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"uptime {(int)response.StatusCode}")`, otherwise deserialize with `JsonSerializer.DeserializeAsync<UptimeResponse>` using `JsonSerializerDefaults.Web`. Expose `Services` as an `ObservableCollection<UptimeService>` for `ItemsRepeater` or `ListView` binding and marshal updates through the `DispatcherQueue`. The differences from the source: .NET has no query cache or deduplication, so register the view model as a singleton shared by both pages; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has none; a failed reload should keep the previous `Uptime` to match React Query; and the focus refetch needs an explicit handler on `Window.Activated`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-uptime.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of Concerns**: The hook contains no presentation or computation. The base path and transport live in `StatusApiClient`, caching and the state machine in React Query, the uptime arithmetic in the backend and `lib/uptime.ts`, and the rendering in `Dashboard` and `OverviewTab`.

**Unit Test Coverage**: There is no `use-uptime.test.ts` or `use-uptime.dom.test.tsx` beside the hook, and the component tests that reach it mock it out, so the hook's fetch, key and error path are not exercised by any test.

**Explicit Error Handling**: A non-ok status, a network rejection, and a JSON parse failure all reject the query function and surface through the query's `error`, so none is swallowed. The server's error-body detail is not read.

**Timeout Handling**: The hook sets no timeout and passes no abort signal. A hung request leaves the query fetching indefinitely, though it leaves no inconsistent state behind.

**Graceful Degradation**: A failed refetch keeps the last successful data, and both callers fall back to an empty service list when no data exists, so the dashboard renders without uptime rather than failing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-uptime.ts` |
