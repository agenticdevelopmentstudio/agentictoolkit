---
id: 77a6910a-090c-464a-b3f2-4a7af36aa212
title: Telemetry Sources
domain: agentictoolkit://cookbook/status/dashboard/telemetry/sources
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Two interchangeable adapters that read a telemetry snapshot over HTTP —
  one reading live data (/telemetry) and one reading persisted data (/errors +
  /analytics).
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/api
related:
- agentictoolkit://cookbook/status/dashboard/state/telemetry
- agentictoolkit://cookbook/status/service/telemetry
references: []
approved-by: ''
approved-date: ''
---

# Telemetry Sources

## Overview

This module provides two interchangeable adapters behind a shared telemetry-source contract: an object exposing exactly one operation, `get`, that takes the injected API client and resolves to a telemetry snapshot. Each reads one snapshot (fields `generatedAt`, `errors`, `analytics`) from the dashboard backend through the caller's injected client, so the consumer never knows whether the data is live or persisted.

- The **live source** reads `/telemetry`, where the backend polls the configured error-tracking and analytics providers and returns the data directly. Its authoring note states that no database sits anywhere on this path, so a database outage cannot affect the dashboard's errors and analytics. It is the source wired today.
- The **persisted source** reads the persisted store via `/errors` and `/analytics` in parallel and assembles the snapshot itself. It is documented as the target for reconnecting the persisted backend later.

The composition root holds both adapters and exports the active one; switching backends is a one-line change there. The only consumer is the telemetry state, which calls the active source's `get` operation as its read function.

## Behavioral Requirements

### Shared contract

- **source-shape**: Each source MUST be an object exposing exactly one async operation, `get`, that takes the injected API client and resolves to a telemetry snapshot.
- **api-injection**: Each source MUST issue every HTTP request through the injected client's request operation, with a path relative to the client's base (for example `/telemetry`), never through a global network call or an absolute URL.
- **get-only-requests**: Each source MUST call the injected client's request operation with a path and no extra options, so every request is a plain GET with no custom headers or body.
- **stateless**: Each source MUST hold no state between calls; every `get` issues fresh requests and returns a new snapshot.
- **no-cache**: A source MUST NOT read or write the snapshot cache; caching belongs to the cache abstraction and the telemetry state.
- **interchangeable**: Both sources MUST resolve to the same snapshot shape so the composition root can swap one for the other with no change to any consumer.
- **error-propagation**: A source MUST reject the returned promise on failure rather than resolving to an empty or partial snapshot; it MUST NOT catch or log errors itself.
- **network-rejection**: When the injected client's request rejects (network failure, aborted request), the source's `get` MUST reject with that same error, unwrapped.
- **json-parse-rejection**: When a response with a 2xx status carries a body that is not valid JSON, `get` MUST reject with the error thrown while parsing the body as JSON.
- **no-timeout**: A source MUST NOT impose its own timeout or cancellation; a request that never settles leaves `get` pending.
- **no-retry**: A source MUST NOT retry a failed request; retry policy belongs to the caller (the telemetry state allows one retry).
- **response-shape-trusted**: Both sources trust the backend's response contract: they treat the parsed JSON as already matching the expected shape and perform no runtime validation, so a 2xx body missing `errors`, `analytics`, `metrics` or `generatedAt` resolves as a snapshot whose fields are `undefined`, with no error. Guaranteeing the shape is the backend's job; a source MAY add validation but does not today.

### Live source

- **live-endpoint**: The live source's `get` MUST issue exactly one request, to `/telemetry`.
- **live-status-check**: When the `/telemetry` response has `ok === false` (status outside 200–299), the live source's `get` MUST reject with an error whose message is `telemetry ${status}` (for example `telemetry 503`), without reading the body.
- **live-passthrough**: On an `ok` response, the live source's `get` MUST resolve to the parsed JSON body unchanged, including the server-supplied `generatedAt`.
- **live-no-database**: The live source MUST depend only on `/telemetry`; it MUST NOT call `/errors` or `/analytics`.

### Persisted source

- **turso-endpoints**: The persisted source's `get` MUST issue exactly two requests, `/errors` and `/analytics`.
- **turso-parallel**: The persisted source's `get` MUST start both requests concurrently and wait for both responses before checking either status.
- **turso-network-rejection-order**: When either request rejects, the persisted source's `get` MUST reject with the first rejection to settle, and MUST NOT check any status.
- **turso-errors-status**: When the `/errors` response is not `ok`, the persisted source's `get` MUST reject with an error whose message is `errors ${status}`.
- **turso-analytics-status**: When the `/errors` response is `ok` and the `/analytics` response is not, the persisted source's `get` MUST reject with an error whose message is `analytics ${status}`.
- **turso-status-precedence**: When both responses are not `ok`, the persisted source's `get` MUST reject with the `errors ${status}` message; the `/analytics` status is not reported.
- **turso-body-order**: The persisted source's `get` MUST check both statuses before parsing either body, then parse `/errors` before `/analytics`.
- **turso-errors-projection**: The persisted source's `get` MUST take the snapshot's `errors` from the `errors` property of the `/errors` body and discard any other properties.
- **turso-analytics-projection**: The persisted source's `get` MUST take the snapshot's `analytics` from the `metrics` property of the `/analytics` body, renaming `metrics` to `analytics`, and discard any other properties.
- **turso-generated-at**: The persisted source's `get` MUST set `generatedAt` to the client's clock at assembly time, not to any server-supplied time.
- **turso-snapshot-keys**: The snapshot the persisted source's `get` resolves MUST contain exactly the keys `generatedAt`, `errors` and `analytics`.

### Composition

- **default-source**: The composition root MUST export the active source as the live source today; changing the one marked line MUST be the only edit required to switch backends.
- **single-threaded**: Concurrent calls to either source's `get` MUST NOT share state and MAY interleave freely, each resolving independently.

## Appearance

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## States

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## Accessibility

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## Conformance Test Vectors

Traced to the two source implementations; no test exercises either source directly (the only telemetry test covers the cache).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sources-001 | live-endpoint, api-injection, get-only-requests | The live source's `get`, given an injected client whose request operation is a fake recording calls | Exactly one call: a request to `/telemetry` with no extra options |
| sources-002 | live-passthrough | `/telemetry` returns 200 with body `{"generatedAt":"2026-09-24T00:00:00Z","errors":[],"analytics":[]}` | Resolves to that object, `generatedAt` equal to `"2026-09-24T00:00:00Z"` |
| sources-003 | live-status-check, error-propagation | `/telemetry` returns 503 | Rejects with an error whose message is `telemetry 503`; body not read |
| sources-004 | network-rejection | The client's request rejects with a network-level error | The live source's `get` rejects with that same error |
| sources-005 | json-parse-rejection | `/telemetry` returns 200 with body `not json` | Rejects with the error thrown while parsing the body as JSON |
| sources-006 | turso-endpoints, turso-parallel | The persisted source's `get`, given a client whose request operation returns promises that stay pending | Both `/errors` and `/analytics` requests are issued before either resolves |
| sources-007 | turso-errors-projection, turso-analytics-projection, turso-snapshot-keys | `/errors` 200 `{"errors":[E],"extra":1}`; `/analytics` 200 `{"metrics":[M]}` | Resolves to `{ generatedAt, errors: [E], analytics: [M] }` with no `extra` or `metrics` key |
| sources-008 | turso-generated-at | Clock fixed at `2026-09-24T12:00:00.000Z`; both endpoints 200 | `generatedAt === "2026-09-24T12:00:00.000Z"` |
| sources-009 | turso-errors-status | `/errors` 500, `/analytics` 200 | Rejects with an error whose message is `errors 500` |
| sources-010 | turso-analytics-status | `/errors` 200, `/analytics` 404 | Rejects with an error whose message is `analytics 404` |
| sources-011 | turso-status-precedence | `/errors` 502, `/analytics` 503 | Rejects with an error whose message is `errors 502` |
| sources-012 | turso-network-rejection-order | The `/analytics` request rejects with a network-level error; the `/errors` request is still pending | Rejects with that same error; no status message produced |
| sources-013 | turso-body-order | `/errors` 200 but invalid JSON body, `/analytics` 200 with valid body | Rejects with the JSON-parse error from the `/errors` body; `/analytics` body not parsed |
| sources-014 | stateless | Call the live source's `get` twice | Two separate `/telemetry` requests; two distinct result objects |
| sources-015 | no-retry | `/telemetry` returns 500 once | Exactly one request made; rejects `telemetry 500` |
| sources-016 | default-source, interchangeable | Read the active exported source from the composition root | It is identical to the live source |

## Edge Cases

- **Empty lists**: A 2xx body with `errors: []` and `analytics: []` (or `metrics: []`) MUST resolve to a snapshot with empty arrays; a source MUST NOT treat it as a failure.
- **Missing field in a 2xx body**: A `/errors` body without an `errors` key resolves with `errors: undefined`; a `/telemetry` body without `analytics` resolves without it. See response-shape-trusted.
- **Non-object 2xx body**: A `/errors` body of `null` MUST reject with the runtime error thrown when reading `.errors` of `null`; a `/telemetry` body of `null` resolves to `null` unchecked. See response-shape-trusted.
- **Redirects**: `ok` is judged on the final response after the request follows redirects; a 3xx that is not followed has `ok === false` and MUST reject with the status message.
- **Unconsumed bodies**: On a non-`ok` response the body is never read; on a persisted-source status failure the other response's body is also left unread. Neither source cancels those bodies.
- **Partial persisted-source success**: One endpoint succeeding and the other failing MUST reject the whole call; a source MUST NOT return a partial snapshot.
- **Hung request**: With no timeout, a request that never settles MUST leave `get` pending indefinitely; for the persisted source, one hung endpoint blocks the whole call even if the other failed with an HTTP status.
- **Concurrent calls**: Overlapping `get` calls MUST each issue their own requests and resolve independently. Deduplication, if any, is the caller's (the telemetry state's shared cache key).
- **Offline**: When the client is offline, the request rejects and `get` MUST reject with that error; showing a cached snapshot is the telemetry state's job.
- **Server behavior**: Which providers `/telemetry` polls, and how `/errors` and `/analytics` read the database, is owned by the backend service, not these sources.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Injected API client (argument to `get`) | API client | none; required | The injected client that resolves relative paths against its base (default base `/api`) and performs the request |
| Active source (composition root) | telemetry-source adapter | live source | Which adapter the dashboard reads through; set to the persisted-source adapter to serve from the database |
| Endpoint paths | string literals | `/telemetry`; `/errors`, `/analytics` | Hard-coded in each source; not configurable |

## Deep Linking

Not applicable: the sources are data adapters with no route or URL of their own; they only request backend paths.

## Localization

Not applicable: the only strings are developer-facing error messages (`telemetry ${status}`, `errors ${status}`, `analytics ${status}`) in hardcoded English, which the sources never present to the user themselves.

## Accessibility Options

Not applicable: the sources render nothing, so no display option can affect them.

## Feature Flags

Not applicable: backend selection is a compile-time constant in the composition root, not a runtime flag.

## Analytics

Not applicable: the sources read analytics KPIs as data (a list of analytics-metric entries) but emit no analytics events.

## Privacy

Not applicable: the sources send no credentials, tokens or user data of their own; they read aggregate error summaries and anonymous KPI counts (anonymous and aggregate, sourced from PostHog) and persist nothing.

## Logging

Not applicable: neither source logs; every failure surfaces as a rejected promise with a status message for the caller to handle.

## Platform Notes

- **SwiftUI**: Model `TelemetrySource` as a `Sendable` protocol with `func get(api: StatusAPIClient) async throws -> TelemetrySnapshot`, and each adapter as a `struct`. Decode with `JSONDecoder` into `Codable` DTOs (which also closes the response-shape question), check `HTTPURLResponse.statusCode` in 200...299, and run the Turso pair with `async let` so both requests start before either is awaited. `async let` cancels the sibling on a throw, which differs from `Promise.all` leaving the other request running.
- **Compose**: A Kotlin `interface TelemetrySource { suspend fun get(api: StatusApiClient): TelemetrySnapshot }` with Ktor or Retrofit plus `kotlinx.serialization`. Use `coroutineScope { val e = async { ... }; val a = async { ... } }` for the Turso pair; structured concurrency cancels the sibling on failure. Throw an `IOException` subclass carrying `"telemetry $status"`.
- **React/Web**: The source platform. `sources/live.ts` is a single `api.fetch` plus an `ok` check; `sources/turso.ts` uses `Promise.all` and renames `metrics` to `analytics`. Both use TypeScript `as` casts, which are erased at runtime, and `Response.ok`. The port lives in `telemetry/ports.ts`, the DTOs in `telemetry/types.ts`, and the selection in `telemetry/client.ts`. Concurrent calls interleave freely because the browser executes JavaScript on a single thread; deduplication across calls, if any, is handled by the caller's cache key (React Query's `queryKey: ["telemetry"]`), not by either source.
- **AppKit / UIKit**: The same Swift adapters as the SwiftUI note, driven from a view controller `Task` or a Combine publisher wrapping `URLSession.dataTask`; no UI-framework-specific code is involved.
- **WinUI 3**: Define `public interface ITelemetrySource { Task<TelemetrySnapshot> GetAsync(IStatusApiClient api, CancellationToken ct = default); }` with `LiveTelemetrySource` and `TursoTelemetrySource` classes. Issue requests through a shared `HttpClient` (`GetAsync(relativeUri)` against a `BaseAddress` standing in for the base path), test `response.IsSuccessStatusCode`, and throw `HttpRequestException($"telemetry {(int)response.StatusCode}")`. Deserialize with `System.Text.Json` (`JsonSerializer.DeserializeAsync<TelemetrySnapshot>` with `JsonSerializerOptions { PropertyNameCaseInsensitive = true }` or `[JsonPropertyName]` attributes), and for Turso read `/analytics` into a `record AnalyticsResponse(List<AnalyticsMetricDto> Metrics)` before mapping to `Analytics`. Run the pair with `Task.WhenAll(errorsTask, analyticsTask)`; unlike `Promise.all`, `WhenAll` waits for both tasks even if one faults, and its awaited exception is the first faulted task in argument order. Stamp `GeneratedAt` with `DateTimeOffset.UtcNow.ToString("O")`. `HttpClient.Timeout` defaults to 100 seconds, unlike the browser's no-timeout fetch. Select the adapter at the composition root through DI (`services.AddSingleton<ITelemetrySource, LiveTelemetrySource>()`), and let the view model marshal results onto the UI thread with `DispatcherQueue` before updating an `INotifyPropertyChanged` or `ObservableCollection` binding.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/telemetry/sources/` |

## Design Decisions

**Decision**: Hide the backend behind a single `TelemetrySource` port with two adapters selected in one composition-root line.
**Rationale**: Per the `ports.ts` and `client.ts` comments, the client "reads through a Source without knowing whether the data is live or from the database", so reconnecting Turso changes one line and leaves the hook, cache and panels untouched.
**Approved**: pending

**Decision**: Make `liveSource` the wired default and route it through `/telemetry`, which touches no database.
**Rationale**: The `live.ts` comment states that "a Turso outage cannot affect the dashboard's errors/analytics" on this path.
**Approved**: pending

**Decision**: `tursoSource` stamps `generatedAt` on the client and renames `metrics` to `analytics`.
**Rationale**: `/errors` and `/analytics` return separate bodies with no snapshot timestamp, so the adapter assembles the snapshot itself to meet the shared `TelemetrySnapshot` contract; the comment says it "Preserves the original useErrors/useAnalytics read logic as a single composable source."
**Approved**: pending

**Decision**: Sources throw on any failure and leave retry, caching and fallback to the caller.
**Rationale**: Per the `FetchResult` comment in `ports.ts`, an empty list must never be mistaken for "no data"; rejecting lets `useTelemetry` keep the cached snapshot rather than overwrite it with an empty one.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | access-patterns |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | failed | access-patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | access-patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

Separation of concerns passes: each adapter knows only its endpoints and the
DTO contract, and neither touches storage or UI. Unit-test coverage fails
because no test exercises `liveSource` or `tursoSource`. Error handling is
partial: non-`ok` statuses become explicit `Error`s carrying the status, but the
body's error detail is discarded, and `tursoSource` reports only the `/errors`
status when both fail. Timeouts are absent and retries are delegated to
`useTelemetry` (one retry, React Query's default delay), so the sources
themselves fail both checks. Graceful degradation is partial: the sources reject
rather than return partial data, which lets the hook fall back to its cached
snapshot, but they offer no fallback themselves. Data integrity is partial
because response bodies are cast, not validated, so a malformed 2xx body passes
through unchecked.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/telemetry/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
