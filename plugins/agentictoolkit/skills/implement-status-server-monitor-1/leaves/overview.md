<!-- leaf: implement-status-server-monitor-1/overview · source: status-server-monitor-overview.md -->

**Rules** (cite as `implement-status-server-monitor-1/overview#<slug>`):

- `platform-summary-shape` MUST
- `endpoint-like-shape` MUST
- `canon-reexport` MUST
- `platform-grouping` MUST
- `status-bucket-mapping` MUST
- `status-bucket-omission` MUST
- `platform-summary-ordering` MUST
- `deploy-target-key-precondition` MUST
- `deploy-endpoint-correlation` MUST
- `deploy-endpoint-sort` MUST
- `latest-terminal-selection` MUST
- `failure-count` MUST
- `module-purity` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `deploys` (parameter to all four exported functions) | `DeploymentDTO[]` | none — caller-supplied | The full or already-narrowed set of deploy rows the function summarizes or filters; this file fetches none of these rows itself. |
| `ep` (parameter to `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint`) | `EndpointLike` | none — caller-supplied | The monitored endpoint's own explicit `platform`/`deployProject`/`environment`, read from its stored configuration by the caller before this file sees it. |
| the platform-order list (module-level constant) | `string[]` | fixed 4 entries: `"vercel"`, `"cloudflare-pages"`, `"railway"`, `"crunchy"` | Not configurable at runtime; adding, removing, or reordering an entry requires editing this file. This file reads no environment variable and consults no injected configuration object of its own. |

## Platform Notes

- **SwiftUI**: not a view-layer concern — this file has no view. A Swift port models `PlatformSummary` as a `Sendable` `struct` with `platform: String`, `ready: Int`, `building: Int`, `failed: Int`, `total: Int`, and `EndpointLike` as a `Sendable` `struct` with three optional `String?` fields; the platform-order list becomes a `static let` `[String]`, and `summarizeByPlatform`/`deploysForEndpoint`/`latestTerminalForEndpoint`/`failuresForEndpoint` become plain (non-`actor`, since nothing here is asynchronous or mutates shared state) static functions taking `[DeploymentDTO]` and returning the same shapes.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models `PlatformSummary` as a `data class`, `EndpointLike` as a `data class` with three nullable `String?` properties, the platform-order list as a `listOf(...)`, and the four derivation functions as top-level `fun`s or an object's methods, using `Collections.groupingBy`-style folding or a plain mutable `Map` built with a `for` loop exactly as the source does — no `suspend` modifier is needed anywhere, since nothing in this file performs asynchronous work.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/overview.ts`, a plain module in the Hono status backend (Node), not client-side React. As documented in Overview, its re-exported `platformCanon`/`deployTargetKey` are imported across `status-server`'s `board/` and `routes/` layers, while its own four functions and two interfaces currently have no importer in this package; the browser-side client (`status-web`) maintains a separate, parallel copy at `src/lib/deploy-view.ts` with an added staleness-demotion parameter, consumed by its Dashboard/DetailPanel/StatusMatrix/KpiStrip/GlobalPanel components.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — nothing here touches a view controller or window. A macOS/iOS host app would consume the Swift port described above from its data/service layer exactly as this file's server-side callers do today, with no framework-specific adaptation needed beyond that layer boundary.
- **WinUI 3**: a .NET port models `PlatformSummary` as a `readonly record struct` (`Platform`, `Ready`, `Building`, `Failed`, `Total`) and `EndpointLike` as a `readonly record struct` with three nullable `string?` properties; the platform-order list as a `static readonly ImmutableArray<string>`; and `SummarizeByPlatform`, `DeploysForEndpoint`, `LatestTerminalForEndpoint`, `FailuresForEndpoint` as static methods on a plain static class, with `DeploysForEndpoint` building its grouping via a `Dictionary<string, PlatformSummary>` and its endpoint match via LINQ's `Where`/`OrderByDescending(d => d.CreatedAt)` in place of `.filter()`/`.sort()`. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`, or `ObservableCollection`/`INotifyPropertyChanged` is needed anywhere in this port, because the source file itself performs no I/O, no asynchronous work, and holds no UI-observable state; `CreatedAt` should be parsed with `DateTimeOffset.TryParse` rather than a throwing parse, to match the source's own unvalidated-but-typed-precondition treatment of that field without introducing an exception path the source doesn't have.

