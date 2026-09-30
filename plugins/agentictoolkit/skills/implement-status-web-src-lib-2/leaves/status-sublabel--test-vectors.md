<!-- leaf: implement-status-web-src-lib-2/status-sublabel--test-vectors · source: status-web-src-lib-status-sublabel.md -->

# Status Sublabel

## Conformance Test Vectors

The source has no test file (`status-sublabel.test.ts` does not exist). These vectors are derived from `buildSublabel` and `SUBLABEL_PHRASE`. `row(w)` stands for a `Row` whose `statusWord` is `w`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sublabel-001 | ok-all-healthy | `buildSublabel("ok", 12, 12, [])` | `"12/12 endpoints healthy · no failed builds"` |
| sublabel-002 | ok-not-all-healthy | `buildSublabel("ok", 4, 5, [])` | `"5 endpoints monitored · no failed builds"` |
| sublabel-003 | ok-ignores-problems | `buildSublabel("ok", 3, 3, [row("down")])` | `"3/3 endpoints healthy · no failed builds"` |
| sublabel-004 | ok-strict-equality | `buildSublabel("ok", 6, 5, [])` | `"5 endpoints monitored · no failed builds"` |
| sublabel-005 | ok-all-healthy | `buildSublabel("ok", 0, 0, [])` | `"0/0 endpoints healthy · no failed builds"` |
| sublabel-006 | breakdown-phrase-down, breakdown-phrase-degraded, breakdown-separator | `buildSublabel("warn", 0, 0, [row("degraded"), row("down"), row("down")])` | `"2 down · 1 degraded"` |
| sublabel-007 | breakdown-phrase-build-failed | `buildSublabel("down", 0, 0, [row("build failed")])`; the same with two rows | `"1 failed build"`; `"2 failed builds"` |
| sublabel-008 | breakdown-phrase-deploy-failed | `buildSublabel("down", 0, 0, [row("deploy failed")])`; the same with three rows | `"1 failed deploy"`; `"3 failed deploys"` |
| sublabel-009 | breakdown-phrase-deployment-failed | `buildSublabel("warn", 0, 0, [row("deployment failed"), row("deployment failed")])` | `"2 stale deploys"` |
| sublabel-010 | breakdown-phrase-building | `buildSublabel("warn", 0, 0, [row("building")])` | `"1 stuck build"` |
| sublabel-011 | breakdown-phrase-platform-unreachable | one `row("platform unreachable")`; then two such rows, with state `"down"` | `"1 platform unreachable"`; `"2 platforms unreachable"` |
| sublabel-012 | breakdown-mapped-order | `buildSublabel("down", 0, 0, [row("building"), row("build failed"), row("down")])` | `"1 down · 1 failed build · 1 stuck build"` |
| sublabel-013 | breakdown-unmapped-verbatim, breakdown-unmapped-after-mapped | `buildSublabel("warn", 0, 0, [row("expired"), row("down"), row("cert warn"), row("expired")])` | `"1 down · 2 expired · 1 cert warn"` |
| sublabel-014 | breakdown-empty-problems | `buildSublabel("warn", 5, 5, [])` | `""` |
| sublabel-015 | breakdown-group-by-status-word | `buildSublabel("warn", 0, 0, [row("Down")])` | `"1 Down"` (unmapped, because matching is case-sensitive) |
| sublabel-016 | breakdown-sums-to-problem-count | any non-ok call with `problems.length === 7` over mixed words | the integers in the result add up to 7 |
| sublabel-017 | breakdown-ignores-counts-args | `buildSublabel("down", 1, 9, [row("down")])` vs `buildSublabel("down", 9, 9, [row("down")])` | both `"1 down"` |
| sublabel-018 | sublabel-pure | call with a frozen `problems` array of frozen rows | returns normally; the array and rows are unchanged |
