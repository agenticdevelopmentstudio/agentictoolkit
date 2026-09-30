<!-- leaf: implement-status-server-monitor-2/types--edge-cases · source: status-server-monitor-types.md -->

# Status Server Monitor Types

**Rules** (cite as `implement-status-server-monitor-2/types--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an endpoint with no persisted health check yet MUST be represented as ServiceStatusDTO with status: "unknown" and …
- `null-and-empty-input-2` MUST — a DeploymentDTO row with no provider-issued id or no resolvable tier MUST carry providerProjectId: null / tier: null as …
- `null-and-empty-input-3` SHOULD — an IntegrationCheck with nothing missing SHOULD omit missingEnv entirely rather than supply an empty array — per the …
- `boundary-values` MUST — HealthStatus, OverallStatus, DeployStatus, BuildPhase, DeployPhase, and CheckState are each closed literal-string …
- `boundary-values-2` MUST — UptimeDay.status admits only the three HealthStatus literals, never "unknown"; per uptime.ts's dayStatus, a day with …
- `error-states` MUST — not applicable to this file raising one — it declares no function that can throw. errorText (DeploymentDTO) and error …

## Edge Cases

- **Null and empty input**: an endpoint with no persisted health check yet MUST be represented as `ServiceStatusDTO` with `status: "unknown"` and `responseTimeMs`, `statusCode`, `error`, `lastCheckedAt` all `null` — per **service-status-status-includes-unknown** and **service-status-dto-all-fields-required**; `routes/reads.ts`'s `serviceDtos` producer, outside this file, is the one place this is currently exercised. (MUST)
- **Null and empty input**: a `DeploymentDTO` row with no provider-issued id or no resolvable tier MUST carry `providerProjectId: null` / `tier: null` as explicit values, never omitting either property — per **provider-project-id-required-though-nullable** and **tier-required-and-distinct-from-environment**. (MUST)
- **Null and empty input**: an `IntegrationCheck` with nothing missing SHOULD omit `missingEnv` entirely rather than supply an empty array — per the field's own comment, "Omitted/empty when nothing is missing," both forms are treated as equivalent, so a producer's choice between them is a style choice this contract does not prescribe either way. (SHOULD)
- **Boundary values**: `HealthStatus`, `OverallStatus`, `DeployStatus`, `BuildPhase`, `DeployPhase`, and `CheckState` are each closed literal-string unions; a value outside a union's listed literals is not a valid value of that type, and TypeScript rejects it at compile time for a caller that assigns a literal — this module supplies no runtime guard of its own for a value that arrives already-widened to plain `string` from an untyped boundary such as `JSON.parse` or a `TEXT` database column, since an interface or type alias vanishes at runtime for every TypeScript module, not only this one. (MUST, for the compile-time guarantee)
- **Boundary values**: `UptimeDay.status` admits only the three `HealthStatus` literals, never `"unknown"`; per `uptime.ts`'s `dayStatus`, a day with zero checks (`Counts { total: 0, healthy: 0, degraded: 0, down: 0 }`) still returns `"healthy"` — its default fall-through — while `uptimePercent` returns `null` for that same zero-check day, so the two fields diverge (a definite status paired with a null percentage) rather than the type offering a fourth "no data" status literal. (MUST)
- **Concurrent access**: not applicable — this file declares no mutable state and no function, so nothing in it can be entered concurrently. The concurrency of whichever producer builds a value of one of these types (`routes/reads.ts`, `provider-deploy.ts`, `integrations.ts`) is outside this file's own contract.
- **Error states**: not applicable to this file raising one — it declares no function that can throw. `errorText` (`DeploymentDTO`) and `error` (`ServiceStatusDTO`, `HistoryCheck`) are this contract's error-state signal instead: a producer that observed a failure MUST report it through that field as a `string`, per **error-text-verbatim-rendering**, rather than through an exception this file has no mechanism to carry.
- **Offline or disconnected state**: not applicable — this file makes no network call of its own; `lastCheckedAt`, `checkedAt`, and `phaseConfirmedAt` exist precisely so a consumer can judge the staleness of data that was already gathered elsewhere, per **phase-confirmed-at-required-non-null**.
