<!-- leaf: implement-general-1/auth-client--part-5 · source: auth-client.md -->

# Auth Client — continued (part 5)

**Rules** (cite as `implement-general-1/auth-client--part-5#<slug>`):

- `access-token-transmission` MUST
- `refresh-token-never-persisted` MUST
- `open-redirect-violation-handling` MUST
- `link-csrf-violation-handling` MUST
- `token-subject-not-an-authorization-decision` MUST
- `platform-i18n-layer-decide-design-choice-outside` MUST — Every string above is hardcoded English with no lookup table, ICU message, or locale parameter anywhere in these 11 …

### Security

`auth-client` is a security-relevant recipe: it handles bearer session
tokens, an HttpOnly refresh cookie, second-factor secrets, WebAuthn
ceremonies, and cross-site redirect targets. The following requirements are
this recipe's dedicated security treatment; each restates or cross-references
a requirement above under its security framing rather than duplicating its
mechanics.

- **sensitive-data-classification**: The following are sensitive within this
  contract: the access token (bearer credential), the deliberately-never-read
  refresh token, the cached `AuthUser` object, TOTP secrets/`otpauthUri`,
  WebAuthn registration/assertion payloads, recovery codes, the CSRF link
  nonce (`LINK_NONCE_KEY`), and the return-to path (open-redirect surface via
  **safe-return-to-rejects-cross-origin**).
- **access-token-transmission**: The access token MUST be attached only via
  the `Authorization: Bearer` header (**authed-fetch-bearer-attach**) and
  MUST NEVER appear in a URL query string, a log message, or a
  `reportAuthError`/`reportUnexpectedAuthError` context value (`report.ts`'s
  `ErrorContext` type is explicitly scalars-only — see
  **report-unexpected-status-gate**).
- **refresh-token-never-persisted**: The refresh token MUST NOT be read from
  a backend response or written to any client-side storage —
  **tokens-from-response-refresh-token-blanked** always blanks it to `''`;
  refresh and revoke are cookie-first against an HttpOnly, server-controlled
  cookie this package never reads.
- **open-redirect-violation-handling**: A stashed or query-supplied
  return-to value that resolves to a different origin MUST be rejected
  outright (`null`), never partially trusted or redirected to — see
  **safe-return-to-rejects-cross-origin**.
- **link-csrf-violation-handling**: A provider-link completion MUST be
  refused (fails closed, no navigation) when its CSRF nonce cannot be
  stashed before the redirect — see **begin-link-provider-csrf-nonce**; a
  completion callback whose returned nonce does not match the stashed one is
  rejected by the completing consumer (outside this package's own files, but
  the nonce this package mints and stashes is the entire defense).
- **token-subject-not-an-authorization-decision**: `readTokenSubject`'s
  unverified, locally-decoded `sub` claim MUST be used only for client-side
  cache scoping (keying cached data to the current principal so an account
  switch in another tab cannot serve stale rows) and MUST NEVER be used as an
  authorization decision — the token is not signature-verified client-side
  (`tokens.ts`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storageKey` | `string` (via `configureAuth`) | `'auth_tokens'` | localStorage key for the persisted `AuthTokens` bundle; the cached-user key is `` `${storageKey}:user` `` |
| `refreshPath` | `string` (via `configureAuth`) | `'/api/auth/refresh'` | Same-origin path the cookie-first refresh POST targets |
| `NEXT_PUBLIC_AUTH_API_URL` | environment variable | unset | Absolute AS base URL; when unset, every AS-bound call falls back to the same-origin `/api` proxy (or, for `centralLoginStep`, refuses outright) |
| `DEFAULT_EXCHANGE_PATH` | exported constant | `'/api/oauth/signin/exchange'` | Default path `exchangeSsoCode` posts the one-time code to |
| `EXCHANGE_NETWORK_RETRY_DELAY_MS` | internal constant | `750` | Pause before `exchangeSsoCode`'s single network-failure retry |
| `LOSER_RECHECK_DELAY_MS` | internal constant | `300` | Pause a losing concurrent refresh waits before re-reading storage |
| `REPORT_DEDUPE_WINDOW_MS` | internal constant | `60000` | Per-signature throttle window for `reportUnexpectedAuthError` |
| `PREFLIGHT_TIMEOUT_MS` | internal constant | `2000` | Abort timeout for `preflightSsoReturn`'s GET |
| `LOGIN_SMS_PATH` / `MFA_WEBAUTHN_OPTIONS_PATH` / `PASSKEY_OPTIONS_PATH` | exported constants | `'/auth/login/mfa/sms/send'`, `'/auth/login/mfa/webauthn/options'`, `'/auth/login/webauthn/options'` | Shared login-time MFA/passkey paths, reused by both the site (`mfa.ts`) and central (`sso.ts`) login clients |
| `DEFAULT_CALLBACK_PATH` | internal constant | `'/auth/callback'` | Default in-site route the AS bounces the exchange code back to |
| `clientId` | caller-supplied option | `'adh'` | OAuth client id sent on every AS-bound navigation/POST |
| `setAuthErrorReporter` | injected hook | `null` | Host-supplied sink for `reportAuthError`/`reportUnexpectedAuthError`; `null` means console-only |
| `setAuthRetryMarker` | injected hook | `null` | Host-supplied callback tagging the exact `RequestInit` of a retried request |
| `onSessionChange` | injected subscription | n/a | Caller-registered callback invoked on every token write/clear |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `tokens.missingToken` | Token response missing token/accessToken | Thrown by `tokensFromResponse` (`tokens.ts`) |
| `client.exchangeFallback` | Sign-in failed | `exchangeSsoCode`'s fallback error message (`client.ts`) |
| `client.httpFallback` | HTTP {status} | `authedFetch`'s fallback error message (`client.ts`) |
| `client.emptyResponse` | Unexpected empty response (204 No Content); use authedRequest for endpoints with no body | `authedJson`'s 204 guard (`client.ts`) |
| `mfa.passkeyCheckFailed` | Could not start the passkey check. | `assertSecondFactor`'s fallback (`mfa.ts`) |
| `mfa.noPasskey` | No passkey is available for this account. | `assertPasswordlessPasskey`'s fallback (`mfa.ts`) |
| `mfa.smsSendFailed` | Could not send a code. | `requestLoginSms`'s fallback (`mfa.ts`) |
| `mfa.codeMismatch` | That code didn't match. | `completeLoginCode`'s fallback (`mfa.ts`) |
| `mfa.passkeyVerifyFailed` | Passkey verification failed. | `completeLoginPasskey`'s fallback (`mfa.ts`) |
| `mfa.passkeyLoginFailed` | Passkey login failed. | `passwordlessPasskeyLogin`'s fallback (`mfa.ts`) |
| `labels.accountExistsTitle` | Account already exists | `accountExistsTitle` (`labels.ts`) |
| `labels.oauthAccountExists` | An account already exists for this email — sign in with your email and password instead. | `oauthErrorMessage('account_exists')` (`labels.ts`) |
| `labels.linkFailedTitle` | Couldn't connect account | `linkFailedTitle` (`labels.ts`) |
| `labels.loginDisabledTitle` / `loginDisabledBody` | We're not open just yet / The Hub isn't quite ready for visitors yet — please check back soon. | Shown when `user_login_disabled` is on (`labels.ts`) |
| `sso.misconfigured` | Sign-in is misconfigured on this site: NEXT_PUBLIC_AUTH_API_URL was not set when it was built... | `centralLoginStep`'s thrown message when no AS base is configured (`sso.ts`) |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in these 11 files — there is no localization
mechanism in this component at all. This is a plain fact about the source,
not a gap: a port to a platform with an i18n layer MUST decide, as a design
choice outside this contract, whether and how to route these strings through
it.

## Privacy

- **Data collected**: The access token (a bearer credential, not itself
  PII); a cached `AuthUser` (`id`, `email`, `name`, `avatarUrl`, `slug`,
  `capabilities`, `authMethods`, `attributes`) written by `writeUser`;
  TOTP secrets/`otpauthUri` and WebAuthn ceremony payloads pass through this
  module in memory only and are never persisted by any file in it; recovery
  codes are returned once by `regenerateRecoveryCodes` and are likewise not
  persisted here. The refresh token is explicitly never read or persisted
  (**refresh-token-never-persisted**). `reportAuthError`'s `ErrorContext` is
  typed scalars-only (no PII, request bodies, or ids) by declared contract
  (`report.ts`).
- **Storage**: The access token and cached user live in `localStorage` under
  `authConfig().storageKey` and `` `${storageKey}:user` `` as plaintext JSON
  — readable by any script running on the page (the standard SPA
  localStorage/XSS tradeoff; this contract does not encrypt or otherwise
  protect that value beyond keeping the refresh token out of it). The CSRF
  link nonce (`adh_link_nonce`), the post-login return-to path
  (`adh_sso_return_to`), the once-per-tab restore guard (`adh_sso_checked`),
  and the pending-link intent (`adh_pending_link`) live in `sessionStorage`,
  scoped to one tab and cleared when it closes.
- **Transmission**: The access token is sent only via the `Authorization:
  Bearer` header (see Security). `credentials: 'include'` is sent to the
  refresh endpoint and every central-login/MFA endpoint so the HttpOnly
  refresh/central-session cookies travel with the request; `preflightSsoReturn`
  deliberately sends `credentials: 'omit'` because its question needs no
  session context. This module never reads the HttpOnly refresh or central
  session cookies itself — only the server sets and reads them.
- **Retention**: The access token and cached user persist in `localStorage`
  until an explicit `clearTokens()` (logout, or a refresh that gives up —
  **refresh-failure-clears-when-unresolved**) or until the browser's own
  storage is cleared; this module enforces no client-side TTL on the access
  token — expiry is discovered only when the server returns a `401`, which
  triggers a refresh attempt.

