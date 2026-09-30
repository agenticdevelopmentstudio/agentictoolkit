<!-- leaf: implement-status-server-monitor-1/health--edge-cases · source: status-server-monitor-health.md -->

# Status Server Monitor Health

**Rules** (cite as `implement-status-server-monitor-1/health--edge-cases#<slug>`):

- `null-and-empty-input` MUST — bodyText: undefined and bodyText: "" MUST both be treated as "no body to check" — isHealthKind && bodyText is falsy for …
- `boundary-values` MUST — responseTimeMs exactly equal to DEGRADED_THRESHOLD_MS (2000) MUST classify as "healthy", and 2001 MUST classify as …
- `concurrent-access` MUST — classify is a synchronous, pure computation over its single input argument with no shared mutable state and no await of …
- `error-states` MUST — this file has no dependency of its own — no network call, no database access, no file I/O — so its only possible thrown …

## Edge Cases

- **Null and empty input**: `bodyText: undefined` and `bodyText: ""` MUST both be treated as "no body to check" — `isHealthKind && bodyText` is falsy for either, so the JSON parse is skipped and evaluation proceeds to the `bodyMarkerMissing`/latency check (health-kind-check-skipped-without-body-text) — MUST. `isHealthKind: undefined` and `bodyMarkerMissing: undefined` MUST both be treated as `false` by the `&&`/`if` checks that read them, so an endpoint that never sets these optional fields gets the plain success/latency classification — MUST. `statusCode`, `responseTimeMs`, and `expectedStatus` are declared as required `number` fields on `ClassifyInput`; nothing inside `classify` validates that a caller actually supplied a finite number for any of them at runtime — this is a caller precondition enforced by the type signature, not unvalidated input the function's purpose calls for validating, since `classify` has exactly one caller in this codebase (`probe()` in `probe.ts`, external), which always supplies `res.status` and a computed millisecond duration.
- **Boundary values**: `responseTimeMs` exactly equal to `DEGRADED_THRESHOLD_MS` (`2000`) MUST classify as `"healthy"`, and `2001` MUST classify as `"degraded"` (degraded-latency-threshold, status-server-monitor-health-012) — MUST. `statusCode` at `199` MUST NOT be treated as a 2xx response, `200` and `299` MUST both be treated as 2xx, and `300` MUST NOT be treated as 2xx (success-status-range) — MUST.
- **Concurrent access**: `classify` is a synchronous, pure computation over its single `input` argument with no shared mutable state and no `await` of its own, so any number of concurrent callers MUST NOT interleave in a way that changes any single call's result — MUST.
- **Error states**: this file has no dependency of its own — no network call, no database access, no file I/O — so its only possible thrown error is `JSON.parse(bodyText)` inside the health-kind check; that throw MUST be caught and MUST NOT propagate out of `classify`, per health-kind-json-parse-failure-falls-through — MUST. `classify` never returns a value other than one of the three `HealthStatus` literals; there is no error return value or thrown error visible to a caller under any input this file's own logic can produce.
- **Offline / disconnected state**: not applicable — `classify` makes no network connection of its own to lose; it consumes the outcome of a fetch that its caller (`probe()`, external to this file) already completed or failed before calling `classify`.
