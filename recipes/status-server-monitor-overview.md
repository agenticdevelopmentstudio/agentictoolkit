---
id: add8a34c-a40d-417e-9ee8-aec108e73474
title: Status Server Monitor Overview
domain: agentictoolkit://recipes/status-server-monitor-overview
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Platform-grouped deploy tallies and explicit platform-plus-project endpoint-to-deploy
  correlation, with no host guessing.
platforms:
- typescript
- web
tags:
- monitor
- deploy
- pure-function
- server
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-issue-sources
- agentictoolkit://recipes/status-server-monitor-deploy-status
- agentictoolkit://recipes/status-server-monitor-deploy-view
- agentictoolkit://recipes/status-server-board
references:
- packages/web/packages/status-server/src/monitor/overview.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/canon/index.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/canon/canon.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/target-key.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/ownership.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-problems.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/issue-sources.ts (agentictoolkit)
- packages/web/packages/status-server/src/lib/links.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/auto-configure.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/deploy-view.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/deploy-view.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Overview

## Overview

`overview.ts` (`packages/web/packages/status-server/src/monitor/overview.ts`) is a pure, synchronous logic module in the status backend. It exports one platform-level aggregation, `summarizeByPlatform`, and three endpoint-level correlation helpers — `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint` — that all match a monitored endpoint to its deploys by the endpoint's EXPLICIT `platform`/`deployProject`/`environment` fields, never by guessing from a host. It also re-exports `platformCanon` and `deployTargetKey`, which it imports from the shared `@agentic-toolkit/deploy-platform/canon` package, so callers that already import them via `./overview` keep working after the two functions moved into that package. Within `status-server`, the re-exported `platformCanon` is imported by `board/target-key.ts`, `board/ownership.ts`, `board/derive-problems.ts`, `monitor/issue-sources.ts`, `lib/links.ts`, `routes/reads.ts`, and `routes/auto-configure.ts`; `deployTargetKey` is imported by `routes/reads.ts`. `summarizeByPlatform`, `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint`, and the `PlatformSummary`/`EndpointLike` interfaces they use have, as of this recipe's authoring, no importer anywhere in `status-server`'s own source or test files. The client package `status-web` ships its own re-implementation of the same four names and two interfaces at `src/lib/deploy-view.ts`, consumed by its `Dashboard`, `DetailPanel`, `StatusMatrix`, `KpiStrip`, and `GlobalPanel` components — that file is a separate, browser-side module with an added staleness-demotion parameter this file's version does not take, not a caller of this file.

## Behavioral Requirements

### Data Shapes

- **platform-summary-shape**: A `PlatformSummary` value MUST carry exactly five fields — `platform: string`, `ready: number`, `building: number`, `failed: number`, `total: number` — with no other field.
- **endpoint-like-shape**: An `EndpointLike` value MUST carry `platform`, `deployProject`, and `environment`, each typed `string | null` and each OPTIONAL (a caller MAY omit any of the three entirely, not only pass `null`).
- **canon-reexport**: This module MUST re-export the `platformCanon` and `deployTargetKey` functions it imports from `@agentic-toolkit/deploy-platform/canon` unchanged, so a caller importing either name from `./overview` gets the identical function, and identical results, as a caller importing it directly from the `canon` package.

### Platform Summarization

- **platform-grouping**: `summarizeByPlatform` MUST group input `DeploymentDTO` rows by the raw, uncanonicalized `d.platform` string; it MUST NOT pass `d.platform` through `platformCanon` before grouping, so a `"cloudflare-pages"` row and a `"cloudflare"` row (were both ever present) produce two separate `PlatformSummary` entries rather than one merged entry — unlike this same file's endpoint-correlation functions, which canonicalize the platform through `deployTargetKey` before comparing.
- **status-bucket-mapping**: For each `DeploymentDTO` grouped into a platform's entry, `summarizeByPlatform` MUST increment `total` by one, and MUST additionally increment exactly one of `ready` (when `status === "success"`), `building` (when `status === "building"` or `status === "queued"`), or `failed` (when `status === "failed"`).
- **status-bucket-omission**: `summarizeByPlatform` MUST leave `ready`, `building`, and `failed` all unchanged — incrementing only `total` — for a `DeploymentDTO` whose `status` is `"canceled"` or `"unknown"`; the source's own doc comment names only `canceled` for this treatment, but the code's `if`/`else if` chain matches none of `"canceled"` or `"unknown"` against any literal, so both fall through identically to total-only counting.
- **platform-summary-ordering**: `summarizeByPlatform` MUST order its returned array by placing every platform present in the fixed list `["vercel", "cloudflare-pages", "railway", "crunchy"]` first, in that exact sequence (skipping any of the four not present in the input), followed by every other platform encountered, in the order each was first encountered while iterating the input array.

### Endpoint Correlation

- **deploy-target-key-precondition**: `deploysForEndpoint` MUST return an empty array, without inspecting the `deploys` argument, when `deployTargetKey(ep.platform, ep.deployProject, ep.environment)` returns `null` — which `deployTargetKey` does whenever `ep.platform` canonicalizes to an empty string or `ep.deployProject` is falsy, i.e. an endpoint with no platform or no project wired (a health-only check) correlates to nothing.
- **deploy-endpoint-correlation**: When the endpoint's key is non-`null`, `deploysForEndpoint` MUST return every `DeploymentDTO` in `deploys` whose own `deployTargetKey(d.platform, d.projectName, d.environment)` equals that same key — matching the endpoint's `deployProject` field against the deploy row's differently-named `projectName` field — and MUST exclude every row whose key differs, including one that shares the platform or project but not both (or, for `"railway"`, not the environment as well, per `deployTargetKey`'s railway-specific environment matching).
- **deploy-endpoint-sort**: `deploysForEndpoint` MUST return its matches sorted by `createdAt` descending (newest first), computed as `+new Date(b.createdAt) - +new Date(a.createdAt)`.
- **latest-terminal-selection**: `latestTerminalForEndpoint` MUST return the first element of `deploysForEndpoint(deploys, ep)` — i.e. the newest by `createdAt` — whose `status` is `"success"` or `"failed"`, skipping every element before it, and MUST return `null` when no element in that list has either status; the source's own doc comment names `canceled`, `building`, and `queued` as the statuses skipped, but the code's `find` predicate accepts only `"success"` or `"failed"`, so a `"unknown"`-status row is skipped identically even though the comment does not name it.
- **failure-count**: `failuresForEndpoint` MUST return the count of elements in `deploysForEndpoint(deploys, ep)` whose `status` is `"failed"`.

### Ordering and Concurrency

- **module-purity**: Every function this file exports MUST be a pure function of the arguments passed to it: none reads or writes any variable outside its own call, the file holds no top-level mutable state (the one module-level constant, the platform-order list, is never reassigned or mutated by any exported function), and none performs an `await`, a callback registration, or any I/O. Because JavaScript executes one module instance's code on a single thread and nothing here yields to the event loop mid-computation, two calls into any of this file's functions from the same thread MUST NOT interleave in a way that corrupts either call's result — a structural fact of the runtime and this file's statelessness, not a lock this file implements.

## Appearance

Not applicable — this is a logic module (deploy-platform summarization and endpoint-deploy correlation), not a visual component.

## States

Not applicable — this is a logic module with no visual-state table; its only state-like distinctions (which status bucket a deploy falls into, which deploy is an endpoint's latest terminal one) are pure return values documented under Behavioral Requirements, not runtime states of a component instance.

## Accessibility

Not applicable — this is a logic module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-overview-001 | platform-summary-shape, platform-grouping, status-bucket-mapping, platform-summary-ordering | `summarizeByPlatform` on deploys, in this order: one `"crunchy"`/`"success"`, one `"netlify"`/`"success"` (a platform outside the fixed list), one `"vercel"`/`"failed"`, one `"vercel"`/`"building"`, one `"cloudflare-pages"`/`"queued"` | Returns four entries in the order `vercel, cloudflare-pages, crunchy, netlify` (the three known platforms present, in the fixed sequence, then the one unknown platform); the `vercel` entry is exactly `{ platform: "vercel", ready: 0, building: 1, failed: 1, total: 2 }` — no dedicated unit test exists in this package; traced to the `PLATFORM_ORDER` literal and the doc comment "Stable ordering for known platforms; unknowns go after" |
| status-server-monitor-overview-002 | status-bucket-omission | `summarizeByPlatform` on two `"vercel"` deploys, one `status: "canceled"` and one `status: "unknown"` | Returns `[{ platform: "vercel", ready: 0, building: 0, failed: 0, total: 2 }]` — neither row touches `ready`, `building`, or `failed` — no dedicated unit test exists in this package; traced directly to the `if`/`else if` chain having no branch for either literal |
| status-server-monitor-overview-003 | platform-grouping | `summarizeByPlatform` on one deploy with `platform: "cloudflare-pages"` and one with `platform: "cloudflare"` | Returns two separate entries, `{ platform: "cloudflare-pages", ... }` and `{ platform: "cloudflare", ... }`, each with `total: 1` — not one merged entry — no dedicated unit test exists in this package; traced to the grouping key being `d.platform` with no `platformCanon` call |
| status-server-monitor-overview-004 | deploy-target-key-precondition, endpoint-like-shape | `deploysForEndpoint(deploys, {})` where `deploys` is a non-empty array of otherwise-matching-looking rows | Returns `[]` — no dedicated unit test exists in this package; traced to `deployTargetKey(undefined, undefined, undefined)` returning `null` (no platform canonicalizes to a non-empty string) and the `if (!key) return [];` guard |
| status-server-monitor-overview-005 | deploy-endpoint-correlation, deploy-endpoint-sort | `deploysForEndpoint(deploys, ep)` with `ep = { platform: "vercel", deployProject: "hub", environment: "production" }` and `deploys` containing three rows with `platform: "vercel", projectName: "hub"` at `createdAt` `"2026-01-01T00:00:00.000Z"`, `"2026-03-01T00:00:00.000Z"`, `"2026-02-01T00:00:00.000Z"`, plus one row with `projectName: "other"` | Returns exactly the three `"hub"` rows, ordered March, February, January (newest first); the `"other"` row is excluded — no dedicated unit test exists in this package; traced to `deployTargetKey`'s Vercel key (environment-free) and the `.sort()` comparator |
| status-server-monitor-overview-006 | deploy-endpoint-correlation | `deploysForEndpoint(deploys, ep)` with `ep = { platform: "railway", deployProject: "backend", environment: "production" }` and `deploys` containing two `platform: "railway", projectName: "backend"` rows, one `environment: "production"` and one `environment: "staging"` | Returns only the `environment: "production"` row — traced to `deployTargetKey` including the (lowercased) environment in the key only when the canonical platform is `"railway"`, per its own doc comment: Railway serves every environment from one project |
| status-server-monitor-overview-007 | latest-terminal-selection | `latestTerminalForEndpoint(deploys, ep)` where the matching, newest-first rows for `ep` have statuses `"building"`, `"canceled"`, `"failed"`, `"success"` in that order | Returns the `"failed"` row (third-newest) — the newer `"building"` and `"canceled"` rows are skipped — no dedicated unit test exists in this package |
| status-server-monitor-overview-008 | latest-terminal-selection | `latestTerminalForEndpoint(deploys, ep)` where the matching, newest-first rows have statuses `"unknown"`, `"success"` in that order | Returns the `"success"` row, skipping the newer `"unknown"` row even though the source's doc comment names only `canceled`/`building`/`queued` as skipped statuses — no dedicated unit test exists in this package |
| status-server-monitor-overview-009 | latest-terminal-selection | `latestTerminalForEndpoint(deploys, ep)` where every matching row has status `"building"` or `"queued"` | Returns `null` — no dedicated unit test exists in this package; traced to `.find(...) ?? null` |
| status-server-monitor-overview-010 | failure-count | `failuresForEndpoint(deploys, ep)` where the matching rows for `ep` have statuses `"failed"`, `"failed"`, `"success"`, `"canceled"` | Returns `2` — no dedicated unit test exists in this package; traced to `.filter((d) => d.status === "failed").length` |
| status-server-monitor-overview-011 | canon-reexport | `import { platformCanon, deployTargetKey } from "./overview"` then `platformCanon("cloudflare-pages")` and `deployTargetKey("vercel", "hub", null)` | Returns `"cloudflare"` and `"vercel\|hub\|"` respectively — identical to calling the same inputs against `@agentic-toolkit/deploy-platform/canon` directly, per `canon.test.ts`'s own assertions of `platformCanon` and `deployTargetKey`'s underlying behavior |
| status-server-monitor-overview-012 | module-purity | `summarizeByPlatform(deploys)` called twice in sequence with the same `deploys` array reference, with a `deploysForEndpoint(deploys, ep)` call for an unrelated `ep` interleaved between the two calls | Both `summarizeByPlatform` calls return deep-equal results, and neither is affected by the intervening `deploysForEndpoint` call — no dedicated unit test exists in this package; traced to the absence of any module-level mutable state and the absence of any `await` in either function |

## Edge Cases

- **Null and empty input**: `summarizeByPlatform([])` returns `[]` — MUST (platform-summary-ordering, vacuously). `deploysForEndpoint(deploys, {})` (an `EndpointLike` with all three fields omitted, e.g. a health-only check with no deploy target wired) returns `[]` regardless of `deploys` — MUST (deploy-target-key-precondition). `latestTerminalForEndpoint([], ep)` and `failuresForEndpoint([], ep)` return `null` and `0` respectively for any `ep`, because `deploysForEndpoint` on an empty `deploys` array is itself `[]` — MUST (latest-terminal-selection, failure-count).
- **Boundary values**: the fixed platform-order list has exactly four entries; a fifth or later distinct unknown platform value is placed after all four known ones, in first-encountered order among the unknowns themselves — MUST (platform-summary-ordering). An endpoint with exactly one of `platform`/`deployProject` set and the other omitted still produces a `null` key from `deployTargetKey` (both are required for a non-`null` key), so `deploysForEndpoint` still returns `[]` — MUST (deploy-target-key-precondition).
- **Concurrent access**: this file holds no state beyond the read-only platform-order array, and every exported function is synchronous and pure — MUST NOT require any lock or ordering guarantee, because there is no shared mutable state for concurrent calls to race over (module-purity).
- **Error states**: none of this file's own functions throw for any input shape its types allow. `deployTargetKey` and `platformCanon`, both re-exported from `@agentic-toolkit/deploy-platform/canon`, handle a missing platform or project by returning `null` or an empty string rather than throwing, and `deploysForEndpoint` checks that `null` explicitly before doing any filtering. This file has no dependency on a network, database, or file system of its own to fail. `DeploymentDTO.createdAt` is typed as a required, non-`null` `string` (an ISO timestamp per its origin in the provider fetchers, external to this file); `deploysForEndpoint`'s sort computes `+new Date(b.createdAt) - +new Date(a.createdAt))` without validating that string, so a malformed `createdAt` would produce `NaN` from `+new Date(...)` and an unordered pair in the sort — this is a fact of an unvalidated precondition the type contract already guarantees is met by every caller in this codebase, not a gap this file's purpose calls for it to re-validate.
- **Offline or disconnected state**: Not applicable — this file performs no network I/O, holds no connection, and reads no external service; every function is a synchronous transform of a `deploys` array and an `ep`/`endpoint` value its caller already has in hand. The deploy rows these functions operate on were fetched by other files (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, `fetch-crunchy.ts`, all external to this file), whose own connectivity failure modes are theirs to document, not this module's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploys` (parameter to all four exported functions) | `DeploymentDTO[]` | none — caller-supplied | The full or already-narrowed set of deploy rows the function summarizes or filters; this file fetches none of these rows itself. |
| `ep` (parameter to `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint`) | `EndpointLike` | none — caller-supplied | The monitored endpoint's own explicit `platform`/`deployProject`/`environment`, read from its stored configuration by the caller before this file sees it. |
| the platform-order list (module-level constant) | `string[]` | fixed 4 entries: `"vercel"`, `"cloudflare-pages"`, `"railway"`, `"crunchy"` | Not configurable at runtime; adding, removing, or reordering an entry requires editing this file. This file reads no environment variable and consults no injected configuration object of its own. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route; it produces in-memory summaries and filtered arrays consumed by other layers, never a navigable link.

## Localization

Not applicable: this file produces no user-facing string of any kind — its outputs are numeric counts, platform identifiers, and `DeploymentDTO` rows already shaped by other files, none of it literal copy a person reads as prose.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; its only branching on a fixed value is the literal status-string and platform-string comparisons described under Behavioral Requirements, which are data-driven rules, not flag lookups.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

Not applicable: this file performs no data collection, storage, or transmission of its own. Every exported function is a pure, synchronous transform of arguments its caller already supplied — deploy rows and endpoint configuration that originated elsewhere (the provider fetchers and the endpoint's own stored config, both external to this file) — and this file itself never writes them anywhere or sends them anywhere.

## Logging

Not applicable: this file contains no logging call of any kind — no `console` call and no structured logger call appears anywhere in its source.

## Platform Notes

- **SwiftUI**: not a view-layer concern — this file has no view. A Swift port models `PlatformSummary` as a `Sendable` `struct` with `platform: String`, `ready: Int`, `building: Int`, `failed: Int`, `total: Int`, and `EndpointLike` as a `Sendable` `struct` with three optional `String?` fields; the platform-order list becomes a `static let` `[String]`, and `summarizeByPlatform`/`deploysForEndpoint`/`latestTerminalForEndpoint`/`failuresForEndpoint` become plain (non-`actor`, since nothing here is asynchronous or mutates shared state) static functions taking `[DeploymentDTO]` and returning the same shapes.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `PlatformSummary` as a `data class`, `EndpointLike` as a `data class` with three nullable `String?` properties, the platform-order list as a `listOf(...)`, and the four derivation functions as top-level `fun`s or an object's methods, using `Collections.groupingBy`-style folding or a plain mutable `Map` built with a `for` loop exactly as the source does — no `suspend` modifier is needed anywhere, since nothing in this file performs asynchronous work.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/overview.ts`, a plain module in the Hono status backend (Node), not client-side React. As documented in Overview, its re-exported `platformCanon`/`deployTargetKey` are imported across `status-server`'s `board/` and `routes/` layers, while its own four functions and two interfaces currently have no importer in this package; the browser-side client (`status-web`) maintains a separate, parallel copy at `src/lib/deploy-view.ts` with an added staleness-demotion parameter, consumed by its Dashboard/DetailPanel/StatusMatrix/KpiStrip/GlobalPanel components.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — nothing here touches a view controller or window. A macOS/iOS host app would consume the Swift port described above from its data/service layer exactly as this file's server-side callers do today, with no framework-specific adaptation needed beyond that layer boundary.
- **WinUI 3**: a .NET port models `PlatformSummary` as a `readonly record struct` (`Platform`, `Ready`, `Building`, `Failed`, `Total`) and `EndpointLike` as a `readonly record struct` with three nullable `string?` properties; the platform-order list as a `static readonly ImmutableArray<string>`; and `SummarizeByPlatform`, `DeploysForEndpoint`, `LatestTerminalForEndpoint`, `FailuresForEndpoint` as static methods on a plain static class, with `DeploysForEndpoint` building its grouping via a `Dictionary<string, PlatformSummary>` and its endpoint match via LINQ's `Where`/`OrderByDescending(d => d.CreatedAt)` in place of `.filter()`/`.sort()`. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed anywhere in this port, because the source file itself performs no I/O, no asynchronous work, and holds no UI-observable state; `CreatedAt` should be parsed with `DateTimeOffset.TryParse` rather than a throwing parse, to match the source's own unvalidated-but-typed-precondition treatment of that field without introducing an exception path the source doesn't have.

## Design Decisions

- **Decision**: group `summarizeByPlatform`'s tallies by the raw `d.platform` string rather than by `platformCanon(d.platform)`, even though this same file's endpoint-correlation functions canonicalize the platform before comparing.
  **Rationale**: the source gives no comment explaining this asymmetry; it is stated here as an observed fact of the code (platform-grouping), not a defect this recipe is asserting — a Vercel/Cloudflare/Railway/Crunchy deploy's `d.platform` is written by this fleet's own upsert path using one of the four fixed literals, so in practice the raw and canonicalized groupings agree for every row this code currently sees; the divergence would only surface for a `"cloudflare-pages"`/`"cloudflare"` mix that the rest of this codebase does not currently produce.
  **Approved**: pending
- **Decision**: treat a `"unknown"`-status deploy identically to a `"canceled"` one — total-only in `summarizeByPlatform`, and skipped by `latestTerminalForEndpoint`'s terminal-status check — even though the source's own doc comments on both functions name only `canceled`/`building`/`queued` and never mention `unknown`.
  **Rationale**: this is the actual, traceable behavior of the `if`/`else if` chain (status-bucket-omission) and the `find` predicate (latest-terminal-selection): both are closed lists of literal comparisons, so any `DeployStatus` value not explicitly named — currently only `"unknown"` — falls through to the same "not a counted/terminal outcome" treatment as `"canceled"`. Recorded here because a reader trusting only the doc comments would not expect `"unknown"` to be covered at all.
  **Approved**: pending
- **Decision**: keep exporting `summarizeByPlatform`, `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint`, `PlatformSummary`, and `EndpointLike` even though, at the time of this recipe's authoring, no other file in the `status-server` package imports any of the six.
  **Rationale**: recorded as an observed fact of the current call graph, not a defect in this file — all six behave exactly as documented here, and the two re-exported helpers (`platformCanon`, `deployTargetKey`) remain in heavy use across `status-server`. `status-web`'s `src/lib/deploy-view.ts` re-implements the same four functions and two interfaces for the browser, with an added staleness-demotion parameter this server-side version does not take, rather than importing this file — the two currently diverge in that one respect, and a future consolidation is an open question for whoever owns both packages, not a gap in either file's own documented behavior.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `partial`: the re-exported `platformCanon` and `deployTargetKey` are exercised indirectly — `canon.test.ts` tests the identical underlying functions in `@agentic-toolkit/deploy-platform/canon` directly, and because this file re-exports them unchanged (canon-reexport), that coverage carries over — but `summarizeByPlatform`, `deploysForEndpoint`, `latestTerminalForEndpoint`, and `failuresForEndpoint` have no dedicated test anywhere in this package, and, per the Overview and Design Decisions above, no runtime importer either; nothing in this repository currently exercises those four functions' logic at all, in a test or in production. `separation-of-concerns` passes: the file performs no I/O, reads no configuration, and does exactly one thing — deploy-platform summarization and endpoint correlation — with the shared canonicalization delegated to the `canon` package rather than reimplemented here. `explicit-error-handling` passes: the one real failure case, an endpoint with no usable platform/project, is surfaced as an explicit `null` key from `deployTargetKey` and handled by an explicit `if (!key) return [];` guard rather than silently proceeding with a bogus correlation or throwing. `fault-tolerance` passes: every function accepts an empty `deploys` array, an `EndpointLike` with any or all of its three fields omitted, and any `DeployStatus` value its type allows (including `"unknown"`, per the open question above) without throwing.

`unit-test-coverage`'s gap is the open question on `summarizeByPlatform`, `deploysForEndpoint`, `latestTerminalForEndpoint`, and `failuresForEndpoint` — see the corresponding Design Decision above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
