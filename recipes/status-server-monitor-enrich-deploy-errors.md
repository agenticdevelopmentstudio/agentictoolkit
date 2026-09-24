---
id: e029def6-7d5d-4e52-b565-e2a6612179bb
title: Status Server Monitor Enrich Deploy Errors
domain: agentictoolkit://recipes/status-server-monitor-enrich-deploy-errors
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Fetches and persists the provider failure reason for recent failed Vercel/Railway
  deploys lacking one, bounded per cycle with cooldown-aware fail-soft dispatch.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- vercel
- railway
- rate-limiting
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/networking/timeouts
- agenticdevelopercookbook://guidelines/implementing/networking/retry-and-resilience
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
related: []
references:
- packages/web/packages/status-server/src/monitor/enrich-deploy-errors.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-vercel.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-railway.ts (agentictoolkit)
- packages/web/packages/status-server/src/storage/ports.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/deploy-store.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/conn/index.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/cooldown/provider-cooldown.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/util/map-limit.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-error-shaping.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Enrich Deploy Errors

## Overview

`enrich-deploy-errors.ts` (`packages/web/packages/status-server/src/monitor/enrich-deploy-errors.ts`) is the status backend's deploy-error enrichment healer. Its own header comment states the problem it exists to fix: a failed Vercel or Railway deploy row is stored with no explanation of WHY it failed, so the details pane (and its copy button) has nothing to show an operator short of opening the provider's own dashboard. This module fills in `error_text` for failed deploys that don't have it yet — Vercel's `errorMessage` via `fetchVercelDeployError`, Railway's build-log tail via `fetchRailwayBuildLogTail` — fetched ONCE per deploy and persisted via `storage.deploy.setErrorText`. It exports one function, `enrichDeployErrors`, invoked by `sync.ts`'s `runCycle` immediately after `storage.deploy.upsertDeployments` on every full sync cycle. Per its own doc comment it is deliberately bounded and fail-soft: a recent-only window, a small per-cycle cap, bounded concurrency, and a per-call timeout keep it from threatening the cycle's own time budget, and every fetch is wrapped so a single failure can never abort the cycle — a failed fetch just leaves `error_text` null, to retry next cycle.

## Behavioral Requirements

### Public Operation

- **enrich-deploy-errors-signature**: `enrichDeployErrors` MUST accept exactly two parameters — `storage: Storage` and `conn: ProviderConn` — and MUST return `Promise<void>`.
- **runs-after-upsert**: Per `sync.ts`'s own call order and comment, `enrichDeployErrors` MUST be invoked only after `storage.deploy.upsertDeployments` has persisted the current cycle's freshly fetched deploys, so `listFailedWithoutError` can see failures upserted earlier in that same cycle.
- **never-throws**: `enrichDeployErrors`'s returned promise MUST NOT reject on any traced failure path (a candidate-query rejection, a per-row fetch/store rejection, or a per-call timeout) — every one of those is caught internally and logged, never re-thrown.

### Candidate Selection

- **candidate-platform-filter**: `enrichDeployErrors` MUST compute its candidate platform list as `pollableByIdPlatforms(conn)` filtered to exclude any provider for which `rateLimitedUntil(provider)` is non-null (currently cooling down after a 429), and MUST use only that filtered list (`polled`) as the `platforms` argument to `storage.deploy.listFailedWithoutError`.
- **no-pollable-platform-short-circuit**: When the filtered `polled` list is empty — per the source comment, "no token, or both cooling down" — `enrichDeployErrors` MUST return immediately without calling `storage.deploy.listFailedWithoutError` and without performing any provider fetch.
- **candidate-query-shape**: `enrichDeployErrors` MUST call `storage.deploy.listFailedWithoutError` with `platforms` set to `polled`, `createdAfterMs` set to `Date.now()` minus `ENRICH_WINDOW_DAYS` (14) days expressed in milliseconds, and `limit` set to `ENRICH_MAX_PER_CYCLE` (8).
- **candidate-window-boundary**: Per the libsql `listFailedWithoutError` implementation's `gt(deployments.createdAt, new Date(input.createdAfterMs))` predicate, a deploy row created at exactly the 14-day-ago instant MUST be excluded from the candidate set, not included — the boundary is strictly greater-than.
- **query-failure-fail-soft**: When `storage.deploy.listFailedWithoutError` rejects, `enrichDeployErrors` MUST catch the rejection, log it via `console.error` with `[enrich] failed-deploy query failed:` as the first argument and the caught error as the second, and return without calling `mapLimit` or performing any provider fetch.
- **empty-candidates-short-circuit**: When `listFailedWithoutError` resolves an empty array, `enrichDeployErrors` MUST return without calling `mapLimit` or performing any provider fetch.

### Platform Dispatch (`fetchErrorFor`)

- **id-platform-row-shape**: A `DeployIdPlatformRow` value, as returned by `listFailedWithoutError`, MUST carry exactly two fields — `id: string` and `platform: string` — per its declaration in `storage/ports.ts`.
- **platform-dispatch-vercel**: `fetchErrorFor` MUST call `fetchVercelDeployError` when `row.platform === "vercel"` and `conn.vercel.token` is set, passing `row.id` with a leading `vc_` prefix stripped, an env object built from `conn.vercel.token`/`conn.vercel.teamId`, and the per-call `AbortSignal`.
- **platform-dispatch-railway**: `fetchErrorFor` MUST call `fetchRailwayBuildLogTail` when `row.platform === "railway"` and `conn.railway.token` is set, passing `row.id` with a leading `ry_` prefix stripped, `conn.railway.token`, and the per-call `AbortSignal`.
- **platform-dispatch-fallback-null**: For a row whose platform/token combination matches neither the Vercel nor the Railway branch, `fetchErrorFor` MUST resolve `null` without making any network call — per its own doc comment, "for a platform we can't fetch (no token / no reason)."
- **per-call-timeout**: For each candidate row, `enrichDeployErrors` MUST create an `AbortController`, start a `setTimeout` that calls `controller.abort()` after `ENRICH_CALL_TIMEOUT_MS` (8,000) milliseconds, pass `controller.signal` into `fetchErrorFor`, and MUST clear that timer in a `finally` block regardless of whether the fetch settled, rejected, or was aborted.
- **bounded-concurrency**: `enrichDeployErrors` MUST process the candidate rows via `mapLimit` with a concurrency limit of `ENRICH_CONCURRENCY` (4), so no more than 4 candidate rows are ever being fetched at the same instant.

### Persistence

- **persist-only-truthy-text**: When `fetchErrorFor` resolves a truthy string for a row, `enrichDeployErrors` MUST call `storage.deploy.setErrorText(row.id, text)` exactly once for that row before that row's `mapLimit` task completes.
- **no-persist-on-null**: When `fetchErrorFor` resolves `null` for a row, `enrichDeployErrors` MUST NOT call `storage.deploy.setErrorText` for that row, and MUST NOT log anything for that row — a null result is a normal outcome (no reason available yet), not a failure.
- **idempotent-enrichment**: Because `setErrorText` sets a row's `error_text` to a non-null value and `listFailedWithoutError`'s own predicate (`isNull(deployments.errorText)`) excludes any row with a non-null `error_text`, a row enriched in one cycle MUST NOT be re-selected as a candidate by a later cycle's call to `listFailedWithoutError` — from this function's perspective, enrichment of a given row is write-once.

### Error Handling and Fail-Soft Behavior

- **per-row-fetch-failure-fail-soft**: When `fetchErrorFor` or the subsequent `setErrorText` call rejects for one candidate row, `enrichDeployErrors` MUST catch that rejection inside that row's `mapLimit` callback, log it via `console.error` with a template string `` `[enrich] ${row.id} error fetch/store failed:` `` as the first argument and the caught error as the second, and MUST NOT let that rejection propagate out of the `mapLimit` call or affect the processing of any other candidate row.
- **timeout-manifests-as-abort**: When a candidate row's fetch has not settled after `ENRICH_CALL_TIMEOUT_MS` (8,000) milliseconds, the fired timer's `controller.abort()` call MUST cause the in-flight `fetchErrorFor` call's underlying request promise to reject with an abort error, which MUST then be caught and logged exactly as any other per-row fetch failure (per-row-fetch-failure-fail-soft), not treated as a distinct case.

### Credential Handling

- **tokens-passed-opaque**: `enrichDeployErrors` and `fetchErrorFor` MUST treat `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` as opaque values received via the `conn` parameter — this file MUST NOT read them from `process.env` or any other source itself, and MUST NOT log, persist, or otherwise expose any of these three values.
- **tokens-gate-not-authenticate**: This file's own use of a provider token MUST be limited to a truthiness check (`conn.vercel.token` / `conn.railway.token` set or unset) that decides whether `fetchErrorFor` attempts a fetch at all; the token value itself is forwarded unread to `fetchVercelDeployError`/`fetchRailwayBuildLogTail` (both external to this file), which are the functions that actually place it on an outbound request.

### Ordering and Concurrency

- **single-invocation-per-cycle**: `enrichDeployErrors` MUST be invoked at most once per full sync cycle, synchronously awaited by `runCycle` before that cycle continues to `reconcileVanishedDeploys`; this file holds no module-level state of its own (no queue, no singleton), so nothing internal to it can race across cycles.
- **intra-call-concurrency-bound**: Within one `enrichDeployErrors` call, up to `ENRICH_CONCURRENCY` (4) candidate rows' fetches MAY run concurrently via `mapLimit`, each against its own distinct row id and its own `AbortController`/timer pair, so no two concurrent fetches within one call can write to the same storage row or share a timeout.
- **thread-context**: This function runs on whichever thread its caller (`runCycle` in `sync.ts`, via `runMonitorCycle` in `cycle-runner.ts`) is executing on — the monitor's own worker thread for a scheduled cycle, or the API thread when `runMonitorCycle` is invoked from there — per `cycle-runner.ts`'s own doc comment describing `config` (and, by the same structural argument, the `storage`/`conn` handles) as threaded in from whichever caller owns that invocation; this file itself makes no thread-affinity assumption beyond running to completion on whichever thread called it.

## Appearance

Not applicable — this is a server-side deploy-error enrichment healer, not a visual component.

## States

Not applicable — this is a server-side deploy-error enrichment healer, not a visual component; its only runtime states (no pollable platform, empty candidate set, per-row pending/fetched/failed) are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side deploy-error enrichment healer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-enrich-deploy-errors-001 | no-pollable-platform-short-circuit, candidate-platform-filter | `conn.vercel.token` and `conn.railway.token` both unset; `await enrichDeployErrors(storage, conn)` | `storage.deploy.listFailedWithoutError` is never called; `storage.deploy.setErrorText` is never called; the call resolves `undefined` |
| status-server-monitor-enrich-deploy-errors-002 | candidate-platform-filter, no-pollable-platform-short-circuit | `conn.vercel.token` set but `rateLimitedUntil("vercel")` returns a future timestamp (both providers effectively cooling down since `conn.railway.token` is unset); `await enrichDeployErrors(storage, conn)` | `storage.deploy.listFailedWithoutError` is never called — the "vercel" entry is filtered out of `polled` before the query is built |
| status-server-monitor-enrich-deploy-errors-003 | query-failure-fail-soft | `conn.vercel.token` set; `storage.deploy.listFailedWithoutError` stubbed to reject with `new Error("db down")` | The call resolves `undefined` (does not throw); exactly one `console.error` call is made whose first argument is `[enrich] failed-deploy query failed:`; `storage.deploy.setErrorText` is never called |
| status-server-monitor-enrich-deploy-errors-004 | empty-candidates-short-circuit | `conn.vercel.token` set; `storage.deploy.listFailedWithoutError` resolves `[]` | No `fetchVercelDeployError`/`fetchRailwayBuildLogTail` call is made; `storage.deploy.setErrorText` is never called |
| status-server-monitor-enrich-deploy-errors-005 | platform-dispatch-vercel, persist-only-truthy-text, candidate-query-shape | `conn.vercel.token = "tok"`; `listFailedWithoutError` resolves `[{ id: "vc_abc123", platform: "vercel" }]`; `fetchVercelDeployError` stubbed to resolve `"Command \"next build\" exited with 1"` | `fetchVercelDeployError` is called with `"abc123"` (the `vc_` prefix stripped) as its first argument; `storage.deploy.setErrorText("vc_abc123", "Command \"next build\" exited with 1")` is called exactly once |
| status-server-monitor-enrich-deploy-errors-006 | platform-dispatch-railway, persist-only-truthy-text | `conn.railway.token = "tok"`; `listFailedWithoutError` resolves `[{ id: "ry_xyz789", platform: "railway" }]`; `fetchRailwayBuildLogTail` stubbed to resolve `"error: build failed"` | `fetchRailwayBuildLogTail` is called with `"xyz789"` (the `ry_` prefix stripped) as its first argument; `storage.deploy.setErrorText("ry_xyz789", "error: build failed")` is called exactly once |
| status-server-monitor-enrich-deploy-errors-007 | no-persist-on-null, platform-dispatch-fallback-null | `conn.vercel.token = "tok"`; candidate row `{ id: "vc_def456", platform: "vercel" }`; `fetchVercelDeployError` stubbed to resolve `null` | `storage.deploy.setErrorText` is never called for `"vc_def456"`; no `console.error` call is made for this row |
| status-server-monitor-enrich-deploy-errors-008 | per-row-fetch-failure-fail-soft | `conn.railway.token = "tok"`; candidate row `{ id: "ry_bad", platform: "railway" }`; `fetchRailwayBuildLogTail` stubbed to reject with `new Error("network down")` | The call resolves `undefined` (does not throw); exactly one `console.error` call is made whose first argument is `` `[enrich] ry_bad error fetch/store failed:` ``; `storage.deploy.setErrorText` is never called for `"ry_bad"` |
| status-server-monitor-enrich-deploy-errors-009 | bounded-concurrency, candidate-query-shape | `conn.vercel.token = "tok"`; `listFailedWithoutError` resolves 8 distinct Vercel candidate rows; `fetchVercelDeployError` stubbed to track the concurrently in-flight call count before resolving each after a delay | The tracked concurrently in-flight call count never exceeds 4 at any instant |
| status-server-monitor-enrich-deploy-errors-010 | per-call-timeout, timeout-manifests-as-abort | `conn.railway.token = "tok"`; one candidate row; `fetchRailwayBuildLogTail` stubbed to never resolve or reject on its own, but to reject with an abort error when its received `AbortSignal` fires; fake timers advanced past 8,000ms | The `AbortSignal` passed to `fetchRailwayBuildLogTail` aborts at 8,000ms; the call resolves `undefined` within the timeout window (via per-row-fetch-failure-fail-soft), not indefinitely |

## Edge Cases

- **Null and empty input**: no pollable platform (`polled.length === 0`, whether from no token being configured or both providers currently rate-limited) MUST short-circuit before any storage query is made — MUST (no-pollable-platform-short-circuit). An empty candidate array from `listFailedWithoutError` MUST short-circuit before any provider fetch is made — MUST (empty-candidates-short-circuit). A row whose platform/token combination `fetchErrorFor` doesn't recognize MUST resolve `null` silently, with no log line and no `setErrorText` call, distinguishing "nothing to report" from a failure — MUST (no-persist-on-null).
- **Boundary values**: exactly `ENRICH_MAX_PER_CYCLE` (8) rows are ever queried or fetched in one call, even when more rows qualify — MUST. Because `listFailedWithoutError` orders candidates newest-created-first, a fixed 8-row cap combined with a steady stream of more than 8 new unenriched failures per cycle within the 14-day window means the OLDEST unenriched rows are perpetually deprioritized behind fresher ones, and such a row can in principle age past the `createdAfterMs` cutoff before ever being selected, leaving it permanently unenriched — this is a fact of the observed ordering + cap combination, not a case this file validates against, so it is recorded here rather than under Behavioral Requirements as a guaranteed drain — SHOULD be understood as a known limit of the "any backlog drains over successive cycles" claim in the module's own header comment, not a contradiction of it under normal load. The candidate window's `createdAfterMs` boundary is strictly greater-than, so a deploy created at exactly 14 days ago is excluded — MUST (candidate-window-boundary).
- **Concurrent access**: within one `enrichDeployErrors` call, `mapLimit` bounds concurrent candidate processing to 4 in flight at once, each against a distinct row id, so two concurrent fetches can never target the same storage row — MUST (bounded-concurrency, intra-call-concurrency-bound). Across cycles, `enrichDeployErrors` holds no module-level state, so there is no cross-call race internal to this file to reason about; whether two overlapping cycle invocations could ever race is a property of the caller's own scheduling (`runCycle`/`runMonitorCycle`, both external to this file) and is not addressed here — MUST (no internal state to race, per the file's own contents).
- **Error states**: a `listFailedWithoutError` rejection is caught, logged, and the whole call returns without fetching anything — MUST (query-failure-fail-soft). A per-row `fetchErrorFor`/`setErrorText` rejection is caught and logged inside that row's own `mapLimit` callback, without affecting sibling rows or the overall call's resolution — MUST (per-row-fetch-failure-fail-soft). A provider that answers with "no reason available" (Vercel with no `errorMessage`/`readyStateReason`, or Railway's own permanent "no associated build" placeholder text) is not distinguished by THIS file from a transient fetch failure that returned `null` — both simply skip `setErrorText` for that row and let a later cycle re-select it (except the Railway "no build" placeholder, which is itself a truthy string, so it IS persisted and does take that row out of future candidate sets) — MUST (no-persist-on-null, external behavior of `fetchRailwayBuildLogTail` cited for context, not owned by this file).
- **Offline/disconnected state**: this file holds no persistent connection of its own to lose; its analogue is a provider being unreachable mid-fetch for the whole `ENRICH_CALL_TIMEOUT_MS` (8,000ms) window, which is exactly the per-row Error states case above — caught, logged, and left for a later cycle, with no retry attempted within the same call — MUST.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` (parameter) | `Storage` | required, caller-supplied | The storage port providing `storage.deploy.listFailedWithoutError` and `storage.deploy.setErrorText`; this file never constructs or configures a storage implementation itself. |
| `conn` (parameter) | `ProviderConn` | required, caller-supplied | Resolved provider connections (`@agentic-toolkit/deploy-platform/conn`), carrying `conn.vercel.token`/`conn.vercel.teamId` and `conn.railway.token`, used only to gate and authenticate the per-provider fetches this file dispatches to. |
| `ENRICH_WINDOW_DAYS` (module constant) | `number` | `14` | Recency window in days; only failed deploys created within this window are candidates. Not configurable per call and has no environment override in this file. |
| `ENRICH_MAX_PER_CYCLE` (module constant) | `number` | `8` | Maximum candidate rows queried and enriched per call. Not configurable per call. |
| `ENRICH_CONCURRENCY` (module constant) | `number` | `4` | Maximum concurrent in-flight fetches passed to `mapLimit`. Not configurable per call. |
| `ENRICH_CALL_TIMEOUT_MS` (module constant) | `number` | `8_000` | Per-row fetch deadline enforced via `AbortController`/`setTimeout`. Not configurable per call. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own; `enrichDeployErrors` only reads candidate rows from `storage` and writes back to it via `setErrorText` — it has no inbound URL to handle and constructs no outbound deep link.

## Localization

Not applicable: this file authors no user-facing string of its own. Its two `console.error` calls (`[enrich] failed-deploy query failed:` and `` `[enrich] ${row.id} error fetch/store failed:` ``) are operator-facing diagnostic log lines, not text shown in any UI, so they carry no localization concern here; the `error_text` value it persists via `setErrorText` is entirely provider-authored (Vercel's `errorMessage`/`readyStateReason`, or Railway's build-log tail), not a string literal in this file, so whether or how that value is localized when rendered is a concern of the consumer that displays it, external to this file.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind; `enrichDeployErrors` is invoked unconditionally from `sync.ts`'s `runCycle` on every full sync cycle, with the cooldown/token gating already documented under Behavioral Requirements as its only on/off lever.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: this file receives `conn.vercel.token`, `conn.vercel.teamId`, and `conn.railway.token` as opaque values (sourced by callers external to this file — `providerConnFromConfig`/`connFromEnv` in `deploy-platform/conn`) and forwards the token values, unread, to `fetchVercelDeployError`/`fetchRailwayBuildLogTail`. It also reads and persists the provider's own failure-reason text via `storage.deploy.setErrorText` — that text is provider-authored build/deploy output (a Vercel error message or a Railway build-log tail) and may contain anything the build process printed, which this file has no ability to inspect or redact.
- **Storage**: this file itself performs no storage beyond delegating to `storage.deploy.setErrorText`, whose durability is the storage port's concern (external to this file); the provider tokens are never written to storage by this file — they exist only as in-memory `conn` fields for the duration of one call.
- **Transmission**: tokens are handed to `fetchVercelDeployError`/`fetchRailwayBuildLogTail` (both external to this file), which use them to authenticate the corresponding provider's HTTPS API call; this file makes no network call of its own and never logs a token value.
- **Retention**: not applicable to this file directly; the `error_text` value it persists is retained for as long as the `deployments` row exists, governed by `storage.deploy.pruneOlderThanDays(90)`, called elsewhere in `sync.ts` and external to this file.

## Logging

This file uses plain `console.error` calls, each with a literal `[enrich]` prefix, not a structured logger with its own subsystem/category object.

| Event | Level | Message |
|-------|-------|---------|
| The `listFailedWithoutError` candidate query rejects | error (`console.error`) | `[enrich] failed-deploy query failed:` (caught error passed as the second `console.error` argument) |
| A candidate row's fetch or `setErrorText` call rejects | error (`console.error`) | `` `[enrich] ${row.id} error fetch/store failed:` `` (caught error passed as the second `console.error` argument) |

No log line is emitted on a successful enrichment, an empty candidate set, or a no-pollable-platform short circuit, at any level — silence is the expected steady state.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple-side status monitor port would model this healer as an `async` function isolated to an actor that owns the monitor cycle, using `URLSession` for the Vercel/Railway calls (the Swift equivalents of `fetchVercelDeployError`/`fetchRailwayBuildLogTail`), a `withThrowingTaskGroup` capped at 4 concurrently-running child tasks as the `mapLimit` analogue, and each child task racing its fetch against a `Task.sleep(for: .seconds(8))` (or `URLRequest.timeoutInterval = 8`) as the `AbortController`/8,000ms deadline analogue.
- **Compose**: a Kotlin port models this as a `suspend fun` using a `kotlinx.coroutines.sync.Semaphore(4)` (or a bounded dispatcher) as the direct substitute for `mapLimit` — Kotlin coroutines have no built-in bounded-map primitive, so `async` + `Semaphore.withPermit` per candidate is the idiomatic shape — `withTimeout(8_000)` for the per-call deadline, and the candidate query/persist behind a Room or Exposed repository mirroring `listFailedWithoutError`/`setErrorText`.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/enrich-deploy-errors.ts` as a plain exported `async` function on the Node status backend — not client-side React, and no framework dependency beyond the `Storage` port and the shared `@agentic-toolkit/deploy-platform` cooldown/util/conn modules it imports. It is imported and awaited exactly once per full cycle by `sync.ts`'s `runCycle`, itself invoked from `runMonitorCycle` in `cycle-runner.ts`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI; a macOS/iOS agent embedding this healer pattern has no UIKit/AppKit-specific concern, since this is a background sync task rather than a view-driven one — the actor + `URLSession` + `TaskGroup` shape described under SwiftUI applies unchanged.
- **WinUI 3**: model `DeployIdPlatformRow` as a `readonly record struct(string Id, string Platform)`, the candidate query as an `async Task<IReadOnlyList<DeployIdPlatformRow>> ListFailedWithoutErrorAsync(...)` over EF Core or Dapper mirroring `listFailedWithoutError`'s predicate (`ErrorText == null`, platform `IN`, `CreatedAt > cutoff`, ordered newest-first, `Take(8)`), and the per-row dispatch as `Task<string?> FetchErrorForAsync(DeployIdPlatformRow row, ProviderConn conn, CancellationToken ct)` using a `switch` expression on `row.Platform` in place of the source's `if`/`else` chain in `fetchErrorFor`. Give each call a `CancellationTokenSource(TimeSpan.FromSeconds(8))` — composed with any caller-supplied token via `CancellationTokenSource.CreateLinkedTokenSource` — as the `AbortController`/`AbortSignal.timeout` analogue, and cap concurrency with `Parallel.ForEachAsync(candidates, new ParallelOptions { MaxDegreeOfParallelism = 4 }, ...)` (the .NET 6+ idiomatic equivalent of `mapLimit`; a hand-rolled `SemaphoreSlim(4)` loop is the alternative on older targets). Persist via `DeployStoreAsync.SetErrorTextAsync(id, text)` inside a per-item `try`/`catch` that logs through `ILogger<T>` with the same `[enrich]`-prefixed message shapes, in place of `console.error`.

## Design Decisions

- **Decision**: cap both the query and the fetch batch at `ENRICH_MAX_PER_CYCLE` (8) rather than fetching every currently-qualifying row each cycle.
  **Rationale**: per the module's own header comment, only a few rows are enriched per cycle by design, and because enrichment is idempotent (`error_text` is written once and the row is then permanently excluded from later scans by `listFailedWithoutError`'s own `isNull` predicate), any backlog drains over successive cycles "without a single cycle ever fetching enough to threaten the watchdog budget" — the external per-cycle time budget the surrounding `runCycle` is held to.
  **Approved**: pending
- **Decision**: rely on `listFailedWithoutError`'s newest-created-first ordering rather than oldest-first.
  **Rationale**: not explained in a comment on this file directly; recorded here as an observed, deliberate fact rather than an invented rationale. Under sustained load (more than 8 new unenriched failures within the 14-day window every cycle), this ordering means the oldest unenriched rows are the ones perpetually deprioritized behind fresher failures, and such a row can in principle age out of the `createdAfterMs` window before ever being selected — a genuine tension with the header comment's "any backlog drains" claim under that specific load pattern, traded off against the more actionable default of explaining the freshest failures first.
  **Approved**: pending
- **Decision**: honor the shared provider cooldown by filtering it INTO the candidate query's `platforms` argument, rather than querying unfiltered and catching a 429 per row.
  **Rationale**: stated directly in the source comment on the `polled` computation — a throttled provider's rows "wait for a later cycle rather than spending requests that extend the throttle," the same rule the sibling by-id reconcile healer applies to the identical shared `SharedArrayBuffer`-backed cooldown.
  **Approved**: pending
- **Decision**: return before ever calling `storage.deploy.listFailedWithoutError` when `polled` is empty, rather than issuing the query and discarding an empty-platforms result.
  **Rationale**: the inline comment on the check states the two possible causes plainly — "no token, or both cooling down" — either way nothing this cycle could fetch, so the DB round trip itself is skipped rather than spent and immediately thrown away.
  **Approved**: pending
- **Decision**: type `pollableByIdPlatforms`'s return as `ProviderName[]` (a fixed union of cooldown slot names) rather than `string[]`.
  **Rationale**: stated directly in that function's own doc comment (`deploy-platform/conn`) — a raw `platform` string (e.g. a stored row's `"cloudflare-pages"`) cast to `ProviderName` could otherwise smuggle a non-slot name into the cooldown module's `Atomics` index and throw a `RangeError` inside the monitor cycle; sourcing the candidate list from the fixed slot literals makes that cast impossible at this file's own call site.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | partial | Access Patterns |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` is `failed` for this file specifically: `deploy-error-shaping.test.ts` exercises only the network-free shaping helpers `enrichDeployErrors` calls into indirectly (`composeVercelDeployError`, `buildLogTail`, `buildLogFull`, `fetchRailwayBuildLogTail`'s GraphQL-error branches) — no test in the given sources imports or invokes `enrichDeployErrors` itself, so its own candidate-selection, cooldown filter, dispatch, concurrency cap, and fail-soft catches are untested at this file's level. `separation-of-concerns` passes: this file owns exactly one concern — selecting candidates and dispatching/persisting their error text — delegating the actual provider fetch logic to `fetch-vercel.ts`/`fetch-railway.ts`, the cooldown check to `deploy-platform/cooldown`, the bounded fan-out to `deploy-platform/util`'s `mapLimit`, and every storage read/write to the `Storage` port, never touching a database directly. `explicit-error-handling` passes: every failure path this file can hit — the candidate query rejecting, and a per-row fetch or store rejecting — is caught explicitly and logged with a distinguishing `[enrich]`-prefixed message; nothing is silently swallowed without a signal. `timeout-configuration` passes: every per-row fetch carries an explicit 8,000ms deadline via `AbortController`/`setTimeout`, cleared in a `finally`. `retry-with-backoff` is `partial`: a failed row is never retried within the same call, and there is no backoff of any kind — but because the row remains a candidate (its `error_text` stays null) and `enrichDeployErrors` runs again on the very next full cycle, a failed fetch is naturally retried across cycles, just without exponential backoff or a retry cap other than the 14-day recency window; this is a real, if unconventional, retry mechanism, which is why the check is `partial` rather than `failed`. `rate-limit-handling` passes: the shared cooldown (`rateLimitedUntil`) is consulted before the candidate query is even built, so a throttled provider's rows wait for a later cycle instead of spending requests that would extend the throttle. `idempotent-operations` passes: `setErrorText` writes `error_text` once, and `listFailedWithoutError`'s own `isNull(errorText)` predicate then permanently excludes that row from future candidate sets — re-running the identical logic against an already-enriched row is a no-op by construction. `graceful-degradation` passes: no token, both providers cooling down, an empty candidate set, a query failure, or a per-row fetch failure all degrade to a skip/no-op for the affected scope rather than throwing, matching the caller's own "best-effort and fail-soft" framing in `sync.ts`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
