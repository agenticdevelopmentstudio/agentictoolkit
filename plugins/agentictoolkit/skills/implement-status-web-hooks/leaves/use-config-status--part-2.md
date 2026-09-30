<!-- leaf: implement-status-web-hooks/use-config-status--part-2 · source: status-web-hooks-use-config-status.md -->

# useConfigStatus — continued (part 2)

## Platform Notes

- **SwiftUI**: Model as an `@Observable @MainActor` store holding `configure: ConfigureData?`, the classification response, and a computed `status`. Run the four roster reads in one `async let` group (or `withThrowingTaskGroup`) so they fail together, and the classification in a separate `Task` so it cannot blank the rosters. Share one store instance through the environment to replace react-query's shared cache; expose `refresh()` that awaits both loads.
- **Compose**: A `ViewModel` exposing `StateFlow<UseConfigStatus>`; roster reads with `coroutineScope { awaitAll(...) }`, classification in a sibling `launch` with its own `runCatching`. Combine the two flows with `combine` and `map` for `buildStatus`; `stateIn(viewModelScope, SharingStarted.WhileSubscribed(), ...)` gives the "enabled observers drive the shared source" behavior.
- **React/Web**: Source platform. `hooks/use-config-status.ts` uses `@tanstack/react-query` `useQuery` twice, `useMemo` for `buildStatus` and `useCallback` for `refetch`; it depends on `lib/config-status.ts` (the paused-monitor fold over the engine's `endpointConfigStatus`), `lib/deploy-view.ts` (re-exports `platformCanon` from `@agentic-toolkit/deploy-platform/canon`), `hooks/use-deploy-projects.ts` (`fetchUnconfigured`, `UnconfiguredResponse`, `DeployProject`) and `api/monitored-sites.ts` (the four list calls). Tests: `hooks/use-config-status.dom.test.tsx`.
- **AppKit / UIKit**: Same store as SwiftUI, observed via Observation tracking or Combine `@Published`; view controllers call the store rather than issuing reads, keeping the "one access point" rule.
- **WinUI 3**: Implement a singleton `ConfigStatusService : INotifyPropertyChanged` registered in the DI container (the stand-in for the shared `QueryClient` cache). Use one `HttpClient` for all reads and `System.Text.Json` (`JsonSerializer.DeserializeAsync<UnconfiguredResponse>`) for bodies. Load rosters with `await Task.WhenAll(listGroups, listSites, listIntegrations, listAllEndpoints)` so any fault fails the roster load; load the classification in a separate `Task` wrapped in its own `try/catch` so its failure only sets `Error`. Expose `Groups`/`Sites`/`Integrations`/`Endpoints` as `ObservableCollection<T>` for the editor, `Status` as an immutable record rebuilt when either load completes, `IsLoading` bound to the roster task only, and `Error` set roster-first. Build `UnmonitoredByPlatform` as `Dictionary<string,int>` with the same `cloudflare-pages` to `cloudflare` normalization. Marshal property changes to the UI thread with `DispatcherQueue.TryEnqueue`. Unlike react-query, nothing deduplicates concurrent loads or refreshes automatically: guard with a cached in-flight `Task` per load and add an explicit refresh timer if the host needs the shared periodic refresh.

## Design Decisions

**Decision**: Split the classification out of the roster query into its own key.
**Rationale**: The source records that one flaky provider in the old five-leg `Promise.all` emptied Settings ▸ Sites and Settings ▸ Platforms while the rows sat readable in SQLite; the rosters must not depend on a third party being up.
**Approved**: pending

**Decision**: Keep reporting the classification failure through `error` while `isLoading` tracks rosters only.
**Rationale**: "A dead classification must never be read as zero gaps / all clear", but it "no longer parks the editor in a permanent skeleton". Roster-first precedence means a double failure surfaces only the roster error.
**Approved**: pending

**Decision**: Take the project axis whole from the server; derive the endpoint axis client-side.
**Rationale**: The server is the single source of truth for which projects need monitoring; the endpoint axis stays local because the banner needs each endpoint's url, site and environment, which the server's `{id,name}` shape omits, and the raw endpoints are already loaded for the editor.
**Approved**: pending

**Decision**: Fold `isActive === false` into the engine's `ignoreProjectWarning` at the app boundary (`lib/config-status`).
**Rationale**: `isActive` means nothing to the engine's other consumers; the server applies the identical fold in its own adapter (`autoConfigureOptedOut`), so browser and server agree on the same endpoint.
**Approved**: pending

**Decision**: Return `EMPTY_STATUS` until both queries have data.
**Rationale**: `buildStatus` needs both halves to produce a consistent model; the trade-off, recorded under Edge Cases, is that a pending classification is indistinguishable from zero gaps through `status` alone.
**Approved**: pending

**Decision**: Use the cache-served classification request (no `fresh`) with no `refetchInterval`.
**Rationale**: The source says the badges' refresh "coalesces on" the server's 30-second single-flight cache instead of fanning out a provider scan per tab per minute; only the Auto Configure modal forces a fresh scan.
**Approved**: pending
