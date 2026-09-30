<!-- leaf: implement-status-web-hooks/use-integrations--test-vectors · source: status-web-hooks-use-integrations.md -->

# useIntegrations

## Conformance Test Vectors

There is no test file beside `use-integrations.ts`. The `Dashboard` and `OverviewTab` DOM tests mock the module out with `{ data: undefined, isLoading: false }`, so the vectors below come from the source. Wrap the hook in a `QueryClientProvider` whose client sets `retry: false` (the convention in the package's `*.dom.test.tsx` files), plus a `StatusApiProvider` with a stubbed `fetch`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-integrations-001 | always-enabled, request-path, request-init, client-source | Render `useIntegrations()` with the default client; the stub returns `200` and `{"generatedAt":"2026-09-24T00:00:00Z","overall":"ok","checks":[]}` | Exactly one `fetch`, to `/api/integrations`, with no init argument; `data` deep-equals the body |
| use-integrations-002 | client-source, request-path | Mount `StatusApiProvider basePath="/proxy"` and render `useIntegrations()` | The requested URL is `/proxy/integrations` |
| use-integrations-003 | non-ok-error, error-detail-dropped | The stub returns `502` with body `{"error":"upstream down"}` | `isError` is true; `error.message` is exactly `status 502`; the body text is not in the message |
| use-integrations-004 | parse-failure | The stub returns `200` with body `not json` | `isError` is true; `error` is the JSON parse error thrown by `response.json()` |
| use-integrations-005 | network-failure | The stub rejects with `TypeError("Failed to fetch")` | `isError` is true; `error` is that same `TypeError` |
| use-integrations-006 | query-key, single-threaded-ordering | Render two components that each call `useIntegrations()` under one `QueryClient` | One `fetch` in total; both results have the same `data` |
| use-integrations-007 | refetch-on-focus | After a successful fetch with `staleTime` 0, dispatch a window `focus` / `visibilitychange` through React Query's `focusManager` | A second `fetch` to `/api/integrations` is made |
| use-integrations-008 | shared-interval-refresh | Mount `useIntegrations()` alongside `useRefreshAll(1000)` with fake timers; advance 1000 ms | A second `fetch` to `/api/integrations` is made |
| use-integrations-009 | raw-fetch-not-json-helper | Inspect the request | The hook adds no `Content-Type` header |
| use-integrations-010 | integration-check-optional-fields, success-body | The stub returns a check carrying `"missingEnv":["CLOUDFLARE_ACCOUNT_ID"],"unreachable":true,"correlated":true` | `data.checks[0]` keeps all three fields exactly as sent |
