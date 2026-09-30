<!-- leaf: implement-status-web-src-lib-1/auto-configure--part-2 · source: status-web-src-lib-auto-configure.md -->

# Auto Configure Match Adapter — continued (part 2)

## Localization

The detail blocks contain hardcoded English, with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `Left alone:` | `skipDetail` header |
| (none) | `Also:` | `noteDetail` header |
| (none) | `…and <N> more` | Remainder line in both blocks |
| (none) | `runMatch: opts.client is required when opts.api is not supplied` | `requireClient` error message, meant for developers |

The per-project reasons and notes are English text produced by the engine, and this module forwards them unchanged.

## Platform Notes

- **SwiftUI**: Port the `StatusAddApi` port as a `protocol` with `async throws` methods, and `runMatch` as an `async throws` function. Mark the result structs (`MatchRun`, `NotedAdd`) `Sendable`, and keep the loop sequential with a plain `for` and `await`, not a `TaskGroup`. `detailBlock` becomes a pure `String` builder using `prefix(5)`. Hand the strings to SwiftUI views unchanged.
- **Compose**: Port the port as a Kotlin `interface` with `suspend` functions, and `runMatch` as a `suspend fun` run in a `viewModelScope` coroutine. Use a sequential `for` loop, not `async`/`awaitAll`, and `runCatching` per project to reproduce the engine's resilience. `onProgress` maps naturally to a `MutableStateFlow<Pair<Int, Int>>`.
- **React/Web**: Source platform. `auto-configure.ts` is plain TypeScript with no React. It depends on `../api/monitored-sites` (the HTTP functions), `../api/client` (the `StatusApiClient` type), `./config-status` (`autoConfigureOptedOut`) and `@agentic-toolkit/deploy-platform/engine` (`runAutoConfigure` and its types). Tests use Vitest with a fake monitored-sites module cast to `typeof import(...)`.
- **AppKit / UIKit**: Same port shape as SwiftUI, backed by `URLSession` `async` data tasks. Report progress from `onProgress` to the main actor (`@MainActor` closure) before touching a progress indicator. The detail strings suit an `NSAlert` `informativeText` or a `UIAlertController` message.
- **WinUI 3**: Port the port as a C# `interface IStatusAddApi` with `Task<IReadOnlyList<EndpointLite>> ListAllEndpointsAsync()` and similar methods, implemented over a shared `HttpClient`, with `System.Text.Json` records for `EndpointLite`, `SiteLite` and `MatchRun`. Write `RunMatchAsync` as `async Task<MatchRun>` with a sequential `foreach` + `await` and a per-item `try/catch (Exception ex)` that records `ex.Message`. Throw `ArgumentNullException` in place of `requireClient`'s `Error`. Report progress through `IProgress<(int Done, int Total)>`: `Progress<T>` captures the UI `DispatcherQueue` context, so a `ProgressBar` bound to it updates safely. Unlike the source, .NET code idiomatically takes a `CancellationToken`. Adding one is a deliberate divergence; the source has no cancellation. Build the detail blocks with `string.Join("\n", rows.Take(5))` and show them in a `ContentDialog` or `InfoBar`. `ObservableCollection` is unnecessary because the result is a one-shot value.

## Design Decisions

**Decision**: The browser runs the shared engine through an adapter rather than its own planner.
**Rationale**: The header comment calls a second copy "one piece of knowledge in two places with nothing checking they agree". The browser and the server could otherwise file the same project under different sites.
**Approved**: pending

**Decision**: Match-only is a property of the call (no `create` passed), not of a crippled port. The create methods stay wired.
**Rationale**: Creation needs a transaction-scoped view of every site, so it can pick the group that owns a domain family and disambiguate a taken slug. Only the server has that view. A port that threw for half its methods would trap the next caller.
**Approved**: pending

**Decision**: `runMatch` has no hidden default network client, so `opts.client` is required when `opts.api` is absent.
**Rationale**: The doc comment on `requireClient` says there is "no hidden default network client to fall back on silently". This keeps tests from accidentally reaching the network.
**Approved**: pending

**Decision**: The opt-out fold (`ignoreProjectWarning || !isActive`) happens in the adapter, not in the engine.
**Rationale**: Dropping the flag once made the endpoint axis wire every opted-out monitor. `isActive` means nothing to the engine's other consumers, so the fold belongs at the boundary, matching the server's adapter.
**Approved**: pending

**Decision**: The detail blocks are capped at 5 named rows with a remainder count, and are kept separate from `summarizeAutoConfigure`.
**Rationale**: Counts alone let "a permanently stuck project" stay "invisible behind a bare `skipped: 1`", while an uncapped list would turn the dialog into a log dump. The summary function describes what the engine did; these blocks are the diagnostic beside it.
**Approved**: pending

**Decision**: The notes header is the neutral `Also:`.
**Rationale**: Two different caveats share the block: a site filed under its domain family's group, and a monitor taken over from a retired project. The source says "a header naming only one of them mislabels the other — a wrong explanation is worse than none."
**Approved**: pending
