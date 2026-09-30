<!-- leaf: implement-status-web-hooks/use-uptime--test-vectors · source: status-web-hooks-use-uptime.md -->

# useUptime

## Conformance Test Vectors

No test file exists beside `use-uptime.ts`; the package's `Dashboard.dom.test.tsx` and `OverviewTab.dom.test.tsx` mock the hook out entirely (returning `{ data: undefined, isLoading: false }`), so these vectors are derived from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's `*.dom.test.tsx` files) and a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-uptime-001 | days-default, always-enabled, request-path, request-init, client-source | `useUptime()` with the default client; stub returns `200` and `{"services":[],"days":90}` | Exactly one `fetch` to `/api/uptime?days=90` with no init argument |
| use-uptime-002 | success-body, uptime-response-shape, uptime-service-shape, uptime-day-shape, pass-through | `useUptime(90)`; stub returns `200` and `{"services":[{"slug":"b","name":"B","uptimePercent":null,"totalChecks":0,"daily":[]},{"slug":"a","name":"A","uptimePercent":99.5,"totalChecks":200,"daily":[{"day":"2026-09-23","status":"degraded","uptimePercent":99}]}],"days":90}` | `data` deep-equals the body; service `b` stays first and its `null` percentage is unchanged |
| use-uptime-003 | client-source, request-path | `StatusApiProvider basePath="/proxy"`, `useUptime(30)` | The requested URL is `/proxy/uptime?days=30` |
| use-uptime-004 | days-interpolation | `useUptime(1.5)` | The requested path is `/api/uptime?days=1.5` |
| use-uptime-005 | non-ok-error, error-detail-dropped | `useUptime(90)`; stub returns `401` with body `{"error":"unauthorized"}` | `isError` is true; `error.message` is exactly `uptime 401`; the body text does not appear in the message |
| use-uptime-006 | parse-failure | `useUptime(90)`; stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-uptime-007 | network-failure | `useUptime(90)`; stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-uptime-008 | no-polling | `useUptime(90)` with fake timers; first fetch succeeds; window keeps focus | Advancing time by 600,000 ms triggers no second `fetch` |
| use-uptime-009 | query-key | Render `useUptime(90)`, then rerender with `useUptime(30)` | Two fetches, one per window; returning to `90` within the cache's lifetime serves the cached 90-day data |
| use-uptime-010 | raw-fetch-not-json-helper | `useUptime(90)`; inspect the request | No `Content-Type` header is added by the hook |
| use-uptime-011 | single-threaded-ordering | Two components both call `useUptime(90)` under one `QueryClient` | One `fetch` is made; both receive the same `data` |
| use-uptime-012 | return-value | `useUptime(90)` before the stub resolves | The result has `isLoading` true and `data` undefined, and exposes no keys beyond React Query's own |
