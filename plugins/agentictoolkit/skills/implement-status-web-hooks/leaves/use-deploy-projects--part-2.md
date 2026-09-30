<!-- leaf: implement-status-web-hooks/use-deploy-projects--part-2 · source: status-web-hooks-use-deploy-projects.md -->

# useDeployProjects — continued (part 2)

## Platform Notes

- **React/Web**: Source is `packages/web/packages/status-web/src/hooks/use-deploy-projects.ts`. It uses TanStack React Query's `useQuery` (query key, `enabled`, `staleTime`), the package's `StatusApiClient` port from `src/api/client.ts` (`api.fetch` with `RequestInit.cache: "no-store"`), and a module-level `let` as the page-load latch. `"use client"` marks it as a Next.js client module. Callers: `ConfigPanel.tsx` arms the latch before invalidating; `use-config-status.ts` polls `fetchUnconfigured`; `AutoConfigureProvider.tsx`, `ProjectBrowser.tsx`, `PlatformProjects.tsx`, `EndpointsSection.tsx` and `UnconfiguredProjectsBanner.tsx` consume the data.
- **SwiftUI**: Start from an `@Observable` (or `ObservableObject`) model on `@MainActor` holding `DeployProjectsResponse?` and an error, with `async` methods calling `URLSession.shared.data(for:)` using a `URLRequest` whose `cachePolicy` is `.reloadIgnoringLocalCacheData`; decode with `JSONDecoder` into `Codable` structs (optionals for the nullable fields, `verifiedPlatforms: [String]?`). The 60 s stale window and dedup must be hand-rolled (store a fetch timestamp and an in-flight `Task`), and the latch becomes a property on the model or a static on the service.
- **Compose**: Start from a `ViewModel` exposing `StateFlow<UiState>` with a repository using Ktor or Retrofit plus `kotlinx.serialization` data classes; send `Cache-Control: no-store` (or OkHttp `CacheControl.FORCE_NETWORK`). Dedup and staleness come from a `Mutex` plus timestamp or a library such as Store; the latch is an `AtomicBoolean` in the repository singleton.
- **AppKit / UIKit**: Same `URLSession` and `Codable` service as SwiftUI, with a view controller or coordinator observing results via delegate, Combine publisher or closure; UI updates hop to the main queue.
- **WinUI 3**: Start from a service using a shared `HttpClient` with `GetAsync` and a `CacheControlHeaderValue { NoStore = true }` request header (or `HttpRequestMessage.Headers.CacheControl`), deserializing with `System.Text.Json` `JsonSerializer.DeserializeAsync<DeployProjectsResponse>` into records with nullable `string?` properties and `List<string>? VerifiedPlatforms`. Throw `HttpRequestException` (or a custom exception carrying the `deploy-projects <status>` message) when `!response.IsSuccessStatusCode`. Expose results from a ViewModel implementing `INotifyPropertyChanged` (for example CommunityToolkit.Mvvm `ObservableObject` with an `ObservableCollection<DeployProject>` for list binding), marshalling updates through `DispatcherQueue.TryEnqueue`. React Query's dedup, 60 s `staleTime` and retry policy have no built-in equivalent: cache the last `Task<DeployProjectsResponse>` and its completion time, and add retry via Polly if wanted. The latch becomes a `static` field (or a `volatile bool` in the service) cleared only after a successful await; consider a generation counter so an arm during an in-flight request is not lost. Pass a `CancellationToken` to `GetAsync`, which the source does not do.

## Design Decisions

**Decision**: Both fetch helpers pass `cache: "no-store"`.

**Rationale**: A refetch right after Add or Ignore, or on picker open, must reach the server for a fresh provider scan; the browser's HTTP cache would otherwise show stale wired, ignored and project data.

**Approved**: pending

---

**Decision**: The first hook fetch of a page load, and any fetch after an explicit arm, sends `?fresh=1`; the latch disarms only on success.

**Rationale**: A reload and the explicit Refresh must show, and Auto Configure must plan against, the live project list rather than the server's 30 s provider cache; keeping the latch armed after a failure keeps retries fresh, while later refetches in the same page load use normal caching.

**Approved**: pending

---

**Decision**: `fetchUnconfigured` defaults to the cache-served path; only the Auto Configure modal sends `fresh: true`.

**Rationale**: The route shares the sibling `/deploy-projects` 30 s provider cache, so the config-status badges' 60 s poll coalesces on it instead of fanning out a provider scan per tab per minute.

**Approved**: pending

---

**Decision**: The fetch helpers are exported functions separate from the hook.

**Rationale**: The hook, the imperative Auto Configure run and the badges share one URL, flag and response shape so they cannot drift.

**Approved**: pending

---

**Decision**: `verifiedPlatforms` is optional and its absence means "treat every wiring as live".

**Rationale**: A backend that predates the field sends nothing, and a provider that errored, timed out or fell back to its configured list is deliberately omitted, so a client can tell "deleted upstream" from "we couldn't look".

**Approved**: pending
