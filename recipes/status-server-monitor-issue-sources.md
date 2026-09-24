---
id: 86e7936a-c295-4e1f-8f7a-7278b4849008
title: Status Server Monitor Issue Sources
domain: agentictoolkit://recipes/status-server-monitor-issue-sources
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Deploy-provider status vocabulary: the IssueSource union and its labels,
  the integration-platform-to-health-source lookup, the HTTP/deploy bad-state predicates,
  the consecutive-failure streak step, and the vanished-Vercel-project narrowing that
  keeps deploy Problems from pinning open or going silent.'
platforms:
- typescript
- web
tags:
- monitor
- deploy
- vocabulary
- pure-function
- server
depends-on: []
related:
- agentictoolkit://recipes/status-server-monitor-deploy-status
references:
- packages/web/packages/status-server/src/monitor/issue-sources.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/overview.ts (agentictoolkit)
- packages/web/packages/deploy-platform/src/canon/index.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/ownership.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-problems.ts (agentictoolkit)
- packages/web/packages/status-server/src/libsql/stores/observation-store.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-deploy.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-monitoring.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/board-ownership.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/issue-sources.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Issue Sources

## Overview

`issue-sources.ts` (`packages/web/packages/status-server/src/monitor/issue-sources.ts`) is the status backend's vocabulary and predicate module for "where a problem came from" and "is this row currently a problem". It defines the `IssueSource` union (the seven values a Problem or an error row can be sourced from), `SOURCE_LABEL` and `ISSUE_SOURCES` for the source filter UI, and the lookup (`INTEGRATION_PLATFORM_SOURCE` / `platformHealthSource`) that reconciles the deploy-integration config vocabulary against the health/`IssueSource` vocabulary, because the two disagree about exactly one platform's spelling (`cloudflare` vs. `cloudflare-pages`). It then defines the small set of pure boolean/derivation predicates every board fold reads to judge HTTP state (`httpIsBad`), deploy state (`deployIsBad`, `deployIsStuck`, `deployIsResolving`, and the `STUCK_DEPLOY_MS` threshold), and provider-unreachability state (`PLATFORM_UNREACHABLE_POLLS`, `nextPlatformStreak`, `PlatformStreak`) — and finally `dropVanishedVercelProjects`, which narrows a site's configured Vercel deploy targets to the ones that still exist upstream, so a project deleted at the provider cannot pin an unclearable "failed" Problem open forever. Every exported member is synchronous and pure: the file performs no network call, no database read or write, and no logging of its own; it is consumed by `board/ownership.ts`, `board/derive-problems.ts`, `board/facts.ts`, `libsql/stores/observation-store.ts`, `libsql/stores/config-store.ts`, and `monitor/issues.ts`, all external to it. `IssueSource`, `SOURCE_LABEL`, and `ISSUE_SOURCES` are also hand-mirrored, unenforced, on the client at `packages/web/packages/status-web/src/lib/issue-sources.ts` (see Design Decisions).

## Behavioral Requirements

### Issue Source Vocabulary

- **issue-source-values**: `IssueSource` MUST be exactly one of `"dns"`, `"http"`, `"glitchtip"`, `"vercel"`, `"cloudflare-pages"`, `"railway"`, or `"crunchy"`.
- **glitchtip-distinct-signal**: `"glitchtip"` MUST be treated as answering a different question from every other `IssueSource` — per the type's own doc comment, the other sources answer "is the thing reachable" while `glitchtip` answers "is the thing THROWING" — so a site MAY be reported healthy by every other source while a `glitchtip`-sourced Problem is open at the same time.
- **source-label-completeness**: `SOURCE_LABEL` MUST supply exactly one display string for every `IssueSource` member: `dns` → `"DNS"`, `http` → `"HTTP"`, `glitchtip` → `"GlitchTip"`, `vercel` → `"Vercel"`, `cloudflare-pages` → `"Cloudflare"`, `railway` → `"Railway"`, `crunchy` → `"Crunchy Bridge"`.
- **issue-sources-canonical-order**: `ISSUE_SOURCES` MUST list all seven `IssueSource` values in exactly this order: `dns`, `http`, `glitchtip`, `vercel`, `cloudflare-pages`, `railway`, `crunchy` — the order the source filter UI renders them in.

### Deploy Integration → Health Source Mapping

- **integration-platform-source-mapping**: `platformHealthSource` MUST map the normalized integration-platform string `"vercel"` to `"vercel"`, `"cloudflare"` to `"cloudflare-pages"`, `"cloudflare-pages"` to `"cloudflare-pages"`, `"railway"` to `"railway"`, and `"crunchy"` to `"crunchy"`.
- **integration-platform-source-normalization**: `platformHealthSource` MUST normalize its `integrationPlatform` argument by trimming whitespace and lowercasing before the lookup, and MUST treat a `null` argument identically to an empty string (both normalize to `""`).
- **integration-platform-source-unmapped**: `platformHealthSource` MUST return `null` for any normalized string not in the five listed above — including `""`, `"dns"`, `"http"`, `"glitchtip"`, and any unrecognized platform string — because those platforms are never polled for platform-level reachability.
- **cloudflare-spelling-not-a-cast**: `platformHealthSource` MUST resolve the mapping through the `INTEGRATION_PLATFORM_SOURCE` lookup table rather than a type cast of its input, because per the source's own doc comment the deploy-integration config vocabulary (`"cloudflare"`, from the vendored provider-connection config reader) and the `IssueSource`/`platform_health_state.source` vocabulary (`"cloudflare-pages"`) disagree about that one platform's spelling — a cast would compile, run, and silently produce no match for exactly that platform.
- **cloudflare-both-spellings-accepted**: `platformHealthSource` MUST accept both `"cloudflare"` and `"cloudflare-pages"` as input and MUST map both to the single output `"cloudflare-pages"`, because a deploy integration's `platform` column accepts either spelling as a free string at creation time (`createIntegration`, external to this file, in `libsql/stores/config-store.ts`).

### HTTP Verdict

- **http-is-bad-definition**: `httpIsBad(status)` MUST return `true` if and only if `status` is `"down"` or `"degraded"`, and MUST return `false` for `"healthy"`.

### Deploy Verdict

- **deploy-is-bad-definition**: `deployIsBad(status)` MUST return `true` if and only if `status` is `"failed"`, and MUST return `false` for every other `DeployStatus` value (`"success"`, `"building"`, `"queued"`, `"canceled"`, `"unknown"`).
- **deploy-is-bad-excludes-canceled**: `deployIsBad` MUST NOT treat `"canceled"` as bad, because per the function's own doc comment a canceled build is the ABSENCE of a verdict, not a good one — Vercel's Ignored Build Step cancels a deployment for every site a commit did not touch, making `"canceled"` the ordinary newest state of a low-churn site; judging it as bad would both pin an open Problem open forever and hide a later real failure that lands after it.
- **deploy-is-bad-newest-outcome-precondition**: callers of `deployIsBad` MUST feed it the newest deploy row that reached a verdict — per the function's own doc comment, this is the caller's obligation (documented at the call site as `HAS_OUTCOME` filtering, external to this file), not something `deployIsBad` itself can enforce, because it receives only a single `DeployStatus` value with no row ordering context.
- **stuck-deploy-threshold-value**: `STUCK_DEPLOY_MS` MUST be exactly `1,800,000` (30 minutes expressed as `30 * 60 * 1000`).
- **deploy-is-stuck-definition**: `deployIsStuck(status, ageMs)` MUST return `true` if and only if `status` is `"building"` AND `ageMs` is greater than or equal to `STUCK_DEPLOY_MS`.
- **deploy-is-stuck-excludes-queued**: `deployIsStuck` MUST return `false` for `status === "queued"` regardless of `ageMs`, because per the function's own doc comment a long-queued deploy is almost always an INTENTIONAL hold (a Railway deploy awaiting approval, a Vercel build gated by the Ignored Build Step or concurrency limits) rather than a wedge, and flagging those paged on-call for deploys that were working as designed.
- **deploy-is-resolving-definition**: `deployIsResolving(status)` MUST return `true` if and only if `status` is `"success"`, and MUST return `false` for every other `DeployStatus` value.

### Platform-Unreachable Streak

- **platform-unreachable-poll-threshold-value**: `PLATFORM_UNREACHABLE_POLLS` MUST be exactly `2`.
- **platform-streak-shape**: A `PlatformStreak` value MUST carry exactly two fields: `streak: number` (the new consecutive-failure count to persist) and `bad: boolean` (whether the platform-health issue should be open this cycle).
- **next-platform-streak-increment**: `nextPlatformStreak(prevStreak, failing, threshold)` MUST return `streak: prevStreak + 1` when `failing` is `true`.
- **next-platform-streak-reset**: `nextPlatformStreak` MUST return `streak: 0` when `failing` is `false`, regardless of `prevStreak` — per the function's own doc comment, a single reachable poll clears the streak immediately; recovery is deliberately NOT debounced the way a failure is.
- **next-platform-streak-bad-threshold**: `nextPlatformStreak` MUST return `bad: true` if and only if `failing` is `true` AND the resulting `streak` is greater than or equal to `threshold`; it MUST return `bad: false` whenever `failing` is `false`, even if the passed-in `prevStreak` already met or exceeded `threshold`.
- **next-platform-streak-default-threshold**: `nextPlatformStreak` MUST default its `threshold` parameter to `PLATFORM_UNREACHABLE_POLLS` when the caller omits it.
- **next-platform-streak-single-transient-blip-debounced**: `nextPlatformStreak` MUST NOT report `bad: true` for a single failing poll following an all-reachable history (`prevStreak: 0`, `failing: true` → `streak: 1`, `bad: false` at the default threshold of `2`) — per the module's own doc comment on `PLATFORM_UNREACHABLE_POLLS`, this debounces a one-off transient API blip (a `429` or a timeout) that would otherwise open and immediately auto-resolve an "unreachable" issue within a single poll cycle.

### Vanished Vercel Project Narrowing

- **configured-deploy-targets-shape**: A `ConfiguredDeployTargets` value MUST carry exactly three fields — `vercel`, `railway`, and `cloudflare`, each a `ReadonlySet<string>` — keyed by canonical platform (Cloudflare's `cloudflare-pages` config spelling folds to `cloudflare` at this boundary).
- **drop-vanished-computes-set-difference**: `dropVanishedVercelProjects(configured, liveVercelProjects)` MUST compute `vanished` as every member of `configured.vercel` that is NOT a member of `liveVercelProjects`, and MUST leave the `railway` and `cloudflare` fields of the returned `configured` untouched in every case.
- **drop-vanished-empty-live-guard**: `dropVanishedVercelProjects` MUST return `vanished: []` and the unmodified `configured` when `liveVercelProjects.size === 0`, narrowing nothing — per the function's own doc comment, an empty live set is indistinguishable from "the account read came back empty because the token was rescoped" and MUST NOT be read as "every project was deleted".
- **drop-vanished-whole-fleet-guard**: `dropVanishedVercelProjects` MUST return `vanished: []` and the unmodified `configured` when every member of `configured.vercel` is absent from `liveVercelProjects` (i.e. `vanished.length === configured.vercel.size` and `configured.vercel.size > 0`) — per the function's own doc comment, a non-empty live read naming none of the configured projects is indistinguishable from a re-scoped token or a project transfer, and MUST NOT be read as a real mass deletion.
- **drop-vanished-partial-narrowing**: `dropVanishedVercelProjects` MUST, when `vanished` is non-empty and smaller than `configured.vercel.size`, return `vanished` populated with exactly the missing project names AND a `configured.vercel` narrowed to exclude them.
- **drop-vanished-vercel-only-scope**: `dropVanishedVercelProjects` MUST narrow only the `vercel` field; per the function's own doc comment, Railway and Cloudflare projects are polled live on every enumeration and so have no equivalent staleness problem, and this function has no Railway/Cloudflare counterpart.

## Appearance

Not applicable — this is a status-vocabulary, predicate, and set-reconciliation module, not a visual component.

## States

Not applicable — this is a status-vocabulary, predicate, and set-reconciliation module, not a visual component; its runtime verdict values (`IssueSource`, `DeployStatus`-derived booleans, `PlatformStreak`) are data this module derives, not a visual-state table, and are specified under Behavioral Requirements.

## Accessibility

Not applicable — this is a status-vocabulary, predicate, and set-reconciliation module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-issue-sources-001 | source-label-completeness, issue-sources-canonical-order | `ISSUE_SOURCES.map(s => SOURCE_LABEL[s])` | `["DNS", "HTTP", "GlitchTip", "Vercel", "Cloudflare", "Railway", "Crunchy Bridge"]` — traced directly to the `SOURCE_LABEL` object literal and `ISSUE_SOURCES` array literal; the client's own mirror asserts the weaker property `for (const s of ISSUE_SOURCES) expect(SOURCE_LABEL[s]).toBeTruthy()` in `status-web/src/lib/issue-sources.test.ts` |
| status-server-monitor-issue-sources-002 | integration-platform-source-mapping, cloudflare-both-spellings-accepted | `platformHealthSource("cloudflare")`; `platformHealthSource("cloudflare-pages")` | Both `"cloudflare-pages"` — traced directly to the `INTEGRATION_PLATFORM_SOURCE` table; exercised indirectly via `storage.config.createIntegration({ platform: 'cloudflare', ... })` in `test/issues.test.ts` |
| status-server-monitor-issue-sources-003 | integration-platform-source-normalization | `platformHealthSource("  VERCEL  ")` | `"vercel"` — traced directly to the `.trim().toLowerCase()` normalization in the function body |
| status-server-monitor-issue-sources-004 | integration-platform-source-unmapped | `platformHealthSource(null)`; `platformHealthSource("glitchtip")`; `platformHealthSource("something-unknown")` | All three `null` — traced directly to the `?? null` fallback on the table lookup |
| status-server-monitor-issue-sources-005 | http-is-bad-definition | `httpIsBad("down")`; `httpIsBad("degraded")`; `httpIsBad("healthy")` | `true`, `true`, `false` — traced directly to the function body |
| status-server-monitor-issue-sources-006 | deploy-is-bad-definition, deploy-is-bad-excludes-canceled | `deployIsBad("failed")`; `deployIsBad("canceled")`; `deployIsBad("unknown")` | `true`, `false`, `false` — `deployIsBad("canceled")` exercised via `test/board-deploy.test.ts` › "7. a CANCELED deploy is not a verdict and is never a problem" |
| status-server-monitor-issue-sources-007 | stuck-deploy-threshold-value, deploy-is-stuck-definition | `deployIsStuck("building", STUCK_DEPLOY_MS - 60_000)`; `deployIsStuck("building", STUCK_DEPLOY_MS + 1)` | `false`, `true` — `test/board-deploy.test.ts` › "4. a deploy still BUILDING is not a problem" and "5. a deploy building past STUCK_DEPLOY_MS IS a problem" |
| status-server-monitor-issue-sources-008 | deploy-is-stuck-excludes-queued | `deployIsStuck("queued", STUCK_DEPLOY_MS * 10)` | `false` — `test/board-deploy.test.ts` › "6. a deploy QUEUED past the threshold is NOT stuck — a hold is intentional" |
| status-server-monitor-issue-sources-009 | deploy-is-resolving-definition | `deployIsResolving("success")`; `deployIsResolving("building")` | `true`, `false` — traced directly to the function body; exercised via `board/facts.ts`'s `binByOutcome`, which routes a `deployIsBad`/`deployIsResolving` row to `concluded` |
| status-server-monitor-issue-sources-010 | next-platform-streak-increment, next-platform-streak-single-transient-blip-debounced | `nextPlatformStreak(0, true)` | `{ streak: 1, bad: false }` — traced directly to the function body against the default `PLATFORM_UNREACHABLE_POLLS` threshold of `2` |
| status-server-monitor-issue-sources-011 | next-platform-streak-bad-threshold | `nextPlatformStreak(1, true)` | `{ streak: 2, bad: true }` — traced directly to the function body; the resulting threshold-met state is exercised (as a persisted `streak` value fed into `platformProblems`) by `test/board-monitoring.test.ts` › "an unreachable provider at the threshold IS a problem" |
| status-server-monitor-issue-sources-012 | next-platform-streak-reset | `nextPlatformStreak(5, false)` | `{ streak: 0, bad: false }` — traced directly to the function body's `failing ? prevStreak + 1 : 0` |
| status-server-monitor-issue-sources-013 | drop-vanished-computes-set-difference, drop-vanished-partial-narrowing | `dropVanishedVercelProjects({ vercel: new Set(["ghost-project", "live-project"]), railway: new Set(), cloudflare: new Set() }, new Set(["live-project"]))` | `{ configured: { vercel: new Set(["live-project"]), railway: new Set(), cloudflare: new Set() }, vanished: ["ghost-project"] }` — exercised (through `rosterTargets`) by `test/board-ownership.test.ts` › "a Vercel project DELETED upstream is invisible, even though a live site still wires it" |
| status-server-monitor-issue-sources-014 | drop-vanished-empty-live-guard | `dropVanishedVercelProjects({ vercel: new Set(["hub-web"]), railway: new Set(), cloudflare: new Set() }, new Set())` | `{ configured: <unchanged>, vanished: [] }` — exercised (through `rosterTargets`) by `test/board-ownership.test.ts` › "narrows NOTHING when the mirror is empty, or when it would delete the whole fleet" |
| status-server-monitor-issue-sources-015 | drop-vanished-whole-fleet-guard | `dropVanishedVercelProjects({ vercel: new Set(["hub-web"]), railway: new Set(), cloudflare: new Set() }, new Set(["something-else-entirely"]))` | `{ configured: <unchanged>, vanished: [] }` — same test as vector 014, second assertion in the same `it` |
| status-server-monitor-issue-sources-016 | drop-vanished-vercel-only-scope | `dropVanishedVercelProjects({ vercel: new Set(), railway: new Set(["shared-name"]), cloudflare: new Set() }, new Set(["hub-web"]))` | `{ configured: <unchanged>, vanished: [] }` — the Railway member is never inspected; exercised (through `rosterTargets`) by `test/board-ownership.test.ts` › "narrows by PLATFORM too — a Railway project sharing a vanished Vercel name survives" |

## Edge Cases

- **Null and empty input**: `platformHealthSource(null)` MUST be accepted and MUST return `null`, identically to `platformHealthSource("")` (integration-platform-source-unmapped) — MUST. `dropVanishedVercelProjects` called with `configured.vercel` an empty set MUST return `vanished: []` regardless of `liveVercelProjects`'s contents, because an empty set's filter is always empty (drop-vanished-computes-set-difference) — MUST. No function in this file rejects an empty string or an empty `Set`; each routes it through the same logic as any other value, per each function's documented contract, not an unvalidated-input gap.
- **Boundary values**: `deployIsStuck`'s only boundary is `ageMs === STUCK_DEPLOY_MS` exactly, which MUST return `true` (the comparison is `>=`) (deploy-is-stuck-definition) — MUST. `nextPlatformStreak`'s only boundary is `streak === threshold` exactly, which MUST set `bad: true` when `failing` is also `true`, by the same `>=` comparison (next-platform-streak-bad-threshold) — MUST. `dropVanishedVercelProjects`'s boundary between "partial" and "whole fleet" is `vanished.length === configured.vercel.size`; at that exact boundary the whole-fleet guard MUST win and narrow nothing (drop-vanished-whole-fleet-guard) — MUST.
- **Concurrent access**: every exported function in this file is a synchronous, pure computation over its arguments with no shared mutable module-level state and no `await`, so calls from any number of callers MUST NOT interleave in a way that changes any single call's result — MUST. `nextPlatformStreak` itself holds no state between calls — the counter it advances is persisted by its sole caller, `libsql/stores/observation-store.ts`'s `recordObservations`, which reads every prior streak in ONE query before writing any row for the batch specifically so this file's pure step function is never handed a stale `prevStreak` mid-batch; that read-then-write ordering is owned by the caller, external to this file.
- **Error states**: this file has no dependency of its own — no network call, no database access, no file I/O — so it has no error path to swallow, log, or surface; every function returns a value for every input via an explicit lookup-with-fallback, boolean expression, or comparison, never a thrown exception. What a caller's own dependency (the Vercel account-projects read that feeds `dropVanishedVercelProjects`'s `liveVercelProjects`, the `platform_health_state` table `nextPlatformStreak`'s result is persisted to) does on failure is those callers' concern, external to this file.
- **Offline / disconnected state**: not applicable — this file makes no network connection of its own to lose; the fetchers and account-mirror readers that supply its inputs (`fetch-vercel-projects.ts`, the provider poll loop that supplies `failing` to `nextPlatformStreak`, all external to this file) own whatever happens when their own outbound call fails, and simply pass this file whatever input that failure implies (e.g. `failing: true`, or an empty `liveVercelProjects` set).

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

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it exports only types, constants, lookup tables, and pure predicate/derivation functions.

## Localization

Not applicable: this file emits no user-facing string; `SOURCE_LABEL`'s English display strings (`"DNS"`, `"HTTP"`, `"GlitchTip"`, `"Vercel"`, `"Cloudflare"`, `"Railway"`, `"Crunchy Bridge"`) are hardcoded and unlocalized, and a UI layer external to this file (the source filter, the board's Problem badges) is responsible for rendering them as-is; this file provides no translation mechanism for them.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: none of this file's own — it receives already-derived status values (`HealthStatus`, `DeployStatus`), an integration's already-configured `platform` string, and a caller-supplied set of Vercel project names as plain function arguments; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing; the consecutive-failure count `nextPlatformStreak` advances is persisted by its caller to `platform_health_state` (`libsql/stores/observation-store.ts`), external to this file.
- **Transmission**: none. This file performs no network or database call of its own.
- **Retention**: not applicable — this file holds no data across calls.

## Logging

Not applicable: this file contains no logging call of any kind — every exported function is a pure synchronous lookup, predicate, or derivation with no side effects.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port would model `IssueSource` as a `Sendable`, `String`-backed `enum`, `SOURCE_LABEL` as a `[IssueSource: String]` dictionary (or a computed property on the enum), and `ConfiguredDeployTargets`/`PlatformStreak` as `Sendable struct`s; because every function here is a pure, synchronous, non-isolated computation, the ported functions need no `actor` or `@MainActor` isolation at all — plain top-level or static functions on a namespacing `enum` are the direct equivalent.
- **Compose**: same non-UI framing. A Kotlin port models `IssueSource` as an `enum class` with a `label: String` property in place of the separate `SOURCE_LABEL` map, and the predicate/derivation functions as top-level functions; `dropVanishedVercelProjects`'s set-difference reads directly onto Kotlin's `Set` operators (`subtract`/`minus`) with the same two-guard early-return shape.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/issue-sources.ts` as a plain ESM module on the Node status backend, imported by `board/ownership.ts`, `board/derive-problems.ts`, `board/facts.ts`, `libsql/stores/observation-store.ts`, `libsql/stores/config-store.ts`, and `monitor/issues.ts`; `IssueSource`, `SOURCE_LABEL`, and `ISSUE_SOURCES` are hand-mirrored (not imported, not build-shared) at `packages/web/packages/status-web/src/lib/issue-sources.ts` for the browser client, with no automated parity guard between the two copies (see Design Decisions).
- **AppKit / UIKit**: same non-UI framing as SwiftUI; this file has no mutable module-level state to duplicate across a per-thread or per-`Worker` boundary the way a stateful Node module might.
- **WinUI 3**: a .NET port models `IssueSource` as a C# `enum` with a companion `IReadOnlyDictionary<IssueSource, string>` for `SOURCE_LABEL` (or a `[Description]`-attributed enum read through a small extension method), `HealthStatus`/`DeployStatus` as C# `enum`s (ported alongside the sibling `deploy-status` recipe), and `ConfiguredDeployTargets`/`PlatformStreak` as `readonly record struct`s using `IReadOnlySet<string>` for the per-platform project sets. `HttpIsBad`, `DeployIsBad`, `DeployIsStuck`, `DeployIsResolving`, `PlatformHealthSource`, `NextPlatformStreak`, and `DropVanishedVercelProjects` all port as `static` methods (e.g. on an `IssueSources` class) using C# `switch` expressions or LINQ set operators (`Except`) in place of this file's ternaries and array `.filter`; `nextPlatformStreak`'s caller-owns-persistence contract maps directly onto a .NET repository/store class calling the pure step function before an `INSERT ... ON CONFLICT`-equivalent `UPSERT` via EF Core or `Microsoft.Data.Sqlite`, exactly as `observation-store.ts` does.

## Design Decisions

- **Decision**: resolve the deploy-integration `platform` string to an `IssueSource` through the `INTEGRATION_PLATFORM_SOURCE` lookup table (`platformHealthSource`) rather than a type cast, and accept both `"cloudflare"` and `"cloudflare-pages"` as valid input.
  **Rationale**: stated directly in the source comment — the config-side vocabulary and the health/`IssueSource` vocabulary disagree about exactly one platform's spelling, so a cast would compile, run, and silently produce no match for Cloudflare specifically; both spellings are accepted because `createIntegration` (external, in `libsql/stores/config-store.ts`) takes the platform as a free string, so either one may already be stored.
  **Approved**: pending
- **Decision**: give `deployIsBad` no opinion on `"canceled"` at all — neither good nor bad — rather than treating a canceled build as either a resolved Problem or an open one.
  **Rationale**: stated directly in the source comment — Vercel's Ignored Build Step cancels a deployment for every site a commit did not touch, making `"canceled"` the ordinary newest state of a low-churn site; judging it as bad would pin an open Problem open forever, and judging it as good would let a canceled retry mask a real failure on the row it superseded. The precondition this places on every caller — feed `deployIsBad` only the newest row that reached a verdict — is enforced entirely outside this file, by the `HAS_OUTCOME` row filter callers apply before selecting a row to judge.
  **Approved**: pending
- **Decision**: exempt `"queued"` from `deployIsStuck` entirely, flagging only `"building"` past `STUCK_DEPLOY_MS`.
  **Rationale**: stated directly in the source comment — a long-queued deploy is almost always an intentional hold (a Railway deploy awaiting approval, a Vercel build gated by concurrency limits), and flagging those paged on-call for deploys that were working as designed; only an actively-building deploy that never lands is treated as wedged.
  **Approved**: pending
- **Decision**: give `nextPlatformStreak` a `bad` field that only the debounce logic computes, while its sole caller (`observation-store.ts`'s `recordObservations`) reads only the `streak` half and discards `bad`.
  **Rationale**: stated directly in the caller's own source comment — the threshold decision belongs to `board/derive-problems.ts`'s `platformProblems`, which re-checks the PERSISTED `streak` against `PLATFORM_UNREACHABLE_POLLS` itself on every board read; the recorder's only job is advancing and persisting the count. `nextPlatformStreak` computes `bad` anyway so the function's contract is self-contained and independently testable, even though today's single caller does not consume it.
  **Approved**: pending
- **Decision**: `dropVanishedVercelProjects` declines to narrow (returns `vanished: []`) both when the live read is empty AND when it would remove every configured project, rather than trusting either read at face value.
  **Rationale**: stated directly in the source comment as two independently load-bearing guards — an empty live set is indistinguishable from a read that came back empty because the token was rescoped, not because the account was emptied; and a non-empty read naming none of the configured projects is indistinguishable from a re-scoped token or a project transfer returning a complete list of somebody else's projects. Both decline the narrowing rather than the underlying deletion, so the cost of a false guard is a board that keeps showing deploy Problems for a project that really was deleted — judged, per the same comment, as far cheaper than silently losing every monitor for the fleet in one bad read.
  **Approved**: pending
- **Decision** (`mirror-parity-guard`, SHOULD): the hand-mirrored client copy of `IssueSource`/`SOURCE_LABEL`/`ISSUE_SOURCES` at `status-web/src/lib/issue-sources.ts` SHOULD gain a cross-package parity test analogous to `deploy-status-parity.test.ts`, which performs this same role for the sibling `deploy-status.ts` module.
  **Rationale**: the client file's own doc comment names the exact failure mode of an unguarded drift — "a source the server can emit and the client has never heard of renders `undefined` in the filter and the badge" — but, unlike `deploy-status.ts`, no test in either package currently asserts the two copies agree; `status-web/src/lib/issue-sources.test.ts` only asserts the client copy's own internal consistency (every `ISSUE_SOURCES` member has a truthy label), never that it matches this file. This is an absent safeguard for a documented risk, not a defect in this file's own behavior, so it is recorded here as a deviation-with-rationale rather than a source-fidelity gap.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |

`unit-test-coverage` is `partial`: this file has no dedicated test file of its own. `platformHealthSource`'s Cloudflare-spelling reconciliation and `deployIsStuck`/`STUCK_DEPLOY_MS`/`PLATFORM_UNREACHABLE_POLLS` are each exercised, but only indirectly, through the board-fold test suites that import these constants and drive them through `deployProblems`/`platformProblems` (`test/board-deploy.test.ts`, `test/board-monitoring.test.ts`) and through `dropVanishedVercelProjects` via `rosterTargets` (`test/board-ownership.test.ts`); `httpIsBad`, `deployIsBad`, `deployIsResolving`, `nextPlatformStreak`, `SOURCE_LABEL`, and `ISSUE_SOURCES` have no test — direct or indirect — asserting their literal values or full branch behavior, only the client's own mirror asserts a weaker property on the label/order pair. `separation-of-concerns` passes: this file's only responsibility is the issue-source vocabulary, its integration-platform reconciliation, and the pure predicates/derivations built on that vocabulary; it performs no I/O, no persistence, and no presentation of its own, leaving those to the board-fold and storage-layer files that call it. `fault-tolerance` passes: `platformHealthSource` and `dropVanishedVercelProjects` both accept external, potentially malformed or unexpected input (an unrecognized platform string, a `null` platform, an empty or all-or-nothing live-project read) and resolve every case to a documented fallback (`null`, or "narrow nothing") rather than throwing or producing an undefined result. `data-integrity` passes: the Cloudflare spelling reconciliation and the two emptiness guards in `dropVanishedVercelProjects` exist specifically to stop a vocabulary mismatch or an unreliable upstream read from corrupting the board's Problem set — either by silently failing to match a platform's health row, or by narrowing (and thereby hiding or reopening) deploy Problems on the strength of a read that cannot be told apart from a bad one; the actual persistence of the streak this file computes is owned by `libsql/stores/observation-store.ts`, external to this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
