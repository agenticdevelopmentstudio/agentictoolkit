---
id: 4a345333-b18d-48f1-806d-453c15155dfa
title: Authentication Proxy
domain: agentictoolkit://cookbook/data/services/auth/auth-proxy
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Server-side BFF proxy forwarding /api and /auth requests to the backend,
  preserving redirects and Set-Cookie verbatim.
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

# Authentication Proxy

## Overview

This recipe is the server half of a site's authentication plumbing: a
Backend-for-Frontend (BFF) that forwards a browser's `/api/*` and `/auth/*`
requests to the shared backend from a server-side request handler, rather
than a declarative rewrite rule. It exists specifically because a
declarative rewrite cannot preserve auth on every hosting tier: one hosting
target (OpenNext running on Cloudflare Workers) issues its outbound request
with automatic redirect-following by default, which silently follows the
backend's OAuth redirect and discards its `Set-Cookie` header. This module
forces manual redirect handling so a 3xx response (and its `Set-Cookie`)
reaches the browser unmodified. Sites that proxy via a declarative rewrite
(such as on Vercel) don't need it. A consuming site wires it into three
exported request handlers on its own catch-all route, forwarding whatever
method it receives.

It is a headless **logic** module — no visual surface — so this recipe marks
Appearance, States and Accessibility not applicable and carries the runtime
contract entirely in Behavioral Requirements, per the non-UI component
guidance this recipe was authored under.

## Behavioral Requirements

- **backend-url-explicit-override**: Backend-URL resolution MUST return the
  `API_BACKEND_URL` environment value verbatim when it is a non-empty
  string, regardless of the runtime environment mode.
- **backend-url-empty-override-ignored**: Backend-URL resolution MUST treat
  an empty-string `API_BACKEND_URL` as unset and fall through to the
  environment-mode-based default, because the check is a plain truthiness
  test.
- **backend-url-production-default**: When `API_BACKEND_URL` is unset (or
  empty) and the runtime environment mode is exactly the string
  `production`, backend-URL resolution MUST return
  `https://api.agenticdeveloperhub.com`.
- **backend-url-development-default**: When `API_BACKEND_URL` is unset (or
  empty) and the runtime environment mode is anything other than exactly
  `production` (including unset or any other string), backend-URL
  resolution MUST return `http://localhost:3000`.
- **api-prefix-strips-namespace**: For the `api` prefix, the backend
  forwarder MUST build the backend target with no `api/` segment inserted,
  because the backend already dropped its own `/api` route prefix.
- **auth-prefix-preserved**: For the `auth` prefix, the backend forwarder
  MUST insert a literal `auth/` segment before the forwarded path, mapping
  1:1 onto the backend's Hydra OIDC routes.
- **path-segments-joined-and-appended**: The backend forwarder MUST join the
  path's segments with `/` and append the result after the resolved prefix
  segment to form the backend target path.
- **query-string-forwarded**: The backend forwarder MUST append the inbound
  request URL's query string (the `?...` suffix, including none when
  absent) to the backend target URL unchanged.
- **host-header-removed**: The backend forwarder MUST remove the `host`
  header from the copied header collection before forwarding, so the
  outbound request carries the backend's own host rather than the inbound
  one.
- **content-length-header-removed**: The backend forwarder MUST remove the
  `content-length` header from the copied header collection before
  forwarding, so the outbound length is recomputed for the outbound body.
- **accept-encoding-forced-identity**: The backend forwarder MUST set the
  outbound `accept-encoding` header to `identity`, overriding whatever the
  inbound request declared, because the runtime's HTTP client transparently
  decodes a gzip/deflate response body while leaving the upstream
  `content-encoding` header in place, and this module returns that response
  verbatim.
- **redirect-not-followed**: The backend forwarder MUST issue the outbound
  request with automatic redirect-following disabled, so a 3xx response and
  its `Set-Cookie` header reach the caller unfollowed and unmodified.
- **body-forwarded-for-mutating-methods**: For any request method other than
  `GET` or `HEAD`, the backend forwarder MUST read the inbound body as a
  raw byte buffer and set it as the outbound body verbatim.
- **no-body-for-get-or-head**: For `GET` or `HEAD` requests, the backend
  forwarder MUST NOT set an outbound body.
- **response-returned-verbatim**: The backend forwarder MUST return the
  response the outbound request resolves with, unmodified — its status,
  headers, and body all pass through exactly as the backend produced them.
- **five-methods-generated**: The handler factory MUST return an object with
  exactly the keys `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`.
- **identical-behavior-across-methods**: Every handler the handler factory
  returns MUST resolve the route's path parameters and call the backend
  forwarder with the same bound prefix, applying identical
  target-resolution, header, and body rules regardless of which of the five
  methods was invoked.
- **params-awaited-before-forwarding**: Each generated handler MUST await
  the route's path parameters before calling the backend forwarder, because
  the host supplies those parameters as a deferred (asynchronous) value.

### Security

This module transits authentication material end to end without inspecting
it. It never parses a cookie, decodes a bearer token, or checks an expiry —
every authentication decision belongs to the backend, and this module's only
job is to relay the backend's decision unchanged.

- **credentials-forwarded-opaquely**: The backend forwarder MUST forward the
  inbound `Cookie` and `Authorization` headers, and every other header not
  explicitly removed, to the backend unmodified, and MUST NOT inspect,
  decode, or log their contents. Traced: the only two header removals in
  source target `host` and `content-length`; nothing in the file reads a
  `Cookie` or `Authorization` value.
- **backend-is-sole-authenticator**: This module MUST NOT itself accept,
  reject, or otherwise adjudicate a caller's credentials; it MUST return
  whatever status the backend responds with — including `401`/`403` — via
  response-returned-verbatim, unchanged. Traced: no status-code branch
  exists anywhere in the backend forwarder.
- **no-token-lifetime-authority**: This module MUST NOT set, extend, or
  revoke any token or session lifetime. Token issuance and expiry belong to
  the backend; storage and refresh belong to sibling modules in this
  package, none of which are part of this recipe's source. Traced: no
  variable in this module holds a token value, and the file imports nothing
  from those sibling modules.

## Appearance

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

## States

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

## Accessibility

Not applicable — this is a server-side request-forwarding proxy, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-server-001 | backend-url-explicit-override | Backend-URL resolution given `{ API_BACKEND_URL: 'https://custom.example', NODE_ENV: 'production' }` | Returns `'https://custom.example'` |
| auth-client-server-002 | backend-url-empty-override-ignored | Backend-URL resolution given `{ API_BACKEND_URL: '', NODE_ENV: 'production' }` | Returns `'https://api.agenticdeveloperhub.com'` (empty string is falsy) — derived directly from the truthiness check; no dedicated test exists |
| auth-client-server-003 | backend-url-production-default | Backend-URL resolution given `{ NODE_ENV: 'production' }` | Returns `'https://api.agenticdeveloperhub.com'` |
| auth-client-server-004 | backend-url-development-default | Backend-URL resolution given `{ NODE_ENV: 'development' }` | Returns `'http://localhost:3000'` |
| auth-client-server-005 | backend-url-development-default | Backend-URL resolution given `{}` | Returns `'http://localhost:3000'` |
| auth-client-server-006 | api-prefix-strips-namespace | The backend forwarder called for the `api` prefix with path segments `['users', '42']`, against a resolved backend of `'http://localhost:3000'` | Outbound target path is `'http://localhost:3000/users/42'` — no `api/` segment inserted |
| auth-client-server-007 | auth-prefix-preserved | The backend forwarder called for the `auth` prefix with path segment `['login']` | Outbound target path is `'http://localhost:3000/auth/login'` |
| auth-client-server-008 | path-segments-joined-and-appended | The backend forwarder called with path segments `['a', 'b', 'c']` | Target path segment is `'a/b/c'` |
| auth-client-server-009 | query-string-forwarded | Inbound request URL `'https://site.example/api/foo?x=1&y=2'`; the backend forwarder called for the `api` prefix with path segment `['foo']` | Outbound target URL ends with `'?x=1&y=2'` |
| auth-client-server-010 | host-header-removed, content-length-header-removed | Inbound request carrying `Host: site.example` and `Content-Length: 42` | Forwarded headers have no `host` entry and no `content-length` entry |
| auth-client-server-011 | accept-encoding-forced-identity | Inbound `Accept-Encoding: gzip, deflate, br, zstd` | Forwarded `accept-encoding` is `'identity'` |
| auth-client-server-012 | accept-encoding-forced-identity | Inbound `Accept-Encoding: gzip` only | Forwarded `accept-encoding` is still `'identity'` |
| auth-client-server-013 | redirect-not-followed | Backend responds `302` with `Set-Cookie: session=abc` | The backend forwarder's returned response is `302` with the same `Set-Cookie` header — the outbound request was issued with redirect-following disabled and never followed it itself |
| auth-client-server-014 | body-forwarded-for-mutating-methods | The backend forwarder called with a `POST` request whose body is `'{"code":"x"}'` | Outbound body is the exact raw bytes of `'{"code":"x"}'` |
| auth-client-server-015 | no-body-for-get-or-head | The backend forwarder called with a `GET` request | Outbound body is absent |
| auth-client-server-016 | response-returned-verbatim | Backend responds `200` with JSON body `{"ok":true}` | The backend forwarder resolves to that exact response — same status and body bytes, nothing rewritten |
| auth-client-server-017 | five-methods-generated | The handler factory called for the `api` prefix | Returned object has exactly the keys `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, each a function |
| auth-client-server-018 | identical-behavior-across-methods | Invoke the `PUT` and `DELETE` handlers the handler factory returns for the `auth` prefix, with the same request/context | Both call the backend forwarder for the `auth` prefix identically, because both keys reference the same underlying handler |
| auth-client-server-019 | params-awaited-before-forwarding | The route's path parameters resolve (after a microtask) to `{ path: ['x'] }` | The handler awaits them before calling the backend forwarder, so the forwarder never receives an unresolved deferred value in place of the path |
| auth-client-server-020 | credentials-forwarded-opaquely | Inbound request carrying `Cookie: session=abc` and `Authorization: Bearer tok` | Both headers appear unchanged in the outbound headers; only `host` and `content-length` are removed |
| auth-client-server-021 | backend-is-sole-authenticator | Backend responds `401` with body `{"error":"invalid_token"}` | The backend forwarder returns that exact `401` response unchanged; no status-code check runs before or after the call |
| auth-client-server-022 | no-token-lifetime-authority | Any call into this module | No code path reads, decodes, stores, or sets an expiry on a token/cookie value; the only data inspected are header names and the path/prefix routing parameters |

## Edge Cases

- **Null and empty input**: the path is always a list supplied by the host's
  catch-all route matching, never absent in source; the request and prefix
  are required parameters with no runtime null guard. Every call site in
  source passes literal, well-typed values (one handler factory invocation
  per prefix), so this is enforced at compile time only — MUST be read this
  way, not as a runtime gap, because the prefix originates from a fixed,
  developer-authored literal rather than untrusted input.
- **Empty path**: a catch-all route matched with no trailing segments makes
  the joined path yield `''`. For the `api` prefix the target becomes
  `${backend}/${search}`; for the `auth` prefix it becomes
  `${backend}/auth/${search}`. MUST behave this way — there is no
  empty-path guard in source.
- **`API_BACKEND_URL` set to the empty string**: MUST be treated as unset
  per backend-url-empty-override-ignored above, falling through to the
  environment-mode default.
- **Environment mode set to a value other than `production` or
  `development`** (e.g. `'test'`, `'staging'`, or unset): MUST resolve to
  `'http://localhost:3000'`, identically to an explicit `'development'`,
  because the source checks only equality with `'production'` with no other
  branch.
- **Boundary values**: no numeric or length constraint exists on the path
  or on any header in source; a path with one segment and a path with
  hundreds of segments are joined the same way. Not applicable in the
  numeric sense — there is nothing in source to bound.
- **Concurrent access**: the backend forwarder and the handlers the handler
  factory returns hold no shared mutable state between invocations — the
  only module-level value is a read-only production-backend constant. Not
  applicable: each call is an independent forward with nothing to
  serialize.
- **Error states — backend responds with a non-2xx status**: MUST be
  returned to the caller unchanged, per response-returned-verbatim; this
  module inspects nothing about the status.
- **Error states — backend unreachable**: a connection failure (e.g.
  connection refused) makes the outbound request itself reject. The
  backend forwarder and the handler factory catch nothing, so the
  rejection propagates unhandled out of the request handler to the host
  runtime, which converts it to a generic framework-level error response
  with no proxy-authored message. This is what the source does, not an
  idealized description of it.
- **Offline / disconnected state**: connectivity loss between the browser
  and this proxy is handled by the platform's own HTTP layer, not by this
  module; there is no reconnection or resumption logic in source. The
  server-side analogue — the backend becoming unreachable mid-request — is
  the backend-unreachable case immediately above.
- **No retry on network failure**: the backend forwarder issues exactly one
  outbound request per incoming request and never retries a failed one
  itself. This is a deliberate layering boundary, not an oversight — a
  sibling module in this package's family (its SSO code exchange) already
  owns a one-time network-failure retry one layer up, at the caller.
- No timeout bounds the outbound request to the backend: a
  reachable-but-unresponsive backend leaves the inbound request pending
  until the hosting runtime's own request limit, if it has one; the proxy
  authors no deadline of its own.
- The outbound request in the backend forwarder is not given the inbound
  request's cancellation signal, so a browser-cancelled request does not
  cancel the in-flight backend call.
- No re-encoding of path segments: the backend forwarder builds the target
  URL by joining segments with no percent-encoding or validation of any
  segment. A segment containing a character invalid in a URL makes the
  joined string an invalid URL; the outbound request rejects with a
  construction error that neither the backend forwarder nor the handler
  factory catches, so it propagates unhandled to the host runtime the same
  way the backend-unreachable case above does.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `API_BACKEND_URL` | environment variable (string) | unset | Overrides the resolved backend base URL entirely when non-empty; read via backend-URL resolution's environment parameter, which defaults to the process environment. |
| `NODE_ENV` | environment variable (string) | unset | Selects the fallback backend URL when `API_BACKEND_URL` is unset or empty: `https://api.agenticdeveloperhub.com` when exactly `production`, `http://localhost:3000` otherwise. |
| `prefix` | caller parameter, `'auth' \| 'api'` | none — required | Passed to the handler factory by the site's route file; selects the URL-namespace mapping (`api` → backend root, `auth` → backend `/auth/*`). |
| `path` | route path-segment parameter, string list | — | The catch-all segments after the mount point, supplied by the host's routing layer from the matching catch-all route. |
| A route-level dynamic-rendering directive | framework routing directive, exported by the consuming route file | required by convention | Documented in source's comments as part of the wiring a consuming route file must export; not enforced by this module itself. |

## Deep Linking

Not applicable: this module defines no application URL scheme; it
implements the receiving side of whatever `/auth/*` and `/api/*` paths a
site's own route file forwards to it, via the handler factory.

## Localization

Not applicable: this module contains no user-facing string — every byte in
its responses is either forwarded verbatim from the backend or absent; the
file defines no text of its own.

## Accessibility Options

Not applicable: this module has no UI and responds to none of the
accessibility display options (Reduce Motion, Increase Contrast,
Differentiate Without Color).

## Feature Flags

Not applicable: this module contains no feature-flag check of any kind —
the prefix and path are the only runtime branches in the file.

## Analytics

Not applicable: this module emits no analytics event; the file contains no
telemetry call of any kind.

## Privacy

- **Data collected**: none originated by this module. It transits whatever
  the browser and backend already exchange through it — session cookies,
  `Authorization` headers, OAuth codes in request bodies, and `Set-Cookie`
  tokens in 3xx responses — per credentials-forwarded-opaquely, without
  inspecting, parsing, or logging any of it.
- **Storage**: none. The backend forwarder is a stateless per-request
  forward; it holds nothing in memory or on disk beyond the lifetime of a
  single call.
- **Transmission**: yes. Credentials leave the browser and pass through
  this server compute to the backend at the resolved backend URL
  (`localhost` in development, an environment-configured or default
  production URL). TLS, if any, is provided by the deployment platform;
  this module does not configure it.
- **Retention**: none. Nothing this module handles is retained after the
  response it produced is returned to the caller.

## Logging

Not applicable: this module contains no logging call — nothing in the file
writes to a log at any level.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/auth/src/server/proxy.ts`
  holds `resolveBackendUrl`, `proxyToBackend`, and `makeProxyHandlers`;
  `server/index.ts` re-exports all three. A consuming site wires it from a
  catch-all Next.js App Router Route Handler,
  `app/<prefix>/[...path]/route.ts`:
  ```
  import { makeProxyHandlers } from '@agentic-toolkit/auth/server'
  export const dynamic = 'force-dynamic'
  export const { GET, POST, PUT, PATCH, DELETE } = makeProxyHandlers('api')
  ```
  exporting `dynamic = 'force-dynamic'` and the five methods
  `makeProxyHandlers` returns. `ctx.params` is a `Promise` in this router,
  which is why the generated handlers `await` it. The module is built on
  the Fetch API's `Request`/`Response`/`Headers`, and specifically works
  around OpenNext-on-Cloudflare-Workers' default `redirect: 'follow'`
  behavior and Node `undici`'s transparent gzip decoding — both named in the
  file's own comments. Vercel sites that proxy via `next.config` rewrites
  don't need this module at all.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/services/auth/. |
