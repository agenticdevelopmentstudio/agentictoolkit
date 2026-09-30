<!-- leaf: implement-status-web/telemetry-sources--test-vectors · source: status-web-telemetry-sources.md -->

# Status Web Telemetry Sources

## Conformance Test Vectors

Traced to `sources/live.ts` and `sources/turso.ts`; no test file exercises either source directly (the only telemetry test, `stores/local-cache.test.ts`, covers the cache).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| sources-001 | live-endpoint, api-injection, get-only-requests | `liveSource.get(api)` with a fake `api.fetch` recording calls | Exactly one call: `api.fetch("/telemetry")` with no second argument |
| sources-002 | live-passthrough | `/telemetry` returns 200 with body `{"generatedAt":"2026-09-24T00:00:00Z","errors":[],"analytics":[]}` | Resolves to that object, `generatedAt` equal to `"2026-09-24T00:00:00Z"` |
| sources-003 | live-status-check, error-propagation | `/telemetry` returns 503 | Rejects with `Error` message `telemetry 503`; body not read |
| sources-004 | network-rejection | `api.fetch` rejects with `TypeError("Failed to fetch")` | `liveSource.get` rejects with that same `TypeError` |
| sources-005 | json-parse-rejection | `/telemetry` returns 200 with body `not json` | Rejects with the `SyntaxError` thrown by `Response.json()` |
| sources-006 | turso-endpoints, turso-parallel | `tursoSource.get(api)` with a fake `api.fetch` whose promises stay pending | Both `api.fetch("/errors")` and `api.fetch("/analytics")` are called before either resolves |
| sources-007 | turso-errors-projection, turso-analytics-projection, turso-snapshot-keys | `/errors` 200 `{"errors":[E],"extra":1}`; `/analytics` 200 `{"metrics":[M]}` | Resolves to `{ generatedAt, errors: [E], analytics: [M] }` with no `extra` or `metrics` key |
| sources-008 | turso-generated-at | Clock fixed at `2026-09-24T12:00:00.000Z`; both endpoints 200 | `generatedAt === "2026-09-24T12:00:00.000Z"` |
| sources-009 | turso-errors-status | `/errors` 500, `/analytics` 200 | Rejects with `Error` message `errors 500` |
| sources-010 | turso-analytics-status | `/errors` 200, `/analytics` 404 | Rejects with `Error` message `analytics 404` |
| sources-011 | turso-status-precedence | `/errors` 502, `/analytics` 503 | Rejects with `Error` message `errors 502` |
| sources-012 | turso-network-rejection-order | `/analytics` fetch rejects with `TypeError`; `/errors` still pending | Rejects with that `TypeError`; no status message produced |
| sources-013 | turso-body-order | `/errors` 200 but invalid JSON body, `/analytics` 200 with valid body | Rejects with the `SyntaxError` from the `/errors` body; `/analytics` body not parsed |
| sources-014 | stateless | Call `liveSource.get(api)` twice | Two separate `/telemetry` requests; two distinct result objects |
| sources-015 | no-retry | `/telemetry` returns 500 once | Exactly one request made; rejects `telemetry 500` |
| sources-016 | default-source, interchangeable | Import `source` from `telemetry/client.ts` | `source === liveSource` |
