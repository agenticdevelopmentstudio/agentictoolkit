<!-- leaf: implement-status-web-hooks/use-refresh-all · source: status-web-hooks-use-refresh-all.md -->

**Rules** (cite as `implement-status-web-hooks/use-refresh-all#<slug>`):

- `signature` MUST
- `interval-default` MUST
- `return-shape` MUST
- `refresh-all-stable` MUST
- `return-object-fresh` MUST
- `refetch-call` MUST
- `live-excluded` MUST
- `live-prefix-only` MUST
- `disabled-excluded` MUST
- `others-included` MUST
- `no-key-list` MUST
- `disabled-means-no-enabled-observer` MUST
- `inactive-queries-eligible` MUST
- `fire-and-forget` MUST
- `no-await-no-signal` MUST
- `errors-land-on-queries` MUST
- `independent-completion` MUST
- `in-flight-restart` MUST
- `interval-start` MUST
- `no-immediate-refresh` MUST
- `interval-cleanup` MUST
- `interval-restart-on-change` MUST
- `one-timer-per-mount` MUST
- `no-visibility-pause` MUST
- `no-input-validation` MUST
- `side-effects` MUST
- `client-only` MUST
- `query-client-required` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `intervalMs` | `number` | `60_000` | Milliseconds between automatic refreshes. Not validated. `BoardShell` passes `60_000`. |
| `QueryClient` (injected) | `QueryClient` | host `QueryClientProvider` | The cache whose queries are refetched. It also owns retry, network mode and `cancelRefetch` behavior. |
| Live key (hard-coded) | `string` | `"live"` | First key element excluded from refresh. Not configurable. |

## Platform Notes

- **SwiftUI**: Start from a `@MainActor` coordinator that owns a `Task` looping over `try await Task.sleep(for: .milliseconds(intervalMs))` and calling `refresh()` on each registered store, skipping the live store and any store whose consumers have all opted out. Swift has no shared query cache, so the coordinator needs an explicit registry of refreshable stores where the source uses the react-query cache predicate. Cancel the task in `.task` teardown or `deinit` to match `clearInterval`. Launch the per-store refreshes with `withTaskGroup` and do not await the group from the caller, which gives the same fire-and-forget behavior.
- **Compose**: A `ViewModel` (or an app-scoped class) running `viewModelScope.launch { while (isActive) { delay(intervalMs); refreshAll() } }`, where `refreshAll()` calls `launch { repo.refresh() }` for each repository except the live one. `LaunchedEffect(intervalMs)` restarts the loop when the interval changes, matching the effect's dependency array. Errors stay in each repository's `StateFlow`, as they stay on each query in the source.
- **React/Web**: Source platform. `hooks/use-refresh-all.ts` combines `useQueryClient` from `@tanstack/react-query` v5 with `useCallback` and a `useEffect` around `setInterval`. The only caller is `components/BoardShell.tsx` (`useRefreshAll(60_000)`). The excluded live query is owned by `hooks/use-live-snapshot.ts` (`queryKey: ["live"]`, `refetchInterval` gated on the SSE stream). The `isDisabled()` gate matters for `useConfigStatus({ enabled })` consumers.
- **AppKit / UIKit**: Same coordinator as SwiftUI, owned by the window controller or scene delegate. A `Timer.scheduledTimer(withTimeInterval:repeats:)` on the main run loop is the closest match to `setInterval`: invalidate it in `deinit` or on window close, and recreate it when the interval changes.
- **WinUI 3**: Use a `DispatcherQueueTimer` (from `DispatcherQueue.GetForCurrentThread().CreateTimer()`) with `Interval = TimeSpan.FromMilliseconds(intervalMs)` and `IsRepeating = true`. Call `Start()` when the shell page loads and `Stop()` in `Unloaded` to match mount and unmount. There is no react-query cache, so register each data service (`INotifyPropertyChanged` view models backed by one shared `HttpClient` and `System.Text.Json`) in a DI-held `IRefreshable` list with an `IsEnabled` flag and a key. In the `Tick` handler, filter out the live service and disabled services, then start `_ = service.RefreshAsync()` for each one without awaiting, to match `void refetchQueries`. Each service catches its own exceptions and exposes them on an `Error` property, so no unobserved `Task` exception escapes. Unlike react-query, nothing cancels an in-flight refresh when the next tick fires: to match `cancelRefetch`, keep a `CancellationTokenSource` per service, cancel it, and replace it on each tick. Setting `Interval` to a new value takes effect without recreating the timer, while the source restarts its phase.

