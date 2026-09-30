<!-- leaf: implement-general-1/auth-client--test-vectors · source: auth-client.md -->

# Auth Client

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-001 | default-runtime-config | `authConfig()` called with no prior `configureAuth` | `{ storageKey: 'auth_tokens', refreshPath: '/api/auth/refresh' }` |
| auth-client-002 | configure-auth-merges | `configureAuth({ storageKey: 'x' })` then `authConfig()` | `refreshPath` unchanged; `storageKey === 'x'` (tokens.test.ts "honors a re-configured key") |
| auth-client-003 | auth-api-base-resolution | `authApiBaseOrEnv('https://x.example.com/')` | `'https://x.example.com'` (trailing slash stripped) |
| auth-client-004 | as-endpoint-proxy-fallback | `asEndpoint('/a', undefined)` with no env var set | `'/api/a'` |
| auth-client-005 | auth-tokens-shape | `{ accessToken: 'a', refreshToken: 'b' }` assigned to `AuthTokens` | Compiles; no other fields required or permitted |
| auth-client-006 | auth-user-shape | An `AuthUser` literal omitting `slug` | Compiles (types.test.ts's `user()` helper omits `slug`) |
| auth-client-007 | has-capability-null-safe | `hasCapability(null, 'billing')` | `false` (types.test.ts) |
| auth-client-008 | is-admin-derived | `isAdmin(user(['user', 'admin']))` | `true` (types.test.ts) |
| auth-client-009 | tokens-from-response-precedence | `tokensFromResponse({ accessToken: 'A', token: 'T' })` | `{ accessToken: 'A', refreshToken: '' }` (tokens.test.ts) |
| auth-client-010 | tokens-from-response-refresh-token-blanked | `tokensFromResponse({ token: 'T', refreshToken: 'server-rt' } as any)` | `refreshToken === ''` |
| auth-client-011 | tokens-from-response-throws-when-absent | `tokensFromResponse({})` | Throws `/missing token/i` (tokens.test.ts) |
| auth-client-012 | token-storage-key-configurable | `configureAuth({ storageKey: 'other_key' })`; `writeTokens(...)` | `localStorage.getItem('other_key')` truthy; `test_tokens` key absent (tokens.test.ts) |
| auth-client-013 | token-read-off-browser-returns-null | `readTokens()` with `window` undefined (SSR) | `null` |
| auth-client-014 | token-read-malformed-json-returns-null | `localStorage.setItem('test_tokens', 'not json')`; `readTokens()` | `null` (tokens.test.ts) |
| auth-client-015 | write-tokens-persists-and-announces | Subscribe via `onSessionChange`; call `writeTokens(...)` | Subscriber invoked exactly once; storage contains the tokens |
| auth-client-016 | clear-tokens-clears-sibling-user-key | `writeUser(u)`; `clearTokens()` | `readUser()` returns `null`; tokens key absent |
| auth-client-017 | read-access-token-derivation | `writeTokens({ accessToken: 'A', refreshToken: '' })`; `readAccessToken()` | `'A'` (tokens.test.ts) |
| auth-client-018 | session-change-subscription | `const unsub = onSessionChange(fn)`; `unsub()`; `writeTokens(...)` | `fn` not called |
| auth-client-019 | session-change-payload-free | `onSessionChange(fn)`; `writeTokens(...)` | `fn` called with zero arguments |
| auth-client-020 | session-change-snapshot-iteration | Listener A unsubscribes listener B from inside A's own callback, both registered before one `writeTokens` call | B is still invoked for that same announcement |
| auth-client-021 | decode-base64url-json-utf8-strict | `decodeBase64UrlJson(b64url(JSON.stringify({ name: '東京' })))` | `{ name: '東京' }` (tokens.test.ts) |
| auth-client-022 | decode-base64url-json-tolerates-missing-padding | Unpadded base64url of `{ sub: 'u', iat: 1 }` | `{ sub: 'u', iat: 1 }` (tokens.test.ts) |
| auth-client-023 | decode-base64url-json-never-throws | `decodeBase64UrlJson(btoa('\xff\xfe'))` | `null`, no throw (tokens.test.ts) |
| auth-client-024 | read-token-subject-derivation | Access token `` `x.${b64url(JSON.stringify({ sub: 'user-1' }))}.y` `` stored | `readTokenSubject() === 'user-1'` (tokens.test.ts) |
| auth-client-025 | read-user-validates-shape | `localStorage` holds `{"name":"x"}` (no `id`/`capabilities`) under the user key | `readUser() === null` |
| auth-client-026 | write-user-persists-off-browser-noop | `writeUser(u)` with `window` undefined | No throw; no storage write |
| auth-client-027 | refresh-single-flight-dedup | `Promise.all([refreshAccessToken(), refreshAccessToken()])`, fetch resolves `{ token: 'NEW' }` | `fetchMock` called exactly once; both results `'NEW'` (refresh.test.ts) |
| auth-client-028 | refresh-request-shape | `refreshAccessToken()` | fetch called with `method: 'POST'`, `credentials: 'include'`, `body: '{}'` (refresh.test.ts) |
| auth-client-029 | invalidate-refresh-bumps-generation | `refreshAccessToken()` in flight; `invalidateRefresh()` called | Next `refreshAccessToken()` call starts a fresh in-flight promise, not the old one |
| auth-client-030 | refresh-generation-guard | Refresh in flight; `invalidateRefresh()` fires before the response lands; response then resolves OK | Result `null`; no `writeTokens` call |
| auth-client-031 | refresh-success-adopts-current-storage | Refresh in flight; `clearTokens()` (logout) fires before the OK response lands | Result `null`; storage stays cleared (refresh.test.ts "does NOT resurrect the session") |
| auth-client-032 | refresh-success-adopts-current-storage | Refresh in flight; a concurrent `writeTokens({ accessToken: 'WINNER' })` fires before this attempt's OK response lands with `{ token: 'MINE' }` | Result `'WINNER'`; storage still `'WINNER'` (refresh.test.ts "adopts a concurrently-written token") |
| auth-client-033 | refresh-failure-adopts-concurrent-winner | Non-OK response; storage already holds a token different from the one this attempt started with | Result is that current stored token; no `clearTokens` |
| auth-client-034 | refresh-failure-loser-recheck-delay | Non-OK response; a winner's `writeTokens({ accessToken: 'WINNER' })` lands during the 300ms wait | After the wait, result `'WINNER'` (refresh.test.ts "failure path: waits for a delayed concurrent winner") |
| auth-client-035 | refresh-failure-clears-when-unresolved | Non-OK response; no winner appears during the 300ms wait | Result `null`; `readTokens()` is `null` (refresh.test.ts "clears tokens and returns null on a non-OK response with no concurrent winner") |
| auth-client-036 | refresh-network-error-reports-and-clears | `fetch` rejects with a `TypeError` | `reportAuthError` called with `{ feature: 'auth', step: 'tokenRefresh' }`; result `null`; tokens cleared |
| auth-client-037 | authed-fetch-bearer-attach | `writeTokens({ accessToken: 'TOK' })`; `authedFetch('/api/x')` | Request header `Authorization: 'Bearer TOK'` (client.test.ts) |
| auth-client-038 | authed-fetch-default-content-type | `authedJson('/api/x', { body: JSON.stringify({}) })` with no `Content-Type` given | Sent request has `Content-Type: application/json` |
| auth-client-039 | authed-fetch-default-init | `authedFetch('/api/x')` called with no second argument | Resolves normally; no throw reading `init.headers` (client.test.ts "works with no init at all") |
| auth-client-040 | authed-fetch-401-refresh-retry-once | First fetch → `401`; refresh → `{ token: 'NEW' }`; retry → `200` | 3 fetch calls total; final result uses `Authorization: 'Bearer NEW'` (client.test.ts) |
| auth-client-041 | authed-fetch-throws-on-non-ok | Response `{ ok: false, status: 500, json: () => ({ error: 'boom' }) }` | Throws `AuthHttpError` with message `'boom'`, `status === 500` (client.test.ts) |
| auth-client-042 | authed-json-rejects-204 | Response `{ ok: true, status: 204 }` | Throws `/Unexpected empty response/` |
| auth-client-043 | authed-request-discards-body | `authedRequest('/api/x', { method: 'DELETE' })` on a `200` with a JSON body | Resolves `undefined`; body never parsed by the caller |
| auth-client-044 | auth-http-error-shape | `new AuthHttpError(409, 'conflict', 'ALREADY_LINKED')` | `.status === 409`, `.code === 'ALREADY_LINKED'`, `.name === 'AuthHttpError'`, `instanceof Error` |
| auth-client-045 | extract-error-message-precedence | `extractErrorMessage({ error: 'E' }, 'fb')`, `({ message: 'M' }, 'fb')`, `({ title: 'T' }, 'fb')`, `({}, 'fb')` | `'E'`, `'M'`, `'T'`, `'fb'` respectively (client.test.ts) |
| auth-client-046 | extract-error-message-precedence | `extractErrorMessage({ title: 'Bad Request', status: 400, detail: 'no GitHub App is configured' }, 'fb')` | `'no GitHub App is configured'` (RFC 9457 `detail` wins) |
| auth-client-047 | extract-error-code-precedence | `extractErrorCode({ error: { code: 'X' } })` and `extractErrorCode({})` | `'X'` and `undefined` respectively |
| auth-client-048 | read-error-message-single-parse | `res.json` mocked to resolve once with `{ message: 'M' }` | Returns `'M'`; `res.json` called exactly once |
| auth-client-049 | exchange-sso-code-request-shape | `exchangeSsoCode('code-1')` | `POST` to `'/api/oauth/signin/exchange'` with body `{"code":"code-1"}` |
| auth-client-050 | exchange-sso-code-network-retry-once | First `fetch` rejects (`TypeError`), second resolves `200` with tokens | `fetchMock` called twice; result resolves with the tokens (client.test.ts "retries once after a network-level failure") |
| auth-client-051 | exchange-sso-code-no-http-retry | `fetch` resolves `{ ok: false, status: 401 }` | `fetchMock` called once per `exchangeSsoCode` call — no internal retry (client.test.ts "does NOT retry an HTTP error") |
| auth-client-052 | exchange-sso-code-success-result | `200` response with `{ token: 'A', user: { id: 'u1' } }` | `{ tokens: { accessToken: 'A', refreshToken: '' }, user: { id: 'u1' } }` |
| auth-client-053 | exchange-sso-code-failure-throws | `401` response with `{ error: { message: 'invalid or expired exchange code' } }` | Throws `AuthHttpError` with that message (client.test.ts) |
