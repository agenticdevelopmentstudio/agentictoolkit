<!-- leaf: implement-status-web-src-lib-1/overall--test-vectors · source: status-web-src-lib-overall.md -->

# Overall Status Rollup

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-web-src-lib-overall-001 | empty-is-unknown | `computeOverall([])` | `"unknown"` (`overall.test.ts` "empty is unknown") |
| status-web-src-lib-overall-002 | all-healthy-is-operational | `computeOverall(["healthy", "healthy"])` | `"operational"` (`overall.test.ts` "all healthy is operational") |
| status-web-src-lib-overall-003 | any-down-or-degraded-is-degraded | `computeOverall(["healthy", "degraded"])` | `"degraded"` (`overall.test.ts` "any degraded is degraded") |
| status-web-src-lib-overall-004 | any-down-or-degraded-is-degraded | `computeOverall(["healthy", "down"])` | `"degraded"` (`overall.test.ts` "some down is degraded") |
| status-web-src-lib-overall-005 | all-down-is-major-outage, check-order | `computeOverall(["down", "down"])` | `"major_outage"` (`overall.test.ts` "all down is major_outage"); also meets the degraded condition, so it confirms check-order |
| status-web-src-lib-overall-006 | single-down-is-major-outage | `computeOverall(["down"])` | `"major_outage"` (traced to the `every` check; no dedicated test) |
| status-web-src-lib-overall-007 | any-down-or-degraded-is-degraded | `computeOverall(["degraded", "degraded"])` | `"degraded"` (traced to the `some` check) |
| status-web-src-lib-overall-008 | any-down-or-degraded-is-degraded, order-independent | `computeOverall(["down", "degraded"])` and `computeOverall(["degraded", "down"])` | both `"degraded"` |
| status-web-src-lib-overall-009 | all-healthy-is-operational | `computeOverall(["healthy"])` | `"operational"` |
| status-web-src-lib-overall-010 | no-mutation | `const a = ["down", "healthy"]; computeOverall(a)` | returns `"degraded"`; `a` still equals `["down", "healthy"]` |
| status-web-src-lib-overall-011 | unrecognized-element-fallback | `computeOverall(["unknown"] as unknown as HealthStatus[])` | `"operational"` |
| status-web-src-lib-overall-012 | overall-status-values, compute-overall-signature, health-status-input | assign `"ok"` to an `OverallStatus`, or pass `["unknown"]` without a cast | compile-time type error |
| status-web-src-lib-overall-013 | pure-synchronous, no-errors-raised | call `computeOverall` with any `HealthStatus[]` | returns a string synchronously (not a Promise); no throw, no console output |
| status-web-src-lib-overall-014 | exported-surface, type-only-health-import | inspect module exports and imports | exports only `OverallStatus` and `computeOverall`; the only import is `import type { HealthStatus } from "./health"` |
| status-web-src-lib-overall-015 | no-runtime-caller-in-client | search status-web sources for `computeOverall` | only `overall.ts` and `overall.test.ts` reference it; `types.ts` uses `OverallStatus` for `StatusResponse.overall` |
