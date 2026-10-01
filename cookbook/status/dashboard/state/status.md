---
id: acf8decd-8427-4547-a9ec-49c0a35b0b3a
title: Status State
domain: agentictoolkit://cookbook/status/dashboard/state/status
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that reads the service health summary from GET /status into a
  shared cache, surfacing the backend's error reason when the read fails.
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/refresh-all
- agentictoolkit://cookbook/status/dashboard/state/config-status
references: []
approved-by: ''
approved-date: ''
---

# Status State

## Overview

The status state is the dashboard's read of the service health summary. It issues one `GET /status` request through an injected API client and caches the response — `{ overall, services, checkedAt }` — under the shared cache key `status`. The dashboard view is its consumer: it reads `data.services`, `data.checkedAt`, the loading flag and the error, and renders `Failed to load status — <error message>` when the read fails.

The one piece of logic this state adds over a plain request is error-reason extraction: the endpoint returns `{ error }` with the real reason (for example a database outage), and that is surfaced as the thrown message so the UI shows WHY, not `status 503`. The state returns the full underlying read result unchanged.

## Behavioral Requirements

### Query identity and options

- **query-key**: The state MUST register its read under the cache key `status`.
- **result-type**: The state MUST return the full read-result object produced by the underlying read mechanism, with no fields added, removed or renamed.
- **refetch-on-focus**: The read MUST refetch automatically when the application regains focus, so a stale `status` read refetches without a manual reload.
- **no-interval**: The read MUST NOT set its own periodic refresh interval; periodic refresh is owned outside this state (the app's refresh-all state refetches every non-live, non-disabled read on a 60-second default interval).
- **no-enabled-option**: The state MUST take no parameters and MUST NOT support being conditionally disabled, so every active consumer is an active observer.
- **client-defaults**: The read MUST NOT set its own retry count, staleness duration, cache lifetime or timeout; those come from the host cache's defaults.

### Request

- **client-injection**: The read MUST obtain its transport from an injected API client, which resolves to an overriding client when one has been provided and to the same-origin default client otherwise.
- **request-path**: Each read MUST call the client's request operation for `/status` exactly once, with no extra request options, so the request is a `GET` to `<basePath>/status` (`/api/status` with the default base path).
- **raw-fetch**: The state MUST use the client's basic request operation, not its JSON-decoding convenience method, so no `Content-Type` header is added and the convenience method's own `${method} ${url} → ${status}` error format is not used.

### Success path

- **success-ok**: When the response has `ok === true` (status 200–299), the read MUST resolve to the parsed JSON body.
- **success-unvalidated**: The parsed body MUST be returned as the response type by assertion only; the state performs no runtime shape check on `overall`, `services` or `checkedAt`.
- **success-parse-failure**: When a successful response body is not valid JSON, the read MUST fail with the rejection produced by parsing it as JSON, not with a `status <code>` message.

### Error path

- **error-body-read**: When the response has `ok === false`, the state MUST attempt to parse the body as JSON and read its `error` field.
- **error-detail-message**: When that `error` field is a non-empty string, the read MUST fail with an error whose message is the string unchanged.
- **error-status-fallback**: When the body is not JSON, has no `error` field, or its `error` is an empty string, `null` or otherwise falsy, the read MUST fail with an error whose message is `status <code>`, where `<code>` is the numeric HTTP status (for example `status 503`).
- **error-parse-swallowed**: A JSON parse failure while reading the error body MUST NOT escape; it MUST be converted to the `status <code>` fallback message.
- **error-nonstring-detail**: The state MUST NOT narrow `error` to a string at runtime; a truthy non-string `error` (for example an object) MUST be used as the error message source as-is, producing its string coercion as the message (for an object, `[object Object]`).
- **error-message-only**: The failure MUST carry only a message; the HTTP status code and response body are not attached to it as additional properties.
- **network-failure**: When the underlying request itself fails (network unreachable, DNS failure, CORS), the read MUST fail with that failure unchanged.

### Caching, concurrency and side effects

- **shared-cache**: All consumers under one shared cache MUST share the single `status` read; concurrent mounts MUST NOT start more than one in-flight request beyond the cache's own deduplication.
- **no-cancellation**: The read MUST NOT accept or forward a cancellation signal; an in-flight request runs to completion even when the read is cancelled or its consumers unmount.
- **side-effects**: The state's only side effect MUST be the one `GET /status` request per read; it MUST NOT write storage, log, emit analytics, or mutate server state.
- **server-contract**: The response body shape and the `{ error }` failure body are owned by the status service's `/status` endpoint; this state surfaces whatever that endpoint sends, unchanged apart from the error-message extraction above.

## Appearance

Not applicable — this is a data state, not a visual component.

## States

Not applicable — this is a data state, not a visual component.

## Accessibility

Not applicable — this is a data state, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-001 | query-key, request-path, success-ok | Default client; the transport resolves with status `200` and body `{ "overall": "operational", "services": [], "checkedAt": "2026-09-24T00:00:00Z" }` | One request to `/api/status`; `data` deep-equals the body; `error` is `null`; the read is cached under `status` |
| use-status-002 | error-body-read, error-detail-message | The transport resolves with status `503` and body `{ "error": "database unavailable" }` | Read fails; `error` is an error whose message is exactly `database unavailable` |
| use-status-003 | error-status-fallback | The transport resolves with status `503` and body `{}` | `error.message` is `status 503` |
| use-status-004 | error-status-fallback, error-parse-swallowed | The transport resolves with status `502` and a non-JSON body `Bad Gateway` | `error.message` is `status 502`; no JSON parsing error surfaces |
| use-status-005 | error-status-fallback | The transport resolves with status `500` and body `{ "error": "" }` | `error.message` is `status 500` |
| use-status-006 | error-nonstring-detail | The transport resolves with status `500` and body `{ "error": { "message": "x" } }` | `error.message` is `[object Object]` |
| use-status-007 | network-failure | The transport itself fails with a network-level error | `error` is that same failure, unchanged |
| use-status-008 | success-parse-failure | The transport resolves with status `200` and a non-JSON body `not json` | Read fails with the error produced by parsing the body as JSON; message does not start with `status ` |
| use-status-009 | client-injection, request-path | An overriding client configured with base path `/proxy`; the transport resolves with status `200` and a valid body | The request URL is `/proxy/status` |
| use-status-010 | shared-cache | Two consumers use the status state under one shared cache; the transport resolves after a delay | Exactly one request is made; both consumers receive the same `data` |
| use-status-011 | refetch-on-focus | The read is loaded and stale; the application regains focus | One additional request to `/status` is made |
| use-status-012 | error-message-only | The transport resolves with status `503` and body `{ "error": "db down" }` | `error` has no `status` or `body` property; only `message` is `db down` |
| use-status-013 | result-type | A consumer mock providing the result shape `{ isLoading: false, error: null, data: { overall: "operational", checkedAt, services: [one healthy service] } }` | The dashboard view reads `data.services` and `data.checkedAt` from the result without adaptation (the result is the raw read result) |

## Edge Cases

- **Empty services list**: A `200` body with `services: []` MUST resolve as-is; the state does not treat an empty list as an error (MUST).
- **Missing or malformed fields in a 200 body**: A body lacking `services` or `checkedAt`, or with wrong types, MUST resolve without error because the body is cast, not validated; consumers such as the dashboard view guard by defaulting a missing services list to an empty one (MUST, as implemented).
- **Non-JSON 200 body**: The read MUST fail with the JSON parsing error (MUST).
- **Non-JSON error body**: The parse failure MUST be caught and replaced by `status <code>` (MUST).
- **Empty-string or null `error`**: Falsy detail MUST fall back to `status <code>` (MUST).
- **Non-string `error`**: A truthy object or number is used unconverted, yielding a coerced message such as `[object Object]` or `42`; the reason is lossy but the failure is still reported (MUST, as implemented).
- **Network unreachable / offline**: The transport rejects and the read fails with that rejection; the state adds no retry, backoff or offline detection of its own beyond the host cache's defaults (MUST).
- **Timeout**: The state sets no timeout; a request that never settles leaves the read pending until the platform's network stack gives up (MUST, as implemented).
- **Cancellation / unmount**: The request is not tied to a cancellation signal, so an unmounted or cancelled read's request still completes and its result may populate the cache (MUST, as implemented).
- **Concurrent callers**: Reads are deduplicated by cache key, so concurrent mounts share one in-flight request; there is no interleaving to order (MUST).
- **No provider mounted**: When no client is injected, the state falls back to the module-level default client at `/api` (MUST).
- **Window focus while fresh**: Refetch-on-focus refetches only when the read is stale per the host's staleness setting; a fresh read is not refetched on focus (MUST, per the cache's semantics).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Injected API client | API client | resolved via dependency injection; same-origin client at the default base path (`/api`) | Transport for the `GET /status` request; overridden via the client provider's client or base path. |
| Shared cache (injected) | cache | host cache provider | Owns caching, retry, stale time and garbage collection; the state sets none of these. |
| Cache key | fixed | `status` | Fixed cache key; not exported as a constant. |
| Refetch on focus | boolean | `true` | Fixed in the source; not caller-configurable. |

The state takes no arguments and reads no environment variables.

## Deep Linking

Not applicable: the state is a data source with no route or URL of its own; its only URL is the backend `/status` API path it fetches.

## Localization

The state emits one hardcoded, untranslated English message pattern that consumers display to the user (the dashboard view renders it after `Failed to load status — `):

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none; inline literal) | `status <code>` | Thrown error message when an error response carries no usable `error` detail; `<code>` is the numeric HTTP status. |

The backend-supplied `error` string is passed through untranslated.

## Accessibility Options

Not applicable: the state renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: the state reads the operator's own service health summary (service names, URLs, status codes, response times) from the app's backend, keeps it only in the in-memory cache, and sends no credentials or personal data of its own.

## Logging

Not applicable: the source contains no log calls; failures are surfaced through the returned `error` field instead.

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor` store with `status: StatusResponse?`, `isLoading: Bool` and `error: Error?`. Fetch with `URLSession.shared.data(from:)` and decode with `JSONDecoder` into a `Decodable` `StatusResponse`; on a non-2xx `HTTPURLResponse`, try decoding `{ error: String? }` and throw a custom error with that message or `"status \(code)"`. Note that `Decodable` validates shape, unlike the source's cast. Refresh on `scenePhase == .active` to mirror refetch-on-focus; share one store through the environment to replace the shared cache.
- **Compose**: A `ViewModel` exposing `StateFlow<UiState<StatusResponse>>`, loading with Ktor `HttpClient` or Retrofit plus `kotlinx.serialization`. Map a non-2xx response by decoding an `ErrorBody(val error: String? = null)` inside `runCatching`, falling back to `"status $code"`. Refetch on `Lifecycle.Event.ON_RESUME` for the focus behavior.
- **React/Web**: Source platform. `hooks/use-status.ts` wraps `@tanstack/react-query`'s `useQuery`, returning its `UseQueryResult<StatusResponse>` unchanged and caching it under the key `["status"]`; it depends on `api/client.ts` (`useStatusApi`, `StatusApiClient.fetch`) and `types.ts` (`StatusResponse`, `ServiceStatusDTO`, `OverallStatus`). Its consumer is `components/Dashboard.tsx`; `components/Dashboard.dom.test.tsx` mocks the hook's result shape. Periodic refresh comes from `hooks/use-refresh-all.ts`, not from this hook. The module must be marked `"use client"` because it calls React hooks and touches the client-side cache. A network failure surfaces as whatever rejection the browser `fetch` API produces (typically a `TypeError`, e.g. `Failed to fetch`). Concurrent mounts share one in-flight request because react-query deduplicates by key and JavaScript is single-threaded.
- **AppKit / UIKit**: Same store as SwiftUI, observed via Observation tracking or Combine `@Published`; trigger a refresh from `NSApplication.didBecomeActiveNotification` / `UIApplication.didBecomeActiveNotification` to mirror refetch-on-focus.
- **WinUI 3**: Implement a singleton `StatusService : INotifyPropertyChanged` registered in the DI container, holding `Status` (`StatusResponse?`), `IsLoading` and `Error`. Send the request with a shared `HttpClient` (`GetAsync($"{basePath}/status")`); on `IsSuccessStatusCode`, deserialize with `JsonSerializer.DeserializeAsync<StatusResponse>` (`System.Text.Json`, `PropertyNameCaseInsensitive` or `JsonPropertyName` attributes for camelCase). On failure, wrap `JsonSerializer.Deserialize<ErrorBody>` in `try/catch (JsonException)` and raise `new Exception(body?.Error is { Length: > 0 } e ? e : $"status {(int)resp.StatusCode}")`. Map `HttpRequestException` to the network-failure path. Mirror refetch-on-focus by handling `Window.Activated` (`WindowActivationState != Deactivated`) and reloading when stale. Unlike react-query, nothing deduplicates concurrent loads: cache the in-flight `Task` and return it to concurrent callers. `HttpClient` has a 100-second default `Timeout`, unlike the source's untimed fetch; pass a `CancellationToken` if cancellation is wanted, which the source does not do. Marshal property changes to the UI thread with `DispatcherQueue.TryEnqueue`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-status.ts` |

## Design Decisions

**Decision**: Surface the endpoint's `error` string as the thrown message, falling back to `status <code>`.
**Rationale**: The endpoint returns the real reason (for example a DB outage) and the UI should show "WHY, not \"status 503\"". The fallback keeps a message when the body carries no reason.
**Approved**: pending

**Decision**: On the web implementation, use the API client's raw request method instead of its JSON-decoding convenience method (`StatusApiClient.json`).
**Rationale**: The convenience method would prefix the message with `GET /api/status → 503 — `; the raw path lets the state throw the bare reason string. The trade-off is that a non-string `error` (which the convenience method's `errorDetail` would unwrap via `error.message`) is coerced here to `[object Object]`.
**Approved**: pending

**Decision**: Enable refetch-on-focus and set no periodic refresh interval (on the web implementation, react-query's `refetchOnWindowFocus: true` with no `refetchInterval`).
**Rationale**: Focus refetch keeps the summary current when the operator returns to the tab; the 60-second periodic refresh is centralized in the refresh-all state so all supporting datasets refresh together.
**Approved**: pending

**Decision**: On the web implementation, return the success body by type assertion without runtime validation.
**Rationale**: The body shape is owned by the status service's endpoint in the same toolkit; consumers guard optional access (for example defaulting to an empty list). A malformed body therefore resolves rather than failing. Other platforms (for example SwiftUI's `Decodable`) validate shape instead, per Platform Notes.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
