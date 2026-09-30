<!-- leaf: implement-status-server-monitor-1/overall--edge-cases · source: status-server-monitor-overall.md -->

# Status Server Monitor Overall

**Rules** (cite as `implement-status-server-monitor-1/overall--edge-cases#<slug>`):

- `null-and-empty-input` MUST — an empty statuses array MUST yield "unknown" from computeOverall, and from publicOverall regardless of …
- `boundary-values` MUST — a single-element statuses array is the minimum non-empty boundary; ["down"] MUST return "major_outage" from …
- `concurrent-access` MUST — computeOverall and publicOverall are synchronous, pure computations over their own arguments, with no shared mutable …
- `error-states` MUST — neither function contains a try/catch, a throw, or a dependency of its own — no network call, no database access, no …

## Edge Cases

- **Null and empty input**: an empty `statuses` array MUST yield `"unknown"` from `computeOverall`, and from `publicOverall` regardless of `hasNonEndpointProblem` (empty-statuses-is-unknown, public-overall-base, non-endpoint-problem-never-lifts-unknown; status-server-monitor-overall-001, -011) — MUST. `statuses` is typed as `HealthStatus[]`, so there is no `null`/`undefined`-element case at the type level; `hasNonEndpointProblem` is a required `boolean` with no default, and the source performs no runtime check that a caller actually supplied a `boolean` — this is a caller precondition enforced by the type signature, not unvalidated input this function's purpose calls for validating, since `publicOverall` has exactly one caller in this codebase (`buildSnapshot` in `routes/reads.ts`, external), which always supplies a computed `boolean` — MUST.
- **Boundary values**: a single-element `statuses` array is the minimum non-empty boundary; `["down"]` MUST return `"major_outage"` from `computeOverall` (`.every()` over one element is trivially satisfied by all-down-is-major-outage), and `["degraded"]` or `["healthy"]` MUST return `"degraded"` or `"operational"` respectively (any-down-or-degraded-is-degraded, all-healthy-is-operational) — MUST. There is no declared maximum length on `statuses`; the source imposes no upper-bound check, and both `.every()` and `.some()` are evaluated over the full array regardless of length — MUST (no length ceiling exists to violate).
- **Concurrent access**: `computeOverall` and `publicOverall` are synchronous, pure computations over their own arguments, with no shared mutable state, no module-level variable, and no `await` of their own; any number of concurrent callers MUST NOT interleave in a way that changes any single call's result (pure-synchronous-functions) — MUST.
- **Error states**: neither function contains a `try`/`catch`, a `throw`, or a dependency of its own — no network call, no database access, no file I/O — so there is no error path in this file for either function to raise or swallow; under any input satisfying the declared `HealthStatus[]`/`boolean` parameter types, neither function MUST throw — MUST.
- **Offline or disconnected state**: not applicable — `computeOverall` and `publicOverall` make no network connection of their own to lose; they consume already-computed `HealthStatus` values and a boolean flag that a caller external to this file (`buildSnapshot` in `routes/reads.ts`) derives from network- and database-backed state before calling either function.
