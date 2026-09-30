<!-- leaf: implement-general-1/auth-client-server--test-vectors · source: auth-client-server.md -->

# Auth Client-Server Proxy

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-server-001 | backend-url-explicit-override | `resolveBackendUrl({ API_BACKEND_URL: 'https://custom.example', NODE_ENV: 'production' })` | Returns `'https://custom.example'` — `proxy.test.ts` › "uses explicit API_BACKEND_URL when set" |
| auth-client-server-002 | backend-url-empty-override-ignored | `resolveBackendUrl({ API_BACKEND_URL: '', NODE_ENV: 'production' })` | Returns `'https://api.agenticdeveloperhub.com'` (empty string is falsy) — derived directly from the `if (env.API_BACKEND_URL)` truthiness check; no dedicated test exists |
| auth-client-server-003 | backend-url-production-default | `resolveBackendUrl({ NODE_ENV: 'production' })` | Returns `'https://api.agenticdeveloperhub.com'` — `proxy.test.ts` › "defaults to the shared prod data API in production" |
| auth-client-server-004 | backend-url-development-default | `resolveBackendUrl({ NODE_ENV: 'development' })` | Returns `'http://localhost:3000'` — `proxy.test.ts` › "defaults to localhost in development" |
| auth-client-server-005 | backend-url-development-default | `resolveBackendUrl({})` | Returns `'http://localhost:3000'` — `proxy.test.ts` › "defaults to localhost when NODE_ENV is unset" |
| auth-client-server-006 | api-prefix-strips-namespace | `proxyToBackend(req, 'api', ['users', '42'])` against a resolved backend of `'http://localhost:3000'` | Outbound target path is `'http://localhost:3000/users/42'` — no `api/` segment inserted, per source's `forwardPrefix = prefix === 'api' ? '' : ...` |
| auth-client-server-007 | auth-prefix-preserved | `proxyToBackend(req, 'auth', ['login'])` | Outbound target path is `'http://localhost:3000/auth/login'` |
| auth-client-server-008 | path-segments-joined-and-appended | `proxyToBackend(req, 'api', ['a', 'b', 'c'])` | Target path segment is `'a/b/c'` |
| auth-client-server-009 | query-string-forwarded | Inbound request URL `'https://site.example/api/foo?x=1&y=2'`; `proxyToBackend(req, 'api', ['foo'])` | Outbound target URL ends with `'?x=1&y=2'` |
| auth-client-server-010 | host-header-removed, content-length-header-removed | Inbound request carrying `Host: site.example` and `Content-Length: 42` | Forwarded `Headers` has no `host` entry and no `content-length` entry |
| auth-client-server-011 | accept-encoding-forced-identity | Inbound `Accept-Encoding: gzip, deflate, br, zstd` | Forwarded `accept-encoding` is `'identity'` — `proxy.test.ts` › "asks the backend for an unencoded body instead of forwarding the browser Accept-Encoding" |
| auth-client-server-012 | accept-encoding-forced-identity | Inbound `Accept-Encoding: gzip` only | Forwarded `accept-encoding` is still `'identity'` — `proxy.test.ts` › "overrides Accept-Encoding even when the browser asks only for gzip" |
| auth-client-server-013 | redirect-not-followed | Backend responds `302` with `Set-Cookie: session=abc` | `proxyToBackend`'s returned `Response` is `302` with the same `Set-Cookie` header — `fetch` was called with `redirect: 'manual'` and never followed it itself |
| auth-client-server-014 | body-forwarded-for-mutating-methods | `proxyToBackend` called with a `POST` request whose body is `'{"code":"x"}'` | Outbound `init.body` is the exact `ArrayBuffer` of `'{"code":"x"}'` — exercised via `proxy.test.ts`'s `captureForwardedHeaders` helper, which sends a `POST` |
| auth-client-server-015 | no-body-for-get-or-head | `proxyToBackend` called with a `GET` request | Outbound `init.body` is `undefined` |
| auth-client-server-016 | response-returned-verbatim | Backend responds `200` with JSON body `{"ok":true}` | `proxyToBackend` resolves to that exact `Response` — same status and body bytes, nothing rewritten |
| auth-client-server-017 | five-methods-generated | `makeProxyHandlers('api')` | Returned object has exactly the keys `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, each a function |
| auth-client-server-018 | identical-behavior-across-methods | Invoke the `PUT` and `DELETE` handlers `makeProxyHandlers('auth')` returns, with the same `req`/`ctx` | Both call `proxyToBackend(req, 'auth', path)` identically, because both keys reference the same `handle` closure |
| auth-client-server-019 | params-awaited-before-forwarding | `ctx.params` resolves (after a microtask) to `{ path: ['x'] }` | The handler awaits it before calling `proxyToBackend`, so `proxyToBackend` never receives an unresolved `Promise` in place of `path` |
| auth-client-server-020 | credentials-forwarded-opaquely | Inbound request carrying `Cookie: session=abc` and `Authorization: Bearer tok` | Both headers appear unchanged in the outbound `Headers`; only `host` and `content-length` are deleted |
| auth-client-server-021 | backend-is-sole-authenticator | Backend responds `401` with body `{"error":"invalid_token"}` | `proxyToBackend` returns that exact `401` response unchanged; no status-code check runs before or after the call |
| auth-client-server-022 | no-token-lifetime-authority | Any call into this module | No code path reads, decodes, stores, or sets an expiry on a token/cookie value; the only data inspected are header names and the `path`/`prefix` routing parameters |
