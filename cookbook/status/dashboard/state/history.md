---
id: 3bb63ddd-6c9a-41c1-a906-6c8542cb4e5c
title: Health Check History
domain: agentictoolkit://cookbook/status/dashboard/state/history
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Cached state that fetches one service's 24-hour health-check history from
  the status API, idle until a slug is selected.
platforms:
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/activity-history
references: []
approved-by: ''
approved-date: ''
---

# Health Check History

## Overview

History is state in the status dashboard that loads the last 24 hours of health checks for a single monitored service. It wraps one cached read keyed by the service slug, requests `/history?service=<slug>&hours=24` through the dashboard's status API client (see [status-web-api](agentictoolkit://cookbook/status/dashboard/api)), and returns the query result typed as `HistoryResponse`. Passing no slug leaves the query disabled, so a detail pane can use History unconditionally before any service is selected. Its one caller in the package is the detail panel, which feeds `data.checks` into the response-time chart and status strip and shows `loading…` while the result is loading.

## Behavioral Requirements

- **hook-signature**: History MUST accept exactly one argument, `slug` (a string or none), identifying the service whose history is requested.
- **return-value**: History MUST return the shared cache's query result unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`), adding no fields of its own.
- **client-source**: History MUST obtain its HTTP client from the app's API context, which supplies the status API client from the nearest provider, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the key `["history", slug]`, so each distinct slug (including no slug) has its own cache entry.
- **disabled-without-slug**: When `slug` is none or the empty string, the query MUST be disabled and MUST NOT issue any request.
- **enabled-with-slug**: When `slug` is a non-empty string, the query MUST be enabled and MUST fetch according to the shared cache's policy.
- **request-path**: Each fetch MUST call the client's raw request method with the relative path `/history?service=<encoded slug>&hours=24`, which the client resolves against its base path (by default producing `/api/history?service=<encoded slug>&hours=24`).
- **slug-encoding**: The slug MUST be percent-encoded before being placed in the `service` query parameter.
- **fixed-window**: The `hours` query parameter MUST always be the literal `24`; History exposes no way to request a different window.
- **request-init**: Each fetch MUST be issued with no added request options, so it is a default GET with no added headers, body, or cancellation signal from History.
- **raw-fetch-not-json-helper**: History MUST use the client's raw request method, not its JSON-body helper, so that helper's `Content-Type` header, its error-detail extraction, and its "no-content response becomes an empty result" handling do not apply.
- **non-ok-error**: When the response is not ok, the query's read step MUST fail with an error whose message is `history <status>` (for example `history 503`), placing the query in its error state.
- **error-detail-dropped**: On a non-ok response History MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the failure.
- **success-body**: When the response is ok, the query's read step MUST resolve with the parsed response body, typed as `HistoryResponse` without runtime shape validation.
- **parse-failure**: When an ok response's body is not valid JSON, the parse failure MUST propagate as the query's error.
- **network-failure**: When the request itself fails (network failure or unreachable host), the failure MUST propagate unchanged as the query's error.
- **history-response-shape**: A successful result is declared as `HistoryResponse` with fields `service` (string), `hours` (number), and `checks` (a `HistoryCheck` array).
- **history-check-shape**: Each `HistoryCheck` is declared with fields `status` (`"healthy" | "degraded" | "down" | "unknown"`), `responseTimeMs` (number or none), `statusCode` (number or none), `error` (string or none), and `checkedAt` (string).
- **no-hook-level-policy**: History MUST NOT set its own freshness window, cache retention window, retry count, automatic refresh interval, or refresh-on-returning-focus behavior; caching, retry, and refresh behavior MUST come entirely from the shared cache's host-supplied and library defaults.
- **no-timeout**: History MUST NOT impose its own request timeout; a request that never settles leaves the query pending until the client or runtime ends it.
- **no-persistence**: History MUST NOT write history to any durable store; results live only in the in-memory shared cache.
- **client-only-module**: History has no server-only or universal-rendering variant; it requires a live client execution context.
- **single-threaded-ordering**: History runs on a single execution thread; concurrent reads with the same slug MUST share one cache entry and are deduplicated by the shared cache rather than by History itself.

## Appearance

Not applicable — this is a data-fetching concept, not a visual component.

## States

Not applicable — this is a data-fetching concept, not a visual component.

## Accessibility

Not applicable — this is a data-fetching concept, not a visual component.

## Conformance Test Vectors

No test file exists for the source directly; these vectors are derived from the source. They assume a shared cache with retries disabled and a stubbed transport.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-history-001 | disabled-without-slug, query-key | History with no slug | No request is made; the result's status is `"pending"` with fetch status `"idle"`; `data` is not yet available |
| use-history-002 | disabled-without-slug | History with an empty-string slug | No request is made |
| use-history-003 | enabled-with-slug, request-path, fixed-window, request-init, client-source | History with slug `"api"` and the default client; stub returns `200` and `{"service":"api","hours":24,"checks":[]}` | Exactly one request to `/api/history?service=api&hours=24` with no added options; `data` deep-equals the body |
| use-history-004 | slug-encoding | History with slug `"a b/c&d"` | The requested path is `/api/history?service=a%20b%2Fc%26d&hours=24` |
| use-history-005 | client-source, request-path | API base path `/proxy`, History with slug `"web"` | The requested URL is `/proxy/history?service=web&hours=24` |
| use-history-006 | non-ok-error, error-detail-dropped | History with slug `"api"`; stub returns `503` with body `{"error":"down for maintenance"}` | `isError` is true; error message is exactly `history 503`; the body text does not appear in the message |
| use-history-007 | parse-failure | History with slug `"api"`; stub returns `200` with body `not json` | `isError` is true; error is the parse failure from reading the body |
| use-history-008 | network-failure | History with slug `"api"`; stub fails with a network error | `isError` is true; error is that same failure |
| use-history-009 | query-key | Use History with slug `"a"`, then with slug `"b"` | Two requests, one per slug; returning to `"a"` within the cache's lifetime serves the cached `"a"` data |
| use-history-010 | raw-fetch-not-json-helper | History with slug `"api"`; inspect the request | No `Content-Type` header is added by History |

## Edge Cases

- **null-slug**: With `slug` none, History MUST stay idle and return no data; the slug is never dereferenced because the query is disabled.
- **empty-slug**: The empty string is falsy, so History with an empty-string slug MUST behave exactly like History with no slug and MUST NOT fetch.
- **special-characters-in-slug**: A slug containing spaces, `&`, `/`, `?`, or `=` MUST be percent-encoded so it cannot inject extra query parameters.
- **unknown-slug**: A slug the backend does not recognize is sent as-is; whether the backend answers with an empty `checks` array or an error status is owned by the backend `/history` route, and History MUST surface whichever it returns (data, or `history <status>`).
- **empty-checks**: A successful response with `checks: []` MUST resolve as data; History applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `HistoryResponse` (for example missing `checks`) MUST resolve as data unchanged; History performs no shape validation, and a consumer reading `data.checks` receives nothing.
- **204-response**: A response with no body is still ok, so History MUST attempt to parse the empty body, which fails and puts the query in its error state (unlike the client's JSON-body helper, which maps a no-content response to an empty result).
- **server-error**: A non-2xx status MUST produce an error whose message is `history <status>`; retries after that follow the shared cache's policy (the library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A failed request MUST surface as the query error with no extra retry, fallback data, or message rewriting from History.
- **hung-request**: With no timeout or cancellation signal from History, a request that never settles MUST leave the query in its fetching state indefinitely.
- **slug-change-mid-flight**: When `slug` changes while a request is in flight, the new slug MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new slug's data.
- **concurrent-callers**: Two consumers using History with the same slug MUST share one cache entry; the shared cache deduplicates the in-flight request.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `slug` | string or none | — (required) | Service identifier; a falsy value disables the query. |
| `hours` | number (hard-coded) | `24` | History window sent in the `hours` query parameter; not configurable. |
| Status API provider (client / base path) | injected client / string | default client, base path `/api` | Injected through the app's API context; determines where `/history` is resolved and allows a test double. |
| Shared cache | injected cache context | library defaults | Supplied by the host; controls retry, freshness window, cache retention, and refresh triggers. |

## Deep Linking

Not applicable: History reads no URL and registers no route; the slug is passed in by the caller.

## Localization

History produces one hard-coded English string, surfaced as the query's error message rather than rendered by History. Its one caller, the detail panel, does not display it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `history <status>` | Message of the error on a non-ok response, for example `history 503` |

## Accessibility Options

Not applicable: History renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: History reads no flags; the only gate is whether a slug is present.

## Analytics

Not applicable: History emits no analytics events.

## Privacy

Not applicable: History sends only the service slug and a fixed `hours=24` window, attaches no credentials or tokens itself, and stores results only in the in-memory shared cache.

## Logging

Not applicable: History makes no log calls; failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-history.ts`, a thin `useQuery` wrapper, exported as `useHistory(slug: string | null)`. It depends on `useStatusApi` from `src/api/client.ts` and on `HistoryResponse`/`HistoryCheck` from `src/types.ts`. TanStack React Query supplies caching, deduplication, retry, and the loading and error state machine. The raw request method is `api.fetch`; the JSON-body helper it is deliberately not used is `api.json`. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`. The module is marked `"use client"`.
- **SwiftUI**: Start from an `@Observable` model (or `@MainActor` class) holding `HistoryResponse?`, an error, and a loading flag. Load with `URLSession.shared.data(for:)` inside `.task(id: slug)`, which cancels and restarts when the slug changes; this is the equivalent of the `["history", slug]` key. Build the query with `URLComponents`/`URLQueryItem`, which encodes values for you. Decode with `JSONDecoder` into `Codable` structs. Unlike the source, decoding validates the shape. There is no built-in query cache, so add a dictionary keyed by slug if you need to keep the source's cache-per-slug behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`. Collect a `slug` flow with `flatMapLatest` or `mapLatest`, and use Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. `flatMapLatest` cancels the previous slug's request. The source does not; there, the stale request simply lands in its own cache key.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a view controller or a `@MainActor` model that cancels the prior `Task` when the selection changes, and `NSCache` or a dictionary keyed by slug for caching.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `HistoryResponse? History`, `bool IsLoading`, and `Exception? Error`. Fetch with a shared `HttpClient.GetAsync($"{basePath}/history?service={Uri.EscapeDataString(slug)}&hours=24")` inside an `async Task`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"history {(int)response.StatusCode}")`. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<HistoryResponse>` using `JsonSerializerDefaults.Web` for camelCase. Expose `checks` as `ObservableCollection<HistoryCheck>` or a `List` for chart binding, and marshal updates through the `DispatcherQueue`. A null or empty slug skips the call. The differences from the source: .NET has no query cache or deduplication, so keep a `Dictionary<string, HistoryResponse>` and a `CancellationTokenSource` per selection; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout; and retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because the source's default retry does not carry over.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-history.ts` |

## Design Decisions

**Decision**: History fetches through the client's raw request method and checks whether the response is ok itself, instead of calling its JSON-body helper.

**Rationale**: The source chooses the raw method and produces its own short `history <status>` message. As a result, it drops the server's error detail and treats a no-content response as a parse failure. Both are deliberate consequences of that choice, recorded here so ports keep them.

**Approved**: pending

---

**Decision**: The history window is fixed at 24 hours.

**Rationale**: The consuming pane labels itself `Response time · 24h`, and History hard-codes `hours=24` to match. A different window would need a new parameter.

**Approved**: pending

---

**Decision**: Cache, retry, and refresh policy are left to the shared cache.

**Rationale**: History sets only its cache key, its read step, and whether it is enabled. Tests in the package build their cache with retries disabled, and production hosts supply their own defaults. A port MUST get its retry and staleness from the equivalent app-level policy rather than hard-coding them in History.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |

**Separation of Concerns**: The hook contains no presentation. The base path and transport live in `StatusApiClient`, the caching and state machine in React Query, and the rendering in `DetailPanel`.

**Unit Test Coverage**: There is no `use-history.test.ts` or `use-history.dom.test.tsx` beside the hook. It is exercised only indirectly, through components that render `DetailPanel`.

**Explicit Error Handling**: A non-ok status, a network rejection, and a JSON parse failure all reject the query function. Each one surfaces through the query's `error`, so none is swallowed. The server's error-body detail is not read.

**Timeout Handling**: The hook sets no timeout and passes no abort signal. A hung request leaves the query fetching, but it leaves no inconsistent state behind: the cache entry simply stays pending.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-history.ts` |
</content>
