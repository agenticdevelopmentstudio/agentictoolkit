<!-- leaf: implement-status-server/src--test-vectors · source: status-server-src.md -->

# Status Server

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| vector-001 | health-endpoint | Scheduler has completed a cycle within freshness window; call `GET /health` | Status 200, response `{status: 'ok', lastCycleAt: <ISO string>}`; with no scheduler injected the same 200 carries `lastCycleAt: null` |
| vector-002 | health-endpoint | Scheduler started but has not completed a cycle within the staleness window; call `GET /health` | Status 503, response `{status: 'stale', lastCycleAt: <last completed ISO string, or null if none>}` |
| vector-003 | version-endpoint | Call `GET /version` | Status 200, response `{name: 'status-backend', version: <config.appVersion>}` |
| vector-004 | status-summary-endpoint, status-summary-caching | Call `GET /public/status-summary`, change health data, call again within 30 seconds, then again after 31 seconds | Second response equals the first (same `generatedAt`, old status); third reflects the new state |
| vector-005 | status-summary-endpoint | Call `GET /public/status-summary` with unknown status (all services status unknown); buildStatusSummary creates snapshot with services.length > 0 but all services.status === 'unknown' | Response status is `'unknown'` (not `'healthy'`), `operational: false` |
| vector-006 | public-path-cors, status-summary-endpoint | Call `GET /public/status-summary` with arbitrary `Origin` header | `Access-Control-Allow-Origin` equals the request's `Origin` value |
| vector-007 | authenticated-path-cors | Call `GET /live` with `Origin: https://evil.example.com` not in `config.corsAllowedHosts` | Response has no `Access-Control-Allow-Origin` header |
| vector-008 | body-size-limit | POST a 1,048,577-byte body (1 byte over limit) to the pre-auth `POST /hooks/vercel` | Status 413, response `{error: {message: 'request body too large'}}` |
| vector-009 | scheduler-single-flight | Call `runNow()` with a cycle that stays open, then call `runNow()` again before it settles | Second call resolves false (coalesced); after the cycle settles the first resolves true; the cycle ran once |
| vector-010 | scheduler-watchdog | `intervalMs: 1000`, `cycleTimeoutMs: 5000`; the boot cycle hangs forever, later cycles resolve; advance 4s, then 4s more | After 4s the cycle ran once and `lastCycleAt()` is null; after 8s the watchdog has logged and released the lock, a later tick ran a fresh cycle, and `lastCycleAt()` is non-null |
