<!-- leaf: implement-status-web-hooks/use-response-history--test-vectors · source: status-web-hooks-use-response-history.md -->

# useResponseHistory

## Conformance Test Vectors

No test file exists beside `use-response-history.ts`; these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's other `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-response-history-001 | always-enabled, request-path, request-init, client-source, no-buckets-parameter | `useResponseHistory(24)` with the default client; stub returns `200` and `{"hours":24,"points":[120,null,95]}` | Exactly one `fetch` to `/api/response-history?hours=24` with no init argument and no `buckets` parameter |
| use-response-history-002 | success-body, points-semantics, response-history-shape | Same as 001 | `data` deep-equals `{"hours":24,"points":[120,null,95]}`; the `null` stays in position 1 |
| use-response-history-003 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useResponseHistory(168)` | The requested URL is `/proxy/response-history?hours=168` |
| use-response-history-004 | hours-interpolation | `useResponseHistory(1.5)` | The requested path is `/api/response-history?hours=1.5` |
| use-response-history-005 | non-ok-error, error-detail-dropped | `useResponseHistory(24)`; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `response-history 401`; the body text does not appear in the message |
| use-response-history-006 | parse-failure | `useResponseHistory(24)`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-response-history-007 | network-failure | `useResponseHistory(24)`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-response-history-008 | polling-interval | `useResponseHistory(24)` with fake timers; first fetch succeeds | Advancing time by 60,000 ms triggers a second `fetch` to the same URL; advancing less than 60,000 ms does not |
| use-response-history-009 | query-key | Render `useResponseHistory(24)`, then rerender with `useResponseHistory(720)` | Two fetches, one per window; returning to `24` within the cache's lifetime serves the cached 24-hour data |
| use-response-history-010 | raw-fetch-not-json-helper | `useResponseHistory(24)`; inspect the request | No `Content-Type` header is added by the hook |
| use-response-history-011 | single-threaded-ordering | Two components both call `useResponseHistory(24)` under one `QueryClient` | One `fetch` is made; both receive the same `data` |
