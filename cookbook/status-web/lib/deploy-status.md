---
id: 4b068644-9e3a-42bf-bce8-4f3068dea7e3
title: Status Web Deploy Status
domain: agentictoolkit://cookbook/status-web/lib/deploy-status
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Browser-side hand mirror of the deploy phase vocabulary, per-provider phase
  mappers and the combined deploy status.
platforms:
- typescript
- web
tags:
- deploy
- status
- pure-function
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/deploy-status
- agentictoolkit://cookbook/status-web/lib/board-types
references: []
approved-by: ''
approved-date: ''
---

# Status Web Deploy Status

## Overview

`deploy-status.ts` (`packages/web/packages/status-web/src/lib/deploy-status.ts`) is the status dashboard's copy of the platform-independent deploy vocabulary. It defines three string unions (`DeployStatus`, `BuildPhase`, `DeployPhase`), the `Phases` pair, the in-flight vocabulary (`IN_FLIGHT_BUILD_PHASES`, `IN_FLIGHT_DEPLOY_PHASE`, `isInFlight`), the in-flight `DeployStatus` values (`IN_FLIGHT_STATUSES`, `deployStatusInFlight`), two provider mappers (`vercelPhases`, `railwayPhases`) and the collapse function `combinedStatus`.

The module's own comment calls it "A HAND MIRROR of the server's deploy-status.ts (there is no shared build between the two packages)". The server original is specified in [Status Server Monitor Deploy Status](agentictoolkit://cookbook/status-server/monitor/deploy-status). `deploy-status-parity.test.ts` imports both modules and asserts they agree across the full phase space.

Inside the web app, `types.ts` imports the three unions to type `DeploymentDTO.status`, `buildPhase` and `deployPhase`. `deploy-display.ts` imports `DeployStatus`. `row-model.ts` calls `deployStatusInFlight` in `deployDtoUnconfirmed` to decide whether a `DeploymentDTO` asserts live progress that may need demoting. The module has no state, no I/O and no side effects.

## Behavioral Requirements

### Vocabulary types

- **deploy-status-union**: `DeployStatus` MUST be exactly the string union `"success" | "failed" | "building" | "queued" | "canceled" | "unknown"`.
- **build-phase-union**: `BuildPhase` MUST be exactly the string union `"queued" | "building" | "built" | "failed" | "canceled" | "unknown"`.
- **deploy-phase-union**: `DeployPhase` MUST be exactly the string union `"none" | "deploying" | "deployed" | "failed" | "unknown"`.
- **phases-shape**: `Phases` MUST have two fields: `buildPhase: BuildPhase | null` and `deployPhase: DeployPhase`.
- **null-build-phase**: A `buildPhase` of `null` MUST mean the platform reports no build lifecycle. The source comment gives Cloudflare Workers as the example, which "list only already-live deployments".
- **unknown-terminal**: The `unknown` phase MUST be treated as terminal. Per the source comment it is "an in-flight phase the backend could not re-confirm for its expiry window", and "Like `canceled` it is the ABSENCE of a verdict — never good or bad".

### In-flight vocabulary

- **in-flight-build-phases**: `IN_FLIGHT_BUILD_PHASES` MUST be the read-only array `["building", "queued"]`, in that order.
- **in-flight-deploy-phase**: `IN_FLIGHT_DEPLOY_PHASE` MUST be `"deploying"`.
- **server-parity-constants**: `IN_FLIGHT_BUILD_PHASES` and `IN_FLIGHT_DEPLOY_PHASE` MUST equal the server module's constants of the same names, element for element.
- **is-in-flight-signature**: `isInFlight` MUST take `buildPhase: string | null` and `deployPhase: string`, and MUST return a `boolean`.
- **is-in-flight-build**: `isInFlight` MUST return `true` when `buildPhase` is a member of `IN_FLIGHT_BUILD_PHASES`, whatever `deployPhase` is.
- **is-in-flight-deploy**: `isInFlight` MUST return `true` when `deployPhase` equals `IN_FLIGHT_DEPLOY_PHASE`, whatever `buildPhase` is.
- **is-in-flight-terminal**: `isInFlight` MUST return `false` for every other pair, including a `null` build phase with a non-deploying deploy phase, and any string outside the unions.
- **server-parity-is-in-flight**: `isInFlight` MUST return the same result as the server's `isInFlight` for every pair in the product of `{null, queued, building, built, failed, canceled, unknown}` and `{none, deploying, deployed, failed, unknown}`.

### In-flight statuses (web only)

- **in-flight-statuses**: `IN_FLIGHT_STATUSES` MUST be the read-only array `["building", "queued"]`.
- **deploy-status-in-flight**: `deployStatusInFlight(status)` MUST return `true` exactly when `status` is `"building"` or `"queued"`, and `false` for `"success"`, `"failed"`, `"canceled"` and `"unknown"`.
- **in-flight-statuses-cover**: `IN_FLIGHT_STATUSES` MUST cover every `DeployStatus` that `combinedStatus` produces from an in-flight `Phases`. Per the doc comment, `combinedStatus` maps a deploying phase to `"building"` and a queued build to `"queued"`.
- **web-only-exports**: `IN_FLIGHT_STATUSES` and `deployStatusInFlight` exist only in the web module. The server module has no counterpart, and the parity test does not compare them.

### vercelPhases

- **vercel-signature**: `vercelPhases` MUST take `readyState: string`, `readySubstate: string | null | undefined` and `target: string | null | undefined`, and MUST return `Phases`. Per the doc comment, `readyState` is the build and `readySubstate` (production only) is the deploy.
- **vercel-build-ready**: A `readyState` of `"READY"` MUST map to `buildPhase` `"built"`.
- **vercel-build-error**: A `readyState` of `"ERROR"` MUST map to `buildPhase` `"failed"`.
- **vercel-build-canceled**: A `readyState` of `"CANCELED"` or `"DELETED"` MUST map to `buildPhase` `"canceled"`.
- **vercel-build-queued**: A `readyState` of `"QUEUED"` MUST map to `buildPhase` `"queued"`.
- **vercel-build-fallback**: Every other `readyState` MUST map to `buildPhase` `"building"`. The source comment lists `BUILDING`, `INITIALIZING`, `BLOCKED` and unknown values. Matching is exact and case-sensitive.
- **vercel-deploy-default**: `deployPhase` MUST be `"none"` unless `buildPhase` is `"built"` and `target` is exactly `"production"`.
- **vercel-deploy-promoted**: For a built production deployment, a `readySubstate` of `"PROMOTED"` MUST map to `deployPhase` `"deployed"`.
- **vercel-deploy-rolling**: For a built production deployment, a `readySubstate` of `"ROLLING"` MUST map to `deployPhase` `"deploying"`.
- **vercel-deploy-staged**: For a built production deployment, any other `readySubstate` (including `"STAGED"`, `null` and `undefined`) MUST map to `deployPhase` `"none"`. The source comment says STAGED means "built but never promoted → no deploy entry yet".
- **vercel-never-unknown**: `vercelPhases` MUST NOT produce the `unknown` phase on either lifecycle, and MUST NOT produce a `failed` deploy phase.

### railwayPhases

- **railway-signature**: `railwayPhases` MUST take `status: string` and MUST return `Phases`. Per the doc comment, Railway reports both phases natively in one enum.
- **railway-building**: `"BUILDING"` and `"INITIALIZING"` MUST map to `{ buildPhase: "building", deployPhase: "none" }`.
- **railway-deploying**: `"DEPLOYING"` MUST map to `{ buildPhase: "built", deployPhase: "deploying" }`.
- **railway-success**: `"SUCCESS"` MUST map to `{ buildPhase: "built", deployPhase: "deployed" }`.
- **railway-crashed**: `"CRASHED"` MUST map to `{ buildPhase: "built", deployPhase: "deployed" }`. The source comment says a runtime crash "is a health concern, not a deploy failure".
- **railway-failed**: `"FAILED"` MUST map to `{ buildPhase: "failed", deployPhase: "none" }`. The source comment says the enum "can't separate build-fail from deploy-fail; build is the common case".
- **railway-queued**: `"WAITING"` and `"NEEDSAPPROVAL"` MUST map to `{ buildPhase: "queued", deployPhase: "none" }`.
- **railway-canceled**: `"REMOVED"` and `"SKIPPED"` MUST map to `{ buildPhase: "canceled", deployPhase: "none" }`.
- **railway-fallback**: Every other `status`, including the empty string and lowercase spellings, MUST map to `{ buildPhase: "building", deployPhase: "none" }`.

### combinedStatus

- **combined-signature**: `combinedStatus` MUST take a `Phases` value and MUST return one `DeployStatus`. Per the doc comment it is the single status for "the Details matrix / KPI strip / deploy-issue recorder".
- **combined-failed-first**: `combinedStatus` MUST return `"failed"` when `buildPhase` or `deployPhase` is `"failed"`, before any other rule.
- **combined-canceled**: When no phase is `"failed"`, `combinedStatus` MUST return `"canceled"` if `buildPhase` is `"canceled"`, whatever `deployPhase` is.
- **combined-unknown**: When neither earlier rule applies, `combinedStatus` MUST return `"unknown"` if `buildPhase` or `deployPhase` is `"unknown"`. This check MUST run before the in-flight rules, so that "an expired row can never re-read as building".
- **combined-deployed**: When no earlier rule applies, a `deployPhase` of `"deployed"` MUST give `"success"`, including with a `null` build phase.
- **combined-deploying**: When no earlier rule applies, a `deployPhase` of `"deploying"` MUST give `"building"`.
- **combined-built**: When no earlier rule applies, a `buildPhase` of `"built"` with `deployPhase` `"none"` MUST give `"success"`. The source comment says this is "built, no separate deploy step (non-prod / staged)".
- **combined-queued**: When no earlier rule applies, a `buildPhase` of `"queued"` MUST give `"queued"`.
- **combined-fallback**: Every remaining input MUST give `"building"`. That covers `buildPhase` `"building"`, and `buildPhase` `null` with `deployPhase` `"none"`.
- **server-parity-combined**: `combinedStatus` MUST return the same result as the server's `combinedStatus` for every pair in the product of `{null, queued, building, built, failed, canceled, unknown}` and `{none, deploying, deployed, failed, unknown}`.

### Purity and concurrency

- **pure-functions**: Every exported function MUST be pure and synchronous. None performs I/O, logs, mutates its arguments or holds state.
- **no-throw**: Every exported function MUST NOT throw for any input of its declared types. Unrecognized strings fall through to a defined default instead.
- **single-threaded**: The module is stateless and runs on the single JavaScript thread, so concurrent calls cannot interleave and no ordering rule is needed.

## Appearance

Not applicable — this is a pure deploy-status vocabulary and mapping module, not a visual component.

## States

Not applicable — this is a pure deploy-status vocabulary and mapping module, not a visual component.

## Accessibility

Not applicable — this is a pure deploy-status vocabulary and mapping module, not a visual component.

## Conformance Test Vectors

Vectors 001 to 014 are traced to the assertions in `deploy-status.test.ts`. Vectors 015 and 016 are traced to `deploy-status-parity.test.ts`. Vectors 017 to 022 are traced to the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-status-001 | vercel-build-fallback, vercel-build-queued, vercel-build-error, vercel-build-canceled, vercel-build-ready | `vercelPhases` with readyState `"BUILDING"`, `"QUEUED"`, `"ERROR"`, `"CANCELED"`, `"READY"` | `buildPhase` of `"building"`, `"queued"`, `"failed"`, `"canceled"`, `"built"` |
| deploy-status-002 | vercel-deploy-promoted | `vercelPhases("READY", "PROMOTED", "production")` | `deployPhase` `"deployed"` |
| deploy-status-003 | vercel-deploy-rolling | `vercelPhases("READY", "ROLLING", "production")` | `deployPhase` `"deploying"` |
| deploy-status-004 | vercel-deploy-staged | `vercelPhases("READY", "STAGED", "production")` | `deployPhase` `"none"` |
| deploy-status-005 | vercel-deploy-default | `vercelPhases("READY", null, null)`; `vercelPhases("READY", "PROMOTED", "staging")` | `deployPhase` `"none"` for both |
| deploy-status-006 | railway-building, railway-deploying, railway-success, railway-failed | `railwayPhases` with `"BUILDING"`, `"DEPLOYING"`, `"SUCCESS"`, `"FAILED"` | `{building, none}`, `{built, deploying}`, `{built, deployed}`, `{failed, none}` |
| deploy-status-007 | railway-crashed, railway-queued, railway-canceled | `railwayPhases` with `"CRASHED"`, `"WAITING"`, `"REMOVED"`, `"SKIPPED"` | `{built, deployed}`, `{queued, none}`, `{canceled, none}`, `{canceled, none}` |
| deploy-status-008 | combined-failed-first | `combinedStatus` of `{failed, none}` and of `{built, failed}` | `"failed"` for both |
| deploy-status-009 | combined-deployed, combined-built | `combinedStatus` of `{built, deployed}` and of `{built, none}` | `"success"` for both |
| deploy-status-010 | combined-fallback, combined-deploying | `combinedStatus` of `{building, none}` and of `{built, deploying}` | `"building"` for both |
| deploy-status-011 | combined-deployed, null-build-phase | `combinedStatus({ buildPhase: null, deployPhase: "deployed" })` | `"success"` |
| deploy-status-012 | combined-fallback, combined-queued | `combinedStatus` of `{null, none}` and of `{queued, none}` | `"building"`; `"queued"` |
| deploy-status-013 | combined-unknown, unknown-terminal | `combinedStatus` of `{unknown, none}` and of `{built, unknown}` | `"unknown"` for both |
| deploy-status-014 | combined-failed-first, combined-unknown | `combinedStatus({ buildPhase: "unknown", deployPhase: "failed" })` | `"failed"` |
| deploy-status-015 | in-flight-build-phases, in-flight-deploy-phase, server-parity-constants | Compare web and server `IN_FLIGHT_BUILD_PHASES` and `IN_FLIGHT_DEPLOY_PHASE` | Equal arrays; both deploy phases `"deploying"` |
| deploy-status-016 | server-parity-is-in-flight, server-parity-combined | For all 35 pairs of build phase (7 values including `null`) and deploy phase (5 values), call web and server `isInFlight` and `combinedStatus` | Web and server results are identical for every pair |
| deploy-status-017 | is-in-flight-build, is-in-flight-deploy, is-in-flight-terminal | `isInFlight("queued", "none")`; `isInFlight("built", "deploying")`; `isInFlight(null, "deployed")`; `isInFlight("unknown", "unknown")` | `true`; `true`; `false`; `false` |
| deploy-status-018 | deploy-status-in-flight, in-flight-statuses | `deployStatusInFlight` for each of `"building"`, `"queued"`, `"success"`, `"failed"`, `"canceled"`, `"unknown"` | `true`, `true`, `false`, `false`, `false`, `false` |
| deploy-status-019 | vercel-build-canceled, vercel-build-fallback | `vercelPhases("DELETED", null, null)`; `vercelPhases("INITIALIZING", null, "production")`; `vercelPhases("ready", "PROMOTED", "production")` | `{canceled, none}`; `{building, none}`; `{building, none}` |
| deploy-status-020 | railway-queued, railway-building, railway-fallback | `railwayPhases("NEEDSAPPROVAL")`; `railwayPhases("INITIALIZING")`; `railwayPhases("")`; `railwayPhases("success")` | `{queued, none}`; `{building, none}`; `{building, none}`; `{building, none}` |
| deploy-status-021 | combined-canceled | `combinedStatus({ buildPhase: "canceled", deployPhase: "deployed" })`; `combinedStatus({ buildPhase: "canceled", deployPhase: "unknown" })` | `"canceled"` for both |
| deploy-status-022 | vercel-deploy-staged | `vercelPhases("READY", undefined, "production")`; then `combinedStatus` of the result | `{built, none}`; `"success"` |

## Edge Cases

- **Null build phase**: `combinedStatus` MUST return `"success"` for `{null, deployed}` and `"building"` for `{null, none}`. `isInFlight(null, "none")` MUST return `false`.
- **Null or undefined Vercel substate or target**: `readySubstate` and `target` MUST be treated as not `"PROMOTED"`, not `"ROLLING"` and not `"production"`, so `deployPhase` is `"none"`.
- **Empty strings**: An empty `readyState` or Railway `status` MUST map to `buildPhase` `"building"` and `deployPhase` `"none"`, the fallthrough branch.
- **Unrecognized provider values**: Any `readyState` or Railway `status` outside the listed literals, including a lowercase spelling, MUST map to `"building"`. That reads as in flight. The source bounds the claim elsewhere: `row-model.ts` demotes a `"building"` or `"queued"` `DeploymentDTO` whose `phaseConfirmedAt` outlives its confirmation window.
- **Strings outside the unions in `isInFlight`**: `isInFlight` MUST return `false` for any build or deploy string that is not an in-flight literal. Its parameters are typed `string`, not the unions.
- **Conflicting phases**: `combinedStatus` MUST resolve conflicts by fixed precedence: failed, then canceled, then unknown, then deployed, deploying, built, queued, and finally building. A `failed` on either lifecycle MUST beat an `unknown` on the other.
- **Canceled deploy phase**: `DeployPhase` has no `canceled` value, so only a canceled build yields `"canceled"`.
- **Railway failure attribution**: A Railway deploy-stage failure MUST read as `buildPhase` `"failed"`, because the source enum cannot separate the two.
- **Railway crash**: A `"CRASHED"` service MUST read as `"success"` through `combinedStatus`. Runtime health is left to other checks.
- **Drift from the server mirror**: If the server's in-flight phases or `combinedStatus` branches change, the web copy MUST change with them. `deploy-status-parity.test.ts` fails when they disagree. Nothing detects drift at compile time.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O and receives already-fetched provider values.

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

## Deep Linking

Not applicable: the module exports types, constants and pure functions and has no navigable surface.

## Localization

Not applicable: the module returns fixed machine tokens such as `"success"` and `"building"`, not user-facing text. Display wording is owned by `deploy-display.ts`.

## Accessibility Options

Not applicable: the module renders nothing, so display options such as Reduce Motion have nothing to act on.

## Feature Flags

Not applicable: the source reads no flag, and every mapping always applies.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module handles only provider state enums and a deployment target. It stores and transmits nothing, and handles no credentials.

## Logging

Not applicable: the module makes no log calls. Unrecognized provider values fall through to `"building"` silently, as defined by `vercel-build-fallback` and `railway-fallback`.

## Platform Notes

- **SwiftUI**: Port the unions as `enum DeployStatus: String, Codable, Sendable`, `enum BuildPhase: String, Codable, Sendable` and `enum DeployPhase: String, Codable, Sendable`, and `Phases` as a `struct` with `buildPhase: BuildPhase?`. Write the mappers as `static func` on a caseless `enum` namespace with a `switch` whose `default` gives `.building`. Swift's exhaustive `switch` over `Phases` makes `combinedStatus` precedence explicit, but keep the `if` order of the source rather than a tuple pattern, so `failed` still beats `unknown`. `isInFlight` should take `String?` and `String` to keep the source's loose typing, or the enums when the caller has already decoded.
- **Compose**: Use Kotlin `enum class` types with a `wire` string property, a `data class Phases(val buildPhase: BuildPhase?, val deployPhase: DeployPhase)`, and `when` expressions with an `else` branch for the fallthrough. Serialise with `kotlinx.serialization` `@SerialName` so the lowercase wire tokens are kept.
- **React/Web**: This is the source: `src/lib/deploy-status.ts`, tested by `src/lib/deploy-status.test.ts` and pinned to `status-server/src/monitor/deploy-status.ts` by `src/lib/deploy-status-parity.test.ts`. The server original also exports SQL predicate builders (`inFlightSql`, `columnOverwritableSql`, `webhookKeepsStoredSql`, the collapse helpers), `IN_FLIGHT_BUILD_ORDER` and `crunchyPhases`. The web copy omits all of them. It adds `IN_FLIGHT_STATUSES` and `deployStatusInFlight`, which the server lacks.
- **AppKit / UIKit**: Use the same Swift value types as the SwiftUI port, placed in a shared framework target. Nothing here is UI-bound. If the same Swift module serves both a server and a client, one copy replaces the hand mirror and the parity test becomes unnecessary.
- **WinUI 3**: Port as a `public static class DeployStatusRules` in C#. Use `public enum DeployStatus`, `BuildPhase` and `DeployPhase`, serialised through `System.Text.Json` with `JsonStringEnumConverter` plus `[JsonStringEnumMemberName("building")]` (or a naming policy) so the lowercase wire tokens match. Make `Phases` a `public readonly record struct Phases(BuildPhase? BuildPhase, DeployPhase DeployPhase)`. Expose `IReadOnlyList<BuildPhase> InFlightBuildPhases` and `IReadOnlyList<DeployStatus> InFlightStatuses` as `static readonly` arrays or `ImmutableArray`. Write `VercelPhases(string readyState, string? readySubstate, string? target)` and `RailwayPhases(string status)` as `switch` expressions with a `_ => BuildPhase.Building` discard arm, using ordinal comparison to keep the source's case sensitivity. `CombinedStatus` keeps the source's sequential `if` order. Everything stays synchronous with no `Task`. A view model that shows these statuses would expose them through `INotifyPropertyChanged` or an `ObservableCollection<DeploymentDto>`, but that belongs to the consumer, not this module.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/deploy-status.ts` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of concerns.** The module holds only vocabulary and mapping rules. Fetching, storage, demotion timing and display wording live in other modules.

**Unit test coverage.** `deploy-status.test.ts` covers both provider mappers and every `combinedStatus` branch, including the `unknown` precedence. `deploy-status-parity.test.ts` checks the full phase space against the server. `deployStatusInFlight` and `IN_FLIGHT_STATUSES` have no direct test in the given sources.

**Explicit error handling.** No function throws. Unrecognized provider strings map to `"building"` by design, with no log or signal at this layer. That is partial: the claim is bounded downstream by the confirmation window, not here.

**Data integrity.** The parity test keeps the browser and server from interpreting the same phases differently, and `unknown` can never be reported as in progress.

**Graceful degradation.** Unexpected provider values degrade to an in-flight reading that the dashboard later demotes, rather than to a crash or a false verdict.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from source |
