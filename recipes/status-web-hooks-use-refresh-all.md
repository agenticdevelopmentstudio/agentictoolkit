---
id: 87d66a8a-5742-4ae0-91c4-8bb1fd09f9e4
title: useRefreshAll
domain: agentictoolkit://recipes/status-web-hooks-use-refresh-all
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that refetches every enabled react-query query except the live
  snapshot on one shared interval, and exposes a manual refreshAll.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-hooks-use-config-status
- agentictoolkit://recipes/status-web-hooks-use-live-snapshot
references: []
approved-by: ''
approved-date: ''
---

# useRefreshAll

## Overview

`useRefreshAll` (`hooks/use-refresh-all.ts` in the status web app) keeps the dashboard's supporting datasets — uptime, integrations, response history and every other cached query — on one shared refresh tick. Its doc comment states the goal: refresh them "together on one shared interval, so the dashboard never shows a mix of fresh + stale datasets."

On each tick it asks the host `QueryClient` to refetch every cached query except two groups:

- **The live snapshot** (any query whose key starts with `"live"`). The doc comment explains that the live query "drives itself on its own refetchInterval (use-live-snapshot) — refetching it here too would double the provider fan-out to two polls per minute per client."
- **Disabled queries** (`q.isDisabled()`). The inline comment says an observer with `enabled: false` "opted OUT of fetching — refetching it here would undo that gate every 60s."

The hook returns `{ refreshAll }` so a caller can trigger the same refresh on demand. Its one caller, `BoardShell`, mounts it as `useRefreshAll(60_000)` and ignores the return value.

## Behavioral Requirements

### Signature and return value

- **signature**: The module MUST export `useRefreshAll(intervalMs?: number): { refreshAll: () => void }`.
- **interval-default**: When called with no argument, `intervalMs` MUST default to `60_000` (60 seconds).
- **return-shape**: The hook MUST return an object with exactly one member, `refreshAll`, a zero-argument function returning `void`.
- **refresh-all-stable**: The `refreshAll` function identity MUST stay the same across renders for as long as the `QueryClient` from `useQueryClient()` stays the same. It is memoized on `[queryClient]` only.
- **return-object-fresh**: The hook MUST return a new wrapper object on every render. Only `refreshAll` inside it is memoized.

### Refresh selection

- **refetch-call**: Each invocation of `refreshAll` MUST call `queryClient.refetchQueries` exactly once, passing a `predicate` filter and no other filter or options.
- **live-excluded**: The predicate MUST reject every query whose `queryKey[0]` is strictly equal to the string `"live"`. This includes keys with more elements, such as `["live", "x"]`.
- **live-prefix-only**: The live exclusion MUST compare only the first key element. A key such as `["live-history"]` or `["history", "live"]` MUST NOT be excluded.
- **disabled-excluded**: The predicate MUST reject every query for which `q.isDisabled()` returns `true`.
- **others-included**: The predicate MUST accept every other query in the cache, whatever its key.
- **no-key-list**: The hook MUST NOT hold a list of the datasets it refreshes. Which queries get refetched depends only on what is in the `QueryClient` cache at the moment of the call.
- **disabled-means-no-enabled-observer**: The disabled test MUST be react-query's own `Query.isDisabled()`. `BoardShell`'s comment records that it "is false while ANY observer is enabled", so one enabled observer on a key makes that query refreshable even if other observers on the same key have `enabled: false`.
- **inactive-queries-eligible**: The hook MUST NOT restrict refetching to queries that are currently observed. It passes no `type` filter, so it uses the `QueryClient` default. Under `@tanstack/react-query` v5 (`^5.62.0` in `package.json`), that default selects all queries, including cached queries with no mounted observer that have fetched before and are still inside their garbage-collection window. That behavior belongs to react-query, not to this hook.

### Fire-and-forget and errors

- **fire-and-forget**: `refreshAll` MUST discard the promise returned by `refetchQueries` (`void`). It MUST return synchronously, before any refetch settles.
- **no-await-no-signal**: `refreshAll` MUST NOT tell its caller whether a refetch succeeded or failed.
- **errors-land-on-queries**: A refetch failure MUST show up only in the failing query's own cache state (its `error` and `status`), where that query's observers read it. The hook passes no `throwOnError`, so react-query v5 resolves the aggregate `refetchQueries` promise even when an individual query fails. No unhandled rejection reaches the page.
- **independent-completion**: The refetches MUST start in the same `refetchQueries` call, but each one settles on its own schedule. The hook MUST NOT hold back results until all refetches finish, and it MUST NOT roll back a query whose refetch succeeded when another query's refetch fails.
- **in-flight-restart**: The hook MUST NOT override react-query's `cancelRefetch` default. Under react-query v5 that default is `true` for `refetchQueries`, so a query that is already fetching when a tick fires has that fetch cancelled and restarted. That behavior belongs to react-query.

### Interval lifecycle

- **interval-start**: On mount the hook MUST schedule `refreshAll` on a repeating timer every `intervalMs` milliseconds (`setInterval`).
- **no-immediate-refresh**: The hook MUST NOT call `refreshAll` on mount. The first automatic refresh MUST happen `intervalMs` after the effect runs.
- **interval-cleanup**: On unmount the hook MUST cancel its timer (`clearInterval`), and no further automatic refresh MUST fire from that mount.
- **interval-restart-on-change**: When `intervalMs` or `refreshAll`'s identity (and therefore the `QueryClient`) changes, the hook MUST cancel the old timer and start a new one with the new values, which resets the tick phase.
- **one-timer-per-mount**: Each mounted instance MUST own exactly one timer. Two mounts under the same `QueryClient` run two independent timers, and the hook does nothing to coordinate or deduplicate them.
- **no-visibility-pause**: The hook MUST NOT pause its timer when the page is hidden or offline. Any background-tab throttling comes from the browser's timer policy, not from this hook.
- **no-input-validation**: The hook MUST pass `intervalMs` to `setInterval` unchanged, with no range check.

### Concurrency and side effects

- **single-threaded**: The hook runs on the browser's single JavaScript thread. `refreshAll` calls and timer ticks cannot interleave. Each call finishes selecting and starting its refetches before the next begins.
- **side-effects**: The hook's only side effects MUST be its one timer and the refetches it asks the `QueryClient` to start. It MUST NOT write storage, log, emit analytics or perform network I/O directly. Every network request comes from the refetched queries' own query functions.
- **client-only**: The module MUST be a client module (`"use client"`), since it uses React hooks and the react-query cache.
- **query-client-required**: The hook MUST be rendered inside a `QueryClientProvider`. `useQueryClient()` throws when there is none (react-query's contract).

## Appearance

Not applicable — this is a React timer hook that drives cache refetches, not a visual component.

## States

Not applicable — this is a React timer hook that drives cache refetches, not a visual component.

## Accessibility

Not applicable — this is a React timer hook that drives cache refetches, not a visual component.

## Conformance Test Vectors

The source has no test file for this hook (no `use-refresh-all.*test*` exists next to it). These vectors come from `hooks/use-refresh-all.ts` and are meant for a test that renders the hook under a `QueryClientProvider` with fake timers.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| refresh-all-001 | interval-default, interval-start, no-immediate-refresh | Render `useRefreshAll()` with a spied `refetchQueries`; advance fake timers by 59,999 ms, then by 1 ms | Zero calls after 59,999 ms; exactly one call at 60,000 ms |
| refresh-all-002 | interval-start | Render `useRefreshAll(1_000)`; advance timers by 3,000 ms | `refetchQueries` called exactly 3 times |
| refresh-all-003 | live-excluded, others-included | Cache holds enabled, fetched queries `["live"]`, `["live", "x"]`, `["uptime"]` and `["integrations"]`; call `refreshAll()` | `["uptime"]` and `["integrations"]` query functions each run once; neither `["live"]` query function runs |
| refresh-all-004 | live-prefix-only | Cache holds enabled queries `["live-history"]` and `["history", "live"]`; call `refreshAll()` | Both query functions run once |
| refresh-all-005 | disabled-excluded | Cache holds `["config-status"]` whose only observer has `enabled: false`; call `refreshAll()` | Its query function does not run |
| refresh-all-006 | disabled-means-no-enabled-observer | `["configure-data"]` has one observer with `enabled: false` and one with `enabled: true`; call `refreshAll()` | Its query function runs once |
| refresh-all-007 | fire-and-forget, errors-land-on-queries | `["uptime"]` query function rejects with `Error("boom")`; call `refreshAll()` | `refreshAll()` returns `undefined` synchronously; after settling, the `["uptime"]` query state has `status: "error"` and `error.message === "boom"`; no unhandled rejection |
| refresh-all-008 | independent-completion | `["a"]` resolves `1`, `["b"]` rejects; call `refreshAll()` | Query `["a"]` data becomes `1` even though `["b"]` ends in `status: "error"` |
| refresh-all-009 | interval-cleanup | Render `useRefreshAll(1_000)`, unmount, advance timers by 5,000 ms | `refetchQueries` called zero times after unmount |
| refresh-all-010 | interval-restart-on-change | Render with `intervalMs = 1_000`; advance 500 ms; rerender with `intervalMs = 2_000`; advance 1,999 ms, then 1 ms | No call before the rerender and none during the 1,999 ms; exactly one call at 2,000 ms after the rerender |
| refresh-all-011 | refresh-all-stable, return-object-fresh | Rerender twice with the same `QueryClient` | `result.refreshAll` is the same reference each time; the wrapper objects are different references |
| refresh-all-012 | refetch-call | Call `refreshAll()` once | `refetchQueries` called once with one argument, an object whose only key is `predicate` |
| refresh-all-013 | one-timer-per-mount | Render two instances of `useRefreshAll(1_000)` under one `QueryClient`; advance 1,000 ms | `refetchQueries` called twice |

## Edge Cases

- **Empty cache**: With no queries in the `QueryClient`, `refreshAll` MUST still call `refetchQueries`. That call refetches nothing and resolves.
- **Only the live query cached**: `refreshAll` MUST refetch nothing. The live query keeps its own cadence, set by `use-live-snapshot` (`refetchInterval: streamConnected ? false : POLL_INTERVAL_MS`).
- **Empty query key**: For a query with key `[]`, `queryKey[0]` is `undefined`, so that query MUST NOT be excluded as live. It is refetched if it is not disabled.
- **Non-string first key element**: The comparison is strict (`!==`), so a first element that is not the string `"live"` (for example a number or an object) MUST NOT be excluded.
- **`intervalMs` of 0, negative or `NaN`**: Passed to `setInterval` unchanged. Browsers treat these as a zero delay, clamped to their minimum timer interval (about 4 ms once nested), so the hook MUST then fire refreshes continuously. The only caller passes `60_000`. The value is a caller precondition set by the `number` signature and that call site.
- **Very large `intervalMs`**: A value above 2,147,483,647 ms overflows the browser's 32-bit timer delay and fires almost immediately. The hook does not guard against this, and MUST pass the value through unchanged.
- **Tick during an in-flight fetch**: react-query cancels the running fetch and restarts it (`cancelRefetch` defaults to `true` for `refetchQueries` in v5). The hook MUST NOT add its own deduplication.
- **Refetch failure / unreachable server / offline**: Each failing query records its error in its own cache state, and the hook MUST NOT surface, retry or log it. Retries follow the host `QueryClient` defaults. While offline, react-query's network mode may pause fetches. That behavior belongs to react-query.
- **Background tab**: The timer keeps running, subject to browser throttling. The hook MUST NOT skip or delay ticks itself.
- **Unmount mid-refetch**: Refetches already started keep running and still update the cache. Unmount only stops future ticks (MUST, as implemented).
- **Cancellation and timeout**: The hook has no cancellation or timeout of its own. Timeouts, if any, belong to each query function and its transport.
- **`QueryClient` swapped**: A new client changes `refreshAll`'s identity, so the effect restarts the timer against the new client. The old client gets no more ticks from this mount (MUST).
- **Missing provider**: Rendering outside a `QueryClientProvider` MUST throw from `useQueryClient()` during render.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `intervalMs` | `number` | `60_000` | Milliseconds between automatic refreshes. Not validated. `BoardShell` passes `60_000`. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | The cache whose queries are refetched. It also owns retry, network mode and `cancelRefetch` behavior. |
| Live key (hard-coded) | `string` | `"live"` | First key element excluded from refresh. Not configurable. |

## Deep Linking

Not applicable: the hook has no route or URL. It only asks the cache to refetch existing queries.

## Localization

Not applicable: the hook produces no strings, user-facing or otherwise.

## Accessibility Options

Not applicable: the hook renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag. `intervalMs` is a per-call parameter.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: the hook handles no data itself. It only triggers refetches of queries that already exist, and those queries' own recipes cover the data they carry.

## Logging

Not applicable: the source contains no log calls. Refetch outcomes are recorded only in each query's cache state.

## Platform Notes

- **SwiftUI**: Start from a `@MainActor` coordinator that owns a `Task` looping over `try await Task.sleep(for: .milliseconds(intervalMs))` and calling `refresh()` on each registered store, skipping the live store and any store whose consumers have all opted out. Swift has no shared query cache, so the coordinator needs an explicit registry of refreshable stores where the source uses the react-query cache predicate. Cancel the task in `.task` teardown or `deinit` to match `clearInterval`. Launch the per-store refreshes with `withTaskGroup` and do not await the group from the caller, which gives the same fire-and-forget behavior.
- **Compose**: A `ViewModel` (or an app-scoped class) running `viewModelScope.launch { while (isActive) { delay(intervalMs); refreshAll() } }`, where `refreshAll()` calls `launch { repo.refresh() }` for each repository except the live one. `LaunchedEffect(intervalMs)` restarts the loop when the interval changes, matching the effect's dependency array. Errors stay in each repository's `StateFlow`, as they stay on each query in the source.
- **React/Web**: Source platform. `hooks/use-refresh-all.ts` combines `useQueryClient` from `@tanstack/react-query` v5 with `useCallback` and a `useEffect` around `setInterval`. The only caller is `components/BoardShell.tsx` (`useRefreshAll(60_000)`). The excluded live query is owned by `hooks/use-live-snapshot.ts` (`queryKey: ["live"]`, `refetchInterval` gated on the SSE stream). The `isDisabled()` gate matters for `useConfigStatus({ enabled })` consumers.
- **AppKit / UIKit**: Same coordinator as SwiftUI, owned by the window controller or scene delegate. A `Timer.scheduledTimer(withTimeInterval:repeats:)` on the main run loop is the closest match to `setInterval`: invalidate it in `deinit` or on window close, and recreate it when the interval changes.
- **WinUI 3**: Use a `DispatcherQueueTimer` (from `DispatcherQueue.GetForCurrentThread().CreateTimer()`) with `Interval = TimeSpan.FromMilliseconds(intervalMs)` and `IsRepeating = true`. Call `Start()` when the shell page loads and `Stop()` in `Unloaded` to match mount and unmount. There is no react-query cache, so register each data service (`INotifyPropertyChanged` view models backed by one shared `HttpClient` and `System.Text.Json`) in a DI-held `IRefreshable` list with an `IsEnabled` flag and a key. In the `Tick` handler, filter out the live service and disabled services, then start `_ = service.RefreshAsync()` for each one without awaiting, to match `void refetchQueries`. Each service catches its own exceptions and exposes them on an `Error` property, so no unobserved `Task` exception escapes. Unlike react-query, nothing cancels an in-flight refresh when the next tick fires: to match `cancelRefetch`, keep a `CancellationTokenSource` per service, cancel it, and replace it on each tick. Setting `Interval` to a new value takes effect without recreating the timer, while the source restarts its phase.

## Design Decisions

**Decision**: Refresh every supporting query on one shared tick instead of giving each query its own `refetchInterval`.
**Rationale**: The doc comment says the goal is that "the dashboard never shows a mix of fresh + stale datasets". `BoardShell` repeats it: "no staggered, mismatched state." The refetches start together but still finish independently.
**Approved**: pending

**Decision**: Exclude the `"live"` query from the shared tick.
**Rationale**: The live query drives itself through `use-live-snapshot`'s own `refetchInterval`, which stands down while the SSE stream is connected. Refetching it here "would double the provider fan-out to two polls per minute per client."
**Approved**: pending

**Decision**: Skip disabled queries.
**Rationale**: An observer with `enabled: false` "opted OUT of fetching — refetching it here would undo that gate every 60s." Because `isDisabled()` is false while any observer is enabled, `BoardShell` relies on the config-status gate being the role gate only.
**Approved**: pending

**Decision**: Select queries with a predicate over the whole cache instead of a list of keys.
**Rationale**: New datasets join the shared refresh automatically with no edit to this hook. The trade-off is that an unobserved cached query that has fetched before is also refetched until it is garbage-collected (react-query v5 default).
**Approved**: pending

**Decision**: Make `refreshAll` fire-and-forget.
**Rationale**: Results and errors belong to each query's observers. The aggregate promise carries no useful signal, and discarding it with `void` satisfies the no-floating-promise lint.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | partial | performance |

The hook handles only scheduling and query selection. What each dataset fetches and how it reports failure stays with the query that owns it, so separation of concerns passes. There is no test file for the hook, so the timer lifecycle and both exclusion rules are untested, and unit test coverage fails. Error handling passes because failures are not swallowed: react-query records each refetch failure on its own query, where observers read it, and the discarded aggregate promise always resolves. Resource efficiency is partial. The live exclusion and the disabled gate deliberately avoid duplicate provider polls, but the timer keeps running in hidden tabs, each mount runs its own timer, and cached queries with no observer are still refetched.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
