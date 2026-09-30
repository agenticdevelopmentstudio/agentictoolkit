<!-- leaf: implement-general-1/auth-client-server · source: auth-client-server.md -->

**Rules** (cite as `implement-general-1/auth-client-server#<slug>`):

- `backend-url-explicit-override` MUST
- `backend-url-empty-override-ignored` MUST
- `backend-url-production-default` MUST
- `backend-url-development-default` MUST
- `api-prefix-strips-namespace` MUST
- `auth-prefix-preserved` MUST
- `path-segments-joined-and-appended` MUST
- `query-string-forwarded` MUST
- `host-header-removed` MUST
- `content-length-header-removed` MUST
- `accept-encoding-forced-identity` MUST
- `redirect-not-followed` MUST
- `body-forwarded-for-mutating-methods` MUST
- `no-body-for-get-or-head` MUST
- `response-returned-verbatim` MUST
- `five-methods-generated` MUST
- `identical-behavior-across-methods` MUST
- `params-awaited-before-forwarding` MUST
- `credentials-forwarded-opaquely` MUST
- `backend-is-sole-authenticator` MUST
- `no-token-lifetime-authority` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `API_BACKEND_URL` | environment variable (string) | unset | Overrides the resolved backend base URL entirely when non-empty; read via `resolveBackendUrl`'s `env` parameter, which defaults to `process.env`. |
| `NODE_ENV` | environment variable (string) | unset | Selects the fallback backend URL when `API_BACKEND_URL` is unset or empty: `https://api.agenticdeveloperhub.com` when exactly `production`, `http://localhost:3000` otherwise. |
| `prefix` | caller parameter, `'auth' \| 'api'` | none — required | Passed to `makeProxyHandlers(prefix)` by the site's route file; selects the URL-namespace mapping (`api` → backend root, `auth` → backend `/auth/*`). |
| `path` | Next.js dynamic-route parameter, `string[]` | — | The catch-all segments after the mount point, supplied by Next.js via `ctx.params` from the matching `[...path]` route file. |
| `dynamic` | route file export, `'force-dynamic'` | required by convention | Documented in source's JSDoc as part of the wiring a consuming route file must export; not enforced by this module itself. |

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

