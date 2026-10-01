---
id: 7610ef55-32c9-43b6-8a70-aaa247cc4899
title: Board State
domain: agentictoolkit://cookbook/status/dashboard/state/board
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The client's one source for the server-derived board, folding read staleness
  and frozen data into a null board with a reason
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/api
references: []
approved-by: ''
approved-date: ''
---

# Board State

## Overview

This logic is the status dashboard's one source for the server-derived board. It fetches `GET /board` through the injected API client, polls every 60 seconds, and refetches immediately whenever the live transport ingests a frame. Per its own documentation it "fetches and renders; it does not derive, accumulate, or persist."

Its defining contract is that `board` is non-null only when the board can back a current claim. A board that has not arrived, whose request failed, whose read clock (`generatedAt`) has gone old, whose data clock (`dataAsOfMs`) lags the read clock past a cadence-scaled window, or that rests on no observation at all, is returned as `board: null` together with a reason naming which of those it is. Consumers get the staleness verdict by construction instead of each re-deriving it. The rules and thresholds themselves live in a separate staleness component; this logic is the single call site that applies them.

Use it anywhere a view needs the portfolio board (the overview, the header pill, the global panel view). Word the "unknown" message per cause from `reason`; never re-derive staleness downstream.

## Behavioral Requirements

### Public shape

- **hook-signature**: This logic MUST take no arguments and MUST return an object with exactly the fields `board`, `reason`, `error` and `refetch`.
- **board-field**: The returned `board` field MUST be a board object or `null`.
- **reason-field**: The returned `reason` field MUST be one of `"loading"`, `"unavailable"`, `"stale"`, `"frozen"`, `"no-data"`, or `null`.
- **reason-board-exclusive**: `reason` MUST be null exactly when `board` is non-null, and `board` MUST be null exactly when `reason` is non-null.
- **single-loading-signal**: This logic MUST NOT expose a separate loading flag; a caller wanting a spinner MUST test whether `reason` exactly equals `"loading"` (a separate loading flag would be a second way to ask one question).
- **error-field**: The returned `error` field MUST be the last fetch's error, or null when there is none.
- **refetch-field**: The returned `refetch` field MUST be a callback taking no arguments that triggers a refetch of the board and returns nothing.
- **poll-interval-export**: This logic's module MUST expose the poll interval constant (60,000 ms) alongside its main export, for callers that need the exact number.

### Fetching

- **fetch-request**: Each board read MUST issue one request for path `/board` through the API client (resolved against its base path, `/api` by default), with header `accept: application/json` and no other request options.
- **fetch-http-error**: A response whose `ok` is false MUST reject the read with an `Error` whose message is exactly `board fetch failed: <status>` (for example `board fetch failed: 500`); the response body is not read.
- **fetch-body-passthrough**: A successful response MUST be returned as the parsed JSON body, unmodified, as the board (see Platform Notes for the test asserting deep equality with the server payload).
- **fetch-parse-error**: A body that is not valid JSON MUST reject the read with the underlying parse error.
- **query-key**: The board MUST be held in a shared cache under the key `["board"]`, so every caller sharing that cache shares one cached board and one fetch.
- **poll-cadence**: This logic MUST refetch every 60 seconds while active, independent of whether the live stream is connected.
- **retry-once**: A failed read MUST be retried exactly once before an error is reported, using the underlying fetch layer's default retry delay (see Platform Notes).
- **no-timeout**: This logic MUST NOT apply its own request timeout or abort signal; a hung request stays in flight until the transport ends it or a subsequent refetch cancels it.

### Live-frame refetch

- **frame-subscription**: While active, this logic MUST subscribe to the live-frame feed and MUST call `refetch` once for every live frame delivered.
- **frame-source-agnostic**: The frame subscription MUST fire for a frame ingested by any API client's live store, because the subscriber set is shared module-wide (see Platform Notes).
- **frame-no-second-connection**: This logic MUST NOT open its own streaming connection; it piggybacks on the live snapshot's existing feed ("one connection per tab is the existing contract").
- **frame-unsubscribe**: On teardown, and before re-subscribing when the `refetch` function's identity changes, this logic MUST remove its frame subscriber.
- **frame-no-throttle**: This logic MUST NOT debounce or coalesce frames; each frame calls `refetch`, cancelling any in-flight board read in favor of the new one (see Platform Notes).

### Availability verdict

The verdict is computed every time this logic runs, from the cached data (the last successful board, retained across later failures) and the current time. The branches are evaluated in this order and the first match wins:

- **verdict-loading**: When there is no cached board and the initial load is still in flight (pending and fetching), `reason` MUST be `"loading"`.
- **verdict-unavailable**: When there is no cached board and the initial load has already finished (the fetch failed after its retry, or the fetch is paused), `reason` MUST be `"unavailable"`.
- **verdict-stale**: When a cached board exists and its read clock is judged stale against the current time, `reason` MUST be `"stale"`.
- **stale-threshold**: The staleness check MUST return true when the current time minus the parsed `generatedAt` timestamp is greater than 180,000 ms (three poll cycles), and false when it is less than or equal.
- **stale-unparseable-clock**: The staleness check MUST return true (fail closed) when `generatedAt` does not parse to a finite age.
- **stale-client-clock**: The read-clock check MUST be judged against the client's wall clock as sampled at its default 30-second refresh, so a board is reported stale no later than about 30 seconds after it crosses the 180,000 ms threshold.
- **verdict-no-data**: When the board is not stale and `board.dataAsOfMs` is null, `reason` MUST be `"no-data"`.
- **verdict-frozen**: When the board is not stale and the data-clock freshness check on `dataAsOfMs`, `generatedAt` and `probeIntervalMs` returns `"frozen"`, `reason` MUST be `"frozen"`.
- **frozen-threshold**: The data clock MUST read `"frozen"` when the parsed `generatedAt` timestamp minus `dataAsOfMs` is greater than the data-staleness window for `probeIntervalMs`, which equals `max(probeIntervalMs × 5, 300000) × 2` ms (600,000 ms at the default 60-second cadence).
- **frozen-unparseable-lag**: The data clock MUST read `"frozen"` when the lag between `generatedAt` and `dataAsOfMs` is not a finite number.
- **frozen-server-clock**: The data-clock check MUST compare two server timestamps carried on the board being judged (`generatedAt` and `dataAsOfMs`), using the cadence carried on that same board (`probeIntervalMs`), and MUST NOT depend on the client clock or on the live snapshot.
- **verdict-current**: When the board is not stale and its data clock reads `"current"`, `reason` MUST be null and `board` MUST be the cached board object, unmodified.
- **stale-over-frozen**: When a board is both stale and frozen, `reason` MUST be `"stale"`, because the read-clock check is evaluated first.
- **error-independent-of-board**: `error` MUST reflect the last fetch's error state independently of the verdict, so a board that is still current from an earlier successful read MAY be returned alongside a non-null `error` from a later failed poll.
- **retained-data-ages-out**: A board retained from an earlier success while later polls fail MUST keep being judged each time this logic runs, and MUST become `board: null, reason: "stale"` once its `generatedAt` crosses the 180,000 ms threshold.

### State and persistence

- **no-durable-state**: This logic MUST NOT write to durable client storage of any kind (see Platform Notes for the test asserting nothing is written); the only board storage is an in-memory cache.
- **server-removal-propagates**: A problem absent from the next server read MUST be absent from the returned board after that read, with no client-side accumulation.
- **no-derivation**: This logic MUST NOT derive, merge or filter board contents; all content derivation belongs to the server.
- **render-thread**: All verdict computation MUST run synchronously each time this logic runs, without interleaving; the live-frame callback, the poll timer and the clock-refresh interval MUST only schedule state updates, never running concurrently with the computation itself (see Platform Notes).
- **response-shape-precondition**: This logic MUST treat the response body's conformance to the board shape as a caller precondition: the body is cast, not validated (see Platform Notes for how the shape is kept in step with the server's type).

## Appearance

Not applicable — this logic fetches and judges the board, not a visual component.

## States

Not applicable — this logic has a runtime availability verdict (listed under Behavioral Requirements), not a visual component.

## Accessibility

Not applicable — this logic has no rendered output, not a visual component.

## Conformance Test Vectors

All vectors run this logic under a fresh shared cache with the live-frame feed mocked and the network stubbed (see Platform Notes). "Fresh" below means `generatedAt` = now and `dataAsOfMs` = now; `probeIntervalMs` is 60,000.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-board-001 | fetch-body-passthrough, verdict-current, reason-board-exclusive | Server returns a fresh board with one problem | `board` deep-equals the server payload; `reason` null (see Platform Notes) |
| use-board-002 | no-durable-state | Fresh board fetched successfully | No durable storage write occurs after `board` is non-null |
| use-board-003 | server-removal-propagates, refetch-field | First read has 1 problem; server switched to `problems: []`, `indicator: "operational"`; caller invokes `refetch` | `board.problems` becomes `[]` |
| use-board-004 | frame-subscription, frame-no-second-connection | This logic is active and the first fetch is done; every registered frame subscriber is invoked once | The network has been called exactly 2 times; no separate streaming connection is created |
| use-board-005 | verdict-stale, stale-threshold, error-independent-of-board | Server returns 200 with `generatedAt` = now − 180,000 ms − 5,000 ms | `board` null; `reason` `"stale"`; `error` null |
| use-board-006 | verdict-frozen, frozen-threshold, frozen-server-clock | Server returns fresh `generatedAt`, `dataAsOfMs` = now − the default data-staleness window − 5,000 ms, green indicator, no problems | `board` null; `reason` `"frozen"` (not `"stale"`); `error` null |
| use-board-007 | verdict-no-data | Server returns fresh `generatedAt`, `dataAsOfMs: null` | `board` null; `reason` `"no-data"` |
| use-board-008 | verdict-current | Server returns fresh `generatedAt`, `dataAsOfMs` = now − 1,000 ms, `indicator: "operational"` | `reason` null; `board.indicator` `"operational"` |
| use-board-009 | verdict-loading, single-loading-signal | The network is stubbed with a request that never resolves; read result immediately after this logic becomes active | `board` null; `reason` `"loading"`; the result carries no separate loading flag |
| use-board-010 | fetch-http-error, verdict-unavailable, error-field, retry-once | The network always returns status 500; wait for the read to settle | The network is called 2 times (initial + one retry); `board` null; `reason` `"unavailable"`; `error.message` is `board fetch failed: 500` |
| use-board-011 | fetch-request, query-key | This logic becomes active | The first network call has URL `/api/board` and headers `{ accept: "application/json" }` |
| use-board-012 | stale-unparseable-clock | Server returns `generatedAt: "not-a-date"`, `dataAsOfMs` = now | `board` null; `reason` `"stale"` |
| use-board-013 | stale-over-frozen | Server returns `generatedAt` = now − 200,000 ms, `dataAsOfMs` = now − 900,000 ms | `reason` `"stale"` |
| use-board-014 | frozen-threshold | Not stale; `probeIntervalMs` 3,600,000; lag between `generatedAt` and `dataAsOfMs` = 30,000,000 ms | `reason` null (window is 36,000,000 ms); with lag 36,000,001 ms, `reason` `"frozen"` |
| use-board-015 | fetch-parse-error, verdict-unavailable | The network returns status 200 with body `not json` on every call | `board` null; `reason` `"unavailable"`; `error` is a parse error |
| use-board-016 | frame-unsubscribe | This logic becomes active, then is torn down | the mocked frame subscriber set no longer contains its callback |
| use-board-017 | retained-data-ages-out | First read returns a fresh board; every later read returns 500; advance the clock past `generatedAt` + 180,000 ms + 30,000 ms | `board` null; `reason` `"stale"`; `error` non-null |

Vectors 001–008, 009–011 and 015–017 are derived from the implementation's test suite; 012–014 are derived from the staleness component's own rules (see Platform Notes).

## Edge Cases

- **Empty cache, request pending**: MUST report `board: null, reason: "loading"`.
- **Empty cache, request failed twice**: MUST report `board: null, reason: "unavailable"` with `error` set; the poll keeps retrying every 60 seconds.
- **Unreachable server (network error)**: The rejected fetch MUST surface through `error` after one retry; with no cached board `reason` is `"unavailable"`, and with a cached board the verdict continues to judge that board until it goes stale.
- **Browser offline**: The underlying fetch layer pauses the request (paused, not actively fetching) rather than erroring, so with no cached board `reason` MUST be `"unavailable"`, not `"loading"`.
- **Permanently failing `/api/board` after a success**: The last good board MUST remain the judged data and MUST read `"stale"` once older than the 180,000 ms threshold; it MUST NOT be reported as current forever.
- **Wedged monitor, healthy API**: A board re-stamped with a fresh `generatedAt` over an old `dataAsOfMs` MUST read `"frozen"`.
- **Nothing configured to observe**: `dataAsOfMs: null` MUST read `"no-data"`, never a green board; distinguishing a fresh install from a broken monitor is left to the consumer (for example the overview view pairing it with the live snapshot's blind indicator).
- **Unparseable `generatedAt`**: MUST read `"stale"` (fail closed in the staleness check).
- **Missing `dataAsOfMs` field (undefined rather than null)**: The exact-equals-null check does not match, the lag is not a number, and the data clock MUST read `"frozen"`.
- **Missing `probeIntervalMs`**: The data-staleness window function MUST fall back to the widest window, `300000 × 2` = 600,000 ms, so an unknown cadence can only delay the frozen verdict.
- **Boundary at exactly the read-clock threshold**: An age equal to 180,000 ms MUST NOT be stale (the comparison is strictly greater than).
- **Boundary at exactly the data window**: A lag equal to the data-staleness window for `probeIntervalMs` MUST read `"current"`.
- **Client clock skew**: A client clock running more than the 180,000 ms threshold fast MUST false-trip a healthy board to `"stale"`; one running more than that threshold slow masks a stale board. This exposure is accepted and uncorrected (per the staleness component's own documentation, see Platform Notes); the data-clock check is immune because it uses only server timestamps.
- **Burst of live frames**: Each frame MUST trigger a refetch; an in-flight read is cancelled and replaced, so a burst of N frames produces up to N requests with only the last completing.
- **Several callers active at once**: Callers sharing a cache MUST share one cached board and one poll; each active caller adds its own frame subscriber, so one frame calls `refetch` once per active caller, and the cancel-and-refetch behavior (see Platform Notes) leaves one read completing.
- **Concurrent access**: Not applicable beyond the burst cases above — this logic runs without concurrent execution, so callbacks cannot interleave with the verdict computation (see Platform Notes).
- **Malformed but parseable body**: A JSON body that does not match the board shape is passed through unvalidated; only the three clock fields are checked, and they fail closed (`"stale"` or `"frozen"`) when unparseable. Conformance of the rest is the server's contract, guarded at compile time (see Platform Notes).
- **Hung request**: No client timeout exists; the request stays in flight until the transport ends it or a frame-triggered refetch cancels it. With a cached board, the verdict still ages the board to `"stale"` because it is judged from the current time, not from request completion.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| API client | injected dependency | same-origin client with base path `/api` | Resolves `/board` against the host's base path; a test double can be injected |
| Shared cache | injected dependency | none (required) | Holds the `["board"]` cache; callers sharing it share one board |
| Poll interval | constant (ms) | `60000` | Poll cadence |
| Read-clock staleness threshold | constant (ms) | `180000` | 3 × poll cadence |
| Data-clock stale-cycle multiplier | constant | `2` | Multiplier on the snapshot-staleness window for the data-clock window |
| Snapshot-staleness floor | constant (ms) | `300000` | Floor of the snapshot-staleness window, and the window used when `probeIntervalMs` is missing |
| Retry count | number | `1` | Retries before an error is reported |
| Client clock refresh interval | number (ms) | `30000` | Client clock refresh used for the read-clock check (default, not overridden by this logic) |
| `probeIntervalMs` | server-supplied field | — | Cadence that scales the data-clock window, taken from the board being judged |

## Deep Linking

Not applicable: this logic has no route or URL of its own; it only requests the `/board` API path.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded) | `board fetch failed: <status>` | `Error.message` of a non-OK board response, exposed on the returned `error` field; a hardcoded English string with no localization lookup |

The reason values are machine identifiers, not display strings; consumers word their own per-cause messages.

## Accessibility Options

Not applicable: this logic renders nothing and responds to no display settings.

## Feature Flags

Not applicable: the source reads no feature flag; this logic is always active where it is called.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: this logic attaches no credentials or identifiers to its request, sends no request body, and persists nothing on the client (see Platform Notes for the test asserting this); the board is held only in an in-memory cache for the page's lifetime.

## Logging

Not applicable: this logic contains no log calls; failures surface only through `error` and `reason`.

## Platform Notes

- **SwiftUI**: Model it as an `@Observable` `@MainActor` class exposing `board: Board?`, `reason: BoardUnavailableReason?` (a `String`-backed enum), `error: Error?` and `refetch()`. Fetch with `URLSession.shared.data(for:)` and decode with `JSONDecoder` (unlike the source, decoding validates shape and throws on mismatch). Drive the poll with a `Task` loop using `Task.sleep(for: .seconds(60))`, and the live-frame refetch with an `AsyncStream` subscription. Recompute the verdict from a stored `nowMs` refreshed by a 30 s `Timer.publish` or `TimelineView(.periodic)`. There is no React Query, so the single-retry, in-flight cancellation and cross-view sharing must be written explicitly (for example one shared store in the environment).
- **Compose**: A `ViewModel` exposing `StateFlow<BoardResult>`; poll with a `viewModelScope` coroutine using `delay(60_000)`, fetch with Ktor or Retrofit plus `kotlinx.serialization`, and model the reason as a `sealed interface` or `enum class`. Combine the fetched board flow with a ticking `nowMs` flow (`flow { while (true) { emit(System.currentTimeMillis()); delay(30_000) } }`) via `combine` so the verdict re-evaluates as time passes. Cancel the previous fetch `Job` on each live frame to mirror `cancelRefetch`.
- **React/Web**: Source platform. `hooks/use-board.ts` uses `@tanstack/react-query` v5 `useQuery` (key `["board"]`, `refetchInterval`, `retry: 1`) and relies on its retention of the last successful `data` across failures, which is why the verdict must re-judge `data` on every render. `subscribeLiveFrames` comes from `hooks/use-live-snapshot.ts` (its `frameSubscribers` set is module-wide, per its own comment), `useNow` from `hooks/use-now.ts`, and the rules from `lib/board-staleness.ts` (itself built on `lib/snapshot-staleness.ts`). `Board` is a hand mirror of the server type in `lib/board-types.ts`, kept in step by the compile-time drift guard in `board-types-parity.test.ts`. React's single-threaded render pass is what guarantees verdict computation cannot interleave with the scheduled callbacks. `use-board.dom.test.tsx` is the test suite behind the conformance vectors above; it also asserts nothing is written to `localStorage`. React Query's default `cancelRefetch` behavior is what cancels an in-flight board read when a new one starts.
- **AppKit / UIKit**: The same `@MainActor` store as SwiftUI, observed through `withObservationTracking` or Combine `@Published`; use `URLSession` with `JSONDecoder`, and drive the poll and 30 s clock with `Timer.scheduledTimer` or a `Task` loop. There is no render pass to recompute from, so recompute the verdict when the board, the error or the clock tick changes and push the result to observers.
- **WinUI 3**: Implement a `BoardStore` class implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject` with `[ObservableProperty]`) exposing `Board? Board`, `BoardUnavailableReason? Reason`, `Exception? Error` and a `RefetchCommand` (`IAsyncRelayCommand`). Fetch with a shared `HttpClient.GetAsync("board")` against a `BaseAddress` of the host's API base, checking `IsSuccessStatusCode` and throwing `new HttpRequestException($"board fetch failed: {(int)status}")`, and deserialize with `System.Text.Json` `JsonSerializer.DeserializeAsync<Board>` (which, unlike the source's cast, fails on type mismatch but still tolerates missing properties unless `JsonRequired` is set). Poll with `PeriodicTimer(TimeSpan.FromSeconds(60))` in an `async Task` loop, and keep a `CancellationTokenSource` per request so each live frame calls `Cancel()` on the in-flight read before starting a new one. Tick the client clock with a `DispatcherQueueTimer` (`Interval = 30s`) on the UI thread and recompute `Reason` on every tick and every fetch completion, raising `PropertyChanged` for `Board` and `Reason` together; there is no React Query, so the one-retry policy, retention of the last good board and sharing across pages (register `BoardStore` as a singleton in `Microsoft.Extensions.DependencyInjection`) are all explicit. Marshal results back with `DispatcherQueue.TryEnqueue` if fetching off the UI thread. Model `BoardUnavailableReason` as a C# `enum` and map it to per-cause text in the view (for example with `x:Bind` to a converter), never to a boolean `IsLoading`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-board.ts` |

## Design Decisions

**Decision**: Fold read staleness, data freezing and absent observations into `board === null` inside the hook, instead of leaving `isBoardStale` for each consumer to call.
**Rationale**: Per "Fix Round 3 item 1", three separate rounds produced the same bug: a consumer checked `board === null` but not staleness and rendered a confident verdict off a frozen read. Making null mean "cannot back a current claim" gives every consumer the right answer by construction.
**Approved**: pending

**Decision**: Keep `stale`, `frozen` and `no-data` as distinct reasons even though all three produce a null board.
**Rationale**: Per the `BoardUnavailableReason` doc comment, they send a human to different places (the API, the monitor process, the config); `no-data` was split out ("Fix Round 2 item C3") because it is the normal state of a roster with nothing to observe and was misreported as a wedged monitor.
**Approved**: pending

**Decision**: Expose no `isLoading` flag; `reason === "loading"` is the only loading signal.
**Rationale**: A second way to ask the same question is the shape that caused the three-round bug above (doc comment on `reason`).
**Approved**: pending

**Decision**: Retry a failed read once (`retry: 1`) instead of React Query's default three retries with backoff.
**Rationale**: Per "Fix Round 2 item 5", the board already polls every 60 s, so extra retries only delay surfacing a down backend behind a longer spinner; one retry absorbs a single transient blip, and it matches the sibling `useLiveSnapshot` feed that gates the same loading screen.
**Approved**: pending

**Decision**: Judge the read clock against the client clock but the data clock server-against-server, using the cadence carried on the board being judged.
**Rationale**: The client clock keeps moving when every server feed has died, which is the failure the read check exists to catch; the data check compares two server timestamps so it is immune to client skew and throttled timers. The cadence used to come from the live-snapshot singleton, which was null for consumers that never open the SSE stream and silently widened the window ("One board, one answer").
**Approved**: pending

**Decision**: Hold no durable client state (no `localStorage`).
**Rationale**: Per the `useBoard` doc comment, a durable client store let a fixed problem survive in one browser tab forever, because a server-side fix could not reach into the tab's saved state.
**Approved**: pending

**Decision**: Use live frames as the fast path and the 60 s poll as the floor, without opening a second connection.
**Rationale**: The board and the snapshot change at the same moments and "one connection per tab is the existing contract" (`subscribeLiveFrames` doc comment); the poll keeps the board updating when the stream is down.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

**Unit Test Coverage**: `use-board.dom.test.tsx` covers verbatim pass-through, the absence of `localStorage` writes, server-side removal propagating, live-frame refetch, the `stale`, `frozen` and `no-data` verdicts, the fresh-board pass-through, and agreement between `usePortfolioIndicator` and `GlobalPanel` on a stale or wedged board. `board-staleness.test.ts` covers the threshold functions. The initial-load, HTTP-error and retry paths are not asserted by the hook's own tests.

**Separation of Concerns**: Transport sits behind `StatusApiClient`, caching and polling behind React Query, the staleness rules and thresholds in `lib/board-staleness.ts`, and the clock in `useNow`; the hook only composes them and applies the verdict in one place.

**Explicit Error Handling**: HTTP failures throw a descriptive `Error`, parse failures propagate, and both surface through `error` and `reason: "unavailable"`; nothing is swallowed.

**Graceful Degradation**: When the stream is down the poll keeps the board current; when the API or the monitor fails the hook degrades to `board: null` with a cause instead of showing a retained verdict as current.

**Timeout Handling**: The hook sets no request timeout. A hung read does not leave a stale verdict on screen because the verdict is clock-driven, but the request itself is bounded only by the transport or a later cancel.

**Data Integrity**: The three clock fields are checked and fail closed, but the rest of the response body is cast to `Board` without runtime validation; shape conformance relies on the server contract and the compile-time drift guard in `board-types-parity.test.ts`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `use-board.ts` |
