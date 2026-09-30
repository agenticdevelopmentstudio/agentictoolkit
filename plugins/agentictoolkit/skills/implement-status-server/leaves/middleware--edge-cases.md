<!-- leaf: implement-status-server/middleware--edge-cases · source: status-server-middleware.md -->

# Status Server Middleware

**Rules** (cite as `implement-status-server/middleware--edge-cases#<slug>`):

- `null-and-empty-input` MUST — a missing Authorization header resolves bearer to undefined (MUST); a missing x-forwarded-for header resolves clientIp …
- `boundary-values` MUST — a bearer value of exactly 'Bearer ' (prefix plus nothing) slices to the empty string, which bearer returns as-is rather …

## Edge Cases

- **Null and empty input**: a missing `Authorization` header resolves
  `bearer` to `undefined` (MUST); a missing `x-forwarded-for` header
  resolves `clientIp` to `'local'` (MUST). A `x-forwarded-for` header that
  is present but consists only of commas or whitespace (e.g. `','`, `' '`)
  also resolves to `'local'`, because `split(',').map(trim).filter(Boolean)`
  discards every entry, leaving `hops[hops.length - 1]` as `undefined`,
  caught by the `?? 'local'` fallback (MUST).
- **Boundary values**: a bearer value of exactly `'Bearer '` (prefix plus
  nothing) slices to the empty string, which `bearer` returns as-is rather
  than as `undefined` (MUST; see bearer-empty-after-trim). `opts.max` set to
  `0` blocks the very first request on a route, because that request's
  bucket `count` becomes `1`, which already exceeds `0`; this is a
  fully-determined arithmetic outcome of the code as written, not a
  distinct branch. A bucket exactly at `count === opts.max` is still
  admitted — only `count > opts.max` blocks (MUST, rate-limit-block-response).
- **Concurrent access**: `rateLimit`'s bucket lookup, creation, increment,
  and comparison run synchronously (no `await`) before the middleware calls
  `next()`, and Node's event loop runs one request handler at a time up to
  its first `await`; two concurrent requests for the same key therefore
  never interleave mid-mutation of a bucket. `requireAuth` and `requireAdmin`
  hold no module-level mutable state at all, so concurrent requests for
  different callers never interfere with each other's `tier`/`user`/`token`
  context values.
- **Error states**: `requireAuth`'s middleware calls
  `await gate.authenticate(c.req)` with no `try`/`catch`; if the gate's
  promise rejects (a `Storage` dependency failure, for example), the
  rejection propagates out of `requireAuth` uncaught rather than resolving
  `401`. This is consistent with the `AuthGate` interface's own documented
  contract (per `status-server-auth`), which scopes the "never throws"
  guarantee to an *unauthenticated* caller, not to a failed dependency; the
  app's own error handler (external to these two files) is what turns that
  rejection into a response. `rateLimit` has no external dependency to
  fail — its only failure mode is the hard-cap drop, which is a defined
  outcome (rate-limit-hard-cap-drop), not an error.
- **Offline / disconnected state**: neither file makes an outbound network
  or storage call itself; `requireAuth` delegates that concern entirely to
  the injected `gate`, and `rate-limit.ts` is purely in-memory. There is
  nothing in these two files that can go "offline" independently of the
  process they run in.
- **Process restart**: because `rateLimit`'s bucket map is a plain in-memory
  `Map` created inside the `rateLimit(opts)` closure, a process restart
  (deploy, crash, scale event) discards every bucket for every key; a
  client that was mid-window when the process restarted gets a fresh
  ceiling with no memory of its prior attempts. This is a direct consequence
  of the documented "in-memory by design (single-instance backend)" choice
  (Design Decisions), not a separate mechanism.
