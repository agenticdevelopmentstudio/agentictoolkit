<!-- leaf: implement-status-server-monitor-2/uptime--test-vectors · source: status-server-monitor-uptime.md -->

# Status Server Monitor Uptime

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-uptime-001 | uptime-percent-formula, uptime-percent-degraded-counts-as-up | `uptimePercent({ total: 100, healthy: 90, degraded: 5, down: 5 })` | Returns `95` — `status-web/src/lib/uptime.test.ts` › "counts healthy+degraded as up" (evidence source for the byte-identical formula, per Design Decisions) |
| status-server-monitor-uptime-002 | uptime-percent-no-data | `uptimePercent({ total: 0, healthy: 0, degraded: 0, down: 0 })` | Returns `null` — same test file › "null when no checks" |
| status-server-monitor-uptime-003 | uptime-percent-formula | `uptimePercent({ total: 3, healthy: 1, degraded: 1, down: 1 })` | Returns `66.67` — traced directly to `Math.round(((2/3) * 10000)) / 100` in the source (2 of 3 checks up, rounded to two decimal places) |
| status-server-monitor-uptime-004 | day-status-down-majority | `dayStatus({ total: 10, healthy: 2, degraded: 0, down: 8 })` | Returns `"down"` (`8/10 = 0.8`, greater than `0.5`) — `status-web/src/lib/uptime.test.ts` › "day status: >50% down is down" |
| status-server-monitor-uptime-005 | day-status-down-minority | `dayStatus({ total: 10, healthy: 7, degraded: 0, down: 3 })` | Returns `"degraded"` (`3/10 = 0.3`, not greater than `0.5`) — same test file › "day status: some down <=50% is degraded" |
| status-server-monitor-uptime-006 | day-status-degraded-only | `dayStatus({ total: 10, healthy: 8, degraded: 2, down: 0 })` | Returns `"degraded"` — same test file › "day status: degraded only is degraded" |
| status-server-monitor-uptime-007 | day-status-healthy-default | `dayStatus({ total: 10, healthy: 10, degraded: 0, down: 0 })` | Returns `"healthy"` — same test file › "day status: all healthy is healthy" |
| status-server-monitor-uptime-008 | day-status-no-zero-total-guard | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 0 })` | Returns `"healthy"` — traced directly to the source's fallthrough (`c.down > 0` is false, `c.degraded > 0` is false, default `"healthy"`); contrast with vector 002, the identical input returning `null` from `uptimePercent` |
| status-server-monitor-uptime-009 | overall-uptime-mean | `overallUptimePercent([{ uptimePercent: 100 }, { uptimePercent: 90 }])` | Returns `95` — `status-web/src/lib/uptime.test.ts` › "is the simple mean of each service's uptime (every service counts equally)" |
| status-server-monitor-uptime-010 | overall-uptime-excludes-null | `overallUptimePercent([{ uptimePercent: 99 }, { uptimePercent: null }, { uptimePercent: 95 }])` | Returns `97` (mean of `99` and `95` only; the divisor is `2`, not `3`) — same test file › "ignores services with null uptime (no data), averaging the rest equally" |
| status-server-monitor-uptime-011 | overall-uptime-no-data | `overallUptimePercent([])` | Returns `null` — same test file › "is null when there's no data" |
| status-server-monitor-uptime-012 | overall-uptime-no-data | `overallUptimePercent([{ uptimePercent: null }])` | Returns `null` — same test file |
| status-server-monitor-uptime-013 | uptime-percent-formula (caller integration) | `GET /uptime?days=90` against seeded per-day check rows for one configured endpoint | `body.services[0].uptimePercent === 50` — `test/reads.int.test.ts` › "/uptime aggregates daily counts for the configured endpoint" (integration evidence for the same formula reached through the caller `buildUptime`) |
| status-server-monitor-uptime-014 | pure-computation, concurrency-safety | `uptimePercent(c)` and `dayStatus(c)` both called on the same `Counts` object `c = { total: 10, healthy: 10, degraded: 0, down: 0 }`, repeated and interleaved with calls using other `Counts` values | Every call returns the same value for the same input every time (`100` and `"healthy"` for `c`), and `c`'s own fields are unchanged after any call — traced to the source's complete absence of module-scope variables or mutation of the `c` parameter |
| status-server-monitor-uptime-015 | counts-shape, health-status-return | `dayStatus`'s return value inspected across vectors 004–008 | Every returned value is one of exactly `"healthy"`, `"degraded"`, or `"down"` (`HealthStatus`, `./health`); the function's TypeScript return type makes any other string a compile error at the call site — traced to the `import type { HealthStatus } from "./health"` and the function's `: HealthStatus` return annotation |
