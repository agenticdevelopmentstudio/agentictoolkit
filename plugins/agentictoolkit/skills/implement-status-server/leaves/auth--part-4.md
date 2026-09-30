<!-- leaf: implement-status-server/auth--part-4 · source: status-server-auth.md -->

# Status Server Auth — continued (part 4)

## Privacy

- **Data collected**: a GitHub profile's `id`, `email`, and display name
  (`name`/`login`) during OAuth login (`github.ts`); a plaintext password
  for the duration of one `hashPassword`/`verifyPassword` call
  (`password.ts`); an opaque session token and an opaque `sts_` API bearer
  token, read but never decoded (`cookie.ts`, `default-adapter.ts`).
- **Storage**: none of these five files writes to persistent storage
  directly — they call the `AuthStore`/`TokenStore` ports
  (`createUser`, `attachGithubId`, `createSession`, `validateApiToken`),
  whose implementation (hashing, table layout) is external and not
  specified here. `toAuthUser`, the port's own projection (external to
  these files), drops the password hash before a `UserRecord` is exposed as
  an `AuthUser`.
- **Transmission**: the session and OAuth-state cookies are `httpOnly`
  always, and carry `Secure` whenever `config.cookieSecure` is true; a host
  opts out only for local/e2e http, per `cookie.ts`'s documented
  `COOKIE_INSECURE` escape hatch (read by the external env adapter, not
  these files). GitHub API calls in `github.ts` are made to hardcoded
  `https://` origins.
- **Retention**: the session cookie has a fixed 30-day `maxAge`
  (`MAX_AGE_SECONDS`) and the OAuth-state cookie a fixed 600-second
  `maxAge`; both are set unconditionally by these files with no
  configurable override. Server-side session/token expiry and revocation
  (`revokeSession`, `revokeApiToken`) are the `Storage` ports' job, called
  from outside these five files.

## Platform Notes

- **React/Web** (source platform): the five files live under
  `packages/web/packages/status-server/src/auth/`, on top of Hono
  (`hono/cookie`, `hono/http-exception`, `hono/utils/cookie`) and Node's
  built-in `node:crypto` (`randomBytes`, `timingSafeEqual`) and global
  `fetch`/`AbortSignal.timeout`. Password hashing uses the `bcryptjs`
  package. The Hono binding that turns an `AuthGate` resolution into an
  HTTP response (`requireAuth`/`requireAdmin`) lives one directory over, in
  `../middleware/auth`, and is not part of this recipe's sources.
- **SwiftUI / AppKit / UIKit**: an Apple client of this backend is a
  consumer, not a re-implementer, of this auth layer — it calls the status
  API with `URLSession`, attaching the session cookie (via
  `HTTPCookieStorage`) or an `sts_` bearer token in an `Authorization`
  header exactly as `default-adapter.ts` expects to receive it. A future
  Apple-side re-implementation of this SERVER logic (a companion Swift
  backend, e.g. Vapor or Hummingbird) would model `AuthGate` as a Swift
  `protocol` with an `async throws` `authenticate(_:) -> AuthVars?` method,
  `AuthVars`/`AuthUser`/`TokenPrincipal` as `Sendable` `struct`s, the
  constant-time peer-token compare via `CryptoKit`'s
  constant-time byte comparison (or a hand-rolled loop, since Foundation has
  no direct `timingSafeEqual` equivalent), and password hashing via a
  bcrypt Swift package at the same cost factor 10.
- **Compose**: same client relationship as SwiftUI/AppKit/UIKit — an
  Android client calls the backend directly (OkHttp/Retrofit), attaching
  its own cookie jar or bearer header; it has no server-side gate to port.
- **WinUI 3**: a WinUI 3 desktop app is likewise a client, calling the
  status API with `HttpClient` and attaching `Authorization: Bearer
  <sts_ token>` or forwarding the session cookie via
  `HttpClientHandler.CookieContainer`. If a future product needed to
  reimplement this AuthGate pattern on a .NET backend (ASP.NET Core Minimal
  API), the port maps as: the `AuthGate` interface becomes a C# interface
  `Task<AuthVars?> AuthenticateAsync(HttpRequest req)`; the session cookie
  is set with `CookieOptions { HttpOnly = true, Secure = config.CookieSecure,
  SameSite = SameSiteMode.Lax, Path = "/", MaxAge = TimeSpan.FromDays(30) }`;
  the `PEER_TOKEN` constant-time compare uses
  `CryptographicOperations.FixedTimeEquals` over two equal-length byte
  spans (matching `safeEqual`'s length-then-timing-safe-compare shape);
  password hashing uses `BCrypt.Net-Next` at work factor 10; and the GitHub
  OAuth exchange is a hand-rolled `HttpClient` POST/GET sequence (no
  built-in GitHub SDK), reusing `System.Text.Json` for the token/profile
  response shapes and `HttpClient`'s per-request `CancellationToken`
  (mapped from a `TimeSpan`) as the `AbortSignal.timeout` analogue.

## Design Decisions

- **Decision**: check the session cookie before the `sts_` bearer token in
  `authenticate`'s resolution order.
  **Rationale**: the source comment states the status BFF (a proxy external
  to these five files) forwards the session cookie's *value* verbatim as an
  inert `Authorization: Bearer` header on some requests; gating the bearer
  branch to values that start with `sts_` and checking the cookie first
  means a dashboard request authenticated by cookie never pays a token
  lookup against that inert forwarded value, and never risks the forwarded
  cookie value being mistaken for an API token.
  **Approved**: pending
- **Decision**: compare the `PEER_TOKEN` bearer with `timingSafeEqual`, but
  compare the OAuth `state` value with plain `!==`.
  **Rationale**: `PEER_TOKEN` is a long-lived shared secret worth protecting
  from a timing side-channel; the OAuth `state` is a single-use, freshly
  generated nonce whose possession already required reading the
  `gh_oauth_state` cookie set on the same login attempt, so a timing
  side-channel on the comparison itself adds no practical attack surface.
  **Approved**: pending
- **Decision**: recover from a `createUser`/`attachGithubId` unique-violation
  by re-querying instead of propagating the raw error.
  **Rationale**: the source comment explains this directly — the loser of a
  concurrent first-login race for the same identity should log into the
  winner's row rather than fail with a raw database error; the old
  human-token login paths this replaced did not have this problem because
  they had no signup race, but GitHub-identity signup does.
  **Approved**: pending
- **Decision**: export a precomputed `DUMMY_PASSWORD_HASH` from
  `password.ts` rather than let a login route skip the bcrypt comparison
  entirely when no user is found.
  **Rationale**: the module comment states this directly: comparing against
  a real cost-10 hash even when no such user/hash exists keeps a login
  response's timing from revealing whether an email is registered; computing
  it once at module load (rather than per request) avoids paying bcrypt's
  cost repeatedly for a value that never changes.
  **Approved**: pending
- **Decision**: use a long-lived (30-day), revocable session cookie rather
  than a short-lived token with refresh rotation.
  **Rationale**: not stated in source; this is a plain fact about the
  code's actual behavior (see the `token-lifecycle` compliance result
  below), not an idealized rationale invented for this recipe.
  **Approved**: pending
