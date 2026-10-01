---
id: 87d66a8a-5742-4ae0-91c4-8bb1fd09f9e4
title: Refresh All
domain: agentictoolkit://cookbook/status/dashboard/state/refresh-all
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: State that refetches every enabled cached read except the live snapshot
  on one shared interval, and exposes a manual refresh-all operation.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/state/config-status
- agentictoolkit://cookbook/status/dashboard/state/live-snapshot
references: []
approved-by: ''
approved-date: ''
---

# Refresh All

## Overview

Refresh All keeps the dashboard's supporting datasets — uptime, integrations, response history and every other cached read — on one shared refresh tick, so the dashboard never shows a mix of fresh and stale datasets.

On each tick it asks the shared cache to refetch every cached read except two groups:

- **Live Snapshot's own cache entry** (any cache key starting with `"live"`). Live Snapshot drives itself on its own refresh interval; refetching it here too would double the provider fan-out to two polls per minute per client.
- **Disabled reads** (those with no enabled observer). An observer that opted out of fetching should not have that gate undone every 60 s by a shared refresh.

Refresh All returns a `refreshAll` function so a caller can trigger the same refresh on demand. Its one caller, the board shell, uses it with a 60,000 ms interval and ignores the return value beyond that function.

## Behavioral Requirements

### Signature and return value

- **signature**: Refresh All MUST take one optional numeric input (the refresh interval in milliseconds) and MUST return an object with a `refreshAll` function that takes no arguments and returns nothing.
- **interval-default**: When called with no argument, the interval MUST default to `60,000` (60 seconds).
- **return-shape**: Refresh All MUST return an object with exactly one member, `refreshAll`, a zero-argument function returning nothing.
- **refresh-all-stable**: The `refreshAll` function MUST keep a stable identity for as long as the shared cache context stays the same.
- **return-object-fresh**: Refresh All MUST return a new wrapper object each time it is used. Only `refreshAll` inside it keeps a stable identity.

### Refresh selection

- **refetch-call**: Each invocation of `refreshAll` MUST trigger a refetch of matching cache entries exactly once, using a filter and no other option.
- **live-excluded**: The filter MUST reject every cache entry whose key's first element is exactly the string `"live"`. This includes keys with more elements, such as `["live", "x"]`.
- **live-prefix-only**: The live exclusion MUST compare only the first key element. A key such as `["live-history"]` or `["history", "live"]` MUST NOT be excluded.
- **disabled-excluded**: The filter MUST reject every cache entry that has no enabled observer.
- **others-included**: The filter MUST accept every other cache entry, whatever its key.
- **no-key-list**: Refresh All MUST NOT hold a list of the datasets it refreshes. Which entries get refetched depends only on what is in the shared cache at the moment of the call.
- **disabled-means-no-enabled-observer**: The disabled test MUST be false while any observer of that cache entry is enabled, so one enabled observer on a key makes that entry refreshable even if other observers on the same key are individually disabled.
- **inactive-queries-eligible**: Refresh All MUST NOT restrict refetching to entries that are currently observed. It applies no extra filter of its own, so it uses the shared cache's own default, which includes cached entries with no active observer that have fetched before and are still inside their retention window. That behavior belongs to the shared cache, not to Refresh All.

### Fire-and-forget and errors

- **fire-and-forget**: `refreshAll` MUST discard the result of triggering the refetch. It MUST return synchronously, before any refetch settles.
- **no-await-no-signal**: `refreshAll` MUST NOT tell its caller whether a refetch succeeded or failed.
- **errors-land-on-queries**: A refetch failure MUST show up only in the failing entry's own cache state (its error and status), where that entry's observers read it. Refresh All applies no error-throwing option, so the aggregate refresh operation resolves even when an individual entry fails. No unhandled failure reaches the page.
- **independent-completion**: The refetches MUST start in the same refresh operation, but each one settles on its own schedule. Refresh All MUST NOT hold back results until all refetches finish, and it MUST NOT roll back an entry whose refetch succeeded when another entry's refetch fails.
- **in-flight-restart**: Refresh All MUST NOT override the shared cache's default in-flight-restart behavior. Under that default, an entry that is already fetching when a tick fires has that fetch cancelled and restarted. That behavior belongs to the shared cache, not to Refresh All.

### Interval lifecycle

- **interval-start**: Once started, Refresh All MUST schedule `refreshAll` on a repeating timer every `intervalMs` milliseconds.
- **no-immediate-refresh**: Refresh All MUST NOT call `refreshAll` immediately when it starts. The first automatic refresh MUST happen `intervalMs` after it starts running.
- **interval-cleanup**: When the caller stops using it, Refresh All MUST cancel its timer, and no further automatic refresh MUST fire from that use.
- **interval-restart-on-change**: When the interval or the shared cache context changes, Refresh All MUST cancel the old timer and start a new one with the new values, which resets the tick phase.
- **one-timer-per-mount**: Each use MUST own exactly one timer. Two uses sharing the same cache context run two independent timers, and Refresh All does nothing to coordinate or deduplicate them.
- **no-visibility-pause**: Refresh All MUST NOT pause its timer when the app is in the background or offline. Any throttling of a backgrounded timer comes from the environment's own policy, not from Refresh All.
- **no-input-validation**: Refresh All MUST pass the interval to the timer unchanged, with no range check.

### Concurrency and side effects

- **single-threaded**: Refresh All runs on a single execution thread. `refreshAll` calls and timer ticks cannot interleave. Each call finishes selecting and starting its refetches before the next begins.
- **side-effects**: Refresh All's only side effects MUST be its one timer and the refetches it asks the shared cache to start. It MUST NOT write storage, log, emit analytics or perform network I/O directly. Every network request comes from the refetched entries' own read functions.
- **client-only**: Refresh All has no server-only or universal-rendering variant; it requires a live client execution context.
- **cache-context-required**: Refresh All MUST be used only where a shared cache context is available. Accessing the cache context fails when none is available.

## Appearance

Not applicable — this is a timer concept that drives cache refetches, not a visual component.

## States

Not applicable — this is a timer concept that drives cache refetches, not a visual component.

## Accessibility

Not applicable — this is a timer concept that drives cache refetches, not a visual component.

## Conformance Test Vectors

There is no dedicated test file for this concept. The vectors below are derived from the source and assume a shared cache context and a controllable timer.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| refresh-all-001 | interval-default, interval-start, no-immediate-refresh | Start using Refresh All with the default interval, with the refetch operation monitored; advance the timer by 59,999 ms, then by 1 ms more | Zero calls after 59,999 ms; exactly one call at 60,000 ms |
| refresh-all-002 | interval-start | Start using Refresh All with a 1,000 ms interval; advance the timer by 3,000 ms | The refetch operation is triggered exactly 3 times |
| refresh-all-003 | live-excluded, others-included | Cache holds enabled, fetched entries `["live"]`, `["live", "x"]`, `["uptime"]` and `["integrations"]`; call `refreshAll` | The uptime and integrations entries' read functions each run once; neither live entry's read function runs |
| refresh-all-004 | live-prefix-only | Cache holds enabled entries `["live-history"]` and `["history", "live"]`; call `refreshAll` | Both entries' read functions run once |
| refresh-all-005 | disabled-excluded | Cache holds `["config-status"]` whose only observer is disabled; call `refreshAll` | Its read function does not run |
| refresh-all-006 | disabled-means-no-enabled-observer | `["configure-data"]` has one disabled observer and one enabled observer; call `refreshAll` | Its read function runs once |
| refresh-all-007 | fire-and-forget, errors-land-on-queries | The `["uptime"]` entry's read function rejects with an error message `"boom"`; call `refreshAll` | `refreshAll` returns immediately with nothing; after settling, the uptime entry is in an error state with message `"boom"`; no unhandled failure |
| refresh-all-008 | independent-completion | `["a"]` resolves `1`, `["b"]` rejects; call `refreshAll` | Entry `["a"]`'s data becomes `1` even though `["b"]` ends in an error state |
| refresh-all-009 | interval-cleanup | Start using Refresh All with a 1,000 ms interval, stop using it, advance the timer by 5,000 ms | The refetch operation is triggered zero times after that |
| refresh-all-010 | interval-restart-on-change | Start with a 1,000 ms interval; advance 500 ms; change the interval to 2,000 ms; advance 1,999 ms, then 1 ms more | No call before the change and none during the 1,999 ms; exactly one call at 2,000 ms after the change |
| refresh-all-011 | refresh-all-stable, return-object-fresh | Use Refresh All twice with the same cache context | The `refreshAll` reference is the same each time; the wrapper objects are different references |
| refresh-all-012 | refetch-call | Call `refreshAll` once | The refetch operation is triggered once with one argument, an object whose only key is the filter |
| refresh-all-013 | one-timer-per-mount | Use Refresh All twice, each with a 1,000 ms interval, sharing one cache context; advance 1,000 ms | The refetch operation is triggered twice |

## Edge Cases

- **Empty cache**: With no entries in the shared cache, `refreshAll` MUST still trigger a refetch. That call refetches nothing and resolves.
- **Only the live entry cached**: `refreshAll` MUST refetch nothing. Live Snapshot's own cache entry keeps its own cadence, set by Live Snapshot itself.
- **Empty cache key**: For an entry with an empty key, there is no first element to compare, so that entry MUST NOT be excluded as live. It is refetched if it is not disabled.
- **Non-string first key element**: The comparison is exact, so a first element that is not the string `"live"` (for example a number or another kind of value) MUST NOT be excluded.
- **Interval of 0, negative, or not a number**: Passed to the timer unchanged. The environment treats these as a zero delay, clamped to its own minimum timer interval, so Refresh All MUST then fire refreshes continuously. The only caller passes 60,000 ms; the value otherwise is a caller precondition.
- **Very large interval**: A value large enough can overflow a platform's timer-delay representation and fire almost immediately. Refresh All does not guard against this, and MUST pass the value through unchanged.
- **Tick during an in-flight fetch**: The shared cache cancels the running fetch and restarts it, by its own default behavior. Refresh All MUST NOT add its own deduplication.
- **Refetch failure / unreachable server / offline**: Each failing entry records its error in its own cache state, and Refresh All MUST NOT surface, retry or log it. Retries follow the host cache context's defaults. While offline, the shared cache's own network policy may pause fetches. That behavior belongs to the shared cache.
- **Background tab**: The timer keeps running, subject to the environment's own throttling. Refresh All MUST NOT skip or delay ticks itself.
- **Stopping use mid-refetch**: Refetches already started keep running and still update the cache. Stopping use of Refresh All only stops future ticks.
- **Cancellation and timeout**: Refresh All has no cancellation or timeout of its own. Timeouts, if any, belong to each entry's own read function and its transport.
- **Shared cache context swapped**: A new context changes `refreshAll`'s identity, so Refresh All restarts the timer against the new context. The old context gets no more ticks from this use.
- **Missing cache context**: Using Refresh All where no shared cache context is available MUST fail immediately.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Interval | number | `60000` | Milliseconds between automatic refreshes. Not validated. The board shell passes `60,000`. |
| Shared cache context | injected dependency | host-provided | The cache whose entries are refetched. It also owns retry, network policy and in-flight-restart behavior. |
| Live key (hard-coded) | string | `"live"` | First key element excluded from refresh. Not configurable. |

## Deep Linking

Not applicable: Refresh All has no route or URL. It only asks the cache to refetch existing entries.

## Localization

Not applicable: Refresh All produces no strings, user-facing or otherwise.

## Accessibility Options

Not applicable: Refresh All renders nothing, so Reduce Motion, Increase Contrast and Differentiate Without Color have no effect on it.

## Feature Flags

Not applicable: the source reads no feature flag. The interval is a per-use parameter.

## Analytics

Not applicable: the source emits no analytics events.

## Privacy

Not applicable: Refresh All handles no data itself. It only triggers refetches of entries that already exist, and those entries' own recipes cover the data they carry.

## Logging

Not applicable: the source contains no log calls. Refetch outcomes are recorded only in each entry's cache state.

## Platform Notes

- **SwiftUI**: Start from a `@MainActor` coordinator that owns a `Task` looping over `try await Task.sleep(for: .milliseconds(intervalMs))` and calling `refresh()` on each registered store, skipping the live store and any store whose consumers have all opted out. Swift has no shared query cache, so the coordinator needs an explicit registry of refreshable stores where the source uses the cache's own filter predicate. Cancel the task in `.task` teardown or `deinit` to match the interval cleanup. Launch the per-store refreshes with `withTaskGroup` and do not await the group from the caller, which gives the same fire-and-forget behavior.
- **Compose**: A `ViewModel` (or an app-scoped class) running `viewModelScope.launch { while (isActive) { delay(intervalMs); refreshAll() } }`, where `refreshAll()` calls `launch { repo.refresh() }` for each repository except the live one. `LaunchedEffect(intervalMs)` restarts the loop when the interval changes, matching the source's effect dependency array. Errors stay in each repository's `StateFlow`, as they stay on each entry in the source.
- **React/Web**: Source platform. `hooks/use-refresh-all.ts` combines `useQueryClient` from `@tanstack/react-query` v5 (`^5.62.0` in `package.json`) with `useCallback` and a `useEffect` around `setInterval`/`clearInterval`. The only caller is `components/BoardShell.tsx` (`useRefreshAll(60_000)`). The excluded live query is owned by `hooks/use-live-snapshot.ts` (`queryKey: ["live"]`, `refetchInterval: streamConnected ? false : POLL_INTERVAL_MS`). The disabled test is react-query's own `Query.isDisabled()`, which matters for `useConfigStatus({ enabled })` consumers. The in-flight-restart default is react-query v5's `cancelRefetch: true` for `refetchQueries`. Browser timers clamp a zero or negative delay to about 4 ms once nested, and a delay above 2,147,483,647 ms overflows the 32-bit timer representation and fires almost immediately. There is no `use-refresh-all.*test*` file next to the source.
- **AppKit / UIKit**: Same coordinator as SwiftUI, owned by the window controller or scene delegate. A `Timer.scheduledTimer(withTimeInterval:repeats:)` on the main run loop is the closest match to a repeating interval timer: invalidate it in `deinit` or on window close, and recreate it when the interval changes.
- **WinUI 3**: Use a `DispatcherQueueTimer` (from `DispatcherQueue.GetForCurrentThread().CreateTimer()`) with `Interval = TimeSpan.FromMilliseconds(intervalMs)` and `IsRepeating = true`. Call `Start()` when the shell page loads and `Stop()` in `Unloaded` to match starting and stopping use. There is no shared query cache, so register each data service (`INotifyPropertyChanged` view models backed by one shared `HttpClient` and `System.Text.Json`) in a DI-held `IRefreshable` list with an `IsEnabled` flag and a key. In the `Tick` handler, filter out the live service and disabled services, then start `_ = service.RefreshAsync()` for each one without awaiting, to match the fire-and-forget behavior. Each service catches its own exceptions and exposes them on an `Error` property, so no unobserved `Task` exception escapes. Unlike the shared cache, nothing cancels an in-flight refresh when the next tick fires: to match the in-flight-restart behavior, keep a `CancellationTokenSource` per service, cancel it, and replace it on each tick. Setting `Interval` to a new value takes effect without recreating the timer, while the source restarts its phase.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-refresh-all.ts` |

## Design Decisions

**Decision**: Refresh every supporting dataset on one shared tick instead of giving each one its own refresh interval.
**Rationale**: The goal is that the dashboard never shows a mix of fresh and stale datasets — no staggered, mismatched state. The refetches start together but still finish independently.
**Approved**: pending

**Decision**: Exclude the live entry from the shared tick.
**Rationale**: The live entry drives itself through Live Snapshot's own refresh interval, which stands down while its stream is connected. Refetching it here too would double the provider fan-out to two polls per minute per client.
**Approved**: pending

**Decision**: Skip disabled reads.
**Rationale**: An observer that opted out of fetching should not have that gate undone every 60 s. Because the disabled test is false while any observer is enabled, a role-gated caller relies on that gate being the deciding one.
**Approved**: pending

**Decision**: Select entries with a filter over the whole cache instead of a list of keys.
**Rationale**: New datasets join the shared refresh automatically with no edit to Refresh All. The trade-off is that an unobserved cached entry that has fetched before is also refetched until it leaves its retention window.
**Approved**: pending

**Decision**: Make `refreshAll` fire-and-forget.
**Rationale**: Results and errors belong to each entry's observers. The aggregate result carries no useful signal, and discarding it satisfies a no-floating-result lint rule on the source platform.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/state/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
</content>
