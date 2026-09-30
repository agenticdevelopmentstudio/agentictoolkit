<!-- leaf: implement-status-web-src-lib-2/uptime--test-vectors · source: status-web-src-lib-uptime.md -->

# Uptime Math

## Conformance Test Vectors

Vectors 001–009 are the assertions in `uptime.test.ts`; the rest are derived from the source arithmetic.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| uptime-001 | uptime-degraded-counts-as-up, uptime-two-decimal-rounding | `uptimePercent({ total: 100, healthy: 90, degraded: 5, down: 5 })` | `95` |
| uptime-002 | uptime-null-when-no-checks | `uptimePercent({ total: 0, healthy: 0, degraded: 0, down: 0 })` | `null` |
| uptime-003 | day-down-majority | `dayStatus({ total: 10, healthy: 2, degraded: 0, down: 8 })` | `"down"` |
| uptime-004 | day-down-minority | `dayStatus({ total: 10, healthy: 7, degraded: 0, down: 3 })` | `"degraded"` |
| uptime-005 | day-degraded | `dayStatus({ total: 10, healthy: 8, degraded: 2, down: 0 })` | `"degraded"` |
| uptime-006 | day-healthy | `dayStatus({ total: 10, healthy: 10, degraded: 0, down: 0 })` | `"healthy"` |
| uptime-007 | overall-unweighted-mean | `overallUptimePercent([{ uptimePercent: 100 }, { uptimePercent: 90 }])` | `95` |
| uptime-008 | overall-ignores-null | `overallUptimePercent([{ uptimePercent: 99 }, { uptimePercent: null }, { uptimePercent: 95 }])` | `97` |
| uptime-009 | overall-null-when-no-data | `overallUptimePercent([])` and `overallUptimePercent([{ uptimePercent: null }])` | `null` for both |
| uptime-010 | uptime-two-decimal-rounding | `uptimePercent({ total: 3, healthy: 2, degraded: 0, down: 1 })` | `66.67` |
| uptime-011 | uptime-null-when-no-checks | `uptimePercent({ total: -1, healthy: 0, degraded: 0, down: 0 })` | `null` |
| uptime-012 | uptime-denominator-total, uptime-no-clamp | `uptimePercent({ total: 4, healthy: 5, degraded: 0, down: 0 })` | `125` |
| uptime-013 | day-down-minority | `dayStatus({ total: 10, healthy: 5, degraded: 0, down: 5 })` (exactly half down) | `"degraded"` |
| uptime-014 | day-down-checked-first | `dayStatus({ total: 10, healthy: 0, degraded: 9, down: 1 })` | `"degraded"` |
| uptime-015 | day-zero-total-with-down | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 1 })` | `"down"` |
| uptime-016 | day-healthy | `dayStatus({ total: 0, healthy: 0, degraded: 0, down: 0 })` | `"healthy"` |
| uptime-017 | overall-two-decimal-rounding | `overallUptimePercent([{ uptimePercent: 33.33 }, { uptimePercent: 33.33 }, { uptimePercent: 33.34 }])` | `33.33` |
| uptime-018 | overall-nan-propagates | `overallUptimePercent([{ uptimePercent: NaN }, { uptimePercent: 90 }])` | `NaN` |
| uptime-019 | service-input-shape, overall-unweighted-mean | `overallUptimePercent([{ uptimePercent: 100, totalChecks: 1000 }, { uptimePercent: 50, totalChecks: 2 }])` | `75` (check volume has no effect) |
| uptime-020 | pure-functions | Call `uptimePercent`, `dayStatus` and `overallUptimePercent` on frozen input objects and arrays | No exception; inputs unchanged |
