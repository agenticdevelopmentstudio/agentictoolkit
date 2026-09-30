<!-- leaf: implement-status-web-src-lib-1/deploy-status--part-2 · source: status-web-src-lib-deploy-status.md -->

# Status Web Deploy Status — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `readyState` | `string` | none (required) | Vercel deployment build state passed to `vercelPhases`. |
| `readySubstate` | `string \| null \| undefined` | none (required parameter, may be `null`) | Vercel production substate: `PROMOTED`, `ROLLING` or `STAGED`. |
| `target` | `string \| null \| undefined` | none (required parameter, may be `null`) | Vercel deployment target. Only `"production"` enables a deploy phase. |
| `status` (Railway) | `string` | none (required) | Railway deployment status enum passed to `railwayPhases`. |
| `IN_FLIGHT_BUILD_PHASES` | constant | `["building", "queued"]` | Compiled in. Must mirror the server. |
| `IN_FLIGHT_DEPLOY_PHASE` | constant | `"deploying"` | Compiled in. Must mirror the server. |
| `IN_FLIGHT_STATUSES` | constant | `["building", "queued"]` | Compiled in. Web only. |

The module reads no environment variables and no settings keys, and takes no injected dependencies. It has no imports.

## Platform Notes

- **SwiftUI**: Port the unions as `enum DeployStatus: String, Codable, Sendable`, `enum BuildPhase: String, Codable, Sendable` and `enum DeployPhase: String, Codable, Sendable`, and `Phases` as a `struct` with `buildPhase: BuildPhase?`. Write the mappers as `static func` on a caseless `enum` namespace with a `switch` whose `default` gives `.building`. Swift's exhaustive `switch` over `Phases` makes `combinedStatus` precedence explicit, but keep the `if` order of the source rather than a tuple pattern, so `failed` still beats `unknown`. `isInFlight` should take `String?` and `String` to keep the source's loose typing, or the enums when the caller has already decoded.
- **Compose**: Use Kotlin `enum class` types with a `wire` string property, a `data class Phases(val buildPhase: BuildPhase?, val deployPhase: DeployPhase)`, and `when` expressions with an `else` branch for the fallthrough. Serialise with `kotlinx.serialization` `@SerialName` so the lowercase wire tokens are kept.
- **React/Web**: This is the source: `src/lib/deploy-status.ts`, tested by `src/lib/deploy-status.test.ts` and pinned to `status-server/src/monitor/deploy-status.ts` by `src/lib/deploy-status-parity.test.ts`. The server original also exports SQL predicate builders (`inFlightSql`, `columnOverwritableSql`, `webhookKeepsStoredSql`, the collapse helpers), `IN_FLIGHT_BUILD_ORDER` and `crunchyPhases`. The web copy omits all of them. It adds `IN_FLIGHT_STATUSES` and `deployStatusInFlight`, which the server lacks.
- **AppKit / UIKit**: Use the same Swift value types as the SwiftUI port, placed in a shared framework target. Nothing here is UI-bound. If the same Swift module serves both a server and a client, one copy replaces the hand mirror and the parity test becomes unnecessary.
- **WinUI 3**: Port as a `public static class DeployStatusRules` in C#. Use `public enum DeployStatus`, `BuildPhase` and `DeployPhase`, serialised through `System.Text.Json` with `JsonStringEnumConverter` plus `[JsonStringEnumMemberName("building")]` (or a naming policy) so the lowercase wire tokens match. Make `Phases` a `public readonly record struct Phases(BuildPhase? BuildPhase, DeployPhase DeployPhase)`. Expose `IReadOnlyList<BuildPhase> InFlightBuildPhases` and `IReadOnlyList<DeployStatus> InFlightStatuses` as `static readonly` arrays or `ImmutableArray`. Write `VercelPhases(string readyState, string? readySubstate, string? target)` and `RailwayPhases(string status)` as `switch` expressions with a `_ => BuildPhase.Building` discard arm, using ordinal comparison to keep the source's case sensitivity. `CombinedStatus` keeps the source's sequential `if` order. Everything stays synchronous with no `Task`. A view model that shows these statuses would expose them through `INotifyPropertyChanged` or an `ObservableCollection<DeploymentDto>`, but that belongs to the consumer, not this module.

## Design Decisions

**Decision**: Keep the web vocabulary as a hand-copied mirror of the server module, guarded by a parity test.
**Rationale**: The source comment says "there is no shared build between the two packages". Drift would make the board mislabel deploys silently, so `deploy-status-parity.test.ts` imports both modules and compares the in-flight constants, `isInFlight` and `combinedStatus` across all 35 phase pairs.
**Approved**: pending

**Decision**: Treat `unknown` as terminal and check it before the in-flight rules in `combinedStatus`.
**Rationale**: `unknown` marks a phase nothing could re-confirm within the expiry window. Checking it first guarantees "an expired row can never re-read as building". A real `failed` still wins, because failure is checked before it.
**Approved**: pending

**Decision**: Map Railway `CRASHED` to built and deployed, and `FAILED` to a failed build.
**Rationale**: Per the source comments, a runtime crash is a health concern, not a deploy failure. The single Railway enum cannot separate build failure from deploy failure, and build failure is the common case.
**Approved**: pending

**Decision**: Only a Vercel production deployment gets a deploy phase.
**Rationale**: For non-production targets build-ready is go-live (per the test's description), so `combinedStatus` reads `built` with `none` as `"success"`. A production build that is `STAGED` has not been promoted, so it gets no deploy entry.
**Approved**: pending

**Decision**: Unrecognized provider states fall through to `"building"` rather than an error.
**Rationale**: The Vercel comment lists `BLOCKED` and unknown values alongside `BUILDING` and `INITIALIZING`. The in-flight claim is bounded by the confirmation window in `row-model.ts` (`deployDtoUnconfirmed`), so an unexpected value demotes rather than asserting progress forever.
**Approved**: pending

**Decision**: Add `IN_FLIGHT_STATUSES` and `deployStatusInFlight` to the web copy only.
**Rationale**: Panels that render a `DeploymentDTO` directly (DeployList, the "Build pipeline" counts) see only the collapsed `status`, not the phases. They need an in-flight test over `DeployStatus` to demote a wedged build in step with the activity list, whose demotion the server applies.
**Approved**: pending
