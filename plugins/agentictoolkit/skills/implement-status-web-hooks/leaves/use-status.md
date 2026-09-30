<!-- leaf: implement-status-web-hooks/use-status · source: status-web-hooks-use-status.md -->

**Rules** (cite as `implement-status-web-hooks/use-status#<slug>`):

- `query-key` MUST
- `result-type` MUST
- `refetch-on-focus` MUST
- `no-interval` MUST
- `no-enabled-option` MUST
- `client-defaults` MUST
- `client-injection` MUST
- `request-path` MUST
- `raw-fetch` MUST
- `success-ok` MUST
- `success-unvalidated` MUST
- `success-parse-failure` MUST
- `error-body-read` MUST
- `error-detail-message` MUST
- `error-status-fallback` MUST
- `error-parse-swallowed` MUST
- `error-nonstring-detail` MUST
- `error-message-only` MUST
- `network-failure` MUST
- `shared-cache` MUST
- `no-cancellation` MUST
- `side-effects` MUST
- `client-only` MUST

# useStatus

## Overview

`useStatus` is the status web app's read of the service health summary. It issues one `GET /status` through the injected `StatusApiClient` (from `useStatusApi()`) and caches the `StatusResponse` — `{ overall, services, checkedAt }` — under the react-query key `["status"]`. `Dashboard` is its consumer: it reads `data.services`, `data.checkedAt`, `isLoading` and `error`, and renders `Failed to load status — <error.message>` when the query fails.

The one piece of logic the hook adds over a plain fetch is error-reason extraction. The authoring comment states the intent: "The route returns `{ error }` with the real reason (e.g. a DB outage); surface that as the thrown message so the UI shows WHY, not \"status 503\"." The hook returns the full react-query `UseQueryResult<StatusResponse>` unchanged.

## Behavioral Requirements

### Query identity and options

- **query-key**: The hook MUST register its query under the key `["status"]`.
- **result-type**: The hook MUST return react-query's `UseQueryResult<StatusResponse>` as produced by `useQuery`, with no fields added, removed or renamed.
- **refetch-on-focus**: The query MUST set `refetchOnWindowFocus: true`, so a stale `["status"]` query refetches when the browser window regains focus.
- **no-interval**: The query MUST NOT set a `refetchInterval`; periodic refresh is owned outside this hook (the app's `useRefreshAll` refetches every non-`live`, non-disabled query on a 60-second default interval).
- **no-enabled-option**: The hook MUST take no parameters and MUST NOT set `enabled`, so every mounted caller is an active observer.
- **client-defaults**: The query MUST NOT set its own `retry`, `staleTime`, `gcTime` or timeout; those come from the host `QueryClient` defaults.

### Request

- **client-injection**: The query function MUST obtain its transport from `useStatusApi()`, which returns the `StatusApiProvider` client when one is mounted and the same-origin default client otherwise.
- **request-path**: Each query run MUST call `api.fetch("/status")` exactly once, with no `RequestInit`, so the request is a `GET` to `<basePath>/status` (`/api/status` with the default base `DEFAULT_API_BASE`).
- **raw-fetch**: The hook MUST use the client's raw `fetch`, not its `json` helper, so no `Content-Type` header is added and the `json` helper's `${method} ${url} → ${status}` error format is not used.

### Success path

- **success-ok**: When the response has `ok === true` (status 200–299), the query MUST resolve to the parsed JSON body.
- **success-unvalidated**: The parsed body MUST be returned as `StatusResponse` by type assertion only; the hook performs no runtime shape check on `overall`, `services` or `checkedAt`.
- **success-parse-failure**: When an `ok` response body is not valid JSON, the query MUST fail with the rejection from `r.json()` (a JSON syntax error), not with a `status <code>` message.

### Error path

- **error-body-read**: When the response has `ok === false`, the hook MUST attempt to parse the body as JSON and read its `error` field.
- **error-detail-message**: When that `error` field is a non-empty string, the query MUST fail with `new Error(<error>)`, whose `message` is the string unchanged.
- **error-status-fallback**: When the body is not JSON, has no `error` field, or its `error` is an empty string, `null` or otherwise falsy, the query MUST fail with `new Error("status <code>")`, where `<code>` is the numeric HTTP status (for example `status 503`).
- **error-parse-swallowed**: A JSON parse failure while reading the error body MUST NOT escape; it MUST be converted to the `status <code>` fallback message.
- **error-nonstring-detail**: The hook MUST NOT narrow `error` to a string at runtime; a truthy non-string `error` (for example an object) MUST be passed to the `Error` constructor as-is, producing its string coercion as the message (for an object, `[object Object]`).
- **error-message-only**: The thrown value MUST be a plain `Error` carrying only a message; the HTTP status code and response body are not attached as properties.
- **network-failure**: When `api.fetch` itself rejects (network unreachable, DNS failure, CORS), the query MUST fail with that rejection unchanged.

### Caching, concurrency and side effects

- **shared-cache**: All callers under one `QueryClient` MUST share the single `["status"]` query; concurrent mounts MUST NOT start more than one in-flight request beyond react-query's own deduplication.
- **no-cancellation**: The query function MUST NOT accept or forward react-query's `AbortSignal`; an in-flight request runs to completion even when the query is cancelled or its observers unmount.
- **side-effects**: The hook's only side effect MUST be the one `GET /status` request per query run; it MUST NOT write storage, log, emit analytics, or mutate server state.
- **client-only**: The module MUST be a client module (`"use client"`), because it calls React hooks and the react-query cache.
- **server-contract**: The response body shape and the `{ error }` failure body are owned by the status-server `/status` route; this client surfaces whatever that route sends, unchanged apart from the error-message extraction above.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()`; same-origin client at `DEFAULT_API_BASE` (`/api`) | Transport for the `GET /status` request; overridden via `StatusApiProvider`'s `client` or `basePath`. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns caching, retry, stale time and garbage collection; the hook sets none of these. |
| `queryKey` | `["status"]` | — | Fixed cache key; not exported as a constant. |
| `refetchOnWindowFocus` | `boolean` | `true` | Fixed in the source; not caller-configurable. |

The hook takes no arguments and reads no environment variables.

## Localization

The hook emits one hardcoded, untranslated English message pattern that consumers display to the user (`Dashboard` renders it after `Failed to load status — `):

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; inline literal) | `status <code>` | Thrown `Error.message` when an error response carries no usable `error` detail; `<code>` is the numeric HTTP status. |

The backend-supplied `error` string is passed through untranslated.

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor` store with `status: StatusResponse?`, `isLoading: Bool` and `error: Error?`. Fetch with `URLSession.shared.data(from:)` and decode with `JSONDecoder` into a `Decodable` `StatusResponse`; on a non-2xx `HTTPURLResponse`, try decoding `{ error: String? }` and throw a custom error with that message or `"status \(code)"`. Note that `Decodable` validates shape, unlike the source's cast. Refresh on `scenePhase == .active` to mirror `refetchOnWindowFocus`; share one store through the environment to replace the shared cache.
- **Compose**: A `ViewModel` exposing `StateFlow<UiState<StatusResponse>>`, loading with Ktor `HttpClient` or Retrofit plus `kotlinx.serialization`. Map a non-2xx response by decoding an `ErrorBody(val error: String? = null)` inside `runCatching`, falling back to `"status $code"`. Refetch on `Lifecycle.Event.ON_RESUME` for the focus behavior.
- **React/Web**: Source platform. `hooks/use-status.ts` wraps `@tanstack/react-query` `useQuery` and depends on `api/client.ts` (`useStatusApi`, `StatusApiClient.fetch`) and `types.ts` (`StatusResponse`, `ServiceStatusDTO`, `OverallStatus`). Its consumer is `components/Dashboard.tsx`; `components/Dashboard.dom.test.tsx` mocks the hook's result shape. Periodic refresh comes from `hooks/use-refresh-all.ts`, not from this hook.
- **AppKit / UIKit**: Same store as SwiftUI, observed via Observation tracking or Combine `@Published`; trigger a refresh from `NSApplication.didBecomeActiveNotification` / `UIApplication.didBecomeActiveNotification` to mirror refetch-on-focus.
- **WinUI 3**: Implement a singleton `StatusService : INotifyPropertyChanged` registered in the DI container, holding `Status` (`StatusResponse?`), `IsLoading` and `Error`. Send the request with a shared `HttpClient` (`GetAsync($"{basePath}/status")`); on `IsSuccessStatusCode`, deserialize with `JsonSerializer.DeserializeAsync<StatusResponse>` (`System.Text.Json`, `PropertyNameCaseInsensitive` or `JsonPropertyName` attributes for camelCase). On failure, wrap `JsonSerializer.Deserialize<ErrorBody>` in `try/catch (JsonException)` and raise `new Exception(body?.Error is { Length: > 0 } e ? e : $"status {(int)resp.StatusCode}")`. Map `HttpRequestException` to the network-failure path. Mirror `refetchOnWindowFocus` by handling `Window.Activated` (`WindowActivationState != Deactivated`) and reloading when stale. Unlike react-query, nothing deduplicates concurrent loads: cache the in-flight `Task` and return it to concurrent callers. `HttpClient` has a 100-second default `Timeout`, unlike the source's untimed fetch; pass a `CancellationToken` if cancellation is wanted, which the source does not do. Marshal property changes to the UI thread with `DispatcherQueue.TryEnqueue`.

## Design Decisions

**Decision**: Surface the route's `{ error }` string as the thrown message, falling back to `status <code>`.
**Rationale**: The authoring comment says the route returns the real reason (for example a DB outage) and the UI should show "WHY, not \"status 503\"". The fallback keeps a message when the body carries no reason.
**Approved**: pending

**Decision**: Use the client's raw `fetch` instead of `StatusApiClient.json`.
**Rationale**: `json` would prefix the message with `GET /api/status → 503 — `; the raw path lets the hook throw the bare reason string. The trade-off is that a non-string `error` (which `json`'s `errorDetail` would unwrap via `error.message`) is coerced here to `[object Object]`.
**Approved**: pending

**Decision**: Set `refetchOnWindowFocus: true` explicitly and no `refetchInterval`.
**Rationale**: Focus refetch keeps the summary current when the operator returns to the tab; the 60-second periodic refresh is centralized in `useRefreshAll` so all supporting datasets refresh together.
**Approved**: pending

**Decision**: Return the success body by type assertion without validation.
**Rationale**: The body shape is owned by the status-server route in the same toolkit; consumers guard optional access (`status.data?.services ?? []`). A malformed body therefore resolves rather than failing.
**Approved**: pending
