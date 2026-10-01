---
id: cd71721b-e80e-4525-a7a1-fc1ac2158267
title: Auto Configure
domain: agentictoolkit://cookbook/status/dashboard/logic/auto-configure
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A client-side adapter onto the shared auto-configure engine, running
  match-only against a port contract mapped onto monitoring configuration,
  with capped per-project detail blocks for what it left alone or noted.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status/dashboard/api
- agentictoolkit://cookbook/status/dashboard/state/config-status
references: []
approved-by: ''
approved-date: ''
---

# Auto Configure

## Overview

This adapter is the status dashboard's client-side entry point into "Auto
Configure". It does no matching of its own: the planner, classifier, and
runner belong to the shared auto-configure engine, the same logic the backend
runs behind `POST /auto-configure`. The reason is explained directly: a
second, hand-written copy of the planner risked canonicalizing a host
differently on each side, filing the same project under different sites
depending on which side acted.

This adapter provides three things: a port adapter that maps the
monitoring-configuration client onto the engine's port contract; a match
operation that runs the engine match-only (it never asks it to create) and
flattens the result into the match-result shape a dialog renders; and a pair
of detail-block builders that build the "Left alone:" and "Also:" text blocks
appended to the engine's own summary sentence, each capped at a fixed number
of named projects.

Callers: a per-platform project panel calls the match operation for its
"Match" and "Match all" actions. A global summary panel appends the note and
skip detail blocks to the backend-driven global "Auto Configure" summary. Site
creation stays on the backend, because only the backend sees every site in one
transaction-scoped snapshot.

## Behavioral Requirements

### Port adapter

- **port-shape**: constructing the port adapter, given a client, MUST return
  an object implementing all six operations of the engine's port contract:
  listing every endpoint, listing sites, updating an endpoint, creating a
  site, creating an endpoint, and deleting a site.
- **port-default-api**: when no backing implementation is supplied, the port
  adapter MUST use the monitoring-configuration client's own functions as its
  backing implementation.
- **port-client-passthrough**: every port operation MUST forward the supplied
  client as the first argument to the matching monitoring-configuration
  client function.
- **port-create-methods-wired**: the create-site, create-endpoint, and
  delete-site operations MUST be fully wired to the client even though the
  match operation never reaches them. The design intent stated alongside
  them: "an adapter that threw for half its port would be a trap for the next
  caller."
- **endpoint-projection**: listing every endpoint MUST map each endpoint view
  to a projected shape holding exactly `id`, `siteId`, `url`, `kind`,
  `environment`, `platform`, `deployProject`, and `ignoreProjectWarning`. The
  endpoint's probe and monitoring fields (`expectedStatus`, `expectBody`,
  `dnsCheckA`, `dnsCheckAaaa`, `dnsCheckCname`, `checkIntervalSeconds`,
  `isActive`) MUST NOT appear in the output. This projection drops data
  deliberately.
- **opt-out-fold**: the projected `ignoreProjectWarning` MUST be `true` when
  the endpoint's own `ignoreProjectWarning` is `true`, or when its `isActive`
  is `false`, and `false` otherwise. This is the same opt-out fold the
  config-status logic and the backend's own adapter apply.
- **site-projection**: listing sites MUST map each site view to exactly
  `{ id, slug, groupId }`. Every other field MUST be dropped.
- **update-passthrough**: updating an endpoint MUST call the client's
  update-endpoint operation with the given identifier and body, and resolve
  to what it returns. The body is forwarded unchanged; the only check is a
  type check, not a runtime validation.
- **create-site-projection**: creating a site MUST send only `name`, `slug`,
  and `groupId` from the caller's body, and MUST resolve to `{ id }` taken
  from the created site.
- **create-endpoint-projection**: creating an endpoint MUST forward the
  caller's body unchanged and MUST resolve to the created endpoint passed
  through the same projection as listing every endpoint.
- **delete-passthrough**: deleting a site MUST call the client's delete-site
  operation with the given identifier and resolve when it resolves.
- **port-errors-propagate**: a rejection from any monitoring-configuration
  client operation MUST propagate unchanged out of the port operation that
  called it. The adapter catches nothing.

### Match operation

- **match-only**: the match operation MUST run the shared engine without a
  create option. A project that no existing endpoint monitors MUST therefore
  be skipped with the engine's reason `no site monitors this domain yet`,
  and MUST NOT cause any create-site or create-endpoint call.
- **injected-port-precedence**: when an engine port is supplied directly, the
  match operation MUST use it as the engine's port and MUST NOT construct
  one from a supplied client.
- **client-required**: when no port and no client is supplied, the match
  operation MUST reject with an error whose message is `runMatch:
  opts.client is required when opts.api is not supplied`. It MUST NOT fall
  back to a default network client.
- **client-port**: when no port is supplied but a client is, the match
  operation MUST build the port adapter from that client and use it.
- **live-projects-forwarded**: the match operation MUST forward the caller's
  live-project index to the engine unchanged. The engine uses it to tell
  stale wiring apart from a live conflict.
- **progress-forwarded**: the match operation MUST forward the caller's
  progress callback to the engine unchanged. The engine calls it as
  `(done, total)` once per project, after that project settles.
- **added-is-count**: the match result's `added` count MUST equal the number
  of projects the engine reported as added. The engine's created list MUST
  NOT be counted; it is empty by construction because create is never
  requested.
- **skipped-flattened**: the match result's `skipped` list MUST list one
  `{ project, reason }` per engine skip, in the engine's order. `project`
  MUST be the skipped project's name and `reason` MUST be the engine's
  reason text, unchanged.
- **notes-flattened**: the match result's `notes` list MUST list one
  `{ project, note }` per engine note, in the engine's order. `project` MUST
  be the project's name and `note` MUST be the engine's note text,
  unchanged.
- **sequential-execution**: projects MUST be applied strictly one after
  another, never concurrently, so that each match sees the wiring written by
  the previous one. This ordering is enforced by the engine itself, and the
  match operation MUST NOT reorder or batch its input.
- **per-project-resilience**: a project whose apply fails MUST be recorded in
  the skip list, with the failure's message as its reason (or a string
  conversion for a non-error failure), and MUST NOT stop the rest of the
  batch. The engine provides this behavior.
- **snapshot-failure-rejects**: when the engine's initial read of every
  endpoint or every site rejects, the match operation MUST reject with that
  error. No partial match result is returned.
- **one-snapshot-per-run**: each match-operation call MUST read endpoints and
  sites once, at the start, and MUST plan every project against that
  snapshot as updated by the run's own writes. Other runs, whether on this
  adapter or the backend, are not seen.
- **match-write-shape**: each successful match MUST issue one
  update-endpoint call whose body sets `platform`, `deployProject`, and
  `environment`. The engine builds this body; the match operation does not
  alter it.

### Detail blocks

- **detail-line-limit**: the shared row cap MUST equal `5`, and both
  detail-block builders MUST use it as their cap.
- **detail-empty**: the skip-detail and note-detail block builders MUST
  return the empty string `""`, with no header, when their input is absent
  or an empty list.
- **detail-leading-separator**: a non-empty block MUST start with two
  newlines (`"\n\n"`) and then its header line.
- **detail-row-format**: each named row MUST read `• <project>: <why>` on
  its own line, in input order.
- **detail-cap**: a block MUST name at most the first rows up to the shared
  row cap.
- **detail-remainder**: when the input has more rows than the cap, the block
  MUST end with a final line `…and <N> more`, where `N` is the input length
  minus the number of rows shown, not the total.
- **detail-no-remainder**: when the input has the cap's row count or fewer,
  the block MUST NOT contain a `…and` line.
- **skip-header**: the skip-detail block builder MUST use the header
  `Left alone:` and MUST take each row's `why` from `reason`.
- **note-header**: the note-detail block builder MUST use the neutral header
  `Also:` and MUST take each row's `why` from `note`.
- **detail-pure**: both block builders MUST be pure and synchronous, with no
  I/O and no mutation of their input.

### Concurrency and side effects

- **single-threaded**: within one run, port calls are awaited one at a time,
  except for the engine's first read, which issues the endpoint list and the
  site list together, concurrently rather than sequentially.
- **no-cross-run-serialization**: the match operation MUST NOT serialize
  itself against other concurrent match-operation calls. Callers own that
  guard: the per-platform project panel runs one match at a time per
  platform.
- **network-side-effects**: the only side effects of a match run MUST be the
  port's calls through the supplied client: two reads, then one
  update-endpoint call per matched project.
- **no-timeout-or-retry**: the match operation MUST NOT add a timeout,
  retry, or cancellation of its own. A hung request holds the run until the
  client's own transport settles. There is no cancellation parameter.

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
| autocfg-001 | endpoint-projection | Constructing the port adapter over a fake backing implementation whose endpoint list returns one endpoint view `{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false, expectedStatus:200, isActive:true, …}` | the port's endpoint-list operation resolves to exactly `[{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false}]` |
| autocfg-002 | opt-out-fold | Three endpoint views: `ignored` (`ignoreProjectWarning:true`), `paused` (`isActive:false`), `live` (neither) | Projected flags: `ignored → true`, `paused → true`, `live → false` |
| autocfg-003 | site-projection | The port's site-list operation given a backing site view `{id:"s1", slug:"alpha", groupId:"g1", name:"Alpha", extra:"ignored"}` | resolves to `[{id:"s1", slug:"alpha", groupId:"g1"}]` |
| autocfg-004 | match-only | No endpoints or sites. Running a match over one project `{platform:"vercel", projectName:"help-production", domain:"agenticdeveloperhelp.com"}` with a supplied port | `createSite` and `createEndpoint` are never called. `added === 0`. `skipped[0]` is `{project:"help-production", reason}` with `reason` containing `no site monitors this domain` |
| autocfg-005 | added-is-count, skipped-flattened, match-write-shape | One endpoint `e1` on `https://a.com` (production). Running a match over two projects, `a-production` (a.com) and `b-production` (b.com) | `added === 1`. `skipped` equals `[{project:"b-production", reason:<string>}]`. One update-endpoint call for `e1` |
| autocfg-006 | client-required | Running a match over an empty project list with neither a port nor a client supplied | Rejects with `Error("runMatch: opts.client is required when opts.api is not supplied")` |
| autocfg-007 | injected-port-precedence | Running a match with both a supplied port and an explicitly absent client | Resolves normally, and the supplied port's operations are the ones called |
| autocfg-008 | detail-empty | Each detail-block builder called with an absent input, then with an empty list | Each returns `""` |
| autocfg-009 | skip-header, detail-row-format, detail-leading-separator | The skip-detail block builder given two skip rows: `{project:"p1", reason:"r1"}, {project:"p2", reason:"r2"}` | `"\n\nLeft alone:\n• p1: r1\n• p2: r2"` |
| autocfg-010 | detail-no-remainder | The skip-detail block builder given exactly 5 rows | Splitting on `"\n• "` yields 6 parts, and the output does not contain `more` |
| autocfg-011 | detail-cap, detail-remainder | The skip-detail block builder given 7 rows p1..p7 | Contains `• p5: r5`, does not contain `• p6: r6`, and contains `…and 2 more` |
| autocfg-012 | note-header | The note-detail block builder given two note rows: `{project:"p1", note:"n1"}, {project:"p2", note:"n2"}` | `"\n\nAlso:\n• p1: n1\n• p2: n2"` |
| autocfg-013 | detail-line-limit | The note-detail block builder given 7 rows | Splitting on `"\n• "` yields 6 parts, and the output contains `…and 2 more` |
| autocfg-014 | per-project-resilience | A port whose update-endpoint operation rejects with `Error("boom")` for the first matching project, and a second project that matches normally | First project is in `skipped` with reason `boom`. `added === 1` for the second |
| autocfg-015 | snapshot-failure-rejects | A port whose endpoint-list operation rejects with `Error("down")` | The match operation rejects with `down`, and no update-endpoint call is made |
| autocfg-016 | progress-forwarded | Running a match over 2 projects with a progress callback observed | Callback called with `(1, 2)` and then `(2, 2)` |
| autocfg-017 | notes-flattened | An engine plan for project `x` that wires an endpoint taking over from a retired project `old` on platform `vercel` | `notes` equals `[{project:"x", note:"took over the monitor wired to old, which vercel no longer has"}]`, and `added === 1` |

## Edge Cases

- **Empty batch**: running a match over an empty list, with a valid port,
  MUST still perform the two snapshot reads and MUST resolve to
  `{added: 0, skipped: [], notes: []}`. The progress callback is never
  called because there are no items.
- **Missing client and missing api**: the run MUST reject with the
  `client-required` error before any network call.
- **Project with no domain**: the engine's planner owns the verdict. The
  match operation MUST pass the project descriptor through unchanged and
  report whatever skip reason comes back.
- **Domain wired to another live project**: the run MUST record a skip with
  the engine's reason `that domain is already wired to <existingProject>`.
  This is a conflict, not an error.
- **Environment slot already taken**: the run MUST record a skip with the
  reason `its site's <environment> endpoint is already wired to
  <existingProject>`.
- **Opted-out or paused endpoint**: the endpoint MUST reach the engine with
  `ignoreProjectWarning: true`, so the engine's opt-out rules apply to it.
  Its `isActive` value never reaches the engine directly.
- **Per-project network failure**: the failing project MUST appear in
  `skipped` with the error message as its reason, and the batch MUST
  continue.
- **Snapshot read failure or backend unreachable**: the match operation MUST
  reject. The caller renders the failure (the per-platform project panel
  shows `Match failed — <message>`).
- **Non-error thrown value**: the skip reason MUST be a string conversion of
  the thrown value, per the engine's own formatting.
- **Concurrent runs**: two overlapping match-operation calls each MUST plan
  against their own snapshot. Neither sees the other's writes, and the
  backend's conflict handling decides the outcome. Guarding against this is
  the caller's job.
- **Hung request**: no timeout exists in this module. The run MUST stay
  pending until the client's transport settles, and the progress callback
  stops advancing.
- **Detail block with exactly 5 rows**: the block MUST list all 5 rows with
  no remainder line.
- **Detail block with 6 rows**: the block MUST list 5 rows followed by
  `…and 1 more`.
- **Project names or reasons containing newlines or bullets**: they MUST be
  inserted verbatim. The detail blocks do no escaping or sanitizing.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Port adapter's client | API client | none (required) | Client forwarded to every monitoring-configuration client call |
| Port adapter's backing implementation | monitoring-configuration client module | the real monitoring-configuration client | Backing functions; tests inject a fake module |
| Match operation's input list | list of project descriptors | none (required) | Projects to match, applied in list order |
| Match operation's supplied port | engine port contract | built from the supplied client | Injected engine port; takes precedence over a supplied client |
| Match operation's supplied client | API client | none | Required when no port is supplied; no hidden default |
| Match operation's live-project index | engine-defined shape | none | Live-project index forwarded to the planner |
| Match operation's progress callback | callback receiving `(done, total)` | none | Per-project progress callback |
| Shared row cap | number constant | `5` | Row cap shared by both detail-block builders |

No environment variables or settings keys are read.

## Deep Linking

Not applicable: the module exports functions and a constant and registers no route or URL.

## Localization

The detail blocks contain hardcoded English, with no localization lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none) | `Left alone:` | skip-detail block header |
| (none) | `Also:` | note-detail block header |
| (none) | `…and <N> more` | Remainder line in both blocks |
| (none) | `runMatch: opts.client is required when opts.api is not supplied` | the client-required check's error message, meant for developers |

The per-project reasons and notes are English text produced by the engine, and this module forwards them unchanged.

## Accessibility Options

Not applicable: the module renders nothing, so it cannot respond to display options such as Reduce Motion or Increase Contrast.

## Feature Flags

Not applicable: no flag is read. Match-only behavior is fixed by the absent create option, not by a flag.

## Analytics

Not applicable: the module emits no analytics events.

## Privacy

Not applicable: the module handles only monitoring configuration (endpoint URLs, site slugs, deploy-project names). It stores nothing and transmits nothing beyond the injected client's calls to the status backend.

## Logging

Not applicable: the module makes no log calls. Failures reach the caller through the match result's `skipped` list or a rejected promise.

## Platform Notes

- **SwiftUI**: Port the engine port contract as a `protocol` with `async throws` methods, and the match operation as an `async throws` function. Mark the result structs (`MatchRun`, `NotedAdd`) `Sendable`, and keep the loop sequential with a plain `for` and `await`, not a `TaskGroup`. The detail-block builder becomes a pure `String` builder using `prefix(5)`. Hand the strings to SwiftUI views unchanged.
- **Compose**: Port the port as a Kotlin `interface` with `suspend` functions, and the match operation as a `suspend fun` run in a `viewModelScope` coroutine. Use a sequential `for` loop, not `async`/`awaitAll`, and `runCatching` per project to reproduce the engine's resilience. The progress callback maps naturally to a `MutableStateFlow<Pair<Int, Int>>`.
- **React/Web**: Source platform. `auto-configure.ts` is plain TypeScript with no React. It depends on `../api/monitored-sites` (the HTTP functions), `../api/client` (the `StatusApiClient` type), `./config-status` (`autoConfigureOptedOut`) and `@agentic-toolkit/deploy-platform/engine` (`runAutoConfigure` and its types). Tests use Vitest with a fake monitored-sites module cast to `typeof import(...)`. The module's four exports are named `statusApi`, `runMatch`, `skipDetail`, and `noteDetail`; the port contract is the `StatusAddApi` interface, and the data shapes are `EndpointLite`, `SiteLite`, `MatchRun`, `ProjectLite`, and `NotedAdd`. `SKIP_DETAIL_LINES` is the shared row-cap constant, and the missing-client guard is a small `requireClient` helper that throws a plain `Error`. `update-passthrough`'s only check is a TypeScript compile-time type cast, not a runtime schema check. The concurrency assumption in Concurrency and side effects holds because this runs on the browser's single JavaScript thread; the engine's first read issues `listAllEndpoints` and `listSites` together via `Promise.all`. There is no `AbortSignal` parameter anywhere in this module — a hung request has no cancellation path. The two calling components are `components/configure/PlatformProjects.tsx` (the per-platform project panel) and `components/AutoConfigureProvider.tsx` (the global summary panel); the backend equivalent runs the same engine behind a Hono route at `POST /auto-configure`.
- **AppKit / UIKit**: Same port shape as SwiftUI, backed by `URLSession` `async` data tasks. Report progress to the main actor (`@MainActor` closure) before touching a progress indicator. The detail strings suit an `NSAlert` `informativeText` or a `UIAlertController` message.
- **WinUI 3**: Port the port as a C# `interface IStatusAddApi` with `Task<IReadOnlyList<EndpointLite>> ListAllEndpointsAsync()` and similar methods, implemented over a shared `HttpClient`, with `System.Text.Json` records for `EndpointLite`, `SiteLite` and `MatchRun`. Write `RunMatchAsync` as `async Task<MatchRun>` with a sequential `foreach` + `await` and a per-item `try/catch (Exception ex)` that records `ex.Message`. Throw `ArgumentNullException` in place of `requireClient`'s `Error`. Report progress through `IProgress<(int Done, int Total)>`: `Progress<T>` captures the UI `DispatcherQueue` context, so a `ProgressBar` bound to it updates safely. Unlike the source, .NET code idiomatically takes a `CancellationToken`. Adding one is a deliberate divergence; the source has no cancellation. Build the detail blocks with `string.Join("\n", rows.Take(5))` and show them in a `ContentDialog` or `InfoBar`. `ObservableCollection` is unnecessary because the result is a one-shot value.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/auto-configure.ts` |

## Design Decisions

**Decision**: The browser runs the shared engine through an adapter rather than its own planner. (Written from the browser adapter's perspective; the same reasoning applies to every platform's port.)
**Rationale**: The header comment calls a second copy "one piece of knowledge in two places with nothing checking they agree". The browser and the server could otherwise file the same project under different sites.
**Approved**: pending

**Decision**: Match-only is a property of the call (no `create` passed), not of a crippled port. The create methods stay wired.
**Rationale**: Creation needs a transaction-scoped view of every site, so it can pick the group that owns a domain family and disambiguate a taken slug. Only the server has that view. A port that threw for half its methods would trap the next caller.
**Approved**: pending

**Decision**: `runMatch` has no hidden default network client, so `opts.client` is required when `opts.api` is absent. (React/Web implementation — `runMatch`, `opts.client`, `opts.api`, and `requireClient` are this module's own names.)
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation from status-web `src/lib/auto-configure.ts` |
