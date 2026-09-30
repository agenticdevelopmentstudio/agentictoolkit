<!-- leaf: implement-status-server/fetchers--part-2 · source: status-server-fetchers.md -->

# Status Server Fetchers — continued (part 2)

## Privacy

- **Data collected**: `glitchtip.ts` reads GlitchTip issue metadata (title, culprit, level, count, user count, timestamps, a permalink, and a project slug/name) — application error data, not end-user personal data. `posthog.ts` reads only aggregate, anonymous counts (`count()`/`count(DISTINCT person_id)` over `$pageview` events); per the file's own comment, this is a deliberate privacy-first design — "no person data ever leaves PostHog into here." Both files also hold their provider's bearer credential (`GLITCHTIP_API_TOKEN`, `POSTHOG_API_KEY`) for the duration of one `fetch()` call.
- **Storage**: neither file writes to persistent storage; both are PURE with respect to storage, per each file's own header comment. Persisting a fetch's results is `collect.ts`'s and the `Store<T>` port's job, external to these two files.
- **Transmission**: every outbound call in both files sends its provider credential as an `Authorization: Bearer` header, never in a query string or request body; the transport scheme (`http://` vs `https://`) is whatever the caller-supplied `GLITCHTIP_URL`/`POSTHOG_HOST` value specifies — neither file validates or enforces `https://`.
- **Retention**: neither file caches, persists, or retains a credential or a fetched item beyond the lifetime of one `fetch()` call; there is no in-memory cache of any kind in either file.

## Platform Notes

- **React/Web** (source platform): both files live under `packages/web/packages/status-server/src/telemetry/fetchers/`, on Node's global `fetch`, `AbortController`, and `setTimeout`/`clearTimeout` — no framework dependency beyond the runtime globals. `../ports` and `../types` (this package's own modules) supply the `Fetcher`/`FetchResult` contract and `ErrorDTO`/`AnalyticsMetricDTO` shapes both files implement and produce.
- **SwiftUI**: a port models `GlitchtipEnv`/`PosthogEnv` as small `Sendable` structs of optional `String`s, `mapIssues`/`hogql`'s pure mapping as a free function over `Codable` structs mirroring `ErrorDTO`/`AnalyticsMetricDTO`, and the bounded single-attempt fetch via `URLSession` with `URLRequest.timeoutInterval` (or a `Task` wrapped in `withTimeout`/`Task.sleep` racing) in place of `AbortController`; the sequential PostHog batch is a plain `for` loop over `await` calls, matching the source's deliberate non-concurrent dispatch.
- **Compose**: the same structural mapping as SwiftUI — Kotlin `data class`es for the env/DTO shapes, a coroutine `withTimeout(...)` block per request in place of `AbortController`, and a sequential `for` loop with `suspend` calls (not `async`/`awaitAll`) for the PostHog batch.
- **AppKit/UIKit**: identical mapping to SwiftUI's; `URLSession`'s `dataTask`/`data(for:)` with `URLSessionConfiguration.timeoutIntervalForRequest` is the direct analogue of each file's bounded, non-retried single attempt.
- **WinUI 3**: a .NET port uses `HttpClient` with a per-call `CancellationTokenSource` (timed via `CancelAfter`) as the `AbortController`/`AbortSignal.timeout` analogue — one `CancellationTokenSource` for the GlitchTip request, and a fresh one per query inside the PostHog batch; `System.Text.Json` replaces `res.json()`/`JSON.stringify` for both the GlitchTip issues array and the HogQL request/response bodies; the four `METRICS` entries become a fixed, non-configurable `IReadOnlyList<MetricSpec>` record array; the PostHog batch is a plain sequential `foreach` with `await` (never `Task.WhenAll`), matching **posthog-sequential-execution**; and `GlitchtipEnv`/`PosthogEnv` map to small `record` types with nullable `string` properties, since neither carries behavior. No `Windows.Storage` or `ObservableCollection`/`INotifyPropertyChanged` counterpart applies — neither file persists anything or exposes an observable collection.

## Design Decisions

- **Decision**: `glitchtipFetcher` makes exactly one bounded attempt per poll and never retries a failed or timed-out request.
  **Rationale**: the source comment states this directly — the issues query already fans out over source-maps and grouping and can occasionally stall, so a retry on a stalled provider would double that cycle's wait; under sustained degradation, stacked retries blew the scheduler's cycle budget and triggered container restarts.
  **Approved**: pending
- **Decision**: a GlitchTip response of exactly `PAGE_LIMIT` (100) issues is always treated as truncated (`complete: false`), even though 100 could coincidentally be the provider's true total.
  **Rationale**: the source comment explains the asymmetry directly — a reconciling store reads "absent from this poll" as "resolved upstream," which is sound for a whole answer and catastrophic for a truncated page (an issue past the page edge would be resolved on one poll and reopened on the next, flapping the board forever); erring toward "may not have seen everything" costs a delayed resolve, while erring the other way costs a false all-clear during a live incident.
  **Approved**: pending
- **Decision**: the four PostHog HogQL queries are issued sequentially, never concurrently.
  **Rationale**: stated directly in the source comment — the HogQL query API returns HTTP 503 under concurrent load from this same client, so sequential dispatch is a gentleness constraint on the provider, not merely a stylistic choice.
  **Approved**: pending
- **Decision**: a PostHog batch that fails partway through keeps the metrics it already answered rather than discarding the whole batch; only an all-failed batch resolves `ok: false`.
  **Rationale**: the source comment states this directly — persisting whatever succeeded means a total outage is the only case that returns `ok: false`, so a partial provider degradation never overwrites already-good trend data (in the external `Store`) with an empty set.
  **Approved**: pending
