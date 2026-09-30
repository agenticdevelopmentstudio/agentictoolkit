<!-- leaf: implement-status-web-hooks/use-refresh-all--test-vectors · source: status-web-hooks-use-refresh-all.md -->

# useRefreshAll

## Conformance Test Vectors

The source has no test file for this hook (no `use-refresh-all.*test*` exists next to it). These vectors come from `hooks/use-refresh-all.ts` and are meant for a test that renders the hook under a `QueryClientProvider` with fake timers.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| refresh-all-001 | interval-default, interval-start, no-immediate-refresh | Render `useRefreshAll()` with a spied `refetchQueries`; advance fake timers by 59,999 ms, then by 1 ms | Zero calls after 59,999 ms; exactly one call at 60,000 ms |
| refresh-all-002 | interval-start | Render `useRefreshAll(1_000)`; advance timers by 3,000 ms | `refetchQueries` called exactly 3 times |
| refresh-all-003 | live-excluded, others-included | Cache holds enabled, fetched queries `["live"]`, `["live", "x"]`, `["uptime"]` and `["integrations"]`; call `refreshAll()` | `["uptime"]` and `["integrations"]` query functions each run once; neither `["live"]` query function runs |
| refresh-all-004 | live-prefix-only | Cache holds enabled queries `["live-history"]` and `["history", "live"]`; call `refreshAll()` | Both query functions run once |
| refresh-all-005 | disabled-excluded | Cache holds `["config-status"]` whose only observer has `enabled: false`; call `refreshAll()` | Its query function does not run |
| refresh-all-006 | disabled-means-no-enabled-observer | `["configure-data"]` has one observer with `enabled: false` and one with `enabled: true`; call `refreshAll()` | Its query function runs once |
| refresh-all-007 | fire-and-forget, errors-land-on-queries | `["uptime"]` query function rejects with `Error("boom")`; call `refreshAll()` | `refreshAll()` returns `undefined` synchronously; after settling, the `["uptime"]` query state has `status: "error"` and `error.message === "boom"`; no unhandled rejection |
| refresh-all-008 | independent-completion | `["a"]` resolves `1`, `["b"]` rejects; call `refreshAll()` | Query `["a"]` data becomes `1` even though `["b"]` ends in `status: "error"` |
| refresh-all-009 | interval-cleanup | Render `useRefreshAll(1_000)`, unmount, advance timers by 5,000 ms | `refetchQueries` called zero times after unmount |
| refresh-all-010 | interval-restart-on-change | Render with `intervalMs = 1_000`; advance 500 ms; rerender with `intervalMs = 2_000`; advance 1,999 ms, then 1 ms | No call before the rerender and none during the 1,999 ms; exactly one call at 2,000 ms after the rerender |
| refresh-all-011 | refresh-all-stable, return-object-fresh | Rerender twice with the same `QueryClient` | `result.refreshAll` is the same reference each time; the wrapper objects are different references |
| refresh-all-012 | refetch-call | Call `refreshAll()` once | `refetchQueries` called once with one argument, an object whose only key is `predicate` |
| refresh-all-013 | one-timer-per-mount | Render two instances of `useRefreshAll(1_000)` under one `QueryClient`; advance 1,000 ms | `refetchQueries` called twice |
