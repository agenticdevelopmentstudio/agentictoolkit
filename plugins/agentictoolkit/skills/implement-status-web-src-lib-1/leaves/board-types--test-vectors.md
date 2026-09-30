<!-- leaf: implement-status-web-src-lib-1/board-types--test-vectors · source: status-web-src-lib-board-types.md -->

# Board Wire Types

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| board-types-001 | server-parity | Compile `Exact<server.Board, web.Board>` (and the same for `Problem`, `ActivityRow`, `ActivityTone`, `ActivityKind`, `Indicator`, `ActivityCursor`, `ActivityPage`) where `Exact<A, B>` is true only under mutual assignability | Every check resolves to `true` and the file typechecks; renaming a field, widening a nullability or adding a union member on one side makes it fail to compile |
| board-types-002 | indicator-members | Keys of the client's `INDICATOR_STATE` map, sorted | Exactly `["degraded", "operational", "outage"]` |
| board-types-003 | problem-fields, issue-source-reuse | A `Problem` literal with `target: "vercel\|example"`, `source: "vercel"`, `name: "example"`, `severity: "minor"`, `state: "failed"`, `since: "2026-06-30T00:00:00.000Z"` and every nullable field `null` | Typechecks; omitting any field, or setting `source: "cloudflare"`, fails to typecheck |
| board-types-004 | indicator-members, problem-fields | Empty `Problem[]` passed to the client's `indicatorFromProblems` and to the server's `indicatorFor` | Client result equals `{ state: INDICATOR_STATE[indicatorFor([])], count: 0 }` |
| board-types-005 | problem-fields | `[minor, minor]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 2 }` |
| board-types-006 | problem-fields | `[major, minor]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 2 }` |
| board-types-007 | problem-fields | `[minor, major, critical]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 3 }` |
| board-types-008 | activity-kind-members, activity-tone-members | Assign `"deploy"`, `"probe"`, `"platform"` to `ActivityKind`; assign `"good"`, `"bad"`, `"progress"`, `"neutral"`, `"stale"` to `ActivityTone` | All typecheck; `"issue"` as `ActivityKind` or `"warning"` as `ActivityTone` fails |
| board-types-009 | activity-row-id-deploy-format, activity-row-step | Deployment `abc` that reached the deploy step | Two rows with ids `deploy:abc:build` (`step: "build"`) and `deploy:abc:deploy` (`step: "deploy"`), no target or timestamp in either id |
| board-types-010 | cursor-pair, page-next-cursor | `ActivityPage` with `nextCursor: { atMs: 1719705600000, id: "deploy:abc:build" }`, then one with `nextCursor: null` | Both typecheck; `nextCursor: 1719705600000` (a bare number) fails; the null page means history is exhausted |
| board-types-011 | board-fields, board-data-as-of | `Board` with `dataAsOfMs: null`, empty `problems`, `activity` and `monitoredTargets` | Typechecks; omitting `probeIntervalMs` or `activityFromMs` fails |
| board-types-012 | type-only-module, no-side-effects | Import the module and inspect its runtime exports | No runtime values are exported |
