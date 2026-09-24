---
id: 77a6910a-090c-464a-b3f2-4a7af36aa212
title: Status Web Telemetry Sources
domain: agentictoolkit://recipes/status-web-telemetry-sources
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Two interchangeable TelemetrySource adapters that read a TelemetrySnapshot
  over HTTP: live (/telemetry) and Turso-backed (/errors + /analytics).'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-api
related:
- agentictoolkit://recipes/status-web-hooks-use-telemetry
- agentictoolkit://recipes/status-server-telemetry
references: []
approved-by: ''
approved-date: ''
---

# Status Web Telemetry Sources

## Overview

`liveSource` and `tursoSource` are the two client-side adapters behind the
`TelemetrySource` port (`telemetry/ports.ts`): an object with one method,
`get(api: StatusApiClient): Promise<TelemetrySnapshot>`. Each reads one
`TelemetrySnapshot` (`generatedAt`, `errors: ErrorDTO[]`,
`analytics: AnalyticsMetricDTO[]`, defined in `telemetry/types.ts`) from the
dashboard backend through the caller's `StatusApiClient`, so the consumer never
knows whether the data is live or persisted.

- **`liveSource`** (`sources/live.ts`) reads `/telemetry`, where the server
  polls GlitchTip and PostHog and returns DTOs directly. Its authoring comment
  states "No database anywhere on this path: a Turso outage cannot affect the
  dashboard's errors/analytics." It is the source wired today.
- **`tursoSource`** (`sources/turso.ts`) reads the persisted store via
  `/errors` and `/analytics` in parallel and assembles the snapshot itself. Its
  comment calls it the "reconnect the Turso backend later" target.

The composition root `telemetry/client.ts` holds both in
`const SOURCES = { live: liveSource, turso: tursoSource }` and exports
`source = SOURCES.live`; switching to Turso is a one-line change there. The only
consumer is `useTelemetry` (`hooks/use-telemetry.ts`), which calls
`source.get(api)` as its query function.

## Behavioral Requirements

### Shared contract

- **source-shape**: Each source MUST be an object exposing exactly one async operation, `get(api)`, that takes a `StatusApiClient` and resolves to a `TelemetrySnapshot`.
- **api-injection**: Each source MUST issue every HTTP request through the injected `api.fetch(path)` with a path relative to the client's base (for example `/telemetry`), never through a global `fetch` or an absolute URL.
- **get-only-requests**: Each source MUST call `api.fetch` with a path and no `init` argument, so every request is a plain GET with no custom headers or body.
- **stateless**: Each source MUST hold no state between calls; every `get` issues fresh requests and returns a new snapshot.
- **no-cache**: A source MUST NOT read or write the snapshot cache; caching belongs to the `SnapshotCache` port and the `useTelemetry` hook.
- **interchangeable**: Both sources MUST resolve to the same `TelemetrySnapshot` shape so the composition root can swap one for the other with no change to any consumer.
- **error-propagation**: A source MUST reject the returned promise on failure rather than resolving to an empty or partial snapshot; it MUST NOT catch or log errors itself.
- **network-rejection**: When `api.fetch` rejects (network failure, aborted request), the source's `get` MUST reject with that same error, unwrapped.
- **json-parse-rejection**: When a response with a 2xx status carries a body that is not valid JSON, `get` MUST reject with the error thrown by `Response.json()`.
- **no-timeout**: A source MUST NOT impose its own timeout or cancellation; a request that never settles leaves `get` pending.
- **no-retry**: A source MUST NOT retry a failed request; retry policy belongs to the caller (`useTelemetry` passes `retry: 1` to React Query).
- **response-shape-trusted**: Both sources trust the status-server response contract: they cast the parsed JSON with `as` and never check its shape, so a 2xx body missing `errors`, `analytics`, `metrics` or `generatedAt` resolves as a snapshot whose fields are `undefined`, with no error. Guaranteeing the shape is the backend's (status-server's) job; a port MAY add validation but the source does not.

### liveSource

- **live-endpoint**: `liveSource.get` MUST issue exactly one request, to `/telemetry`.
- **live-status-check**: When the `/telemetry` response has `ok === false` (status outside 200–299), `liveSource.get` MUST reject with an `Error` whose message is `telemetry ${status}` (for example `telemetry 503`), without reading the body.
- **live-passthrough**: On an `ok` response, `liveSource.get` MUST resolve to the parsed JSON body unchanged, including the server-supplied `generatedAt`.
- **live-no-database**: `liveSource` MUST depend only on `/telemetry`; it MUST NOT call `/errors` or `/analytics`.

### tursoSource

- **turso-endpoints**: `tursoSource.get` MUST issue exactly two requests, `/errors` and `/analytics`.
- **turso-parallel**: `tursoSource.get` MUST start both requests concurrently and wait for both responses (`Promise.all`) before checking either status.
- **turso-network-rejection-order**: When either request rejects, `tursoSource.get` MUST reject with the first rejection to settle (`Promise.all` semantics) and MUST NOT check any status.
- **turso-errors-status**: When the `/errors` response is not `ok`, `tursoSource.get` MUST reject with an `Error` whose message is `errors ${status}`.
- **turso-analytics-status**: When the `/errors` response is `ok` and the `/analytics` response is not, `tursoSource.get` MUST reject with an `Error` whose message is `analytics ${status}`.
- **turso-status-precedence**: When both responses are not `ok`, `tursoSource.get` MUST reject with the `errors ${status}` message; the `/analytics` status is not reported.
- **turso-body-order**: `tursoSource.get` MUST check both statuses before parsing either body, then parse `/errors` before `/analytics`.
- **turso-errors-projection**: `tursoSource.get` MUST take the snapshot's `errors` from the `errors` property of the `/errors` body (`{ errors: ErrorDTO[] }`) and discard any other properties.
- **turso-analytics-projection**: `tursoSource.get` MUST take the snapshot's `analytics` from the `metrics` property of the `/analytics` body (`{ metrics: AnalyticsMetricDTO[] }`), renaming `metrics` to `analytics`, and discard any other properties.
- **turso-generated-at**: `tursoSource.get` MUST set `generatedAt` to the client's clock at assembly time, as `new Date().toISOString()`, not to any server-supplied time.
- **turso-snapshot-keys**: The snapshot `tursoSource.get` resolves MUST contain exactly the keys `generatedAt`, `errors` and `analytics`.

### Composition

- **default-source**: The composition root MUST export `source` as `liveSource` today; changing the one marked line to `SOURCES.turso` MUST be the only edit required to switch backends.
- **single-threaded**: Both sources run on the browser's single JavaScript thread; concurrent `get` calls MUST NOT share state and MAY interleave freely, each resolving independently.

## Appearance

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## States

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## Accessibility

Not applicable — this is a pair of HTTP data-source adapters, not a visual component.

## Conformance Test Vectors

Traced to `sources/live.ts` and `sources/turso.ts`; no test file exercises either source directly (the only telemetry test, `stores/local-cache.test.ts`, covers the cache).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sources-001 | live-endpoint, api-injection, get-only-requests | `liveSource.get(api)` with a fake `api.fetch` recording calls | Exactly one call: `api.fetch("/telemetry")` with no second argument |
| sources-002 | live-passthrough | `/telemetry` returns 200 with body `{"generatedAt":"2026-09-24T00:00:00Z","errors":[],"analytics":[]}` | Resolves to that object, `generatedAt` equal to `"2026-09-24T00:00:00Z"` |
| sources-003 | live-status-check, error-propagation | `/telemetry` returns 503 | Rejects with `Error` message `telemetry 503`; body not read |
| sources-004 | network-rejection | `api.fetch` rejects with `TypeError("Failed to fetch")` | `liveSource.get` rejects with that same `TypeError` |
| sources-005 | json-parse-rejection | `/telemetry` returns 200 with body `not json` | Rejects with the `SyntaxError` thrown by `Response.json()` |
| sources-006 | turso-endpoints, turso-parallel | `tursoSource.get(api)` with a fake `api.fetch` whose promises stay pending | Both `api.fetch("/errors")` and `api.fetch("/analytics")` are called before either resolves |
| sources-007 | turso-errors-projection, turso-analytics-projection, turso-snapshot-keys | `/errors` 200 `{"errors":[E],"extra":1}`; `/analytics` 200 `{"metrics":[M]}` | Resolves to `{ generatedAt, errors: [E], analytics: [M] }` with no `extra` or `metrics` key |
| sources-008 | turso-generated-at | Clock fixed at `2026-09-24T12:00:00.000Z`; both endpoints 200 | `generatedAt === "2026-09-24T12:00:00.000Z"` |
| sources-009 | turso-errors-status | `/errors` 500, `/analytics` 200 | Rejects with `Error` message `errors 500` |
| sources-010 | turso-analytics-status | `/errors` 200, `/analytics` 404 | Rejects with `Error` message `analytics 404` |
| sources-011 | turso-status-precedence | `/errors` 502, `/analytics` 503 | Rejects with `Error` message `errors 502` |
| sources-012 | turso-network-rejection-order | `/analytics` fetch rejects with `TypeError`; `/errors` still pending | Rejects with that `TypeError`; no status message produced |
| sources-013 | turso-body-order | `/errors` 200 but invalid JSON body, `/analytics` 200 with valid body | Rejects with the `SyntaxError` from the `/errors` body; `/analytics` body not parsed |
| sources-014 | stateless | Call `liveSource.get(api)` twice | Two separate `/telemetry` requests; two distinct result objects |
| sources-015 | no-retry | `/telemetry` returns 500 once | Exactly one request made; rejects `telemetry 500` |
| sources-016 | default-source, interchangeable | Import `source` from `telemetry/client.ts` | `source === liveSource` |

## Edge Cases

- **Empty lists**: A 2xx body with `errors: []` and `analytics: []` (or `metrics: []`) MUST resolve to a snapshot with empty arrays; a source MUST NOT treat it as a failure.
- **Missing field in a 2xx body**: A `/errors` body without an `errors` key resolves with `errors: undefined`; a `/telemetry` body without `analytics` resolves without it. See response-shape-trusted.
- **Non-object 2xx body**: A `/errors` body of `null` MUST reject with a `TypeError` when reading `.errors` of `null`; a `/telemetry` body of `null` resolves to `null` unchecked. See response-shape-trusted.
- **Redirects**: `ok` is judged on the final response after `fetch` follows redirects; a 3xx that is not followed has `ok === false` and MUST reject with the status message.
- **Unconsumed bodies**: On a non-`ok` response the body is never read; on a Turso status failure the other response's body is also left unread. Neither source cancels those bodies.
- **Partial Turso success**: One endpoint succeeding and the other failing MUST reject the whole call; a source MUST NOT return a partial snapshot.
- **Hung request**: With no timeout, a request that never settles MUST leave `get` pending indefinitely; for `tursoSource`, one hung endpoint blocks the whole call even if the other failed with an HTTP status.
- **Concurrent calls**: Single-threaded JavaScript; overlapping `get` calls MUST each issue their own requests and resolve independently. Deduplication, if any, is the caller's (React Query's `queryKey: ["telemetry"]`).
- **Offline**: When the browser is offline, `api.fetch` rejects and `get` MUST reject with that error; showing a cached snapshot is the `useTelemetry` hook's job.
- **Server behavior**: Which providers `/telemetry` polls, and how `/errors` and `/analytics` read the database, is owned by the status server, not these sources.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `api` | `StatusApiClient` (argument to `get`) | none; required | The injected client that resolves relative paths against its base (default base `/api`, via `createStatusApiClient`) and performs the request |
| `source` (in `telemetry/client.ts`) | `TelemetrySource` | `SOURCES.live` | Which adapter the dashboard reads through; set to `SOURCES.turso` to serve from the database |
| Endpoint paths | string literals | `/telemetry`; `/errors`, `/analytics` | Hard-coded in each source; not configurable |

## Deep Linking

Not applicable: the sources are data adapters with no route or URL of their own; they only request backend paths.

## Localization

Not applicable: the only strings are developer-facing error messages (`telemetry ${status}`, `errors ${status}`, `analytics ${status}`) in hardcoded English, which the sources never present to the user themselves.

## Accessibility Options

Not applicable: the sources render nothing, so no display option can affect them.

## Feature Flags

Not applicable: backend selection is a compile-time constant in `telemetry/client.ts`, not a runtime flag.

## Analytics

Not applicable: the sources read analytics KPIs as data (`AnalyticsMetricDTO`) but emit no analytics events.

## Privacy

Not applicable: the sources send no credentials, tokens or user data of their own; they read aggregate error summaries and anonymous KPI counts ("anonymous + aggregate (from PostHog)" per `types.ts`) and persist nothing.

## Logging

Not applicable: neither source logs; every failure surfaces as a rejected promise with a status message for the caller to handle.

## Platform Notes

- **SwiftUI**: Model `TelemetrySource` as a `Sendable` protocol with `func get(api: StatusAPIClient) async throws -> TelemetrySnapshot`, and each adapter as a `struct`. Decode with `JSONDecoder` into `Codable` DTOs (which also closes the response-shape question), check `HTTPURLResponse.statusCode` in 200...299, and run the Turso pair with `async let` so both requests start before either is awaited. `async let` cancels the sibling on a throw, which differs from `Promise.all` leaving the other request running.
- **Compose**: A Kotlin `interface TelemetrySource { suspend fun get(api: StatusApiClient): TelemetrySnapshot }` with Ktor or Retrofit plus `kotlinx.serialization`. Use `coroutineScope { val e = async { ... }; val a = async { ... } }` for the Turso pair; structured concurrency cancels the sibling on failure. Throw an `IOException` subclass carrying `"telemetry $status"`.
- **React/Web**: The source platform. `sources/live.ts` is a single `api.fetch` plus an `ok` check; `sources/turso.ts` uses `Promise.all` and renames `metrics` to `analytics`. Both use TypeScript `as` casts, which are erased at runtime, and `Response.ok`. The port lives in `telemetry/ports.ts`, the DTOs in `telemetry/types.ts`, and the selection in `telemetry/client.ts`.
- **AppKit / UIKit**: The same Swift adapters as the SwiftUI note, driven from a view controller `Task` or a Combine publisher wrapping `URLSession.dataTask`; no UI-framework-specific code is involved.
- **WinUI 3**: Define `public interface ITelemetrySource { Task<TelemetrySnapshot> GetAsync(IStatusApiClient api, CancellationToken ct = default); }` with `LiveTelemetrySource` and `TursoTelemetrySource` classes. Issue requests through a shared `HttpClient` (`GetAsync(relativeUri)` against a `BaseAddress` standing in for the base path), test `response.IsSuccessStatusCode`, and throw `HttpRequestException($"telemetry {(int)response.StatusCode}")`. Deserialize with `System.Text.Json` (`JsonSerializer.DeserializeAsync<TelemetrySnapshot>` with `JsonSerializerOptions { PropertyNameCaseInsensitive = true }` or `[JsonPropertyName]` attributes), and for Turso read `/analytics` into a `record AnalyticsResponse(List<AnalyticsMetricDto> Metrics)` before mapping to `Analytics`. Run the pair with `Task.WhenAll(errorsTask, analyticsTask)`; unlike `Promise.all`, `WhenAll` waits for both tasks even if one faults, and its awaited exception is the first faulted task in argument order. Stamp `GeneratedAt` with `DateTimeOffset.UtcNow.ToString("O")`. `HttpClient.Timeout` defaults to 100 seconds, unlike the browser's no-timeout fetch. Select the adapter at the composition root through DI (`services.AddSingleton<ITelemetrySource, LiveTelemetrySource>()`), and let the view model marshal results onto the UI thread with `DispatcherQueue` before updating an `INotifyPropertyChanged` or `ObservableCollection` binding.

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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
