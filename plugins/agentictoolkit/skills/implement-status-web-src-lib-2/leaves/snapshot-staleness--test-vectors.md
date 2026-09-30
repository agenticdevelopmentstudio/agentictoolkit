<!-- leaf: implement-status-web-src-lib-2/snapshot-staleness--test-vectors · source: status-web-src-lib-snapshot-staleness.md -->

# Snapshot Staleness

## Conformance Test Vectors

All vectors use `GEN = "2024-06-01T12:00:00.000Z"` and `lag(ms)` = the ISO string `ms` milliseconds before `GEN`. Vectors 001 to 013 are traced to the assertions in `snapshot-staleness.test.ts`. Vectors 014 to 018 are traced to the function bodies (strict comparisons, the `?? 0` fallback and the falsy guard).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| snapshot-staleness-001 | window-unknown-interval, stale-floor | `snapshotStaleMs(undefined)`; `snapshotStaleMs(null)` | 300 000 for both |
| snapshot-staleness-002 | window-small-interval | `snapshotStaleMs(60000)` | 300 000 |
| snapshot-staleness-003 | window-scaling, window-formula | `snapshotStaleMs(120000)` | 600 000 |
| snapshot-staleness-004 | missing-last-cycle | `snapshotFreshness(null, GEN, 60000)`; `snapshotFreshness(undefined, GEN)` | `"fresh"` for both |
| snapshot-staleness-005 | missing-generated-at | `snapshotFreshness(lag(600000), null)` | `"fresh"` |
| snapshot-staleness-006 | fresh-at-or-below-window, lag-computation | `snapshotFreshness(lag(240000), GEN, 60000)` | `"fresh"` |
| snapshot-staleness-007 | stale-band | `snapshotFreshness(lag(360000), GEN, 60000)` | `"stale"` |
| snapshot-staleness-008 | very-stale-band | `snapshotFreshness(lag(960000), GEN, 60000)` | `"very-stale"` |
| snapshot-staleness-009 | window-scaling, fresh-at-or-below-window | `snapshotFreshness(lag(360000), GEN, 120000)` | `"fresh"` |
| snapshot-staleness-010 | window-scaling, stale-band | `snapshotFreshness(lag(660000), GEN, 120000)` | `"stale"` |
| snapshot-staleness-011 | nan-fails-open | `snapshotFreshness("not-a-date", GEN, 60000)` | `"fresh"` |
| snapshot-staleness-012 | nan-fails-open | `snapshotFreshness(lag(1200000), "not-a-date", 60000)` | `"fresh"` |
| snapshot-staleness-013 | negative-lag-fresh | `snapshotFreshness` with lastCycleAt = GEN plus 30 000 ms, `GEN`, `60000` | `"fresh"` |
| snapshot-staleness-014 | fresh-at-or-below-window | `snapshotFreshness(lag(300000), GEN, 60000)` (lag exactly the window) | `"fresh"` |
| snapshot-staleness-015 | stale-band | `snapshotFreshness(lag(900000), GEN, 60000)` (lag exactly three times the window) | `"stale"` |
| snapshot-staleness-016 | very-stale-band | `snapshotFreshness(lag(900001), GEN, 60000)` | `"very-stale"` |
| snapshot-staleness-017 | missing-last-cycle | `snapshotFreshness("", GEN, 60000)` | `"fresh"` |
| snapshot-staleness-018 | window-small-interval | `snapshotStaleMs(0)`; `snapshotStaleMs(-1000)` | 300 000 for both |
| snapshot-staleness-019 | server-clock-only | `snapshotFreshness(lag(360000), GEN, 60000)` evaluated with the system clock set one day ahead | `"stale"` (unchanged) |
| snapshot-staleness-020 | freshness-type | Every return value across vectors 004 to 017 | One of `"fresh"`, `"stale"`, `"very-stale"` |
