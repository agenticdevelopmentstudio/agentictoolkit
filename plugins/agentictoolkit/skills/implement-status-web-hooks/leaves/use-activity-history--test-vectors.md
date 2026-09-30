<!-- leaf: implement-status-web-hooks/use-activity-history--test-vectors · source: status-web-hooks-use-activity-history.md -->

# useActivityHistory

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vector-001 | hook-signature, return-type, rows-state, no-localStorage | Call `useActivityHistory({ enabled: true, live: [] })` | Returns object with fields `{ rows: [], loadOlder: function, loading: false, exhausted: false, error: false, autoBudgetSpent: false, resetAutoBudget: function }` |
| vector-002 | loading-state, page-size-constant, cursor-from-live-tail | Live window contains one row `{ id: "a", at: "2026-09-24T10:00:00Z", tone: "ok" }`; call `loadOlder()`; server responds with 300 rows after 0.5s | `loading: true` immediately after call; request URL includes `limit=300&before=<timestamp>&beforeId=a`; `loading: false` after response; `rows` contains the 300 new rows |
| vector-003 | merge-strategy-incoming-wins, merge-sorting, merge-identity-preservation | Load page with rows `[{ id: "x", at: "2026-09-24T08:00:00Z" }]`; then load second page with rows `[{ id: "x", at: "2026-09-24T08:00:01Z" }, { id: "y", at: "2026-09-24T07:00:00Z" }]` | Final `rows` contains two entries: `id: "x"` with the newer `at`, and `id: "y"`; both sorted by (at, id); previous rows array is not modified if incoming rows were identical |
| vector-004 | error-state, error-does-not-prevent-retry, error-is-reported | Fetch request times out after 20s; next `loadOlder()` is called | `error: true` is set after timeout; cursor is not advanced; next call retries the same page; `error: false` as soon as the next call starts |
| vector-005 | auto-continue-budget, auto-budget-tracking, auto-budget-reset | Call `loadOlder()` six times without resetting budget, each after the previous page settles with a non-null `nextCursor` | First five calls proceed; sixth call returns immediately without fetch; `autoBudgetSpent: true` as soon as the fifth call starts; after `resetAutoBudget()`, the seventh call proceeds |
| vector-006 | exhausted-state, exhausted-guard, cursor-from-server | Load a page with `nextCursor: null` | `exhausted: true` is set; subsequent calls to `loadOlder()` return immediately without fetching |
| vector-007 | shed-absorption-enabled, shed-absorption-guards, shed-no-progress | Live window `[{ id: "a", at: "2026-09-24T10:00:00Z", tone: "ok" }, { id: "b", at: "2026-09-24T11:00:00Z", tone: "ok" }]`; call `loadOlder()`; live window then updates to `[{ id: "b", at: "2026-09-24T11:00:00Z", tone: "ok" }]` | Shed row `{ id: "a", ... }` is merged into `rows` without a fetch; had row `a` carried `tone: "progress"`, it would not be captured |
| vector-008 | enabled-filtering, epoch-validation, abort-on-unmount | Set `enabled: false` while a fetch is in-flight | History array is cleared to `[]`; in-flight fetch is aborted; any response to the aborted fetch is discarded; state is reset to defaults |
| vector-009 | loadOlder-stable-identity | Capture the `loadOlder` reference; re-render the hook with a new `live` prop; capture it again | Both references are the same object |
| vector-010 | request-headers, response-type | Call `loadOlder()`; server responds with `{ rows: [...], nextCursor: { atMs: 1234567890, id: "next" } }` | Request header includes `accept: application/json`; `rows` state is updated; `cursorRef` is set to the returned cursor |
