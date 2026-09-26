---
id: c85f8913-1112-4ba2-b78f-2b97ea2f8fba
title: Status Web Telemetry
domain: agentictoolkit://cookbook/status-web/telemetry/src-telemetry
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Client telemetry contract for the status dashboard: snapshot DTOs, ports,
  and the composition root picking the live source and localStorage cache'
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/hooks/use-telemetry
- agentictoolkit://cookbook/status-server/telemetry
- agentictoolkit://cookbook/status-web/api
references: []
approved-by: ''
approved-date: ''
---

# Status Web Telemetry

## Overview

The telemetry subsystem of the status dashboard's web client (`packages/web/packages/status-web/src/telemetry/`) defines what the "production-visibility band" shows (grouped error issues and headline analytics KPIs) and where the browser gets it from. It has three parts:

- `types.ts`: the data contract. These are pure DTO shapes (`ErrorDTO`, `AnalyticsMetricDTO`, `TelemetrySnapshot`) plus the `emptySnapshot()` factory. The file has "ZERO runtime dependencies (no db, no fetch, no react)".
- `ports.ts`: the ports. `FetchResult<T>`, `Fetcher<T>` and `Store<T>` describe the server-side poll-and-persist pipeline. `SnapshotCache` and `TelemetrySource` are the two client-side ports.
- `client.ts`: "THE client composition root". It exports one `cache: SnapshotCache` (wired to the localStorage adapter `localCache`) and one `source: TelemetrySource` (wired to `liveSource`). `tursoSource` is also wired, but inactive.

The [useTelemetry](agentictoolkit://cookbook/status-web/hooks/use-telemetry) hook uses only `cache` and `source`. Swapping the backend means changing one line in `client.ts`, and the hook, cache and panels stay the same. The server side that answers `/telemetry`, `/errors` and `/analytics` is covered by [Status Server Telemetry](agentictoolkit://cookbook/status-server/telemetry). The `StatusApiClient` that every source reads through is covered by [Status Web API](agentictoolkit://cookbook/status-web/api).

## Behavioral Requirements

### Data contract (types.ts)

- **error-dto-shape**: `ErrorDTO` MUST carry `id: string`, `issueKey: string`, `project: string`, `title: string`, `culprit: string | null`, `level: string | null`, `count: number`, `userCount: number`, `firstSeen: string | null`, `lastSeen: string | null` and `permalink: string | null`.
- **error-dto-id**: `ErrorDTO.id` is the stable key for rendering. It MUST hold the GlitchTip issue id when the data comes from the live path and the database row id when it comes from Turso.
- **error-dto-issue-key**: `ErrorDTO.issueKey` MUST be the GlitchTip issue id. It stays the same across polls and is the server store's upsert key.
- **error-dto-timestamps**: `ErrorDTO.firstSeen` and `ErrorDTO.lastSeen` MUST be ISO 8601 strings or `null`.
- **analytics-dto-shape**: `AnalyticsMetricDTO` MUST carry `metric: string`, `window: string`, `scope: string`, `value: number` and `capturedAt: string`.
- **analytics-dto-vocabulary**: The documented values are `metric` = `'pageviews' | 'visitors'`, `window` = `'24h' | '7d'`, and `scope` = `'all'` or a site slug. The type is plain `string`, so these values MUST be treated as documented conventions, not as enforced unions.
- **analytics-dto-aggregate**: An `AnalyticsMetricDTO` MUST describe one anonymous aggregate KPI sample (from PostHog), not per-user data.
- **snapshot-shape**: `TelemetrySnapshot` MUST carry `generatedAt: string` (ISO 8601), `errors: ErrorDTO[]` and `analytics: AnalyticsMetricDTO[]`. It is one self-contained read of everything the band shows.
- **empty-snapshot**: `emptySnapshot()` MUST return a new object `{ generatedAt: "", errors: [], analytics: [] }` on every call. An empty `generatedAt` marks "no data yet".
- **types-no-runtime-deps**: `types.ts` MUST NOT import any runtime module. Its only runtime export is `emptySnapshot`.
- **duplicated-definition**: The `types.ts` comment says the shape "is defined in exactly one place", meaning within status-web; `status-server/src/telemetry/types.ts` and `status-server/src/telemetry/ports.ts` are separate hand-maintained copies with no shared import, generation step or parity test (unlike `board-types-parity.test.ts` and `deploy-status-parity.test.ts`), and they already differ: the web `FetchResult` has no `complete` field, the web `Store.save` takes no `opts`, and the web `TelemetrySource.get` takes a `StatusApiClient` where the server's takes none. A port MUST follow the web copy for the client side.

### Ports (ports.ts)

- **fetch-result-shape**: `FetchResult<T>` MUST carry `ok: boolean` and `items: T[]`.
- **fetch-result-not-ok**: When `FetchResult.ok` is `false`, the provider poll failed. A caller MUST NOT treat the accompanying `items` (usually empty) as "no data", and MUST NOT overwrite or clear a store because of it, since that would wipe data during a temporary provider outage.
- **fetcher-port**: `Fetcher<T>` MUST expose `fetch(): Promise<FetchResult<T>>` and knows nothing about storage.
- **store-port-save**: `Store<T>.save(items: T[]): Promise<void>` MUST persist a freshly fetched set, using upsert or append depending on the stream.
- **store-port-load**: `Store<T>.load(): Promise<T[]>` MUST return the current persisted set.
- **store-port-server-only**: `Fetcher` and `Store` are server-side ports. No module in status-web implements them. They are declared here only to document the pipeline shape.
- **snapshot-cache-port**: `SnapshotCache` MUST expose a synchronous `load(): TelemetrySnapshot | null` and a synchronous `save(snapshot: TelemetrySnapshot): void`.
- **telemetry-source-port**: `TelemetrySource` MUST expose `get(api: StatusApiClient): Promise<TelemetrySnapshot>`. The caller supplies the API client, and every path is resolved through it.

### Composition root (client.ts)

- **cache-binding**: `client.ts` MUST export `cache` typed as `SnapshotCache` and bound to `localCache`.
- **source-binding**: `client.ts` MUST export `source` typed as `TelemetrySource` and bound to `SOURCES.live` (`liveSource`).
- **source-registry**: `client.ts` MUST keep a `SOURCES` map with both `live: liveSource` and `turso: tursoSource`, so either one can be selected by editing the single `source` line and nothing else.
- **static-selection**: Source selection MUST happen at build time, as a code edit. There is no runtime switch, environment variable or setting.

### Live source (sources/live.ts)

- **live-request**: `liveSource.get(api)` MUST issue exactly one `api.fetch("/telemetry")` per call.
- **live-http-error**: When the response is not `ok`, `liveSource.get` MUST reject with `Error("telemetry <status>")`, for example `telemetry 503`.
- **live-body**: When the response is `ok`, `liveSource.get` MUST resolve with the parsed JSON body cast to `TelemetrySnapshot`, including the server's `generatedAt`.
- **live-no-database**: The live path MUST NOT depend on Turso, so a database outage cannot affect the band.

### Turso source (sources/turso.ts)

- **turso-parallel-requests**: `tursoSource.get(api)` MUST issue `api.fetch("/errors")` and `api.fetch("/analytics")` in parallel.
- **turso-errors-http-error**: When the `/errors` response is not `ok`, `tursoSource.get` MUST reject with `Error("errors <status>")`. It checks `/errors` before `/analytics`.
- **turso-analytics-http-error**: When `/errors` is `ok` and `/analytics` is not, `tursoSource.get` MUST reject with `Error("analytics <status>")`.
- **turso-projection**: On success, `tursoSource.get` MUST resolve with `{ generatedAt, errors, analytics }`. `errors` is the `errors` field of the `/errors` body, `analytics` is the `metrics` field of the `/analytics` body, and `generatedAt` is the client's `new Date().toISOString()` at the moment of assembly, not a server timestamp.
- **source-response-trusted**: Both `liveSource` and `tursoSource` trust the status-server response contract and cast the response JSON to the DTO types without checking its shape, so a malformed body reaches the panels and is persisted by `cache.save` unchecked. `parseSnapshot` applies its shape gate only when a snapshot is read back from storage.

### localStorage cache (stores/local-cache.ts)

- **cache-key**: `localCache` MUST read and write the single localStorage key `adh-telemetry-v1`.
- **cache-save-format**: `localCache.save` MUST store `JSON.stringify(snapshot)` under that key and overwrite any earlier value.
- **cache-save-best-effort**: `localCache.save` MUST swallow any exception thrown by storage (quota, disabled storage) without rethrowing or logging. Per the source comment, "the in-memory query result is the live truth".
- **cache-ssr-guard**: Both `localCache.load` and `localCache.save` MUST do nothing when `window` is undefined (server render). In that case `load` returns `null`.
- **cache-load-parse**: `localCache.load` MUST return `parseSnapshot(localStorage.getItem(KEY))`, and MUST return `null` if reading storage throws.
- **parse-empty**: `parseSnapshot` MUST return `null` for `null` or empty-string input.
- **parse-malformed-json**: `parseSnapshot` MUST return `null` when `JSON.parse` throws.
- **parse-shape-gate**: `parseSnapshot` MUST return `null` unless the parsed value is truthy, `generatedAt` is a string, and both `errors` and `analytics` are arrays.
- **parse-projection**: On success, `parseSnapshot` MUST return a new object with only `generatedAt`, `errors` and `analytics`, and drop any other top-level keys. Array elements are passed through without per-field checks. This is a deliberate top-level-only gate.

### Concurrency and side effects

- **single-threaded**: All of this code runs on the browser's single JavaScript thread. `SnapshotCache` calls are synchronous and cannot interleave. Two overlapping `source.get` calls are independent fetches, and ordering their results is up to the caller (react-query in `useTelemetry`).
- **no-timeout-no-retry**: The sources MUST NOT apply their own timeout, cancellation or retry. Those come from the `StatusApiClient` fetch and from the calling hook (`retry: 1`, 60 s poll).
- **side-effects**: The only side effects are the HTTP GETs made by the sources and the single localStorage key written by `localCache.save`. Nothing in the subsystem logs.

## Appearance

Not applicable — this is a client-side data contract and adapter composition for telemetry, not a visual component.

## States

Not applicable — this is a client-side data contract and adapter composition for telemetry, not a visual component.

## Accessibility

Not applicable — this is a client-side data contract and adapter composition for telemetry, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| telemetry-001 | empty-snapshot | `emptySnapshot()` called twice | Each call returns `{ generatedAt: "", errors: [], analytics: [] }`, and the two results are different objects |
| telemetry-002 | cache-save-format, parse-projection | `parseSnapshot(JSON.stringify(snap))` where `snap` has `generatedAt` `2026-06-13T12:00:00.000Z`, one `ErrorDTO` (`id` "1", `project` "hub", `title` "boom", `count` 3) and one `pageviews`/`24h`/`all` metric of value 10 | A value deep-equal to `snap` (from `local-cache.test.ts` "round-trips a stored snapshot") |
| telemetry-003 | parse-empty | `parseSnapshot(null)` and `parseSnapshot("")` | Both return `null` |
| telemetry-004 | parse-malformed-json | `parseSnapshot("{not json")` | `null` |
| telemetry-005 | parse-shape-gate | `parseSnapshot` of the JSON for `null`, `{ generatedAt: "x" }`, `{ generatedAt: 1, errors: [], analytics: [] }`, and `{ generatedAt: "x", errors: "nope", analytics: [] }` | Each returns `null` |
| telemetry-006 | parse-projection | `parseSnapshot('{"generatedAt":"x","errors":[],"analytics":[],"extra":1}')` | `{ generatedAt: "x", errors: [], analytics: [] }` with no `extra` key |
| telemetry-007 | cache-ssr-guard | `localCache.load()` with `window` undefined | Returns `null` and does not touch storage |
| telemetry-008 | cache-save-best-effort | `localCache.save(snap)` when `localStorage.setItem` throws a quota error | Returns normally with no exception |
| telemetry-009 | live-request, live-body | `liveSource.get(api)` where `api.fetch("/telemetry")` answers 200 with a snapshot body | Exactly one fetch to `/telemetry`, and the promise resolves with the body unchanged |
| telemetry-010 | live-http-error | `api.fetch("/telemetry")` answers 503 | The promise rejects with an `Error` whose message is `telemetry 503` |
| telemetry-011 | turso-parallel-requests, turso-projection | `/errors` answers 200 `{ errors: [e] }` and `/analytics` answers 200 `{ metrics: [m] }` | Both fetches are issued before either resolves. The result is `{ errors: [e], analytics: [m] }` with `generatedAt` set to the client's ISO time at assembly |
| telemetry-012 | turso-errors-http-error | `/errors` answers 500 and `/analytics` answers 500 | Rejects with `errors 500` (the `/errors` check runs first) |
| telemetry-013 | turso-analytics-http-error | `/errors` answers 200 and `/analytics` answers 502 | Rejects with `analytics 502` |
| telemetry-014 | cache-binding, source-binding | Import `cache` and `source` from `telemetry/client` | `cache === localCache` and `source === liveSource` |
| telemetry-015 | fetch-result-not-ok | A store consumer receives `{ ok: false, items: [] }` | The consumer leaves its store unchanged, with no save and no clear |

## Edge Cases

- **Nothing cached (first visit)**: `localCache.load()` MUST return `null`, and the hook falls back to `emptySnapshot()`.
- **Corrupt or old-shape cache entry**: A stored value that is not JSON, or lacks the three top-level fields, MUST load as `null` rather than throw. The bad entry stays in storage until the next successful `save` overwrites it.
- **Malformed array elements in cache**: An entry whose `errors` holds non-`ErrorDTO` values MUST still load, because the gate checks only that the fields are arrays. Consumers get the elements unchanged.
- **Storage unavailable or full**: With storage disabled (private mode) or over quota, `load` MUST return `null` and `save` MUST do nothing, silently in both cases.
- **Server render**: With no `window`, both cache operations MUST do nothing, which keeps SSR output and the first client paint identical.
- **Source HTTP failure**: A non-2xx response MUST reject `get` with an `Error` naming the path stem and status. The sources do not return an empty snapshot and do not cache on failure.
- **Network failure**: If `api.fetch` itself rejects (host unreachable), the rejection MUST propagate unchanged out of `get`.
- **Malformed success body**: A 2xx body that is not valid JSON MUST reject `get` with the `SyntaxError` thrown by `Response.json()`. Valid JSON of the wrong shape resolves unchecked (see source-response-trusted).
- **Turso partial failure**: If either request fails, the whole `get` MUST reject, so no half-populated snapshot is returned. The response to the other request is discarded.
- **Timeouts and cancellation**: The sources SHOULD be treated as having no timeout of their own. A hung request waits as long as the underlying fetch and the calling hook allow, which keeps timeout policy in one place (the caller).
- **Provider outage on the server pipeline**: A `FetchResult` with `ok: false` MUST NOT clear persisted data. The client never sees `FetchResult`.
- **Concurrent calls**: Overlapping `get` calls MUST each issue their own requests. There is no shared state or deduplication in the sources.
- **Empty lists**: A snapshot with `errors: []` and `analytics: []` and a non-empty `generatedAt` is a valid "nothing to report" read, and MUST be cached like any other.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `source` (in `client.ts`) | `TelemetrySource` | `SOURCES.live` (`liveSource`) | Where the client reads snapshots. Change it to `SOURCES.turso` to serve from the database. This is a code edit, not a runtime setting |
| `cache` (in `client.ts`) | `SnapshotCache` | `localCache` | Where the client persists the last snapshot |
| `api` (argument to `get`) | `StatusApiClient` | none (the caller supplies it) | The injected HTTP client. It resolves `/telemetry`, `/errors` and `/analytics` against its base path |
| `KEY` (in `local-cache.ts`) | string | `adh-telemetry-v1` | The localStorage key. The `-v1` suffix versions the stored shape |

## Deep Linking

Not applicable: the subsystem exposes no routes or URL handling. It only issues API GETs through `StatusApiClient`.

## Localization

Not applicable: no user-facing strings are produced. The only strings are the developer-facing error messages `telemetry <status>`, `errors <status>` and `analytics <status>`, which are hardcoded English.

## Accessibility Options

Not applicable: nothing is rendered, so there is nothing to respond to display options.

## Feature Flags

Not applicable: the only switch is the source selection in `client.ts`, and it is a code edit, not a flag.

## Analytics

Not applicable: the subsystem emits no analytics events. It only transports PostHog aggregate KPI values (`AnalyticsMetricDTO`) that the server has already computed.

## Privacy

- **Data collected**: None by the client. It only displays error-issue summaries (`title`, `culprit`, `count`, `userCount`, `permalink`) and anonymous aggregate KPIs that the server provides.
- **Storage**: The latest `TelemetrySnapshot`, stored as JSON in browser localStorage under `adh-telemetry-v1`.
- **Transmission**: HTTP GETs to the status API through `StatusApiClient`. Nothing is sent upstream.
- **Retention**: The cached entry lasts until the next successful `save` overwrites it, or until the user clears site data. There is no expiry.

## Logging

Not applicable: no module in the subsystem logs. Source failures surface as rejected promises to the caller, and cache failures are swallowed by design (see cache-save-best-effort).

## Platform Notes

- **SwiftUI**: Model the DTOs as `Codable, Sendable` structs (`ErrorDTO`, `AnalyticsMetricDTO`, `TelemetrySnapshot` with `static let empty`). Express the ports as protocols: `TelemetrySource` with `func get(api: StatusAPIClient) async throws -> TelemetrySnapshot` and a `SnapshotCache` protocol. A `UserDefaults`-backed cache that uses `JSONDecoder` gives the null-on-failure parse via `try?`. Note that `Codable` validates each field, which is stricter than the source's top-level gate. Fire the Turso requests in parallel with `async let`. Hold the selected source as a `let` in a composition-root enum.
- **Compose**: Use Kotlin `@Serializable data class` DTOs and `interface TelemetrySource { suspend fun get(api: StatusApiClient): TelemetrySnapshot }`. Back the cache with `SharedPreferences` or DataStore, and parse with `Json { ignoreUnknownKeys = true }` wrapped in `runCatching` to return `null`. Run the Turso requests in parallel with `coroutineScope { async { } }`. Put the composition root in an `object TelemetryClient`.
- **React/Web**: This is the source: `src/telemetry/types.ts`, `ports.ts`, `client.ts`, `sources/live.ts`, `sources/turso.ts`, `stores/local-cache.ts`, and the vitest suite `stores/local-cache.test.ts`. Its specifics are `typeof window` SSR guards, `localStorage` try/catch, `Promise.all` for Turso, and `as` casts on response JSON. The server keeps its own copy of the types and ports in `status-server/src/telemetry/`.
- **AppKit / UIKit**: The same Swift DTOs and protocols as the SwiftUI note, placed in a shared framework. Use `URLSession.data(for:)` behind the API client, `UserDefaults.standard` for the cache, and a `withThrowingTaskGroup` alternative to `async let` if more sources are added.
- **WinUI 3**: Port the DTOs as C# `record`s (`public sealed record ErrorDTO(string Id, string IssueKey, string Project, string Title, string? Culprit, string? Level, int Count, int UserCount, string? FirstSeen, string? LastSeen, string? Permalink)`) and serialize them with `System.Text.Json` using `JsonSerializerDefaults.Web` so camelCase names match. Define `interface ITelemetrySource { Task<TelemetrySnapshot> GetAsync(IStatusApiClient api, CancellationToken ct = default); }` and `interface ISnapshotCache { TelemetrySnapshot? Load(); void Save(TelemetrySnapshot s); }`. Implement the live source with `HttpClient.GetAsync("telemetry")`, throw `HttpRequestException($"telemetry {(int)r.StatusCode}")` when the status is not a success, and then call `ReadFromJsonAsync<TelemetrySnapshot>()`. Implement the Turso source with `Task.WhenAll` over the two GETs, checking `/errors` before `/analytics`. Implement the cache with `Windows.Storage.ApplicationData.Current.LocalSettings` (8 KB per value, so a large snapshot may need a `LocalFolder` file via `FileIO.WriteTextAsync`) or a file in `LocalFolder`. Wrap `JsonSerializer.Deserialize` in try/catch and return `null`, then check the three members for non-null to match the top-level gate. There is no SSR, so drop the `window` guard. Register the composition root in DI (`services.AddSingleton<ITelemetrySource, LiveTelemetrySource>()`) instead of using a module constant. The view model that consumes it exposes the snapshot through `INotifyPropertyChanged`, and the lists through `ObservableCollection<ErrorDTO>` and `ObservableCollection<AnalyticsMetricDTO>`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/telemetry/client.ts` |
| web | `packages/web/packages/status-web/src/telemetry/ports.ts` |
| web | `packages/web/packages/status-web/src/telemetry/types.ts` |

## Design Decisions

**Decision**: Hide every concrete backend behind ports, and select adapters only in the composition root `client.ts`.
**Rationale**: Per the `ports.ts` and `client.ts` comments, reconnecting the Turso backend means changing one line (`SOURCES.live` to `SOURCES.turso`), and the hook, cache and panels do not change because both sources honor the same `TelemetrySnapshot` contract.
**Approved**: pending

**Decision**: Wire the live `/telemetry` source by default instead of the database-backed one.
**Rationale**: `live.ts` states that there is "No database anywhere on this path: a Turso outage cannot affect the dashboard's errors/analytics".
**Approved**: pending

**Decision**: Persist the last snapshot in localStorage, and make saving best-effort.
**Rationale**: The cache gives instant paint on reload and a last-known view during a brief source outage. The in-memory query result stays the live truth, so a failed write loses only the reload shortcut.
**Approved**: pending

**Decision**: Gate stored snapshots only at the top level, and project them to the three known fields.
**Rationale**: The comment "Defensive, shape-gated parse" favors never throwing over full validation. The `-v1` key suffix allows a future shape change to start clean. The pure `parseSnapshot` is split out so it can be tested without a browser.
**Approved**: pending

**Decision**: `FetchResult.ok = false` must never clear a store.
**Rationale**: The `ports.ts` doc comment warns that an empty list from a failed poll is not "no data", and wiping the store during a temporary provider outage would blank the band.
**Approved**: pending

**Decision**: `tursoSource` stamps `generatedAt` on the client.
**Rationale**: `/errors` and `/analytics` return no snapshot timestamp, so the source records when it assembled the snapshot. As a result, Turso-path `generatedAt` values follow client-clock semantics, while live-path values follow the server clock.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |

**Separation of concerns.** The DTOs have no runtime dependencies, the ports are pure interfaces, the adapters each own one backend, and the composition root is the only place that picks adapters.

**Unit test coverage.** Partial: `local-cache.test.ts` covers `parseSnapshot` for round-trip, empty, malformed JSON and wrong-shape inputs. No test covers `liveSource`, `tursoSource`, the `localCache` I/O wrapper or the composition root.

**Explicit error handling.** Partial: the sources turn non-2xx responses into named `Error`s, and the cache turns every failure into `null` or a no-op. However, `localCache.save` drops write failures with no signal, which the source documents as intended.

**Graceful degradation.** The cached snapshot covers the gap before the first poll and during a brief outage, and the SSR guard keeps server render safe.

**Data integrity.** Partial: stored snapshots pass a top-level shape gate, but source responses are cast without validation, and the web and server copies of the DTOs have no mechanism keeping them in sync. Both are recorded as open questions under Behavioral Requirements.

**Caching strategy.** A single versioned key holds the latest snapshot. Every successful read overwrites it, and live data always takes precedence over the cache.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
