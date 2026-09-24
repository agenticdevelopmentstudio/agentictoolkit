---
id: 8648272e-2da3-46fc-b9e8-5148dacdbcff
title: Status Server Fetchers
domain: agentictoolkit://recipes/status-server-fetchers
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Two Fetcher-port adapters (GlitchTip issues, PostHog HogQL analytics) feeding
  the status server's telemetry streams — env-gated no-op, one bounded fetch attempt,
  and DTO mapping.
platforms:
- typescript
- web
tags:
- telemetry
- glitchtip
- posthog
- fetcher
- server
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/telemetry/fetchers/glitchtip.ts (agentictoolkit)
- packages/web/packages/status-server/src/telemetry/fetchers/posthog.ts (agentictoolkit)
- packages/web/packages/status-server/test/telemetry-glitchtip-fetcher.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Fetchers

## Overview

Two files under `src/telemetry/fetchers/` — `glitchtip.ts` and `posthog.ts` — are the two provider adapters behind the status server's telemetry `Fetcher<T>` port (`../ports`, external to this recipe's two files but the contract both implement). `glitchtipFetcher` polls GlitchTip's Sentry-API-compatible organization-issues endpoint and maps grouped issues to `ErrorDTO`; `posthogFetcher` runs four fixed HogQL queries against PostHog's query API and maps the results to `AnalyticsMetricDTO` (both DTOs from `../types`, external). Each is built from a small `*Env` record naming its provider's credentials (`GlitchtipEnv`, `PosthogEnv`), no-ops with an empty successful result when those credentials are not all present, and otherwise performs one bounded, non-retried outbound HTTP round of calls before resolving a `FetchResult<T>`. Both files are PURE with respect to storage — they only fetch and map; persisting the result is `collect.ts`'s and the `Store<T>` port's job (external), and choosing which fetcher backs which stream is `server.ts`'s composition-root job (also external) — this recipe specifies only what these two adapter files themselves do.

## Behavioral Requirements

### GlitchTip Fetcher (glitchtip.ts)

- **unconfigured-no-op**: `glitchtipFetcher(env).fetch()` MUST resolve `{ ok: true, items: [] }` without issuing any network request when `env.GLITCHTIP_URL`, `env.GLITCHTIP_API_TOKEN`, or `env.GLITCHTIP_ORG` is missing.
- **issues-request-shape**: When all three are present, `fetch()` MUST issue exactly one `GET` request to `${GLITCHTIP_URL with trailing slashes stripped}/api/0/organizations/${GLITCHTIP_ORG}/issues/?query=is:unresolved&limit=${PAGE_LIMIT}` carrying header `Authorization: Bearer ${GLITCHTIP_API_TOKEN}`.
- **issues-request-timeout**: The request MUST be bounded by an `AbortController` whose signal aborts after `TIMEOUT_MS` (12,000ms), driven by `setTimeout`, and the timer MUST be cleared in a `finally` block regardless of outcome.
- **issues-no-retry**: `fetch()` MUST make exactly one request attempt per call; it MUST NOT retry a failed or timed-out attempt within the same call.
- **http-error-fails-poll**: When the response's `ok` is `false`, `fetch()` MUST resolve `{ ok: false, items: [] }` and MUST log a `console.warn` line naming the HTTP status, without throwing.
- **non-array-body-fails-poll**: When the parsed JSON body is not an `Array`, `fetch()` MUST resolve `{ ok: false, items: [] }` (never `ok: true`) and MUST log a `console.warn` line, regardless of whether the body looks like an error envelope, an HTML page, a `{results:[...]}` wrapper, or `null`.
- **thrown-fetch-fails-poll**: When the `fetch` call itself throws (a network failure or the timeout's abort), `fetch()` MUST catch it and resolve `{ ok: false, items: [] }`, logging a `console.warn` line that names the elapsed timeout when `err.name` is `"AbortError"` or `"TimeoutError"` (per `isTransient`), and the thrown error's message otherwise.
- **complete-flag-by-page-size**: On a successful array response, `fetch()` MUST set `FetchResult.complete` to `issues.length < PAGE_LIMIT` (100), so a page of exactly 100 issues is reported incomplete even if it happens to be GlitchTip's entire unresolved set.
- **issue-mapping-delegated**: On a successful array response, `fetch()` MUST set `FetchResult.items` to `mapIssues(issues)`, the module's pure, network-free mapping function.
- **issue-project-fallback**: `mapIssues` MUST resolve each item's `project` via `projectSlug`: the input `project`'s `slug`, else its `name`, else the literal string `"unknown"` — including when `project` itself is a string, `null`, or `undefined`.
- **issue-count-coercion**: `mapIssues` MUST coerce `count` to a `number`: pass a `number` through unchanged, `parseInt` a `string` (defaulting to `0` when parsing fails), and default `null`/`undefined` to `0`.
- **issue-timestamp-normalization**: `mapIssues` MUST normalize `firstSeen`/`lastSeen` via `normalizeIso`, returning `null` for a falsy input or a string that does not parse to a valid `Date`, and the `Date`'s own ISO string otherwise.
- **issue-field-defaults**: `mapIssues` MUST default `culprit`, `level`, and `permalink` to `null` and `userCount` to `0` when the corresponding input field is absent, and MUST copy `id`/`title` verbatim, setting `issueKey` to the same value as `id`.

### PostHog Fetcher (posthog.ts)

- **posthog-unconfigured-no-op**: `posthogFetcher(env).fetch()` MUST resolve `{ ok: true, items: [] }` without issuing any network request when `env.POSTHOG_HOST`, `env.POSTHOG_API_KEY`, or `env.POSTHOG_PROJECT_ID` is missing.
- **posthog-fixed-metric-set**: When all three are present, `fetch()` MUST query exactly the four fixed `METRICS` entries — `pageviews`/`24h` (1 day, non-distinct), `visitors`/`24h` (1 day, distinct), `pageviews`/`7d` (7 days, non-distinct), `visitors`/`7d` (7 days, distinct) — in that fixed order.
- **posthog-hogql-request-shape**: Each metric's query MUST `POST` to `${host with trailing slashes stripped}/api/projects/${projectId}/query/` with headers `Authorization: Bearer ${apiKey}` and `Content-Type: application/json`, body `{ query: { kind: "HogQLQuery", query } }`.
- **posthog-query-text**: The HogQL query text MUST select `count(DISTINCT person_id)` for a `distinct` metric and `count()` otherwise, `FROM events WHERE event = '$pageview' AND timestamp > now() - INTERVAL ${days} DAY`.
- **posthog-per-query-timeout**: Each of the four queries MUST carry its OWN `AbortController` timing out at `QUERY_TIMEOUT_MS` (10,000ms), independent of the other three queries' timeouts, with its timer cleared in a `finally` block.
- **posthog-sequential-execution**: The four metric queries MUST be issued sequentially, one at a time (never via `Promise.all` or other concurrent dispatch), so at most one HogQL request from this batch is outstanding at once.
- **posthog-short-circuit-on-first-failure**: When a query's `hogql` call resolves a non-null `error` (a non-`ok` HTTP response or a thrown request), `fetch()` MUST stop issuing any further metric queries in that batch, retaining only the items collected from queries that were answered before the failure.
- **posthog-single-warn-log**: When a batch stopped early on a failure, `fetch()` MUST log exactly one `console.warn` line naming the failure and the count of queries answered out of the fixed total (`${items.length}/${METRICS.length}`), never one line per failed query.
- **posthog-empty-result-fails**: `fetch()` MUST resolve `{ ok: false, items: [] }` when zero metrics were successfully queried in the batch, even when no query itself threw.
- **posthog-partial-result-succeeds**: `fetch()` MUST resolve `{ ok: true, items }` with whatever metrics succeeded before a later failure, whenever at least one metric was answered — a batch that answers some queries and fails on a later one MUST NOT discard the metrics it already has.
- **posthog-value-coercion**: `hogql` MUST resolve a `number` `results[0][0]` value unchanged and a `string` value via `Number(...)` (defaulting to `0` when the conversion is `NaN`), both with `error: null`.
- **posthog-captured-at-per-batch**: Every `AnalyticsMetricDTO` produced within one `fetch()` call MUST carry the identical `capturedAt` ISO string, captured once via `new Date().toISOString()` at the start of that call, never re-captured per metric.
- **posthog-scope-fixed**: Every `AnalyticsMetricDTO` this file emits MUST set `scope` to the literal string `"all"`.

### Shared Contract (ports.ts, referenced)

- **complete-flag-omission-vs-explicit**: Per `FetchResult.complete`'s documented default in `../ports` (unset defaults to `true`), `posthogFetcher` MUST leave `complete` unset on every result it returns, because its four-metric batch is never a partial page in the pagination sense; `glitchtipFetcher` MUST set `complete` explicitly on every successful result, per **complete-flag-by-page-size**, because its provider is cursor-paginated and a reconciling store depends on that signal being explicit rather than assumed.

## Appearance

Not applicable — this is a pair of telemetry Fetcher-port adapters, not a visual component.

## States

Not applicable — this is a pair of telemetry Fetcher-port adapters, not a visual component; their runtime branches (unconfigured, succeeded, failed, timed out) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a pair of telemetry Fetcher-port adapters, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| status-server-fetchers-001 | unconfigured-no-op | `glitchtipFetcher({}).fetch()` | Resolves `{ ok: true, items: [] }`; no `fetch` call is made — `telemetry-glitchtip-fetcher.test.ts` › "no-ops green when unconfigured" |
| status-server-fetchers-002 | issues-request-shape, issues-request-timeout | `glitchtipFetcher(ENV).fetch()` with a stubbed `fetch` returning `[]` | The single outbound URL is `https://glitchtip.example/api/0/organizations/adh/issues/?query=is:unresolved&limit=100` — `telemetry-glitchtip-fetcher.test.ts` › "asks for exactly one page of PAGE_LIMIT unresolved issues" |
| status-server-fetchers-003 | complete-flag-by-page-size, issue-mapping-delegated | Response body is an array of 2 issues (`a`, `b`) | `r.ok === true`, `r.complete === true`, `r.items.map(i => i.issueKey)` equals `["a","b"]` — `telemetry-glitchtip-fetcher.test.ts` › "reports a short page as COMPLETE" |
| status-server-fetchers-004 | complete-flag-by-page-size | Response body is an array of exactly 100 (`PAGE_LIMIT`) issues | `r.ok === true`, `r.complete === false` — `telemetry-glitchtip-fetcher.test.ts` › "reports a FULL page as incomplete" |
| status-server-fetchers-005 | non-array-body-fails-poll | Response body is `{ detail: "Authentication credentials were not provided." }` on a 200 | Resolves `{ ok: false, items: [] }` — `telemetry-glitchtip-fetcher.test.ts` › the non-array-body `it.each` (also covers a `{results:[...]}` wrapper, an HTML string, and `null`) |
| status-server-fetchers-006 | http-error-fails-poll | Response is not `ok`, status 502 | Resolves `{ ok: false, items: [] }` — `telemetry-glitchtip-fetcher.test.ts` › "treats an HTTP error as a failed poll" |
| status-server-fetchers-007 | thrown-fetch-fails-poll, issues-no-retry | Stubbed `fetch` throws `Error("ECONNREFUSED")` | Resolves `{ ok: false, items: [] }`; `fetch` is invoked exactly once — `telemetry-glitchtip-fetcher.test.ts` › "treats a thrown fetch as a failed poll" |
| status-server-fetchers-008 | issue-project-fallback | `mapIssues([{id:"1",title:"t",project:{slug:"adh",name:"ADH"}},{id:"2",title:"t",project:{name:"Some Team's App"}},{id:"3",title:"t",project:null}])` | Projects resolve to `"adh"`, `"Some Team's App"`, `"unknown"` respectively — `telemetry-glitchtip-fetcher.test.ts` › "falls back through slug, name, then unknown" |
| status-server-fetchers-009 | issue-count-coercion, issue-timestamp-normalization, issue-field-defaults | `mapIssues([{id:"1",title:"t",count:"42",firstSeen:"not-a-date",lastSeen:"2026-08-18T00:00:00Z"}])` | Resolves `{ count: 42, firstSeen: null, lastSeen: "2026-08-18T00:00:00.000Z" }` — `telemetry-glitchtip-fetcher.test.ts` › "parses GlitchTip's string counts and drops unparseable timestamps" |
| status-server-fetchers-010 | posthog-unconfigured-no-op | `posthogFetcher({}).fetch()` | Resolves `{ ok: true, items: [] }`; no `fetch` call is made |
| status-server-fetchers-011 | posthog-fixed-metric-set, posthog-query-text, posthog-hogql-request-shape | `posthogFetcher(ENV).fetch()` with every HogQL POST answering `{results:[[10]]}` | Exactly 4 POSTs to `https://ph.example/api/projects/42/query/`; the two `visitors` bodies contain `count(DISTINCT person_id)`, the two `pageviews` bodies contain `count()`; the two `7d` bodies contain `INTERVAL 7 DAY` |
| status-server-fetchers-012 | posthog-per-query-timeout | The first of four HogQL POSTs never resolves | That query's own `AbortController` fires at 10,000ms and resolves `{ value: null, error: "..." }` without the batch waiting past that one query's own timeout |
| status-server-fetchers-013 | posthog-sequential-execution | Four HogQL POSTs, each recording the order it was invoked | The second POST is not issued until the first has settled; no two POSTs are ever in flight together |
| status-server-fetchers-014 | posthog-short-circuit-on-first-failure, posthog-partial-result-succeeds, posthog-single-warn-log | The first 2 metric queries succeed with a value; the 3rd (`pageviews`/`7d`) responds HTTP 503 | Resolves `{ ok: true, items: <the 2 items from the first two metrics> }`; the 4th query (`visitors`/`7d`) is never issued; exactly one `console.warn` call, containing `"2/4 queries answered"` |
| status-server-fetchers-015 | posthog-empty-result-fails | All four metric queries respond HTTP 500 | Resolves `{ ok: false, items: [] }` |
| status-server-fetchers-016 | posthog-value-coercion | One query's body is `{results:[["42"]]}`, another's is `{results:[["abc"]]}` | First resolves value `42`; second resolves value `0` (`Number("abc") || 0`) |
| status-server-fetchers-017 | posthog-captured-at-per-batch, posthog-scope-fixed | A successful 4-metric batch | Every emitted `AnalyticsMetricDTO.capturedAt` is the identical ISO string; every `scope` is `"all"` |
| status-server-fetchers-018 | complete-flag-omission-vs-explicit | A successful `posthogFetcher(...).fetch()` result | The returned object has no `complete` key at all — `"complete" in result` is `false` |

## Edge Cases

- **Null and empty input**: any one of GlitchTip's three env fields absent, or PostHog's three absent, produces a clean, immediate `{ ok: true, items: [] }` no-op rather than a partial attempt; a GlitchTip issues response of `[]` produces `{ ok: true, items: [], complete: true }`, distinct from an unconfigured no-op only in that the request was actually made.
- **Boundary values**: a GlitchTip response of exactly `PAGE_LIMIT` (100) issues is treated as truncated (`complete: false`) even on the (unknowable to this file) chance that 100 was the provider's true total; 99 issues is treated as the whole answer. `Number("abc") || 0` in `hogql`'s string-value branch relies on `NaN` being falsy — any numeric string that parses to a genuinely falsy number (e.g. `"0"`) is indistinguishable from a parse failure, both resolving `0`.
- **Concurrent access**: neither file holds any module-level mutable state; every `fetch()` call constructs its own `AbortController`(s) local to that call, so concurrent or repeated calls to `glitchtipFetcher(env).fetch()` or `posthogFetcher(env).fetch()` never interfere with each other. `collectTelemetry` (external, `server.ts`) does call both fetchers concurrently via `Promise.all`, but each fetcher's own state is entirely call-local, so this is not a race either file needs to guard against.
- **Error states**: an HTTP error, a non-array body, and a thrown/aborted request each map to a distinct, already-itemized outcome for GlitchTip (**http-error-fails-poll**, **non-array-body-fails-poll**, **thrown-fetch-fails-poll**); a non-`ok` response or a thrown request maps to a per-query `error` string for PostHog, short-circuiting the remaining queries (**posthog-short-circuit-on-first-failure**). Neither file retries; a failure is reported for the current poll and left to the next scheduled cycle (external to these two files).
- **Offline / disconnected state**: both files bound every outbound request with an `AbortController`/timeout (`TIMEOUT_MS` for GlitchTip, `QUERY_TIMEOUT_MS` per PostHog query) so an unreachable or hanging provider fails the poll within a fixed budget rather than hanging the caller indefinitely.
- **glitchtip-issue-schema-unverified**: `mapIssues`/`GlitchtipIssue` reads `id`, `title`, `culprit`, `level`, `count`, `userCount`, `firstSeen`, `lastSeen`, `permalink`, and `project` in the shapes declared, falling back per field as described above; the file's own comment records that this shape has not been confirmed against a live GlitchTip instance. The response schema itself is owned by GlitchTip.
- **posthog-query-response-schema-unverified**: `hogql` reads the aggregate from `results[0][0]` of a `{ results: [[value]] }` response; the file's own comment records that this shape has not been confirmed against a live PostHog project. The response schema itself is owned by PostHog.
- **posthog-malformed-result-shape-unsignaled**: NEEDS REVIEW: Not implemented in source. When a query's response is `ok` but `results[0][0]` is neither a `number` nor a `string` (missing `results`, `null`, an object, a boolean), `hogql` resolves `{ value: null, error: null }`, and the caller treats it identically to a successful query with no assertable KPI — no `console.warn`, no recorded `failure`, and no signal distinguishing it from a provider that genuinely answered with nothing; whether a malformed shape of this kind should count as a failure is unresolved without a decision on how strictly to validate the HogQL response.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `env.GLITCHTIP_URL` | `string \| undefined` (`GlitchtipEnv` field) | caller-supplied | GlitchTip instance base URL; trailing slashes are stripped before building the issues-endpoint URL. All three GlitchTip fields must be present or the fetcher no-ops. |
| `env.GLITCHTIP_API_TOKEN` | `string \| undefined` (`GlitchtipEnv` field) | caller-supplied | Sent as `Authorization: Bearer` on the issues request. |
| `env.GLITCHTIP_ORG` | `string \| undefined` (`GlitchtipEnv` field) | caller-supplied | GlitchTip organization slug interpolated into the issues-endpoint path. |
| `TIMEOUT_MS` | `number` (module constant, `glitchtip.ts`) | `12_000` | Deadline for the single GlitchTip issues request, via `AbortController`. Not exported; not caller-configurable. |
| `PAGE_LIMIT` | `number` (exported module constant, `glitchtip.ts`) | `100` | Page size requested from GlitchTip and the threshold `complete-flag-by-page-size` compares the response length against. |
| `env.POSTHOG_HOST` | `string \| undefined` (`PosthogEnv` field) | caller-supplied | PostHog project host; trailing slashes stripped before building the query-endpoint URL. All three PostHog fields must be present or the fetcher no-ops. |
| `env.POSTHOG_API_KEY` | `string \| undefined` (`PosthogEnv` field) | caller-supplied | Sent as `Authorization: Bearer` on every HogQL query. |
| `env.POSTHOG_PROJECT_ID` | `string \| undefined` (`PosthogEnv` field) | caller-supplied | Interpolated into the HogQL query-endpoint path. |
| `METRICS` | `MetricSpec[]` (module constant, `posthog.ts`) | fixed 4-entry array (`pageviews`/`24h`, `visitors`/`24h`, `pageviews`/`7d`, `visitors`/`7d`) | Not exported; not caller-configurable. Defines every metric this file will ever query. |
| `QUERY_TIMEOUT_MS` | `number` (module constant, `posthog.ts`) | `10_000` | Deadline for each individual HogQL query, via its own `AbortController`. Not exported; not caller-configurable. |

## Deep Linking

Not applicable: neither file constructs or consumes an application deep link or universal link; every URL either file builds (the GlitchTip issues endpoint, the PostHog query endpoint) is a configured provider API host, not a link into this application.

## Localization

Not applicable: neither file emits a user-facing string; every string literal in either file is a diagnostic `console.warn` message (see Logging) or opaque provider data passed through unchanged.

## Accessibility Options

Not applicable: neither file renders UI, so Reduce Motion, Increase Contrast, and Differentiate Without Color have nothing to apply to.

## Feature Flags

Not applicable: neither file consults a feature-flag system; whether a fetcher is active is decided entirely by the presence of its three env credentials, per **unconfigured-no-op** and **posthog-unconfigured-no-op**.

## Analytics

Not applicable: neither file emits a self-referential analytics/telemetry event about its own invocation; producing the `AnalyticsMetricDTO` stream is the module's whole purpose, and that is fully specified under Behavioral Requirements, not a side-channel instrumentation event.

## Privacy

- **Data collected**: `glitchtip.ts` reads GlitchTip issue metadata (title, culprit, level, count, user count, timestamps, a permalink, and a project slug/name) — application error data, not end-user personal data. `posthog.ts` reads only aggregate, anonymous counts (`count()`/`count(DISTINCT person_id)` over `$pageview` events); per the file's own comment, this is a deliberate privacy-first design — "no person data ever leaves PostHog into here." Both files also hold their provider's bearer credential (`GLITCHTIP_API_TOKEN`, `POSTHOG_API_KEY`) for the duration of one `fetch()` call.
- **Storage**: neither file writes to persistent storage; both are PURE with respect to storage, per each file's own header comment. Persisting a fetch's results is `collect.ts`'s and the `Store<T>` port's job, external to these two files.
- **Transmission**: every outbound call in both files sends its provider credential as an `Authorization: Bearer` header, never in a query string or request body; the transport scheme (`http://` vs `https://`) is whatever the caller-supplied `GLITCHTIP_URL`/`POSTHOG_HOST` value specifies — neither file validates or enforces `https://`.
- **Retention**: neither file caches, persists, or retains a credential or a fetched item beyond the lifetime of one `fetch()` call; there is no in-memory cache of any kind in either file.

## Logging

Subsystem: process `console` | Category: telemetry

| Event | Level | Message |
|-------|-------|---------|
| GlitchTip issues request returned a non-`ok` HTTP response | warn | `` [telemetry] GlitchTip issues HTTP <status> `` |
| GlitchTip issues response body parsed but was not an array | warn | `[telemetry] GlitchTip issues returned a non-array body — treating as a failed poll` |
| GlitchTip issues request timed out | warn | `` [telemetry] GlitchTip issues fetch timed out after <TIMEOUT_MS>ms `` |
| GlitchTip issues request threw a non-timeout error | warn | `` [telemetry] GlitchTip issues fetch failed: <message> `` |
| A PostHog HogQL query batch stopped early on a failure | warn | `` [telemetry] PostHog poll failed (<failure>) — <answered>/<total> queries answered `` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | partial | Security |

`separation-of-concerns` passes: `mapIssues` (GlitchTip) and `hogql` (PostHog) are pure, network-free mapping functions the module itself calls out as "the testable core, no network"; all I/O is isolated to `glitchtipFetcher`'s/`posthogFetcher`'s outer `fetch()` closures. `unit-test-coverage` is `partial`: `glitchtip.ts` has a dedicated sibling suite (`telemetry-glitchtip-fetcher.test.ts`) exercising the unconfigured no-op, both `complete` branches, every failure path, and `mapIssues`'s fallbacks; `posthog.ts` has no dedicated unit-test file among the given sources — the closest coverage (`integrations-telemetry.test.ts`) exercises a different function (`runIntegrationsCheck`'s reachability probe), not `posthogFetcher` itself. `explicit-error-handling` is `partial`: every GlitchTip failure path and every all-fail/partial-fail PostHog path resolves a distinct, explicit outcome, but see the open question on `posthog-malformed-result-shape-unsignaled` — a malformed HogQL result silently contributes nothing with no error signal at all. `timeout-configuration` passes: every outbound call in both files is bounded by its own `AbortController`, cleared in a `finally`. `retry-with-backoff` fails as written: neither file retries a failed request under any condition — a deliberate choice recorded in Design Decisions, not an oversight. `error-response-handling` passes: both files distinguish a non-`ok` HTTP response, a body that parses but is the wrong shape, and a thrown/aborted request, each mapped to its own outcome. `graceful-degradation` passes: `posthogFetcher` preserves already-answered metrics on a partial batch failure rather than discarding them, and `glitchtipFetcher` degrades every recognizable failure to `ok: false` rather than throwing past its own boundary. `data-integrity` passes: the `complete` flag is set conservatively (a full page is never claimed complete), and a failed poll never resolves `ok: true` with a smaller-than-reality item set. `no-pii-in-logs` passes: every `console.warn` line names an HTTP status, a timeout duration, an error message, or a query-answered count — never a credential, a token, or provider response body. `secure-transport` is `partial`: both files send their provider credential only via an `Authorization: Bearer` header, never a query string or body, but neither validates or enforces that `GLITCHTIP_URL`/`POSTHOG_HOST` is `https://` — the transport scheme is entirely whatever the caller configured.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation, documenting the GlitchTip issues fetcher and PostHog HogQL analytics fetcher: their env-gated no-op, single bounded fetch attempt, DTO mapping, the `complete`-flag contract with the reconciling errors store, and the PostHog batch's sequential, partial-success semantics. Records the open questions over both providers' unverified response schemas and PostHog's unsignaled malformed-shape case.
