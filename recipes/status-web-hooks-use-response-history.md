---
id: f5f0f19f-065e-4484-8c81-e591eee6db3c
title: useResponseHistory
domain: agentictoolkit://recipes/status-web-hooks-use-response-history
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React Query hook that polls the portfolio-wide response-time history for
  the last N hours every 60 seconds
platforms:
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-api
related:
- agentictoolkit://recipes/status-web-hooks-use-history
references: []
approved-by: ''
approved-date: ''
---

# useResponseHistory

## Overview

`useResponseHistory` is a React hook in the status dashboard (`status-web/src/hooks/use-response-history.ts`) that loads the portfolio-wide response-time history over the last `hours` hours, "for the overview graph" as its doc comment says. It wraps one TanStack React Query `useQuery` call keyed by the window length. It requests `/response-history?hours=<hours>` through the dashboard's `StatusApiClient` (see [status-web-api](agentictoolkit://recipes/status-web-api)), polls every 60 seconds, and returns the query result typed as `ResponseHistory`. Its one caller in the package is `OverviewStats`, which passes the selected span's `hours` (24, 168, 720 or 2160 from `SPANS`) and draws `data.points` as the "avg response" sparkline, falling back to an empty array while no data is loaded. It is the portfolio-level sibling of [status-web-hooks-use-history](agentictoolkit://recipes/status-web-hooks-use-history), which loads one service's checks.

## Behavioral Requirements

- **hook-signature**: The hook MUST accept exactly one argument, `hours: number`, the length of the history window in hours.
- **return-value**: The hook MUST return the React Query `UseQueryResult<ResponseHistory>` object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`), adding no fields of its own.
- **client-source**: The hook MUST obtain its HTTP client from `useStatusApi()`, which returns the `StatusApiClient` supplied by the nearest `StatusApiProvider`, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the key `["response-history", hours]`, so each distinct window length has its own cache entry.
- **always-enabled**: The query MUST NOT set an `enabled` condition; it fetches whenever the hook is mounted, for any `hours` value.
- **request-path**: Each fetch MUST call `api.fetch` with the relative path `/response-history?hours=<hours>`, which the client resolves against its base path (by default producing `/api/response-history?hours=<hours>`).
- **hours-interpolation**: The `hours` value MUST be interpolated into the query string by JavaScript template-string conversion, with no `encodeURIComponent`, rounding, or range check (so `24` becomes `hours=24` and `1.5` becomes `hours=1.5`).
- **no-buckets-parameter**: The request MUST NOT include a `buckets` query parameter; the number of points in the series is chosen by the backend `/response-history` route.
- **request-init**: Each fetch MUST be issued with no `RequestInit` argument, so it is a default GET with no added headers, body, or abort signal from the hook.
- **raw-fetch-not-json-helper**: The hook MUST use the client's raw `fetch` method, not its `json` helper, so the `json` helper's `Content-Type` header, its error-detail extraction, and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the query function MUST throw `Error` with the message `response-history <status>` (for example `response-history 401`), placing the query in its error state.
- **error-detail-dropped**: On a non-ok response the hook MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the thrown error.
- **success-body**: When the response is ok, the query function MUST resolve with the result of `response.json()`, typed as `ResponseHistory` without runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the rejection from `response.json()` MUST propagate as the query's error.
- **network-failure**: When `api.fetch` rejects (network failure or unreachable host), the rejection MUST propagate unchanged as the query's error.
- **response-history-shape**: A successful result is declared as the exported interface `ResponseHistory` with fields `hours: number` and `points: (number | null)[]`.
- **points-semantics**: Per the interface's doc comment, each entry of `points` is the average response time in milliseconds of UP checks for one time bucket, ordered oldest to newest, and `null` means the bucket had no data or every check in it was down; the hook MUST pass these values through without reordering, filling, or filtering.
- **polling-interval**: The query MUST set `refetchInterval: 60_000`, so while the hook is mounted React Query refetches the history every 60,000 ms.
- **no-other-hook-policy**: Apart from `refetchInterval`, the hook MUST NOT set `staleTime`, `gcTime`, `retry`, `refetchIntervalInBackground`, or `refetchOnWindowFocus`; those behaviors MUST come from the host `QueryClient` defaults and React Query's library defaults.
- **no-timeout**: The hook MUST NOT impose its own request timeout; a request that never settles leaves the query fetching until the client or browser ends it.
- **no-persistence**: The hook MUST NOT write history to any durable store; results live only in the in-memory React Query cache.
- **client-only-module**: The module MUST be marked `"use client"`, so it runs only in client components under a React Server Components host.
- **single-threaded-ordering**: The hook runs on the JavaScript main thread; concurrent calls with the same `hours` MUST share one cache entry and are deduplicated by React Query rather than by the hook.

## Appearance

Not applicable — this is a data-fetching React hook, not a visual component.

## States

Not applicable — this is a data-fetching React hook, not a visual component.

## Accessibility

Not applicable — this is a data-fetching React hook, not a visual component.

## Conformance Test Vectors

No test file exists beside `use-response-history.ts`; these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's other `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-response-history-001 | always-enabled, request-path, request-init, client-source, no-buckets-parameter | `useResponseHistory(24)` with the default client; stub returns `200` and `{"hours":24,"points":[120,null,95]}` | Exactly one `fetch` to `/api/response-history?hours=24` with no init argument and no `buckets` parameter |
| use-response-history-002 | success-body, points-semantics, response-history-shape | Same as 001 | `data` deep-equals `{"hours":24,"points":[120,null,95]}`; the `null` stays in position 1 |
| use-response-history-003 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useResponseHistory(168)` | The requested URL is `/proxy/response-history?hours=168` |
| use-response-history-004 | hours-interpolation | `useResponseHistory(1.5)` | The requested path is `/api/response-history?hours=1.5` |
| use-response-history-005 | non-ok-error, error-detail-dropped | `useResponseHistory(24)`; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `response-history 401`; the body text does not appear in the message |
| use-response-history-006 | parse-failure | `useResponseHistory(24)`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-response-history-007 | network-failure | `useResponseHistory(24)`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-response-history-008 | polling-interval | `useResponseHistory(24)` with fake timers; first fetch succeeds | Advancing time by 60,000 ms triggers a second `fetch` to the same URL; advancing less than 60,000 ms does not |
| use-response-history-009 | query-key | Render `useResponseHistory(24)`, then rerender with `useResponseHistory(720)` | Two fetches, one per window; returning to `24` within the cache's lifetime serves the cached 24-hour data |
| use-response-history-010 | raw-fetch-not-json-helper | `useResponseHistory(24)`; inspect the request | No `Content-Type` header is added by the hook |
| use-response-history-011 | single-threaded-ordering | Two components both call `useResponseHistory(24)` under one `QueryClient` | One `fetch` is made; both receive the same `data` |

## Edge Cases

- **zero-or-negative-hours**: `useResponseHistory(0)` or a negative value MUST still fetch, sending `hours=0` or `hours=-5` as-is; how the backend `/response-history` route treats it (empty series, clamping, or an error status) is owned by that route, and the hook MUST surface whichever it returns.
- **non-finite-hours**: `NaN` or `Infinity` MUST be sent as the literal text `hours=NaN` or `hours=Infinity`, and cached under a key holding that value; the hook performs no numeric validation, and its one caller only passes the finite constants from `SPANS`.
- **large-window**: The largest window the caller uses is 2,160 hours (90 days); the hook applies no upper bound of its own.
- **empty-points**: A successful response with `points: []` MUST resolve as data; the hook applies no emptiness check (`OverviewStats` separately hides the card sparkline when fewer than two non-null points exist).
- **all-null-points**: A series whose every entry is `null` MUST resolve as data unchanged; per the doc comment this means no data or all checks down in every bucket.
- **malformed-body**: A body that is valid JSON but not shaped like `ResponseHistory` (for example missing `points`) MUST resolve as data unchanged; the hook performs no shape validation, and a consumer reading `data.points` receives `undefined` (the caller's `?? []` fallback covers that case).
- **hours-mismatch**: If the backend's `hours` field differs from the requested value, the hook MUST return the body unchanged; it does not compare the two.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state.
- **server-error**: A non-2xx status, including the `401` the route documents, MUST produce `Error("response-history <status>")`; retries follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting; the 60-second poll continues to attempt refetches while mounted.
- **error-after-success**: When a poll fails after an earlier success, React Query MUST keep the previous `data` alongside the new `error`, so the caller keeps drawing the last good series.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state; React Query does not start the next interval refetch while one is still in flight.
- **hours-change-mid-flight**: When `hours` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **background-tab**: Because `refetchIntervalInBackground` is not set, React Query's default MUST apply: interval refetches pause while the browser tab is hidden.
- **unmount**: When the last component using a given `hours` unmounts, interval polling for that key MUST stop; the cached result remains until the host `QueryClient`'s garbage-collection time elapses.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hours` | `number` | — (required) | History window length, sent as the `hours` query parameter and used in the cache key. |
| `refetchInterval` | number (hard-coded) | `60_000` ms | Polling period while mounted; not configurable by the caller. |
| `buckets` | — (not sent) | backend default | The hook sends no `buckets` parameter, so the series length is the backend route's default. |
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | default client, base path `/api` | Injected through React context; determines where `/response-history` is resolved and allows a test double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`; controls retry, stale time, cache lifetime, focus refetch, and background polling. |

## Deep Linking

Not applicable: the hook reads no URL and registers no route; `hours` is passed in by the caller.

## Localization

The hook produces one hard-coded English string, surfaced as the query's `Error.message` rather than rendered by the hook. Its one caller, `OverviewStats`, does not display it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `response-history <status>` | Message of the `Error` thrown on a non-ok response, for example `response-history 401` |

## Accessibility Options

Not applicable: the hook renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the hook reads no flags and has no `enabled` gate.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook sends only the `hours` window, attaches no credentials or tokens itself (any authentication is added by the host's proxy behind the `StatusApiClient` base path), receives only aggregate response times, and stores results only in the in-memory query cache.

## Logging

Not applicable: the hook makes no log calls; failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-response-history.ts`, a thin `useQuery` wrapper that also exports the `ResponseHistory` interface (unlike `useHistory`, whose types live in `src/types.ts`). It depends on `useStatusApi` from `src/api/client.ts`. React Query supplies caching, deduplication, interval polling, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `ResponseHistory?` (a `Codable` struct with `hours: Double` and `points: [Double?]`), an error, and a loading flag. Load inside `.task(id: hours)` with a loop of `URLSession.shared.data(for:)` followed by `try await Task.sleep(for: .seconds(60))`; the task is cancelled when `hours` changes or the view disappears, which matches the per-key polling. Build the query with `URLComponents`. There is no built-in query cache, so keep a dictionary keyed by `hours` to preserve cache-per-window behavior. `JSONDecoder` validates the shape, unlike the source.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`. Map an `hours` flow with `flatMapLatest` into a `flow { while (true) { emit(fetch()); delay(60_000) } }`, using Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` with `List<Double?>` for `points`. Collect with `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), …)` so polling stops when no one observes, the analogue of polling only while mounted. `flatMapLatest` cancels the previous window's request, whereas React Query lets it land in its own key.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a view controller or `@MainActor` model that owns a polling `Task`, cancels it on window change or `viewDidDisappear`, and pauses on `NSApplication.didResignActiveNotification` / `UIApplication.didEnterBackgroundNotification` to mirror React Query's hidden-tab pause.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `ResponseHistory? History`, `bool IsLoading`, and `Exception? Error`, with `ResponseHistory` as a record `(double Hours, List<double?> Points)`. Fetch with a shared `HttpClient.GetAsync($"{basePath}/response-history?hours={hours.ToString(CultureInfo.InvariantCulture)}")`; the invariant culture keeps `1.5` from becoming `1,5`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"response-history {(int)response.StatusCode}")`. Otherwise deserialize with `JsonSerializer.DeserializeAsync<ResponseHistory>` using `JsonSerializerDefaults.Web`. Poll with a `PeriodicTimer(TimeSpan.FromSeconds(60))` inside an `async Task` loop cancelled by a `CancellationTokenSource` when `hours` changes or the page unloads, or with a `DispatcherQueueTimer` whose `Interval` is 60 seconds. Expose `Points` as `ObservableCollection<double?>` or a `List` for chart binding, and marshal updates through the `DispatcherQueue`. The differences from the source: .NET has no query cache or deduplication, so keep a `Dictionary<double, ResponseHistory>`; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has none; a failed poll should keep the previous `History` to match React Query; and pausing while the window is minimized needs `Window.VisibilityChanged`, because React Query's hidden-tab pause does not carry over.

## Design Decisions

**Decision**: The hook polls every 60 seconds with a hard-coded `refetchInterval`.

**Rationale**: The overview graph is a live portfolio summary; the source fixes the period at `60_000` ms in the hook rather than taking it from the caller, so every window length refreshes at the same rate.

**Approved**: pending

---

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source chooses the raw method and throws its own short `response-history <status>` message. As a result it drops the server's error detail and treats a 204 as a parse failure; both follow from that choice, and it matches the sibling `useHistory` hook.

**Approved**: pending

---

**Decision**: The hook sends only `hours` and leaves the bucket count to the backend.

**Rationale**: The backend route accepts `hours` and `buckets`, but the hook sends no `buckets`, so the series length is a backend decision and the consumer draws whatever length arrives.

**Approved**: pending

---

**Decision**: `hours` is passed through without validation.

**Rationale**: The parameter is typed `number` and its only caller supplies fixed constants from `SPANS` (24, 168, 720, 2160). Rejecting out-of-range values is left to the backend route.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of Concerns**: The hook contains no presentation. The base path and transport live in `StatusApiClient`, the caching, polling and state machine in React Query, and the rendering in `OverviewStats`.

**Unit Test Coverage**: There is no `use-response-history.test.ts` or `use-response-history.dom.test.tsx` beside the hook. The backend route has integration tests in `status-server`, but the hook itself is exercised only indirectly through components that render `OverviewStats`.

**Explicit Error Handling**: A non-ok status, a network rejection, and a JSON parse failure all reject the query function. Each one surfaces through the query's `error`, so none is swallowed. The server's error-body detail is not read.

**Timeout Handling**: The hook sets no timeout and passes no abort signal. A hung request leaves the query fetching and holds back the next interval refetch, but leaves no inconsistent state behind.

**Graceful Degradation**: A failed poll keeps the last successful series in `data`, and the caller falls back to an empty point list when no data exists, so the overview renders without the graph rather than failing.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial recipe extracted from `use-response-history.ts` |
