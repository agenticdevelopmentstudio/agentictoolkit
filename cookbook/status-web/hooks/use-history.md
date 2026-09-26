---
id: 3bb63ddd-6c9a-41c1-a906-6c8542cb4e5c
title: useHistory
domain: agentictoolkit://cookbook/status-web/hooks/use-history
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React Query hook that fetches one service's 24-hour health-check history
  from the status API, idle until a slug is selected
platforms:
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status-web/api
related:
- agentictoolkit://cookbook/status-web/hooks/use-activity-history
references: []
approved-by: ''
approved-date: ''
---

# useHistory

## Overview

`useHistory` is a React hook in the status dashboard (`status-web/src/hooks/use-history.ts`) that loads the last 24 hours of health checks for a single monitored service. It wraps one TanStack React Query `useQuery` call keyed by the service slug, requests `/history?service=<slug>&hours=24` through the dashboard's `StatusApiClient` (see [status-web-api](agentictoolkit://cookbook/status-web/api)), and returns the query result typed as `HistoryResponse`. Passing `null` leaves the query disabled, so a detail pane can call the hook unconditionally before any service is selected. Its one caller in the package is `DetailPanel`, which feeds `data.checks` into the response-time chart and status strip and shows `loading…` while `isLoading` is true.

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

## Appearance

Not applicable — this is a data-fetching React hook, not a visual component.

## States

Not applicable — this is a data-fetching React hook, not a visual component.

## Accessibility

Not applicable — this is a data-fetching React hook, not a visual component.

## Conformance Test Vectors

No test file exists beside `use-history.ts`; these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's other `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-history-001 | disabled-without-slug, query-key | `useHistory(null)` | No `fetch` call is made; the result's `status` is `"pending"` with `fetchStatus` `"idle"`; `data` is `undefined` |
| use-history-002 | disabled-without-slug | `useHistory("")` | No `fetch` call is made |
| use-history-003 | enabled-with-slug, request-path, fixed-window, request-init, client-source | `useHistory("api")` with the default client; stub returns `200` and `{"service":"api","hours":24,"checks":[]}` | Exactly one `fetch` to `/api/history?service=api&hours=24` with no init argument; `data` deep-equals the body |
| use-history-004 | slug-encoding | `useHistory("a b/c&d")` | The requested path is `/api/history?service=a%20b%2Fc%26d&hours=24` |
| use-history-005 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useHistory("web")` | The requested URL is `/proxy/history?service=web&hours=24` |
| use-history-006 | non-ok-error, error-detail-dropped | `useHistory("api")`; stub returns `503` with body `{"error":"down for maintenance"}` | `isError` is true; `error.message` is exactly `history 503`; the body text does not appear in the message |
| use-history-007 | parse-failure | `useHistory("api")`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-history-008 | network-failure | `useHistory("api")`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-history-009 | query-key | Render `useHistory("a")`, then rerender with `useHistory("b")` | Two fetches, one per slug; returning to `"a"` within the cache's lifetime serves the cached `"a"` data |
| use-history-010 | raw-fetch-not-json-helper | `useHistory("api")`; inspect the request | No `Content-Type` header is added by the hook |

## Edge Cases

- **null-slug**: With `slug` `null`, the hook MUST stay idle and return `data` `undefined`; the `slug!` non-null assertion in the query function is never reached because the query is disabled.
- **empty-slug**: The empty string is falsy, so `useHistory("")` MUST behave exactly like `useHistory(null)` and MUST NOT fetch.
- **special-characters-in-slug**: A slug containing spaces, `&`, `/`, `?`, or `=` MUST be percent-encoded so it cannot inject extra query parameters.
- **unknown-slug**: A slug the backend does not recognize is sent as-is; whether the backend answers with an empty `checks` array or an error status is owned by the backend `/history` route, and the hook MUST surface whichever it returns (data, or `history <status>`).
- **empty-checks**: A successful response with `checks: []` MUST resolve as data; the hook applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `HistoryResponse` (for example missing `checks`) MUST resolve as data unchanged; the hook performs no shape validation, and a consumer reading `data.checks` receives `undefined`.
- **204-response**: A `204 No Content` response is `ok`, so the hook MUST call `response.json()` on the empty body, which rejects and puts the query in its error state (unlike the client's `json` helper, which maps 204 to `undefined`).
- **server-error**: A non-2xx status MUST produce `Error("history <status>")`; retries after that follow the host `QueryClient` policy (React Query's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected `fetch` MUST surface as the query error with no hook-level retry, fallback data, or message rewriting.
- **hung-request**: With no timeout or abort signal from the hook, a request that never settles MUST leave the query in its fetching state indefinitely.
- **slug-change-mid-flight**: When `slug` changes while a request is in flight, the new slug MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new slug's data.
- **concurrent-callers**: Two components calling `useHistory` with the same slug MUST share one cache entry; React Query deduplicates the in-flight request.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `slug` | `string \| null` | — (required) | Service identifier; a falsy value disables the query. |
| `hours` | number (hard-coded) | `24` | History window sent in the `hours` query parameter; not configurable. |
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | default client, base path `/api` | Injected through React context; determines where `/history` is resolved and allows a test double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`; controls retry, stale time, cache lifetime, and refetch triggers. |

## Deep Linking

Not applicable: the hook reads no URL and registers no route; the slug is passed in by the caller.

## Localization

The hook produces one hard-coded English string, surfaced as the query's `Error.message` rather than rendered by the hook. Its one caller, `DetailPanel`, does not display it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `history <status>` | Message of the `Error` thrown on a non-ok response, for example `history 503` |

## Accessibility Options

Not applicable: the hook renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the hook reads no flags; the only gate is the `enabled: !!slug` condition.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook sends only the service slug and a fixed `hours=24` window, attaches no credentials or tokens itself, and stores results only in the in-memory query cache.

## Logging

Not applicable: the hook makes no log calls; failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-history.ts`, a thin `useQuery` wrapper. It depends on `useStatusApi` from `src/api/client.ts` and on `HistoryResponse`/`HistoryCheck` from `src/types.ts`. React Query supplies caching, deduplication, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` model (or `@MainActor` class) holding `HistoryResponse?`, an error, and a loading flag. Load with `URLSession.shared.data(for:)` inside `.task(id: slug)`, which cancels and restarts when the slug changes; this is the equivalent of the `["history", slug]` key. Build the query with `URLComponents`/`URLQueryItem`, which encodes values for you. Decode with `JSONDecoder` into `Codable` structs. Unlike the source, decoding validates the shape. There is no built-in query cache, so add a dictionary keyed by slug if you need to keep React Query's cache-per-slug behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`. Collect a `slug` flow with `flatMapLatest` or `mapLatest`, and use Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. `flatMapLatest` cancels the previous slug's request. React Query does not; there, the stale request simply lands in its own cache key.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a view controller or a `@MainActor` model that cancels the prior `Task` when the selection changes, and `NSCache` or a dictionary keyed by slug for caching.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `HistoryResponse? History`, `bool IsLoading`, and `Exception? Error`. Fetch with a shared `HttpClient.GetAsync($"{basePath}/history?service={Uri.EscapeDataString(slug)}&hours=24")` inside an `async Task`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"history {(int)response.StatusCode}")`. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<HistoryResponse>` using `JsonSerializerDefaults.Web` for camelCase. Expose `checks` as `ObservableCollection<HistoryCheck>` or a `List` for chart binding, and marshal updates through the `DispatcherQueue`. A null or empty slug skips the call. The differences from the source: .NET has no query cache or deduplication, so keep a `Dictionary<string, HistoryResponse>` and a `CancellationTokenSource` per selection; `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout; and retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because React Query's default retry does not carry over.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-history.ts` |

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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-history.ts` |
