<!-- leaf: implement-status-web-hooks/use-status-user--test-vectors · source: status-web-hooks-use-status-user.md -->

# useStatusUser

## Conformance Test Vectors

`src/header-auth.test.ts` tests `fetchStatusUser`, the shared query function, with an injected `fetch`. Vectors 001 to 004 come from its assertions. The remaining vectors are derived from the source and assume a test `QueryClient` and an injected `StatusApiClient`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| use-status-user-001 | ok-user-response, status-user-shape | `/auth/me` responds 200 `{ user: { email: "a@b.c", displayName: "A", role: "admin" } }` | Resolves to exactly that user object (test: "resolves the user from a definitive 200") |
| use-status-user-002 | ok-null-response | `/auth/me` responds 200 `{ user: null }` | Resolves to `null` (test: "resolves null from a definitive signed-out 200") |
| use-status-user-003 | non-ok-throws | `/auth/me` responds 500 `{}` | Query function rejects with an error matching `HTTP 500`; the result is not `null` (test: "THROWS on a 5xx") |
| use-status-user-004 | network-error-propagates | `fetch` rejects with `TypeError("fetch failed")` | Query function rejects with an error matching `fetch failed` (test: "propagates a network failure") |
| use-status-user-005 | session-request, api-client-injection | Default client (base `/api`); render the hook | Exactly one `GET` to `/api/auth/me` with no body |
| use-status-user-006 | user-projection, null-when-unknown | Render the hook while the first request is still pending | Returns `null`; the return value has no `isPending` property |
| use-status-user-007 | keep-last-known-session | Cache holds user U; invalidate the key and make every retry answer 503 | Hook keeps returning U through all 4 attempts and after the query enters its error state |
| use-status-user-008 | retry-count, null-when-unknown, no-error-exposure | Empty cache; every `/auth/me` call answers 502 | 4 requests in total; hook then returns `null` with no error exposed |
| use-status-user-009 | shared-cache-key, single-query-owner | Mount this hook and `useStatusHeaderAuth` together with an empty cache | One request; both read the same user from key `["status-auth-me"]` |
| use-status-user-010 | stale-time | Session loaded at t=0; mount a second consumer at t=30,000 ms, then a third at t=61,000 ms | No request at 30,000 ms; one background refetch at 61,000 ms |
| use-status-user-011 | ok-null-response | `/auth/me` responds 200 `{}` | Resolves to `null` |
| use-status-user-012 | query-provider-precondition | Render the hook with no `QueryClientProvider` | Render throws the query library's missing-client error |
| use-status-user-013 | body-not-validated | 200 `{ user: { email: "x@y.z", role: "superuser" } }` | Returns the object as sent, with `role` `"superuser"`; no error |
