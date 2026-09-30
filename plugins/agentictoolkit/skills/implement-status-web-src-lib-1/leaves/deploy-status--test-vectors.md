<!-- leaf: implement-status-web-src-lib-1/deploy-status--test-vectors · source: status-web-src-lib-deploy-status.md -->

# Status Web Deploy Status

## Conformance Test Vectors

Vectors 001 to 014 are traced to the assertions in `deploy-status.test.ts`. Vectors 015 and 016 are traced to `deploy-status-parity.test.ts`. Vectors 017 to 022 are traced to the function bodies.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| deploy-status-001 | vercel-build-fallback, vercel-build-queued, vercel-build-error, vercel-build-canceled, vercel-build-ready | `vercelPhases` with readyState `"BUILDING"`, `"QUEUED"`, `"ERROR"`, `"CANCELED"`, `"READY"` | `buildPhase` of `"building"`, `"queued"`, `"failed"`, `"canceled"`, `"built"` |
| deploy-status-002 | vercel-deploy-promoted | `vercelPhases("READY", "PROMOTED", "production")` | `deployPhase` `"deployed"` |
| deploy-status-003 | vercel-deploy-rolling | `vercelPhases("READY", "ROLLING", "production")` | `deployPhase` `"deploying"` |
| deploy-status-004 | vercel-deploy-staged | `vercelPhases("READY", "STAGED", "production")` | `deployPhase` `"none"` |
| deploy-status-005 | vercel-deploy-default | `vercelPhases("READY", null, null)`; `vercelPhases("READY", "PROMOTED", "staging")` | `deployPhase` `"none"` for both |
| deploy-status-006 | railway-building, railway-deploying, railway-success, railway-failed | `railwayPhases` with `"BUILDING"`, `"DEPLOYING"`, `"SUCCESS"`, `"FAILED"` | `{building, none}`, `{built, deploying}`, `{built, deployed}`, `{failed, none}` |
| deploy-status-007 | railway-crashed, railway-queued, railway-canceled | `railwayPhases` with `"CRASHED"`, `"WAITING"`, `"REMOVED"`, `"SKIPPED"` | `{built, deployed}`, `{queued, none}`, `{canceled, none}`, `{canceled, none}` |
| deploy-status-008 | combined-failed-first | `combinedStatus` of `{failed, none}` and of `{built, failed}` | `"failed"` for both |
| deploy-status-009 | combined-deployed, combined-built | `combinedStatus` of `{built, deployed}` and of `{built, none}` | `"success"` for both |
| deploy-status-010 | combined-fallback, combined-deploying | `combinedStatus` of `{building, none}` and of `{built, deploying}` | `"building"` for both |
| deploy-status-011 | combined-deployed, null-build-phase | `combinedStatus({ buildPhase: null, deployPhase: "deployed" })` | `"success"` |
| deploy-status-012 | combined-fallback, combined-queued | `combinedStatus` of `{null, none}` and of `{queued, none}` | `"building"`; `"queued"` |
| deploy-status-013 | combined-unknown, unknown-terminal | `combinedStatus` of `{unknown, none}` and of `{built, unknown}` | `"unknown"` for both |
| deploy-status-014 | combined-failed-first, combined-unknown | `combinedStatus({ buildPhase: "unknown", deployPhase: "failed" })` | `"failed"` |
| deploy-status-015 | in-flight-build-phases, in-flight-deploy-phase, server-parity-constants | Compare web and server `IN_FLIGHT_BUILD_PHASES` and `IN_FLIGHT_DEPLOY_PHASE` | Equal arrays; both deploy phases `"deploying"` |
| deploy-status-016 | server-parity-is-in-flight, server-parity-combined | For all 35 pairs of build phase (7 values including `null`) and deploy phase (5 values), call web and server `isInFlight` and `combinedStatus` | Web and server results are identical for every pair |
| deploy-status-017 | is-in-flight-build, is-in-flight-deploy, is-in-flight-terminal | `isInFlight("queued", "none")`; `isInFlight("built", "deploying")`; `isInFlight(null, "deployed")`; `isInFlight("unknown", "unknown")` | `true`; `true`; `false`; `false` |
| deploy-status-018 | deploy-status-in-flight, in-flight-statuses | `deployStatusInFlight` for each of `"building"`, `"queued"`, `"success"`, `"failed"`, `"canceled"`, `"unknown"` | `true`, `true`, `false`, `false`, `false`, `false` |
| deploy-status-019 | vercel-build-canceled, vercel-build-fallback | `vercelPhases("DELETED", null, null)`; `vercelPhases("INITIALIZING", null, "production")`; `vercelPhases("ready", "PROMOTED", "production")` | `{canceled, none}`; `{building, none}`; `{building, none}` |
| deploy-status-020 | railway-queued, railway-building, railway-fallback | `railwayPhases("NEEDSAPPROVAL")`; `railwayPhases("INITIALIZING")`; `railwayPhases("")`; `railwayPhases("success")` | `{queued, none}`; `{building, none}`; `{building, none}`; `{building, none}` |
| deploy-status-021 | combined-canceled | `combinedStatus({ buildPhase: "canceled", deployPhase: "deployed" })`; `combinedStatus({ buildPhase: "canceled", deployPhase: "unknown" })` | `"canceled"` for both |
| deploy-status-022 | vercel-deploy-staged | `vercelPhases("READY", undefined, "production")`; then `combinedStatus` of the result | `{built, none}`; `"success"` |
