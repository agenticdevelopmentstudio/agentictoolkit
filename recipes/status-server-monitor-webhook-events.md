---
id: 937650ae-ac85-43f4-8aa4-708207e0d745
title: Status Server Monitor Webhook Events
domain: agentictoolkit://recipes/status-server-monitor-webhook-events
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure, synchronous mappers that turn an untrusted Vercel or Railway webhook
  body into a ProviderDeploy row, or null when the event is not one this monitor ingests.
platforms:
- typescript
- web
tags:
- monitor
- webhook
- deploy
- mapper
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/input-validation
related:
- agentictoolkit://recipes/status-server-monitor-deploy-status
- agentictoolkit://recipes/status-server-monitor-format
- agentictoolkit://recipes/status-server-monitor-provider-deploy
- agentictoolkit://recipes/status-server-monitor-live-buffer
- agentictoolkit://recipes/status-server-monitor-fetch-vercel
- agentictoolkit://recipes/status-server-monitor-fetch-railway
references:
- packages/web/packages/status-server/src/monitor/webhook-events.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/format.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/hooks.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-mappers.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/timestamp-validation.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/hooks.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Webhook Events

## Overview

`webhook-events.ts` (`packages/web/packages/status-server/src/monitor/webhook-events.ts`) exports two pure, synchronous functions — `mapVercelDeployEvent` and `mapRailwayDeployEvent` — that each translate one already-JSON-parsed provider webhook body into a `ProviderDeploy` row (`./provider-deploy`, external), the same shape the poll fetchers produce, or return `null` when the body is not a deployment event this monitor ingests. Both functions are called exactly once each, by `routes/hooks.ts` (external), after that route has verified the request's signature or shared secret (`webhook-verify.ts`, external) and parsed the raw body as JSON; a non-`null` result is then passed to `storage.deploy.upsertDeployments` for persistence, to `pushDeployEvent` (`live-buffer.ts`, external) for the in-memory live overlay, and into the board's issue-derivation and alerting path — none of which this file performs itself. This file makes no network call, touches no database, and holds no state between calls; its only work is field extraction, a fixed lookup table (Vercel), a small string transform (Railway), and delegation to three sibling pure modules — `vercelPhases`/`railwayPhases` (`./deploy-status`, agentictoolkit://recipes/status-server-monitor-deploy-status) for the build/deploy lifecycle, `shortSha`/`commitFullMessage` (`./format`, agentictoolkit://recipes/status-server-monitor-format) for commit display fields, and `toValidDate` (`./provider-deploy`, agentictoolkit://recipes/status-server-monitor-provider-deploy) for the trust-boundary timestamp parse.

## Behavioral Requirements

### Signature and Purity

- **map-vercel-signature**: `mapVercelDeployEvent` MUST accept one `event: unknown` argument and MUST return either a `ProviderDeploy` object or `null`, synchronously.
- **map-railway-signature**: `mapRailwayDeployEvent` MUST accept one `event: unknown` argument and MUST return either a `ProviderDeploy` object or `null`, synchronously.
- **pure-no-io**: Neither `mapVercelDeployEvent` nor `mapRailwayDeployEvent` MUST perform a network call, a database read or write, or any logging; both functions' only observable effect is their return value.
- **no-throw**: Neither function MUST throw for any `event` value, including `undefined`, `null`, an empty object `{}`, or a value whose nested fields are the wrong type — each function casts its argument to its own event interface and reads fields through optional chaining, so an absent or mistyped field flows into a `null`/`undefined` local rather than a thrown `TypeError`.

### Vercel Event-Type Lookup

- **vercel-state-table**: `mapVercelDeployEvent` MUST look up `event.type` in the fixed table `VERCEL_STATE`, which maps exactly the event-type strings `` deployment.created ``, `` deployment.build-requested ``, `` deployment.succeeded ``, `` deployment.ready ``, `` deployment.promoted ``, `` deployment.error ``, and `` deployment.canceled `` to a `{ readyState, readySubstate }` pair; every other event-type string, and an absent `type`, MUST fail the lookup.
- **vercel-unmapped-type-null**: When `event.type` is absent or does not appear in `VERCEL_STATE`, `mapVercelDeployEvent` MUST return `null` without inspecting `event.payload` at all.
- **vercel-created-queued**: `mapVercelDeployEvent` MUST map `` deployment.created `` to `{ readyState: "QUEUED", readySubstate: null }`. Per the table's own comment, `` created `` is the deployment ENTERING the queue, not a build starting — with Vercel admitting builds only as concurrency slots free, a fleet-wide push can leave a `` created `` deployment queued for minutes to hours.
- **vercel-build-requested-building**: `mapVercelDeployEvent` MUST map `` deployment.build-requested `` to `{ readyState: "BUILDING", readySubstate: null }`. Per the table's own comment, this is the transition OUT of the queue — the moment a build slot frees and the build actually starts; the comment records that this event type was previously absent from the table, so the mapper returned `null` and the ingest route silently dropped every queued-to-building transition even though the account's webhook subscription had always included it.
- **vercel-succeeded-ready-built**: `mapVercelDeployEvent` MUST map both `` deployment.succeeded `` and `` deployment.ready `` to `{ readyState: "READY", readySubstate: null }`.
- **vercel-promoted-built-promoted**: `mapVercelDeployEvent` MUST map `` deployment.promoted `` to `{ readyState: "READY", readySubstate: "PROMOTED" }`.
- **vercel-error-failed**: `mapVercelDeployEvent` MUST map `` deployment.error `` to `{ readyState: "ERROR", readySubstate: null }`.
- **vercel-canceled**: `mapVercelDeployEvent` MUST map `` deployment.canceled `` to `{ readyState: "CANCELED", readySubstate: null }`.

### Vercel Row Construction

- **vercel-missing-deployment-null**: After a successful `VERCEL_STATE` lookup, when `event.payload.deployment.id` or `event.payload.deployment.name` is falsy, `mapVercelDeployEvent` MUST return `null`.
- **vercel-id-prefix**: A returned Vercel row's `id` field MUST be the literal string `` vc_ `` concatenated with `event.payload.deployment.id`.
- **vercel-platform-literal**: A returned Vercel row's `platform` field MUST be the literal string `"vercel"`.
- **vercel-project-name**: A returned Vercel row's `projectName` field MUST be `event.payload.deployment.name`.
- **vercel-provider-project-id**: A returned Vercel row's `providerProjectId` field MUST be `event.payload.project.id` when present, otherwise `null`. Per the source's own comment, this is "the identity the board keys on, exactly as the poller records it" (`fetch-vercel-projects.ts`, external) and as `mapRailwayDeployEvent` also does below; without it a webhook-created row is matchable only by project NAME, so a project renamed upstream owns no board target until the next full poll overwrites the row, and because `upsertDeployments` (external) COALESCEs this column, a `null` here can never erase an id an earlier poll already learned for the same deployment.
- **vercel-phases-delegated**: A returned Vercel row's `buildPhase` and `deployPhase` fields MUST be the two properties of the object returned by `vercelPhases(state.readyState, state.readySubstate, target)`, where `target` is `event.payload.target ?? null` — spread directly into the row with no additional transformation in this file. See the Status Server Monitor Deploy Status recipe for `vercelPhases`'s own mapping contract.
- **vercel-environment**: A returned Vercel row's `environment` field MUST be `event.payload.target ?? null` — the same value passed as `vercelPhases`'s `target` argument.
- **vercel-commit-hash**: A returned Vercel row's `commitHash` field MUST be `shortSha(meta.githubCommitSha)`, where `meta` is `event.payload.deployment.meta ?? {}`.
- **vercel-commit-message**: A returned Vercel row's `commitMessage` field MUST be `commitFullMessage(meta.githubCommitMessage)`.
- **vercel-branch**: A returned Vercel row's `branch` field MUST be `meta.githubCommitRef ?? null`.
- **vercel-commit-repo**: A returned Vercel row's `commitRepo` field MUST be the string `` <githubCommitOrg>/<githubCommitRepo> `` when both `meta.githubCommitOrg` and `meta.githubCommitRepo` are truthy, otherwise `null`.
- **vercel-url**: A returned Vercel row's `url` field MUST be `event.payload.links.deployment` when present, otherwise, when `event.payload.deployment.url` is present, MUST be that value prefixed with the literal `` https:// ``, otherwise MUST be `null`.
- **vercel-created-at**: A returned Vercel row's `createdAt` field MUST be `toValidDate(event.createdAt) ?? new Date()` — the current wall-clock time (the webhook's receipt time) whenever `event.createdAt` is absent or does not parse to a finite `Date` via `toValidDate` (`./provider-deploy`, agentictoolkit://recipes/status-server-monitor-provider-deploy). Per the source's own comment, "a webhook is often the only witness of a terminal state, so approximate time beats a dropped event (and an Invalid Date must never leave this boundary)."

### Railway Status Derivation

- **railway-status-from-type**: The module-private `railwayStatusFromType` helper MUST return `undefined` when its `type` argument is falsy, and otherwise MUST return the substring of `type` after its last `.` character, uppercased — e.g. `` Deployment.crashed `` becomes `` CRASHED ``.
- **railway-status-precedence**: `mapRailwayDeployEvent` MUST derive its working `status` as `event.status ?? railwayStatusFromType(event.type)` — a present `event.status` field always wins over deriving one from `event.type`.

### Railway Row Construction

- **railway-missing-required-null**: `mapRailwayDeployEvent` MUST return `null` when any of the derived `status`, `event.id`, or `event.project.name` is falsy.
- **railway-id-prefix**: A returned Railway row's `id` field MUST be the literal string `` ry_ `` concatenated with `event.id`.
- **railway-platform-literal**: A returned Railway row's `platform` field MUST be the literal string `"railway"`.
- **railway-project-name**: A returned Railway row's `projectName` field MUST be `event.project.name`.
- **railway-provider-project-id**: A returned Railway row's `providerProjectId` field MUST be `event.project.id` when present, otherwise `null` — the same identity-preservation contract as vercel-provider-project-id, for the same reason.
- **railway-phases-delegated**: A returned Railway row's `buildPhase` and `deployPhase` fields MUST be the two properties of the object returned by `railwayPhases(status)`, spread directly into the row with no additional transformation in this file. See the Status Server Monitor Deploy Status recipe for `railwayPhases`'s own mapping contract.
- **railway-environment**: A returned Railway row's `environment` field MUST be `event.environment.name` when present, otherwise `null`.
- **railway-commit-hash**: A returned Railway row's `commitHash` field MUST be `shortSha(event.commitHash)` when `event.commitHash` is a `string`, otherwise `null` — a non-string `commitHash` (including `undefined`) is never passed to `shortSha`.
- **railway-commit-message**: A returned Railway row's `commitMessage` field MUST be `commitFullMessage(event.commitMessage)` when `event.commitMessage` is a `string`, otherwise `null`.
- **railway-branch**: A returned Railway row's `branch` field MUST be `event.branch` when it is a `string`, otherwise `null`.
- **railway-commit-repo**: A returned Railway row's `commitRepo` field MUST be `event.repo` when it is a `string` containing a `` / `` character, otherwise `null`.
- **railway-url**: A returned Railway row's `url` field MUST be the string `` https://railway.com/project/<event.project.id> `` when `event.project.id` is present, otherwise `null`.
- **railway-created-at**: A returned Railway row's `createdAt` field MUST be `toValidDate(event.timestamp) ?? new Date()`, with the identical receipt-time fallback contract as vercel-created-at. The source's own inline comment marks this as "the same fallback contract as the Vercel mapper."

## Appearance

Not applicable — this is a webhook-body-to-data-row mapper, not a visual component.

## States

Not applicable — this is a webhook-body-to-data-row mapper, not a visual component; it holds no runtime state machine of its own (each call is a single, independent, stateless translation), so there is no state to place under Behavioral Requirements either.

## Accessibility

Not applicable — this is a webhook-body-to-data-row mapper, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-webhook-events-001 | vercel-build-requested-building, vercel-created-queued, vercel-id-prefix | `mapVercelDeployEvent` called once with `type: "deployment.created"` and once with `type: "deployment.build-requested"`, both otherwise identical (`payload.deployment.id: "dpl_1"`, `payload.deployment.name: "hub-help-testing"`) | First call's `buildPhase` is `"queued"`; second call's `buildPhase` is `"building"`; both calls' `id` is `"vc_dpl_1"` — `deploy-mappers.test.ts` › "distinguishes entering the queue from leaving it" |
| status-server-monitor-webhook-events-002 | vercel-unmapped-type-null, vercel-missing-deployment-null | `mapVercelDeployEvent({ type: "project.created", ... })` and `mapVercelDeployEvent({})` | Both return `null` — `deploy-mappers.test.ts` › "returns null for an event type we do not ingest" |
| status-server-monitor-webhook-events-003 | vercel-missing-deployment-null | `mapVercelDeployEvent` with `type: "deployment.succeeded"` and `payload.deployment: { name: "hub-help-testing" }` (no `id`); separately with `payload.deployment: { id: "dpl_1" }` (no `name`) | Both calls return `null` — `deploy-mappers.test.ts` › "returns null when the deployment id or name is missing" |
| status-server-monitor-webhook-events-004 | vercel-environment, vercel-phases-delegated | `mapVercelDeployEvent` with `payload.target: null` and an otherwise-valid `deployment.succeeded` event | Result's `environment` is `null` — `deploy-mappers.test.ts` › "carries the environment from target, and null for a preview" |
| status-server-monitor-webhook-events-005 | vercel-provider-project-id | `mapVercelDeployEvent(vercelEvent())` where `vercelEvent()`'s `payload.project.id` is `"prj_abc123"` | Result's `providerProjectId` is `"prj_abc123"` — `deploy-mappers.test.ts` › "carries providerProjectId from payload.project — the identity the board keys on" |
| status-server-monitor-webhook-events-006 | vercel-provider-project-id | `mapVercelDeployEvent` with `payload.project` absent entirely | Result's `providerProjectId` is `null`, not `undefined` — `deploy-mappers.test.ts` › "falls back to null when the payload omits the project — never undefined-by-accident" |
| status-server-monitor-webhook-events-007 | vercel-created-at | `mapVercelDeployEvent` called with `createdAt` absent, and separately with `createdAt: "not-a-date"` | Both calls return a non-null row whose `createdAt.getTime()` is finite and `>=` the time just before the call — `deploy-mappers.test.ts` › "falls back to receipt time for a %s timestamp — never Invalid Date" (both cases); reconfirmed by `timestamp-validation.test.ts` › "vercel: a garbage createdAt falls back to receipt time, never Invalid Date" |
| status-server-monitor-webhook-events-008 | railway-status-from-type | `mapRailwayDeployEvent` with `status` absent and `type: "Deployment.crashed"` | Result's `buildPhase`/`deployPhase` are `"built"`/`"deployed"` (the `railwayPhases("CRASHED")` mapping) — `deploy-mappers.test.ts` › "derives the status from a dotted type when status is absent" |
| status-server-monitor-webhook-events-009 | railway-missing-required-null | `mapRailwayDeployEvent` with `id` absent; separately with both `status` and `type` absent; separately with `project: { id: "proj-uuid-1234" }` and no `name` | All three calls return `null` — `deploy-mappers.test.ts` › "returns null when the id, the status, or the project name is missing" |
| status-server-monitor-webhook-events-010 | railway-provider-project-id, railway-project-name | `mapRailwayDeployEvent(railwayEvent())` where `railwayEvent()`'s `project` is `{ id: "proj-uuid-1234", name: "adh-backend" }` | Result's `providerProjectId` is `"proj-uuid-1234"` and `projectName` is `"adh-backend"` — `deploy-mappers.test.ts` › "carries the project id through instead of discarding it" |
| status-server-monitor-webhook-events-011 | railway-provider-project-id | `mapRailwayDeployEvent` with `project: { name: "adh-backend" }` (no `id`) | Result's `providerProjectId` is `null` (via `?? null` at the call site) and `projectName` is `"adh-backend"` — `deploy-mappers.test.ts` › "still maps when no project id is present" |
| status-server-monitor-webhook-events-012 | railway-created-at | `mapRailwayDeployEvent` called with `timestamp` absent, and separately with `timestamp: "whenever"` | Both calls return a non-null row whose `createdAt.getTime()` is finite and `>=` the time just before the call — `deploy-mappers.test.ts` › "falls back to receipt time for a %s timestamp — never Invalid Date" (both cases); reconfirmed by `timestamp-validation.test.ts` › "railway: a garbage timestamp falls back to receipt time, never Invalid Date" |

## Edge Cases

- **Null and empty input**: `mapVercelDeployEvent(undefined)` and `mapVercelDeployEvent(null)` MUST return `null` rather than throw, because the cast to `VercelEvent` and every subsequent read uses optional chaining against a value that may itself be `undefined`/`null` (no-throw) — MUST. `mapRailwayDeployEvent({})` MUST return `null` via railway-missing-required-null (`event.id` is falsy) — MUST. An `event.payload.deployment.meta` that is absent MUST be treated as `{}` (vercel-commit-hash through vercel-commit-repo all read from that empty object rather than throwing on `undefined.githubCommitSha`) — MUST.
- **Boundary values**: `event.type` values are matched by exact string equality against `VERCEL_STATE`'s six keys; no prefix, case-insensitive, or fuzzy match is performed, so e.g. `` Deployment.Succeeded `` (wrong case) fails the lookup exactly like an unrelated string (vercel-unmapped-type-null) — MUST. `railwayStatusFromType` takes the segment after the LAST `.` in `type`, so a value with no `.` at all (e.g. `"CRASHED"`) returns that whole string uppercased, and a value with multiple dots (e.g. `"a.b.crashed"`) returns only the final segment — MUST, traced to `type.split(".").pop()`.
- **Concurrent access**: not a synchronization concern by construction — both functions are synchronous, take no lock, and read or write no module-scope or shared mutable state; each call's `state`, `dep`, `meta`, `target`, `status`, and `p` (Railway) are freshly-read locals scoped to that one call, so any number of concurrent callers observe fully independent results — MUST.
- **Error states**: neither function has a dependency of its own that can fail (no network call, no database access, no file I/O), so the only "error" either function can encounter is a malformed `event` value, and every one of those is routed to a `null` return (vercel-unmapped-type-null, vercel-missing-deployment-null, railway-missing-required-null) or to the `toValidDate ?? new Date()` receipt-time fallback (vercel-created-at, railway-created-at) rather than a thrown exception — MUST. Neither function logs anything of its own when it returns `null` or falls back to receipt time; the caller (`routes/hooks.ts`, external) is the one that decides what a `null` result means at the HTTP layer (a `200 { ok: true, ignored: true }` response, per that file, so the provider does not retry an event this monitor deliberately does not ingest) — this file itself communicates nothing beyond its return value.
- **Offline / disconnected state**: not applicable — this file makes no network connection of its own to lose; it is invoked only after `routes/hooks.ts` (external) has already received, signature-verified, and JSON-parsed the webhook body over an inbound HTTP request that this file has no part in.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `event` (parameter to `mapVercelDeployEvent`) | `unknown`, cast to the module-private `VercelEvent` shape | none — caller-supplied per call | The already-JSON-parsed Vercel webhook request body, handed in by `routes/hooks.ts` (external) after HMAC-SHA1 signature verification (`webhook-verify.ts`, external). |
| `event` (parameter to `mapRailwayDeployEvent`) | `unknown`, cast to the module-private `RailwayEvent` shape | none — caller-supplied per call | The already-JSON-parsed Railway webhook request body, handed in by `routes/hooks.ts` (external) after shared-secret verification. |
| `VERCEL_STATE` (module constant) | `Record<string, { readyState: string; readySubstate: string \| null }>` | the fixed 7-entry table under Vercel Event-Type Lookup | Not exposed to the caller or the environment; the sole source of the mapping from a Vercel event `type` string to a `readyState`/`readySubstate` pair. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it only maps an in-memory webhook body to an in-memory `ProviderDeploy` row or `null`; the HTTP routes that receive the webhooks (`` /hooks/vercel ``, `` /hooks/railway ``) belong to `routes/hooks.ts`, external to this file.

## Localization

Not applicable: this file produces no user-facing string of its own — every string field on a returned row (`projectName`, `commitMessage`, `branch`, `commitRepo`, `url`) is a verbatim pass-through, prefix, or concatenation of provider-supplied values, with no message catalog or locale-dependent formatting anywhere in this file.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; whether an event is ingested at all is determined entirely by the `VERCEL_STATE` lookup and the required-field checks documented under Behavioral Requirements, not a flag-service lookup.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind and performs no logging of its own (pure-no-io); its return value is the whole of its observable behavior.

## Privacy

- **Data collected**: this file reads, but does not itself request, whatever the provider's webhook body already contains: a deployment id, project id and name, environment/target, and commit metadata (`githubCommitSha`, `githubCommitMessage`, `githubCommitRef`, `githubCommitOrg`/`githubCommitRepo` for Vercel; `commitHash`, `commitMessage`, `branch`, `repo` for Railway) that the provider itself already recorded from the monitored project's own deploys. It collects no data from, and about, an end user of the monitored product.
- **Storage**: none in this file — it holds every field only in local variables for the duration of one synchronous call and returns a plain object; persisting the returned row (`storage.deploy.upsertDeployments`) and buffering it for live reads (`pushDeployEvent`) are both the caller's responsibility, external to this file.
- **Transmission**: none — this file makes no outbound call of any kind; it only reads an already-received, already-parsed request body handed to it by its caller.
- **Retention**: not applicable to this file directly — it retains nothing after either function returns; how long a persisted row survives is governed entirely by the caller's storage layer, external to this file.

## Logging

Not applicable: this file makes no `console.error`, `console.warn`, or any other logging call anywhere in either exported function or the private `railwayStatusFromType` helper (pure-no-io).

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models each function as a static, non-isolated function taking the provider's already-decoded webhook payload (a `Decodable` struct rather than `unknown`, since Swift's type system makes the "cast anything, read through optionals" pattern this file uses unnecessary) and returning `ProviderDeploy?`; the Vercel event-type table becomes a `[String: (readyState: String, readySubstate: String?)]` dictionary literal, and the Railway `type` suffix extraction becomes `type.split(separator: ".").last?.uppercased()`.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models each function as a top-level function over a `@Serializable` data class decoded by `kotlinx.serialization` rather than an `unknown`/cast pair, the Vercel table as a `mapOf(...)`, and the Railway suffix extraction as `type?.substringAfterLast('.')?.uppercase()`.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/webhook-events.ts` as two exported pure functions plus one private helper, on the Node status backend (Hono), imported only by `routes/hooks.ts`; it imports three sibling in-repo modules (`./deploy-status`, `./format`, `./provider-deploy`) and defines its own two module-private TypeScript interfaces (`VercelEvent`, `RailwayEvent`) that model only the subset of each provider's webhook payload this file reads.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this mapping pattern (e.g. a companion backend written in Swift on server-side infrastructure) has the identical no-UI framing; there is no AppKit/UIKit-specific concern to translate because neither exported function here touches a view, a window, or a run loop.
- **WinUI 3**: a .NET port models `mapVercelDeployEvent`/`mapRailwayDeployEvent` as static methods returning `ProviderDeploy?` (the same `record` shape the Status Server Monitor Provider Deploy recipe describes), taking the webhook body already deserialized by `System.Text.Json` into two record types mirroring `VercelEvent`/`RailwayEvent` (so the "cast `unknown`, read through `?.`" idiom becomes ordinary nullable-property access on a strongly-typed record, with no runtime cast needed) rather than a raw `JsonElement`/`object`; the fixed `VERCEL_STATE` table becomes a `static readonly Dictionary<string, (string ReadyState, string? ReadySubstate)>`; the Railway suffix extraction becomes `type?.Split('.').LastOrDefault()?.ToUpperInvariant()`; and the receipt-time fallback (`toValidDate(...) ?? new Date()`) becomes `ToValidDate(raw) ?? DateTimeOffset.UtcNow`, calling the same `ToValidDate` helper the Status Server Monitor Provider Deploy recipe's WinUI 3 notes describe. Both methods stay fully synchronous — `Task`/`async` is never needed, since neither performs I/O.

## Design Decisions

- **Decision**: add `` deployment.build-requested `` to `VERCEL_STATE` mapping to `{ readyState: "BUILDING", readySubstate: null }`, alongside the pre-existing `` deployment.created `` → `QUEUED` mapping.
  **Rationale**: stated directly in the source's own comment on the two entries — `` created `` is the deployment entering the queue, not a build starting, and with Vercel admitting builds only as concurrency slots free, a fleet-wide push fanning out to roughly 48 projects against few slots can leave a `` created `` deployment sitting queued for minutes to hours; mapping it to `BUILDING` would have claimed work that had not begun. `` build-requested `` is the transition out of the queue, and the comment records that this event type was previously absent from the table — so `mapVercelDeployEvent` returned `null` for it and the ingest route dropped it (`200 { ok: true, ignored: true }`) even though the account's webhook subscription had always included that event; the only reason a queued-to-building transition never appeared on the board was that this one mapping was missing.
  **Approved**: pending
- **Decision**: carry `providerProjectId` through on both the Vercel and Railway mappers (`event.payload.project.id ?? null` and `event.project.id ?? null`, respectively) rather than leaving it unset, even though `event.payload.project.id`/`event.project.id` were previously parsed and used elsewhere (the Railway URL) without being carried onto the row.
  **Rationale**: stated directly in the source comments on both fields — identity resolution is keyed as `providerProjectId ?? projectName` (per the Status Server Monitor Provider Deploy recipe's own `provider-project-id-identity-key` requirement), so a webhook row with no provider id is matchable only by project NAME; a project renamed upstream would then own no board target until the next full poll overwrote the row. Because `upsertDeployments` (external) COALESCEs this column on write, a `null` here can never erase an id an earlier poll already learned for the same deployment — carrying the field through costs nothing on a poll-then-webhook sequence and fixes the rename gap on a webhook-first sequence.
  **Approved**: pending
- **Decision**: fall back to `new Date()` (webhook receipt time) rather than dropping the event or propagating an Invalid Date, whenever `event.createdAt`/`event.timestamp` is absent or fails `toValidDate`.
  **Rationale**: stated directly in the source's inline comment on both mappers — "a webhook is often the only witness of a terminal state, so approximate time beats a dropped event (and an Invalid Date must never leave this boundary)." This trades timestamp precision (the row's `createdAt` may read a few milliseconds to seconds later than the provider's own event time) for never losing the one signal a webhook uniquely carries, and for never letting an Invalid Date reach `upsertDeployments`, external, which the Status Server Monitor Provider Deploy recipe's own `timestamp-validation.test.ts` framing describes as failing the whole deployments upsert cycle repeatedly.
  **Approved**: pending
- **Decision**: derive Railway's working `status` from the dotted `type` field (e.g. `` Deployment.crashed ``) only when `event.status` itself is absent, rather than always preferring `type` or requiring both.
  **Rationale**: not spelled out in an inline comment as a deliberate precedence choice beyond the type annotation's own note that `type` is "used when `status` is absent," but demonstrated as intentional by `deploy-mappers.test.ts`'s dedicated "derives the status from a dotted type when status is absent" test, which supplies `type` with no `status` and asserts the derived phases — a genuine Railway payload may carry either field depending on the account's webhook configuration, and this ordering lets the mapper accept both without the caller needing to know which one a given Railway integration sends.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

`unit-test-coverage` passes: `deploy-mappers.test.ts` gives both exported functions thorough, table-driven coverage of every `VERCEL_STATE` entry and every `railwayPhases` status, plus dedicated tests for the missing-required-field, provider-project-id, environment, and receipt-time-fallback branches; `timestamp-validation.test.ts` separately re-confirms the receipt-time fallback for a garbage timestamp on both mappers; `hooks.int.test.ts` exercises both mappers indirectly through a live signed request against the full `/hooks/vercel` and `/hooks/railway` routes. `separation-of-concerns` passes: this file's only responsibility is translating one provider's webhook body into a `ProviderDeploy` row or `null`; it delegates phase computation to `vercelPhases`/`railwayPhases`, commit formatting to `shortSha`/`commitFullMessage`, and timestamp validation to `toValidDate`, reimplementing none of them. `input-sanitization` passes: every field this file reads off the untrusted, caller-parsed webhook body is read through optional chaining against a cast-to-`unknown` interface, an unrecognized `type`/missing required field is rejected to `null` (never assumed present), a non-string `commitHash`/`commitMessage`/`branch`/`repo` on the Railway body is rejected to `null` rather than passed through (railway-commit-hash through railway-commit-repo), and every timestamp is routed through the trust-boundary parser `toValidDate` rather than trusted as already-valid — see agenticdevelopercookbook://guidelines/implementing/security/input-validation. `explicit-error-handling` is `partial`: every malformed-input branch resolves to a well-defined `null` or a documented fallback value rather than throwing (no-throw), but neither function nor its caller distinguishes, in any signal this file produces, "the event was well-formed but not one we ingest" from "the event was malformed" — both collapse to the identical `null` return, a fact recorded here rather than defended as a full pass. `graceful-degradation` passes: a webhook body missing a required field, carrying an unrecognized event type, or carrying an unparseable timestamp never fails the call; it degrades to `null` (asking nothing further of the caller) or to a receipt-time timestamp (preserving the event rather than discarding it), per the Design Decisions above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
