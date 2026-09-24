---
id: d1098650-e0d0-4d4b-9bbc-3ceeac8635fe
title: Status Server Middleware
domain: agentictoolkit://recipes/status-server-middleware
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Hono middleware binding an AuthGate's resolution to 401/403 (requireAuth/requireAdmin)
  and a fixed-window per-key limiter guarding the pre-auth surface.
platforms:
- typescript
- web
tags:
- auth
- server
- rate-limit
- middleware
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/authentication
- agenticdevelopercookbook://guidelines/implementing/security/authorization
- agenticdevelopercookbook://guidelines/implementing/networking/rate-limiting
- agenticdevelopercookbook://guidelines/implementing/networking/error-responses
related:
- agentictoolkit://recipes/status-server-auth
references:
- packages/web/packages/status-server/src/middleware/auth.ts (agentictoolkit)
- packages/web/packages/status-server/src/middleware/rate-limit.ts (agentictoolkit)
- packages/web/packages/status-server/src/auth/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/auth-gate.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/rate-limit.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/auth.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/api-tokens.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Middleware

## Overview

This is the status backend's HTTP binding layer: two files under
`src/middleware/` that sit between Hono's router and the rest of the app.
`auth.ts` exports `bearer` (a small `Authorization`-header helper),
`requireAuth` (a factory that turns any host-supplied `AuthGate`'s
resolution — the `tier`/`user`/`token` triple defined in `../auth/port` and
documented in the sibling `status-server-auth` recipe — into a `401` or a
populated Hono context) and `requireAdmin` (a fixed, gate-less per-route
guard that demands `tier === 'admin'` from whatever `requireAuth` already
set). `rate-limit.ts` exports `rateLimit`, a fixed-window, per-key request
ceiling built for the PRE-AUTH surface — `/auth/login` and `/auth/signup` —
where, per the source comment, every attempt costs a bcrypt verification on
the API thread, so with no ceiling credential stuffing doubles as a CPU
attack.

All authentication MECHANISM — session lookup, bearer-token validation, the
`PEER_TOKEN`/`AUTH_DISABLED` paths — lives in the `AuthGate` implementation
these files receive as a parameter (the default one, `../auth/default-adapter`,
is documented in `status-server-auth`); this recipe's two files never resolve
a credential themselves. `auth.ts` only translates a gate's resolution into
HTTP, and `rate-limit.ts` independently caps request volume by client key,
with no knowledge of what a request is trying to do.

## Behavioral Requirements

### Auth Binding (auth.ts)

- **bearer-prefix-match**: `bearer(c)` MUST return the substring of the
  request's `Authorization` header following the literal prefix `'Bearer '`,
  trimmed of surrounding whitespace, when the header's value starts with
  that exact prefix (case-sensitive, including the trailing space).
- **bearer-absent-or-mismatched**: `bearer(c)` MUST return `undefined` when
  the `Authorization` header is absent, or is present but does not start
  with the literal prefix `'Bearer '`.
- **bearer-empty-after-trim**: When the header is exactly `'Bearer '`
  followed only by whitespace, `bearer(c)` MUST return the empty string, not
  `undefined` — a header that matches the prefix always reaches
  `.slice(7).trim()`, whose result can itself be empty.
- **require-auth-single-gate-call**: `requireAuth(gate)` MUST call
  `gate.authenticate(c.req)` exactly once per incoming request, passing
  Hono's request object directly with no adapter, and MUST await the result
  before proceeding.
- **require-auth-unauthenticated-401**: When `gate.authenticate` resolves
  `null`, `requireAuth`'s middleware MUST throw
  `HTTPException(401, { message: 'Unauthorized' })` and MUST NOT call
  `next()`.
- **require-auth-sets-three-vars**: When `gate.authenticate` resolves a
  non-null value, `requireAuth`'s middleware MUST set exactly the three Hono
  context variables `tier`, `user`, and `token` from the resolved value's
  like-named fields, then MUST call `next()`.
- **require-admin-reads-context-only**: `requireAdmin` MUST read the
  caller's tier only from the Hono context (`c.get('tier')`); it MUST NOT
  accept a gate argument, call `gate.authenticate`, or perform any
  credential resolution of its own — the source comment states it "Runs
  AFTER requireAuth."
- **require-admin-forbidden-403**: When the context's `tier` is not exactly
  the string `'admin'`, `requireAdmin` MUST throw
  `HTTPException(403, { message: 'Admin required' })` and MUST NOT call
  `next()`.
- **require-admin-admits-admin**: When the context's `tier` is exactly
  `'admin'`, `requireAdmin` MUST call `next()`.
- **require-admin-fails-closed**: Because the comparison is
  `c.get('tier') !== 'admin'`, a request on which no prior middleware set
  `tier` (an `undefined` context value) MUST be refused with `403` — the
  same outcome as an explicit non-admin tier. `requireAdmin` fails closed
  rather than admitting an unset tier.

### Rate Limiter (rate-limit.ts)

- **rate-limit-window-default**: `rateLimit(opts)` MUST use
  `opts.windowMs` as the fixed-window length in milliseconds when provided,
  and MUST default it to `60000` (60 seconds) when `opts.windowMs` is
  omitted.
- **rate-limit-key-rightmost-hop**: `rateLimit`'s per-request key
  (`clientIp`) MUST be the rightmost non-empty, trimmed entry of the
  request's `x-forwarded-for` header after splitting it on commas.
- **rate-limit-key-local-fallback**: `clientIp` MUST return the literal
  string `'local'` when the `x-forwarded-for` header is absent, or when
  splitting and trimming it yields no non-empty entries.
- **rate-limit-bucket-creation**: For a given key, `rateLimit`'s middleware
  MUST create a fresh bucket with `count: 0` and `resetAt` set to
  `now + windowMs` whenever no bucket exists for that key, or the existing
  bucket's `resetAt` is at or before the current time.
- **rate-limit-increment-before-check**: `rateLimit`'s middleware MUST
  increment the resolved bucket's `count` by exactly `1` before comparing it
  against `opts.max`, so the request that first exceeds the ceiling is
  itself counted.
- **rate-limit-block-response**: When a bucket's `count` exceeds
  `opts.max`, `rateLimit`'s middleware MUST respond `429` with the JSON body
  `{ error: { message: 'Too many attempts — try again shortly' } }` and MUST
  NOT call `next()`.
- **rate-limit-retry-after-header**: On a `429` response, `rateLimit`'s
  middleware MUST set a `Retry-After` header to the number of whole seconds
  remaining until the bucket's `resetAt`, rounded up, with a minimum value
  of `1`.
- **rate-limit-pass-through**: When a bucket's `count` is less than or
  equal to `opts.max`, `rateLimit`'s middleware MUST call `next()` and MUST
  NOT set a `Retry-After` header or otherwise alter the response.
- **rate-limit-sweep-cadence**: `rateLimit`'s middleware MUST invoke its
  sweep step only when at least `windowMs` milliseconds have elapsed since
  the previous sweep, or when the bucket map's size is at or above
  `MAX_BUCKETS` (`50_000`); it MUST NOT sweep on every request regardless of
  elapsed time or table size.
- **rate-limit-sweep-expiry**: A sweep MUST delete every bucket whose
  `resetAt` is at or before the sweep's `now`.
- **rate-limit-hard-cap-drop**: When, after deleting expired buckets, the
  map's size remains at or above `MAX_BUCKETS` (`50_000`), the sweep MUST
  log an error via `console.error` naming the live bucket count and the
  `50_000` threshold, then MUST clear the entire bucket map.
- **rate-limit-instance-isolation**: Each call to `rateLimit(opts)` MUST
  create its own independent bucket `Map` and `lastSweepAt` closure
  variable, so two middleware instances mounted on different routes (for
  example `/auth/login` and `/auth/signup`) never share a counter for the
  same client key.

### Security

`auth.ts` is where every request's tier/role decision is made, and
`rate-limit.ts` is this backend's only defense against credential-stuffing
CPU exhaustion on its unauthenticated login/signup routes; per this
cookbook's Cookbook Compliance guideline, both are security-relevant and
addressed explicitly rather than left to "platform best practices."

- **credential-value-opaque**: `bearer(c)` MUST return the raw bearer string
  unmodified except for the fixed prefix strip and a trim; it MUST NOT
  parse, decode, or validate the token's contents — token validation is the
  `AuthGate`'s job, external to these two files.
- **authorization-decision-server-side**: `requireAuth` and `requireAdmin`
  MUST derive `tier` exclusively from the `AuthGate`'s resolution and the
  Hono context variable it wrote; MUST NOT read a tier, role, or admin claim
  directly from a request header, cookie value, or query parameter.
- **no-credential-logging**: Neither `auth.ts` nor `rate-limit.ts` MUST log
  the `Authorization` header's value, the resolved bearer string, or any
  other per-request credential. The one `console.error` call in
  `rate-limit.ts` logs only a live bucket count and the fixed `50_000`
  threshold, never a key, an IP, or a credential.
- **violation-outcomes-explicit**: Every rejection path in these two files
  MUST resolve to one specific, already-itemized HTTP outcome (`401` from
  `requireAuth`, `403` from `requireAdmin`, or `429` from `rateLimit`) and
  MUST NOT silently continue as though the request had passed.

Sensitive data in scope: the `Authorization` header's raw value, held only
long enough for `bearer` to strip its prefix and hand it to the caller or the
gate, and the derived `x-forwarded-for` client-IP key, held only inside a
rate-limit bucket for at most one window past its last hit. Neither file
persists, logs, or returns either value in a form that identifies a specific
requester. Storage and revocation of the underlying session/token
credentials `bearer`'s output is checked against are the `AuthGate`'s and,
beneath it, the `Storage` ports' job — external to these two files and
specified in `status-server-auth`.

## Appearance

Not applicable — this is server-side HTTP middleware, not a visual component.

## States

Not applicable — this is server-side HTTP middleware, not a visual component; its per-request resolution branches are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is server-side HTTP middleware, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-middleware-001 | bearer-prefix-match | `bearer(c)` where `Authorization: Bearer abc123` | Returns `'abc123'` |
| status-server-middleware-002 | bearer-absent-or-mismatched | `bearer(c)` with no `Authorization` header | Returns `undefined` |
| status-server-middleware-003 | bearer-absent-or-mismatched | `bearer(c)` where `Authorization: Basic abc123` | Returns `undefined` |
| status-server-middleware-004 | bearer-empty-after-trim | `bearer(c)` where `Authorization: Bearer   ` (trailing whitespace only) | Returns `''` (empty string), not `undefined` |
| status-server-middleware-005 | require-auth-single-gate-call, require-auth-sets-three-vars | `requireAuth(gate)` wraps a gate that resolves `{ tier: 'admin', user: null, token: null }`; `GET /read` | Resolves `200` — `auth-gate.test.ts` › "grants 200 when the gate resolves the request" |
| status-server-middleware-006 | require-auth-unauthenticated-401 | `requireAuth(gate)` wraps a gate that resolves `null`; `GET /read` | Resolves `401` — `auth-gate.test.ts` › "rejects with 401 when the gate resolves to null"; also `auth.int.test.ts` › "rejects with 401 when no session" |
| status-server-middleware-007 | require-admin-reads-context-only, require-admin-admits-admin | An `sts_` admin-role bearer token authenticates, then `GET /users` | Resolves `200` — `api-tokens.int.test.ts` › "an admin token passes requireAdmin (GET /users → 200)" |
| status-server-middleware-008 | require-admin-forbidden-403 | An `sts_` user-role bearer token authenticates (resolves tier `'view'`), then `GET /users` | Resolves `403` — `api-tokens.int.test.ts` › "a user token authenticates a viewer route (200) but is refused an admin route (403)" |
| status-server-middleware-009 | require-admin-forbidden-403 | A `viewer`-role session cookie authenticates, then `POST /write` | Resolves `403` — `auth.int.test.ts` › "lets a viewer read but 403s on an admin route" |
| status-server-middleware-010 | require-admin-fails-closed | `requireAdmin` runs on a Hono context that no prior middleware populated (`c.get('tier')` is `undefined`) | `undefined !== 'admin'` is `true`; throws `403`, the same as an explicit non-admin tier |
| status-server-middleware-011 | rate-limit-window-default, rate-limit-bucket-creation, rate-limit-increment-before-check | `rateLimit({ max: 10 })` mounted on `/auth/login`; 10 sequential `POST /auth/login` requests from the same IP with wrong credentials | All 10 resolve `401` (bad credentials, not rate-limited) — `rate-limit.int.test.ts` › "caps login attempts per IP, then recovers after the window" |
| status-server-middleware-012 | rate-limit-block-response, rate-limit-retry-after-header | An 11th `POST /auth/login` from the same IP within the same window | Resolves `429` with a truthy `Retry-After` header — same test |
| status-server-middleware-013 | rate-limit-instance-isolation | `rateLimit({ max: 5 })` mounted separately on `/auth/signup`; 5 signups then a 6th, all from one IP that has also exhausted its `/auth/login` bucket | The first 5 signups resolve `201`; the 6th resolves `429` from the signup bucket alone, independent of the login bucket's state — `rate-limit.int.test.ts` › "caps signup attempts per IP" |
| status-server-middleware-014 | rate-limit-pass-through | 30 sequential `GET /auth/me` requests from one IP (no `rateLimit` mounted on this route) | All 30 resolve `200`; none resolves `429` — `rate-limit.int.test.ts` › "does not limit the high-frequency public probe /auth/me" |
| status-server-middleware-015 | rate-limit-key-rightmost-hop | 11 `POST /auth/login` requests, each with `x-forwarded-for: <a different forged IP>, 198.51.100.42` | The 11th still resolves `429` — all 11 keyed on the constant rightmost hop, not the attacker-rotated leftmost one — `rate-limit.int.test.ts` › "ignores a spoofed leading x-forwarded-for entry" |
| status-server-middleware-016 | rate-limit-key-rightmost-hop | 10 requests with `x-forwarded-for: 10.0.0.1, 203.0.113.1` (now blocked), then one with `x-forwarded-for: 10.0.0.1, 203.0.113.2` | The `203.0.113.2` request resolves `401`, not `429` — `rate-limit.int.test.ts` › "keys separately per real client when the edge reports different hops" |
| status-server-middleware-017 | rate-limit-key-local-fallback | `rateLimit`'s middleware runs on a request with no `x-forwarded-for` header at all | `clientIp` resolves `'local'`; the request is bucketed under that key alongside every other header-less request to the same route |
| status-server-middleware-018 | rate-limit-sweep-cadence, rate-limit-sweep-expiry | With fake timers: exhaust a bucket to `429`, advance time by `61_000`ms (past the 60s window), then retry | The retry resolves `401` (bad credentials again, not `429`) because the expired bucket was swept and recreated — `rate-limit.int.test.ts` › "the window lapses; the first IP may try again" |
| status-server-middleware-019 | rate-limit-hard-cap-drop | (Derived from source; no dedicated test given.) 50,000 distinct `x-forwarded-for` keys hit a `rateLimit`-guarded route inside one window, none yet expired | The next request's sweep logs exactly one `console.error` naming the live count and `50_000`, then clears the whole bucket map; the triggering request's own key starts a fresh bucket at `count: 1` |
| status-server-middleware-020 | credential-value-opaque, no-credential-logging | Full `requireAuth` + `rateLimit` round trip with `console.log`/`console.error` spied | No spied call includes the `Authorization` header's value or the resolved bearer string; `auth.ts` calls neither `console.log` nor `console.error` at all |
| status-server-middleware-021 | authorization-decision-server-side, violation-outcomes-explicit | A request carries a forged `X-Tier: admin` header but no valid session cookie, `sts_` bearer, or peer token | `requireAuth` still throws `401` — only `gate.authenticate`'s own resolution can set the `tier` context variable; an arbitrary header is never consulted |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gate` | `AuthGate` (from `../auth/port`) | required, caller-supplied | The credential resolver `requireAuth` wraps; injected per app, not read from environment by these two files. |
| `opts.max` | `number` | required, no default | Ceiling on requests per key per window before `rateLimit` starts responding `429`. Caller-supplied per mount point — `10` for `/auth/login`, `5` for `/auth/signup` in this backend's own wiring. |
| `opts.windowMs` | `number \| undefined` | `60000` (60 seconds) via `?? 60_000` | Fixed-window length in milliseconds for one `rateLimit(opts)` instance. |
| `MAX_BUCKETS` | module constant (`rate-limit.ts`) | `50_000` | Hard ceiling on distinct keys one `rateLimit` instance holds at once before its sweep drops the whole table. Not configurable per call. |
| `'admin'` tier literal | hardcoded string (`requireAdmin`) | fixed | The one tier value `requireAdmin` admits; not a configurable threshold. |

## Deep Linking

Not applicable: neither `auth.ts` nor `rate-limit.ts` defines an application URL scheme; both are HTTP middleware bound onto existing routes on the status backend's own origin, not deep-link targets.

## Localization

Neither file uses a localization mechanism; every user-facing string is a hardcoded English literal returned in a JSON error body. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — `401` | `Unauthorized` | `requireAuth`, `gate.authenticate` resolves `null` |
| n/a — `403` | `Admin required` | `requireAdmin`, context `tier` is not `'admin'` |
| n/a — `429` | `Too many attempts — try again shortly` | `rateLimit`, bucket `count` exceeds `opts.max` |

## Accessibility Options

Not applicable: these two files have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: neither file consults a feature-flag system; `opts.max` and `opts.windowMs` are caller-supplied per-call parameters (see Configuration), not a flag-service lookup, and `requireAdmin`'s tier check is a fixed literal comparison.

## Analytics

Not applicable: neither file emits an analytics or telemetry event of any kind.

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

## Logging

Subsystem: n/a (status backend) | Category: `rate-limit`

| Event | Level | Message |
|-------|-------|---------|
| Hard-cap drop | error | `` [rate-limit] bucket table exceeded ${MAX_BUCKETS} live keys — dropping it `` |

`auth.ts` contains no logging call at any level; the table above is
`rate-limit.ts`'s only log statement, and it names a bucket count and the
fixed `50_000` threshold — never a key, an IP address, or a credential.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [rate-limit-handling](agenticdevelopercookbook://compliance/access-patterns#rate-limit-handling) | passed | Access Patterns |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |

`server-side-authorization` passes: `tier` is set exclusively from the
injected `AuthGate`'s resolution, and `requireAdmin` compares only that
server-set context value — no header, cookie, or query parameter is ever
trusted as a tier claim. `secure-log-output` passes: the one log statement
in these two files (the hard-cap drop) carries only a count and a fixed
threshold, never a key, IP, or credential; `auth.ts` logs nothing at all.
`rate-limit-handling` passes: the pre-auth credential routes are capped
per-key with a fixed window, a defined `429` response, and a computed
`Retry-After` header a client can act on. `error-response-handling` passes:
every rejection in these two files resolves to one specific, distinguishable
status (`401`, `403`, `429`) with a JSON body, never a generic failure or a
silent pass-through. `separation-of-concerns` passes: `auth.ts` only
translates a gate's resolution into HTTP and never resolves a credential
itself; `rate-limit.ts` only counts requests and knows nothing about
authentication. `unit-test-coverage` passes: `auth-gate.test.ts` exercises
`requireAuth`'s 200/401 split directly, `rate-limit.int.test.ts` exercises
the limiter's cap, recovery, and IP-spoofing resistance, and
`auth.int.test.ts`/`api-tokens.int.test.ts` exercise `requireAdmin`'s 403
path end-to-end. `explicit-error-handling` is `partial`: every rejection
these two files themselves produce is explicit, but `requireAuth` does not
wrap its `await gate.authenticate(c.req)` call in a `try`/`catch`, so a
rejected gate promise (a dependency failure, not an unauthenticated caller)
propagates uncaught rather than being mapped to a specific status by this
file — a deliberate scope boundary per the `AuthGate` contract (see Edge
Cases), but still a case where this file itself does not produce the final
error response. `data-minimization` passes: `rate-limit.ts` retains only
the derived IP key and a count/reset timestamp per bucket — no request
body, path, or other request data is captured by the limiter — and `bearer`
returns a substring of one header with no further extraction.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
