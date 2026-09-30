<!-- leaf: implement-status-web-src-lib-1/health--edge-cases · source: status-web-src-lib-health.md -->

# Health Classification (status-web)

**Rules** (cite as `implement-status-web-src-lib-1/health--edge-cases#<slug>`):

- `status-code-just-outside-2xx` MUST — statusCode 199 or 300 with a different expectedStatus MUST return "down". 200 and 299 MUST be success candidates.
- `expectedstatus-inside-2xx` MUST — When expectedStatus is 204 and the response is 200, the response MUST still be a success candidate, because any 2xx …
- `latency-at-the-threshold` MUST — responseTimeMs of exactly 2 000 MUST return "healthy". 2 001 MUST return "degraded".
- `empty-or-missing-bodytext-on-a-health-kind-endpoint` MUST — The body check MUST be skipped, and the verdict falls to the marker and latency checks.
- `malformed-json-body` MUST — The JSON.parse exception MUST be caught and discarded, and classification continues. This is the documented …
- `json-null-array-string-or-number-body` MUST — The body check MUST be skipped, because only a non-null object with a status key is judged.
- `non-string-status-value` MUST — status is stringified before comparison, so {"status": null} ("null"), {"status": true} ("true") and {"status": 1} MUST …
- `marker-flag-on-a-non-success-response` MUST — When the status gate fails, bodyMarkerMissing MUST have no effect, and the result is "down" either way.
- `non-finite-or-negative-responsetimems` MUST — NaN and negative values MUST return "healthy" for a success candidate, because only a strict greater-than comparison …

## Edge Cases

- **Status code just outside 2xx**: `statusCode` 199 or 300 with a different `expectedStatus` MUST return `"down"`. 200 and 299 MUST be success candidates.
- **`expectedStatus` inside 2xx**: When `expectedStatus` is 204 and the response is 200, the response MUST still be a success candidate, because any 2xx passes the gate. `expectedStatus` only widens the gate. It never narrows it.
- **Latency at the threshold**: `responseTimeMs` of exactly 2 000 MUST return `"healthy"`. 2 001 MUST return `"degraded"`.
- **Empty or missing `bodyText` on a health-kind endpoint**: The body check MUST be skipped, and the verdict falls to the marker and latency checks.
- **Malformed JSON body**: The `JSON.parse` exception MUST be caught and discarded, and classification continues. This is the documented fall-through, not a lost error. The caller still receives a verdict.
- **JSON `null`, array, string or number body**: The body check MUST be skipped, because only a non-null object with a `status` key is judged.
- **Non-string `status` value**: `status` is stringified before comparison, so `{"status": null}` (`"null"`), `{"status": true}` (`"true"`) and `{"status": 1}` MUST all return `"down"`.
- **Marker flag on a non-success response**: When the status gate fails, `bodyMarkerMissing` MUST have no effect, and the result is `"down"` either way.
- **Non-finite or negative `responseTimeMs`**: `NaN` and negative values MUST return `"healthy"` for a success candidate, because only a strict greater-than comparison against 2 000 is made. `Infinity` MUST return `"degraded"`. The only production caller (status-server's probe) computes the value from wall-clock differences, which keeps it finite and non-negative.
- **Timeout**: `classify` has no timeout and performs no waiting. A timed-out probe never reaches `classify`. The status-server probe enforces `HEALTH_CHECK_TIMEOUT_MS` and reports the timeout on its own `catch` path.
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Network errors and offline**: Not applicable. The module performs no I/O. The caller receives the response and measures latency before it calls `classify`.
- **Copy drift**: If `status-server/src/monitor/health.ts` gains a fourth status and this copy does not, the dashboard's `HealthStatus` would not describe server values. No test catches this (see server-copy-identity).
