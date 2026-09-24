---
id: 7ba98112-0f6d-4236-ab6b-aa18b72d76bd
title: Status Server Monitor Provider Deploy
domain: agentictoolkit://recipes/status-server-monitor-provider-deploy
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: ProviderDeploy data shape, the trust-boundary timestamp parser toValidDate,
  and providerDeployToDTO, which shapes a provider deploy into the wire DeploymentDTO.
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
- agentictoolkit://recipes/status-server-monitor-deploy-status
- agentictoolkit://recipes/status-server-monitor-deploy-view
references:
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/status-server/test/timestamp-validation.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/deploy-env.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-view.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Provider Deploy

## Overview

`provider-deploy.ts` (`packages/web/packages/status-server/src/monitor/provider-deploy.ts`) is a pure, synchronous logic module in the status backend. It exports the `ProviderDeploy` interface — a deployment exactly as a provider fetcher or webhook mapper reports it, described by the file's own header comment as "structurally the old deployments-table row minus the storage-only columns" (a `liveHost` is stamped from config at serve time; a `fetchedAt` was a storage artifact) — the trust-boundary timestamp parser `toValidDate`, and `providerDeployToDTO`, which shapes a `ProviderDeploy` plus a resolved `liveHost` into the wire `DeploymentDTO` (`types.ts`) that the client renders. `providerDeployToDTO` composes two other pure modules external to this file: `combinedStatus` from `deploy-status.ts` (agentictoolkit://recipes/status-server-monitor-deploy-status) derives the single `status` field, and `deployEnv` plus `isRealEnvDeployRow` from `deploy-view.ts` (agentictoolkit://recipes/status-server-monitor-deploy-view) derive the `tier` field. Every provider fetcher (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, `fetch-vercel-projects.ts`) and the webhook mapper (`webhook-events.ts`) import `toValidDate` and the `ProviderDeploy` type to construct rows at the trust boundary; `routes/reads.ts` is `providerDeployToDTO`'s only caller, once for a persisted row (via its own `rowToProviderDeploy`, which stamps `confirmedAt` from the row's `fetched_at`) and once for a live-buffer overlay row (whose `confirmedAt` is stamped from the webhook's own receipt time). This file performs no network call, no database read or write, and holds no state between calls; its one side effect is a single `console.error` call inside the module-private `isoOf` helper, reached only when a legacy row's `createdAt` is already an Invalid Date.

## Behavioral Requirements

### `ProviderDeploy` Data Shape

- **provider-deploy-required-fields**: A `ProviderDeploy` value MUST carry `id: string`, `platform: string`, `projectName: string`, `buildPhase: BuildPhase | null`, `deployPhase: DeployPhase`, `environment: string | null`, `commitHash: string | null`, `commitMessage: string | null`, `branch: string | null`, `commitRepo: string | null`, `url: string | null`, and `createdAt: Date`; per the interface's own inline comments, `id` MUST be one of the four provider-prefixed shapes `'vc_<uid>'`, `'cf_<id>'`, `'ry_<id>'`, `'cr_<id>'`, `platform` MUST be one of `'vercel'`, `'cloudflare-pages'`, `'railway'`, `'crunchy'`, and `commitRepo` MUST be an `'owner/name'` pair when present, used to build a GitHub commit link.
- **provider-deploy-optional-fields**: A `ProviderDeploy` value MAY omit `providerProjectId` (`string | null`), `errorText` (`string | null`), and `confirmedAt` (`Date`) entirely; these three fields carry no default and their absence is a distinct, meaningful state from a present `null` (only `providerProjectId` and `errorText` accept an explicit `null`; `confirmedAt` accepts only presence or absence).
- **provider-project-id-identity-key**: A consumer resolving a `ProviderDeploy`'s identity against a board target MUST key on `providerProjectId ?? projectName`, per the field's own doc comment; `providerProjectId` MUST be left absent for any platform whose fetcher has not adopted provider-issued project ids, so that platform keeps working unchanged and id adoption remains a per-platform change rather than a flag day.
- **error-text-out-of-band-only**: No provider fetcher and no webhook mapper in this codebase MUST set `errorText` when constructing a `ProviderDeploy`; per the field's own comment, `errorText` MUST be populated only out-of-band, by `enrich-deploy-errors.ts` (external to this file), and is otherwise read back unchanged off the persisted row.
- **confirmed-at-fetcher-omission**: A `ProviderDeploy` constructed directly from freshly fetched or freshly received provider truth (a poll fetcher or a webhook mapper) MUST leave `confirmedAt` absent, because, per the field's own comment, that construction's own confirmation time is "now" and the row is persisted before it is served; a caller reconstructing a `ProviderDeploy` from a persisted row or a live-buffer overlay MUST supply `confirmedAt` from that row's own confirmation timestamp (the persisted `fetched_at`, or a webhook overlay's receipt time) rather than leaving it absent.

### `toValidDate`

- **to-valid-date-nullish-rejection**: `toValidDate(raw)` MUST return `null` when `raw` is `null` or `undefined`, without constructing a `Date`.
- **to-valid-date-type-rejection**: `toValidDate(raw)` MUST return `null` when `raw` is neither a `string`, a `number`, nor a `Date` instance, without constructing a `Date`.
- **to-valid-date-construction**: For a `raw` value that is a `string`, a `number`, or a `Date`, `toValidDate` MUST use `raw` itself when it is already a `Date` instance, and MUST otherwise construct `new Date(raw)`; it MUST return that `Date` when `Number.isFinite(d.getTime())` is `true`, and MUST return `null` in every other case — an unparseable string, `Number.NaN`, a numeric value outside `Date`'s representable range, or a `Date` already constructed from unparseable input.

### `providerDeployToDTO`

- **dto-passthrough-fields**: `providerDeployToDTO(d, liveHost)` MUST copy `id`, `platform`, `projectName`, `buildPhase`, `deployPhase`, `environment`, `commitHash`, `commitMessage`, `branch`, `commitRepo`, and `url` from `d` to the returned `DeploymentDTO` unchanged.
- **dto-provider-project-id-coalesce**: `providerDeployToDTO` MUST set the result's `providerProjectId` to `d.providerProjectId ?? null`; per the mapper's own comment, this converts an absent field to an explicit wire `null` (rather than an absent JSON key) so a consumer can distinguish "this row has no provider-issued id" from "this DTO predates the field."
- **dto-error-text-coalesce**: `providerDeployToDTO` MUST set the result's `errorText` to `d.errorText ?? null`.
- **dto-status-derivation**: `providerDeployToDTO` MUST set the result's `status` to `combinedStatus({ buildPhase: d.buildPhase, deployPhase: d.deployPhase })` (agentictoolkit://recipes/status-server-monitor-deploy-status, external to this file).
- **dto-tier-gate**: `providerDeployToDTO` MUST set the result's `tier` to `null` when `isRealEnvDeployRow(d.platform, d.environment)` returns `false`, and MUST otherwise set `tier` to `deployEnv(d.platform, d.projectName, d.environment, d.branch ?? null)` (both agentictoolkit://recipes/status-server-monitor-deploy-view, external to this file). Per the mapper's own comment, this gate MUST be evaluated and applied before `deployEnv` is called, because `deployEnv` itself has no "not a deployment of any tier" answer to give — a Vercel preview reports no `environment` yet its `branch` names a feature ref and its `projectName` is the production project's, so both of `deployEnv`'s own fallback signals would otherwise badge it with a tier it does not have.
- **dto-live-host-passthrough**: `providerDeployToDTO` MUST set the result's `liveHost` to its own `liveHost` parameter unchanged; it MUST NOT derive `liveHost` from any field of `d`.
- **iso-serialize-valid-date**: The module-private `isoOf(id, d)` helper MUST return `d.toISOString()` when `Number.isFinite(d.getTime())` is `true`.
- **iso-serialize-invalid-date-fail-soft**: `isoOf(id, d)` MUST NOT throw when `d` is an Invalid Date; it MUST instead log an error identifying `id` and the fact that the value being serialized is an invalid `createdAt` (via `console.error`), and MUST return `new Date(0).toISOString()` — the Unix epoch, ISO-encoded.
- **dto-created-at-via-iso-serialize**: `providerDeployToDTO` MUST set the result's `createdAt` to `isoOf(d.id, d.createdAt)`.
- **dto-phase-confirmed-at-fallback**: `providerDeployToDTO` MUST set the result's `phaseConfirmedAt` to `isoOf(d.id, d.confirmedAt ?? d.createdAt)` — using `d.confirmedAt` when present, and falling back to `d.createdAt` when `d.confirmedAt` is absent.

## Appearance

Not applicable — this is a data-shape and pure-mapping module, not a visual component.

## States

Not applicable — this is a data-shape and pure-mapping module with no visual-state table; the deployment lifecycle values it reads (`BuildPhase`, `DeployPhase`) are external data this module passes through and derives `status`/`tier` from, specified under Behavioral Requirements, not a runtime state machine this file owns.

## Accessibility

Not applicable — this is a data-shape and pure-mapping module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-provider-deploy-001 | to-valid-date-construction | `toValidDate('2026-07-12T00:00:00.000Z')` | A `Date` whose `.toISOString()` is `'2026-07-12T00:00:00.000Z'` — `timestamp-validation.test.ts` › "accepts ISO strings, epoch numbers, and Dates" |
| status-server-monitor-provider-deploy-002 | to-valid-date-construction | `toValidDate(1_750_000_000_000)` | A `Date` whose `.getTime()` is `1_750_000_000_000` — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-003 | to-valid-date-construction | `toValidDate(new Date())` (call it `d`) | The identical `d` instance's `.getTime()` value, unchanged — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-004 | to-valid-date-type-rejection | `toValidDate('not a date')` | `null` — `timestamp-validation.test.ts` › "rejects garbage, missing, and out-of-range values as null" |
| status-server-monitor-provider-deploy-005 | to-valid-date-nullish-rejection | `toValidDate(undefined)`; `toValidDate(null)` | Both `null` — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-006 | to-valid-date-construction | `toValidDate(Number.NaN)` | `null` — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-007 | to-valid-date-construction | `toValidDate(8.7e15)` | `null` — a numeric value past `Date`'s representable range constructs an Invalid Date — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-008 | to-valid-date-construction | `toValidDate(new Date('garbage'))` | `null` — an already-invalid `Date` instance is still rejected — `timestamp-validation.test.ts` › same "it" block |
| status-server-monitor-provider-deploy-009 | iso-serialize-invalid-date-fail-soft, dto-created-at-via-iso-serialize | `providerDeployToDTO({ id: 'vc_x', platform: 'vercel', projectName: 'p', buildPhase: null, deployPhase: 'none', environment: null, commitHash: null, commitMessage: null, branch: null, commitRepo: null, url: null, createdAt: new Date('garbage') }, null)` | `dto.createdAt === new Date(0).toISOString()`, and a `console.error` call naming `vc_x` occurs — `timestamp-validation.test.ts` › "providerDeployToDTO read-side belt" › "serializes a poisoned legacy Date to epoch instead of throwing" |
| status-server-monitor-provider-deploy-010 | dto-tier-gate | `providerDeployToDTO(deploy({ projectName: 'hub', branch: 'prepared' }), null)` where `deploy()` defaults to `{ platform: 'vercel', projectName: 'hub-help-testing', environment: 'production', branch: null, ... }` | `dto.tier === 'testing'` and `dto.environment === 'production'` (the raw promotion target is preserved alongside the derived tier) — `deploy-env.test.ts` › "providerDeployToDTO stamps the tier" › "derives it from the branch, alongside the RAW promotion target" |
| status-server-monitor-provider-deploy-011 | dto-tier-gate | `providerDeployToDTO(deploy(), null)`; `providerDeployToDTO(deploy({ projectName: 'hub' }), null)` | `'testing'` and `'production'` respectively — with no branch, `deployEnv` falls back to the project-name rule — `deploy-env.test.ts` › "falls back to the name rule when the row has no branch" |
| status-server-monitor-provider-deploy-012 | dto-tier-gate | `providerDeployToDTO(deploy({ environment: null, branch: 'feature/x' }), null)`; `providerDeployToDTO(deploy({ environment: '' }), null)` | Both `dto.tier === null` — a Vercel preview (no real `environment`) is never assigned a tier even though its branch or project name would otherwise suggest one — `deploy-env.test.ts` › "is NULL for a Vercel preview, which is not a deployment of any tier" |
| status-server-monitor-provider-deploy-013 | dto-phase-confirmed-at-fallback | `providerDeployToDTO({ ...deploy(), confirmedAt: undefined }, null)` vs. `providerDeployToDTO({ ...deploy(), confirmedAt: new Date(2000) }, null)` | The first result's `phaseConfirmedAt` equals `isoOf` applied to `createdAt` (`new Date(1000).toISOString()`); the second's equals `isoOf` applied to the supplied `confirmedAt` (`new Date(2000).toISOString()`) — traced to the mapper's `d.confirmedAt ?? d.createdAt` expression; no dedicated test exercises `phaseConfirmedAt` directly in this package |
| status-server-monitor-provider-deploy-014 | dto-provider-project-id-coalesce, dto-error-text-coalesce | `providerDeployToDTO({ id: 'ry_1', platform: 'railway', projectName: 'p', buildPhase: null, deployPhase: 'none', environment: null, commitHash: null, commitMessage: null, branch: null, commitRepo: null, url: null, createdAt: new Date(0) }, null)` (both `providerProjectId` and `errorText` omitted) | `dto.providerProjectId === null` and `dto.errorText === null` — traced directly to the mapper's `?? null` expressions; no dedicated test asserts these two fields in isolation in this package |

## Edge Cases

- **Null and empty input**: `toValidDate(null)` and `toValidDate(undefined)` MUST return `null` without constructing a `Date` (to-valid-date-nullish-rejection) — MUST. An empty-string `commitHash`, `commitMessage`, `branch`, `commitRepo`, or `url` on a `ProviderDeploy` is passed through `providerDeployToDTO` unchanged (dto-passthrough-fields); this file performs no non-empty validation of any of these fields itself — they are already-fetched provider data, and validating their contents is not this module's declared contract.
- **Boundary values**: a numeric `raw` value outside `Date`'s representable range (`toValidDate(8.7e15)`, per `timestamp-validation.test.ts`) constructs a JavaScript Invalid Date and MUST be rejected as `null`, identically to an unparseable string (to-valid-date-construction) — MUST. `Number.NaN` passed to `toValidDate` MUST likewise return `null` — MUST.
- **Concurrent access**: `toValidDate`, `isoOf`, and `providerDeployToDTO` are synchronous, pure functions with no `await` and no shared mutable module state, so any number of concurrent callers MUST NOT observe interleaved or corrupted results from any one call — MUST. `routes/reads.ts` calls `providerDeployToDTO` once per persisted row and once per live-buffer overlay row on every request; because neither call mutates the `ProviderDeploy` it is given nor any state outside its own return value, concurrent requests reading the same underlying row MUST each receive an independently correct `DeploymentDTO`.
- **Error states**: this file has no dependency of its own — no network call, no database access, no file I/O — so the only failure mode it can encounter is a poisoned `createdAt`/`confirmedAt` `Date` value already present on a `ProviderDeploy` it is handed. `isoOf` MUST NOT throw on such a value; it MUST log the failure via `console.error` (naming the deploy's `id`) and MUST substitute the Unix epoch rather than propagating a `RangeError` out of `toISOString()` (iso-serialize-invalid-date-fail-soft) — MUST. Per the source's own comment, this fail-soft path exists only for a legacy row already poisoned before `toValidDate` existed at every construction boundary; every `ProviderDeploy` a current fetcher or webhook mapper constructs MUST already carry a valid `createdAt`, because that construction path is gated by `toValidDate` — this is a fact about the codebase's other files (the fetchers, external to this one), not a residual gap in this module.
- **Offline or disconnected state**: not applicable — this file performs no network I/O and holds no connection of its own. The `ProviderDeploy` values it operates on were already fetched or already received via webhook by files external to this one (`fetch-vercel.ts`, `fetch-railway.ts`, `fetch-cloudflare.ts`, `webhook-events.ts`); their own connectivity failure modes are theirs to document, not this module's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `raw` (parameter to `toValidDate`) | `unknown` | none — caller-supplied | The provider- or webhook-supplied timestamp value to validate: an ISO string, an epoch number, or a `Date`. |
| `d`, `liveHost` (parameters to `providerDeployToDTO`) | `ProviderDeploy`, `string \| null` | none — caller-supplied | `d` is the in-memory deployment to shape; `liveHost` is the config-resolved live custom-domain host (external to this file, e.g. `ownerHostFor` in `routes/reads.ts`) stamped onto the result's `liveHost` field unchanged. |
| `id`, `d` (parameters to the module-private `isoOf`) | `string`, `Date` | none — caller-supplied only from within this file | `id` identifies the deploy in the logged error message when `d` is an Invalid Date; `isoOf` is not exported and has no caller outside `providerDeployToDTO`. |

## Deep Linking

Not applicable: this file defines no application URL scheme or route of its own — it exports only a data-shape interface, a timestamp parser, and a DTO-shaping function.

## Localization

Not applicable: this file emits no user-facing string of its own. Its one literal string reaching an external sink is the `console.error` template in `isoOf` (`` `[provider-deploy] ${id} carries an invalid createdAt — serializing as epoch` ``), which is a developer-facing diagnostic log message, not user-facing copy — see Logging.

## Accessibility Options

Not applicable: this file has no UI and responds to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system of any kind.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: none of this file's own. It receives an already-fetched or already-received `ProviderDeploy` (provider status strings, commit metadata, a source URL) and a resolved `liveHost` string as plain function arguments from callers external to this file; it collects nothing itself.
- **Storage**: none. This file holds no state between calls and writes nothing to disk, memory cache, or database; persistence of the data it shapes is owned by the storage layer and `routes/reads.ts`, both external to this file.
- **Transmission**: none performed by this file itself. `providerDeployToDTO`'s return value is handed back to its caller (`routes/reads.ts`), which decides whether and how to serialize it onto the wire.
- **Retention**: not applicable — this file holds no data across calls.

## Logging

Subsystem: `status-server` | Category: `provider-deploy`

| Event | Level | Message |
|-------|-------|---------|
| Invalid `Date` reaches `isoOf` (a legacy row's `createdAt`, or a `confirmedAt`/`createdAt` fallback that resolves to an Invalid Date) | error | `` [provider-deploy] ${id} carries an invalid createdAt — serializing as epoch `` |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port models `ProviderDeploy` as a `Sendable struct` with `providerProjectId: String?`, `errorText: String??`-avoiding double-optionality by instead modeling "absent" vs. "present-and-null" with an explicit sentinel or by dropping the present-null state if the port's own wire format has no use for it, and `confirmedAt: Date?`; `toValidDate` becomes a static function returning `Date?` over `Any`/a small `TimestampLike` enum (Swift's `Date(timeIntervalSince1970:)` / `ISO8601DateFormatter` in place of `new Date(raw)`); `providerDeployToDTO` and the private `isoOf` become plain, non-isolated static functions, since neither performs `await` or touches shared mutable state in the source.
- **Compose**: same non-UI framing. A Kotlin port models `ProviderDeploy` as a `data class` with nullable/optional fields (`String?` for `providerProjectId`/`errorText`, and either a nullable `Instant?` or a wrapper type for `confirmedAt`'s true absent-vs-present distinction), `toValidDate` as a top-level function accepting `Any?` and returning `Instant?`, parsing an ISO-8601 string via `Instant.parse`, an epoch `Long` via `Instant.ofEpochMilli`, and validating range with a try/catch or explicit bounds check in place of the source's `Number.isFinite(d.getTime())` idiom.
- **React/Web** (source platform): lives at `packages/web/packages/status-server/src/monitor/provider-deploy.ts`, a plain ESM module on the Node status backend (Hono). `toValidDate` and the `ProviderDeploy` type are imported by every provider fetcher and by `webhook-events.ts` to construct rows at the trust boundary; `providerDeployToDTO` is imported only by `routes/reads.ts`. The module-private `isoOf` helper is not exported and has no test or caller outside this file's own `providerDeployToDTO`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI — nothing here touches a view controller or window. A macOS/iOS host app would consume the Swift port's `ProviderDeploy`/`providerDeployToDTO` equivalents from its data/service layer exactly as `routes/reads.ts` does today, with no framework-specific adaptation needed beyond that layer boundary.
- **WinUI 3**: a .NET port models `ProviderDeploy` as a `record` (or `readonly record struct` if value semantics are preferred) with `string? ProviderProjectId`, `string? ErrorText`, and a true absent-vs-present `DateTimeOffset?` for `ConfirmedAt`; `DeploymentDTO` is the `System.Text.Json`-serializable output `record`. `ToValidDate(object? raw)` becomes a static method returning `DateTimeOffset?`, using `DateTimeOffset.TryParse` for a string, `DateTimeOffset.FromUnixTimeMilliseconds` guarded by a `try`/`catch OverflowException` (or an explicit range check against `DateTimeOffset.TryParse`'s own bounds) for a numeric epoch in place of the source's `Number.isFinite(d.getTime())` range gate, and returning `null` for any other input type or an out-of-range value — mirroring `toValidDate`'s three-way branch (nullish → null-type-check → construct-and-range-check) rather than throwing and catching for the ordinary "not parseable" case. `ProviderDeployToDto` and the private `IsoOf` helper are static methods with no `Task`/`async` needed, since neither performs I/O in the source; `IsoOf`'s fail-soft epoch substitution uses `DateTimeOffset.UnixEpoch.ToString("o")` in place of `new Date(0).toISOString()`, and its diagnostic write uses whatever structured logger (e.g. `ILogger`) the host app already uses in place of `console.error`, preserving the source's "log and substitute, never throw" contract rather than letting a poisoned value raise an unhandled exception.

## Design Decisions

- **Decision**: derive `providerProjectId`'s identity role as `providerProjectId ?? projectName` rather than requiring every platform to adopt a provider-issued project id before this field can be used at all.
  **Rationale**: stated directly in the field's own doc comment — keying identity on the coalesced value means a platform whose fetcher has not adopted ids keeps working unchanged, and adopting ids for a new platform is a per-platform change rather than a flag day across every consumer of `ProviderDeploy`.
  **Approved**: pending
- **Decision**: convert `providerProjectId` and `errorText` from an absent field to an explicit wire `null` in `providerDeployToDTO` (`?? null`) rather than passing an absent value straight through to the DTO.
  **Rationale**: stated directly in the mapper's own comment on `providerProjectId` — the DTO field is not optional the way the `ProviderDeploy` field is, so a consumer must be able to tell "this row genuinely has no id" from "this build of the DTO predates the field being added at all"; an absent key on the wire would conflate those two states.
  **Approved**: pending
- **Decision**: gate `tier` derivation on `isRealEnvDeployRow` before calling `deployEnv`, rather than letting `deployEnv` itself decide when to return a "no tier" answer.
  **Rationale**: stated directly in the mapper's own comment — `deployEnv` has no "don't know" to return, so a Vercel preview (no `environment`, a feature-branch `branch`, and a project name reused from the production project) would otherwise be badged with a tier by either of `deployEnv`'s own fallback signals; the gate has to be applied by the caller before asking `deployEnv` anything, and this is the same gate the board's `ownedDeployTarget` (external to this file) applies before a preview can become a Problem.
  **Approved**: pending
- **Decision**: give `isoOf` a fail-soft epoch fallback with a logged error, rather than letting an Invalid Date's `.toISOString()` throw a `RangeError` out of `providerDeployToDTO`.
  **Rationale**: stated directly in the source comment — a poisoned legacy row reaching this function unguarded would throw at serialize time and, per the test suite's own framing comment in `timestamp-validation.test.ts`, "500s /live for everyone"; substituting the epoch keeps one bad row from taking down every other row's response, at the cost of that one row displaying an obviously-wrong (epoch) timestamp instead. The source comment also notes new writes cannot produce this condition, because `toValidDate` gates every construction boundary — this fallback exists specifically for data written before that guarantee existed.
  **Approved**: pending
- **Decision**: model `confirmedAt` as an optional field with no default, rather than always requiring a caller to supply one (e.g. defaulting it to `createdAt` at construction time).
  **Rationale**: stated directly in the field's own doc comment — the many `ProviderDeploy` constructors that never observe a confirmation time distinct from creation (every current fetcher and webhook mapper) would otherwise each have to spell out the same fallback explicitly; leaving it optional and resolving the fallback once, centrally, in `providerDeployToDTO` (`d.confirmedAt ?? d.createdAt`) avoids repeating that rule at every construction site.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

`unit-test-coverage` is `partial`: `timestamp-validation.test.ts` gives `toValidDate` thorough coverage of its accept and reject branches, and separately asserts `isoOf`'s fail-soft epoch substitution through `providerDeployToDTO`'s `createdAt` field; `deploy-env.test.ts` separately gives the `tier` derivation (the gate plus both of `deployEnv`'s fallback paths) thorough coverage through `providerDeployToDTO`. But `dto-passthrough-fields`, `dto-provider-project-id-coalesce`, `dto-error-text-coalesce`, and `dto-phase-confirmed-at-fallback` have no dedicated assertion anywhere in this package — each is exercised only incidentally, as an unasserted field on a `DeploymentDTO` object the `tier`/`createdAt`-focused tests construct for another purpose. `separation-of-concerns` passes: this file's only responsibility is the `ProviderDeploy` data shape, trust-boundary timestamp parsing, and DTO shaping composed from two other pure modules' exported derivations; it performs no I/O, no persistence, and no presentation of its own. `explicit-error-handling` passes: `toValidDate` converts every unparseable or out-of-range input into an explicit `null` return rather than letting a downstream `.toISOString()` throw later, and `isoOf`'s fail-soft path logs the specific failure (naming the deploy's `id`) via `console.error` rather than silently substituting a value with no signal. `fault-tolerance` passes: `providerDeployToDTO` accepts a `ProviderDeploy` whose `createdAt` or `confirmedAt` may already be an Invalid Date — data this file did not itself validate at construction time — and still returns a well-formed `DeploymentDTO` rather than throwing, per `iso-serialize-invalid-date-fail-soft`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
