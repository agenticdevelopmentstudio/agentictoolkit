---
id: 9ff57831-bdf9-47ad-b009-bcc1de59d5f4
title: useTelemetry
domain: agentictoolkit://cookbook/status-web/hooks/use-telemetry
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that polls the configured TelemetrySource every 60 s, persists
  each snapshot to a localStorage cache, and returns live, cached or empty data.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-server/telemetry
references: []
approved-by: ''
approved-date: ''
---

# useTelemetry

## Overview

`useTelemetry` is the status dashboard's single read of production telemetry: grouped error issues (GlitchTip) and headline analytics KPIs (PostHog), delivered as one `TelemetrySnapshot` (`{ generatedAt, errors, analytics }`). The Overview rail's `ErrorsCard` and `TrafficCard` (`components/TelemetrySections.tsx`) both call it.

The hook knows only two ports, both composed in `telemetry/client.ts`:

- `source: TelemetrySource` — where a fresh snapshot comes from. Today it is `liveSource`, which does `GET /telemetry` through the caller's `StatusApiClient`. `tursoSource` is wired as the alternative and is selected by changing one line in `telemetry/client.ts`.
- `cache: SnapshotCache` — where the browser keeps the last snapshot. Today it is `localCache`, a `localStorage` adapter under the key `adh-telemetry-v1`.

The source comment states the contract: poll the source, persist each snapshot to the cache, hydrate from the cache after mount rather than during render (so server render and first client paint match), and let live data win over the cached snapshot, which wins over an empty snapshot. The hook never names GlitchTip, PostHog or Turso, so swapping the backend leaves it untouched.

## Behavioral Requirements

### Exports and signature

- **poll-interval-constant**: The module MUST export `TELEMETRY_POLL_MS` equal to `60000` (60 seconds).
- **hook-signature**: `useTelemetry()` MUST take no arguments and MUST return a `TelemetrySnapshot`, never `undefined` or `null`.
- **client-only**: The module MUST be a client module (`"use client"`), since it uses React state, effects and the react-query cache.

### Data shape

- **snapshot-shape**: A `TelemetrySnapshot` MUST carry `generatedAt: string` (ISO timestamp), `errors: ErrorDTO[]` and `analytics: AnalyticsMetricDTO[]`.
- **error-dto-shape**: Each `ErrorDTO` MUST carry `id`, `issueKey`, `project`, `title` (strings), `culprit`, `level`, `firstSeen`, `lastSeen`, `permalink` (string or `null`), and `count`, `userCount` (numbers).
- **analytics-dto-shape**: Each `AnalyticsMetricDTO` MUST carry `metric` (for example `pageviews` or `visitors`), `window` (for example `24h` or `7d`), `scope` (`all` or a site slug), `value: number` and `capturedAt` (ISO string).
- **empty-snapshot**: `emptySnapshot()` MUST return a new object `{ generatedAt: "", errors: [], analytics: [] }` on every call.

### Query configuration

- **query-key**: The hook MUST read through a single react-query query keyed `["telemetry"]`, so every caller under one `QueryClient` shares one cached snapshot and one poll.
- **query-fn**: The query function MUST call `source.get(api)`, where `api` is the `StatusApiClient` returned by `useStatusApi()` (the context client, or the same-origin default whose base is `/api`).
- **poll-cadence**: The query MUST refetch every `TELEMETRY_POLL_MS` (60000 ms) while observed; because `refetchIntervalInBackground` is not set, react-query's default pauses this interval while the document is hidden.
- **refetch-on-focus**: The query MUST refetch when the window regains focus (`refetchOnWindowFocus: true`), subject to the host `QueryClient`'s `staleTime`, which the hook does not set.
- **single-retry**: A failed fetch MUST be retried exactly once (`retry: 1`) before the query enters its error state; this per-query setting overrides any `retry` default on the host `QueryClient`. The delay before that retry is react-query's `retryDelay` default, which the hook does not set.

### Live source (`liveSource`, wired today)

- **live-request**: `liveSource.get(api)` MUST issue one `api.fetch("/telemetry")` with no request options (a `GET` to `<basePath>/telemetry`).
- **live-http-error**: A non-2xx response MUST make `liveSource.get` reject with an `Error` whose message is `telemetry <status>` (for example `telemetry 502`).
- **live-body-cast**: A 2xx response body MUST be parsed as JSON and returned as a `TelemetrySnapshot` by cast, with no shape validation; a body that is not JSON rejects the query with the JSON parse error. The response shape is owned by the backend `/telemetry` route (see [Status Server Telemetry](agentictoolkit://cookbook/status-server/telemetry)).

### Cache hydration

- **hydrate-after-mount**: The hook MUST NOT read the cache during render; it MUST call `cache.load()` exactly once per hook instance, in an effect that runs after the first mount.
- **first-render-empty**: On the first render of a hook instance whose query has no data yet, the hook MUST return `emptySnapshot()`, so server-rendered output and the first client paint are identical.
- **cache-load-parse**: `localCache.load()` MUST return the value of `parseSnapshot(localStorage.getItem("adh-telemetry-v1"))`, or `null` when `window` is undefined or reading `localStorage` throws.
- **parse-gate**: `parseSnapshot(raw)` MUST return `null` when `raw` is `null` or empty, when it is not valid JSON, when it parses to `null`, when `generatedAt` is not a string, or when `errors` or `analytics` is not an array.
- **parse-projection**: When the gate passes, `parseSnapshot` MUST return a new object containing only `generatedAt`, `errors` and `analytics`, dropping any other top-level keys; array elements are not validated.

### Cache persistence

- **persist-on-data**: Whenever the query's `data` reference changes to a truthy value, each mounted hook instance MUST call `cache.save(data)` once for that value.
- **cache-save-format**: `localCache.save(snapshot)` MUST write `JSON.stringify(snapshot)` to `localStorage` under the key `adh-telemetry-v1`, replacing any previous value.
- **cache-save-best-effort**: `localCache.save` MUST do nothing when `window` is undefined and MUST swallow any exception from `localStorage.setItem`; the source comment declares it "best-effort — the in-memory query result is the live truth".
- **no-save-on-failure**: A failed query MUST NOT write to or clear the cache; the last successful snapshot stays stored.

### Return precedence

- **live-wins**: When the query has data, the hook MUST return the query's data, regardless of the cached snapshot.
- **cache-fallback**: When the query has no data and the cache load produced a snapshot, the hook MUST return that cached snapshot.
- **empty-fallback**: When the query has no data and the cache load produced `null` (or has not run yet), the hook MUST return `emptySnapshot()`.
- **data-retained-on-error**: After at least one successful fetch in the `QueryClient`, a later failed poll MUST leave the previous data in place (react-query keeps `data` on error), so the hook keeps returning the last live snapshot rather than the cached one.
- **telemetry-failure-signal**: NEEDS REVIEW: Not implemented in source. The hook returns only the snapshot and discards `query.error`, `isError` and `isFetching`, so a source that has never answered is indistinguishable from "zero errors, zero traffic" (`emptySnapshot()`), and a cached or retained snapshot carries no staleness flag beyond its own `generatedAt`; `TelemetrySections.dom.test.tsx` mocks the hook with `stale` and `offline` fields that the hook never returns. Settling this needs the owner to decide whether the hook contract should expose an error or staleness signal.

### Concurrency and side effects

- **shared-poll**: Multiple components calling `useTelemetry` under one `QueryClient` MUST share one in-flight fetch and one interval; additional callers MUST NOT add fetches beyond react-query's deduplication.
- **per-instance-cache-io**: Each mounted hook instance MUST perform its own `cache.load()` on mount and its own `cache.save()` per new data value, so two mounted consumers read `localStorage` twice and write the same snapshot twice.
- **side-effects**: The hook's only side effects MUST be the source's network reads (one `GET /telemetry` per poll today) and the `localStorage` read and writes under `adh-telemetry-v1`; it MUST NOT log, emit analytics, or mutate server state.
- **no-timeout-no-cancel**: The hook MUST NOT impose its own request timeout or cancellation; `liveSource` passes no `AbortSignal` to `api.fetch`, so an in-flight request is not aborted by react-query cancellation.

## Appearance

Not applicable — this is a React data hook, not a visual component.

## States

Not applicable — this is a React data hook, not a visual component.

## Accessibility

Not applicable — this is a React data hook, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| telemetry-001 | poll-interval-constant | Read the exported constant | `TELEMETRY_POLL_MS` is `60000` |
| telemetry-002 | first-render-empty, empty-fallback, hook-signature | Empty `localStorage`; source never resolves; render the hook once | Returned value deep-equals `{ generatedAt: "", errors: [], analytics: [] }` |
| telemetry-003 | hydrate-after-mount, cache-fallback | `localStorage["adh-telemetry-v1"]` holds a valid snapshot `S`; source never resolves | First render returns the empty snapshot; after effects flush, the hook returns a value deep-equal to `S` |
| telemetry-004 | live-wins, persist-on-data, cache-save-format | Cache holds snapshot `A`; source resolves snapshot `B` | Hook returns `B`; `localStorage["adh-telemetry-v1"]` equals `JSON.stringify(B)` |
| telemetry-005 | live-request, query-fn | `StatusApiProvider` with `basePath: "/x"` and a recording `fetch` | Exactly one request to `/x/telemetry` per query run, with no init options |
| telemetry-006 | live-http-error, single-retry, no-save-on-failure | Source `fetch` answers 502 every time; cache holds snapshot `A` | `fetch` is called twice (initial plus one retry); the query error message is `telemetry 502`; the hook returns `A`; `localStorage` still holds `A` |
| telemetry-007 | data-retained-on-error | First poll resolves `B`; next poll (and its retry) answer 500 | Hook still returns `B` after the failed poll |
| telemetry-008 | parse-gate | `parseSnapshot(null)` and `parseSnapshot("")` (from `local-cache.test.ts`) | Both return `null` |
| telemetry-009 | parse-gate | `parseSnapshot("{not json")` (from `local-cache.test.ts`) | Returns `null` |
| telemetry-010 | parse-gate | `parseSnapshot` of `JSON.stringify(null)`, `{ generatedAt: "x" }`, `{ generatedAt: 1, errors: [], analytics: [] }`, `{ generatedAt: "x", errors: "nope", analytics: [] }` (from `local-cache.test.ts`) | Each returns `null` |
| telemetry-011 | parse-projection, snapshot-shape | `parseSnapshot(JSON.stringify(snap))` for a snapshot with one error and one analytics metric (from `local-cache.test.ts`) | Result deep-equals `snap` |
| telemetry-012 | parse-projection | `parseSnapshot('{"generatedAt":"t","errors":[],"analytics":[],"extra":1}')` | Returns `{ generatedAt: "t", errors: [], analytics: [] }` with no `extra` key |
| telemetry-013 | cache-save-best-effort | `localStorage.setItem` throws (quota exceeded); source resolves `B` | No exception reaches the component; the hook returns `B` |
| telemetry-014 | cache-load-parse | `localStorage.getItem` throws; source never resolves | Hook returns the empty snapshot after mount |
| telemetry-015 | shared-poll, per-instance-cache-io | Two components call the hook under one `QueryClient`; source resolves `B` | One source fetch; both return `B`; `localStorage.setItem` is called twice with the same value |
| telemetry-016 | poll-cadence | Hook mounted, document visible, first fetch resolved; advance timers 60000 ms | A second source fetch occurs |
| telemetry-017 | empty-snapshot | Call `emptySnapshot()` twice | Two distinct objects, each deep-equal to `{ generatedAt: "", errors: [], analytics: [] }` |

## Edge Cases

- **No cache, source failing**: The hook MUST return `emptySnapshot()` indefinitely, with no error exposed; consumers render a healthy/empty state (MUST, as implemented; see the open question on telemetry-failure-signal).
- **Corrupt stored value**: Invalid JSON, a wrong-shape object, or a JSON `null` under `adh-telemetry-v1` MUST load as `null`, so the hook falls back to `emptySnapshot()` until the source answers (MUST).
- **Stored arrays with malformed elements**: `parseSnapshot` checks only that `errors` and `analytics` are arrays; malformed elements pass through to consumers unchanged (MUST, as implemented).
- **Malformed 2xx body from the source**: The body is cast, not validated; a body missing `errors` returns an object whose `errors` is `undefined`, which consumers that call `errors.reduce` throw on during render. The same body is saved to the cache, but `parseSnapshot` rejects it on the next load, so a reload recovers to empty. The body shape is owned by the backend `/telemetry` route (MUST, as implemented).
- **Non-JSON 2xx body**: `r.json()` rejects, the query retries once, then enters its error state; the hook falls back to data, cache or empty per precedence (MUST).
- **Storage unavailable** (private mode, disabled storage, quota): `load` returns `null` and `save` is a silent no-op; the hook still returns live data (MUST).
- **Server render**: No effect runs, so the hook returns `emptySnapshot()` unless the query already has data in the server's `QueryClient`; `localCache` also guards `typeof window === "undefined"` (MUST).
- **Source outage after a success in the same session**: react-query retains the last data, so the hook returns that live snapshot, not the cached one; the cache only covers the gap before the first success in a `QueryClient` (for example after a reload) (MUST).
- **Hidden tab**: The 60-second poll pauses while the document is hidden and a focus event triggers a refetch on return (MUST, via react-query defaults).
- **Concurrent callers**: JavaScript is single-threaded; concurrent mounts share one query via deduplication, and each instance's cache writes store the same value, so there is no interleaving to order (MUST).
- **Unreachable server or network timeout**: `api.fetch` rejects (or hangs until the browser gives up); the hook adds no timeout, the query retries once, and the fallback precedence applies (MUST).
- **Unmount mid-fetch**: The request is not aborted; any result lands in the shared query cache for other observers (MUST, as implemented).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `TELEMETRY_POLL_MS` | `number` (exported constant) | `60000` | Poll interval passed as `refetchInterval`. |
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()`: the `StatusApiProvider` client, else the same-origin default with base `/api` | Transport the source reads through. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns the shared `["telemetry"]` cache, `staleTime`, `retryDelay` and background-refetch defaults; the hook overrides only `refetchInterval`, `refetchOnWindowFocus` and `retry`. |
| `source` (composition root) | `TelemetrySource` | `liveSource` (`GET /telemetry`) | Chosen in `telemetry/client.ts` from `SOURCES = { live, turso }`; `tursoSource` reads `/errors` and `/analytics` in parallel and stamps `generatedAt` with the client's current time. |
| `cache` (composition root) | `SnapshotCache` | `localCache` | `localStorage` adapter chosen in `telemetry/client.ts`. |
| Cache key | `string` | `adh-telemetry-v1` | `localStorage` key used by `localCache`. |

## Deep Linking

Not applicable: the hook is a data source with no route or URL of its own; its only URL is the backend API path the source fetches.

## Localization

Not applicable: the hook produces no user-facing strings; the only text it creates is the developer error message `telemetry <status>`, which the hook discards rather than surfacing.

## Accessibility Options

Not applicable: the hook renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; the live-versus-Turso choice is a code constant in `telemetry/client.ts`, not a runtime flag.

## Analytics

Not applicable: the hook reads analytics KPIs for display but emits no analytics events itself.

## Privacy

- **Data collected**: Error-issue summaries (project, title, culprit, level, counts, first/last seen, permalink) and aggregate analytics KPIs; `ErrorDTO.userCount` is a count, and the analytics are described in `telemetry/types.ts` as "anonymous + aggregate". Error titles and culprits are application error text and can contain whatever the reporting app put in them.
- **Storage**: The latest snapshot is stored unencrypted in the browser's `localStorage` under `adh-telemetry-v1`, and in memory in the react-query cache.
- **Transmission**: The hook sends one `GET /telemetry` through `StatusApiClient` per poll; it sends no telemetry data back out.
- **Retention**: The stored snapshot has no expiry; it is replaced on each successful poll and persists until overwritten or until the user clears site data.

## Logging

Not applicable: the source contains no log calls; `localCache` swallows storage errors silently and query failures are discarded by the hook.

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor final class TelemetryStore` holding `snapshot: TelemetrySnapshot` (a `Codable`, `Sendable` struct). On init, decode the cached value from `UserDefaults` (or a file in Application Support) with `JSONDecoder`, gated like `parseSnapshot`; then run a polling `Task` that `await`s `source.get(api)` via `URLSession.data(from:)`, retries once, and sleeps `60` seconds with `Task.sleep(for:)`. Refresh on `scenePhase == .active` to mirror focus refetch, and cancel the task when the scene backgrounds. Share one store through the environment to replace react-query's shared query. SwiftUI has no SSR, so "hydrate after mount" reduces to loading the cache before the first fetch.
- **Compose**: A `ViewModel` exposing `StateFlow<TelemetrySnapshot>`; seed it from a DataStore or `SharedPreferences` JSON blob parsed with `kotlinx.serialization` (return `null` on any `SerializationException`), then poll with a `while (isActive) { runCatching { fetch() }; delay(60_000) }` loop in `viewModelScope`, retrying once per poll. Use `repeatOnLifecycle(Lifecycle.State.STARTED)` to pause the poll while backgrounded, the analogue of react-query's hidden-tab pause.
- **React/Web**: Source platform. `hooks/use-telemetry.ts` uses `@tanstack/react-query` v5 `useQuery` plus two `useEffect`s (cache hydration on mount, cache save on data change). It depends on `telemetry/client.ts` (composition root), `telemetry/ports.ts` (`SnapshotCache`, `TelemetrySource`), `telemetry/types.ts` (DTOs and `emptySnapshot`), `telemetry/sources/live.ts`, `telemetry/stores/local-cache.ts` (tested by `local-cache.test.ts`) and `api/client.ts` (`useStatusApi`). The hook itself has no direct test; `TelemetrySections.dom.test.tsx` mocks it.
- **AppKit / UIKit**: Same `TelemetryStore` as SwiftUI, observed via Observation tracking or Combine `@Published`; refresh on `NSApplication.didBecomeActiveNotification` / `UIApplication.didBecomeActiveNotification` to mirror focus refetch.
- **WinUI 3**: Implement a singleton `TelemetryService : INotifyPropertyChanged` registered in the DI container (the stand-in for the shared `QueryClient` query), exposing `Snapshot` as an immutable `record TelemetrySnapshot(string GeneratedAt, IReadOnlyList<ErrorDto> Errors, IReadOnlyList<AnalyticsMetricDto> Analytics)`. On start, read the cached JSON from `Windows.Storage.ApplicationData.Current.LocalSettings.Values["adh-telemetry-v1"]` (or a file in `LocalFolder` if the snapshot can exceed the 8 KB per-setting limit) and parse it with `System.Text.Json` `JsonSerializer.Deserialize` inside `try/catch (JsonException)`, rejecting a null `GeneratedAt` or null arrays to match `parseSnapshot`. Poll with a `PeriodicTimer(TimeSpan.FromSeconds(60))` loop in an `async Task`, calling a shared `HttpClient.GetAsync("…/telemetry")`, throwing on `!response.IsSuccessStatusCode`, and retrying once; on success set `Snapshot` and write the cache inside a `try/catch` that swallows storage failures. Marshal the property change to the UI thread with `DispatcherQueue.TryEnqueue`. Refetch on `Window.Activated` to mirror `refetchOnWindowFocus`, and pause the timer when the window is minimized if the hidden-tab pause is wanted. Unlike react-query, nothing deduplicates concurrent loads or keeps data on error automatically: keep one in-flight `Task` and leave `Snapshot` unchanged on failure. There is no SSR, so hydration can run before the first fetch.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-telemetry.ts` |

## Design Decisions

**Decision**: Hydrate from the cache in a post-mount effect, not during render or as react-query `initialData`.
**Rationale**: The source comment says this keeps "SSR and the first client paint" identical; reading `localStorage` during render would produce a hydration mismatch. The cost is one render of the empty snapshot before the cached one appears.
**Approved**: pending

**Decision**: Return a plain snapshot with fixed precedence live, then cached, then empty.
**Rationale**: "Live data wins; the cached snapshot covers the gap before the first poll lands (and a brief source outage); empty until either arrives." Consumers never handle `undefined`. The trade-off, recorded as the open question on telemetry-failure-signal, is that no error or staleness signal reaches consumers. In practice react-query retains the last data on error, so within one session an outage is covered by retained query data rather than by the cache; the cache covers the gap after a reload.
**Approved**: pending

**Decision**: Depend only on the `TelemetrySource` and `SnapshotCache` ports, composed in `telemetry/client.ts`.
**Rationale**: The source says swapping the backend (live poll versus Turso) is a one-line change in the composition root that "leaves it untouched"; `ports.ts` states that "nothing above the port moves".
**Approved**: pending

**Decision**: Treat the `localStorage` write as best-effort and the stored value as untrusted.
**Rationale**: `local-cache.ts` says "the in-memory query result is the live truth", so a failed write is silently ignored; `parseSnapshot` is a "defensive, shape-gated parse" because a stored value may be stale, from an older build, or corrupt.
**Approved**: pending

**Decision**: Poll every 60 seconds with one retry and focus refetch.
**Rationale**: `TELEMETRY_POLL_MS = 60_000` with `retry: 1` bounds each poll to at most two requests to `/telemetry`, which on the live path makes the server poll GlitchTip and PostHog; the source records no further rationale for the specific values.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | best-practices |
| [caching-strategy](agenticdevelopercookbook://compliance/performance#caching-strategy) | passed | performance |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | partial | reliability |
| [secure-data-storage](agenticdevelopercookbook://compliance/privacy-and-data#secure-data-storage) | partial | privacy-and-data |

The hook depends only on the source and cache ports; transport, persistence and backend choice live in separate adapters composed in `telemetry/client.ts`. `parseSnapshot` has direct unit tests in `local-cache.test.ts` (null, empty, malformed JSON, wrong shapes, round trip), but the hook itself, `liveSource` and the `localCache` I/O wrapper have none, hence partial. Error handling fails the check because the hook discards the query error entirely: a source that never answers looks like an empty, healthy snapshot, and storage failures are swallowed without a log. Caching is deliberate: one shared react-query key, a 60-second poll, and a persisted last-known snapshot for instant paint. Degradation is partial because stale or empty data is served during an outage without any staleness indicator. Storage is partial because error titles, culprits and permalinks sit unencrypted in `localStorage` with no expiry.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
