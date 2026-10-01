---
id: 5edf4567-65dd-40d7-814e-8604ee70f131
title: Monitor Types
domain: agentictoolkit://cookbook/status/service/monitor/types
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The shared record vocabulary for the monitor's read routes — a service
  status record, daily and per-service uptime records, a deployment record,
  history check records, and integration check records, plus the shared health,
  overall, and deploy status vocabulary.
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
- agentictoolkit://cookbook/status/service/monitor/health
- agentictoolkit://cookbook/status/service/monitor/overall
- agentictoolkit://cookbook/status/service/monitor/deploy-status
- agentictoolkit://cookbook/status/service/monitor/provider-deploy
- agentictoolkit://cookbook/status/service/monitor/integrations
- agentictoolkit://cookbook/status/service/monitor/live-types
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

# Monitor Types

## Overview

This module declares the shared record vocabulary for the monitor's read
routes: eleven record shapes plus three shared status vocabularies (health
status, overall status, and deploy status), with no behavior and no side
effect of its own. The service status record is the base per-endpoint health
row (extended elsewhere by the live service record); the daily uptime entry,
per-service uptime summary, and uptime response bundle the uptime route's
daily rollups; the deployment record is the shape a deploy row becomes for
the board (produced elsewhere, outside this recipe); the history check entry
and history response declare the history route's per-check series; and the
check state, integration check entry, and integrations response declare the
integrations self-check report. This recipe specifies each record's
field-level shape and the invariants a producer or consumer of a value of
that shape MUST honor — not the route, mapper, or self-check logic that
builds or delivers one, which is each related recipe's own concern.

## Behavioral Requirements

- **module-reexports-shared-vocabulary**: The module MUST make health status, overall status, and deploy status available as part of its own vocabulary, so a consumer using only this module can name all three without reaching into their separate defining modules.
- **build-phase-deploy-phase-not-reexported**: The module MUST make build phase and deploy phase available for use as deployment-record field types, but MUST NOT make either available as part of its own vocabulary; a consumer that needs to name a build phase or deploy phase value directly MUST get it from the deploy status vocabulary's own defining module, not from this one.
- **type-only-no-runtime**: The module MUST declare data shapes only; it MUST NOT expose a behavior, a constant, or any other runtime value, and contains no side effect of its own.
- **service-status-dto-all-fields-required**: A service status record MUST carry all twelve fields (`slug`, `group`, `name`, `url`, `environment`, `platform`, `deployProject`, `status`, `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt`), none optional; a conformant value MUST supply an explicit `null` where a field permits it rather than omit the field.
- **service-status-platform-is-correlation-key**: A service status record's `platform` field MUST be a nullable string naming the explicit deploy target (a correlation key) — the field the monitor uses to correlate an endpoint to its deploys, not a display label.
- **service-status-status-includes-unknown**: A service status record's `status` field MUST accept a health status value or the literal `"unknown"` — the three health status values (`healthy`, `degraded`, `down`) plus `"unknown"`, which health status itself does not include.
- **uptime-day-status-excludes-unknown**: A daily uptime entry's `status` field MUST be a health status value alone (`healthy`, `degraded`, or `down`), never also `"unknown"` — unlike a service status record's or history check entry's `status` field, a daily uptime rollup has no `"unknown"` member.
- **uptime-percent-nullable-at-day-and-service-level**: Both a daily uptime entry's and a per-service uptime summary's `uptimePercent` field MUST be a nullable number, independently nullable at each level.
- **uptime-service-shape**: A per-service uptime summary MUST carry `slug`, `name`, `uptimePercent`, `totalChecks`, and a `daily` list of daily uptime entries, all required.
- **uptime-response-shape**: The uptime response MUST bundle a `services` list of per-service uptime summaries and a `days` number — the caller-requested window size the services were computed over.
- **deployment-dto-all-fields-required**: A deployment record MUST carry all fifteen fields (`id`, `platform`, `projectName`, `providerProjectId`, `status`, `buildPhase`, `deployPhase`, `environment`, `tier`, `commitHash`, `commitMessage`, `branch`, `commitRepo`, `url`, `errorText`, `liveHost`, `createdAt`, `phaseConfirmedAt`), none optional.
- **provider-project-id-required-though-nullable**: The `providerProjectId` field MUST be a nullable string and MUST always be present, never omitted, even though nullable — per the field's own documentation, this is required on the wire because a board target's identity segment falls back from `providerProjectId` to `projectName` when the former is absent, so a consumer correlating a target to a deployment can distinguish "this row has no provider id" from a field that is simply missing.
- **tier-required-and-distinct-from-environment**: The `tier` field MUST be a nullable string, present on every value, and MUST be treated as distinct from `environment` — per its own documentation, `environment` is the provider's promotion target (reading "production" for every Vercel project), while `tier` is the logical tier this build belongs to, derived once server-side so no client duplicates the derivation.
- **phase-confirmed-at-required-non-null**: The `phaseConfirmedAt` field MUST be a non-null string (an ISO timestamp) present on every value — unlike every other nullable or optional field on this record, it is never itself nullable or omittable; per its own documentation it records when the phases were last confirmed against provider truth, and an in-flight phase whose confirmation is old is a claim with a freshness deadline, not a fact.
- **error-text-verbatim-rendering**: The `errorText` field MUST be a nullable string and, per its own documentation, is rendered verbatim in the details pane — the provider's failure reason for a failed deploy, or `null` otherwise.
- **live-host-is-correlation-and-url**: The `liveHost` field MUST be a nullable string and, per its own documentation, is the resolved live custom domain host (a correlation key and a live URL).
- **build-deploy-phase-fields-typed-externally**: The `buildPhase` (nullable) and `deployPhase` fields MUST use the shared build phase and deploy phase vocabulary, not a locally redeclared one, so the deployment-lifecycle vocabulary can never diverge between the two.
- **history-check-mirrors-service-status-check-fields**: A history check entry MUST carry a `status` field (a health status value or `"unknown"`), a nullable `responseTimeMs`, a nullable `statusCode`, a nullable `error`, and a `checkedAt` string — the same four check-outcome fields a service status record carries (`status`, `responseTimeMs`, `statusCode`, `error`), with `lastCheckedAt` renamed `checkedAt` for a value standing for one point in a series rather than "most recent."
- **history-response-shape**: The history response MUST bundle a `service` string, an `hours` number, and a `checks` list of history check entries.
- **check-state-closed-set**: A check state MUST be exactly one of the three literal strings `"ok"`, `"warn"`, or `"error"`.
- **integration-check-required-fields**: An integration check entry MUST carry `id`, `label`, a boolean `configured`, a boolean `ok`, a `state` (a check state), and a `detail` string, all required.
- **integration-check-optional-fields**: The `missingEnv` (a list of strings), `unreachable` (boolean), and `correlated` (boolean) fields MUST each be optional and MAY be omitted when not applicable.
- **missing-env-names-not-values**: `missingEnv` MUST carry the exact names of expected environment variables found unset — per its own documentation, "(named exactly, e.g. CLOUDFLARE_ACCOUNT_ID)" — never their values, and, per the same documentation, SHOULD be omitted or empty "when nothing is missing."
- **unreachable-marks-no-http-response**: `unreachable` MUST mean the probe "got NO HTTP response at all (timeout/abort/connection failure)" per its own documentation, and MUST be distinguished from a real HTTP error response (401/5xx), which MUST NOT set `unreachable`.
- **correlated-marks-cross-provider-debounce**: `correlated` MUST mean the check was "confirmed-unreachable together with other providers in the same run" per its own documentation, to be treated by a consumer as monitor-side connectivity rather than an independent provider outage.
- **integrations-response-shape**: The integrations response MUST bundle a `generatedAt` string, an `overall` check state, and a `checks` list of integration check entries.

## Appearance

Not applicable — this is a record-shape contract module, not a visual component.

## States

Not applicable — this is a record-shape contract module, not a visual component.

## Accessibility

Not applicable — this is a record-shape contract module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| types-001 | service-status-status-includes-unknown, service-status-dto-all-fields-required | An endpoint with no persisted health check yet | The service status record sets `status: "unknown"` with `responseTimeMs`, `statusCode`, `error`, and `lastCheckedAt` all `null` — matching the four-member union and the all-fields-required contract, with no field omitted |
| types-002 | service-status-dto-all-fields-required | An endpoint with a persisted check of `{ status: 'healthy', responseTimeMs: 42, statusCode: 200 }` | The corresponding service status record matches `{ slug, status: 'healthy', responseTimeMs: 42 }` |
| types-003 | uptime-day-status-excludes-unknown, uptime-percent-nullable-at-day-and-service-level | A day with zero checks of every kind (`{ total: 0, healthy: 0, degraded: 0, down: 0 }`) | The day's status is `"healthy"` (the default fall-through) while its uptime percentage is `null`; a zero-check day is always a valid three-member health status, never a fourth `"unknown"` literal |
| types-004 | uptime-service-shape, uptime-response-shape | Two persisted checks (one `healthy`, one `down`) for one endpoint, requested over a 90-day window | The response's `days` is `90`, the service's `totalChecks` is `2`, and its `uptimePercent` is `50` |
| types-005 | history-check-mirrors-service-status-check-fields, history-response-shape | Two persisted checks (`healthy` at 10ms, `degraded` at 900ms), requested over a 24-hour window | The `service` field equals the slug, `hours` is `24`, and `checks` has length `2` — matching the history response shape at the wire level, per the open question on **history-response-not-referenced-by-name** in Design Decisions |
| types-006 | deployment-dto-all-fields-required, phase-confirmed-at-required-non-null | A deployment row whose creation time is an unparseable legacy timestamp | The record's `createdAt` is serialized as the epoch time rather than throwing; the same fallback rule backs `phaseConfirmedAt`, so neither field is ever left unparseable |
| types-007 | provider-project-id-required-though-nullable | A deployment row with no provider-issued id | The `providerProjectId` field is always present as an explicit `null`, never omitted |
| types-008 | tier-required-and-distinct-from-environment | A preview-branch deployment row that is not a real-environment row | The `tier` field evaluates to `null` regardless of what `environment` holds for that row |
| types-009 | integration-check-optional-fields, unreachable-marks-no-http-response | A provider probe that gets no HTTP response at all | The integration check entry sets `unreachable: true`; a check that does not apply omits the field rather than setting it `false` |
| types-010 | correlated-marks-cross-provider-debounce | Two providers unreachable in the same self-check run | Both providers' `correlated` field is `true`; contrast a lone failing provider that stays unreachable across runs and the window, whose `correlated` field is `undefined`, never `false` |
| types-011 | integrations-response-shape | A request against a running self-check | The response body has `generatedAt` and `overall` fields and a `checks` array containing an entry with `id === 'stats'` |

## Edge Cases

- **Null and empty input**: an endpoint with no persisted health check yet MUST be represented as a service status record with `status: "unknown"` and `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt` all `null` — per **service-status-status-includes-unknown** and **service-status-dto-all-fields-required**; the producer that builds this record, outside this recipe, is the one place this is currently exercised. (MUST)
- **Null and empty input**: a deployment record with no provider-issued id or no resolvable tier MUST carry `providerProjectId: null` / `tier: null` as explicit values, never omitting either field — per **provider-project-id-required-though-nullable** and **tier-required-and-distinct-from-environment**. (MUST)
- **Null and empty input**: an integration check entry with nothing missing SHOULD omit `missingEnv` entirely rather than supply an empty list — per the field's own documentation, "Omitted/empty when nothing is missing," both forms are treated as equivalent, so a producer's choice between them is a style choice this contract does not prescribe either way. (SHOULD)
- **Boundary values**: health status, overall status, deploy status, build phase, deploy phase, and check state are each closed sets of literal strings; a value outside a set's listed literals is not a valid value of that shape — this module supplies no runtime guard of its own for a value that arrives already widened to plain text from an untyped boundary such as a parsed payload or a text-typed database column, since a declared shape vanishes at runtime, not only for this module. (MUST, for the compile-time guarantee)
- **Boundary values**: a daily uptime entry's status admits only the three health status literals, never `"unknown"`; a day with zero checks still returns `"healthy"` — the default fall-through — while its uptime percentage returns `null` for that same zero-check day, so the two fields diverge (a definite status paired with a null percentage) rather than the shape offering a fourth "no data" status literal. (MUST)
- **Concurrent access**: not applicable — this module declares no mutable state and no behavior, so nothing in it can be entered concurrently. The concurrency of whichever producer builds a value of one of these shapes is outside this module's own contract.
- **Error states**: not applicable to this module raising one — it declares no behavior that can fail. `errorText` (deployment record) and `error` (service status record, history check entry) are this contract's error-state signal instead: a producer that observed a failure MUST report it through that field as a string, per **error-text-verbatim-rendering**, rather than through an exception this module has no mechanism to carry.
- **Offline or disconnected state**: not applicable — this module makes no network call of its own; `lastCheckedAt`, `checkedAt`, and `phaseConfirmedAt` exist precisely so a consumer can judge the staleness of data that was already gathered elsewhere, per **phase-confirmed-at-required-non-null**.

## Configuration

Not applicable: this module declares data shapes only — no parameter, default value, environment variable, settings key, or injected dependency of its own; every field's value is supplied entirely by whichever producer constructs a value of one of these shapes.

## Deep Linking

Not applicable: this module declares data shapes only — no URL, route, or navigable destination originates from it; `url` (service status record, deployment record) and `liveHost` (deployment record) are nullable-string fields the module declares but does not construct or navigate to.

## Localization

Not applicable: this module contains no string literal used as user-facing text — every text-carrying field (`error`, `errorText`, `detail`, `commitMessage`, `branch`) is a text-type field declaration, not a value, so there is no prose for this module itself to localize. The closed literal sets (health status, deploy status, check state, and the rest) are wire-protocol tokens, not display strings — presenting one to a user is a consumer's rendering concern, outside this module.

## Accessibility Options

Not applicable: this module renders nothing and reads no accessibility display setting — it declares data shapes only, with no UI of its own.

## Feature Flags

Not applicable: the module declares no feature-flag key and contains no conditional feature-gating logic of any kind.

## Analytics

Not applicable: the module contains no analytics or event-emission call of any kind; it declares data shapes only.

## Privacy

Not applicable: this module declares data shapes only — it collects, stores, and transmits nothing itself. None of its fields is a token or credential; `missingEnv` (integration check entry) carries only the names of unset environment variables — per its own documentation, "named exactly, e.g. CLOUDFLARE_ACCOUNT_ID" — never their values, so this field cannot leak a credential even when populated. The commit hashes, branch names, project names, URLs, and error strings the other records carry are operational monitoring data already produced elsewhere; this module neither reads nor writes them.

## Logging

Not applicable: the module contains no log call of any kind — it declares data shapes only, with no behavior to log from.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/service/monitor/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
