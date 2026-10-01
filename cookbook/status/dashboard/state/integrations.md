---
id: e6326b0e-cba1-44ee-bf1d-7b033e25e39a
title: Integration Self-Check
domain: agentictoolkit://cookbook/status/dashboard/state/integrations
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Cached state that fetches the monitor's integration self-check snapshot
  from the status API and refreshes on returning focus.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/history
- agentictoolkit://cookbook/status/dashboard/state/config-status
references: []
approved-by: ''
approved-date: ''
---

# Integration Self-Check

## Overview

Integrations is state in the status dashboard that loads the monitor's integration self-check snapshot: one entry per provider integration, saying whether it is configured, reachable and healthy. It wraps one cached read under the fixed key `["integrations"]`. It requests `/integrations` through the dashboard's status API client (see [status-web-api](agentictoolkit://cookbook/status/dashboard/api)) and returns the query result typed as `IntegrationsResponse`. Integrations turns on refresh-on-returning-focus. It takes no arguments and is always enabled.

It has two callers. The Overview passes `data` to the self-check banner, so a failed or degraded self-check shows on the default wallboard. The dashboard passes `data` to the self-check computation for the header self-check pill. Both callers read only `data`.

## Behavioral Requirements

- **hook-signature**: Integrations MUST take no arguments.
- **return-value**: Integrations MUST return the shared cache's query result unchanged (fields such as `data`, `error`, `isLoading`, `isError`, `status`, `refetch`). It MUST NOT add fields of its own.
- **client-source**: Integrations MUST get its HTTP client from the app's API context. That supplies the status API client from the nearest provider, or the same-origin default client (base path `/api`) when no provider is mounted.
- **query-key**: The query MUST be cached under the fixed key `["integrations"]`, so every caller under one shared cache shares a single cache entry.
- **always-enabled**: The query MUST NOT set an enabled gate. It MUST fetch as soon as a consumer that uses Integrations becomes active, following the shared cache's policy.
- **request-path**: Each fetch MUST call the client's raw request method with the relative path `/integrations`. The client resolves it against its base path, which by default gives `/api/integrations`.
- **request-init**: Each fetch MUST be issued with no added request options. It is a default GET, and Integrations adds no headers, body, cache mode or cancellation signal.
- **raw-fetch-not-json-helper**: Integrations MUST use the client's raw request method, not its JSON-body helper. So that helper's `Content-Type` header, its error-detail extraction and its "no-content response becomes an empty result" handling do not apply.
- **non-ok-error**: When the response is not ok, the query's read step MUST fail with an error whose message is `status <status>` (for example `status 502`), which puts the query in its error state.
- **error-detail-dropped**: On a non-ok response Integrations MUST NOT read the response body. Any `error` or `message` detail the server returns is left out of the failure.
- **success-body**: When the response is ok, the query's read step MUST resolve with the parsed response body, typed as `IntegrationsResponse`. There is no runtime schema validation.
- **parse-failure**: When an ok response's body is not valid JSON, the parse failure MUST propagate as the query's error.
- **network-failure**: When the request itself fails (a network failure or an unreachable host), the failure MUST propagate unchanged as the query's error.
- **refetch-on-focus**: The query MUST refresh when the runtime regains focus and the cached data is stale under the shared cache's freshness window.
- **shared-interval-refresh**: Integrations MUST NOT set its own automatic refresh interval. Periodic refresh comes from the Refresh All state, which refreshes every enabled query except the live snapshot on one shared interval, 60,000 ms by default.
- **no-hook-level-policy**: Apart from refresh-on-returning-focus, Integrations MUST NOT set its own freshness window, cache retention window, retry count or automatic refresh interval. Staleness, cache lifetime and retry come from the shared cache's host-supplied and library defaults.
- **integrations-response-shape**: A successful result is declared as `IntegrationsResponse` with fields `generatedAt` (string), `overall` (`CheckState`) and `checks` (an `IntegrationCheck` array). `CheckState` is `"ok" | "warn" | "error"`.
- **integration-check-shape**: Each `IntegrationCheck` is declared with the required fields `id` (string), `label` (string), `configured` (boolean), `ok` (boolean), `state` (`CheckState`) and `detail` (string).
- **integration-check-optional-fields**: `IntegrationCheck` also declares three optional fields. `missingEnv` lists expected environment variables found unset. `unreachable` means the probe got no response. `correlated` means the check was confirmed unreachable together with other providers in the same run. Integrations passes all of them through untouched.
- **no-timeout**: Integrations MUST NOT impose its own request timeout. A request that never settles leaves the query fetching until the client or runtime ends it.
- **no-persistence**: Integrations MUST NOT write the snapshot to any durable store. Results live only in the in-memory shared cache and are lost on reload.
- **client-only-module**: Integrations has no server-only or universal-rendering variant; it requires a live client execution context.
- **single-threaded-ordering**: Integrations runs on a single execution thread. Concurrent callers (the Overview and the dashboard) MUST share the one `["integrations"]` cache entry, and the shared cache, not Integrations, deduplicates their in-flight requests.

## Appearance

Not applicable — this is a data-fetching concept, not a visual component.

## States

Not applicable — this is a data-fetching concept, not a visual component.

## Accessibility

Not applicable — this is a data-fetching concept, not a visual component.

## Conformance Test Vectors

There is no test file for the source directly. Companion component tests mock the module out with a fixed no-data, not-loading result, so the vectors below come from the source. They assume a shared cache with retries disabled and a stubbed transport.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-integrations-001 | always-enabled, request-path, request-init, client-source | Use Integrations with the default client; the stub returns `200` and `{"generatedAt":"2026-09-24T00:00:00Z","overall":"ok","checks":[]}` | Exactly one request, to `/api/integrations`, with no added options; `data` deep-equals the body |
| use-integrations-002 | client-source, request-path | API base path `/proxy`, use Integrations | The requested URL is `/proxy/integrations` |
| use-integrations-003 | non-ok-error, error-detail-dropped | The stub returns `502` with body `{"error":"upstream down"}` | `isError` is true; error message is exactly `status 502`; the body text is not in the message |
| use-integrations-004 | parse-failure | The stub returns `200` with body `not json` | `isError` is true; error is the parse failure from reading the body |
| use-integrations-005 | network-failure | The stub fails with a network error | `isError` is true; error is that same failure |
| use-integrations-006 | query-key, single-threaded-ordering | Two consumers each use Integrations under one shared cache | One request in total; both results have the same `data` |
| use-integrations-007 | refetch-on-focus | After a successful fetch with a zero freshness window, report the runtime regaining focus | A second request to `/api/integrations` is made |
| use-integrations-008 | shared-interval-refresh | Use Integrations alongside Refresh All (interval 1000 ms) with simulated time; advance 1000 ms | A second request to `/api/integrations` is made |
| use-integrations-009 | raw-fetch-not-json-helper | Inspect the request | Integrations adds no `Content-Type` header |
| use-integrations-010 | integration-check-optional-fields, success-body | The stub returns a check carrying `"missingEnv":["CLOUDFLARE_ACCOUNT_ID"],"unreachable":true,"correlated":true` | `data.checks[0]` keeps all three fields exactly as sent |

## Edge Cases

- **empty-checks**: A successful response with `checks: []` MUST resolve as data. Integrations applies no emptiness check.
- **malformed-body**: A body that is valid JSON but not shaped like `IntegrationsResponse` (for example, one missing `checks`) MUST resolve as data unchanged. Integrations does no shape validation, and a consumer reading `data.checks` gets nothing.
- **unknown-check-state**: A `state` or `overall` value outside `"ok" | "warn" | "error"` MUST pass through unchanged. The type is a compile-time-only constraint.
- **204-response**: A response with no body still counts as ok, so Integrations MUST attempt to parse the empty body. That fails and puts the query in its error state, unlike the client's JSON-body helper, which maps a no-content response to an empty result.
- **server-error**: A non-2xx status MUST produce an error whose message is `status <status>`. Retries after that follow the shared cache's policy; when the host sets none, the library default is 3 retries with exponential backoff. What the `/integrations` route returns is owned by the backend.
- **unreachable-server**: A failed request MUST surface as the query error. Integrations adds no retry, fallback data or message rewriting of its own.
- **error-after-success**: When a refresh fails after an earlier success, the shared cache MUST keep the previous `data` and set `error`. The two callers read only `data`, so they keep showing the last good snapshot.
- **ambiguous-error-message**: The failure message is the generic `status <status>`, which does not name the integrations endpoint. A consumer that logs the error cannot tell it from other queries by the message alone. This SHOULD be kept as-is for fidelity; see Design Decisions.
- **hung-request**: Integrations sets no timeout or cancellation signal, so a request that never settles MUST leave the query fetching indefinitely.
- **focus-while-fetching**: Regaining focus during an in-flight fetch MUST NOT start a second request. The shared cache deduplicates on the shared key.
- **no-provider**: With no status API provider mounted, Integrations MUST fall back to the same-origin default client, `/api`. With no shared cache mounted, the runtime fails when Integrations is used.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Status API provider (client / base path) | injected client / string | default client, base path `/api` | Injected through the app's API context. Sets where `/integrations` is resolved and lets a test inject a double. |
| Shared cache | injected cache context | library defaults | Supplied by the host. Controls retry, freshness window and cache retention. |
| Refresh-on-returning-focus | boolean (hard-coded) | `true` | Refreshes stale data when the runtime regains focus. Not configurable. |
| Refresh All interval | number | `60000` | Shared refresh interval that also refreshes this query. Set by whoever uses Refresh All, not by Integrations. |

## Deep Linking

Not applicable: Integrations reads no URL and registers no route.

## Localization

Integrations produces one hard-coded English string. It becomes the query's error message; Integrations itself renders nothing. Neither caller displays it.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; literal in source) | `status <status>` | Message of the error on a non-ok response, for example `status 502` |

## Accessibility Options

Not applicable: Integrations renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: Integrations reads no flags and has no enabled gate.

## Analytics

Not applicable: Integrations emits no analytics events.

## Privacy

Not applicable: Integrations sends a bare GET with no parameters, attaches no credentials or tokens itself, and keeps results only in the in-memory shared cache. The response names missing environment variables, not their values.

## Logging

Not applicable: Integrations makes no log calls. Failures reach the caller only through the query's `error` field.

## Platform Notes

- **React/Web**: The source is `packages/web/packages/status-web/src/hooks/use-integrations.ts`, a thin `useQuery` wrapper `useIntegrations()`. It depends on `useStatusApi` from `src/api/client.ts` and on `IntegrationsResponse`, `IntegrationCheck` and `CheckState` from `src/types.ts`. TanStack React Query provides caching, deduplication, retry, `refetchOnWindowFocus: true`, and the loading/error state machine, and `useRefreshAll` provides the periodic refresh. The raw request method is `api.fetch`; the JSON-body helper it is deliberately not used is `api.json`. A host MUST mount a `QueryClientProvider` and MAY mount a `StatusApiProvider`. The module is marked `"use client"`.
- **SwiftUI**: Start from an `@Observable` `@MainActor` model holding `IntegrationsResponse?`, an error and a loading flag. Load with `URLSession.shared.data(for:)` in `.task` and decode with `JSONDecoder` into `Codable` structs, with a `CheckState` enum and optional `missingEnv`, `unreachable` and `correlated`. Unlike the source, decoding validates the shape, and an unknown `state` fails unless you add a fallback case. For focus refetch, observe `scenePhase` becoming `.active`. For the shared interval, use a `Timer` publisher or an `AsyncStream` loop in one app-level refresher. There is no query cache, so share one model instance between the views to keep the single-entry behavior.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>`, with Ktor `HttpClient` or Retrofit for the GET and `kotlinx.serialization` for decoding. Share one repository-level `StateFlow` between screens to mirror the shared cache key. Refetch on `Lifecycle.Event.ON_RESUME` (through `repeatOnLifecycle(STARTED)`) to stand in for regaining focus, and use a `while (isActive) { delay(60_000) }` loop for the shared interval.
- **AppKit / UIKit**: Use the same `URLSession` and `Codable` stack as SwiftUI, driven from a `@MainActor` model. Refetch on `NSApplication.didBecomeActiveNotification` (AppKit) or `UIApplication.didBecomeActiveNotification` (UIKit) as the focus equivalent.
- **WinUI 3**: Start from a view model implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm's `ObservableObject` with `[ObservableProperty]`) that exposes `IntegrationsResponse? Integrations`, `bool IsLoading` and `Exception? Error`. Register it as a singleton so both views share one instance, which stands in for the single `["integrations"]` cache entry. Fetch in an `async Task` with a shared `HttpClient.GetAsync($"{basePath}/integrations")`. When `response.IsSuccessStatusCode` is false, throw `new HttpRequestException($"status {(int)response.StatusCode}")` without reading the body. Otherwise deserialize with `System.Text.Json`'s `JsonSerializer.DeserializeAsync<IntegrationsResponse>` using `JsonSerializerDefaults.Web` for camelCase. Model `CheckState` as a string or an enum with `JsonStringEnumConverter`, keeping in mind that an unknown value throws where the source passes it through. Expose `Checks` as an `ObservableCollection<IntegrationCheck>` and marshal updates through `DispatcherQueue.TryEnqueue`. For focus refetch, handle `Window.Activated` and refetch when `WindowActivationState` is not `Deactivated`. For the shared refresh, use a `DispatcherQueueTimer` with `Interval = TimeSpan.FromSeconds(60)`. Three things differ from the source. .NET has no request deduplication, so guard against overlapping fetches with an in-flight `Task` field. `HttpClient.Timeout` defaults to 100 seconds, whereas the source has no timeout. Retry needs Polly or `Microsoft.Extensions.Http.Resilience`, because the source's default retry does not carry over.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-integrations.ts` |

## Design Decisions

**Decision**: Integrations fetches through the client's raw request method and checks whether the response is ok itself, instead of calling its JSON-body helper.

**Rationale**: The source picks the raw method and produces its own short `status <status>` message. That drops the server's error detail, gives a message that does not name the endpoint, and treats a no-content response as a parse failure. All three follow from that one choice and are recorded here so ports keep them. A port SHOULD keep the message format so logs match across platforms. It MAY add the endpoint name only if every sibling concept's port does the same.

**Approved**: pending

---

**Decision**: The query refreshes on returning focus, and its periodic refresh is left to Refresh All.

**Rationale**: The integration self-check is the monitor's own health, which the Overview shows on the default wallboard "so a broken monitor can't hide". Integrations turns on refresh-on-returning-focus so a returning viewer sees a current verdict. It sets no automatic refresh interval because Refresh All refreshes all supporting queries together, "so the dashboard never shows a mix of fresh + stale datasets".

**Approved**: pending

---

**Decision**: Staleness, cache lifetime and retry policy are left to the shared cache.

**Rationale**: Integrations sets only its cache key, its read step and refresh-on-returning-focus. Tests in the package build their cache with retries disabled, and production hosts supply their own defaults. A port gets retry and staleness from the equivalent app-level policy.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-integrations.ts` |
</content>
