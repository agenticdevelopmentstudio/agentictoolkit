<!-- leaf: implement-status-server-monitor-2/types · source: status-server-monitor-types.md -->

**Rules** (cite as `implement-status-server-monitor-2/types#<slug>`):

- `consumer-value-type-honor-route-mapper-self` MUST — types.ts declares the shared wire-contract vocabulary for the monitor's read routes: eleven export interface/export …
- `module-reexports-shared-vocabulary` MUST
- `build-phase-deploy-phase-not-reexported` MUST
- `type-only-no-runtime` MUST
- `service-status-dto-all-fields-required` MUST
- `service-status-platform-is-correlation-key` MUST
- `service-status-status-includes-unknown` MUST
- `uptime-day-status-excludes-unknown` MUST
- `uptime-percent-nullable-at-day-and-service-level` MUST
- `uptime-service-shape` MUST
- `uptime-response-shape` MUST
- `deployment-dto-all-fields-required` MUST
- `provider-project-id-required-though-nullable` MUST
- `tier-required-and-distinct-from-environment` MUST
- `phase-confirmed-at-required-non-null` MUST
- `error-text-verbatim-rendering` MUST
- `live-host-is-correlation-and-url` MUST
- `build-deploy-phase-fields-typed-externally` MUST
- `history-check-mirrors-service-status-check-fields` MUST
- `history-response-shape` MUST
- `check-state-closed-set` MUST
- `integration-check-required-fields` MUST
- `integration-check-optional-fields` MUST
- `missing-env-names-not-values` MUST
- `unreachable-marks-no-http-response` MUST
- `correlated-marks-cross-provider-debounce` MUST
- `integrations-response-shape` MUST

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

