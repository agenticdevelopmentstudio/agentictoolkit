<!-- leaf: implement-status-web-hooks/use-status--test-vectors · source: status-web-hooks-use-status.md -->

# useStatus

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-001 | query-key, request-path, success-ok | Default client; `fetch` resolves `200` with body `{ "overall": "operational", "services": [], "checkedAt": "2026-09-24T00:00:00Z" }` | One request to `/api/status`; `data` deep-equals the body; `error` is `null`; the query is cached under `["status"]` |
| use-status-002 | error-body-read, error-detail-message | `fetch` resolves `503` with body `{ "error": "database unavailable" }` | Query fails; `error` is an `Error` whose `message` is exactly `database unavailable` |
| use-status-003 | error-status-fallback | `fetch` resolves `503` with body `{}` | `error.message` is `status 503` |
| use-status-004 | error-status-fallback, error-parse-swallowed | `fetch` resolves `502` with non-JSON body `Bad Gateway` | `error.message` is `status 502`; no JSON syntax error surfaces |
| use-status-005 | error-status-fallback | `fetch` resolves `500` with body `{ "error": "" }` | `error.message` is `status 500` |
| use-status-006 | error-nonstring-detail | `fetch` resolves `500` with body `{ "error": { "message": "x" } }` | `error.message` is `[object Object]` |
| use-status-007 | network-failure | `fetch` rejects with `TypeError("Failed to fetch")` | `error` is that same `TypeError` |
| use-status-008 | success-parse-failure | `fetch` resolves `200` with body `not json` | Query fails with the JSON syntax error thrown by `r.json()`; message does not start with `status ` |
| use-status-009 | client-injection, request-path | `StatusApiProvider` with `basePath="/proxy"`; `fetch` resolves `200` with a valid body | The request URL is `/proxy/status` |
| use-status-010 | shared-cache | Two components call `useStatus()` under one `QueryClient`; `fetch` resolves after a delay | Exactly one request is made; both components receive the same `data` |
| use-status-011 | refetch-on-focus | Query loaded and stale; dispatch a window `focus`/`visibilitychange` event that react-query's focus manager observes | One additional request to `/status` is made |
| use-status-012 | error-message-only | `fetch` resolves `503` with body `{ "error": "db down" }` | `error` has no `status` or `body` property; only `message` is `db down` |
| use-status-013 | result-type | Consumer mock as in `Dashboard.dom.test.tsx`: `{ isLoading: false, error: null, data: { overall: "operational", checkedAt, services: [one healthy service] } }` | `Dashboard` reads `data.services` and `data.checkedAt` from the result without adaptation (the result is the raw `useQuery` object) |
