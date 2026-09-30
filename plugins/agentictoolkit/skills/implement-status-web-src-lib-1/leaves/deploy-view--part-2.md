<!-- leaf: implement-status-web-src-lib-1/deploy-view--part-2 · source: status-web-src-lib-deploy-view.md -->

# Deploy View — continued (part 2)

## Platform Notes

- **SwiftUI**: Port as free functions or a caseless `enum DeployView` namespace over a `Sendable` `DeploymentDTO` struct. `PlatformSummary` becomes a `struct` with `var` counts. Use a `[String: PlatformSummary]` plus an insertion-order `[String]` array, because Swift `Dictionary` does not keep insertion order. Parse dates with `ISO8601DateFormatter` (with `.withFractionalSeconds`), and map a `nil` parse to "unconfirmed" to keep the fail-closed rule. Sort with `sorted { $0.createdAt > $1.createdAt }` on parsed `Date` values.
- **Compose**: Use Kotlin top-level functions over a `data class DeploymentDto`. A `LinkedHashMap<String, PlatformSummary>` keeps the first-seen order the source gets from `Map`. `Instant.parse` throws rather than returning NaN, so wrap it in `runCatching` and treat a failure as unconfirmed. Use `sortedByDescending { it.createdAt }` (it is stable) and `firstOrNull { ... }` for the latest terminal deploy.
- **React/Web**: This is the source: `src/lib/deploy-view.ts`, tested by `src/lib/deploy-view.test.ts`. It relies on `deployDtoUnconfirmed` in `src/lib/row-model.ts` and on `IN_FLIGHT_STATUSES` in `src/lib/deploy-status.ts`. The key functions live in `packages/deploy-platform/src/canon/index.ts`, which the Hono server shares. Call sites are `Dashboard.tsx` (`summarizeByPlatform`), `DetailPanel.tsx` (`deploysForEndpoint`), `StatusMatrix.tsx` (latest terminal and failure count) and `AutoConfigureReview.tsx` (`PLATFORM_ORDER`). The code depends on JavaScript `Map` insertion order and on a stable `Array.prototype.sort`.
- **AppKit / UIKit**: Use the same pure Swift functions as the SwiftUI port, in a shared framework target. Nothing here is UI-bound. `NSTableView` or `UITableView` data sources consume the returned arrays directly.
- **WinUI 3**: Port as a `public static class DeployView` over `record DeploymentDto` (deserialized with `System.Text.Json`, with `DeployStatus` as a `[JsonConverter(typeof(JsonStringEnumConverter))]` enum). `PlatformSummary` becomes a `record` or a small class. `Dictionary<string, PlatformSummary>` does not guarantee enumeration order, so keep a separate `List<string>` of first-seen platforms, or use `OrderedDictionary<TKey,TValue>` (.NET 9). Parse dates with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and treat `false` as unconfirmed, since .NET has no NaN parse result. Use LINQ `Where(...).OrderByDescending(d => d.CreatedAt)`, which is stable, and `FirstOrDefault(...)` for the latest terminal deploy. Share `DeployTargetKey` and `PlatformCanon` from one assembly with whatever server code keys deploys, matching the source's single-owner re-export. Lowercase the environment with `ToLowerInvariant()`. The view model binds the summaries to an `ObservableCollection<PlatformSummary>`, and recomputes on a `DispatcherQueueTimer` tick so demotion tracks the clock. The functions stay synchronous, with no `Task`.

## Design Decisions

**Decision**: Demote a stale in-flight deploy to "total only" in `summarizeByPlatform`, using the same `deployDtoUnconfirmed` rule as `DeployList` and the activity list.
**Rationale**: Per the doc comment, an in-flight deploy that nothing has re-confirmed is no longer a live "building". Counting it would let the Build-pipeline pane and the KPI building pill assert progress the rest of the board has stopped asserting.
**Approved**: pending

**Decision**: Correlate endpoints to deploys only by the explicit (platform, project) configured on the endpoint, never by host.
**Rationale**: The section comment says "No host guessing." An endpoint with no platform or project wired is a health-only check and correlates to nothing.
**Approved**: pending

**Decision**: Re-export `deployTargetKey` and `platformCanon` from the shared canon package rather than restating them.
**Rationale**: The server keys deploys with `deployTargetKey`. A previous local copy omitted the environment lowercasing, so a Railway endpoint whose stored environment differed in case correlated to nothing in the browser while the server matched it.
**Approved**: pending

**Decision**: Match the environment only for Railway.
**Rationale**: Railway serves every environment from one project. Vercel and Cloudflare projects are environment-specific, so the project alone identifies them.
**Approved**: pending

**Decision**: `latestTerminalForEndpoint` skips canceled and in-flight deploys.
**Rationale**: Per its doc comment, the deploy status shown should reflect the last real outcome, not a canceled or in-flight build on top of it.
**Approved**: pending

**Decision**: `summarizeByPlatform` groups by the raw platform string, while the endpoint helpers canonicalize.
**Rationale**: This is how the source behaves. Summary sections are keyed by the platform string on the deploy row (`"cloudflare-pages"` is the one in `PLATFORM_ORDER`). Correlation has to bridge the config spelling `"cloudflare"`. A port that canonicalizes in the summary would change section keys and ordering.
**Approved**: pending

**Decision**: Export `PLATFORM_ORDER` as the single ordering source.
**Rationale**: Per the source comment, every platform-grouped surface should order sections identically, instead of each keeping its own list.
**Approved**: pending
