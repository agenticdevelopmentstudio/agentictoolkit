<!-- leaf: implement-status-web-src-lib-1/health--test-vectors · source: status-web-src-lib-health.md -->

# Health Classification (status-web)

## Conformance Test Vectors

Vectors 001 to 018 are traced to the assertions in `health.test.ts`. Vectors 019 to 026 are traced to the `classify` body (the `is2xx` gate, the `isHealthKind && bodyText` guard, the `toLowerCase()` comparison, and the strict `>` comparison). Rows that omit `expectedStatus` use `expectedStatus: 200`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| health-001 | timeout-constant, degraded-threshold-constant | Read `HEALTH_CHECK_TIMEOUT_MS` and `DEGRADED_THRESHOLD_MS` | 10 000 and 2 000 |
| health-002 | success-gate, latency-healthy | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200` | `"healthy"` |
| health-003 | latency-degraded | `statusCode: 200, responseTimeMs: 2001, expectedStatus: 200` | `"degraded"` |
| health-004 | non-success-down | `statusCode: 500, responseTimeMs: 50, expectedStatus: 200` | `"down"` |
| health-005 | success-gate | `statusCode: 403, responseTimeMs: 50, expectedStatus: 403` | `"healthy"` |
| health-006 | health-body-not-ok-down | `statusCode: 200, responseTimeMs: 50, expectedStatus: 200, isHealthKind: true, bodyText: {"status":"degraded"}` | `"down"` |
| health-007 | health-body-gate, latency-healthy | Same as 006 with `bodyText: {"status":"ok"}` | `"healthy"` |
| health-008 | check-order, latency-degraded | `statusCode: 200, responseTimeMs: 2001, isHealthKind: true, bodyText: {"status":"ok"}` | `"degraded"` |
| health-009 | health-body-only-status-key | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"down","ok":false}` | `"down"` |
| health-010 | health-body-fallthrough-unparseable | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: <html><body>OK</body></html>` | `"healthy"` |
| health-011 | health-body-fallthrough-unknown-shape | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"result":"ok"}` | `"healthy"` |
| health-012 | success-gate, latency-degraded | `statusCode: 403, responseTimeMs: 2001, expectedStatus: 403` | `"degraded"` |
| health-013 | marker-missing-down | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200, bodyMarkerMissing: true` | `"down"` |
| health-014 | marker-absent-neutral, latency-healthy | Same as 013 with `bodyMarkerMissing: false` | `"healthy"` |
| health-015 | marker-absent-neutral, latency-degraded | `statusCode: 200, responseTimeMs: 5000, bodyMarkerMissing: false` | `"degraded"` |
| health-016 | marker-missing-down | `statusCode: 401, expectedStatus: 401, responseTimeMs: 100, bodyMarkerMissing: true` | `"down"` |
| health-017 | marker-absent-neutral | `statusCode: 401, expectedStatus: 401, responseTimeMs: 100, bodyMarkerMissing: false` | `"healthy"` |
| health-018 | marker-absent-neutral | `statusCode: 200, responseTimeMs: 100, expectedStatus: 200` (no marker field) | `"healthy"` |
| health-019 | latency-healthy | `statusCode: 200, responseTimeMs: 2000, expectedStatus: 200` | `"healthy"` (the threshold itself is not degraded) |
| health-020 | health-body-gate | `statusCode: 403, expectedStatus: 403, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"down"}` | `"healthy"` (the body is not inspected for a non-2xx match) |
| health-021 | health-body-gate | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: ""` | `"healthy"` (an empty body skips the check) |
| health-022 | health-body-ok-case-insensitive | `statusCode: 200, responseTimeMs: 50, isHealthKind: true, bodyText: {"status":"OK"}` | `"healthy"` |
| health-023 | health-body-gate | `statusCode: 200, responseTimeMs: 50, isHealthKind: false, bodyText: {"status":"down"}` | `"healthy"` |
| health-024 | check-order, marker-missing-down | `statusCode: 200, responseTimeMs: 5000, bodyMarkerMissing: true` | `"down"` (not `"degraded"`) |
| health-025 | non-success-down, check-order | `statusCode: 301, expectedStatus: 200, responseTimeMs: 50, bodyMarkerMissing: false` | `"down"` |
| health-026 | no-input-validation | `statusCode: 200, responseTimeMs: NaN, expectedStatus: 200` | `"healthy"` |
