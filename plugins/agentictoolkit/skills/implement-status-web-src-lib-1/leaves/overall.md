<!-- leaf: implement-status-web-src-lib-1/overall · source: status-web-src-lib-overall.md -->

**Rules** (cite as `implement-status-web-src-lib-1/overall#<slug>`):

- `exported-surface` MUST
- `overall-status-values` MUST
- `compute-overall-signature` MUST
- `health-status-input` MUST
- `empty-is-unknown` MUST
- `all-down-is-major-outage` MUST
- `any-down-or-degraded-is-degraded` MUST
- `all-healthy-is-operational` MUST
- `check-order` MUST
- `single-down-is-major-outage` MUST
- `order-independent` MUST
- `unrecognized-element-fallback` MUST
- `no-mutation` MUST
- `pure-synchronous` MUST
- `no-errors-raised` MUST
- `type-only-health-import` MUST
- `no-runtime-caller-in-client` MUST

# Overall Status Rollup

## Overview

`overall.ts` (`packages/web/packages/status-web/src/lib/overall.ts`) is the status-web client's copy of the headline-status rollup. It exports the four-value `OverallStatus` type (`"operational"`, `"degraded"`, `"major_outage"`, `"unknown"`) and one pure function, `computeOverall`, which folds an array of per-service `HealthStatus` values (the three-value type from the sibling `health.ts`: `"healthy"`, `"degraded"`, `"down"`) into a single verdict.

The rule is: no statuses is `"unknown"`; every status `"down"` is `"major_outage"`; any status `"down"` or `"degraded"` short of all-down is `"degraded"`; otherwise `"operational"`.

Within status-web, `OverallStatus` is re-exported by `src/types.ts` and types the `overall` field of `StatusResponse`, the shape of the payload the status server returns. No status-web module calls `computeOverall` at runtime; the verdict a page shows arrives already computed in `StatusResponse.overall`. The status server owns the authoritative rollup in its own `monitor/overall.ts` (see Status Server Monitor Overall), which carries the same `computeOverall` plus an extra `publicOverall` step that this client copy does not have.

## Behavioral Requirements

- **exported-surface**: The module MUST export the type `OverallStatus` and the named function `computeOverall`, and nothing else.
- **overall-status-values**: `OverallStatus` MUST be exactly the union of the four string literals `"operational"`, `"degraded"`, `"major_outage"` and `"unknown"`.
- **compute-overall-signature**: `computeOverall` MUST take one parameter `statuses` of type `HealthStatus[]` and return an `OverallStatus`.
- **health-status-input**: Each element of `statuses` MUST be a `HealthStatus` value (`"healthy"`, `"degraded"` or `"down"`); this is a caller precondition enforced by the type signature, and `"unknown"` is not a member of `HealthStatus`.
- **empty-is-unknown**: `computeOverall` MUST return `"unknown"` when `statuses` is an empty array.
- **all-down-is-major-outage**: `computeOverall` MUST return `"major_outage"` when `statuses` is non-empty and every element equals `"down"`.
- **any-down-or-degraded-is-degraded**: `computeOverall` MUST return `"degraded"` when `statuses` is non-empty, not every element equals `"down"`, and at least one element equals `"down"` or `"degraded"`.
- **all-healthy-is-operational**: `computeOverall` MUST return `"operational"` when `statuses` is non-empty and no element equals `"down"` or `"degraded"`.
- **check-order**: `computeOverall` MUST test its conditions in this order and return on the first match: empty array, then every element `"down"`, then some element `"down"` or `"degraded"`, then the fallback. An all-`"down"` array meets both the second and third conditions and MUST yield `"major_outage"`.
- **single-down-is-major-outage**: A one-element array `["down"]` MUST yield `"major_outage"`, because every element is `"down"`; a lone failing service is reported as a full outage.
- **order-independent**: The result MUST depend only on which values are present in `statuses` and whether all are `"down"`, not on element order or duplicate counts.
- **unrecognized-element-fallback**: An element outside `HealthStatus` that reaches the function at runtime (for example through an unchecked cast) MUST be treated as neither `"down"` nor `"degraded"`, so an array of only such values yields `"operational"`.
- **no-mutation**: `computeOverall` MUST NOT mutate `statuses`.
- **pure-synchronous**: `computeOverall` MUST be synchronous and MUST NOT perform I/O, logging, timers or any other side effect; its result depends only on its argument.
- **no-errors-raised**: `computeOverall` MUST NOT throw for any array argument; it has no error path, no cancellation and no timeout.
- **type-only-health-import**: The module MUST depend on `health.ts` only through a type-only import of `HealthStatus`, so it pulls in no runtime code.
- **no-runtime-caller-in-client**: Within status-web, `OverallStatus` MUST remain the type of `StatusResponse.overall`; the client MUST NOT recompute the headline from `services`, and displays the server's verdict unchanged.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statuses` | `HealthStatus[]` | none (required) | The per-service health values to roll up. The function takes no other parameters, environment variables, settings or injected dependencies. |

## Platform Notes

- **SwiftUI**: Model `OverallStatus` and `HealthStatus` as `String`-backed `enum`s conforming to `Sendable` and `Codable` (raw values `"operational"`, `"major_outage"` and so on, so they decode from the server JSON). Write `computeOverall` as a free function or static method over `[HealthStatus]` using `isEmpty`, `allSatisfy { $0 == .down }` and `contains { $0 == .down || $0 == .degraded }`. Swift's exhaustive enums remove the out-of-type element case; an unknown raw value fails at decode time instead.
- **Compose**: Use Kotlin `enum class OverallStatus` and `enum class HealthStatus` with `@SerialName` values for kotlinx.serialization, and a top-level `fun computeOverall(statuses: List<HealthStatus>): OverallStatus` built from `isEmpty()`, `all { it == DOWN }` and `any { it == DOWN || it == DEGRADED }`. A `when` over the enum keeps it exhaustive.
- **React/Web**: The source platform. `overall.ts` is plain TypeScript with no React or DOM dependency; `OverallStatus` is a string-literal union, and `computeOverall` uses `Array.prototype.every` and `some`. `src/types.ts` re-exports the type for `StatusResponse`, and `overall.test.ts` (Vitest) covers the five main cases. The status server holds a parallel copy in `status-server/src/monitor/overall.ts` that adds `publicOverall`.
- **AppKit / UIKit**: Same Swift enums and function as the SwiftUI note; the rollup has no UI-framework dependency, so it belongs in a shared framework target used by either app.
- **WinUI 3**: Define `public enum OverallStatus { Operational, Degraded, MajorOutage, Unknown }` and `public enum HealthStatus { Healthy, Degraded, Down }` in a class library. Map the snake_case wire values with `System.Text.Json` by putting `[JsonStringEnumMemberName("major_outage")]` on the members (or a custom `JsonConverter`) and adding `JsonStringEnumConverter`. Implement `public static OverallStatus ComputeOverall(IReadOnlyList<HealthStatus> statuses)` with LINQ `Count == 0`, `All(s => s == HealthStatus.Down)` and `Any(s => s is HealthStatus.Down or HealthStatus.Degraded)`. It is synchronous and needs no `Task`. If a view model exposes the verdict, raise `INotifyPropertyChanged` (for example through CommunityToolkit.Mvvm `[ObservableProperty]`) when the server payload changes, and map the enum to text or a brush with an `IValueConverter` in XAML. Unlike TypeScript, a C# enum cannot hold an out-of-type string; an unknown wire value makes `JsonSerializer` throw `JsonException` unless the converter supplies a fallback.

## Design Decisions

**Decision**: Report all-down as `"major_outage"`, but any partial failure (some down, or any degraded) as `"degraded"`.
**Rationale**: `computeOverall` tests `every(... "down")` before `some(... "down" || "degraded")`, so a full outage is kept distinct from a partial one; a single down service among healthy ones reads as degraded, not outage.
**Approved**: pending

**Decision**: Return `"unknown"` for an empty array instead of `"operational"`.
**Rationale**: The first check in `computeOverall` is `statuses.length === 0`; with no services reporting, the rollup refuses to claim everything is fine.
**Approved**: pending

**Decision**: Keep a client-side copy of the rollup and type even though the client does not call `computeOverall` at runtime.
**Rationale**: `src/types.ts` needs `OverallStatus` to type `StatusResponse.overall`; the function sits with it and is covered by `overall.test.ts`. The duplicate of the server's `monitor/overall.ts` has already drifted (the server adds `publicOverall`), which is why the client displays the server's verdict rather than recomputing it.
**Approved**: pending
