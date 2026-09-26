---
id: e6326b0e-cba1-44ee-bf1d-7b033e25e39a
title: useIntegrations
domain: agentictoolkit://cookbook/status-web/hooks/use-integrations
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React Query hook that fetches the monitor's integration self-check snapshot
  from the status API and refetches on window focus
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status-web/api
related:
- agentictoolkit://cookbook/status-web/hooks/use-history
- agentictoolkit://cookbook/status-web/hooks/use-config-status
references: []
approved-by: ''
approved-date: ''
---

# useIntegrations

## Overview

`useIntegrations` is a React hook in the status dashboard (`status-web/src/hooks/use-integrations.ts`) that loads the monitor's integration self-check snapshot: one entry per provider integration, saying whether it is configured, reachable and healthy. It wraps one TanStack React Query `useQuery` call under the fixed key `["integrations"]`. It requests `/integrations` through the dashboard's `StatusApiClient` (see [status-web-api](agentictoolkit://cookbook/status-web/api)) and returns the query result typed as `IntegrationsResponse`. The hook turns on refetch-on-window-focus. It takes no arguments and is always enabled.

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

## Appearance

Not applicable — this is a data-fetching React hook, not a visual component.

## States

Not applicable — this is a data-fetching React hook, not a visual component.

## Accessibility

Not applicable — this is a data-fetching React hook, not a visual component.

## Conformance Test Vectors

There is no test file beside `use-integrations.ts`. The `Dashboard` and `OverviewTab` DOM tests mock the module out with `{ data: undefined, isLoading: false }`, so the vectors below come from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's `*.dom.test.tsx` files), plus a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-integrations-001 | always-enabled, request-path, request-init, client-source | Render `useIntegrations()` with the default client; the stub returns `200` and `{"generatedAt":"2026-09-24T00:00:00Z","overall":"ok","checks":[]}` | Exactly one `fetch`, to `/api/integrations`, with no init argument; `data` deep-equals the body |
| use-integrations-002 | client-source, request-path | Mount `StatusApiProvider basePath="/proxy"` and render `useIntegrations()` | The requested URL is `/proxy/integrations` |
| use-integrations-003 | non-ok-error, error-detail-dropped | The stub returns `502` with body `{"error":"upstream down"}` | `isError` is true; `error.message` is exactly `status 502`; the body text is not in the message |
| use-integrations-004 | parse-failure | The stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-integrations-005 | network-failure | The stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-integrations-006 | query-key, single-threaded-ordering | Render two components that each call `useIntegrations()` under one `QueryClient` | One `fetch` in total; both results have the same `data` |
| use-integrations-007 | refetch-on-focus | After a successful fetch with `staleTime` 0, dispatch a window `focus` / `visibilitychange` through React Query's `focusManager` | A second `fetch` to `/api/integrations` is made |
| use-integrations-008 | shared-interval-refresh | Mount `useIntegrations()` alongside `useRefreshAll(1000)` with fake timers; advance 1000 ms | A second `fetch` to `/api/integrations` is made |
| use-integrations-009 | raw-fetch-not-json-helper | Inspect the request | The hook adds no `Content-Type` header |
| use-integrations-010 | integration-check-optional-fields, success-body | The stub returns a check carrying `"missingEnv":["CLOUDFLARE_ACCOUNT_ID"],"unreachable":true,"correlated":true` | `data.checks[0]` keeps all three fields exactly as sent |

## Edge Cases

- **empty-checks**: A successful response with `checks: []` MUST resolve as data. The hook applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `IntegrationsResponse` (for example, one missing `checks`) MUST resolve as data unchanged. The hook does no shape validation, and a consumer reading `data.checks` gets `undefined`.
- **unknown-check-state**: A `state` or `overall` value outside `"ok" | "warn" | "error"` MUST pass through unchanged. The type is compile-time only.
- **204-response**: A `204 No Content` response counts as `ok`, so the hook MUST call `response.json()` on the empty body. That rejects and puts the query in its error state, unlike the client's `json` helper, which maps 204 to `undefined`.
- **server-error**: A non-2xx status MUST produce `Error("status <status>")`. Retries after that follow the host `QueryClient` policy; when the host sets none, React Query's library default is 3 retries with exponential backoff. What the `/integrations` route returns is owned by the backend.
- **unreachable-server**: A rejected `fetch` MUST surface as the query error. The hook adds no retry, fallback data or message rewriting of its own.
- **error-after-success**: When a refetch fails after an earlier success, React Query MUST keep the previous `data` and set `error`. The two callers read only `data`, so they keep showing the last good snapshot.
- **ambiguous-error-message**: The thrown message is the generic `status <status>`, which does not name the integrations endpoint. A consumer that logs the error cannot tell it from other queries by the message alone. This SHOULD be kept as-is for fidelity; see Design Decisions.
- **hung-request**: The hook sets no timeout or abort signal, so a request that never settles MUST leave the query fetching indefinitely.
- **focus-while-fetching**: A window focus during an in-flight fetch MUST NOT start a second request. React Query deduplicates on the shared key.
- **no-provider**: With no `StatusApiProvider` mounted, the hook MUST fall back to the same-origin default client, `/api`. With no `QueryClientProvider` mounted, React Query throws when the hook is called.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiProvider` `client` / `basePath` | `StatusApiClient` / string | Default client, base path `/api` | Injected through React context. Sets where `/integrations` is resolved and lets a test inject a double. |
| Host `QueryClient` | `QueryClient` | React Query library defaults | Supplied by the host's `QueryClientProvider`. Controls retry, stale time and cache lifetime. |
| `refetchOnWindowFocus` | boolean (hard-coded) | `true` | Refetches stale data when the window regains focus. Not configurable. |
| `useRefreshAll` `intervalMs` | number | `60000` | Shared refresh interval that also refetches this query. Set by whoever calls `useRefreshAll`, not by this hook. |

## Deep Linking

Not applicable: the hook reads no URL and registers no route.

## Localization

The hook produces one hard-coded English string. It becomes the query's `Error.message`; the hook itself renders nothing. Neither caller displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `status <status>` | Message of the `Error` thrown on a non-ok response, for example `status 502` |

## Accessibility Options

Not applicable: the hook renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the hook reads no flags and has no `enabled` gate.

## Analytics

Not applicable: the hook emits no analytics events.

## Privacy

Not applicable: the hook sends a bare GET with no parameters, attaches no credentials or tokens itself, and keeps results only in the in-memory query cache. The response names missing env vars, not their values.

## Logging

Not applicable: the hook makes no log calls. Failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-integrations.ts`, a thin `useQuery` wrapper. It depends on `useStatusApi` from `src/api/client.ts` and on `IntegrationsResponse`, `IntegrationCheck` and `CheckState` from `src/types.ts`. React Query provides caching, deduplication, retry, focus refetch and the loading/error state machine, and `useRefreshAll` provides the periodic refresh. A host MUST mount a `QueryClientProvider` and MAY mount a `StatusApiProvider`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `IntegrationsResponse?`, an error and a loading flag. Load with `URLSession.shared.data(for:)` in `.task` and decode with `JSONDecoder` into `Codable` structs, with a `CheckState` enum and optional `missingEnv`, `unreachable` and `correlated`. Unlike the source, decoding validates the shape, and an unknown `state` fails unless you add a fallback case. For focus refetch, observe `scenePhase` becoming `.active`. For the shared interval, use a `Timer` publisher or an `AsyncStream` loop in one app-level refresher. There is no query cache, so share one model instance between the views to keep the single-entry behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`, with Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. Share one repository-level `StateFlow` between screens to mirror the shared cache key. Refetch on `Lifecycle.Event.ON_RESUME` (through `repeatOnLifecycle(STARTED)`) to stand in for window focus, and use a `while (isActive) { delay(60_000) }` loop for the shared interval.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a `@MainActor` model. Refetch on `NSApplication.didBecomeActiveNotification` (AppKit) or `UIApplication.didBecomeActiveNotification` (UIKit) as the focus equivalent.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `IntegrationsResponse? Integrations`, `bool IsLoading` and `Exception? Error`. Register it as a singleton so both views share one instance, which stands in for the single `["integrations"]` cache entry. Fetch in an `async Task` with a shared `HttpClient.GetAsync($"{basePath}/integrations")`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"status {(int)response.StatusCode}")` without reading the body. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<IntegrationsResponse>` using `JsonSerializerDefaults.Web` for camelCase. Model `CheckState` as a string or an enum with `JsonStringEnumConverter`, keeping in mind that an unknown value throws where the source passes it through. Expose `Checks` as an `ObservableCollection<IntegrationCheck>` and marshal updates through `DispatcherQueue.TryEnqueue`. For focus refetch, handle `Window.Activated` and refetch when `WindowActivationState` is not `Deactivated`. For the shared refresh, use a `DispatcherQueueTimer` with `Interval = TimeSpan.FromSeconds(60)`. Three things differ from the source. .NET has no request deduplication, so guard against overlapping fetches with an in-flight `Task` field. `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout. Retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because React Query's default retry does not carry over.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-integrations.ts` |

## Design Decisions

**Decision**: The hook fetches through `api.fetch` and checks `ok` itself instead of calling `api.json`.

**Rationale**: The source picks the raw method and throws its own short `status <status>` message. That drops the server's error detail, gives a message that does not name the endpoint, and treats a 204 as a parse failure. All three follow from that one choice and are recorded here so ports keep them. A port SHOULD keep the message format so logs match across platforms. It MAY add the endpoint name only if every sibling hook's port does the same.

**Approved**: pending

---

**Decision**: The query refetches on window focus, and its periodic refresh is left to `useRefreshAll`.

**Rationale**: The integration self-check is the monitor's own health, which `OverviewTab` shows on the default wallboard "so a broken monitor can't hide". The hook turns on `refetchOnWindowFocus` so a returning viewer sees a current verdict. It sets no `refetchInterval` because `useRefreshAll` refreshes all supporting queries together, "so the dashboard never shows a mix of fresh + stale datasets".

**Approved**: pending

---

**Decision**: Staleness, cache lifetime and retry policy are left to the host `QueryClient`.

**Rationale**: The hook sets only `queryKey`, `queryFn` and `refetchOnWindowFocus`. Tests in the package build their `QueryClient` with `retry: false`, and production hosts supply their own defaults. A port gets retry and staleness from the equivalent app-level policy.

**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |

**Separation of Concerns**: The hook has no presentation code. The base path and transport live in `StatusApiClient`, caching and the state machine in React Query, periodic refresh in `useRefreshAll`, and rendering in `SelfCheckBanner` and `computeSelfCheck`.

**Unit Test Coverage**: There is no `use-integrations.test.ts` or `use-integrations.dom.test.tsx` beside the hook. The `Dashboard` and `OverviewTab` DOM tests replace the module with a mock, so its own fetch and error paths never run in any test.

**Explicit Error Handling**: A non-ok status, a network rejection and a JSON parse failure all reject the query function and surface through the query's `error`, so none is swallowed. The server's error-body detail is not read, and neither caller renders `error`.

**Timeout Handling**: The hook sets no timeout and passes no abort signal. A hung request leaves the query fetching, but the cache entry just stays pending and nothing is left inconsistent.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-integrations.ts` |
