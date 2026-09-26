---
id: 5edf4567-65dd-40d7-814e-8604ee70f131
title: Status Server Monitor Types
domain: agentictoolkit://cookbook/status-server/monitor/types
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The type-only monitor DTO module: ServiceStatusDTO, UptimeDay/UptimeService/UptimeResponse,
  DeploymentDTO, HistoryCheck/HistoryResponse, and CheckState/IntegrationCheck/IntegrationsResponse,
  plus the re-exported HealthStatus, OverallStatus and DeployStatus vocabulary.'
platforms:
- typescript
- web
tags:
- monitor
- types
- dto
- server
depends-on: []
related:
- agentictoolkit://cookbook/status-server/monitor/health
- agentictoolkit://cookbook/status-server/monitor/overall
- agentictoolkit://cookbook/status-server/monitor/deploy-status
- agentictoolkit://cookbook/status-server/monitor/provider-deploy
- agentictoolkit://cookbook/status-server/monitor/integrations
- agentictoolkit://cookbook/status-server/monitor/live-types
references:
- packages/web/packages/status-server/src/monitor/types.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/health.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/overall.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/deploy-status.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/provider-deploy.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/integrations.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/self-check-stability.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/uptime.ts (agentictoolkit)
- packages/web/packages/status-server/src/routes/reads.ts (agentictoolkit)
- packages/web/packages/status-server/src/openapi/paths/reads.ts (agentictoolkit)
- packages/web/packages/status-server/test/reads.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/self-check-stability.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/timestamp-validation.test.ts (agentictoolkit)
- packages/web/packages/status-web/src/types.ts (agentictoolkit)
- packages/web/packages/status-web/src/lib/deploy-status-parity.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Types

## Overview

`types.ts` declares the shared wire-contract vocabulary for the monitor's read routes: eleven `export interface`/`export type` declarations plus three re-exported type aliases (`HealthStatus`, `OverallStatus`, `DeployStatus`), with no function, no class, and no side effect of its own. `ServiceStatusDTO` is the base per-endpoint health row (extended elsewhere by `LiveServiceDTO`, per the `status-server-monitor-live-types` recipe); `UptimeDay`/`UptimeService`/`UptimeResponse` bundle the `/uptime` route's daily rollups; `DeploymentDTO` is the wire shape a deploy row becomes for the board (produced by `providerDeployToDTO` in `provider-deploy.ts`, outside this file); `HistoryCheck`/`HistoryResponse` declare the `/history` route's per-check series; and `CheckState`/`IntegrationCheck`/`IntegrationsResponse` declare the `/integrations` self-check report. This recipe specifies each interface's field-level shape and the invariants a producer or consumer of a value of that type MUST honor — not the route, mapper, or self-check logic that builds or delivers one, which is each sibling file's own concern.

## Behavioral Requirements

- **module-reexports-shared-vocabulary**: The module MUST re-export `HealthStatus` (from `./health`), `OverallStatus` (from `./overall`), and `DeployStatus` (from `./deploy-status`) via `export type { HealthStatus, OverallStatus, DeployStatus };`, so a consumer importing only `./types` can name all three without a separate import from their defining modules.
- **build-phase-deploy-phase-not-reexported**: The module MUST import `BuildPhase` and `DeployPhase` from `./deploy-status` for use as `DeploymentDTO` field types, and MUST NOT re-export either by name; a consumer that needs to declare a variable or parameter of type `BuildPhase` or `DeployPhase` directly MUST import it from `./deploy-status`, not from `./types`.
- **type-only-no-runtime**: The module MUST export only `export type` and `export interface` declarations; it MUST NOT export a function, a class, a constant, or any other runtime value, and contains no side effect of its own.
- **service-status-dto-all-fields-required**: A `ServiceStatusDTO` value MUST carry all twelve fields (`slug`, `group`, `name`, `url`, `environment`, `platform`, `deployProject`, `status`, `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt`), none declared optional; a conformant value MUST supply an explicit `null` where a field's type permits it rather than omit the property.
- **service-status-platform-is-correlation-key**: `ServiceStatusDTO.platform` MUST be `string | null` and, per the field's own comment, names the "explicit deploy target (correlation key)" — the field the monitor uses to correlate an endpoint to its deploys, not a display label.
- **service-status-status-includes-unknown**: `ServiceStatusDTO.status` MUST accept `HealthStatus | "unknown"` — the three `HealthStatus` values (`healthy`, `degraded`, `down`) plus the literal `"unknown"`, which `HealthStatus` itself does not include.
- **uptime-day-status-excludes-unknown**: `UptimeDay.status` MUST be typed as `HealthStatus` alone (`healthy` | `degraded` | `down`), NOT `HealthStatus | "unknown"` — unlike `ServiceStatusDTO.status` and `HistoryCheck.status`, a daily uptime rollup has no `"unknown"` member.
- **uptime-percent-nullable-at-day-and-service-level**: Both `UptimeDay.uptimePercent` and `UptimeService.uptimePercent` MUST be `number | null`, independently nullable at each level.
- **uptime-service-shape**: An `UptimeService` value MUST carry `slug`, `name`, `uptimePercent`, `totalChecks`, and `daily: UptimeDay[]`, all required.
- **uptime-response-shape**: `UptimeResponse` MUST bundle `services: UptimeService[]` and `days: number` — the caller-requested window size the services were computed over.
- **deployment-dto-all-fields-required**: A `DeploymentDTO` value MUST carry all fifteen fields (`id`, `platform`, `projectName`, `providerProjectId`, `status`, `buildPhase`, `deployPhase`, `environment`, `tier`, `commitHash`, `commitMessage`, `branch`, `commitRepo`, `url`, `errorText`, `liveHost`, `createdAt`, `phaseConfirmedAt`), none declared optional.
- **provider-project-id-required-though-nullable**: `providerProjectId` MUST be `string | null` and MUST always be present, never omitted, even though nullable — per its own comment, "ON THE WIRE because a board target's identity segment is `providerProjectId ?? projectName`," so a consumer correlating a target to a deployment can distinguish "this row has no provider id" from a field that is simply missing.
- **tier-required-and-distinct-from-environment**: `tier` MUST be `string | null`, present on every value, and MUST be treated as distinct from `environment` — per its own comment, `environment` is "the provider's promotion target" (reading "production" for every Vercel project), while `tier` is "the logical tier this build belongs to," derived once server-side so no client duplicates the derivation.
- **phase-confirmed-at-required-non-null**: `phaseConfirmedAt` MUST be a non-null `string` (an ISO time) present on every value — unlike every other nullable or optional field on this interface, it carries neither `?` nor `| null`; per its own comment it records when "the phases were last confirmed against provider truth," and an in-flight phase whose confirmation is old is "a claim with a freshness deadline, not a fact."
- **error-text-verbatim-rendering**: `errorText` MUST be `string | null` and, per its own comment, is "rendered verbatim in the details pane" — the provider's failure reason for a failed deploy, or `null` otherwise.
- **live-host-is-correlation-and-url**: `liveHost` MUST be `string | null` and, per its own comment, is the "resolved live custom domain host (correlation key + live url)."
- **build-deploy-phase-fields-typed-externally**: `buildPhase: BuildPhase | null` and `deployPhase: DeployPhase` MUST use the types imported from `./deploy-status`, not a locally redeclared type, so the deployment-lifecycle vocabulary can never diverge between the two files.
- **history-check-mirrors-service-status-check-fields**: `HistoryCheck` MUST carry `status: HealthStatus | "unknown"`, `responseTimeMs: number | null`, `statusCode: number | null`, `error: string | null`, and `checkedAt: string` — the same four check-outcome fields `ServiceStatusDTO` carries (`status`, `responseTimeMs`, `statusCode`, `error`), with `lastCheckedAt` renamed `checkedAt` for a value standing for one point in a series rather than "most recent."
- **history-response-shape**: `HistoryResponse` MUST bundle `service: string`, `hours: number`, and `checks: HistoryCheck[]`.
- **check-state-closed-set**: `CheckState` MUST be exactly one of the three literal strings `"ok"`, `"warn"`, or `"error"`.
- **integration-check-required-fields**: An `IntegrationCheck` value MUST carry `id`, `label`, `configured: boolean`, `ok: boolean`, `state: CheckState`, and `detail: string`, all required.
- **integration-check-optional-fields**: `missingEnv?: string[]`, `unreachable?: boolean`, and `correlated?: boolean` MUST each be declared optional and MAY be omitted when not applicable.
- **missing-env-names-not-values**: `missingEnv` MUST carry the exact names of expected environment variables found unset — per its own comment, "(named exactly, e.g. CLOUDFLARE_ACCOUNT_ID)" — never their values, and, per the same comment, SHOULD be omitted or empty "when nothing is missing."
- **unreachable-marks-no-http-response**: `unreachable` MUST mean the probe "got NO HTTP response at all (timeout/abort/connection failure)" per its own comment, and MUST be distinguished from a real HTTP error response (401/5xx), which MUST NOT set `unreachable`.
- **correlated-marks-cross-provider-debounce**: `correlated` MUST mean the check was "confirmed-unreachable together with other providers in the same run" per its own comment, to be treated by a consumer as monitor-side connectivity rather than an independent provider outage.
- **integrations-response-shape**: `IntegrationsResponse` MUST bundle `generatedAt: string`, `overall: CheckState`, and `checks: IntegrationCheck[]`.

## Appearance

Not applicable — this is a type-only DTO contract module, not a visual component.

## States

Not applicable — this is a type-only DTO contract module, not a visual component.

## Accessibility

Not applicable — this is a type-only DTO contract module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| types-001 | service-status-status-includes-unknown, service-status-dto-all-fields-required | An endpoint with no persisted health check yet | `routes/reads.ts`'s `serviceDtos` producer sets `status: "unknown"` with `responseTimeMs`, `statusCode`, `error`, and `lastCheckedAt` all `null` — matching the four-member union and the all-fields-required contract, with no property omitted |
| types-002 | service-status-dto-all-fields-required | An endpoint with a persisted `{ status: 'healthy', responseTimeMs: 42, statusCode: 200 }` check | `reads.int.test.ts`'s `'/live + /status surface a service derived from the latest health check'` asserts the corresponding service row matches `{ slug, status: 'healthy', responseTimeMs: 42 }` |
| types-003 | uptime-day-status-excludes-unknown, uptime-percent-nullable-at-day-and-service-level | `dayStatus`/`uptimePercent` in `uptime.ts` called with `Counts { total: 0, healthy: 0, degraded: 0, down: 0 }` (a day with zero checks) | `dayStatus` returns `"healthy"` — its default fall-through — while `uptimePercent` returns `null`; a zero-check day is always a valid three-member `HealthStatus`, never a fourth `"unknown"` literal |
| types-004 | uptime-service-shape, uptime-response-shape | Two persisted checks (one `healthy`, one `down`) for one endpoint, requested with `days=90` | `reads.int.test.ts`'s `'/uptime aggregates daily counts for the configured endpoint'` asserts `body.days` is `90`, `body.services[0].totalChecks` is `2`, and `body.services[0].uptimePercent` is `50` |
| types-005 | history-check-mirrors-service-status-check-fields, history-response-shape | Two persisted checks (`healthy` at 10ms, `degraded` at 900ms), requested with `hours=24` | `reads.int.test.ts`'s `'/history returns one endpoint checks (accepts slug; 400 without it)'` asserts `body.service` equals the slug, `body.hours` is `24`, and `body.checks` has length `2` — matching this file's `HistoryResponse` shape at the JSON level, per the open question on **history-response-not-referenced-by-name** in Design Decisions |
| types-006 | deployment-dto-all-fields-required, phase-confirmed-at-required-non-null | A `ProviderDeploy` whose `createdAt` is `new Date('garbage')` (a poisoned legacy `Date`), passed to `providerDeployToDTO` | `timestamp-validation.test.ts`'s `'serializes a poisoned legacy Date to epoch instead of throwing'` asserts `dto.createdAt` equals `new Date(0).toISOString()`; the same `isoOf` helper backs `phaseConfirmedAt`, so neither field is ever left unparseable |
| types-007 | provider-project-id-required-though-nullable | A `ProviderDeploy` row with no provider-issued id, passed through `providerDeployToDTO` | Per `providerDeployToDTO`'s own construction, `providerProjectId: d.providerProjectId ?? null` — the field is always present as an explicit `null`, never omitted |
| types-008 | tier-required-and-distinct-from-environment | A Vercel preview-branch `ProviderDeploy` row, for which `isRealEnvDeployRow` is `false` | Per `providerDeployToDTO`'s own construction, `tier: isRealEnvDeployRow(...) ? deployEnv(...) : null` evaluates to `null` regardless of what `environment` holds for that row |
| types-009 | integration-check-optional-fields, unreachable-marks-no-http-response | A provider probe that gets no HTTP response at all | `self-check-stability.test.ts`'s `unreachable(id)` helper constructs an `IntegrationCheck` literal with `unreachable: true`; no test in that file ever sets `unreachable: false` explicitly — a producer omits the field instead when it does not apply |
| types-010 | correlated-marks-cross-provider-debounce | Two providers unreachable in the same `stabilize()` run | `self-check-stability.test.ts`'s `'correlates simultaneous confirmed failures as monitor-side — amber, one Connectivity chip'` asserts both providers' `correlated` field is `true`; contrast its `'confirms a single provider that stays unreachable across runs AND the window — red'` test, which asserts the lone failing provider's `correlated` field is `undefined`, never `false` |
| types-011 | integrations-response-shape | `GET /integrations` against a running self-check | `reads.int.test.ts`'s `'/integrations returns the self-check report'` asserts the body has `generatedAt` and `overall` properties and `checks` is an array containing an entry with `id === 'stats'` |

## Edge Cases

- **Null and empty input**: an endpoint with no persisted health check yet MUST be represented as `ServiceStatusDTO` with `status: "unknown"` and `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt` all `null` — per **service-status-status-includes-unknown** and **service-status-dto-all-fields-required**; `routes/reads.ts`'s `serviceDtos` producer, outside this file, is the one place this is currently exercised. (MUST)
- **Null and empty input**: a `DeploymentDTO` row with no provider-issued id or no resolvable tier MUST carry `providerProjectId: null` / `tier: null` as explicit values, never omitting either property — per **provider-project-id-required-though-nullable** and **tier-required-and-distinct-from-environment**. (MUST)
- **Null and empty input**: an `IntegrationCheck` with nothing missing SHOULD omit `missingEnv` entirely rather than supply an empty array — per the field's own comment, "Omitted/empty when nothing is missing," both forms are treated as equivalent, so a producer's choice between them is a style choice this contract does not prescribe either way. (SHOULD)
- **Boundary values**: `HealthStatus`, `OverallStatus`, `DeployStatus`, `BuildPhase`, `DeployPhase`, and `CheckState` are each closed literal-string unions; a value outside a union's listed literals is not a valid value of that type, and TypeScript rejects it at compile time for a caller that assigns a literal — this module supplies no runtime guard of its own for a value that arrives already-widened to plain `string` from an untyped boundary such as `JSON.parse` or a `TEXT` database column, since an interface or type alias vanishes at runtime for every TypeScript module, not only this one. (MUST, for the compile-time guarantee)
- **Boundary values**: `UptimeDay.status` admits only the three `HealthStatus` literals, never `"unknown"`; per `uptime.ts`'s `dayStatus`, a day with zero checks (`Counts { total: 0, healthy: 0, degraded: 0, down: 0 }`) still returns `"healthy"` — its default fall-through — while `uptimePercent` returns `null` for that same zero-check day, so the two fields diverge (a definite status paired with a null percentage) rather than the type offering a fourth "no data" status literal. (MUST)
- **Concurrent access**: not applicable — this file declares no mutable state and no function, so nothing in it can be entered concurrently. The concurrency of whichever producer builds a value of one of these types (`routes/reads.ts`, `provider-deploy.ts`, `integrations.ts`) is outside this file's own contract.
- **Error states**: not applicable to this file raising one — it declares no function that can throw. `errorText` (`DeploymentDTO`) and `error` (`ServiceStatusDTO`, `HistoryCheck`) are this contract's error-state signal instead: a producer that observed a failure MUST report it through that field as a `string`, per **error-text-verbatim-rendering**, rather than through an exception this file has no mechanism to carry.
- **Offline or disconnected state**: not applicable — this file makes no network call of its own; `lastCheckedAt`, `checkedAt`, and `phaseConfirmedAt` exist precisely so a consumer can judge the staleness of data that was already gathered elsewhere, per **phase-confirmed-at-required-non-null**.

## Configuration

Not applicable: `types.ts` declares data shapes only — no parameter, default value, environment variable, settings key, or injected dependency of its own; every field's value is supplied entirely by whichever producer constructs a value of one of these types.

## Deep Linking

Not applicable: `types.ts` declares data shapes only — no URL, route, or navigable destination originates from this file itself; `url` (`ServiceStatusDTO`, `DeploymentDTO`) and `liveHost` (`DeploymentDTO`) are typed as `string | null` fields the file declares but does not construct or navigate to.

## Localization

Not applicable: this file contains no string literal used as user-facing text — every text-carrying field (`error`, `errorText`, `detail`, `commitMessage`, `branch`) is a `string`/`string | null` type declaration, not a value, so there is no prose for this file itself to localize. The closed literal unions (`HealthStatus`, `DeployStatus`, `CheckState`, and the rest) are wire-protocol tokens, not display strings — presenting one to a user is a consumer's rendering concern, outside this file.

## Accessibility Options

Not applicable: `types.ts` renders nothing and reads no accessibility display setting — it declares data shapes only, with no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic of any kind.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; it declares data shapes only.

## Privacy

Not applicable: `types.ts` declares data shapes only — it collects, stores, and transmits nothing itself. None of its fields is a token or credential; `missingEnv` (`IntegrationCheck`) carries only the names of unset environment variables — per its own comment, "named exactly, e.g. CLOUDFLARE_ACCOUNT_ID" — never their values, so this field cannot leak a credential even when populated. The commit hashes, branch names, project names, URLs, and error strings the other DTOs carry are operational monitoring data already produced elsewhere; this file neither reads nor writes them.

## Logging

Not applicable: the source contains no log call of any kind — it declares data shapes only, with no function to log from.

## Platform Notes

- **SwiftUI**: not applicable to this file's own source — `types.ts` is a TypeScript type-only module with no SwiftUI or Apple-platform dependency of any kind.
- **AppKit / UIKit**: this is the source. `packages/web/packages/status-server/src/monitor/types.ts` is a TypeScript file in the `status-server` web package; it has no Apple-platform target of its own. A macOS/iOS port would model each interface as a `Codable`, `Sendable` Swift `struct` decoded from the corresponding JSON response — `HealthStatus`, `OverallStatus`, `DeployStatus`, `BuildPhase`, `DeployPhase`, and `CheckState` each as a `String`-backed `enum` with the same literal cases (adding an `unknown` case only where the TypeScript union itself includes `"unknown"`, e.g. `ServiceStatusDTO.status` / `HistoryCheck.status`, and omitting it where it does not, e.g. `UptimeDay.status`), and `Optional` in place of `| null`. A required-though-nullable field such as `providerProjectId`, `tier`, or `phaseConfirmedAt` MUST stay a non-optional property of `Optional` type (`let providerProjectId: String?`, always assigned, never an omitted key) rather than an optional Swift property, to preserve the "always present, sometimes null" contract those fields declare.
- **Compose**: model each interface as a Kotlin `data class` annotated for the project's JSON serializer (e.g. `kotlinx.serialization`'s `@Serializable`), with the literal-string unions as `String`-backed `enum class`es (or sealed value classes) enumerating the same cases, and nullable Kotlin types (`String?`) in place of `| null`. The same required-though-nullable distinction applies: `providerProjectId`, `tier`, and `phaseConfirmedAt` are non-optional, nullable properties (`val tier: String?`, always serialized) rather than fields marked optional or omittable.
- **React/Web**: this is closest to the actual runtime shape — a React/Web client already consumes these DTOs as plain JSON decoded from the `/status`, `/uptime`, `/history`, `/deploy-projects`, and `/integrations` routes, and can import these same TypeScript declarations directly if it shares this package, or mirror them field-for-field in its own type file when it does not, as `status-web`'s independent mirror currently does (see Design Decisions).
- **WinUI 3**: model each interface as a C# `record` deserialized with `System.Text.Json.JsonSerializer`, using nullable reference types (`string?`) in place of `| null` and an `enum` with a `[JsonStringEnumConverter]` (or explicit `[JsonPropertyName]` attributes) for each closed literal union, to preserve the exact wire strings (e.g. `"healthy"` / `"degraded"` / `"down"` / `"unknown"` for the `HealthStatus`-shaped fields). A required-though-nullable field such as `providerProjectId`, `tier`, or `phaseConfirmedAt` needs an explicit `[JsonInclude]`, or a converter that writes `null` rather than omitting the property, so `System.Text.Json`'s default "omit null" serializer behavior does not silently turn a required-but-null field into a missing one; the optional `IntegrationCheck` fields (`missingEnv`, `unreachable`, `correlated`) are the one place omission IS correct, and should use nullable properties with `JsonIgnoreCondition.WhenWritingNull` instead.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/types.ts` |

## Design Decisions

**Decision**: This recipe documents `HistoryCheck`/`HistoryResponse` as this file's declared contract for a `/history`-shaped response, even though the actual producer, `queryHistory` in `routes/reads.ts` (outside this file), returns a separately-declared inline type shape rather than importing and returning `HistoryResponse` by name.
**Rationale**: TypeScript's structural typing means the JSON payload the route serves still matches `HistoryResponse`'s shape, as confirmed in **types-005**'s Conformance Test Vector, but the producer's own return type is looser (a plain `status: string` rather than `HealthStatus | "unknown"`), so a future change to that producer could emit a status value this file's own type does not permit, with no compiler error to catch it. Per source fidelity this is stated as an observed fact about the current codebase — the open question on **history-response-not-referenced-by-name** — rather than fixed or invented away, since fixing the producer is outside this file's own source.
**Approved**: pending

**Decision**: `BuildPhase` and `DeployPhase` are imported from `./deploy-status` for use as `DeploymentDTO` field types but are deliberately not re-exported by name, unlike `HealthStatus`, `OverallStatus`, and `DeployStatus`, which are.
**Rationale**: the source gives no comment explaining this asymmetry, so this recipe states it as an observed fact about the module's export surface rather than inventing a rationale the source does not give: a consumer needing to name a `BuildPhase` or `DeployPhase` value directly MUST import it from `./deploy-status`, per **build-phase-deploy-phase-not-reexported**.
**Approved**: pending

**Decision**: `providerProjectId` and `tier` are both declared as required, non-optional fields typed `string | null`, rather than optional (`?`) fields the module could instead have left absent when not applicable.
**Rationale**: per each field's own comment, `providerProjectId`'s absence must be readable because "a board target's identity segment is `providerProjectId ?? projectName`," and `tier` must be readable as `null` — never omitted — to distinguish "not a tiered deployment" from a consumer that simply forgot to check the field; the OpenAPI schema at `src/openapi/paths/reads.ts` independently documents the same required-though-nullable rationale for both fields, corroborating that this is a deliberate wire-contract decision rather than an accident of one file.
**Approved**: pending

**Decision**: this recipe treats `packages/web/packages/status-web/src/types.ts`'s independently-maintained mirror of these same interfaces as informative context, not as part of this file's own contract — including its currently-observed divergence, where its `phaseConfirmedAt` is declared optional (`phaseConfirmedAt?: string`) against this file's required, non-null `phaseConfirmedAt: string`.
**Rationale**: the two packages share no build — per `deploy-status-parity.test.ts`'s own comment, "there is no shared package between the backend and its embedded web app" — and that test already exists as a runtime drift guard for `deploy-status.ts`'s enums and functions between the two packages, but no equivalent guard exists for the plain type declarations this file documents, since a type vanishes at compile time and cannot be imported and compared at runtime the way a function or a `const` array can. This asymmetry is stated as an observed fact about the current codebase, not a defect of `types.ts` itself, which fully and correctly declares `phaseConfirmedAt` as required.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [health-observability](agenticdevelopercookbook://compliance/reliability#health-observability) | passed | Reliability |

`separation-of-concerns` passes because this file declares wire shapes only, importing nothing from a route, a DB store, or a provider fetcher, and exporting no function or value of its own — construction (`serviceDtos`, `deploymentDtos`, `buildUptime`, `queryHistory` in `routes/reads.ts`; `providerDeployToDTO` in `provider-deploy.ts`; `runIntegrationsCheck` in `integrations.ts`) is entirely the concern of other files. `unit-test-coverage` is partial: no test file targets `types.ts` directly, since it declares no function to unit-test, and while `self-check-stability.test.ts` constructs `IntegrationCheck` literals directly and `timestamp-validation.test.ts` asserts against a real `DeploymentDTO` value returned by `providerDeployToDTO`, no test anywhere constructs or asserts against a `HistoryResponse`/`HistoryCheck` value by name — consistent with the open question on **history-response-not-referenced-by-name** in Design Decisions, since the one producer that would exercise it returns a different, unnamed inline type instead. `data-integrity` passes because every field on every interface this file declares is non-optional (per **service-status-dto-all-fields-required**, **deployment-dto-all-fields-required**, and the rest of the all-fields-required requirements), so a value omitting a field fails structural typing at compile time; the one caveat is `status-web`'s independent mirror, which is a different file's declaration, not this one's, and is documented as an external drift risk rather than a defect here. `health-observability` passes because several fields exist expressly so a consumer can judge data freshness rather than trust a value blindly: `lastCheckedAt`/`checkedAt` timestamp each check, and `phaseConfirmedAt` — per its own comment — turns an in-flight deploy phase into "a claim with a freshness deadline, not a fact."

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
