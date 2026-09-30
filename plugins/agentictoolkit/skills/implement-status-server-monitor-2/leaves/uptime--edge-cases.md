<!-- leaf: implement-status-server-monitor-2/uptime--edge-cases · source: status-server-monitor-uptime.md -->

# Status Server Monitor Uptime

**Rules** (cite as `implement-status-server-monitor-2/uptime--edge-cases#<slug>`):

- `null-and-empty-input` MUST — overallUptimePercent([]) MUST return null (overall-uptime-no-data). A Counts object with every field 0 MUST return null …
- `boundary-values` MUST — the > 0.5 comparison in dayStatus is strict, so a down-ratio of EXACTLY 0.5 (for example { total: 10, healthy: 0, …
- `concurrent-access` MUST — none of the three functions read or write module-scope state, so concurrent or repeated calls — from multiple requests …
- `error-states` SHOULD — none of the three functions can throw, reject, or return an error value for any input conforming to their declared …

## Edge Cases

- **Null and empty input**: `overallUptimePercent([])` MUST return `null` (overall-uptime-no-data). A `Counts` object with every field `0` MUST return `null` from `uptimePercent` (uptime-percent-no-data) and `"healthy"` from `dayStatus` (day-status-no-zero-total-guard) — the SAME input yields two different-looking answers depending on which function is called — MUST.
- **Boundary values**: the `> 0.5` comparison in `dayStatus` is strict, so a down-ratio of EXACTLY `0.5` (for example `{ total: 10, healthy: 0, degraded: 5, down: 5 }`) MUST return `"degraded"`, not `"down"` — MUST. `uptimePercent`'s rounding can land on a repeating fraction (vector 003, `2/3`); the source's `Math.round(x * 10000) / 100` always resolves such a value to a definite two-decimal-place number rather than leaving extra precision — MUST.
- **Concurrent access**: none of the three functions read or write module-scope state, so concurrent or repeated calls — from multiple requests handled by the same `status-server` process, or from the separate `status-web` copy running in a different browser tab entirely — can never interleave in a way that corrupts a result; each call is isolated to its own arguments (pure-computation, concurrency-safety) — MUST.
- **Error states**: none of the three functions can throw, reject, or return an error value for any input conforming to their declared TypeScript signatures — there is no `throw`, `try`/`catch`, or rejected `Promise` anywhere in the source. A runtime caller that passes a `Counts` or `services` argument NOT conforming to the declared type (for example a missing field evaluating to `undefined`) is not guarded against at runtime; ordinary arithmetic on `undefined` produces `NaN`, which propagates through `Math.round`/`Number` operations rather than throwing — this is a SHOULD-level caller precondition enforced only by TypeScript's compile-time type signature (`total: number; healthy: number; degraded: number; down: number`), not a runtime validation this file performs; the only in-repo caller (`buildUptime` in `../routes/reads.ts`) always builds `Counts` from a `reduce` over already-numeric database rows, so the malformed-shape case does not occur in the traced call path.
- **Offline / disconnected state**: not applicable — this module makes no network call and no database call of any kind, per its own header comment "No DB/IO"; nothing in it can be affected by a lost connection.
