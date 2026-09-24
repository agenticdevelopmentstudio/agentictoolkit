---
id: cd71721b-e80e-4525-a7a1-fc1ac2158267
title: Auto Configure Match Adapter
domain: agentictoolkit://recipes/status-web-src-lib-auto-configure
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Browser adapter onto the shared auto-configure engine: match-only runMatch,
  the StatusAddApi port, and the capped per-project detail blocks.'
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://recipes/status-web-api
- agentictoolkit://recipes/status-web-hooks-use-config-status
references: []
approved-by: ''
approved-date: ''
---

# Auto Configure Match Adapter

## Overview

`packages/web/packages/status-web/src/lib/auto-configure.ts` is the status dashboard's side of "Auto Configure". It does no matching of its own: the planner, classifier and runner belong to `@agentic-toolkit/deploy-platform/engine` (`runAutoConfigure`), the same code the Hono server runs behind `POST /auto-configure`. The file's header comment explains why: the app used to carry a hand-written copy of the planner, and "the browser and the server could canonicalize a host differently and file the same project under different sites depending on which button the operator pressed."

The module exports four things:

- `statusApi(client, api?)` — adapts the monitored-sites client onto the engine's I/O port, `StatusAddApi`.
- `runMatch(addable, opts)` — runs the engine **match-only** (it never passes `create`) and flattens the result to the `MatchRun` shape the dialogs render.
- `skipDetail(rows)` and `noteDetail(rows)` — build the "Left alone:" and "Also:" text blocks appended to the engine's `summarizeAutoConfigure` sentence, capped at `SKIP_DETAIL_LINES` (5) named projects.

Callers: `components/configure/PlatformProjects.tsx` calls `runMatch` for the per-platform "Match" and "Match all" buttons. `components/AutoConfigureProvider.tsx` appends `noteDetail` and `skipDetail` to the server-driven global "Auto Configure" summary. Site creation stays on the server, because only the server sees every site in one transaction-scoped snapshot.

## Behavioral Requirements

### Port adapter: `statusApi`

- **port-shape**: `statusApi(client, api)` MUST return an object implementing all six `StatusAddApi` methods: `listAllEndpoints`, `listSites`, `updateEndpoint`, `createSite`, `createEndpoint`, `deleteSite`.
- **port-default-api**: When `api` is omitted, `statusApi` MUST use the module's own monitored-sites client functions (`../api/monitored-sites`) as the backing implementation.
- **port-client-passthrough**: Every port method MUST forward the supplied `client` as the first argument of the matching monitored-sites function.
- **port-create-methods-wired**: `createSite`, `createEndpoint` and `deleteSite` MUST be fully wired to the client even though `runMatch` never reaches them. The doc comment says "an adapter that threw for half its port would be a trap for the next caller."
- **endpoint-projection**: `listAllEndpoints` MUST map each `EndpointView` to an `EndpointLite` holding exactly `id`, `siteId`, `url`, `kind`, `environment`, `platform`, `deployProject` and `ignoreProjectWarning`. The board's probe and monitoring fields (`expectedStatus`, `expectBody`, `dnsCheckA`, `dnsCheckAaaa`, `dnsCheckCname`, `checkIntervalSeconds`, `isActive`) MUST NOT appear in the output. This projection drops data deliberately.
- **opt-out-fold**: The projected `ignoreProjectWarning` MUST be `true` when the view's `ignoreProjectWarning === true`, or when its `isActive === false`, and `false` otherwise. This is `autoConfigureOptedOut` from `./config-status`, the same fold the server's adapter applies.
- **site-projection**: `listSites` MUST map each `SiteView` to exactly `{ id, slug, groupId }`. Every other field MUST be dropped.
- **update-passthrough**: `updateEndpoint(id, body)` MUST call the client's `updateEndpoint(client, id, body)` and resolve to what the client returns. The body is forwarded unchanged; the only check is a compile-time type cast.
- **create-site-projection**: `createSite(body)` MUST send only `name`, `slug` and `groupId` from `body`, and MUST resolve to `{ id }` taken from the created site.
- **create-endpoint-projection**: `createEndpoint(siteId, body)` MUST forward `body` unchanged and MUST resolve to the created endpoint passed through the same `EndpointLite` projection as `listAllEndpoints`.
- **delete-passthrough**: `deleteSite(id)` MUST call the client's `deleteSite(client, id)` and resolve when it resolves.
- **port-errors-propagate**: A rejection from any monitored-sites function MUST propagate unchanged out of the port method that called it. The adapter catches nothing.

### Match run: `runMatch`

- **match-only**: `runMatch` MUST call `runAutoConfigure` without a `create` option. A project that no existing endpoint monitors MUST therefore be skipped with the engine's reason `no site monitors this domain yet`, and MUST NOT cause any `createSite` or `createEndpoint` call.
- **injected-port-precedence**: When `opts.api` is supplied, `runMatch` MUST use it as the engine's port and MUST NOT construct one from `opts.client`.
- **client-required**: When `opts.api` is absent and `opts.client` is `undefined`, `runMatch` MUST reject with an `Error` whose message is `runMatch: opts.client is required when opts.api is not supplied`. It MUST NOT fall back to a default network client.
- **client-port**: When `opts.api` is absent and `opts.client` is supplied, `runMatch` MUST use `statusApi(opts.client)` as the port.
- **live-projects-forwarded**: `runMatch` MUST forward `opts.liveProjects` to the engine unchanged. The engine uses it to tell stale wiring apart from a live conflict.
- **progress-forwarded**: `runMatch` MUST forward `opts.onProgress` to the engine unchanged. The engine calls it as `(done, total)` once per project, after that project settles.
- **added-is-count**: `MatchRun.added` MUST equal the number of projects the engine reported in `added`. The engine's `created` list MUST NOT be counted; it is empty by construction because `create` is never passed.
- **skipped-flattened**: `MatchRun.skipped` MUST list one `{ project, reason }` per engine skip, in the engine's order. `project` MUST be the skipped project's `projectName` and `reason` MUST be the engine's reason text, unchanged.
- **notes-flattened**: `MatchRun.notes` MUST list one `{ project, note }` per engine note, in the engine's order. `project` MUST be the project's `projectName` and `note` MUST be the engine's note text, unchanged.
- **sequential-execution**: Projects MUST be applied strictly one after another, never in parallel, so that each match sees the wiring written by the previous one. This ordering is enforced by the engine's `applySequentially`, and `runMatch` MUST NOT reorder or batch `addable`.
- **per-project-resilience**: A project whose apply throws MUST be recorded in `skipped`, with the error's `message` as its reason (or `String(e)` for a non-`Error`), and MUST NOT stop the rest of the batch. The engine provides this behavior.
- **snapshot-failure-rejects**: When the engine's initial `listAllEndpoints` or `listSites` call rejects, `runMatch` MUST reject with that error. No partial `MatchRun` is returned.
- **one-snapshot-per-run**: Each `runMatch` call MUST read endpoints and sites once, at the start, and MUST plan every project against that snapshot as updated by the run's own writes. Other runs, whether in the browser or on the server, are not seen.
- **match-write-shape**: Each successful match MUST issue one `updateEndpoint` call whose body sets `platform`, `deployProject` and `environment`. The engine builds this body; `runMatch` does not alter it.

### Detail blocks: `skipDetail`, `noteDetail`

- **detail-line-limit**: `SKIP_DETAIL_LINES` MUST equal `5`, and both blocks MUST use it as their cap.
- **detail-empty**: `skipDetail` and `noteDetail` MUST return the empty string `""`, with no header, when their input is `undefined` or an empty array.
- **detail-leading-separator**: A non-empty block MUST start with two newlines (`"\n\n"`) and then its header line.
- **detail-row-format**: Each named row MUST read `• <project>: <why>` on its own line, in input order.
- **detail-cap**: A block MUST name at most the first `SKIP_DETAIL_LINES` rows.
- **detail-remainder**: When the input has more rows than `SKIP_DETAIL_LINES`, the block MUST end with a final line `…and <N> more`, where `N` is the input length minus the number of rows shown, not the total.
- **detail-no-remainder**: When the input has `SKIP_DETAIL_LINES` rows or fewer, the block MUST NOT contain a `…and` line.
- **skip-header**: `skipDetail` MUST use the header `Left alone:` and MUST take each row's `why` from `reason`.
- **note-header**: `noteDetail` MUST use the neutral header `Also:` and MUST take each row's `why` from `note`.
- **detail-pure**: `skipDetail` and `noteDetail` MUST be pure and synchronous, with no I/O and no mutation of their input.

### Concurrency and side effects

- **single-threaded**: All calls run on the browser's single JavaScript thread. Within one run, port calls are awaited one at a time, except for the engine's first read, which issues `listAllEndpoints` and `listSites` together via `Promise.all`.
- **no-cross-run-serialization**: `runMatch` MUST NOT serialize itself against other concurrent `runMatch` calls. Callers own that guard: `PlatformProjects` uses an `addingRef` so each platform panel runs one match at a time.
- **network-side-effects**: The only side effects of `runMatch` MUST be the port's HTTP calls through the supplied client: two reads, then one `updateEndpoint` per matched project.
- **no-timeout-or-retry**: `runMatch` MUST NOT add a timeout, retry or cancellation of its own. A hung request holds the run until the client's own transport settles. There is no `AbortSignal` parameter.

## Appearance

Not applicable — this is a non-visual adapter and text-formatting module, not a visual component.

## States

Not applicable — this is a non-visual adapter and text-formatting module, not a visual component.

## Accessibility

Not applicable — this is a non-visual adapter and text-formatting module, not a visual component.

## Conformance Test Vectors

Derived from `src/lib/auto-configure.test.ts` unless noted.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| autocfg-001 | endpoint-projection | `statusApi(client, fake)` where `listAllEndpoints` returns one `EndpointView` `{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false, expectedStatus:200, isActive:true, …}` | `listAllEndpoints()` resolves to exactly `[{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false}]` |
| autocfg-002 | opt-out-fold | Three views: `ignored` (`ignoreProjectWarning:true`), `paused` (`isActive:false`), `live` (neither) | Projected flags: `ignored → true`, `paused → true`, `live → false` |
| autocfg-003 | site-projection | `listSites` returns `{id:"s1", slug:"alpha", groupId:"g1", name:"Alpha", extra:"ignored"}` | `listSites()` resolves to `[{id:"s1", slug:"alpha", groupId:"g1"}]` |
| autocfg-004 | match-only | No endpoints or sites. `runMatch([{platform:"vercel", projectName:"help-production", domain:"agenticdeveloperhelp.com"}], {api})` | `createSite` and `createEndpoint` are never called. `added === 0`. `skipped[0]` is `{project:"help-production", reason}` with `reason` containing `no site monitors this domain` |
| autocfg-005 | added-is-count, skipped-flattened, match-write-shape | One endpoint `e1` on `https://a.com` (production). `runMatch` over `a-production` (a.com) and `b-production` (b.com) | `added === 1`. `skipped` equals `[{project:"b-production", reason:<string>}]`. One `updateEndpoint("e1", …)` call |
| autocfg-006 | client-required | `runMatch([], {})`, with no `api` and no `client` (derived from `requireClient`) | Rejects with `Error("runMatch: opts.client is required when opts.api is not supplied")` |
| autocfg-007 | injected-port-precedence | `runMatch(list, {api: fake, client: undefined})` (derived from `requireClient` being reached only when `api` is absent) | Resolves normally, and the fake port's methods are the ones called |
| autocfg-008 | detail-empty | `skipDetail(undefined)`, `skipDetail([])`, `noteDetail(undefined)`, `noteDetail([])` | Each returns `""` |
| autocfg-009 | skip-header, detail-row-format, detail-leading-separator | `skipDetail([{project:"p1", reason:"r1"}, {project:"p2", reason:"r2"}])` | `"\n\nLeft alone:\n• p1: r1\n• p2: r2"` |
| autocfg-010 | detail-no-remainder | `skipDetail` with exactly 5 rows | Splitting on `"\n• "` yields 6 parts, and the output does not contain `more` |
| autocfg-011 | detail-cap, detail-remainder | `skipDetail` with 7 rows p1..p7 | Contains `• p5: r5`, does not contain `• p6: r6`, and contains `…and 2 more` |
| autocfg-012 | note-header | `noteDetail([{project:"p1", note:"n1"}, {project:"p2", note:"n2"}])` | `"\n\nAlso:\n• p1: n1\n• p2: n2"` |
| autocfg-013 | detail-line-limit | `noteDetail` with 7 rows | Splitting on `"\n• "` yields 6 parts, and the output contains `…and 2 more` |
| autocfg-014 | per-project-resilience | Port where `updateEndpoint` rejects with `Error("boom")` for the first matching project, and a second project matches normally (derived from the engine's `applySequentially`) | First project is in `skipped` with reason `boom`. `added === 1` for the second |
| autocfg-015 | snapshot-failure-rejects | Port whose `listAllEndpoints` rejects with `Error("down")` (derived from `runAutoConfigure`) | `runMatch` rejects with `down`, and no `updateEndpoint` call is made |
| autocfg-016 | progress-forwarded | `runMatch` over 2 projects with `onProgress` spy (derived from `applySequentially`) | Spy called with `(1, 2)` and then `(2, 2)` |
| autocfg-017 | notes-flattened | Engine plan for project `x` wires an endpoint that `replaces` retired project `old` on `vercel` (derived from `executeAdd`) | `notes` equals `[{project:"x", note:"took over the monitor wired to old, which vercel no longer has"}]`, and `added === 1` |

## Edge Cases

- **Empty batch**: `runMatch([], opts)` with a valid port MUST still perform the two snapshot reads and MUST resolve to `{added: 0, skipped: [], notes: []}`. `onProgress` is never called because there are no items.
- **Missing client and missing api**: The run MUST reject with the `client-required` error before any network call.
- **Project with null domain**: The engine's planner owns the verdict. `runMatch` MUST pass the `ProjectLite` through unchanged and report whatever skip reason comes back.
- **Domain wired to another live project**: The run MUST record a skip with the engine's reason `that domain is already wired to <existingProject>`. This is a conflict, not an error.
- **Environment slot already taken**: The run MUST record a skip with the reason `its site's <environment> endpoint is already wired to <existingProject>`.
- **Opted-out or paused endpoint**: The endpoint MUST reach the engine with `ignoreProjectWarning: true`, so the engine's opt-out rules apply to it. Its `isActive` value never reaches the engine directly.
- **Per-project network failure**: The failing project MUST appear in `skipped` with the error message as its reason, and the batch MUST continue.
- **Snapshot read failure or server unreachable**: `runMatch` MUST reject. The caller renders the failure (`PlatformProjects` shows `Match failed — <message>`).
- **Non-Error thrown value**: The skip reason MUST be `String(value)`, per the engine's `msg`.
- **Concurrent runs**: Two overlapping `runMatch` calls each MUST plan against their own snapshot. Neither sees the other's writes, and the backend's conflict handling decides the outcome. Guarding against this is the caller's job.
- **Hung request**: No timeout exists in this module. The run MUST stay pending until the client's transport settles, and `onProgress` stops advancing.
- **Detail block with exactly 5 rows**: The block MUST list all 5 rows with no remainder line.
- **Detail block with 6 rows**: The block MUST list 5 rows followed by `…and 1 more`.
- **Project names or reasons containing newlines or bullets**: They MUST be inserted verbatim. The detail blocks do no escaping or sanitizing.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statusApi` `client` | `StatusApiClient` | none (required) | Client forwarded to every monitored-sites call |
| `statusApi` `api` | `typeof import("../api/monitored-sites")` | the real `monitored-sites` module | Backing functions; tests inject a fake module |
| `runMatch` `addable` | `ProjectLite[]` | none (required) | Projects to match, applied in array order |
| `runMatch` `opts.api` | `StatusAddApi` | `statusApi(opts.client)` | Injected engine port; takes precedence over `client` |
| `runMatch` `opts.client` | `StatusApiClient` | none | Required when `opts.api` is absent; no hidden default |
| `runMatch` `opts.liveProjects` | `PlanOpts["liveProjects"]` | `undefined` | Live-project index forwarded to the planner |
| `runMatch` `opts.onProgress` | `(done: number, total: number) => void` | `undefined` | Per-project progress callback |
| `SKIP_DETAIL_LINES` | `number` constant | `5` | Row cap shared by `skipDetail` and `noteDetail` |

No environment variables or settings keys are read.

## Deep Linking

Not applicable: the module exports functions and a constant and registers no route or URL.

## Localization

The detail blocks contain hardcoded English, with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `Left alone:` | `skipDetail` header |
| (none) | `Also:` | `noteDetail` header |
| (none) | `…and <N> more` | Remainder line in both blocks |
| (none) | `runMatch: opts.client is required when opts.api is not supplied` | `requireClient` error message, meant for developers |

The per-project reasons and notes are English text produced by the engine, and this module forwards them unchanged.

## Accessibility Options

Not applicable: the module renders nothing, so it cannot respond to display options such as Reduce Motion or Increase Contrast.

## Feature Flags

Not applicable: no flag is read. Match-only behavior is fixed by the absent `create` argument, not by a flag.

## Analytics

Not applicable: the module emits no analytics events.

## Privacy

Not applicable: the module handles only monitoring configuration (endpoint URLs, site slugs, deploy-project names). It stores nothing and transmits nothing beyond the injected client's calls to the status backend.

## Logging

Not applicable: the module makes no log calls. Failures reach the caller through `MatchRun.skipped` or a rejected promise.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | reliability |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | partial | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

The module passes separation-of-concerns: it is only an adapter and formatter, with matching delegated to the shared engine and rendering left to the components. `auto-configure.test.ts` covers the port projection, the opt-out fold, the match-only guarantee, result flattening and both detail blocks at, below and above the line limit, so unit-test-coverage passes. explicit-error-handling passes because the missing-client case throws a named error and port errors propagate unchanged. fault-tolerance passes because one project's failure is recorded in `skipped` and the batch continues. timeout-handling is partial: no timeout or cancellation exists here, and a hung request is bounded only by the client transport. data-integrity is partial: a run plans against a snapshot taken at its start and does not coordinate with concurrent runs. The caller's `addingRef` guard serializes runs within one platform panel, and the backend is the final arbiter across panels and sessions.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from status-web `src/lib/auto-configure.ts` |
