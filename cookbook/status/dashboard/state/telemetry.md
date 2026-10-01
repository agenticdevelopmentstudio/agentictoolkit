---
id: 9ff57831-bdf9-47ad-b009-bcc1de59d5f4
title: Telemetry State
domain: agentictoolkit://cookbook/status/dashboard/state/telemetry
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that polls the configured telemetry source every 60 s, persists
  each snapshot to a persistent cache, and returns live, cached or empty data.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/service/telemetry
references: []
approved-by: ''
approved-date: ''
---

# Telemetry State

## Overview

The telemetry state is the status dashboard's single read of production telemetry: grouped error issues (GlitchTip) and headline analytics KPIs (PostHog), delivered as one snapshot object (`{ generatedAt, errors, analytics }`). The dashboard's error and traffic cards both read it.

The state knows only two ports, both composed in one composition root:

- the source — where a fresh snapshot comes from. Today it is the live source, which does `GET /telemetry` through the caller's injected API client. An alternative source backed by Turso is wired as the alternative and is selected by changing one line in the composition root.
- the cache — where the browser keeps the last snapshot. Today it is the local cache, a persistent-storage adapter under the key `adh-telemetry-v1`.

The contract: poll the source, persist each snapshot to the cache, hydrate from the cache after mount rather than during render (so server render and first client paint match), and let live data win over the cached snapshot, which wins over an empty snapshot. The state never names GlitchTip, PostHog or Turso in its own logic, so swapping the backend leaves it untouched.

## Behavioral Requirements

### Exports and signature

- **poll-interval-constant**: The module MUST export `TELEMETRY_POLL_MS` equal to `60000` (60 seconds).
- **hook-signature**: The state MUST take no arguments and MUST return a snapshot object, never `undefined` or `null`.

### Data shape

- **snapshot-shape**: A snapshot MUST carry a `generatedAt` ISO timestamp string, a list of error entries (`errors`) and a list of analytics metric entries (`analytics`).
- **error-dto-shape**: Each error entry MUST carry `id`, `issueKey`, `project` and `title` (strings), `culprit`, `level`, `firstSeen`, `lastSeen` and `permalink` (string or `null`), and `count` and `userCount` (numbers).
- **analytics-dto-shape**: Each analytics metric entry MUST carry `metric` (for example `pageviews` or `visitors`), `window` (for example `24h` or `7d`), `scope` (`all` or a site slug), a numeric `value` and an ISO `capturedAt` string.
- **empty-snapshot**: Constructing an empty snapshot MUST return a new object `{ generatedAt: "", errors: [], analytics: [] }` on every call.

### Query configuration

- **query-key**: The state MUST read through a single shared read keyed `telemetry`, so every caller under one shared cache shares one cached snapshot and one poll.
- **query-fn**: The read MUST call the source's fetch operation with the injected API client (the context client, or the same-origin default whose base is `/api`).
- **poll-cadence**: The read MUST refetch every `TELEMETRY_POLL_MS` (60000 ms) while observed; the poll pauses by default while the document is hidden, since no override is set to keep it running in the background.
- **refetch-on-focus**: The read MUST refetch when the application regains focus, subject to the host cache's staleness setting, which the state does not set.
- **single-retry**: A failed fetch MUST be retried exactly once before the read enters its error state; this per-read setting overrides any retry default on the host cache. The delay before that retry is the platform's default retry delay, which the state does not set.

### Live source

This is the source variant currently wired in the composition root; an alternative backend is wired by changing one line there.

- **live-request**: The live source's read MUST issue one request to `/telemetry` with no request options (a `GET` to `<basePath>/telemetry`).
- **live-http-error**: A non-2xx response MUST make the live source's read reject with an error whose message is `telemetry <status>` (for example `telemetry 502`).
- **live-body-cast**: A 2xx response body MUST be parsed as JSON and returned as a snapshot object by cast, with no shape validation; a body that is not JSON rejects the read with the JSON parse error. The response shape is owned by the backend `/telemetry` route (see [Status Server Telemetry](agentictoolkit://cookbook/status/service/telemetry)).

### Cache hydration

- **hydrate-after-mount**: The state MUST NOT read the cache during render; it MUST load from the cache exactly once per state instance, after the first mount.
- **first-render-empty**: On the first render of a state instance whose read has no data yet, the state MUST return the empty snapshot, so server-rendered output and the first client paint are identical.
- **cache-load-parse**: Loading from the cache MUST return the parsed value of the stored entry under the key `adh-telemetry-v1`, or `null` when the storage environment is unavailable or reading it throws.
- **parse-gate**: Parsing a stored value MUST return `null` when the raw value is `null` or empty, when it is not valid JSON, when it parses to `null`, when `generatedAt` is not a string, or when `errors` or `analytics` is not an array.
- **parse-projection**: When the gate passes, parsing MUST return a new object containing only `generatedAt`, `errors` and `analytics`, dropping any other top-level keys; array elements are not validated.

### Cache persistence

- **persist-on-data**: Whenever the read's data reference changes to a truthy value, each mounted state instance MUST save that value to the cache once.
- **cache-save-format**: Saving to the cache MUST write the snapshot as JSON under the key `adh-telemetry-v1`, replacing any previous value.
- **cache-save-best-effort**: Saving to the cache MUST do nothing when the storage environment is unavailable, and MUST swallow any exception the write throws; this is best-effort — the in-memory read result is the live truth.
- **no-save-on-failure**: A failed read MUST NOT write to or clear the cache; the last successful snapshot stays stored.

### Return precedence

- **live-wins**: When the read has data, the state MUST return that data, regardless of the cached snapshot.
- **cache-fallback**: When the read has no data and the cache load produced a snapshot, the state MUST return that cached snapshot.
- **empty-fallback**: When the read has no data and the cache load produced `null` (or has not run yet), the state MUST return the empty snapshot.
- **data-retained-on-error**: After at least one successful fetch in the shared cache, a later failed poll MUST leave the previous data in place (the platform keeps the last data on error), so the state keeps returning the last live snapshot rather than the cached one.
- **telemetry-failure-signal**: NEEDS REVIEW: Not implemented in source. The state returns only the snapshot and discards the read's error and loading/fetching flags, so a source that has never answered is indistinguishable from "zero errors, zero traffic" (the empty snapshot), and a cached or retained snapshot carries no staleness flag beyond its own `generatedAt`; some consumer tests mock the state with `stale` and `offline` fields that the state never returns. Settling this needs the owner to decide whether the state's contract should expose an error or staleness signal.

### Concurrency and side effects

- **shared-poll**: Multiple consumers using this state under one shared cache MUST share one in-flight fetch and one interval; additional callers MUST NOT add fetches beyond the cache's deduplication.
- **per-instance-cache-io**: Each mounted state instance MUST perform its own cache load on mount and its own cache save per new data value, so two mounted consumers read the cache twice and write the same snapshot twice.
- **side-effects**: The state's only side effects MUST be the source's network reads (one `GET /telemetry` per poll today) and the cache reads and writes under the key `adh-telemetry-v1`; it MUST NOT log, emit analytics, or mutate server state.
- **no-timeout-no-cancel**: The state MUST NOT impose its own request timeout or cancellation; the live source passes no cancellation signal to its request, so an in-flight request is not aborted by the platform's cancellation mechanism.

## Appearance

Not applicable — this is a data state, not a visual component.

## States

Not applicable — this is a data state, not a visual component.

## Accessibility

Not applicable — this is a data state, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| telemetry-001 | poll-interval-constant | Read the exported constant | `TELEMETRY_POLL_MS` is `60000` |
| telemetry-002 | first-render-empty, empty-fallback, hook-signature | Empty cache; source never resolves; render the state once | Returned value deep-equals `{ generatedAt: "", errors: [], analytics: [] }` |
| telemetry-003 | hydrate-after-mount, cache-fallback | The cache holds a valid snapshot `S` under `adh-telemetry-v1`; source never resolves | First render returns the empty snapshot; after the post-mount step runs, the state returns a value deep-equal to `S` |
| telemetry-004 | live-wins, persist-on-data, cache-save-format | Cache holds snapshot `A`; source resolves snapshot `B` | The state returns `B`; the cache entry under `adh-telemetry-v1` equals the JSON of `B` |
| telemetry-005 | live-request, query-fn | An overriding client configured with base path `/x`, and a recording transport | Exactly one request to `/x/telemetry` per read, with no extra request options |
| telemetry-006 | live-http-error, single-retry, no-save-on-failure | The source's transport answers 502 every time; cache holds snapshot `A` | The transport is called twice (initial plus one retry); the read's error message is `telemetry 502`; the state returns `A`; the cache still holds `A` |
| telemetry-007 | data-retained-on-error | First poll resolves `B`; next poll (and its retry) answer 500 | The state still returns `B` after the failed poll |
| telemetry-008 | parse-gate | Parsing `null` and parsing an empty string | Both return `null` |
| telemetry-009 | parse-gate | Parsing malformed JSON (`{not json`) | Returns `null` |
| telemetry-010 | parse-gate | Parsing the JSON text of `null`, `{ generatedAt: "x" }`, `{ generatedAt: 1, errors: [], analytics: [] }`, and `{ generatedAt: "x", errors: "nope", analytics: [] }` | Each returns `null` |
| telemetry-011 | parse-projection, snapshot-shape | Parsing the JSON text of a snapshot with one error and one analytics metric | Result deep-equals the original snapshot |
| telemetry-012 | parse-projection | Parsing the JSON text `{"generatedAt":"t","errors":[],"analytics":[],"extra":1}` | Returns `{ generatedAt: "t", errors: [], analytics: [] }` with no `extra` key |
| telemetry-013 | cache-save-best-effort | The cache write throws (quota exceeded); source resolves `B` | No exception reaches the consumer; the state returns `B` |
| telemetry-014 | cache-load-parse | The cache read throws; source never resolves | The state returns the empty snapshot after mount |
| telemetry-015 | shared-poll, per-instance-cache-io | Two consumers use this state under one shared cache; source resolves `B` | One source fetch; both return `B`; the cache write is called twice with the same value |
| telemetry-016 | poll-cadence | State mounted, document visible, first fetch resolved; advance time 60000 ms | A second source fetch occurs |
| telemetry-017 | empty-snapshot | Construct the empty snapshot twice | Two distinct objects, each deep-equal to `{ generatedAt: "", errors: [], analytics: [] }` |

## Edge Cases

- **No cache, source failing**: The state MUST return the empty snapshot indefinitely, with no error exposed; consumers render a healthy/empty state (MUST, as implemented; see the open question on telemetry-failure-signal).
- **Corrupt stored value**: Invalid JSON, a wrong-shape object, or a JSON `null` under `adh-telemetry-v1` MUST load as `null`, so the state falls back to the empty snapshot until the source answers (MUST).
- **Stored arrays with malformed elements**: Parsing checks only that `errors` and `analytics` are arrays; malformed elements pass through to consumers unchanged (MUST, as implemented).
- **Malformed 2xx body from the source**: The body is cast, not validated; a body missing `errors` returns an object whose `errors` is `undefined`, which consumers that iterate over `errors` throw on during render. The same body is saved to the cache, but parsing rejects it on the next load, so a reload recovers to empty. The body shape is owned by the backend `/telemetry` route (MUST, as implemented).
- **Non-JSON 2xx body**: Parsing the body as JSON rejects, the read retries once, then enters its error state; the state falls back to data, cache or empty per precedence (MUST).
- **Storage unavailable** (private mode, disabled storage, quota): loading returns `null` and saving is a silent no-op; the state still returns live data (MUST).
- **Server render**: No post-mount step runs, so the state returns the empty snapshot unless the read already has data from the server render; the cache adapter also guards against a missing storage environment (MUST).
- **Source outage after a success in the same session**: the platform retains the last data, so the state returns that live snapshot, not the cached one; the cache only covers the gap before the first success in a session (for example after a reload) (MUST).
- **Hidden tab**: The 60-second poll pauses while the document is hidden and a focus event triggers a refetch on return (MUST, via the platform's defaults).
- **Concurrent callers**: Concurrent mounts share one read via deduplication, and each instance's cache writes store the same value, so there is no interleaving to order (MUST).
- **Unreachable server or network timeout**: The transport rejects (or hangs until the platform's network stack gives up); the state adds no timeout, the read retries once, and the fallback precedence applies (MUST).
- **Unmount mid-fetch**: The request is not aborted; any result lands in the shared cache for other observers (MUST, as implemented).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Poll interval | number (ms), exported constant `TELEMETRY_POLL_MS` | `60000` | Interval the read refetches on while observed. |
| Injected API client | API client | from dependency injection: an overriding client, else the same-origin default with base `/api` | Transport the source reads through. |
| Shared cache (injected) | cache | host cache provider | Owns the shared `telemetry` cache entry, staleness, retry delay and background-refetch defaults; the state overrides only the poll interval, refetch-on-focus and the retry count. |
| Source (composition root) | source | the live source (`GET /telemetry`) | Chosen in the composition root from the available sources (live, or an alternative backend); the alternative reads errors and analytics in parallel and stamps `generatedAt` with the client's current time. |
| Cache (composition root) | cache | the local cache | The persistent-storage adapter chosen in the composition root. |
| Cache key | string | `adh-telemetry-v1` | The persistent-storage key used by the cache adapter. |

## Deep Linking

Not applicable: the state is a data source with no route or URL of its own; its only URL is the backend API path the source fetches.

## Localization

Not applicable: the state produces no user-facing strings; the only text it creates is the developer error message `telemetry <status>`, which the state discards rather than surfacing.

## Accessibility Options

Not applicable: the state renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag; the live-versus-alternative-backend choice is a fixed constant in the composition root, not a runtime flag.

## Analytics

Not applicable: the state reads analytics KPIs for display but emits no analytics events itself.

## Privacy

- **Data collected**: Error-issue summaries (project, title, culprit, level, counts, first/last seen, permalink) and aggregate analytics KPIs; the error entry's `userCount` is a count, and the analytics are anonymous and aggregate. Error titles and culprits are application error text and can contain whatever the reporting app put in them.
- **Storage**: The latest snapshot is stored unencrypted in persistent browser storage under the key `adh-telemetry-v1`, and in memory in the shared cache.
- **Transmission**: The state sends one `GET /telemetry` through the injected API client per poll; it sends no telemetry data back out.
- **Retention**: The stored snapshot has no expiry; it is replaced on each successful poll and persists until overwritten or until the user clears site data.

## Logging

Not applicable: the source contains no log calls; the cache adapter swallows storage errors silently and read failures are discarded by the state.

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor final class TelemetryStore` holding `snapshot: TelemetrySnapshot` (a `Codable`, `Sendable` struct). On init, decode the cached value from `UserDefaults` (or a file in Application Support) with `JSONDecoder`, gated like `parseSnapshot`; then run a polling `Task` that `await`s `source.get(api)` via `URLSession.data(from:)`, retries once, and sleeps `60` seconds with `Task.sleep(for:)`. Refresh on `scenePhase == .active` to mirror focus refetch, and cancel the task when the scene backgrounds. Share one store through the environment to replace react-query's shared query. SwiftUI has no SSR, so "hydrate after mount" reduces to loading the cache before the first fetch.
- **Compose**: A `ViewModel` exposing `StateFlow<TelemetrySnapshot>`; seed it from a DataStore or `SharedPreferences` JSON blob parsed with `kotlinx.serialization` (return `null` on any `SerializationException`), then poll with a `while (isActive) { runCatching { fetch() }; delay(60_000) }` loop in `viewModelScope`, retrying once per poll. Use `repeatOnLifecycle(Lifecycle.State.STARTED)` to pause the poll while backgrounded, the analogue of react-query's hidden-tab pause.
- **React/Web**: Source platform. `hooks/use-telemetry.ts` uses `@tanstack/react-query` v5's `useQuery` plus two `useEffect`s (cache hydration on mount, cache save on data change), and must be marked `"use client"` because it uses React state, effects and the query cache. It depends on `telemetry/client.ts` (composition root), `telemetry/ports.ts` (`SnapshotCache`, `TelemetrySource`), `telemetry/types.ts` (DTOs and `emptySnapshot`), `telemetry/sources/live.ts`, `telemetry/stores/local-cache.ts` (tested by `local-cache.test.ts`) and `api/client.ts` (`useStatusApi`). The hook itself has no direct test; `TelemetrySections.dom.test.tsx` mocks it. Concurrent mounts dedupe trivially because JavaScript runs on a single thread.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
