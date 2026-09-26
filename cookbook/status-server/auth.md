---
id: 735b4e58-bce9-4754-ad3f-bf0344fd4b32
title: Status Server Auth
domain: agentictoolkit://cookbook/status-server/auth
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Status backend''s auth layer: session cookie helpers, the default AuthGate
  (session/sts_-token/PEER_TOKEN/AUTH_DISABLED resolution), GitHub OAuth login, bcrypt
  password hashing, and the host-implementable AuthGate port.'
platforms:
- typescript
- web
tags:
- auth
- session
- oauth
- server
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/authentication
- agenticdevelopercookbook://guidelines/implementing/security/token-handling
- agenticdevelopercookbook://guidelines/implementing/security/sensitive-data
related: []
references:
- packages/web/packages/status-server/src/auth/cookie.ts (agentictoolkit)
- packages/web/packages/status-server/src/auth/default-adapter.ts (agentictoolkit)
- packages/web/packages/status-server/src/auth/github.ts (agentictoolkit)
- packages/web/packages/status-server/src/auth/password.ts (agentictoolkit)
- packages/web/packages/status-server/src/auth/port.ts (agentictoolkit)
- packages/web/packages/status-server/test/auth-gate.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/auth.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/github-oauth.int.test.ts (agentictoolkit)
- packages/web/packages/status-server/test/auth-edge.int.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Auth

## Overview

This is the status backend's authentication layer: five files under
`src/auth/` that together resolve who is calling the API, mint and read the
browser session, log a caller in through GitHub, and hash passwords.
`port.ts` defines the host-implementable `AuthGate` contract (the `authenticate`
function every gate implements, and the `AuthRequest`/`AuthVars` shapes it
reads and returns). `default-adapter.ts` is the shipped `AuthGate`:
session cookie, `sts_`-prefixed API bearer tokens, a machine `PEER_TOKEN`, and
an `AUTH_DISABLED` dev/e2e escape hatch, resolved in that order against this
package's own `Storage` port. `cookie.ts` owns the one browser cookie this
package sets, `status_auth`. `github.ts` is the GitHub OAuth login flow
(`/auth/github/start` and `/auth/github/callback`), including the
upsert-or-link logic that turns a GitHub identity into a `UserRecord`.
`password.ts` hashes and verifies passwords with bcrypt and exports a
precomputed dummy hash for timing-equalized login comparisons.

The Hono binding that turns a gate's resolution into an HTTP response
(`requireAuth`, `requireAdmin` in `../middleware/auth`) and the `Storage`
implementation these files call into (`AuthStore`/`TokenStore` in
`../storage/ports`, backed by libSQL) are external to this recipe's five
files; this recipe cites their documented contracts only where the auth
files depend on them, and never specifies their internals.

## Behavioral Requirements

### Session Cookie (cookie.ts)

- **session-cookie-name**: `setSessionCookie`, `clearSessionCookie`, and
  `readSessionCookie` MUST all operate on the cookie named `status_auth`
  (`SESSION_COOKIE`).
- **session-cookie-http-only**: `setSessionCookie` MUST set `httpOnly: true`
  on the session cookie.
- **session-cookie-same-site-lax**: `setSessionCookie` MUST set
  `sameSite: 'Lax'` on the session cookie, per the source comment, so the
  GitHub OAuth redirect back to `/home` still carries it.
- **session-cookie-secure-flag-from-config**: `setSessionCookie` MUST set the
  cookie's `secure` flag to the caller-supplied `config.cookieSecure` value,
  never a hardcoded constant, deferring the http-vs-https decision to the
  host.
- **session-cookie-path-root**: `setSessionCookie` and `clearSessionCookie`
  MUST scope the cookie to `path: '/'`.
- **session-cookie-max-age**: `setSessionCookie` MUST set `maxAge` to
  2,592,000 seconds (30 days), traced to `MAX_AGE_SECONDS = 30 * 24 * 60 * 60`.
- **session-cookie-clear**: `clearSessionCookie` MUST delete the
  `status_auth` cookie at `path: '/'`.
- **session-cookie-read-returns-undefined**: `readSessionCookie` MUST return
  `undefined` (not throw) when no `status_auth` cookie is present on the
  request.

### Default Auth Gate (default-adapter.ts)

- **auth-disabled-short-circuit**: When `config.authDisabled` is `true`,
  `authenticate` MUST resolve immediately to
  `{ tier: 'admin', user: null, token: null }` without evaluating the
  session, bearer-token, or peer-token checks.
- **session-checked-first**: `authenticate` MUST resolve the request's
  session cookie (via `storage.auth.resolveSession`) before attempting the
  bearer-token or peer-token checks, so a request carrying both a valid
  session cookie and an `Authorization` header authenticates from the
  cookie.
- **session-role-gate**: When `storage.auth.resolveSession` resolves a user
  whose `role` is `admin` or `viewer`, `authenticate` MUST resolve to
  `{ tier: 'admin' | 'view', user, token: null }` (`admin` role maps to tier
  `admin`, `viewer` role maps to tier `view`). MUST NOT resolve any tier for
  a `pending` role or any other role value; such a request falls through to
  the bearer-token check exactly as if no session existed.
- **bearer-token-prefix-gate**: `authenticate` MUST attempt an API-token
  lookup (`storage.tokens.validateApiToken`) only when the request's
  `Authorization: Bearer` value starts with the literal prefix `sts_`; MUST
  NOT call `validateApiToken` for a bearer value with any other prefix
  (including an absent header or an empty string).
- **bearer-token-role-mapping**: When `validateApiToken` resolves a token,
  `authenticate` MUST resolve to `{ tier: 'admin' | 'view', user: null, token }`,
  mapping the token's `role: 'admin'` to tier `admin` and `role: 'user'` to
  tier `view`.
- **bearer-token-invalid-terminal**: When a bearer value starts with `sts_`
  but `validateApiToken` resolves `null` (unknown, revoked, or expired),
  `authenticate` MUST resolve to `null` immediately; MUST NOT fall through
  to the peer-token check.
- **peer-token-path-restricted**: `authenticate` MUST grant the peer-token
  bearer only when the request path is exactly `/snapshot`; MUST NOT accept
  a matching `PEER_TOKEN` bearer on any other path.
- **peer-token-requires-config**: `authenticate` MUST NOT accept a
  peer-token bearer when `config.peerToken` is the empty string, regardless
  of the bearer value presented.
- **peer-token-constant-time-compare**: `authenticate` MUST compare the
  request's bearer value against `config.peerToken` with `timingSafeEqual`
  over two `Buffer`s of equal length, and MUST treat unequal-length buffers
  as a non-match without invoking `timingSafeEqual` on them
  (`safeEqual`'s `ab.length === bb.length && timingSafeEqual(ab, bb)`).
- **peer-token-tier**: A successful peer-token match MUST resolve to
  `{ tier: 'view', user: null, token: null }` — never tier `admin`.
- **unauthenticated-terminal-null**: When AUTH_DISABLED is off and the
  session, bearer-token, and peer-token checks all fail to resolve a
  caller, `authenticate` MUST resolve to `null`.
- **gate-never-throws**: `authenticate` MUST NOT throw for an
  unauthenticated or rejected caller; every non-matching branch resolves to
  `null` rather than raising.

### GitHub OAuth (github.ts)

- **github-start-requires-config**: `GET /auth/github/start` MUST respond
  `500` with message `'GitHub login is not configured'` when
  `config.github.clientId` or `config.publicBaseUrl` is empty, before
  generating any state or redirecting.
- **github-start-state-generation**: `GET /auth/github/start` MUST generate
  a fresh 16-byte random value, hex-encoded, as the OAuth `state` for every
  request (`randomBytes(16).toString('hex')`).
- **github-start-state-cookie**: `GET /auth/github/start` MUST store the
  generated state in a cookie named `gh_oauth_state`
  (`httpOnly: true`, `path: '/'`, `maxAge: 600`, `sameSite: 'Lax'`, `secure`
  from `config.cookieSecure`).
- **github-start-redirect**: `GET /auth/github/start` MUST redirect (`302`)
  to `https://github.com/login/oauth/authorize` with query parameters
  `client_id`, `redirect_uri` set to
  `${config.publicBaseUrl}/api/auth/github/callback`, `scope` set to
  `read:user user:email`, the generated `state`, and `allow_signup=true`.
- **github-callback-state-validated**: `GET /auth/github/callback` MUST
  respond `400` with message `'Invalid OAuth state'` when the request is
  missing the `code` query param, missing the `state` query param, missing
  the `gh_oauth_state` cookie, or when the query `state` does not exactly
  equal the cookie's value.
- **github-callback-state-cookie-cleared**: `GET /auth/github/callback`
  MUST delete the `gh_oauth_state` cookie unconditionally, before
  validating state, so the state cookie can never be reused across two
  callback requests.
- **github-fetch-timeout**: Every GitHub API call `exchangeCode` issues via
  `ghFetch` MUST carry a deadline of `config.github.fetchTimeoutMs`
  milliseconds when set, defaulting to `8000`, via
  `AbortSignal.timeout(...)`.
- **github-fetch-unreachable-maps-502**: When a GitHub fetch throws (a
  network failure, or an abort from the deadline above), `ghFetch` MUST
  respond `502` with message `'GitHub is unreachable'`.
- **github-token-exchange-failure-502**: `exchangeCode` MUST respond `502`
  with message `'GitHub token exchange failed'` when the access-token
  exchange response is not `ok`.
- **github-token-exchange-missing-token-401**: `exchangeCode` MUST respond
  `401` with message `'GitHub authorization failed'` when the token-exchange
  response is `ok` but its parsed body carries no `access_token`.
- **github-profile-fetch-failure-502**: `exchangeCode` MUST check the
  `GET /user` response's `ok` status before parsing its body, and MUST
  respond `502` with message `'Could not read the GitHub profile'` when it
  is not `ok`.
- **github-profile-missing-id-502**: `exchangeCode` MUST respond `502` with
  message `'GitHub profile is missing an id'` when the parsed profile's `id`
  is not a finite number.
- **github-email-fallback**: When the `GET /user` profile's `email` is
  falsy, `exchangeCode` MUST fetch `GET /user/emails` and adopt the first
  entry whose `primary` and `verified` are both `true`; when no such entry
  exists, or the `/user/emails` fetch is not `ok`, the resolved email MUST
  be `null`.
- **github-email-lowercased**: `exchangeCode` MUST lower-case a non-null
  resolved email before returning it.
- **github-display-name-fallback**: `exchangeCode` MUST set `displayName`
  to the profile's `name` when it is truthy, else the profile's `login`,
  else the literal string `'GitHub user'`.
- **github-callback-links-existing-email**: When no `UserRecord` matches the
  GitHub id and a resolved email matches an existing user, the callback MUST
  attach the GitHub id to that existing user (`attachGithubId`) rather than
  creating a second account for the same email.
- **github-callback-creates-new-user**: When no `UserRecord` matches the
  GitHub id and (no email was resolved, or the resolved email matches no
  existing user), the callback MUST create a new user whose `email`
  defaults to `` gh_<githubId>@users.noreply.github.com `` when the GitHub
  profile carries no email, whose `role` is `roleForEmail(email, config)`
  when an email was resolved and `'pending'` otherwise, and whose
  `githubId` is the GitHub profile's id.
- **github-callback-race-recovers**: When the `createUser`/`attachGithubId`
  call rejects with a unique-constraint violation (a concurrent first login
  racing for the same identity), the callback MUST recover by re-resolving
  the user via `findUserByGithubId`, then `findUserByEmail` when that
  misses, and MUST re-throw the original error only when neither resolves a
  user.
- **github-callback-sets-session-and-redirects**: On success, the callback
  MUST create a session for the resolved user (`storage.auth.createSession`),
  set it as the `status_auth` cookie via `setSessionCookie`, and redirect
  (`302`) to `/home`.

### Password Hashing (password.ts)

- **password-hash-cost**: `hashPassword` MUST hash with bcrypt cost factor
  10 (`COST = 10`), stated in the source comment to match the main backend's
  bcrypt cost.
- **password-hash-async**: `hashPassword` MUST return a `Promise<string>`
  produced by bcrypt's asynchronous `hash`, not a synchronous call.
- **password-verify**: `verifyPassword` MUST resolve to exactly the boolean
  `bcrypt.compare(plain, hash)` resolves to — `true` only on a matching
  plaintext/hash pair, `false` for every mismatch, including a malformed
  `hash` (which `bcrypt.compare` resolves `false` for rather than
  rejecting).
- **dummy-hash-precomputed**: The module MUST export `DUMMY_PASSWORD_HASH`,
  a real cost-10 bcrypt hash of the fixed string `'login-timing-equalizer'`,
  computed once at module load via `bcrypt.hashSync`, for a caller to
  compare against when no matching user or password hash exists, so a login
  response's timing does not reveal whether an email is registered.
  Consuming this value in a constant-effort login comparison is the login
  route's responsibility — external to this source, which only supplies the
  precomputed hash.

### Auth Gate Contract (port.ts)

- **auth-request-shape**: An `AuthRequest` MUST expose a readonly
  `path: string` and a `header(name: string): string | undefined` method;
  Hono's `c.req` satisfies this directly, so a Hono host constructs no
  adapter.
- **auth-vars-shape**: An `AuthVars` value MUST carry exactly three fields:
  `tier: 'view' | 'admin'`, `user: AuthUser | null`, and
  `token: TokenPrincipal | null`.
- **auth-gate-contract-never-throws-for-unauthenticated**: Per the
  `AuthGate` interface's doc comment, an implementation MUST resolve to
  `null` for an unauthenticated or rejected caller and MUST NOT throw or
  encode an HTTP status itself; translating a `null` resolution into a
  `401` is the Hono binding's job (`../middleware/auth`, external to this
  source).
- **auth-gate-host-swappable**: `AuthGate` MUST be implementable with no
  dependency on this package's `Storage` or `StatusConfig` types, so a host
  can substitute its own session store or SSO check without the HTTP layer
  above it changing.

### Security

This module is where every credential the status backend accepts — a
session cookie, an `sts_` API bearer token, the machine `PEER_TOKEN`, a
GitHub OAuth code, and a user's password — is resolved or minted. It is a
security-relevant recipe per this cookbook's Cookbook Compliance guideline,
so the concerns below are addressed explicitly rather than left to "platform
best practices."

- **session-token-opaque**: `cookie.ts`, `default-adapter.ts`, and
  `github.ts` MUST treat the session token carried in the `status_auth`
  cookie as an opaque string; none of them decodes, parses, or derives
  meaning from its bytes — its meaning is resolved entirely by
  `storage.auth.resolveSession`, external to these five files and not
  specified here.
- **credential-never-logged**: No function in these five files MUST log a
  raw bearer value, `PEER_TOKEN`, GitHub OAuth `client_secret`, GitHub
  access token, or password. `exchangeCode` holds the GitHub access token
  only in a local variable used to build two outbound request headers; none
  of these files contains a logging call of any kind (see Logging).
- **oauth-state-single-use**: Because `github-callback-state-cookie-cleared`
  deletes `gh_oauth_state` on the very first callback request that reads
  it, a replayed callback presenting the same `state` value MUST fail
  `github-callback-state-validated` on every request after the first,
  unless a fresh `/auth/github/start` reissued a matching cookie.
- **violation-resolves-to-an-explicit-outcome**: Every credential-rejection
  path in these five files MUST resolve to one specific, already-itemized
  outcome — `authenticate` resolving to `null` (unauthenticated-terminal-null,
  bearer-token-invalid-terminal), or one of the named `HTTPException`
  statuses in `github.ts` (`400`, `401`, `500`, `502`) — and MUST NOT
  silently continue as if the caller had succeeded.

Sensitive data in scope: the session token (opaque, cookie-only,
`httpOnly`), the `sts_` API bearer token (opaque, `Authorization` header
only), the `PEER_TOKEN` shared secret, the GitHub OAuth `client_secret` and
exchanged access token (server-side only, per `exchangeCode`'s doc comment:
"the secret never touches the browser"), and the user's password (bcrypt
hash only; the plaintext exists only for the duration of one
`hashPassword`/`verifyPassword` call). Storage of the password hash,
session-token hash, and API-token hash is the `AuthStore`/`TokenStore`
ports' job, external to these files; what these files guarantee is that
they never persist, log, or return a plaintext password or raw token
themselves. Transmission: the session cookie is `httpOnly` always and
`Secure` whenever `config.cookieSecure` is true (a host opts out only for
local/e2e http per `cookie.ts`'s comment); GitHub API calls are made to
hardcoded `https://` origins. Revocation of a session or API token
(`revokeSession`, `revokeApiToken`) is likewise the `Storage` ports' job,
called from outside these five files.

## Appearance

Not applicable — this is a server-side authentication module (cookie helpers, an auth gate, OAuth routes, and password hashing), not a visual component.

## States

Not applicable — this is a server-side authentication module, not a visual component; its runtime resolution branches are captured under Behavioral Requirements, not a visual-state table.

## Accessibility

Not applicable — this is a server-side authentication module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-auth-001 | session-cookie-name, session-cookie-http-only, session-cookie-same-site-lax, session-cookie-path-root, session-cookie-max-age | `setSessionCookie(c, 'tok123', { cookieSecure: true })` | `setCookie` is invoked with cookie name `'status_auth'`, value `'tok123'`, and options `{ httpOnly: true, secure: true, sameSite: 'Lax', path: '/', maxAge: 2592000 }` |
| status-server-auth-002 | session-cookie-secure-flag-from-config | `setSessionCookie(c, 'tok123', { cookieSecure: false })` | `setCookie` is invoked with `secure: false` |
| status-server-auth-003 | session-cookie-clear | `clearSessionCookie(c)` | `deleteCookie(c, 'status_auth', { path: '/' })` is invoked |
| status-server-auth-004 | session-cookie-read-returns-undefined | `readSessionCookie(c)` on a request with no `status_auth` cookie | Returns `undefined` |
| status-server-auth-005 | auth-disabled-short-circuit | `authenticate(req)` with `config.authDisabled = true`, no cookie, no header | Resolves `{ tier: 'admin', user: null, token: null }` — `auth.int.test.ts` › "AUTH_DISABLED=1 runs everyone as admin" |
| status-server-auth-006 | session-checked-first, session-role-gate | `authenticate(req)` where `req` carries a valid `viewer` session cookie | Resolves `{ tier: 'view', user, token: null }` — `auth.int.test.ts` › "lets a viewer read but 403s on an admin route" |
| status-server-auth-007 | session-role-gate | `authenticate(req)` where `req` carries a valid session cookie for a `pending` user, no other credential | Resolves `null` — `auth.int.test.ts` › "rejects a pending user with 401" |
| status-server-auth-008 | bearer-token-prefix-gate, bearer-token-role-mapping | `authenticate(req)` where `req` carries `Authorization: Bearer sts_validAdminToken` and `validateApiToken` resolves `{ role: 'admin', ... }` | Resolves `{ tier: 'admin', user: null, token }` |
| status-server-auth-009 | bearer-token-prefix-gate | `authenticate(req)` where `req` carries `Authorization: Bearer someOtherToken` (no `sts_` prefix) | `validateApiToken` is never called; resolves `null` when no session/peer credential also matches |
| status-server-auth-010 | bearer-token-invalid-terminal | `authenticate(req)` where the bearer starts with `sts_` and `validateApiToken` resolves `null` | Resolves `null` immediately; the peer-token branch is never evaluated |
| status-server-auth-011 | peer-token-path-restricted, peer-token-tier | `authenticate(req)` with `config.peerToken = 'peer'`, `req.path === '/snapshot'`, `Authorization: Bearer peer` | Resolves `{ tier: 'view', user: null, token: null }` — `auth.int.test.ts` › "accepts PEER_TOKEN only on /snapshot" |
| status-server-auth-012 | peer-token-path-restricted | Same peer bearer as above, `req.path === '/read'` | Resolves `null` (status `401` once bound by `requireAuth`) — same test, second assertion |
| status-server-auth-013 | peer-token-requires-config | `authenticate(req)` with `config.peerToken = ''`, `Authorization: Bearer anything`, `req.path === '/snapshot'` | Resolves `null` — the `if (peer && ...)` guard is falsy |
| status-server-auth-014 | peer-token-constant-time-compare | `authenticate(req)` with `config.peerToken = 'peer'`, bearer `'pee'` (shorter) | `safeEqual` returns `false` without calling `timingSafeEqual` (length mismatch short-circuits); resolves `null` |
| status-server-auth-015 | unauthenticated-terminal-null, gate-never-throws | `authenticate(req)` with no cookie, no `Authorization` header, `config.authDisabled = false` | Resolves `null`; the call does not throw — `auth.int.test.ts` › "rejects with 401 when no session" |
| status-server-auth-016 | github-start-requires-config | `GET /auth/github/start` with `GITHUB_OAUTH_CLIENT_ID` empty | `500` — `auth-edge.int.test.ts` › "500s when the client id is not configured" |
| status-server-auth-017 | github-start-requires-config | `GET /auth/github/start` with `PUBLIC_BASE_URL` unset | `500` — `auth-edge.int.test.ts` › "500s when PUBLIC_BASE_URL ... is unset" |
| status-server-auth-018 | github-start-state-generation, github-start-state-cookie, github-start-redirect | `GET /auth/github/start` with valid config | `302` to a `location` containing `github.com/login/oauth/authorize` and `redirect_uri=https%3A%2F%2Fstatus.example.com%2Fapi%2Fauth%2Fgithub%2Fcallback`; `set-cookie` contains `gh_oauth_state=` — `github-oauth.int.test.ts` › "start redirects to GitHub and sets a state cookie" |
| status-server-auth-019 | github-callback-state-validated | `GET /auth/github/callback?code=abc&state=WRONG` with a mismatched `gh_oauth_state` cookie | `400` — `github-oauth.int.test.ts` › "rejects a mismatched OAuth state" |
| status-server-auth-020 | github-callback-creates-new-user, github-callback-sets-session-and-redirects | Valid state; GitHub profile `{ id: 42, login: 'octocat', name: 'Octo Cat', email: 'Octo@Cat.com' }` | `302` to `/home`; a `status_auth` cookie is set; `GET /auth/me` with it reports `{ email: 'octo@cat.com', role: 'pending' }` — `github-oauth.int.test.ts` › "callback upserts a pending user and logs them in" |
| status-server-auth-021 | github-callback-creates-new-user | Same as above but with `ADMIN_EMAILS` containing the resolved email | Created user's `role` is `'admin'` — `auth-edge.int.test.ts` › "a github email in ADMIN_EMAILS is provisioned as admin" |
| status-server-auth-022 | github-callback-links-existing-email | GitHub profile email matches an existing password-account email, distinct `githubId` | Callback links to the existing account; exactly one user row exists afterward; the original password login still succeeds — `auth-edge.int.test.ts` › "logging in with the email of an existing password account LINKS, not duplicates" |
| status-server-auth-023 | github-callback-race-recovers | Two concurrent first callbacks for the same new GitHub identity, gated to create their rows at the same instant | Both resolve `302`; exactly one account exists for that identity afterward — `github-oauth.int.test.ts` › "two CONCURRENT first callbacks for the same identity both log in (no unique-violation 500)" |
| status-server-auth-024 | github-callback-race-recovers | Same as above but with a second, later run of the same flow (repeat login) | The account is reused, not re-created — `github-oauth.int.test.ts` › "a second callback with the same GitHub id reuses the account" |
| status-server-auth-025 | github-fetch-timeout, github-fetch-unreachable-maps-502 | `GITHUB_FETCH_TIMEOUT_MS=60`; GitHub's token-exchange endpoint never responds (only honors abort) | `502` within under 2000ms — `github-oauth.int.test.ts` › "a hung GitHub API cannot hold the pre-auth callback open — it 502s at the timeout" |
| status-server-auth-026 | github-token-exchange-failure-502 | Token-exchange response has `ok: false` | `502` with message `'GitHub token exchange failed'` |
| status-server-auth-027 | github-token-exchange-missing-token-401 | Token-exchange response `ok: true`, body `{}` (no `access_token`) | `401` with message `'GitHub authorization failed'` |
| status-server-auth-028 | github-profile-fetch-failure-502 | `GET /user` responds `401` with `{ message: 'Bad credentials' }` | `502`; no user with `githubId: 'undefined'` is ever created — `auth-edge.int.test.ts` › "a non-200 from /user fails the callback (502), never creating a githubId='undefined' account" |
| status-server-auth-029 | github-email-fallback, github-email-lowercased | GitHub profile `email: null`; `/user/emails` returns a verified primary `'fallback@gh.com'` | Resolved email is `'fallback@gh.com'` — `auth-edge.int.test.ts` › "private profile email falls back to the primary verified /user/emails address" |
| status-server-auth-030 | github-email-fallback | GitHub profile `email: null`; `/user/emails` returns only unverified/non-primary entries | Resolved email is `null`; the callback creates the user with the synthetic `gh_<id>@users.noreply.github.com` address and role `'pending'` |
| status-server-auth-031 | password-hash-cost, password-hash-async | `hashPassword('secret123')` | Resolves a bcrypt hash string beginning with the cost-10 modifier (`$2a$10$` / `$2b$10$`) |
| status-server-auth-032 | password-verify | `verifyPassword('secret123', <hash of 'secret123'>)` | Resolves `true` |
| status-server-auth-033 | password-verify | `verifyPassword('wrong', <hash of 'secret123'>)` | Resolves `false` |
| status-server-auth-034 | password-verify | `verifyPassword('secret123', 'not-a-bcrypt-hash')` | Resolves `false`, does not reject |
| status-server-auth-035 | dummy-hash-precomputed | `verifyPassword('anything', DUMMY_PASSWORD_HASH)` | Resolves `false` (the plaintext `'anything'` does not match `'login-timing-equalizer'`), taking bcrypt-comparable time to a real user lookup |
| status-server-auth-036 | auth-request-shape | A plain object `{ path: '/read', header: (n) => undefined }` passed as `req` to a custom `AuthGate.authenticate` | Type-checks and runs with no adapter, because Hono's `c.req` already satisfies `AuthRequest` — `auth-gate.test.ts` › the `headerGate` fixture |
| status-server-auth-037 | auth-gate-contract-never-throws-for-unauthenticated, auth-gate-host-swappable | A custom `AuthGate` (no `Storage`/`StatusConfig` dependency) wired into `requireAuth` | `200` when the gate resolves the caller, `401` when it resolves `null` — `auth-gate.test.ts` › both assertions |
| status-server-auth-038 | oauth-state-single-use, github-callback-state-cookie-cleared | Replay the exact same `gh_oauth_state` cookie and `state` value against `/auth/github/callback` a second time | `400` on the replay, because the first callback already deleted the cookie |
| status-server-auth-039 | credential-never-logged | Full GitHub login round-trip (start → callback) with `console.log`/`console.error` spied | No spy call includes the GitHub `client_secret`, the exchanged access token, or the session token's raw value — none of these five files contains a logging statement to begin with |
| status-server-auth-040 | violation-resolves-to-an-explicit-outcome | Every failure path exercised above (016, 017, 019, 025, 026, 027, 028) | Each resolves one specific status (`500`, `500`, `400`, `502`, `502`, `401`, `502`) — none resolves `200`/`302` |

## Edge Cases

- **Null and empty input**: a missing `code`, missing `state`, missing
  `gh_oauth_state` cookie, or an empty `Authorization` header all resolve to
  a defined outcome — `400` for the callback's missing/mismatched state
  (github-callback-state-validated), a fall-through (not a match) for an
  absent or non-`sts_` bearer (bearer-token-prefix-gate). MUST behave this
  way; there is no separate null-guard branch because the same
  falsy/undefined check does the gating.
- **Boundary values**: a bearer value of exactly `'Bearer '` (trailing
  space, empty token) slices to the empty string (`header.slice(7).trim()`);
  an empty string never starts with `sts_`, so it is treated identically to
  a missing bearer. `config.peerToken` set to the empty string MUST be
  treated as unset (peer-token-requires-config) even though it is a valid
  JavaScript string, not `null`/`undefined` — the check is a truthiness
  test, not a null check.
- **Concurrent access — the GitHub callback race**: two callbacks racing to
  create the first `UserRecord` for the same new GitHub identity are
  resolved deterministically by github-callback-race-recovers: the loser's
  unique-constraint violation is caught and re-resolved to the winner's row,
  never surfaced as a raw error. A resolved `attachGithubId` call that
  updates zero rows (for example because a concurrent request already
  attached the same id) falls back to the pre-attach `existing` record via
  `?? existing` and the callback proceeds to create a session for it
  regardless — the attach's success or failure has no observable effect on
  this login attempt, because the session is keyed on the resolved user id,
  not on whether the attach wrote a row.
- **Concurrent access — the default gate**: `authenticate` holds no shared
  mutable state between invocations (no module-level variable is written);
  concurrent calls for different requests never interfere with each other.
- **Error states — GitHub unreachable or erroring**: every distinguishable
  GitHub failure maps to a specific status, per the requirements above
  (`502` for an unreachable host or timeout, `502` for a failed token
  exchange or profile fetch, `401` for a token exchange that yields no
  token, `502` for a profile with no numeric id). None of these silently
  succeeds or logs a user in with partial data.
- **Error states — `storage.auth.resolveSession` or
  `storage.tokens.validateApiToken` rejects**: neither call in
  `default-adapter.ts` is wrapped in `try`/`catch`; a rejected promise
  propagates out of `authenticate` uncaught. The `AuthGate` interface's own
  doc comment scopes the "never throws" guarantee to an *unauthenticated*
  caller, not to a failed dependency, so this is consistent with the
  contract as documented, not a swallowed error — the Hono binding
  (`requireAuth`, external to this source) and its surrounding framework
  error handling own turning that rejection into an HTTP response.
- **Offline / disconnected state**: this package has no client-side
  connectivity to lose; its analogue is GitHub becoming unreachable
  mid-login, which is the Error states case above. There is no retry: each
  of `exchangeCode`'s three possible GitHub calls (`access_token`, `/user`,
  `/user/emails`) is issued exactly once per callback; a failure is mapped
  to a status and not retried by these files.
- **Race between OAuth start and callback on different requests**: a
  `/auth/github/start` call and a subsequent `/auth/github/callback` call
  are two separate HTTP requests correlated only by the `gh_oauth_state`
  cookie the browser carries between them; if a client calls `/callback`
  without ever calling `/start` (no state cookie), github-callback-state-validated
  rejects it with `400`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `config.authDisabled` | `boolean` (StatusConfig field) | host-supplied | Dev/e2e escape hatch; when `true`, `authenticate` grants tier `admin` to every request with no other check. Documented as "never true in production." |
| `config.cookieSecure` | `boolean` (StatusConfig field) | host-supplied | Whether the `status_auth` and `gh_oauth_state` cookies carry `Secure`. `cookie.ts`'s comment documents a `COOKIE_INSECURE=1` opt-out for http local dev/e2e; reading that environment variable is the host's env adapter's job, external to these five files. |
| `config.peerToken` | `string` (StatusConfig field) | host-supplied, empty disables | Shared secret a peer monitor presents as a bearer on `/snapshot` only. Empty string disables the peer-token path entirely. |
| `config.publicBaseUrl` | `string` (StatusConfig field) | host-supplied | Browser-facing origin used to build the GitHub OAuth `redirect_uri`; empty makes `/auth/github/start` respond `500`. |
| `config.github.clientId` | `string` (StatusConfig field) | host-supplied | GitHub OAuth app client id; empty makes `/auth/github/start` respond `500`. |
| `config.github.clientSecret` | `string` (StatusConfig field) | host-supplied | GitHub OAuth app client secret; used only server-side in `exchangeCode`'s POST body. |
| `config.github.fetchTimeoutMs` | `number \| null` (StatusConfig field) | `null` (code default `8000`) | Deadline for each outbound GitHub API call in `ghFetch`, via `AbortSignal.timeout`. |
| `config.adminEmails` | `readonly string[]` (StatusConfig field, consumed via `roleForEmail`, external to these five files but called from `github.ts`) | host-supplied | Lower-cased email allowlist auto-promoted to `role: 'admin'` on first GitHub login. |
| `SESSION_COOKIE` | module constant (`cookie.ts`) | `'status_auth'` | The one cookie name this package's session logic reads and writes. |
| `MAX_AGE_SECONDS` | module constant (`cookie.ts`) | `2592000` (30 days) | Fixed `maxAge` for the session cookie; not configurable per call. |
| `STATE_COOKIE` | module constant (`github.ts`) | `'gh_oauth_state'` | CSRF-nonce cookie name for the OAuth start/callback pair; fixed `maxAge: 600`. |
| `COST` | module constant (`password.ts`) | `10` | bcrypt cost factor for both `hashPassword` and `DUMMY_PASSWORD_HASH`. |
| `storage` | injected `Storage` (`AuthStore`/`TokenStore`) | required | Every user, session, and API-token lookup in `default-adapter.ts` and `github.ts` goes through this port; its implementation is external to these five files. |

## Deep Linking

Not applicable: none of these five files defines an application URL scheme; `/auth/github/start` and `/auth/github/callback` are two fixed HTTP routes on the status backend's own origin, not a deep-link target.

## Localization

None of these five files uses a localization mechanism; every user-facing
string is a hardcoded English literal. Per this recipe's authoring rules, a
hardcoded string is a fact to record, not a gap to excuse.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| n/a — `500` | `GitHub login is not configured` | `/auth/github/start`, missing `clientId`/`publicBaseUrl` |
| n/a — `400` | `Invalid OAuth state` | `/auth/github/callback`, missing/mismatched state |
| n/a — `502` | `GitHub is unreachable` | `ghFetch` catch (network failure or timeout) |
| n/a — `502` | `GitHub token exchange failed` | `exchangeCode`, non-`ok` token response |
| n/a — `401` | `GitHub authorization failed` | `exchangeCode`, `ok` response with no `access_token` |
| n/a — `502` | `Could not read the GitHub profile` | `exchangeCode`, non-`ok` `/user` response |
| n/a — `502` | `GitHub profile is missing an id` | `exchangeCode`, non-finite/non-numeric profile `id` |

## Accessibility Options

Not applicable: these five files have no UI and respond to none of Reduce Motion, Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: none of these five files consults a feature-flag system; `config.authDisabled` is a boolean `StatusConfig` field, already documented under Configuration and auth-disabled-short-circuit, not a flag-service lookup.

## Analytics

Not applicable: none of these five files emits an analytics or telemetry event of any kind.

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

## Logging

Not applicable: none of `cookie.ts`, `default-adapter.ts`, `github.ts`, `password.ts`, or `port.ts` contains a logging call at any level.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/auth/` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-authentication](agenticdevelopercookbook://compliance/security#secure-authentication) | passed | Security |
| [server-side-authorization](agenticdevelopercookbook://compliance/security#server-side-authorization) | passed | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [secure-transport](agenticdevelopercookbook://compliance/security#secure-transport) | passed | Security |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [token-lifecycle](agenticdevelopercookbook://compliance/security#token-lifecycle) | failed | Security |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [timeout-configuration](agenticdevelopercookbook://compliance/access-patterns#timeout-configuration) | passed | Access Patterns |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`secure-authentication` passes: GitHub OAuth 2.0 authorization-code flow,
implemented as a confidential (server-side) client — the `client_secret` is
exchanged only in `exchangeCode`'s server-to-server POST and never reaches
the browser, per the source's own comment. This check's PKCE requirement is
scoped to public clients; a confidential client authenticating with a
server-held secret is the case PKCE exists to substitute for, so its
absence here does not violate the check. `server-side-authorization`
passes: tier/role resolution happens entirely in `authenticate` and the
external `requireAdmin` binding, never trusted from the client.
`secure-storage` passes for what these five files themselves do: passwords
are bcrypt-hashed before crossing into storage, never held or returned
plaintext beyond one call; the `AuthStore` port's own documented contract
(external) states only a session token's sha256 is persisted, never the
raw value. `input-sanitization` passes: the only external strings these
files evaluate as more than opaque comparison values (`code`, `state`,
GitHub profile fields) are never interpolated into a query, shell command,
or rendered markup. `secure-transport` passes: every outbound GitHub call
targets a hardcoded `https://` origin. `secure-log-output` passes trivially
— per Logging, there is no log output to leak anything into.
`token-lifecycle` fails as written: the session cookie's `maxAge` is a
fixed 30 days, and neither the session cookie nor the `sts_` API token has
a refresh-rotation mechanism in these files — both are long-lived,
revocable credentials, not the short-lived-with-rotation shape this check
requires; see the Design Decisions entry above for the tradeoff, recorded
as fact rather than defended. `separation-of-concerns` passes: `port.ts`
defines the contract, `default-adapter.ts` the one implementation,
`github.ts` and `password.ts` are independent concerns the adapter and
external routes call into, and the Hono-status-code translation lives one
layer up, outside all five files. `unit-test-coverage` passes: the
sibling `test/` suite exercises the gate's resolution order
(`auth-gate.test.ts`, `auth.int.test.ts`), the GitHub OAuth flow including
its concurrency race and timeout (`github-oauth.int.test.ts`), and edge
cases (`auth-edge.int.test.ts`). `explicit-error-handling` is `partial`:
every GitHub HTTP failure maps to a specific status, but a failed
`/user/emails` fetch is not surfaced as an error at all — it silently
degrades to a `null` email and a synthetic account, a deliberate choice
(see Edge Cases) rather than an oversight, but it is still a case where a
dependency failure produces no distinguishable signal from "GitHub simply
has no public email for this user." `timeout-configuration` passes:
`ghFetch` bounds every outbound GitHub call with `AbortSignal.timeout`,
configurable via `config.github.fetchTimeoutMs`. `no-pii-in-logs` passes
the same way `secure-log-output` does — there is no log output in these
files to carry PII.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
