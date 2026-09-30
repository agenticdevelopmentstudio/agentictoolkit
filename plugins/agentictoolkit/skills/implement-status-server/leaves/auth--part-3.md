<!-- leaf: implement-status-server/auth--part-3 · source: status-server-auth.md -->

# Status Server Auth — continued (part 3)

**Rules** (cite as `implement-status-server/auth--part-3#<slug>`):

- `password-hash-cost` MUST
- `password-hash-async` MUST
- `password-verify` MUST
- `dummy-hash-precomputed` MUST
- `auth-request-shape` MUST
- `auth-vars-shape` MUST
- `auth-gate-contract-never-throws-for-unauthenticated` MUST
- `auth-gate-host-swappable` MUST
- `session-token-opaque` MUST
- `credential-never-logged` MUST
- `oauth-state-single-use` MUST
- `violation-resolves-to-an-explicit-outcome` MUST

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

