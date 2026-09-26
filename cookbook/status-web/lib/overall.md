---
id: ef8570df-111e-484f-aad7-20ad49bd34dc
title: Overall Status Rollup
domain: agentictoolkit://cookbook/status-web/lib/overall
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Pure function folding per-service HealthStatus values into one OverallStatus
  verdict: unknown, major_outage, degraded or operational'
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/overall
- agentictoolkit://cookbook/status-web/src
references: []
approved-by: ''
approved-date: ''
---

# Overall Status Rollup

## Overview

`overall.ts` (`packages/web/packages/status-web/src/lib/overall.ts`) is the status-web client's copy of the headline-status rollup. It exports the four-value `OverallStatus` type (`"operational"`, `"degraded"`, `"major_outage"`, `"unknown"`) and one pure function, `computeOverall`, which folds an array of per-service `HealthStatus` values (the three-value type from the sibling `health.ts`: `"healthy"`, `"degraded"`, `"down"`) into a single verdict.

The rule is: no statuses is `"unknown"`; every status `"down"` is `"major_outage"`; any status `"down"` or `"degraded"` short of all-down is `"degraded"`; otherwise `"operational"`.

Within status-web, `OverallStatus` is re-exported by `src/types.ts` and types the `overall` field of `StatusResponse`, the shape of the payload the status server returns. No status-web module calls `computeOverall` at runtime; the verdict a page shows arrives already computed in `StatusResponse.overall`. The status server owns the authoritative rollup in its own `monitor/overall.ts` (see [Status Server Monitor Overall](agentictoolkit://cookbook/status-server/monitor/overall)), which carries the same `computeOverall` plus an extra `publicOverall` step that this client copy does not have.

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

## Appearance

Not applicable — this is a pure status-rollup function and type, not a visual component.

## States

Not applicable — this is a pure status-rollup function and type, not a visual component.

## Accessibility

Not applicable — this is a pure status-rollup function and type, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-src-lib-overall-001 | empty-is-unknown | `computeOverall([])` | `"unknown"` (`overall.test.ts` "empty is unknown") |
| status-web-src-lib-overall-002 | all-healthy-is-operational | `computeOverall(["healthy", "healthy"])` | `"operational"` (`overall.test.ts` "all healthy is operational") |
| status-web-src-lib-overall-003 | any-down-or-degraded-is-degraded | `computeOverall(["healthy", "degraded"])` | `"degraded"` (`overall.test.ts` "any degraded is degraded") |
| status-web-src-lib-overall-004 | any-down-or-degraded-is-degraded | `computeOverall(["healthy", "down"])` | `"degraded"` (`overall.test.ts` "some down is degraded") |
| status-web-src-lib-overall-005 | all-down-is-major-outage, check-order | `computeOverall(["down", "down"])` | `"major_outage"` (`overall.test.ts` "all down is major_outage"); also meets the degraded condition, so it confirms check-order |
| status-web-src-lib-overall-006 | single-down-is-major-outage | `computeOverall(["down"])` | `"major_outage"` (traced to the `every` check; no dedicated test) |
| status-web-src-lib-overall-007 | any-down-or-degraded-is-degraded | `computeOverall(["degraded", "degraded"])` | `"degraded"` (traced to the `some` check) |
| status-web-src-lib-overall-008 | any-down-or-degraded-is-degraded, order-independent | `computeOverall(["down", "degraded"])` and `computeOverall(["degraded", "down"])` | both `"degraded"` |
| status-web-src-lib-overall-009 | all-healthy-is-operational | `computeOverall(["healthy"])` | `"operational"` |
| status-web-src-lib-overall-010 | no-mutation | `const a = ["down", "healthy"]; computeOverall(a)` | returns `"degraded"`; `a` still equals `["down", "healthy"]` |
| status-web-src-lib-overall-011 | unrecognized-element-fallback | `computeOverall(["unknown"] as unknown as HealthStatus[])` | `"operational"` |
| status-web-src-lib-overall-012 | overall-status-values, compute-overall-signature, health-status-input | assign `"ok"` to an `OverallStatus`, or pass `["unknown"]` without a cast | compile-time type error |
| status-web-src-lib-overall-013 | pure-synchronous, no-errors-raised | call `computeOverall` with any `HealthStatus[]` | returns a string synchronously (not a Promise); no throw, no console output |
| status-web-src-lib-overall-014 | exported-surface, type-only-health-import | inspect module exports and imports | exports only `OverallStatus` and `computeOverall`; the only import is `import type { HealthStatus } from "./health"` |
| status-web-src-lib-overall-015 | no-runtime-caller-in-client | search status-web sources for `computeOverall` | only `overall.ts` and `overall.test.ts` reference it; `types.ts` uses `OverallStatus` for `StatusResponse.overall` |

## Edge Cases

- **Empty input**: `statuses` of length 0 MUST yield `"unknown"`; "no data" is kept distinct from both healthy and outage.
- **Single element**: `["down"]` MUST yield `"major_outage"`, `["degraded"]` MUST yield `"degraded"`, and `["healthy"]` MUST yield `"operational"`.
- **All-down boundary**: the all-down check MUST run before the any-down check, so an all-`"down"` array never yields `"degraded"`.
- **Mixed down and healthy**: an array with at least one `"down"` and at least one non-`"down"` element MUST yield `"degraded"`, not `"major_outage"`, however many services are down.
- **Null or missing argument**: `null` or `undefined` for `statuses` is excluded by the type signature (a typed caller precondition); if one arrives through an unchecked cast, reading `.length` throws a `TypeError` that propagates to the caller unchanged.
- **Out-of-type elements**: values such as `"unknown"`, `null` or other strings are excluded by the type; at runtime they MUST count as neither down nor degraded (see unrecognized-element-fallback), so an all-`"unknown"` array yields `"operational"`, not `"unknown"`.
- **Very large arrays**: the function MUST scan in linear time with no size limit; both `every` and `some` stop at the first deciding element.
- **Concurrent access**: not applicable; the function is synchronous, pure and runs on the single JavaScript thread, so calls cannot interleave.
- **Error states and offline state**: not applicable; the function does no I/O, so it has no dependency that can fail or disconnect.
- **Divergence from the server**: this client copy has no `publicOverall`; a verdict computed here from endpoint statuses alone can read `"operational"` while the server's public verdict reads `"degraded"` because of a non-endpoint problem. The client MUST display the server-supplied `StatusResponse.overall` rather than recompute it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statuses` | `HealthStatus[]` | none (required) | The per-service health values to roll up. The function takes no other parameters, environment variables, settings or injected dependencies. |

## Deep Linking

Not applicable: `overall.ts` is a pure function and type with no navigable surface or URL handling.

## Localization

Not applicable: `computeOverall` returns machine identifiers (`"operational"`, `"major_outage"` and so on), not user-facing text; turning them into display strings belongs to the caller.

## Accessibility Options

Not applicable: `overall.ts` renders nothing, so no display option such as Reduce Motion or Increase Contrast affects it.

## Feature Flags

Not applicable: `overall.ts` reads no flag and has no gated code path.

## Analytics

Not applicable: `overall.ts` emits no events.

## Privacy

Not applicable: `overall.ts` handles only health enum values, stores nothing and transmits nothing.

## Logging

Not applicable: `overall.ts` makes no log calls; it has no error path to report.

## Platform Notes

- **SwiftUI**: Model `OverallStatus` and `HealthStatus` as `String`-backed `enum`s conforming to `Sendable` and `Codable` (raw values `"operational"`, `"major_outage"` and so on, so they decode from the server JSON). Write `computeOverall` as a free function or static method over `[HealthStatus]` using `isEmpty`, `allSatisfy { $0 == .down }` and `contains { $0 == .down || $0 == .degraded }`. Swift's exhaustive enums remove the out-of-type element case; an unknown raw value fails at decode time instead.
- **Compose**: Use Kotlin `enum class OverallStatus` and `enum class HealthStatus` with `@SerialName` values for kotlinx.serialization, and a top-level `fun computeOverall(statuses: List<HealthStatus>): OverallStatus` built from `isEmpty()`, `all { it == DOWN }` and `any { it == DOWN || it == DEGRADED }`. A `when` over the enum keeps it exhaustive.
- **React/Web**: The source platform. `overall.ts` is plain TypeScript with no React or DOM dependency; `OverallStatus` is a string-literal union, and `computeOverall` uses `Array.prototype.every` and `some`. `src/types.ts` re-exports the type for `StatusResponse`, and `overall.test.ts` (Vitest) covers the five main cases. The status server holds a parallel copy in `status-server/src/monitor/overall.ts` that adds `publicOverall`.
- **AppKit / UIKit**: Same Swift enums and function as the SwiftUI note; the rollup has no UI-framework dependency, so it belongs in a shared framework target used by either app.
- **WinUI 3**: Define `public enum OverallStatus { Operational, Degraded, MajorOutage, Unknown }` and `public enum HealthStatus { Healthy, Degraded, Down }` in a class library. Map the snake_case wire values with `System.Text.Json` by putting `[JsonStringEnumMemberName("major_outage")]` on the members (or a custom `JsonConverter`) and adding `JsonStringEnumConverter`. Implement `public static OverallStatus ComputeOverall(IReadOnlyList<HealthStatus> statuses)` with LINQ `Count == 0`, `All(s => s == HealthStatus.Down)` and `Any(s => s is HealthStatus.Down or HealthStatus.Degraded)`. It is synchronous and needs no `Task`. If a view model exposes the verdict, raise `INotifyPropertyChanged` (for example through CommunityToolkit.Mvvm `[ObservableProperty]`) when the server payload changes, and map the enum to text or a brush with an `IValueConverter` in XAML. Unlike TypeScript, a C# enum cannot hold an out-of-type string; an unknown wire value makes `JsonSerializer` throw `JsonException` unless the converter supplies a fallback.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/overall.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |

Separation-of-concerns passes: the rollup is a pure, framework-free function in `src/lib`, apart from the components that display status and from the fetch code that loads `StatusResponse`. Unit-test-coverage passes: `overall.test.ts` checks each of the four return values, including the all-down boundary. Explicit-error-handling passes because the function has no failure path to hide: it neither catches nor throws, and a malformed argument that gets past the type system fails loudly with a `TypeError`. The client copy duplicates the server's `monitor/overall.ts` without the server's `publicOverall` step. That is recorded under Design Decisions and Edge Cases and is not a compliance failure.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
