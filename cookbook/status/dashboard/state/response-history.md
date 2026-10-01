---
id: f5f0f19f-065e-4484-8c81-e591eee6db3c
title: Response History
domain: agentictoolkit://cookbook/status/dashboard/state/response-history
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that polls the portfolio-wide response-time history for the last
  N hours every 60 seconds
platforms:
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/history
references: []
approved-by: ''
approved-date: ''
---

# Response History

## Overview

Response History is state in the status dashboard that loads the portfolio-wide response-time history over the last `hours` hours, for the overview graph. It wraps one shared-cache read keyed by the window length. It requests `/response-history?hours=<hours>` through the dashboard's status API client (see [status-web-api](agentictoolkit://cookbook/status/dashboard/api)), polls every 60 seconds, and returns the read result typed as `ResponseHistory`. Its one caller in the package is the overview stats view, which passes the selected span's `hours` (24, 168, 720 or 2160) and draws `data.points` as the "avg response" sparkline, falling back to an empty array while no data is loaded. It is the portfolio-level sibling of [status-web-hooks-use-history](agentictoolkit://cookbook/status/dashboard/state/history), which loads one service's checks.

## Behavioral Requirements

- **hook-signature**: Response History MUST accept exactly one argument, `hours: number`, the length of the history window in hours.
- **return-value**: Response History MUST return the read result object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, a manual refetch operation), adding no fields of its own.
- **client-source**: Response History MUST obtain its HTTP client from the dashboard's status API client accessor, which returns the client supplied by the nearest provider, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The read MUST be cached under a key holding the literal `"response-history"` and the `hours` value, so each distinct window length has its own cache entry.
- **always-enabled**: The read MUST NOT set an enabled condition; it fetches whenever Response History starts being used, for any `hours` value.
- **request-path**: Each fetch MUST call the client's raw fetch operation with the relative path `/response-history?hours=<hours>`, which the client resolves against its base path (by default producing `/api/response-history?hours=<hours>`).
- **hours-interpolation**: The `hours` value MUST be interpolated into the query string by plain string conversion, with no percent-encoding, rounding, or range check (so `24` becomes `hours=24` and `1.5` becomes `hours=1.5`).
- **no-buckets-parameter**: The request MUST NOT include a `buckets` query parameter; the number of points in the series is chosen by the backend `/response-history` route.
- **request-init**: Each fetch MUST be issued with no extra request options, so it is a default GET with no added headers, body, or abort signal from Response History.
- **raw-fetch-not-json-helper**: Response History MUST use the client's raw fetch operation, not its JSON-decoding helper, so the helper's `Content-Type` header, its error-detail extraction, and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the read MUST fail with an error whose message is `response-history <status>` (for example `response-history 401`), placing the read in its error state.
- **error-detail-dropped**: On a non-ok response Response History MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the thrown error.
- **success-body**: When the response is ok, the read MUST resolve with the parsed JSON body, typed as `ResponseHistory` without runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, that parse failure MUST propagate as the read's error.
- **network-failure**: When the fetch call rejects (network failure or unreachable host), the failure MUST propagate unchanged as the read's error.
- **response-history-shape**: A successful result is declared as the exported shape `ResponseHistory` with fields `hours: number` and `points: (number | null)[]`.
- **points-semantics**: Each entry of `points` is the average response time in milliseconds of UP checks for one time bucket, ordered oldest to newest, and `null` means the bucket had no data or every check in it was down; Response History MUST pass these values through without reordering, filling, or filtering.
- **polling-interval**: Response History MUST refresh on a 60,000 ms interval, so while it is in use it refetches the history every 60 seconds.
- **no-other-hook-policy**: Apart from the refresh interval, Response History MUST NOT set its own freshness window, cache retention window, retry policy, background-refresh policy, or refresh-on-returning-focus policy; those behaviors MUST come from the host cache context's defaults and the shared cache mechanism's own defaults.
- **no-timeout**: Response History MUST NOT impose its own request timeout; a request that never settles leaves the read in its fetching state until the client or environment ends it.
- **no-persistence**: Response History MUST NOT write history to any durable store; results live only in the in-memory shared cache.
- **client-only-module**: Response History has no server-only or universal-rendering variant; it requires a live client execution context.
- **single-threaded-ordering**: Response History runs on a single execution thread; concurrent uses with the same `hours` MUST share one cache entry and are deduplicated by the shared cache rather than by Response History.

## Appearance

Not applicable — this is a data-fetching state concept, not a visual component.

## States

Not applicable — this is a data-fetching state concept, not a visual component.

## Accessibility

Not applicable — this is a data-fetching state concept, not a visual component.

## Conformance Test Vectors

There is no dedicated test file for this concept; these vectors are derived from the source. They assume a shared cache context with retries disabled and a status API client provider with a stubbed fetch.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-response-history-001 | always-enabled, request-path, request-init, client-source, no-buckets-parameter | Response History with `hours` = 24, using the default client; stub returns `200` and `{"hours":24,"points":[120,null,95]}` | Exactly one fetch to `/api/response-history?hours=24` with no extra request options and no `buckets` parameter |
| use-response-history-002 | success-body, points-semantics, response-history-shape | Same as 001 | `data` deep-equals `{"hours":24,"points":[120,null,95]}`; the `null` stays in position 1 |
| use-response-history-003 | client-source, request-path | Status API client provider with base path `/proxy`; Response History with `hours` = 168 | The requested URL is `/proxy/response-history?hours=168` |
| use-response-history-004 | hours-interpolation | Response History with `hours` = 1.5 | The requested path is `/api/response-history?hours=1.5` |
| use-response-history-005 | non-ok-error, error-detail-dropped | Response History with `hours` = 24; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `response-history 401`; the body text does not appear in the message |
| use-response-history-006 | parse-failure | Response History with `hours` = 24; stub returns `200` with body `not json` | `isError` is true; `error` is the parse error thrown while decoding the body |
| use-response-history-007 | network-failure | Response History with `hours` = 24; stub rejects with a network error | `isError` is true; `error` is that same network error |
| use-response-history-008 | polling-interval | Response History with `hours` = 24 and a controllable timer; first fetch succeeds | Advancing time by 60,000 ms triggers a second fetch to the same URL; advancing less than 60,000 ms does not |
| use-response-history-009 | query-key | Start using Response History with `hours` = 24, then switch to `hours` = 720 | Two fetches, one per window; returning to `24` within the cache's lifetime serves the cached 24-hour data |
| use-response-history-010 | raw-fetch-not-json-helper | Response History with `hours` = 24; inspect the request | No `Content-Type` header is added by Response History |
| use-response-history-011 | single-threaded-ordering | Two components both use Response History with `hours` = 24, sharing one cache context | One fetch is made; both receive the same `data` |

## Edge Cases

- **zero-or-negative-hours**: Response History with `hours` = 0 or a negative value MUST still fetch, sending `hours=0` or `hours=-5` as-is; how the backend `/response-history` route treats it (empty series, clamping, or an error status) is owned by that route, and Response History MUST surface whichever it returns.
- **non-finite-hours**: A non-finite `hours` value MUST be sent as whatever text the platform's numeric-to-string conversion produces (for example `hours=NaN` or `hours=Infinity` on the web platform), and cached under a key holding that value; Response History performs no numeric validation, and its one caller only passes the finite constants for the four spans.
- **large-window**: The largest window the caller uses is 2,160 hours (90 days); Response History applies no upper bound of its own.
- **empty-points**: A successful response with `points: []` MUST resolve as data; Response History applies no emptiness check (the overview stats view separately hides the card sparkline when fewer than two non-null points exist).
- **all-null-points**: A series whose every entry is `null` MUST resolve as data unchanged; per its semantics this means no data or all checks down in every bucket.
- **malformed-body**: A body that is valid JSON but not shaped like `ResponseHistory` (for example missing `points`) MUST resolve as data unchanged; Response History performs no shape validation, and a consumer reading `data.points` receives an undefined value (the caller's fallback-to-empty-array behavior covers that case).
- **hours-mismatch**: If the backend's `hours` field differs from the requested value, Response History MUST return the body unchanged; it does not compare the two.
- **204-response**: A `204 No Content` response is `ok`, so Response History MUST attempt to parse the empty body as JSON, which fails and puts the read in its error state.
- **server-error**: A non-2xx status, including the `401` the route documents, MUST produce an error with message `response-history <status>`; retries follow the host cache context's policy (the shared cache mechanism's own default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected fetch MUST surface as the read's error with no Response-History-level retry, fallback data, or message rewriting; the 60-second poll continues to attempt refetches while in use.
- **error-after-success**: When a poll fails after an earlier success, the shared cache MUST keep the previous `data` alongside the new `error`, so the caller keeps drawing the last good series.
- **hung-request**: With no timeout or abort signal from Response History, a request that never settles MUST leave the read in its fetching state; the shared cache does not start the next interval refetch while one is still in flight.
- **hours-change-mid-flight**: When `hours` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **background-tab**: Because no override is set, the shared cache's default MUST apply: interval refetches pause while the app is in the background.
- **unmount**: When the last consumer using a given `hours` stops using it, interval polling for that key MUST stop; the cached result remains until the host cache context's retention window elapses.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hours` | `number` | — (required) | History window length, sent as the `hours` query parameter and used in the cache key. |
| Refresh interval | number (hard-coded) | `60_000` ms | Polling period while in use; not configurable by the caller. |
| `buckets` | — (not sent) | backend default | Response History sends no `buckets` parameter, so the series length is the backend route's default. |
| Status API client provider | client / base path | default client, base path `/api` | Injected through context; determines where `/response-history` is resolved and allows a test double. |
| Host cache context | shared cache | library defaults | Supplied by the host; controls retry, freshness window, cache retention window, refresh-on-returning-focus, and background polling. |

## Deep Linking

Not applicable: Response History reads no URL and registers no route; `hours` is passed in by the caller.

## Localization

Response History produces one hard-coded English string, surfaced as the read's error message rather than rendered by Response History itself. Its one caller, the overview stats view, does not display it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `response-history <status>` | Message of the error raised on a non-ok response, for example `response-history 401` |

## Accessibility Options

Not applicable: Response History renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: Response History reads no flags and has no enabled gate.

## Analytics

Not applicable: Response History emits no analytics events.

## Privacy

Not applicable: Response History sends only the `hours` window, attaches no credentials or tokens itself (any authentication is added by the host's proxy behind the status API client's base path), receives only aggregate response times, and stores results only in the in-memory cache.

## Logging

Not applicable: Response History makes no log calls; failures reach the caller only through the read's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-response-history.ts`, a thin `useQuery` wrapper that also exports the `ResponseHistory` interface (unlike `useHistory`, whose types live in `src/types.ts`). It depends on `useStatusApi` from `src/api/client.ts`. React Query supplies caching, deduplication, interval polling, retry, and the loading and error state machine, including the `staleTime`, `gcTime`, `retry`, `refetchIntervalInBackground` and `refetchOnWindowFocus` options that the hook itself leaves unset so the host `QueryClient`'s defaults apply. The `hours` value is interpolated into the query string via JavaScript template-string coercion, with no `encodeURIComponent`, rounding, or range check. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `ResponseHistory?` (a `Codable` struct with `hours: Double` and `points: [Double?]`), an error, and a loading flag. Load inside `.task(id: hours)` with a loop of `URLSession.shared.data(for:)` followed by `try await Task.sleep(for: .seconds(60))`; the task is cancelled when `hours` changes or the view disappears, which matches the per-key polling. Build the query with `URLComponents`. There is no built-in query cache, so keep a dictionary keyed by `hours` to preserve cache-per-window behavior. `JSONDecoder` validates the shape, unlike the source.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`. Map an `hours` flow with `flatMapLatest` into a `flow { while (true) { emit(fetch()); delay(60_000) } }`, using Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` with `List<Double?>` for `points`. Collect with `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), …)` so polling stops when no one observes, the analogue of polling only while in use. `flatMapLatest` cancels the previous window's request, whereas the source lets it land in its own key.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a view controller or `@MainActor` model that owns a polling `Task`, cancels it on window change or `viewDidDisappear`, and pauses on `NSApplication.didResignActiveNotification` / `UIApplication.didEnterBackgroundNotification` to mirror the hidden-tab pause.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `ResponseHistory? History`, `bool IsLoading`, and `Exception? Error`, with `ResponseHistory` as a record `(double Hours, List<double?> Points)`. Fetch with a shared `HttpClient.GetAsync($"{basePath}/response-history?hours={hours.ToString(CultureInfo.InvariantCulture)}")`; the invariant culture keeps `1.5` from becoming `1,5`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"response-history {(int)response.StatusCode}")`. Otherwise deserialize with `JsonSerializer.DeserializeAsync<ResponseHistory>` using `JsonSerializerDefaults.Web`. Poll with a `PeriodicTimer(TimeSpan.FromSeconds(60))` inside an `async Task` loop cancelled by a `CancellationTokenSource` when `hours` changes or the page unloads, or with a `DispatcherQueueTimer` whose `Interval` is 60 seconds. Expose `Points` as `ObservableCollection<double?>` or a `List` for chart binding, and marshal updates through the `DispatcherQueue`. The differences from the source: .NET has no query cache or deduplication, so keep a `Dictionary<double, ResponseHistory>`; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has none; a failed poll should keep the previous `History` to match the source's graceful degradation; and pausing while the window is minimized needs `Window.VisibilityChanged`, because the hidden-tab pause does not carry over.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-response-history.ts` |

## Design Decisions

**Decision**: Response History polls every 60 seconds with a hard-coded refresh interval.

**Rationale**: The overview graph is a live portfolio summary; the source fixes the period at `60_000` ms rather than taking it from the caller, so every window length refreshes at the same rate.

**Approved**: pending

---

**Decision**: Response History fetches through the client's raw fetch operation and checks the response's `ok` flag itself, instead of using the client's JSON-decoding helper.

**Rationale**: The source chooses the raw method and raises its own short `response-history <status>` error message. As a result it drops the server's error detail and treats a 204 as a parse failure; both follow from that choice, and it matches the sibling History concept.

**Approved**: pending

---

**Decision**: Response History sends only `hours` and leaves the bucket count to the backend.

**Rationale**: The backend route accepts `hours` and `buckets`, but Response History sends no `buckets`, so the series length is a backend decision and the consumer draws whatever length arrives.

**Approved**: pending

---

**Decision**: `hours` is passed through without validation.

**Rationale**: The parameter is numeric and its only caller supplies fixed constants (24, 168, 720, 2160). Rejecting out-of-range values is left to the backend route.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-response-history.ts` |
</content>
