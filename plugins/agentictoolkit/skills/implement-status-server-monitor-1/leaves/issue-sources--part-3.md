<!-- leaf: implement-status-server-monitor-1/issue-sources--part-3 · source: status-server-monitor-issue-sources.md -->

# Status Server Monitor Issue Sources — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `integrationPlatform` (parameter to `platformHealthSource`) | `string \| null` | none — caller-supplied per call | The `deploy_integrations.platform` free-text value the caller (`libsql/stores/config-store.ts`, external) already has on hand. |
| `status` (parameter to `httpIsBad`, `deployIsBad`, `deployIsStuck`, `deployIsResolving`) | `HealthStatus` / `DeployStatus` | none — caller-supplied per call | The already-derived health or combined deploy status (from `health.ts`'s `classify` / `deploy-status.ts`'s `combinedStatus`, both external) the caller wants judged. |
| `ageMs` (parameter to `deployIsStuck`) | `number` | none — caller-supplied per call | Milliseconds since the deploy row was created, computed by the caller (`board/derive-problems.ts`'s `deployProblems`, external) as `nowMs - createdAtMs`. |
| `prevStreak` (parameter to `nextPlatformStreak`) | `number` | none — caller-supplied per call | The consecutive-failure count persisted from the prior poll, read by the caller from `platform_health_state.consecutive_failures` (external). |
| `failing` (parameter to `nextPlatformStreak`) | `boolean` | none — caller-supplied per call | Whether this poll's provider check failed, computed by the caller as `configured && !reachable` (`libsql/stores/observation-store.ts`, external). |
| `threshold` (parameter to `nextPlatformStreak`) | `number` | `PLATFORM_UNREACHABLE_POLLS` (`2`) | The consecutive-failure count `bad` requires; every current caller omits it and takes the default. |
| `configured` (parameter to `dropVanishedVercelProjects`) | `ConfiguredDeployTargets` | none — required | The site-owned deploy targets per platform, built by the caller (`board/ownership.ts`'s `rosterTargets`, external) from the monitored roster. |
| `liveVercelProjects` (parameter to `dropVanishedVercelProjects`) | `ReadonlySet<string>` | none — required; pass an empty set to mean "no account mirror available" | The Vercel project names the caller read live from the account, which MUST be a COMPLETE read (per the function's own doc comment) or a truncated page walk will misread as mass deletion. |

## Privacy

- **Data collected**: none of this file's own — it receives already-derived status values (`HealthStatus`, `DeployStatus`), an integration's already-configured `platform` string, and a caller-supplied set of Vercel project names as plain function arguments; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing; the consecutive-failure count `nextPlatformStreak` advances is persisted by its caller to `platform_health_state` (`libsql/stores/observation-store.ts`), external to this file.
- **Transmission**: none. This file performs no network or database call of its own.
- **Retention**: not applicable — this file holds no data across calls.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `IssueSource` as a `Sendable`, `String`-backed `enum`, `SOURCE_LABEL` as a `[IssueSource: String]` dictionary (or a computed property on the enum), and `ConfiguredDeployTargets`/`PlatformStreak` as `Sendable struct`s; because every function here is a pure, synchronous, non-isolated computation, the ported functions need no `actor` or `@MainActor` isolation at all — plain top-level or static functions on a namespacing `enum` are the direct equivalent.
- **Compose**: same non-UI framing. A Kotlin port models `IssueSource` as an `enum class` with a `label: String` property in place of the separate `SOURCE_LABEL` map, and the predicate/derivation functions as top-level functions; `dropVanishedVercelProjects`'s set-difference reads directly onto Kotlin's `Set` operators (`subtract`/`minus`) with the same two-guard early-return shape.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/issue-sources.ts` as a plain ESM module on the Node status backend, imported by `board/ownership.ts`, `board/derive-problems.ts`, `board/facts.ts`, `libsql/stores/observation-store.ts`, `libsql/stores/config-store.ts`, and `monitor/issues.ts`; `IssueSource`, `SOURCE_LABEL`, and `ISSUE_SOURCES` are hand-mirrored (not imported, not build-shared) at `packages/web/packages/status-web/src/lib/issue-sources.ts` for the browser client, with no automated parity guard between the two copies (see Design Decisions).
- **AppKit / UIKit**: same non-UI framing as SwiftUI; this file has no mutable module-level state to duplicate across a per-thread or per-`Worker` boundary the way a stateful Node module might.
- **WinUI 3**: a .NET port models `IssueSource` as a C# `enum` with a companion `IReadOnlyDictionary<IssueSource, string>` for `SOURCE_LABEL` (or a `[Description]`-attributed enum read through a small extension method), `HealthStatus`/`DeployStatus` as C# `enum`s (ported alongside the sibling `deploy-status` recipe), and `ConfiguredDeployTargets`/`PlatformStreak` as `readonly record struct`s using `IReadOnlySet<string>` for the per-platform project sets. `HttpIsBad`, `DeployIsBad`, `DeployIsStuck`, `DeployIsResolving`, `PlatformHealthSource`, `NextPlatformStreak`, and `DropVanishedVercelProjects` all port as `static` methods (e.g. on an `IssueSources` class) using C# `switch` expressions or LINQ set operators (`Except`) in place of this file's ternaries and array `.filter`; `nextPlatformStreak`'s caller-owns-persistence contract maps directly onto a .NET repository/store class calling the pure step function before an `INSERT ... ON CONFLICT`-equivalent `UPSERT` via EF Core or `Microsoft.Data.Sqlite`, exactly as `observation-store.ts` does.

