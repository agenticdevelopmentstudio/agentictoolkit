<!-- leaf: implement-general-1/auth-client-server--edge-cases · source: auth-client-server.md -->

# Auth Client-Server Proxy

**Rules** (cite as `implement-general-1/auth-client-server--edge-cases#<slug>`):

- `null-and-empty-input` MUST — path is always an array supplied by Next.js's [...path] catch-all param, never null/undefined in source; req and prefix …
- `empty-path-array` MUST — a catch-all route matched with no trailing segments makes path.join('/') yield ''. For prefix === 'api' the target …
- `api-backend-url-set-to-the-empty-string` MUST — MUST be treated as unset per backend-url-empty-override-ignored above, falling through to the NODE_ENV default.
- `node-env-set-to-a-value-other-than-production-or-development` MUST (e.g. `'test'`, `'staging'`, or unset) — MUST resolve to 'http://localhost:3000', identically to an explicit 'development', because the source checks only === …
- `error-states-backend-responds-with-a-non-2xx-status` MUST — MUST be returned to the caller unchanged, per response-returned-verbatim; this module inspects nothing about the status.

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
