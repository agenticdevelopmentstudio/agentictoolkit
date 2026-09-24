---
id: acf8decd-8427-4547-a9ec-49c0a35b0b3a
title: useStatus
domain: agentictoolkit://recipes/status-web-hooks-use-status
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that fetches the service health summary from GET /status into
  the shared react-query cache and surfaces the backend's error reason.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-api
related:
- agentictoolkit://recipes/status-web-hooks-use-refresh-all
- agentictoolkit://recipes/status-web-hooks-use-config-status
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a React data hook, not a visual component.

## States

Not applicable — this is a React data hook, not a visual component.

## Accessibility

Not applicable — this is a React data hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-001 | query-key, request-path, success-ok | Default client; `fetch` resolves `200` with body `{ "overall": "operational", "services": [], "checkedAt": "2026-09-24T00:00:00Z" }` | One request to `/api/status`; `data` deep-equals the body; `error` is `null`; the query is cached under `["status"]` |
| use-status-002 | error-body-read, error-detail-message | `fetch` resolves `503` with body `{ "error": "database unavailable" }` | Query fails; `error` is an `Error` whose `message` is exactly `database unavailable` |
| use-status-003 | error-status-fallback | `fetch` resolves `503` with body `{}` | `error.message` is `status 503` |
| use-status-004 | error-status-fallback, error-parse-swallowed | `fetch` resolves `502` with non-JSON body `Bad Gateway` | `error.message` is `status 502`; no JSON syntax error surfaces |
| use-status-005 | error-status-fallback | `fetch` resolves `500` with body `{ "error": "" }` | `error.message` is `status 500` |
| use-status-006 | error-nonstring-detail | `fetch` resolves `500` with body `{ "error": { "message": "x" } }` | `error.message` is `[object Object]` |
| use-status-007 | network-failure | `fetch` rejects with `TypeError("Failed to fetch")` | `error` is that same `TypeError` |
| use-status-008 | success-parse-failure | `fetch` resolves `200` with body `not json` | Query fails with the JSON syntax error thrown by `r.json()`; message does not start with `status ` |
| use-status-009 | client-injection, request-path | `StatusApiProvider` with `basePath="/proxy"`; `fetch` resolves `200` with a valid body | The request URL is `/proxy/status` |
| use-status-010 | shared-cache | Two components call `useStatus()` under one `QueryClient`; `fetch` resolves after a delay | Exactly one request is made; both components receive the same `data` |
| use-status-011 | refetch-on-focus | Query loaded and stale; dispatch a window `focus`/`visibilitychange` event that react-query's focus manager observes | One additional request to `/status` is made |
| use-status-012 | error-message-only | `fetch` resolves `503` with body `{ "error": "db down" }` | `error` has no `status` or `body` property; only `message` is `db down` |
| use-status-013 | result-type | Consumer mock as in `Dashboard.dom.test.tsx`: `{ isLoading: false, error: null, data: { overall: "operational", checkedAt, services: [one healthy service] } }` | `Dashboard` reads `data.services` and `data.checkedAt` from the result without adaptation (the result is the raw `useQuery` object) |

## Edge Cases

- **Empty services list**: A `200` body with `services: []` MUST resolve as-is; the hook does not treat an empty list as an error (MUST).
- **Missing or malformed fields in a 200 body**: A body lacking `services` or `checkedAt`, or with wrong types, MUST resolve without error because the body is cast, not validated; consumers such as `Dashboard` guard with `status.data?.services ?? []` (MUST, as implemented).
- **Non-JSON 200 body**: The query MUST fail with the `r.json()` syntax error (MUST).
- **Non-JSON error body**: The parse failure MUST be caught and replaced by `status <code>` (MUST).
- **Empty-string or null `error`**: Falsy detail MUST fall back to `status <code>` (MUST).
- **Non-string `error`**: A truthy object or number is passed to `Error` unconverted, yielding a coerced message such as `[object Object]` or `42`; the reason is lossy but the failure is still reported (MUST, as implemented).
- **Network unreachable / offline**: `api.fetch` rejects and the query fails with that rejection; the hook adds no retry, backoff or offline detection of its own beyond the host `QueryClient` defaults (MUST).
- **Timeout**: The hook sets no timeout; a request that never settles leaves the query pending until the browser or network stack gives up (MUST, as implemented).
- **Cancellation / unmount**: The fetch is not tied to react-query's `AbortSignal`, so an unmounted or cancelled query's request still completes and its result may populate the cache (MUST, as implemented).
- **Concurrent callers**: JavaScript is single-threaded and react-query deduplicates by key, so concurrent mounts share one in-flight request; there is no interleaving to order (MUST).
- **No provider mounted**: `useStatusApi()` falls back to the module-level default client at `/api` (MUST).
- **Window focus while fresh**: `refetchOnWindowFocus: true` refetches only when the query is stale per the host `staleTime`; a fresh query is not refetched on focus (MUST, per react-query semantics).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()`; same-origin client at `DEFAULT_API_BASE` (`/api`) | Transport for the `GET /status` request; overridden via `StatusApiProvider`'s `client` or `basePath`. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns caching, retry, stale time and garbage collection; the hook sets none of these. |
| `queryKey` | `["status"]` | — | Fixed cache key; not exported as a constant. |
| `refetchOnWindowFocus` | `boolean` | `true` | Fixed in the source; not caller-configurable. |

The hook takes no arguments and reads no environment variables.

## Deep Linking

Not applicable: the hook is a data source with no route or URL of its own; its only URL is the backend `/status` API path it fetches.

## Localization

The hook emits one hardcoded, untranslated English message pattern that consumers display to the user (`Dashboard` renders it after `Failed to load status — `):

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; inline literal) | `status <code>` | Thrown `Error.message` when an error response carries no usable `error` detail; `<code>` is the numeric HTTP status. |

The backend-supplied `error` string is passed through untranslated.

## Accessibility Options

Not applicable: the hook renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: the hook reads the operator's own service health summary (service names, URLs, status codes, response times) from the app's backend, keeps it only in the in-memory react-query cache, and sends no credentials or personal data of its own.

## Logging

Not applicable: the source contains no log calls; failures are surfaced through the returned `error` field instead.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |

The hook owns only the query definition and error-reason extraction; transport and base path belong to `StatusApiClient`, and rendering belongs to `Dashboard`. There is no test file for `use-status.ts`; `Dashboard.dom.test.tsx` replaces the hook with a mock, so neither the error-detail extraction nor the `status <code>` fallback is exercised, hence failed. Every failure path produces a thrown `Error` that reaches the UI, but a non-string `error` detail is coerced to an unhelpful message and a malformed success body is cast rather than validated, hence partial. Caching uses a single shared react-query key with refetch-on-focus and defers periodic refresh to the app-wide `useRefreshAll` interval.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
