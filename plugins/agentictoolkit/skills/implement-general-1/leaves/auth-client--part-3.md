<!-- leaf: implement-general-1/auth-client--part-3 · source: auth-client.md -->

# Auth Client — continued (part 3)

**Rules** (cite as `implement-general-1/auth-client--part-3#<slug>`):

- `authed-request-discards-body` MUST
- `auth-http-error-shape` MUST
- `extract-error-message-precedence` MUST
- `extract-error-code-precedence` MUST
- `read-error-message-single-parse` MUST
- `exchange-sso-code-request-shape` MUST
- `exchange-sso-code-network-retry-once` MUST
- `exchange-sso-code-no-http-retry` MUST
- `exchange-sso-code-success-result` MUST
- `exchange-sso-code-failure-throws` MUST
- `link-provider-routes-to-as-host` MUST
- `link-provider-authed-post` MUST
- `retry-marker-hook` MUST
- `webauthn-assertion-ceremony-shared` MUST
- `assert-second-factor-body` MUST
- `assert-passwordless-passkey-body` MUST
- `request-login-sms` MUST
- `complete-login-code` MUST
- `complete-login-passkey` MUST
- `passwordless-passkey-login` MUST
- `begin-login-navigation` MUST
- `authorize-url-shape` MUST
- `provider-signin-url-shape` MUST
- `sso-hint-cookie-check` MUST
- `sso-checked-guard-tolerates-storage-failure` MUST
- `silent-restore-guard-order` MUST
- `silent-restore-evidence` MUST
- `registrable-domain-apex-comparison` MUST
- `preflight-sso-return-contract` MUST
- `preflight-sso-return-timeout` MUST
- `begin-silent-login-flow` MUST
- `parse-inbound-sso` MUST
- `strip-sso-fragment-preserves-other-keys` MUST
- `sso-logout-navigation` MUST

- **authed-request-discards-body**: `authedRequest` MUST perform an
  `authedFetch` and resolve `void`, discarding the response body
  (`client.ts`).
- **auth-http-error-shape**: `AuthHttpError` MUST extend `Error`, MUST expose
  a `status: number` and an optional `code?: string`, and MUST set
  `name` to `'AuthHttpError'` (`client.ts`).
- **extract-error-message-precedence**: `extractErrorMessage(body, fallback)`
  MUST return, in order: a string top-level `error`; else a string `message`
  on a nested `error` object; else a string top-level `message`; else
  (RFC 9457 problem+json) `detail` when the body also has a string `title`
  and a numeric `status`; else a string `title`; else `fallback` (`client.ts`).
- **extract-error-code-precedence**: `extractErrorCode(body)` MUST return a
  string `code` from a nested `error.code`, else a top-level `code`, else
  `undefined` (`client.ts`).
- **read-error-message-single-parse**: `readErrorMessage(res, fallback)` MUST
  parse the response body exactly once (`res.json().catch(() => null)`) and
  pass that single parsed value to `extractErrorMessage` (`client.ts`).
- **exchange-sso-code-request-shape**: `exchangeSsoCode(code, exchangePath)`
  MUST `POST` `{ code }` as JSON to `exchangePath`, which MUST default to
  `DEFAULT_EXCHANGE_PATH` (`'/api/oauth/signin/exchange'`) (`client.ts`).
- **exchange-sso-code-network-retry-once**: `exchangeSsoCode` MUST retry the
  `POST` exactly once, after a 750ms delay
  (`EXCHANGE_NETWORK_RETRY_DELAY_MS`), only when the first attempt fails at
  the network level (`fetch` itself throws/rejects), and MUST propagate the
  second attempt's outcome — including a second network failure — without
  retrying again (`client.ts`).
- **exchange-sso-code-no-http-retry**: `exchangeSsoCode` MUST NOT retry when
  the server returns any HTTP response, including a non-OK one; only a
  network-level failure triggers the retry (`client.ts`).
- **exchange-sso-code-success-result**: On a `2xx` response, `exchangeSsoCode`
  MUST return `{ tokens, user }`, where `tokens` is built via
  `tokensFromResponse` and `user` is the response body's `user` field
  (`client.ts`).
- **exchange-sso-code-failure-throws**: On a non-OK response,
  `exchangeSsoCode` MUST throw `AuthHttpError` carrying the status and the
  message/code extracted from the parsed body, with fallback message
  `'Sign-in failed'` (`client.ts`).
- **link-provider-routes-to-as-host**: `linkProvider(input, opts)` MUST
  resolve its target via `asEndpoint('/auth/link-provider', opts.authApiBase)`
  — the authorization server directly, never a hard-coded same-origin path —
  falling back to `/api/auth/link-provider` only when no AS base is
  configured (`client.ts`).
- **link-provider-authed-post**: `linkProvider` MUST `POST` `input`
  (`clientSlug`, `providerSlug`, `code`, `redirectUri`) as JSON through
  `authedRequest` (Bearer-authed, with the same one-refresh-then-retry
  waterfall as any other authed call), and MUST resolve on success or throw
  `AuthHttpError` on failure (`client.ts`).
- **retry-marker-hook**: `setAuthRetryMarker(fn)` MUST register `fn` to be
  invoked with the exact `RequestInit` object handed to `fetch` for a
  retried request — a post-refresh retry in `authedFetch`, or the
  network-failure retry in `exchangeSsoCode`; passing `null` MUST unregister
  it, and with no function registered, marking MUST be a silent no-op
  (`client.ts`).
- **webauthn-assertion-ceremony-shared**: The shared `runAssertion` helper
  MUST `POST` `body` to `optionsUrl`, throw `Error(optionsError)` (via
  `readErrorMessage`) on a non-OK response, otherwise run the browser's
  `startAuthentication` ceremony with the returned `options` and return
  `{ token, response }` (`mfa.ts`).
- **assert-second-factor-body**: `assertSecondFactor(token, optionsUrl)` MUST
  run the assertion ceremony with body `{ token }` and fallback error `'Could
  not start the passkey check.'` (`mfa.ts`).
- **assert-passwordless-passkey-body**: `assertPasswordlessPasskey(identifier,
  optionsUrl)` MUST run the assertion ceremony with body `{ identifier }` and
  fallback error `'No passkey is available for this account.'` (`mfa.ts`).
- **request-login-sms**: `requestLoginSms(token)` MUST `POST` `{ token }` to
  `` `/api${LOGIN_SMS_PATH}` `` and MUST throw on a non-OK response, with
  fallback message `'Could not send a code.'` (`mfa.ts`).
- **complete-login-code**: `completeLoginCode(token, method, code)` MUST
  `POST` `{ token, method, code }` to `/api/auth/login/mfa` and return the
  parsed response on success, else throw with fallback `'That code didn't
  match.'` (`mfa.ts`).
- **complete-login-passkey**: `completeLoginPasskey(token)` MUST run
  `assertSecondFactor` against `` `/api${MFA_WEBAUTHN_OPTIONS_PATH}` ``, then
  `POST` the resulting assertion to `/api/auth/login/mfa/webauthn`, returning
  the parsed response or throwing with fallback `'Passkey verification
  failed.'` (`mfa.ts`).
- **passwordless-passkey-login**: `passwordlessPasskeyLogin(identifier)` MUST
  run `assertPasswordlessPasskey` against `` `/api${PASSKEY_OPTIONS_PATH}` ``,
  then `POST` the resulting assertion to `/api/auth/login/webauthn`,
  returning the parsed response or throwing with fallback `'Passkey login
  failed.'` (`mfa.ts`).
- **begin-login-navigation**: `beginLogin(opts)` MUST be a no-op when
  `window` is `undefined`; otherwise it MUST stash `opts.returnTo` when given
  and navigate the top-level window (`window.location.href`) to the AS
  `/oauth/signin/authorize` URL for `opts.clientId` (default `'adh'`) and a
  return URL equal to `${origin}${opts.callbackPath ?? '/auth/callback'}`
  (`sso.ts`).
- **authorize-url-shape**: `buildAuthorizeUrl` MUST resolve
  `/oauth/signin/authorize` via `asEndpoint` and MUST include `clientId` and
  `return` query parameters, plus a `prompt` parameter only when one is given
  (`sso.ts`).
- **provider-signin-url-shape**: `providerSigninUrl(opts)` MUST resolve
  `/oauth/signin/start` via `asEndpoint` with `clientId`, `providerId`, and
  `return` query parameters (`sso.ts`).
- **sso-hint-cookie-check**: `ssoHintPresent()` MUST return `true` if and only
  if a cookie named `adh_sso_hint` is present, and MUST return `false` when
  `document` is `undefined` (`sso.ts`).
- **sso-checked-guard-tolerates-storage-failure**: `markSsoChecked()` and
  `clearSsoChecked()` MUST set/remove the `adh_sso_checked` sessionStorage
  flag and MUST swallow a thrown storage exception without propagating it
  (`sso.ts`).
- **silent-restore-guard-order**: `shouldSilentRestore(initialHash)`
  MUST return `false`, checked in this order, when: `window` is `undefined`;
  `initialHash` carries an inbound SSO code/error (mid-flow); this tab has
  already checked (`ssoCheckedThisTab()`); or no AS base is configured — all
  before any hint or cross-apex evidence is consulted (`sso.ts`).
- **silent-restore-evidence**: Given none of the guards above apply,
  `shouldSilentRestore` MUST return `true` when the SSO hint cookie is
  present, and otherwise MUST return `true` if and only if the site is
  cross-apex with the configured AS host (`sso.ts`).
- **registrable-domain-apex-comparison**: `isCrossApex` MUST compare the last
  two dot-separated labels of the AS host and the current hostname, treating
  them as different registrable domains if and only if those two-label
  suffixes differ (`sso.ts`).
- **preflight-sso-return-contract**: `preflightSsoReturn(opts)` MUST `GET`
  the AS `/oauth/signin/preflight` endpoint (resolved via `asEndpoint` against
  `opts.authApiBase`) with `clientId` and `return` query parameters and
  `credentials: 'omit'`, and MUST return `true` if and only if the response
  is OK and its parsed JSON body has `allowed === true`; any other outcome —
  non-OK, thrown/rejected fetch, or a body without `allowed === true` — MUST
  return `false` (`sso.ts`).
- **preflight-sso-return-timeout**: `preflightSsoReturn` MUST pass an
  `AbortSignal` with a 2000ms timeout (`PREFLIGHT_TIMEOUT_MS`) when
  `AbortSignal.timeout` exists in the runtime, and MUST proceed without a
  signal when it does not (`sso.ts`).
- **begin-silent-login-flow**: `beginSilentLogin(opts)` MUST return `false`
  without navigating when `window` is `undefined`; MUST always call
  `markSsoChecked()` first; MUST return `false` without navigating when no AS
  base is configured or when `preflightSsoReturn` resolves `false` for the
  current URL; and, only when preflight allows it, MUST navigate the
  top-level window to the AS authorize URL with `prompt: 'none'` and a return
  URL equal to `${origin}${pathname}${search}` (dropping any existing hash),
  returning `true` (`sso.ts`).
- **parse-inbound-sso**: `parseInboundSso(hash)` MUST return `{ code }` when
  the fragment has a `code` param, else `{ error }` when it has an `error`
  param, else `null` — including for an empty or absent hash (`sso.ts`).
- **strip-sso-fragment-preserves-other-keys**: `stripSsoFragment(hash)` MUST
  remove only the `code` and `error` keys from the fragment, preserving every
  other key-value pair (e.g. a site-switch marker or scroll anchor) in its
  original order, and MUST return `''` when nothing remains (`sso.ts`).
- **sso-logout-navigation**: `ssoLogout(opts)` MUST be a no-op when `window`
  is `undefined`; otherwise it MUST navigate the top-level window to the AS
  `/oauth/signin/logout` endpoint with `clientId` (default `'adh'`) and
  `return` (default `${origin}/`) query parameters (`sso.ts`).
