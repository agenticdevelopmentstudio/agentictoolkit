<!-- leaf: implement-status-server-monitor-1/overall--test-vectors · source: status-server-monitor-overall.md -->

# Status Server Monitor Overall

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-overall-001 | empty-statuses-is-unknown | `computeOverall([])` | `'unknown'` — `overall.test.ts` › "no statuses → unknown" |
| status-server-monitor-overall-002 | all-healthy-is-operational | `computeOverall(['healthy', 'healthy'])` | `'operational'` — `overall.test.ts` › "all healthy → operational" |
| status-server-monitor-overall-003 | any-down-or-degraded-is-degraded | `computeOverall(['healthy', 'degraded'])` | `'degraded'` — `overall.test.ts` › "any degraded → degraded" |
| status-server-monitor-overall-004 | any-down-or-degraded-is-degraded | `computeOverall(['healthy', 'down'])` | `'degraded'` — `overall.test.ts` › "some down → degraded" |
| status-server-monitor-overall-005 | all-down-is-major-outage, compute-overall-check-order | `computeOverall(['down', 'down'])` | `'major_outage'` — `overall.test.ts` › "all down → major_outage"; this input also satisfies any-down-or-degraded-is-degraded's condition, so this vector confirms check-order's precedence rather than only the final value |
| status-server-monitor-overall-006 | non-endpoint-problem-degrades-operational, public-overall-base | `publicOverall(['healthy', 'healthy'], true)` | `'degraded'` — `overall.test.ts` › "healthy endpoints + a non-endpoint problem (e.g. a failed build) → degraded" |
| status-server-monitor-overall-007 | no-problem-leaves-base-unchanged | `publicOverall(['healthy', 'healthy'], false)` | `'operational'` — `overall.test.ts` › "healthy endpoints + no other problem → operational (unchanged)" |
| status-server-monitor-overall-008 | non-endpoint-problem-degrades-operational, non-endpoint-problem-never-escalates-past-degraded | `publicOverall(['healthy'], true)` | `'degraded'` — `overall.test.ts` › "a non-endpoint problem never manufactures a full outage — degraded, not major_outage" |
| status-server-monitor-overall-009 | non-endpoint-problem-never-overrides-major-outage | `publicOverall(['down', 'down'], true)` | `'major_outage'` — `overall.test.ts` › "an all-endpoints-down major_outage stands even with non-endpoint problems" |
| status-server-monitor-overall-010 | non-endpoint-problem-never-overrides-existing-degraded | `publicOverall(['healthy', 'down'], true)` | `'degraded'` — `overall.test.ts` › "an already-degraded endpoint rollup is unchanged by a non-endpoint problem" |
| status-server-monitor-overall-011 | non-endpoint-problem-never-lifts-unknown | `publicOverall([], true)` | `'unknown'` — `overall.test.ts` › "an unknown (no-signal) rollup is never lifted to degraded by a problem flag" |
| status-server-monitor-overall-012 | overall-status-values | the four literals returned across `computeOverall` and `publicOverall`'s branches | each is one of `'operational'`, `'degraded'`, `'major_outage'`, `'unknown'` — traced to the `OverallStatus` type declaration; not exercised by a dedicated `overall.test.ts` assertion, confirmed by inspection of the declaration and the return literals used throughout the source |
| status-server-monitor-overall-013 | health-status-input | `computeOverall` and `publicOverall`'s `statuses` parameter type is declared `HealthStatus[]` (imported as a type-only import from `./health`) | compile-time rejection of an `"unknown"` element — traced to the `import type { HealthStatus } from "./health"` declaration and `HealthStatus`'s three-value union in `health.ts`; no runtime test exercises this since TypeScript enforces it at compile time |
| status-server-monitor-overall-014 | pure-synchronous-functions | two sequential, independent calls `computeOverall(['down'])` followed by `computeOverall(['down'])` | both calls return `'degraded'` with neither call's result affected by the other — traced to the absence of any module-level mutable state or `await` in `overall.ts`; not exercised by a dedicated concurrency test in `overall.test.ts`, confirmed by inspection of the source having no side effects |
| status-server-monitor-overall-015 | exported-surface | `import { computeOverall, publicOverall, type OverallStatus } from '../src/monitor/overall'` (as `overall.test.ts` and `routes/reads.ts` do) | the import resolves all three names — traced to the `export` keyword on each declaration in `overall.ts` |
