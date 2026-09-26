---
id: 4a345333-b18d-48f1-806d-453c15155dfa
title: Auth Client-Server Proxy
domain: agentictoolkit://cookbook/auth/server/proxy
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Server-side BFF proxy forwarding /api and /auth to the backend via a Route
  Handler, preserving redirects and Set-Cookie verbatim.
platforms:
- typescript
- web
tags:
- auth
- proxy
- server
- bff
depends-on: []
related: []
references:
- packages/web/packages/auth/src/server/proxy.ts (agentictoolkit)
- packages/web/packages/auth/src/server/index.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/proxy.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Auth Client-Server Proxy

## Overview

The auth client-server proxy is the server half of a site's authentication
plumbing: a Backend-for-Frontend (BFF) that forwards a browser's `/api/*` and
`/auth/*` requests to the shared backend from inside a Next.js Route Handler,
instead of a `next.config` rewrite. It exists specifically because a rewrite
cannot preserve auth on every hosting tier: OpenNext running on Cloudflare
Workers calls `fetch` with `redirect: "follow"` by default, which silently
follows the backend's OAuth 302 and discards its `Set-Cookie` header. This
module forces `redirect: "manual"` so a 302 (and its `Set-Cookie`) reaches the
browser unmodified. Vercel sites that proxy via `next.config` rewrites don't
need it. A consuming site wires it with three lines in a catch-all route file:

```
import { makeProxyHandlers } from '@agentic-toolkit/auth/server'
export const dynamic = 'force-dynamic'
export const { GET, POST, PUT, PATCH, DELETE } = makeProxyHandlers('api')
```

It is a headless **logic** module — no visual surface — so this recipe marks
Appearance, States and Accessibility not applicable and carries the runtime
contract entirely in Behavioral Requirements, per the non-UI component
guidance this recipe was authored under.

## Behavioral Requirements

- **backend-url-explicit-override**: `resolveBackendUrl` MUST return
  `env.API_BACKEND_URL` verbatim when it is a non-empty string, regardless of
  `env.NODE_ENV`.
- **backend-url-empty-override-ignored**: `resolveBackendUrl` MUST treat an
  empty-string `API_BACKEND_URL` as unset and fall through to the
  `NODE_ENV`-based default, because the check `if (env.API_BACKEND_URL)` is a
  plain truthiness test.
- **backend-url-production-default**: When `API_BACKEND_URL` is unset (or
  empty) and `env.NODE_ENV` is exactly the string `production`,
  `resolveBackendUrl` MUST return `https://api.agenticdeveloperhub.com`.
- **backend-url-development-default**: When `API_BACKEND_URL` is unset (or
  empty) and `env.NODE_ENV` is anything other than exactly `production`
  (including `undefined` or any other string), `resolveBackendUrl` MUST return
  `http://localhost:3000`.
- **api-prefix-strips-namespace**: For `prefix === 'api'`, `proxyToBackend`
  MUST build the backend target with no `api/` segment inserted, because the
  backend already dropped its own `/api` route prefix.
- **auth-prefix-preserved**: For `prefix === 'auth'`, `proxyToBackend` MUST
  insert a literal `auth/` segment before the forwarded path, mapping 1:1 onto
  the backend's Hydra OIDC routes.
- **path-segments-joined-and-appended**: `proxyToBackend` MUST join the
  `path` array elements with `/` and append the result after the resolved
  prefix segment to form the backend target path.
- **query-string-forwarded**: `proxyToBackend` MUST append the inbound
  request URL's `search` string (the `?...` suffix, including none when
  absent) to the backend target URL unchanged.
- **host-header-removed**: `proxyToBackend` MUST delete the `host` header
  from the copied `Headers` before forwarding, so the outbound request
  carries the backend's own host rather than the inbound one.
- **content-length-header-removed**: `proxyToBackend` MUST delete the
  `content-length` header from the copied `Headers` before forwarding, so
  `fetch` recomputes it for the outbound body.
- **accept-encoding-forced-identity**: `proxyToBackend` MUST set the outbound
  `accept-encoding` header to `identity`, overriding whatever the inbound
  request declared, because Node's `undici` transparently decodes a
  gzip/deflate response body while leaving the upstream `content-encoding`
  header in place, and this module returns that response verbatim.
- **redirect-not-followed**: `proxyToBackend` MUST fetch the backend with
  `redirect: 'manual'` so a 3xx response and its `Set-Cookie` header reach the
  caller unfollowed and unmodified.
- **body-forwarded-for-mutating-methods**: For any request method other than
  `GET` or `HEAD`, `proxyToBackend` MUST read the inbound body via
  `req.arrayBuffer()` and set it as the outbound `init.body` verbatim.
- **no-body-for-get-or-head**: For `GET` or `HEAD` requests, `proxyToBackend`
  MUST NOT set an outbound body.
- **response-returned-verbatim**: `proxyToBackend` MUST return the `Response`
  object `fetch` resolves with, unmodified — its status, headers, and body all
  pass through exactly as the backend produced them.
- **five-methods-generated**: `makeProxyHandlers` MUST return an object with
  exactly the keys `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`.
- **identical-behavior-across-methods**: Every handler `makeProxyHandlers`
  returns MUST resolve `ctx.params` and call `proxyToBackend` with the same
  bound `prefix`, applying identical target-resolution, header, and body
  rules regardless of which of the five methods was invoked.
- **params-awaited-before-forwarding**: Each generated handler MUST await
  `ctx.params` to obtain `path` before calling `proxyToBackend`, because
  Next.js supplies `params` as a `Promise`.

### Security

This module transits authentication material end to end without inspecting
it. It never parses a cookie, decodes a bearer token, or checks an expiry —
every authentication decision belongs to the backend, and this module's only
job is to relay the backend's decision unchanged.

- **credentials-forwarded-opaquely**: `proxyToBackend` MUST forward the
  inbound `Cookie` and `Authorization` headers, and every other header not
  explicitly deleted, to the backend unmodified, and MUST NOT inspect,
  decode, or log their contents. Traced: the only two `headers.delete(...)`
  calls in source target `host` and `content-length`; nothing in the file
  reads a `Cookie` or `Authorization` value.
- **backend-is-sole-authenticator**: This module MUST NOT itself accept,
  reject, or otherwise adjudicate a caller's credentials; it MUST return
  whatever status the backend responds with — including `401`/`403` — via
  response-returned-verbatim, unchanged. Traced: no status-code branch exists
  anywhere in `proxyToBackend`.
- **no-token-lifetime-authority**: This module MUST NOT set, extend, or
  revoke any token or session lifetime. Token issuance and expiry belong to
  the backend; storage and refresh belong to sibling modules in this package
  (`client.ts`, `tokens.ts`, `refresh.ts`), none of which are part of this
  recipe's source. Traced: no variable in `proxy.ts` holds a token value, and
  the file imports nothing from those sibling modules.

## Appearance

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

## States

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

## Accessibility

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

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

## Edge Cases

- **Null and empty input**: `path` is always an array supplied by Next.js's
  `[...path]` catch-all param, never `null`/`undefined` in source; `req` and
  `prefix` are required parameters with no runtime null guard. Every call
  site in source passes literal, well-typed values
  (`makeProxyHandlers('api')` / `makeProxyHandlers('auth')`), so this is
  enforced at compile time only — MUST be read this way, not as a runtime
  gap, because `prefix` originates from a fixed, developer-authored literal
  rather than untrusted input.
- **Empty `path` array**: a catch-all route matched with no trailing
  segments makes `path.join('/')` yield `''`. For `prefix === 'api'` the
  target becomes `${backend}/${search}`; for `prefix === 'auth'` it becomes
  `${backend}/auth/${search}`. MUST behave this way — there is no empty-path
  guard in source.
- **`API_BACKEND_URL` set to the empty string**: MUST be treated as unset per
  backend-url-empty-override-ignored above, falling through to the
  `NODE_ENV` default.
- **`NODE_ENV` set to a value other than `production` or `development`**
  (e.g. `'test'`, `'staging'`, or unset): MUST resolve to
  `'http://localhost:3000'`, identically to an explicit `'development'`,
  because the source checks only `=== 'production'` with no other branch.
- **Boundary values**: no numeric or length constraint exists on `path` or on
  any header in source; a `path` with one segment and a `path` with hundreds
  of segments are joined the same way. Not applicable in the numeric sense —
  there is nothing in source to bound.
- **Concurrent access**: `proxyToBackend` and the handlers `makeProxyHandlers`
  returns hold no shared mutable state between invocations — the only
  module-level value is the read-only `PROD_DATA_API` constant. Not
  applicable: each call is an independent forward with nothing to serialize.
- **Error states — backend responds with a non-2xx status**: MUST be
  returned to the caller unchanged, per response-returned-verbatim; this
  module inspects nothing about the status.
- **Error states — backend unreachable**: a connection failure (e.g.
  `ECONNREFUSED`) makes the `fetch` call itself reject. `proxyToBackend` and
  `makeProxyHandlers` catch nothing, so the rejection propagates unhandled out
  of the Route Handler to the Next.js runtime, which converts it to a
  generic framework-level error response with no proxy-authored message.
  This is what the source does, not an idealized description of it.
- **Offline / disconnected state**: connectivity loss between the browser and
  this proxy is handled by the platform's own HTTP layer, not by this module;
  there is no reconnection or resumption logic in source. The server-side
  analogue — the backend becoming unreachable mid-request — is the
  backend-unreachable case immediately above.
- **No retry on network failure**: `proxyToBackend` issues exactly one
  `fetch` per incoming request and never retries a failed one itself. This is
  a deliberate layering boundary, not an oversight — a sibling module in this
  package (`client.ts`'s `exchangeSsoCode`) already owns a one-time
  network-failure retry one layer up, at the caller.
- No timeout bounds the outbound `fetch` to the backend: a
  reachable-but-unresponsive backend leaves the inbound request pending until
  the hosting Route Handler runtime's own request limit, if it has one; the
  proxy authors no deadline of its own.
- The outbound `fetch` in `proxyToBackend` is not given the inbound
  request's `AbortSignal`, so a browser-cancelled request does not cancel the
  in-flight backend call.
- No re-encoding of path segments: `proxyToBackend` builds the target URL
  via `path.join('/')` with no percent-encoding or validation of any
  segment. A segment containing a character invalid in a URL makes the
  joined string an invalid URL; `fetch` rejects with a TypeError that
  neither `proxyToBackend` nor `makeProxyHandlers` catches, so it
  propagates unhandled to the Next.js runtime the same way the
  backend-unreachable case above does.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `API_BACKEND_URL` | environment variable (string) | unset | Overrides the resolved backend base URL entirely when non-empty; read via `resolveBackendUrl`'s `env` parameter, which defaults to `process.env`. |
| `NODE_ENV` | environment variable (string) | unset | Selects the fallback backend URL when `API_BACKEND_URL` is unset or empty: `https://api.agenticdeveloperhub.com` when exactly `production`, `http://localhost:3000` otherwise. |
| `prefix` | caller parameter, `'auth' \| 'api'` | none — required | Passed to `makeProxyHandlers(prefix)` by the site's route file; selects the URL-namespace mapping (`api` → backend root, `auth` → backend `/auth/*`). |
| `path` | Next.js dynamic-route parameter, `string[]` | — | The catch-all segments after the mount point, supplied by Next.js via `ctx.params` from the matching `[...path]` route file. |
| `dynamic` | route file export, `'force-dynamic'` | required by convention | Documented in source's JSDoc as part of the wiring a consuming route file must export; not enforced by this module itself. |

## Deep Linking

Not applicable: `proxy.ts` defines no application URL scheme; it implements
the receiving side of whatever `/auth/*` and `/api/*` paths a site's own
route file forwards to it, via `makeProxyHandlers`.

## Localization

Not applicable: `proxy.ts` contains no user-facing string — every byte in its
responses is either forwarded verbatim from the backend or absent; the file
defines no text of its own.

## Accessibility Options

Not applicable: `proxy.ts` has no UI and responds to none of the
accessibility display options (Reduce Motion, Increase Contrast,
Differentiate Without Color).

## Feature Flags

Not applicable: `proxy.ts` contains no feature-flag check of any kind —
`prefix` and `path` are the only runtime branches in the file.

## Analytics

Not applicable: `proxy.ts` emits no analytics event; the file contains no
telemetry call of any kind.

## Privacy

- **Data collected**: none originated by this module. It transits whatever
  the browser and backend already exchange through it — session cookies,
  `Authorization` headers, OAuth codes in request bodies, and `Set-Cookie`
  tokens in 3xx responses — per credentials-forwarded-opaquely, without
  inspecting, parsing, or logging any of it.
- **Storage**: none. `proxyToBackend` is a stateless per-request forward; it
  holds nothing in memory or on disk beyond the lifetime of a single call.
- **Transmission**: yes. Credentials leave the browser and pass through this
  server compute to the backend at the resolved backend URL (`localhost` in
  development, an environment-configured or default production URL). TLS, if
  any, is provided by the deployment platform; this module does not
  configure it.
- **Retention**: none. Nothing this module handles is retained after the
  response it produced is returned to the caller.

## Logging

Not applicable: `proxy.ts` contains no logging call — nothing in the file
writes to a log at any level.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/auth/src/server/proxy.ts`
  holds `resolveBackendUrl`, `proxyToBackend`, and `makeProxyHandlers`;
  `server/index.ts` re-exports all three. A consuming site wires it from a
  catch-all Next.js App Router Route Handler,
  `app/<prefix>/[...path]/route.ts`, exporting `dynamic = 'force-dynamic'`
  and the five methods `makeProxyHandlers` returns. The module is built on
  the Fetch API's `Request`/`Response`/`Headers`, and specifically works
  around OpenNext-on-Cloudflare-Workers' default `redirect: 'follow'`
  behavior and Node `undici`'s transparent gzip decoding — both named in the
  file's own comments.
- **SwiftUI / AppKit / UIKit**: these are client UI frameworks with no
  server-rendered page needing a BFF; a native app on these platforms talks
  to the backend directly with `URLSession`, attaching its own bearer token
  or session cookie, rather than replaying this pattern. This module's
  reason for existing — working around a serverless edge runtime's forced
  redirect-following and content-encoding relabeling — has no client-side
  analogue on these platforms.
- **Compose**: same reasoning as SwiftUI/AppKit/UIKit — an Android app calls
  the backend directly (e.g. via OkHttp/Retrofit) with its own auth header;
  it has no Route Handler layer to port this file into.
- **WinUI 3**: a WinUI 3 desktop app has no server-rendered pages and so no
  need for a Next.js-style BFF; it would call the backend directly with
  `HttpClient`, attaching `Authorization: Bearer <token>` from wherever the
  app stores it, and parsing responses with `System.Text.Json`.
  `HttpClientHandler`'s default redirect-following does not exhibit the
  Set-Cookie-dropping bug this file works around, so no `AllowAutoRedirect =
  false` equivalent is needed on that platform. If a future WinUI 3 product
  ever grows a companion ASP.NET Core BFF for its own web surface, the
  analogue of `proxyToBackend`/`makeProxyHandlers` would be an
  `IHttpForwarder` (YARP) or hand-rolled `HttpClient`-based middleware in
  `Microsoft.AspNetCore.Http`, explicitly setting
  `HttpClientHandler.AllowAutoRedirect = false` to preserve `Set-Cookie` the
  same way `redirect: 'manual'` does here, and forcing `Accept-Encoding:
  identity` upstream if that host's HTTP client exhibits the same
  transparent-decode-but-relabel behavior as Node's `undici`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/auth/src/server/proxy.ts` |

## Design Decisions

- **Decision**: Force `redirect: 'manual'` on every backend fetch.
  **Rationale**: OpenNext-on-Cloudflare-Workers' default fetch follows a 302
  automatically and drops the `Set-Cookie` header the backend's OAuth flow
  depends on; `manual` hands the 3xx and its `Set-Cookie` to the browser
  untouched. Vercel's rewrite-based sites don't need this, but the source
  makes no distinction — it always sets `manual`.
  **Approved**: pending
- **Decision**: Force outbound `accept-encoding: identity`, discarding the
  browser's own value.
  **Rationale**: Node's `undici` fetch implementation transparently decodes a
  gzip/deflate response body but leaves the upstream `content-encoding: gzip`
  response header in place; because this module returns that response
  verbatim, forwarding the browser's real `Accept-Encoding` made the browser
  receive a body that was already decoded but still labeled compressed, and
  its own `fetch` rejected with a TypeError — the reported symptom was the
  sign-in callback page's "Could not reach the sign-in service" on every
  sign-in. Requesting `identity` upstream removes the mismatch entirely; a
  CDN in front of the browser can still compress on the way out.
  **Approved**: pending
- **Decision**: Map the `'api'` prefix to the backend root instead of a
  literal `/api/...` path, while the `'auth'` prefix keeps its segment.
  **Rationale**: the backend already dropped its own `/api` route prefix, so
  re-adding it here would 404 every request; the backend's Hydra OIDC routes
  are still mounted at `/auth/...`, so that prefix is preserved verbatim.
  **Approved**: pending
- **Decision**: implement this pass-through as a Next.js Route Handler rather
  than a `next.config` rewrite.
  **Rationale**: a rewrite can't preserve auth on every hosting tier —
  specifically OpenNext on Cloudflare Workers, per the redirect decision
  above; Vercel-hosted sites that rewrite via `next.config` don't need this
  file at all.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

The `explicit-error-handling` failure reflects facts recorded in Edge Cases:
a path segment that is invalid in a URL makes `fetch` throw a `TypeError`
that neither `proxyToBackend` nor `makeProxyHandlers` catches. The proxy
also sets no outbound timeout and does not forward cancellation.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
