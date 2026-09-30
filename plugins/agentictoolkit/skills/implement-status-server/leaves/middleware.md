<!-- leaf: implement-status-server/middleware · source: status-server-middleware.md -->

**Rules** (cite as `implement-status-server/middleware#<slug>`):

- `bearer-prefix-match` MUST
- `bearer-absent-or-mismatched` MUST
- `bearer-empty-after-trim` MUST
- `require-auth-single-gate-call` MUST
- `require-auth-unauthenticated-401` MUST
- `require-auth-sets-three-vars` MUST
- `require-admin-reads-context-only` MUST
- `require-admin-forbidden-403` MUST
- `require-admin-admits-admin` MUST
- `require-admin-fails-closed` MUST
- `rate-limit-window-default` MUST
- `rate-limit-key-rightmost-hop` MUST
- `rate-limit-key-local-fallback` MUST
- `rate-limit-bucket-creation` MUST
- `rate-limit-increment-before-check` MUST
- `rate-limit-block-response` MUST
- `rate-limit-retry-after-header` MUST
- `rate-limit-pass-through` MUST
- `rate-limit-sweep-cadence` MUST
- `rate-limit-sweep-expiry` MUST
- `rate-limit-hard-cap-drop` MUST
- `rate-limit-instance-isolation` MUST
- `credential-value-opaque` MUST
- `authorization-decision-server-side` MUST
- `no-credential-logging` MUST
- `violation-outcomes-explicit` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gate` | `AuthGate` (from `../auth/port`) | required, caller-supplied | The credential resolver `requireAuth` wraps; injected per app, not read from environment by these two files. |
| `opts.max` | `number` | required, no default | Ceiling on requests per key per window before `rateLimit` starts responding `429`. Caller-supplied per mount point — `10` for `/auth/login`, `5` for `/auth/signup` in this backend's own wiring. |
| `opts.windowMs` | `number \| undefined` | `60000` (60 seconds) via `?? 60_000` | Fixed-window length in milliseconds for one `rateLimit(opts)` instance. |
| `MAX_BUCKETS` | module constant (`rate-limit.ts`) | `50_000` | Hard ceiling on distinct keys one `rateLimit` instance holds at once before its sweep drops the whole table. Not configurable per call. |
| `'admin'` tier literal | hardcoded string (`requireAdmin`) | fixed | The one tier value `requireAdmin` admits; not a configurable threshold. |

## Localization

Neither file uses a localization mechanism; every user-facing string is a hardcoded English literal returned in a JSON error body. Per this recipe's authoring rules, a hardcoded string is a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — `401` | `Unauthorized` | `requireAuth`, `gate.authenticate` resolves `null` |
| n/a — `403` | `Admin required` | `requireAdmin`, context `tier` is not `'admin'` |
| n/a — `429` | `Too many attempts — try again shortly` | `rateLimit`, bucket `count` exceeds `opts.max` |

