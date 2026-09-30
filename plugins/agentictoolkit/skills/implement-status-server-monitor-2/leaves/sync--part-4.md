<!-- leaf: implement-status-server-monitor-2/sync--part-4 · source: status-server-monitor-sync.md -->

# Status Server Monitor Sync — continued (part 4)

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). An Apple companion backend embedding this cycle models `runCycle` as an `async` function or `actor` method taking a `Storage`-equivalent protocol and a `Sendable` `StatusConfig`-equivalent struct; `guard` becomes a small generic helper built on `withThrowingTaskGroup` or `Task` + `Task.sleep` racing, cancelling the loser but — matching the source's own choice — never cancelling the abandoned real call, only abandoning its result.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `runCycle` as a `suspend fun`; `guard` becomes `withTimeoutOrNull` composed with a `try`/`catch`, since Kotlin's `withTimeoutOrNull` alone cancels the racing coroutine (a deliberate divergence to note, since the source's `guard` does not cancel `fn()`); the four provider polls map to a `coroutineScope` running four `async` children joined together, matching `Promise.all`.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/sync.ts` as two exported `async function`s on the Node status backend (`runCycle`, `guard`), imported by the cycle-runner composition (`cycle-runner.ts`) and by the integration test suites that exercise it directly. Depends on plain `Promise.race`/`Promise.all`/`setTimeout`/`clearTimeout` — no framework of its own beyond the `Storage` port and the `@agentic-toolkit/deploy-platform` package for the deletion rule and cooldown state.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this cycle would typically run it from a background `Task` rather than Node's dedicated worker thread; there is no direct AppKit/UIKit view-layer analogue to any part of this file.
- **WinUI 3**: a .NET port models `runCycle` as `async Task RunCycleAsync(IStorage storage, StatusConfig config, SyncOptions? opts = null)` using `HttpClient` inside each fetcher and `System.Text.Json` for its JSON bodies; `guard` becomes a small generic `async Task<T> GuardAsync<T>(string label, string? provider, T fallback, Func<Task<T>> fn)` built on `Task.WhenAny(fn(), Task.Delay(20_000))` with a `CancellationTokenSource` used only to stop the *timer*, never the abandoned real call — mirroring the source's no-cancel choice. The four provider polls map to `Task.WhenAll`. `Windows.Storage` has no role here (there is no local file persistence in this file); persistence is entirely behind `IStorage`. `ObservableCollection`/`INotifyPropertyChanged` do not apply: this file exposes no UI-bound state of its own — those types belong to a WinUI 3 host's dashboard view model consuming the board this cycle feeds, not to the cycle itself.

## Design Decisions

- **Decision**: a currently-healthy probe (`stillServing`) vetoes the unclaimed-monitor deletion rule outright, even when the platform inventory condemns the same endpoint.
  **Rationale**: the source comment states it directly — a deploy project is keyed by NAME, so a rename or a team transfer at the provider reads exactly like a deletion; a URL that is still answering is a site worth watching regardless of what the inventory currently says, and a genuinely deleted project takes its own deployment down with it, so the healthy case is precisely the ambiguous one this veto exists to protect.
  **Approved**: pending
- **Decision**: split config deletion into two separate gates — a structural prune (step 0, `reconcileOrphanedEndpoints`) and a platform-inventory prune (step 8, `retireUnclaimedMonitors`) — rather than one combined check.
  **Rationale**: the source's own step-by-step comment states each answers "a different half of the same question": step 0 is about the configured group→site→endpoint chain no longer owning a row; step 8 is about no *provider* accounting for the row any more. Both are gated on evidence that survives a transient failure, but they read from entirely different sources of truth and would conflate two independent failure modes if merged.
  **Approved**: pending
- **Decision**: put the rate-limit cooldown check inside `guard` itself, the one wrapper every cycle poll crosses, rather than inside each fetcher.
  **Rationale**: source comment: doing it in each fetcher is "a convention a new provider's author has to remember (and where a typo'd name would silently disable it)." Centralizing it in `guard` makes the cooldown unconditional for every future provider poll added to this file.
  **Approved**: pending
- **Decision**: only run `pruneOlderThanDays(90)` when at least one deploy fetcher succeeded this cycle, rather than pruning unconditionally on a fixed schedule.
  **Rationale**: source comment: pruning unconditionally "avoid[s] deleting history when a temporary outage makes all fetchers return ok:false" — an all-providers-down cycle must not be indistinguishable, in its effect on stored history, from a genuinely stale set of rows.
  **Approved**: pending
- **Decision**: keep the bounded in-flight deploy reconcile (`reconcileVanishedDeploys`) and the ledger write (`reconcileBoardLedger`) running even on a `skipDeploys` (probe-only) tick, while skipping every other deploy-phase step.
  **Rationale**: source comment: only the deploy block terminalizes a finished build, so without this exemption the board kept asserting "building" for deploys the provider had already marked ready, for the full slow-cadence interval; the reconcile itself is "by-id, capped, and a no-op when nothing is in flight," so it costs one small query per tick and only does real work during a deploy burst — exactly when the board would otherwise go stale.
  **Approved**: pending
