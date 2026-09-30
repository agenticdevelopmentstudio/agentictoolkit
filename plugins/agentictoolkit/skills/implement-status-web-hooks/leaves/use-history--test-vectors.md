<!-- leaf: implement-status-web-hooks/use-history--test-vectors · source: status-web-hooks-use-history.md -->

# useHistory

## Conformance Test Vectors

No test file exists beside `use-history.ts`; these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's other `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-history-001 | disabled-without-slug, query-key | `useHistory(null)` | No `fetch` call is made; the result's `status` is `"pending"` with `fetchStatus` `"idle"`; `data` is `undefined` |
| use-history-002 | disabled-without-slug | `useHistory("")` | No `fetch` call is made |
| use-history-003 | enabled-with-slug, request-path, fixed-window, request-init, client-source | `useHistory("api")` with the default client; stub returns `200` and `{"service":"api","hours":24,"checks":[]}` | Exactly one `fetch` to `/api/history?service=api&hours=24` with no init argument; `data` deep-equals the body |
| use-history-004 | slug-encoding | `useHistory("a b/c&d")` | The requested path is `/api/history?service=a%20b%2Fc%26d&hours=24` |
| use-history-005 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useHistory("web")` | The requested URL is `/proxy/history?service=web&hours=24` |
| use-history-006 | non-ok-error, error-detail-dropped | `useHistory("api")`; stub returns `503` with body `{"error":"down for maintenance"}` | `isError` is true; `error.message` is exactly `history 503`; the body text does not appear in the message |
| use-history-007 | parse-failure | `useHistory("api")`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-history-008 | network-failure | `useHistory("api")`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-history-009 | query-key | Render `useHistory("a")`, then rerender with `useHistory("b")` | Two fetches, one per slug; returning to `"a"` within the cache's lifetime serves the cached `"a"` data |
| use-history-010 | raw-fetch-not-json-helper | `useHistory("api")`; inspect the request | No `Content-Type` header is added by the hook |
