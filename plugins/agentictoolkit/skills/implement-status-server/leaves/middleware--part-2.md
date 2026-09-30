<!-- leaf: implement-status-server/middleware--part-2 · source: status-server-middleware.md -->

# Status Server Middleware — continued (part 2)

## Privacy

- **Data collected**: the derived `x-forwarded-for` client-IP key
  (`rate-limit.ts`), held only for the purpose of counting requests against
  it; the raw `Authorization` header value, passed through `bearer`
  opaquely and never inspected beyond its prefix (`auth.ts`).
- **Storage**: `rate-limit.ts`'s buckets live only in a per-instance,
  in-memory `Map`; nothing here writes to a database or file system.
  `auth.ts` writes nothing to persistent storage — the `tier`/`user`/`token`
  it sets are Hono request-scoped context variables, discarded when the
  request finishes.
- **Transmission**: neither file makes an outbound network call; both act
  only on the inbound request already received by this process.
- **Retention**: a rate-limit bucket is retained for at most one
  `windowMs` past its last hit (swept on schedule or on the `MAX_BUCKETS`
  hard cap), and unconditionally for at most the current process's
  lifetime — a restart discards every bucket (see Edge Cases). `auth.ts`
  retains nothing past the request it ran on.

## Platform Notes

- **React/Web** (source platform): both files live under
  `packages/web/packages/status-server/src/middleware/`, on top of Hono
  (`hono/factory`'s `createMiddleware`, `hono/http-exception`) and plain
  JavaScript `Map`/`Date.now()` for the rate limiter — no external rate-limit
  or auth-middleware package is used. `requireAuth`/`requireAdmin` are typed
  against Hono's `MiddlewareHandler<{ Variables: ... }>` generic; `rateLimit`
  returns a plain `MiddlewareHandler`.
- **SwiftUI / AppKit / UIKit**: an Apple client of this backend is a
  consumer, not a re-implementer, of this middleware — it calls the status
  API with `URLSession` and reacts to the status codes these files produce
  (`401`/`403` by re-authenticating or hiding admin UI, `429` by reading the
  `Retry-After` header and backing off before its next attempt, per
  `URLResponse`'s HTTP header access). A future Apple-side re-implementation
  of this SERVER logic (a companion Swift backend, e.g. Vapor or
  Hummingbird) would model `requireAuth`/`requireAdmin` as async
  middleware/route-group guards throwing a typed HTTP error, and the rate
  limiter as a `Sendable` actor wrapping a `Dictionary` keyed the same way,
  guarded by the actor's own serialized access instead of JavaScript's
  single-threaded event loop.
- **Compose**: same client relationship as SwiftUI/AppKit/UIKit — an
  Android client calls the backend directly (OkHttp/Retrofit) and reacts to
  the same status codes and `Retry-After` header; it has no server-side
  middleware to port. A Kotlin backend re-implementation (Ktor) would use
  `Route.install`/an `ApplicationCall` interceptor for the auth guards and
  Ktor's own `RateLimit` plugin (or a hand-rolled `Mutex`-guarded map) for
  the limiter.
- **WinUI 3**: a WinUI 3 desktop app is likewise a client, calling the
  status API with `HttpClient` and reading `HttpResponseMessage.Headers.RetryAfter`
  after a `429` before its next attempt, and reacting to `401`/`403` by
  redirecting to sign-in or disabling admin-only commands. If a future
  product needed to reimplement this exact middleware pattern on a .NET
  backend (ASP.NET Core Minimal API), `requireAuth`/`requireAdmin` map to
  authentication/authorization middleware and an `IAuthorizationHandler`
  checking a claim equivalent to `tier`, both throwing (or short-circuiting
  to) the matching status via `HttpContext.Response`; `rateLimit` maps
  directly onto the built-in `Microsoft.AspNetCore.RateLimiting` middleware,
  configured with a `PartitionedRateLimiter<HttpContext>` partitioned by the
  same rightmost-`X-Forwarded-For`-hop key and a `FixedWindowRateLimiterOptions`
  matching `opts.max`/`opts.windowMs`, which already emits a `Retry-After`
  header on rejection the same way this source does by hand.

## Design Decisions

- **Decision**: key the rate limiter on the rightmost `x-forwarded-for`
  entry, not the leftmost.
  **Rationale**: the source comment states the reasoning directly — XFF is a
  chain each hop APPENDS to, so the leftmost value is whatever the client
  sent and is attacker-controlled; keying on it (as an earlier version did)
  let a scripted attacker rotate a forged IP per request and walk straight
  through the ceiling. The rightmost entry is the one added by the trusted
  edge hop, the last thing to touch the header before the loopback proxy
  forwards it verbatim, so it is the only value with any authority.
  **Approved**: pending
- **Decision**: sweep expired buckets on a schedule (at most once per
  `windowMs`, or when the hard cap is hit), not on every request past a size
  threshold.
  **Rationale**: the source comment states this directly — sweeping past a
  size threshold on every request turned the limiter itself into an
  O(n)-per-request cost exactly when it was under attack, which is the
  opposite of what a rate limiter should do under load.
  **Approved**: pending
- **Decision**: when the hard cap is reached with nothing expired, drop the
  entire bucket table rather than evict the oldest entries.
  **Rationale**: the source comment states this directly — every live
  bucket lapses within `windowMs` regardless, so dropping the table costs at
  most one window's worth of accounting and keeps memory bounded with O(1)
  work, instead of paying for an eviction policy to protect counters that
  are about to expire anyway.
  **Approved**: pending
- **Decision**: keep the rate limiter's state in an in-memory `Map` local to
  one `rateLimit(opts)` call, rather than a shared/distributed store.
  **Rationale**: the source comment states this directly — this is a
  single-instance backend by design, so each process bounding only the
  traffic it actually serves is sufficient; a horizontally-scaled deployment
  would give each instance its own independent ceiling rather than a
  cluster-wide one, a fact recorded here as the tradeoff of the design
  actually shipped, not an idealization of it.
  **Approved**: pending
- **Decision**: give `requireAdmin` no `gate` parameter and no credential
  resolution of its own; make it depend entirely on `requireAuth` having run
  first and populated the context.
  **Rationale**: not stated verbatim in source beyond the "Runs AFTER
  requireAuth" comment; the effect is that admin-gating is a second, cheap,
  synchronous check layered on top of the one gate call `requireAuth`
  already paid for, rather than a second credential lookup — recorded here
  as a plain fact about the code's shape, not an invented justification.
  **Approved**: pending
