<!-- leaf: implement-status-web-hooks/use-telemetry · source: status-web-hooks-use-telemetry.md -->

**Rules** (cite as `implement-status-web-hooks/use-telemetry#<slug>`):

- `poll-interval-constant` MUST
- `hook-signature` MUST
- `client-only` MUST
- `snapshot-shape` MUST
- `error-dto-shape` MUST
- `analytics-dto-shape` MUST
- `empty-snapshot` MUST
- `query-key` MUST
- `query-fn` MUST
- `poll-cadence` MUST
- `refetch-on-focus` MUST
- `single-retry` MUST
- `live-request` MUST
- `live-http-error` MUST
- `live-body-cast` MUST
- `hydrate-after-mount` MUST
- `first-render-empty` MUST
- `cache-load-parse` MUST
- `parse-gate` MUST
- `parse-projection` MUST
- `persist-on-data` MUST
- `cache-save-format` MUST
- `cache-save-best-effort` MUST
- `no-save-on-failure` MUST
- `live-wins` MUST
- `cache-fallback` MUST
- `empty-fallback` MUST
- `data-retained-on-error` MUST
- `shared-poll` MUST
- `per-instance-cache-io` MUST
- `side-effects` MUST
- `no-timeout-no-cancel` MUST

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
- **live-body-cast**: A 2xx response body MUST be parsed as JSON and returned as a `TelemetrySnapshot` by cast, with no shape validation; a body that is not JSON rejects the query with the JSON parse error. The response shape is owned by the backend `/telemetry` route (see Status Server Telemetry).

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `TELEMETRY_POLL_MS` | `number` (exported constant) | `60000` | Poll interval passed as `refetchInterval`. |
| `StatusApiClient` (injected) | `StatusApiClient` | from `useStatusApi()`: the `StatusApiProvider` client, else the same-origin default with base `/api` | Transport the source reads through. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | Owns the shared `["telemetry"]` cache, `staleTime`, `retryDelay` and background-refetch defaults; the hook overrides only `refetchInterval`, `refetchOnWindowFocus` and `retry`. |
| `source` (composition root) | `TelemetrySource` | `liveSource` (`GET /telemetry`) | Chosen in `telemetry/client.ts` from `SOURCES = { live, turso }`; `tursoSource` reads `/errors` and `/analytics` in parallel and stamps `generatedAt` with the client's current time. |
| `cache` (composition root) | `SnapshotCache` | `localCache` | `localStorage` adapter chosen in `telemetry/client.ts`. |
| Cache key | `string` | `adh-telemetry-v1` | `localStorage` key used by `localCache`. |

## Privacy

- **Data collected**: Error-issue summaries (project, title, culprit, level, counts, first/last seen, permalink) and aggregate analytics KPIs; `ErrorDTO.userCount` is a count, and the analytics are described in `telemetry/types.ts` as "anonymous + aggregate". Error titles and culprits are application error text and can contain whatever the reporting app put in them.
- **Storage**: The latest snapshot is stored unencrypted in the browser's `localStorage` under `adh-telemetry-v1`, and in memory in the react-query cache.
- **Transmission**: The hook sends one `GET /telemetry` through `StatusApiClient` per poll; it sends no telemetry data back out.
- **Retention**: The stored snapshot has no expiry; it is replaced on each successful poll and persists until overwritten or until the user clears site data.

