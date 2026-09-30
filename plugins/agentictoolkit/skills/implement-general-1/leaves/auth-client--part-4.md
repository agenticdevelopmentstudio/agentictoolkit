<!-- leaf: implement-general-1/auth-client--part-4 · source: auth-client.md -->

# Auth Client — continued (part 4)

**Rules** (cite as `implement-general-1/auth-client--part-4#<slug>`):

- `sso-switch-url` MUST
- `current-return-to` MUST
- `safe-return-to-rejects-cross-origin` MUST
- `stash-and-take-return-to-single-use` MUST
- `read-central-params` MUST
- `central-login-target-resolution` MUST
- `central-login-step-refuses-without-as-base` MUST
- `central-login-step-outcomes` MUST
- `central-login-step-request-shape` MUST
- `central-email-login` MUST
- `central-send-mfa-sms` MUST
- `central-complete-mfa-code` MUST
- `central-complete-mfa-passkey` MUST
- `central-passwordless-passkey` MUST
- `begin-link-provider-csrf-nonce` MUST
- `mfa-status-fetch` MUST
- `totp-enroll` MUST
- `totp-confirm` MUST
- `totp-remove` MUST
- `webauthn-list` MUST
- `webauthn-register-ceremony` MUST
- `webauthn-remove` MUST
- `recovery-codes-regenerate` MUST
- `preferred-method-set` MUST
- `account-security-authed` MUST
- `report-unexpected-status-gate` MUST
- `report-unexpected-dedup-window` MUST
- `report-auth-error-unconditional` MUST
- `report-never-throws` MUST
- `set-auth-error-reporter-hook` MUST
- `provider-label-known-and-fallback` MUST
- `oauth-error-message-known-codes-and-fallback` MUST
- `link-copy-provider-substitution` MUST

- **sso-switch-url**: `ssoSwitchUrl(destUrl, opts)` MUST return `destUrl`
  unchanged when no AS base is configured, and otherwise MUST return a
  `prompt=none` authorize URL whose `return` parameter is `destUrl` (`sso.ts`).
- **current-return-to**: `currentReturnTo()` MUST return
  `${pathname}${search}${hash}` of the current location, and MUST return
  `undefined` when `window` is `undefined` (`sso.ts`).
- **safe-return-to-rejects-cross-origin**: `safeReturnTo(raw)` MUST return
  `null` for a `null`/empty input or for a value that, resolved against the
  current origin, yields a different origin (SEC-M8 open-redirect defense —
  this also refuses a protocol-relative `//evil.com/x` form), and otherwise
  MUST return only the resolved URL's `pathname + search + hash`, never the
  raw string (`sso.ts`).
- **stash-and-take-return-to-single-use**: `stashReturnTo(returnTo)` MUST
  persist `returnTo` in sessionStorage under a fixed key, swallowing a thrown
  storage exception; `takeReturnTo()` MUST read and remove that key (single
  use) and MUST return the result of `safeReturnTo` on the stored value, or
  `null` when `window` is `undefined` or a storage exception is thrown
  (`sso.ts`).
- **read-central-params**: `readCentralParams(search)` MUST return `null`
  when the query has no `return` parameter, and otherwise MUST return
  `{ clientId, returnUrl }` with `clientId` defaulting to `'adh'` (`sso.ts`).
- **central-login-target-resolution**: `centralLoginTarget(opts)` MUST return
  the AS-relayed `{ clientId, returnUrl }` unchanged (via `readCentralParams`)
  when present; otherwise it MUST stash `opts.returnTo` when given and
  synthesize `{ clientId: opts.clientId, returnUrl:
  \`${origin}${opts.callbackPath ?? '/auth/callback'}\` }` (`sso.ts`).
- **central-login-step-refuses-without-as-base**: `centralLoginStep` MUST
  throw, without making any network request, when no AS base is configured
  for the given target — it MUST NOT silently fall back to the same-origin
  proxy the way `asEndpoint` does for other callers (`sso.ts`).
- **central-login-step-outcomes**: `centralLoginStep` MUST return the parsed
  `MfaChallenge` body on a `202` response; MUST navigate the top-level window
  to the response's `redirectUrl` and return `null` on any other OK response;
  and MUST throw `AuthHttpError` (status + extracted message/code, with
  fallback `` `Server error (${status})` `` for a `5xx` and `'Login failed'`
  otherwise) on a non-OK, non-`202` response (`sso.ts`).
- **central-login-step-request-shape**: Every `centralLoginStep` `POST` MUST
  include `credentials: 'include'` and a JSON body merging the caller's
  fields with `clientId` and `return` (`target.returnUrl`) (`sso.ts`).
- **central-email-login**: `centralEmailLogin(p)` MUST `POST`
  `{ identifier, password }` (plus `clientId`/`return`) to
  `/oauth/signin/login` via `centralLoginStep` (`sso.ts`).
- **central-send-mfa-sms**: `centralSendMfaSms(target, token)` MUST `POST`
  `{ token }` to `LOGIN_SMS_PATH` on the AS and throw `AuthHttpError` on a
  non-OK response, with fallback message `'Could not send a code.'` (`sso.ts`).
- **central-complete-mfa-code**: `centralCompleteMfaCode(target, token,
  method, code)` MUST `POST` `{ token, method, code }` to
  `/oauth/signin/login/mfa` via `centralLoginStep` (`sso.ts`).
- **central-complete-mfa-passkey**: `centralCompleteMfaPasskey(target,
  token)` MUST run the shared WebAuthn assertion ceremony against the AS's
  MFA options endpoint, then `POST` the assertion to
  `/oauth/signin/login/mfa/webauthn` via `centralLoginStep` (`sso.ts`).
- **central-passwordless-passkey**: `centralPasswordlessPasskey(target,
  identifier)` MUST run the passwordless assertion ceremony against the AS's
  passkey options endpoint, then `POST` the assertion to
  `/oauth/signin/login/webauthn` via `centralLoginStep` (`sso.ts`).
- **begin-link-provider-csrf-nonce**: `beginLinkProvider(opts)` MUST generate
  a random nonce (`crypto.randomUUID` when available, else a fallback), MUST
  stash it in sessionStorage under a fixed key BEFORE navigating, and MUST
  return `false` without navigating when the nonce cannot be stashed;
  otherwise it MUST navigate the top-level window to the AS
  `/oauth/signin/start` URL with `link=1`, `clientId`, `providerId`, `return`,
  and `linkNonce` query parameters, returning `true` (`sso.ts`).
- **mfa-status-fetch**: `getMfaStatus()` MUST `GET` `/api/account/mfa`
  through `authedJson` and return the parsed `MfaStatus` (`account-security.ts`).
- **totp-enroll**: `enrollTotp()` MUST `POST` `/api/account/mfa/totp/enroll`
  through `authedJson` and return `{ secret, otpauthUri }` (`account-security.ts`).
- **totp-confirm**: `confirmTotp(code)` MUST `POST` `{ code }` to
  `/api/account/mfa/totp/confirm` through `authedJson` (`account-security.ts`).
- **totp-remove**: `removeTotp()` MUST `DELETE`
  `/api/account/mfa/totp` through `authedRequest` (`account-security.ts`).
- **webauthn-list**: `listWebauthn()` MUST `GET` `/api/account/mfa/webauthn`
  through `authedJson` and return `{ items }` (`account-security.ts`).
- **webauthn-register-ceremony**: `registerWebauthn(kind, name)` MUST `POST`
  `{ kind }` to `/api/account/mfa/webauthn/register/options` through
  `authedJson`, run the browser's `startRegistration` ceremony with the
  returned options, then `POST` `{ token, response, name }` to
  `/api/account/mfa/webauthn/register/verify` through `authedJson`
  (`account-security.ts`).
- **webauthn-remove**: `removeWebauthn(id)` MUST `DELETE`
  `` `/api/account/mfa/webauthn/${encodeURIComponent(id)}` `` through
  `authedRequest` (`account-security.ts`).
- **recovery-codes-regenerate**: `regenerateRecoveryCodes()` MUST `POST`
  `/api/account/mfa/recovery/regenerate` through `authedJson` and return
  `{ codes }` (`account-security.ts`).
- **preferred-method-set**: `setPreferredMethod(method)` MUST `PUT`
  `{ method }` to `/api/account/mfa/preference` through `authedJson` and
  return `{ preferredMethod }` (`account-security.ts`).
- **account-security-authed**: Every `account-security.ts` operation MUST go
  through `authedJson`/`authedRequest` — Bearer-authed, with the same
  one-refresh-then-retry-on-401 waterfall as any other authed call — never a
  bare `fetch` (`account-security.ts` and every exported function).
- **report-unexpected-status-gate**: `reportUnexpectedAuthError(err,
  context)` MUST NOT report (to the injected sink or the console) an error
  whose numeric `.status` (duck-typed off any `Error`, not just this
  package's own `AuthHttpError`) is less than 500 — an expected 4xx from
  either this package's or a host's own error class (`report.ts`).
- **report-unexpected-dedup-window**: `reportUnexpectedAuthError` MUST report
  at most once per exact `` `${message}|${JSON.stringify(context)}` ``
  signature per 60000ms window (`REPORT_DEDUPE_WINDOW_MS`), dropping
  duplicate reports of the same signature within that window (`report.ts`).
- **report-auth-error-unconditional**: `reportAuthError(err, context)` MUST
  call the injected reporter (if one is registered) and MUST always
  `console.error(err, context)`, regardless of the error's status
  (`report.ts`).
- **report-never-throws**: `reportAuthError` MUST swallow any exception
  thrown by the injected reporter and MUST NOT propagate it to the caller
  (`report.ts`).
- **set-auth-error-reporter-hook**: `setAuthErrorReporter(fn)` MUST register
  `fn` as the sink `reportAuthError`/`reportUnexpectedAuthError` call; passing
  `null` MUST unregister it, leaving console-only reporting (`report.ts`).
- **provider-label-known-and-fallback**: `providerLabel(slug)` MUST return
  `'GitHub'` for `'github'`, `'Google'` for `'google'`, and otherwise the
  slug with only its first character capitalized (`labels.ts`).
- **oauth-error-message-known-codes-and-fallback**: `oauthErrorMessage(code)`
  MUST return a fixed message for `'account_exists'`, `'user_not_found'`, and
  `'signups_closed'`; MUST return `loginDisabledBody` for
  `'login_disabled'`; and MUST otherwise return the code verbatim inside
  `` `Sign-in failed (${code})` `` (`labels.ts`).
- **link-copy-provider-substitution**: Every account-linking modal copy
  function (`accountExistsLinkBody`, `linkConfirmTitle`/`Body`/`Action`,
  `linkInProgressTitle`/`Body`, `linkSuccessTitle`/`Body`,
  `linkAlreadyLinkedBody`, `linkStartFailedBody`) MUST substitute
  `providerLabel(providerSlug)` into its returned string (`labels.ts`).
