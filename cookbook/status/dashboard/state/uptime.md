---
id: e322fd0c-1552-4bd9-b129-3c809af3a972
title: Uptime State
domain: agentictoolkit://cookbook/status/dashboard/state/uptime
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that loads per-service daily uptime for the last N days (default
  90) from the status backend, fetched once with no polling.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/response-history
- agentictoolkit://cookbook/status/service/monitor/uptime
references: []
approved-by: ''
approved-date: ''
---

# Uptime State

## Overview

The uptime state loads per-service daily uptime over the last `days` days. It wraps one shared read keyed by the window length, requests `/uptime?days=<days>` through the dashboard's injected API client (see [status-web-api](agentictoolkit://cookbook/status/dashboard/api)), and returns the read result typed as the uptime response. Unlike its sibling [status-web-hooks-use-response-history](agentictoolkit://cookbook/status/dashboard/state/response-history), it sets no polling interval, so it does not poll. It has two consumers in the dashboard, both passing `90`: the dashboard view, which builds a per-service map from `data.services` and picks the selected service's entry, and the overview tab, which reduces `data.services` to one portfolio percentage. The numbers themselves are computed by the backend `/uptime` route in the status service (see [status-server-monitor-uptime](agentictoolkit://cookbook/status/service/monitor/uptime)).

## Behavioral Requirements

- **hook-signature**: The state MUST accept one optional argument, `days`, a number giving the length of the uptime window in days.
- **days-default**: When `days` is omitted or `undefined`, the state MUST use `90`.
- **return-value**: The state MUST return the full read-result object unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`), adding no fields of its own.
- **client-source**: The state MUST obtain its HTTP client through dependency injection, which resolves to the client supplied by the nearest override provider, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The read MUST be cached under a key combining `uptime` and the requested `days`, so each distinct window length has its own cache entry.
- **always-enabled**: The read MUST NOT be conditionally disabled; it fetches whenever the state is mounted, for any `days` value.
- **request-path**: Each fetch MUST request the relative path `/uptime?days=<days>`, which the client resolves against its base path (by default producing `/api/uptime?days=<days>`).
- **days-interpolation**: The `days` value MUST be interpolated into the query string by plain string conversion, with no percent-encoding, rounding, or range check (so `30` becomes `days=30` and `1.5` becomes `days=1.5`).
- **request-init**: Each fetch MUST be issued with no extra request options, so it is a default `GET` with no added headers, body, or cancellation signal from the state.
- **raw-fetch-not-json-helper**: The state MUST use the client's basic request operation, not its JSON-decoding convenience method, so the convenience method's `Content-Type` header, its error-detail extraction, and its 204-as-`undefined` handling do not apply.
- **non-ok-error**: When the response's `ok` flag is false, the read MUST throw, with the message `uptime <status>` (for example `uptime 401`), placing the read in its error state.
- **error-detail-dropped**: On a non-ok response the state MUST NOT read the response body; any `error` or `message` detail the server returns is not included in the thrown error.
- **success-body**: When the response is ok, the read MUST resolve with the parsed JSON body, typed as the uptime response without runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the rejection from parsing it as JSON MUST propagate as the read's error.
- **network-failure**: When the underlying request rejects (network failure or unreachable host), the rejection MUST propagate unchanged as the read's error.
- **uptime-response-shape**: A successful result MUST carry `services` (a list of service entries) and `days` (a number).
- **uptime-service-shape**: Each service entry MUST carry `slug` and `name` (strings), `uptimePercent` (a number or `null`), `totalChecks` (a number), and `daily` (a list of daily entries).
- **uptime-day-shape**: Each daily entry MUST carry `day` (a string), `status` (one of `"healthy"`, `"degraded"` or `"down"`), and `uptimePercent` (a number or `null`).
- **pass-through**: The state MUST return the service list and each service's `daily` list in the order the backend sent them, without sorting, filtering, filling missing days, or recomputing percentages.
- **no-polling**: The read MUST NOT poll on a timer; after the first successful load, refetches happen only through the platform's default triggers (remount of a stale read, window refocus, reconnect) or an explicit manual refetch.
- **no-other-hook-policy**: The state MUST NOT set its own staleness duration, cache lifetime, retry count, focus-refetch or reconnect-refetch behavior; those come from the host cache's defaults.
- **no-timeout**: The state MUST NOT impose its own request timeout; a request that never settles leaves the read fetching until the client or browser ends it.
- **no-persistence**: The state MUST NOT write uptime data to any durable store; results live only in the in-memory shared cache.
- **single-threaded-ordering**: Concurrent calls with the same `days` MUST share one cache entry and be deduplicated by the shared cache rather than by the state, so multiple consumers calling this state with the same window under one shared cache issue one request.

## Appearance

Not applicable — this is a data-fetching state, not a visual component.

## States

Not applicable — this is a data-fetching state, not a visual component.

## Accessibility

Not applicable — this is a data-fetching state, not a visual component.

## Conformance Test Vectors

No dedicated test exists for this state; the consuming views' tests mock it out entirely (returning a result with `data: undefined, isLoading: false`), so these vectors are derived from the source. Wrap the state in a shared cache provider configured with retries disabled and an overriding client with a stubbed transport.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-uptime-001 | days-default, always-enabled, request-path, request-init, client-source | This state called with no argument, using the default client; stub returns `200` and `{"services":[],"days":90}` | Exactly one fetch to `/api/uptime?days=90` with no extra request options |
| use-uptime-002 | success-body, uptime-response-shape, uptime-service-shape, uptime-day-shape, pass-through | This state called with `90`; stub returns `200` and `{"services":[{"slug":"b","name":"B","uptimePercent":null,"totalChecks":0,"daily":[]},{"slug":"a","name":"A","uptimePercent":99.5,"totalChecks":200,"daily":[{"day":"2026-09-23","status":"degraded","uptimePercent":99}]}],"days":90}` | `data` deep-equals the body; service `b` stays first and its `null` percentage is unchanged |
| use-uptime-003 | client-source, request-path | An overriding client with base path `/proxy`; this state called with `30` | The requested URL is `/proxy/uptime?days=30` |
| use-uptime-004 | days-interpolation | This state called with `1.5` | The requested path is `/api/uptime?days=1.5` |
| use-uptime-005 | non-ok-error, error-detail-dropped | This state called with `90`; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `uptime 401`; the body text does not appear in the message |
| use-uptime-006 | parse-failure | This state called with `90`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown while parsing the body |
| use-uptime-007 | network-failure | This state called with `90`; stub rejects with a network-level error | `isError` is true; `error` is that same failure |
| use-uptime-008 | no-polling | This state called with `90`, with fake timers; first fetch succeeds; the application keeps focus | Advancing time by 600,000 ms triggers no second fetch |
| use-uptime-009 | query-key | Render this state with `90`, then rerender with `30` | Two fetches, one per window; returning to `90` within the cache's lifetime serves the cached 90-day data |
| use-uptime-010 | raw-fetch-not-json-helper | This state called with `90`; inspect the request | No `Content-Type` header is added by the state |
| use-uptime-011 | single-threaded-ordering | Two consumers both use this state with `90` under one shared cache | One fetch is made; both receive the same `data` |
| use-uptime-012 | return-value | This state called with `90`, before the stub resolves | The result has `isLoading` true and `data` undefined, and exposes no keys beyond the read result's own |

## Edge Cases

- **zero-or-negative-days**: Calling this state with `0` or a negative value MUST still fetch, sending `days=0` or `days=-5` as-is. The backend `/uptime` route owns the response: it maps `0` or an unparsable value to its default of 90, and clamps the result to 1–365, so `-5` becomes `1`; the state surfaces whatever arrives.
- **fractional-days**: Calling this state with `1.5` MUST send `days=1.5` and cache under a key holding `1.5`; the backend reads it as `1`, so the response `days` field is `1` while the cache key holds `1.5`.
- **non-finite-days**: `NaN` or `Infinity` MUST be sent as the literal text `days=NaN` or `days=Infinity` and cached under a key holding that value; the state performs no numeric validation, and both known consumers pass the constant `90`.
- **large-window**: A `days` value above 365 MUST be sent unchanged; the backend clamps it to 365, and the state does not compare the requested and returned `days`.
- **days-mismatch**: If the backend's `days` field differs from the requested value, the state MUST return the body unchanged.
- **empty-services**: A successful response with `services: []` MUST resolve as data; the state applies no emptiness check (the portfolio percentage then yields `null`).
- **null-percentages**: A service or day whose `uptimePercent` is `null` (the backend's value when a service has zero checks) MUST resolve unchanged; the state does not fill or drop it.
- **malformed-body**: A body that is valid JSON but not shaped like the uptime response (for example missing `services`) MUST resolve as data unchanged; the state performs no shape validation, and both known consumers guard by defaulting a missing services list to an empty one.
- **204-response**: A `204 No Content` response is `ok`, so the state MUST attempt to parse the empty body as JSON, which rejects and puts the read in its error state.
- **server-error**: A non-2xx status, including the `401` the route's OpenAPI entry documents, MUST produce an error with the message `uptime <status>`; retries follow the host cache's policy (the platform's library default is 3 retries with exponential backoff when the host sets none).
- **unreachable-server**: A rejected request MUST surface as the read's error with no state-level retry, fallback data, or message rewriting; with no polling, the read stays in error until a default platform trigger or a manual refetch runs it again.
- **error-after-success**: When a refetch fails after an earlier success, the platform MUST keep the previous `data` alongside the new `error`, so callers keep showing the last good uptime.
- **hung-request**: With no timeout or cancellation signal from the state, a request that never settles MUST leave the read in its fetching state indefinitely.
- **days-change-mid-flight**: When `days` changes while a request is in flight, the new window MUST get its own cache entry and request; the earlier request resolves into its own key and does not overwrite the new window's data.
- **stale-data**: Because the state sets no polling interval, uptime shown on a dashboard left open and focused MUST stay at the first-loaded values until a refocus, reconnect, remount, or manual refetch triggers a new fetch.
- **unmount**: When the last consumer using a given `days` unmounts, the cached result MUST remain until the host cache's garbage-collection time elapses.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `days` | `number` | `90` | Uptime window length, sent as the `days` query parameter and used in the cache key. |
| Poll interval | — (not set) | no polling | The state never polls; refreshes come only from the platform's default triggers or a manual refetch. |
| Injected API client / base path | API client / string | default client, base path `/api` | Injected through dependency injection; determines where `/uptime` is resolved and allows a test double. |
| Shared cache (injected) | cache | platform library defaults | Supplied by the host; controls retry, stale time, cache lifetime, focus refetch, and reconnect refetch. |

## Deep Linking

Not applicable: the state reads no URL and registers no route; `days` is passed in by the caller.

## Localization

The state produces one hard-coded English string, surfaced as the read's error message rather than rendered by the state. Neither known consumer displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `uptime <status>` | Message of the error thrown on a non-ok response, for example `uptime 401` |

## Accessibility Options

Not applicable: the state renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the state reads no flags and has no conditional-disable gate.

## Analytics

Not applicable: the state emits no analytics events.

## Privacy

Not applicable: the state sends only the `days` window, attaches no credentials or tokens itself (the route's bearer security is satisfied by the host's proxy behind the injected API client's base path), receives only aggregate check counts and percentages per monitored service, and stores results only in the in-memory shared cache.

## Logging

Not applicable: the state makes no log calls; failures reach the caller only through the read's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-uptime.ts`, a thin `useQuery` wrapper whose types (`UptimeResponse`, `UptimeService`, `UptimeDay`) live in `src/types.ts` and whose `HealthStatus` comes from `src/lib/health.ts`. It depends on `useStatusApi` from `src/api/client.ts`. React Query supplies caching, deduplication, focus and reconnect refetch, retry, and the loading and error state machine. A host MUST mount a `QueryClientProvider`, and MAY mount a `StatusApiProvider`. The module must be marked `"use client"`, so it runs only in client components under a React Server Components host. Deduplication of concurrent calls is trivial because JavaScript runs on a single thread and React Query performs it, rather than the hook.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-uptime.ts` |
