---
id: 3ea9329e-5acc-4c43-b5ce-bb8c50570104
title: Auth Client
domain: agentictoolkit://cookbook/auth/auth-client
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Web SPA auth client: Bearer-token sessions, single-flight cookie refresh,
  SSO/central-login navigation, WebAuthn/MFA ceremonies, and account-security enrollment.'
platforms:
- typescript
- web
tags:
- auth
- session
- oauth
- sso
- mfa
- webauthn
- token-refresh
- web
depends-on: []
related: []
references:
- packages/web/packages/auth/src/account-security.ts (agentictoolkit)
- packages/web/packages/auth/src/asBase.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/auth/src/config.ts (agentictoolkit)
- packages/web/packages/auth/src/labels.ts (agentictoolkit)
- packages/web/packages/auth/src/mfa.ts (agentictoolkit)
- packages/web/packages/auth/src/refresh.ts (agentictoolkit)
- packages/web/packages/auth/src/report.ts (agentictoolkit)
- packages/web/packages/auth/src/sso.ts (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
- packages/web/packages/auth/src/types.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/client.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/refresh.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/report.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/tokens.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/link.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/types.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/sso.test.ts (agentictoolkit)
- packages/web/packages/auth/src/__tests__/silent-restore.test.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Auth Client

## Overview

The `auth-client` ingredient is the web SPA's headless authentication layer:
eleven dependency-free TypeScript modules under
`packages/web/packages/auth/src/` (`account-security.ts`, `asBase.ts`,
`client.ts`, `config.ts`, `labels.ts`, `mfa.ts`, `refresh.ts`, `report.ts`,
`sso.ts`, `tokens.ts`, `types.ts`) that together give a brand site a
Bearer-token session backed by an HttpOnly refresh cookie, cross-site single
sign-on against a shared authorization server (the AS), MFA/WebAuthn
completion (both at login time and in self-serve account security), and a
Bearer-authed fetch wrapper the rest of the app builds on. It has no visual
surface of its own — every UI component in the auth family (login forms,
callback pages, account-security screens) is a consumer of this contract, not
part of it.

## Behavioral Requirements

- **default-runtime-config**: `authConfig()` MUST return `{ storageKey:
  'auth_tokens', refreshPath: '/api/auth/refresh' }` before `configureAuth` is
  ever called (`config.ts`).
- **configure-auth-merges**: `configureAuth(partial)` MUST shallow-merge
  `partial` onto the current config, leaving any field `partial` omits
  unchanged (`config.ts`).
- **auth-api-base-resolution**: `authApiBaseOrEnv(explicit)` MUST return
  `explicit` when given, else `process.env.NEXT_PUBLIC_AUTH_API_URL`, with any
  trailing `/` characters stripped, and MUST return `undefined` when neither
  is set (`asBase.ts`).
- **as-endpoint-proxy-fallback**: `asEndpoint(path, authApiBase)` MUST return
  `${base}${path}` when a base resolves via `authApiBaseOrEnv`, and MUST
  return `/api${path}` (the same-origin BFF proxy) when no base is configured
  (`asBase.ts`).
- **auth-tokens-shape**: `AuthTokens` MUST carry exactly `accessToken: string`
  and `refreshToken: string` (`types.ts`).
- **auth-user-shape**: `AuthUser` MUST carry `id`, `email`, `name`,
  `avatarUrl: string`, `capabilities: string[]`, `authMethods:
  UserAuthMethod[]`, and `attributes: UserAttribute[]`, and MAY carry `slug:
  string | null` (`types.ts`).
- **has-capability-null-safe**: `hasCapability(user, capability)` MUST return
  `true` if and only if `user.capabilities` includes `capability`, and MUST
  return `false` when `user` is `null` or `undefined` (`types.ts`).
- **is-admin-derived**: `isAdmin(user)` MUST return
  `hasCapability(user, 'admin')` (`types.ts`).
- **tokens-from-response-precedence**: `tokensFromResponse(data)` MUST prefer
  `data.accessToken` over `data.token` when both are present (`tokens.ts`).
- **tokens-from-response-refresh-token-blanked**: `tokensFromResponse` MUST
  always set the returned `refreshToken` to `''`, regardless of whether the
  response body carries one — refresh/revoke are cookie-first against an
  HttpOnly cookie, and the backend's `refreshToken` field is deliberately
  never read or persisted (`tokens.ts`).
- **tokens-from-response-throws-when-absent**: `tokensFromResponse` MUST
  throw `Error('Token response missing token/accessToken')` when neither
  `accessToken` nor `token` is present (`tokens.ts`).
- **token-storage-key-configurable**: `readTokens`/`writeTokens`/`clearTokens`
  MUST read, write, and remove the localStorage key named by
  `authConfig().storageKey`, as JSON (`tokens.ts`).
- **token-read-off-browser-returns-null**: `readTokens` (and therefore
  `readAccessToken`) MUST return `null` when `window` is `undefined` (SSR)
  (`tokens.ts`).
- **token-read-malformed-json-returns-null**: `readTokens` MUST return `null`
  when the stored value is not valid JSON, without throwing (`tokens.ts`).
- **write-tokens-persists-and-announces**: `writeTokens(tokens)` MUST persist
  `tokens` under the storage key and then invoke every subscriber registered
  via `onSessionChange` (`tokens.ts`).
- **clear-tokens-clears-sibling-user-key**: `clearTokens()` MUST remove both
  the tokens key and the sibling cached-user key (`${storageKey}:user`), then
  invoke every `onSessionChange` subscriber (`tokens.ts`).
- **read-access-token-derivation**: `readAccessToken()` MUST return
  `readTokens()?.accessToken ?? null` (`tokens.ts`).
- **session-change-subscription**: `onSessionChange(fn)` MUST register `fn`
  to be called on every subsequent `writeTokens`/`clearTokens` call, and MUST
  return an unsubscribe function that removes `fn` from the listener set
  (`tokens.ts`).
- **session-change-payload-free**: `onSessionChange` listeners MUST be
  invoked with no arguments — the announcement communicates only that the
  session moved, never what it moved to (`tokens.ts`).
- **session-change-snapshot-iteration**: `announceSessionChange` MUST iterate
  a snapshot (`[...sessionListeners]`) of the listener set, so a listener that
  unsubscribes itself or another listener from inside its own callback does
  not affect delivery to the other listeners in that same announcement
  (`tokens.ts`).
- **decode-base64url-json-utf8-strict**: `decodeBase64UrlJson(segment)` MUST
  base64url-decode `segment` and decode the resulting bytes as UTF-8 using a
  strict (`fatal: true`) decoder — never substituting U+FFFD for an invalid
  byte sequence — before `JSON.parse`-ing the text (`tokens.ts`).
- **decode-base64url-json-tolerates-missing-padding**: `decodeBase64UrlJson`
  MUST tolerate a segment whose `=` padding was stripped, by re-padding to a
  multiple of 4 characters before decoding (`tokens.ts`).
- **decode-base64url-json-never-throws**: `decodeBase64UrlJson` MUST return
  `null`, never throw, for input that fails at any step — invalid base64,
  invalid UTF-8, or invalid JSON (`tokens.ts`).
- **read-token-subject-derivation**: `readTokenSubject()` MUST return the
  string `sub` claim decoded from the second dot-separated segment of the
  stored access token, and MUST return `null` when no token is stored, the
  token has no second segment, decoding fails, or `sub` is not a string
  (`tokens.ts`).
- **read-user-validates-shape**: `readUser()` MUST return `null` — never the
  malformed value — when the cached user blob is absent, lacks a string `id`,
  or lacks an array `capabilities` (`tokens.ts`).
- **write-user-persists-off-browser-noop**: `writeUser(user)` MUST persist
  `user` under the cached-user key as JSON, and MUST be a no-op when `window`
  is `undefined` (`tokens.ts`).
- **refresh-single-flight-dedup**: `refreshAccessToken()` MUST return the
  same in-flight `Promise` to every caller while a refresh is outstanding,
  issuing exactly one network request regardless of how many callers invoke
  it concurrently (`refresh.ts`).
- **refresh-request-shape**: A refresh attempt MUST `POST` the literal body
  `'{}'` to `authConfig().refreshPath` with `credentials: 'include'` and
  header `Content-Type: application/json` (`refresh.ts`).
- **invalidate-refresh-bumps-generation**: `invalidateRefresh()` MUST
  increment the module's generation counter and MUST discard any outstanding
  in-flight refresh reference, so a fresh login or logout invalidates a
  refresh that started before it (`refresh.ts`).
- **refresh-generation-guard**: If the generation counter has changed between
  the start of a refresh attempt and its response arriving, `doRefresh` MUST
  resolve `null` on the success path without calling `writeTokens` or
  `clearTokens` (`refresh.ts`).
- **refresh-success-adopts-current-storage**: On a successful (`res.ok`)
  refresh response, `doRefresh` MUST compare the access token currently in
  storage against the one read at the start of the attempt; if storage no
  longer holds that starting token (cleared by a logout, or replaced by
  another login/refresh), `doRefresh` MUST return the current stored token
  (or `null` if storage was cleared) instead of writing the newly fetched
  tokens, and MUST only call `writeTokens` when storage still holds the
  unchanged starting token (`refresh.ts`).
- **refresh-failure-adopts-concurrent-winner**: On a non-OK refresh response,
  if storage's current access token already differs from the one this
  attempt started with, `doRefresh` MUST return that current token rather
  than clearing it (`refresh.ts`).
- **refresh-failure-loser-recheck-delay**: On a non-OK refresh response with
  no immediately visible concurrent winner, `doRefresh` MUST wait exactly
  300ms (`LOSER_RECHECK_DELAY_MS`) and re-read storage once before deciding,
  adopting a winner's token if one appeared during the wait (`refresh.ts`).
- **refresh-failure-clears-when-unresolved**: If, after the loser-recheck
  wait, storage still holds the access token this attempt started with, and
  the generation counter has not changed, `doRefresh` MUST call `clearTokens`
  and resolve `null` (`refresh.ts`).
- **refresh-network-error-reports-and-clears**: A thrown network or parse
  error during a refresh attempt MUST be reported via
  `reportAuthError(err, { feature: 'auth', step: 'tokenRefresh' })`, and MUST
  then clear tokens (subject to the same generation guard) and resolve `null`
  (`refresh.ts`).
- **authed-fetch-bearer-attach**: `authedFetch`/`authedJson`/`authedRequest`
  MUST attach `Authorization: Bearer <token>` to the request whenever
  `readAccessToken()` returns a non-null token (`client.ts`).
- **authed-fetch-default-content-type**: `rawFetch` MUST default a
  `Content-Type: application/json` header whenever `init.body` is set and no
  `Content-Type` header was already supplied (`client.ts`).
- **authed-fetch-default-init**: `authedFetch`/`authedJson`/`authedRequest`
  MAY be called with no `init` argument; each MUST default it to `{}` rather
  than requiring the caller to pass one (`client.ts`).
- **authed-fetch-401-refresh-retry-once**: On a `401` response, `authedFetch`
  MUST call `refreshAccessToken()` exactly once and, if it resolves to a
  token, MUST retry the original request exactly once with that token; it
  MUST NOT call `refreshAccessToken()` again or retry a second time if the
  retried request also fails (`client.ts`).
- **authed-fetch-throws-on-non-ok**: `authedFetch` MUST throw `AuthHttpError`
  — carrying the response's HTTP status and any machine-readable `code`
  extracted from the parsed JSON body — for any final non-OK response, after
  the one refresh-and-retry has already been attempted (`client.ts`).
- **authed-json-rejects-204**: `authedJson` MUST throw `Error('Unexpected
  empty response (204 No Content); use authedRequest for endpoints with no
  body')` when the response status is `204` (`client.ts`).
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

## Appearance

Not applicable — this is a headless authentication client, not a visual
component.

## States

Not applicable — this is a headless authentication client, not a visual
component.

## Accessibility

Not applicable — this is a headless authentication client, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-001 | default-runtime-config | `authConfig()` called with no prior `configureAuth` | `{ storageKey: 'auth_tokens', refreshPath: '/api/auth/refresh' }` |
| auth-client-002 | configure-auth-merges | `configureAuth({ storageKey: 'x' })` then `authConfig()` | `refreshPath` unchanged; `storageKey === 'x'` (tokens.test.ts "honors a re-configured key") |
| auth-client-003 | auth-api-base-resolution | `authApiBaseOrEnv('https://x.example.com/')` | `'https://x.example.com'` (trailing slash stripped) |
| auth-client-004 | as-endpoint-proxy-fallback | `asEndpoint('/a', undefined)` with no env var set | `'/api/a'` |
| auth-client-005 | auth-tokens-shape | `{ accessToken: 'a', refreshToken: 'b' }` assigned to `AuthTokens` | Compiles; no other fields required or permitted |
| auth-client-006 | auth-user-shape | An `AuthUser` literal omitting `slug` | Compiles (types.test.ts's `user()` helper omits `slug`) |
| auth-client-007 | has-capability-null-safe | `hasCapability(null, 'billing')` | `false` (types.test.ts) |
| auth-client-008 | is-admin-derived | `isAdmin(user(['user', 'admin']))` | `true` (types.test.ts) |
| auth-client-009 | tokens-from-response-precedence | `tokensFromResponse({ accessToken: 'A', token: 'T' })` | `{ accessToken: 'A', refreshToken: '' }` (tokens.test.ts) |
| auth-client-010 | tokens-from-response-refresh-token-blanked | `tokensFromResponse({ token: 'T', refreshToken: 'server-rt' } as any)` | `refreshToken === ''` |
| auth-client-011 | tokens-from-response-throws-when-absent | `tokensFromResponse({})` | Throws `/missing token/i` (tokens.test.ts) |
| auth-client-012 | token-storage-key-configurable | `configureAuth({ storageKey: 'other_key' })`; `writeTokens(...)` | `localStorage.getItem('other_key')` truthy; `test_tokens` key absent (tokens.test.ts) |
| auth-client-013 | token-read-off-browser-returns-null | `readTokens()` with `window` undefined (SSR) | `null` |
| auth-client-014 | token-read-malformed-json-returns-null | `localStorage.setItem('test_tokens', 'not json')`; `readTokens()` | `null` (tokens.test.ts) |
| auth-client-015 | write-tokens-persists-and-announces | Subscribe via `onSessionChange`; call `writeTokens(...)` | Subscriber invoked exactly once; storage contains the tokens |
| auth-client-016 | clear-tokens-clears-sibling-user-key | `writeUser(u)`; `clearTokens()` | `readUser()` returns `null`; tokens key absent |
| auth-client-017 | read-access-token-derivation | `writeTokens({ accessToken: 'A', refreshToken: '' })`; `readAccessToken()` | `'A'` (tokens.test.ts) |
| auth-client-018 | session-change-subscription | `const unsub = onSessionChange(fn)`; `unsub()`; `writeTokens(...)` | `fn` not called |
| auth-client-019 | session-change-payload-free | `onSessionChange(fn)`; `writeTokens(...)` | `fn` called with zero arguments |
| auth-client-020 | session-change-snapshot-iteration | Listener A unsubscribes listener B from inside A's own callback, both registered before one `writeTokens` call | B is still invoked for that same announcement |
| auth-client-021 | decode-base64url-json-utf8-strict | `decodeBase64UrlJson(b64url(JSON.stringify({ name: '東京' })))` | `{ name: '東京' }` (tokens.test.ts) |
| auth-client-022 | decode-base64url-json-tolerates-missing-padding | Unpadded base64url of `{ sub: 'u', iat: 1 }` | `{ sub: 'u', iat: 1 }` (tokens.test.ts) |
| auth-client-023 | decode-base64url-json-never-throws | `decodeBase64UrlJson(btoa('\xff\xfe'))` | `null`, no throw (tokens.test.ts) |
| auth-client-024 | read-token-subject-derivation | Access token `` `x.${b64url(JSON.stringify({ sub: 'user-1' }))}.y` `` stored | `readTokenSubject() === 'user-1'` (tokens.test.ts) |
| auth-client-025 | read-user-validates-shape | `localStorage` holds `{"name":"x"}` (no `id`/`capabilities`) under the user key | `readUser() === null` |
| auth-client-026 | write-user-persists-off-browser-noop | `writeUser(u)` with `window` undefined | No throw; no storage write |
| auth-client-027 | refresh-single-flight-dedup | `Promise.all([refreshAccessToken(), refreshAccessToken()])`, fetch resolves `{ token: 'NEW' }` | `fetchMock` called exactly once; both results `'NEW'` (refresh.test.ts) |
| auth-client-028 | refresh-request-shape | `refreshAccessToken()` | fetch called with `method: 'POST'`, `credentials: 'include'`, `body: '{}'` (refresh.test.ts) |
| auth-client-029 | invalidate-refresh-bumps-generation | `refreshAccessToken()` in flight; `invalidateRefresh()` called | Next `refreshAccessToken()` call starts a fresh in-flight promise, not the old one |
| auth-client-030 | refresh-generation-guard | Refresh in flight; `invalidateRefresh()` fires before the response lands; response then resolves OK | Result `null`; no `writeTokens` call |
| auth-client-031 | refresh-success-adopts-current-storage | Refresh in flight; `clearTokens()` (logout) fires before the OK response lands | Result `null`; storage stays cleared (refresh.test.ts "does NOT resurrect the session") |
| auth-client-032 | refresh-success-adopts-current-storage | Refresh in flight; a concurrent `writeTokens({ accessToken: 'WINNER' })` fires before this attempt's OK response lands with `{ token: 'MINE' }` | Result `'WINNER'`; storage still `'WINNER'` (refresh.test.ts "adopts a concurrently-written token") |
| auth-client-033 | refresh-failure-adopts-concurrent-winner | Non-OK response; storage already holds a token different from the one this attempt started with | Result is that current stored token; no `clearTokens` |
| auth-client-034 | refresh-failure-loser-recheck-delay | Non-OK response; a winner's `writeTokens({ accessToken: 'WINNER' })` lands during the 300ms wait | After the wait, result `'WINNER'` (refresh.test.ts "failure path: waits for a delayed concurrent winner") |
| auth-client-035 | refresh-failure-clears-when-unresolved | Non-OK response; no winner appears during the 300ms wait | Result `null`; `readTokens()` is `null` (refresh.test.ts "clears tokens and returns null on a non-OK response with no concurrent winner") |
| auth-client-036 | refresh-network-error-reports-and-clears | `fetch` rejects with a `TypeError` | `reportAuthError` called with `{ feature: 'auth', step: 'tokenRefresh' }`; result `null`; tokens cleared |
| auth-client-037 | authed-fetch-bearer-attach | `writeTokens({ accessToken: 'TOK' })`; `authedFetch('/api/x')` | Request header `Authorization: 'Bearer TOK'` (client.test.ts) |
| auth-client-038 | authed-fetch-default-content-type | `authedJson('/api/x', { body: JSON.stringify({}) })` with no `Content-Type` given | Sent request has `Content-Type: application/json` |
| auth-client-039 | authed-fetch-default-init | `authedFetch('/api/x')` called with no second argument | Resolves normally; no throw reading `init.headers` (client.test.ts "works with no init at all") |
| auth-client-040 | authed-fetch-401-refresh-retry-once | First fetch → `401`; refresh → `{ token: 'NEW' }`; retry → `200` | 3 fetch calls total; final result uses `Authorization: 'Bearer NEW'` (client.test.ts) |
| auth-client-041 | authed-fetch-throws-on-non-ok | Response `{ ok: false, status: 500, json: () => ({ error: 'boom' }) }` | Throws `AuthHttpError` with message `'boom'`, `status === 500` (client.test.ts) |
| auth-client-042 | authed-json-rejects-204 | Response `{ ok: true, status: 204 }` | Throws `/Unexpected empty response/` |
| auth-client-043 | authed-request-discards-body | `authedRequest('/api/x', { method: 'DELETE' })` on a `200` with a JSON body | Resolves `undefined`; body never parsed by the caller |
| auth-client-044 | auth-http-error-shape | `new AuthHttpError(409, 'conflict', 'ALREADY_LINKED')` | `.status === 409`, `.code === 'ALREADY_LINKED'`, `.name === 'AuthHttpError'`, `instanceof Error` |
| auth-client-045 | extract-error-message-precedence | `extractErrorMessage({ error: 'E' }, 'fb')`, `({ message: 'M' }, 'fb')`, `({ title: 'T' }, 'fb')`, `({}, 'fb')` | `'E'`, `'M'`, `'T'`, `'fb'` respectively (client.test.ts) |
| auth-client-046 | extract-error-message-precedence | `extractErrorMessage({ title: 'Bad Request', status: 400, detail: 'no GitHub App is configured' }, 'fb')` | `'no GitHub App is configured'` (RFC 9457 `detail` wins) |
| auth-client-047 | extract-error-code-precedence | `extractErrorCode({ error: { code: 'X' } })` and `extractErrorCode({})` | `'X'` and `undefined` respectively |
| auth-client-048 | read-error-message-single-parse | `res.json` mocked to resolve once with `{ message: 'M' }` | Returns `'M'`; `res.json` called exactly once |
| auth-client-049 | exchange-sso-code-request-shape | `exchangeSsoCode('code-1')` | `POST` to `'/api/oauth/signin/exchange'` with body `{"code":"code-1"}` |
| auth-client-050 | exchange-sso-code-network-retry-once | First `fetch` rejects (`TypeError`), second resolves `200` with tokens | `fetchMock` called twice; result resolves with the tokens (client.test.ts "retries once after a network-level failure") |
| auth-client-051 | exchange-sso-code-no-http-retry | `fetch` resolves `{ ok: false, status: 401 }` | `fetchMock` called once per `exchangeSsoCode` call — no internal retry (client.test.ts "does NOT retry an HTTP error") |
| auth-client-052 | exchange-sso-code-success-result | `200` response with `{ token: 'A', user: { id: 'u1' } }` | `{ tokens: { accessToken: 'A', refreshToken: '' }, user: { id: 'u1' } }` |
| auth-client-053 | exchange-sso-code-failure-throws | `401` response with `{ error: { message: 'invalid or expired exchange code' } }` | Throws `AuthHttpError` with that message (client.test.ts) |
| auth-client-054 | link-provider-routes-to-as-host | `NEXT_PUBLIC_AUTH_API_URL='https://api.example.com'`; `linkProvider(input)` | `fetch` called with `'https://api.example.com/auth/link-provider'` (link.test.ts) |
| auth-client-055 | link-provider-authed-post | `writeTokens({ accessToken: 'at' })`; `linkProvider(input)` | Request header `authorization: 'Bearer at'`; body deep-equals `input` (link.test.ts) |
| auth-client-056 | retry-marker-hook | `setAuthRetryMarker(fn)`; trigger a post-refresh retry in `authedFetch` | `fn` called once with the retried request's `RequestInit` |
| auth-client-057 | webauthn-assertion-ceremony-shared | Options endpoint returns non-OK | `runAssertion` throws using `readErrorMessage`'s extracted/fallback message |
| auth-client-058 | assert-second-factor-body | `assertSecondFactor('tok', url)` | Options `POST` body is `{"token":"tok"}` |
| auth-client-059 | assert-passwordless-passkey-body | `assertPasswordlessPasskey('id', url)` | Options `POST` body is `{"identifier":"id"}` |
| auth-client-060 | request-login-sms | `requestLoginSms('tok')` | `POST` to `'/api/auth/login/mfa/sms/send'` with `{"token":"tok"}` |
| auth-client-061 | complete-login-code | `completeLoginCode('tok', 'totp', '123456')` on a `200` | `POST` to `'/api/auth/login/mfa'`; returns parsed body |
| auth-client-062 | complete-login-passkey | `completeLoginPasskey('tok')` | `POST` to `'/api/auth/login/mfa/webauthn'` with the ceremony's `{ token, response }` |
| auth-client-063 | passwordless-passkey-login | `passwordlessPasskeyLogin('id')` | `POST` to `'/api/auth/login/webauthn'` with the ceremony's `{ token, response }` |
| auth-client-064 | begin-login-navigation | `beginLogin({ clientId: 'cookbook', authApiBase: 'https://api.hub.example.com' })` | `location.href` origin `'https://api.hub.example.com'`, path `/oauth/signin/authorize`, `clientId=cookbook`, `return=<site>/auth/callback` (sso.test.ts) |
| auth-client-065 | authorize-url-shape | `buildAuthorizeUrl({ clientId: 'adh', returnUrl: 'r', prompt: 'none' })` | Query has `clientId=adh`, `return=r`, `prompt=none` |
| auth-client-066 | provider-signin-url-shape | `providerSigninUrl({ clientId: 'adh', providerId: 'github', returnUrl: 'r' })` | Path `/oauth/signin/start`; query has `clientId`, `providerId`, `return` (sso.test.ts) |
| auth-client-067 | sso-hint-cookie-check | `document.cookie = 'adh_sso_hint=1'` | `ssoHintPresent() === true` (silent-restore.test.ts) |
| auth-client-068 | sso-checked-guard-tolerates-storage-failure | `sessionStorage.setItem` mocked to throw | `markSsoChecked()` does not throw |
| auth-client-069 | silent-restore-guard-order | `initialHash` carries `#code=abc` | `shouldSilentRestore('#code=abc') === false` regardless of hint (silent-restore.test.ts "false mid-flow on the callback") |
| auth-client-070 | silent-restore-evidence | No hint cookie, same-apex site | `shouldSilentRestore('') === false` (silent-restore.test.ts "false without the hint on a same-apex site") |
| auth-client-071 | registrable-domain-apex-comparison | AS host `api.agenticdeveloperhub.com`, site host `cookbook.com` | Treated as cross-apex; `shouldSilentRestore` may return `true` even without a hint (silent-restore.test.ts "true for a cross-apex site") |
| auth-client-072 | preflight-sso-return-contract | Preflight response `{ allowed: true }`, `200` | `preflightSsoReturn(...) === true` (silent-restore.test.ts "true only on an explicit allowed:true") |
| auth-client-073 | preflight-sso-return-contract | Preflight `fetch` throws | `preflightSsoReturn(...) === false` (silent-restore.test.ts "false when the request throws") |
| auth-client-074 | preflight-sso-return-timeout | Preflight request never resolves | `preflightSsoReturn(...)` resolves `false` after ~2000ms via its `AbortSignal` (silent-restore.test.ts "resolves false when the AS never answers at all") |
| auth-client-075 | begin-silent-login-flow | No AS base configured | `beginSilentLogin({}) === false`; `markSsoChecked` still called; no navigation |
| auth-client-076 | begin-silent-login-flow | AS base configured; preflight resolves `true` | `beginSilentLogin({}) === true`; navigates to authorize URL with `prompt=none` (silent-restore.test.ts "navigates to the AS /authorize with prompt=none") |
| auth-client-077 | parse-inbound-sso | `parseInboundSso('#code=abc')`, `('#error=login_required')`, `('')` | `{ code: 'abc' }`, `{ error: 'login_required' }`, `null` |
| auth-client-078 | strip-sso-fragment-preserves-other-keys | `stripSsoFragment('#site-switch&code=abc')` | `'#site-switch'` (sso.test.ts) |
| auth-client-079 | sso-logout-navigation | `ssoLogout({ clientId: 'cookbook', authApiBase: 'https://api.hub.example.com' })` | Navigates to `/oauth/signin/logout` with `clientId=cookbook`, `return=<origin>/` (sso.test.ts) |
| auth-client-080 | sso-switch-url | No AS base configured; `ssoSwitchUrl('https://site.example.com/home')` | Returns `'https://site.example.com/home'` unchanged (sso.test.ts) |
| auth-client-081 | current-return-to | `window.location` is `/a?b=1#c` | `currentReturnTo() === '/a?b=1#c'` |
| auth-client-082 | safe-return-to-rejects-cross-origin | `takeReturnTo()` with a stashed value `'//evil.com/x'` | Returns `null`; storage key cleared (sso.test.ts "rejects a cross-origin (protocol-relative) stashed destination") |
| auth-client-083 | safe-return-to-rejects-cross-origin | Stashed value `'https://site.example.com/home?x=1#y'` (same origin, absolute) | Returns `'/home?x=1#y'` (sso.test.ts "reduces an absolute same-origin URL to a relative path") |
| auth-client-084 | stash-and-take-return-to-single-use | `stashReturnTo('/home/x')`; `takeReturnTo()` twice | First call `'/home/x'`; second call `null` (sso.test.ts "reads and clears the stashed destination (single use)") |
| auth-client-085 | read-central-params | `readCentralParams('?return=https%3A%2F%2Fx.example.com%2Fcb')` | `{ clientId: 'adh', returnUrl: 'https://x.example.com/cb' }` (sso.test.ts) |
| auth-client-086 | read-central-params | `readCentralParams('?clientId=adh')` (no `return`) | `null` (sso.test.ts "returns null without a return") |
| auth-client-087 | central-login-target-resolution | `window.location.search` carries a relayed `return`/`clientId` | `centralLoginTarget(...)` returns those relayed values, not a synthesized target |
| auth-client-088 | central-login-step-refuses-without-as-base | No AS base configured; `centralEmailLogin({ identifier: 'a', password: 'b', ... })` | Throws before any `fetch` call; `fetchMock` never called (sso.test.ts "refuses, rather than posting credentials to the same-origin proxy") |
| auth-client-089 | central-login-step-outcomes | `centralEmailLogin(...)` response `202` with an `MfaChallenge` body | Returns that `MfaChallenge`; no navigation |
| auth-client-090 | central-login-step-outcomes | `centralEmailLogin(...)` response `200` with `{ redirectUrl: 'https://bitbag.example.com/auth/callback#code=abc' }` | `location.href` becomes that URL; function returns `null` (sso.test.ts "POSTs the AS /login ... and navigates to the redirectUrl") |
| auth-client-091 | central-login-step-request-shape | `centralEmailLogin(p)` | Request has `credentials: 'include'`; body includes `clientId`/`return` merged with `identifier`/`password` (sso.test.ts) |
| auth-client-092 | central-email-login | `centralEmailLogin({ identifier: 'a@b.com', password: 'p', clientId: 'adh', returnUrl: 'r' })` | `POST` to `'/oauth/signin/login'` with `{identifier,password,clientId,return}` |
| auth-client-093 | central-send-mfa-sms | Non-OK response from `LOGIN_SMS_PATH` on the AS | Throws `AuthHttpError` with fallback `'Could not send a code.'` |
| auth-client-094 | central-complete-mfa-code | `centralCompleteMfaCode(target, 'tok', 'sms', '123456')` | `POST` to `'/oauth/signin/login/mfa'` via `centralLoginStep` |
| auth-client-095 | central-complete-mfa-passkey | `centralCompleteMfaPasskey(target, 'tok')` | Ceremony runs against the AS's MFA options endpoint, then `POST` to `'/oauth/signin/login/mfa/webauthn'` |
| auth-client-096 | central-passwordless-passkey | `centralPasswordlessPasskey(target, 'id')` | Ceremony runs against the AS's passkey options endpoint, then `POST` to `'/oauth/signin/login/webauthn'` |
| auth-client-097 | begin-link-provider-csrf-nonce | `beginLinkProvider({ providerId: 'github', returnTo: '/home' })` | Navigates to AS `/oauth/signin/start` with `link=1`; `sessionStorage['adh_link_nonce']` equals the `linkNonce` query value (sso.test.ts) |
| auth-client-098 | begin-link-provider-csrf-nonce | `sessionStorage.setItem` mocked to throw | `beginLinkProvider(...) === false`; `location.href` unset — never navigated (sso.test.ts "returns false and does NOT navigate when the CSRF nonce cannot be stashed") |
| auth-client-099 | mfa-status-fetch | `getMfaStatus()` on a `200` with an `MfaStatus` body | `GET /api/account/mfa`; returns the parsed body |
| auth-client-100 | totp-enroll | `enrollTotp()` on a `200` with `{ secret, otpauthUri }` | `POST /api/account/mfa/totp/enroll`; returns that body |
| auth-client-101 | totp-confirm | `confirmTotp('123456')` | `POST /api/account/mfa/totp/confirm` with `{"code":"123456"}` |
| auth-client-102 | totp-remove | `removeTotp()` | `DELETE /api/account/mfa/totp` |
| auth-client-103 | webauthn-list | `listWebauthn()` on a `200` with `{ items: [...] }` | `GET /api/account/mfa/webauthn`; returns that body |
| auth-client-104 | webauthn-register-ceremony | `registerWebauthn('passkey', 'My key')` | Options `POST`, then registration ceremony, then verify `POST` with `{ token, response, name: 'My key' }` |
| auth-client-105 | webauthn-remove | `removeWebauthn('cred id/with slash')` | `DELETE` path has the id percent-encoded |
| auth-client-106 | recovery-codes-regenerate | `regenerateRecoveryCodes()` on a `200` with `{ codes: [...] }` | `POST /api/account/mfa/recovery/regenerate`; returns that body |
| auth-client-107 | preferred-method-set | `setPreferredMethod('totp')` | `PUT /api/account/mfa/preference` with `{"method":"totp"}` |
| auth-client-108 | account-security-authed | No access token stored; any `account-security.ts` call | Request carries no `Authorization` header, then a `401` triggers the same refresh-and-retry waterfall as `authedFetch` |
| auth-client-109 | report-unexpected-status-gate | `reportUnexpectedAuthError(new AuthHttpError(401, 'unauthorized'))` and `new HostAuthHttpError(403, 'forbidden')` | Neither `console.error` nor the sink is called for either (report.test.ts "drops an expected 4xx from EITHER AuthHttpError class") |
| auth-client-110 | report-unexpected-status-gate | `reportUnexpectedAuthError(new AuthHttpError(503, 'unavailable'))` | Both `console.error` and the sink are called (report.test.ts "reports a 5xx") |
| auth-client-111 | report-unexpected-dedup-window | Same `Error('boom')` message + context reported twice within 60000ms | Sink/console called once, not twice |
| auth-client-112 | report-auth-error-unconditional | `reportAuthError(err, ctx)` regardless of status | Sink and `console.error` both called |
| auth-client-113 | report-never-throws | `setAuthErrorReporter(() => { throw new Error('telemetry down') })`; `reportUnexpectedAuthError(new Error('boom'))` | Does not throw; `console.error` still called (report.test.ts "swallows a throwing sink") |
| auth-client-114 | set-auth-error-reporter-hook | `setAuthErrorReporter(sink)`; `reportUnexpectedAuthError(new Error('boom'), { feature: 'x' })` | `sink` called with `(err, { feature: 'x' })` (report.test.ts) |
| auth-client-115 | provider-label-known-and-fallback | `providerLabel('github')`, `('google')`, `('discord')` | `'GitHub'`, `'Google'`, `'Discord'` |
| auth-client-116 | oauth-error-message-known-codes-and-fallback | `oauthErrorMessage('account_exists')` and `oauthErrorMessage('weird_code')` | Fixed account-exists message; `'Sign-in failed (weird_code)'` |
| auth-client-117 | link-copy-provider-substitution | `linkConfirmTitle('github')` | `'Add GitHub to your account?'` |
| auth-client-118 | sensitive-data-classification / access-token-transmission | `reportAuthError` called with a context object that happens to include an access token field | Not applicable as a runtime check — `ErrorContext`'s type (`Record<string, string \| number \| boolean \| null \| undefined>`) documents the scalar-only contract; this vector records that no call site in these 11 files passes a token as context |
| auth-client-119 | refresh-token-never-persisted | `tokensFromResponse({ token: 'T', refreshToken: 'server-side-rt' } as any)` then `writeTokens(...)`; inspect `localStorage` | Stored JSON's `refreshToken` field is `''`, never `'server-side-rt'` |
| auth-client-120 | token-subject-not-an-authorization-decision | Access token with an unsigned/forged `sub` claim | `readTokenSubject()` returns that claim's value unverified — documents that callers MUST NOT treat it as an authorization fact |

## Edge Cases

- **Null/empty input**: `tokensFromResponse({})` (neither field present) — MUST
  throw (auth-client-011). `readCentralParams('')` (no query at all) — MUST
  return `null` (auth-client-086). `parseInboundSso('')` — MUST return `null`
  (auth-client-077). `takeReturnTo()` with nothing stashed — MUST return
  `null`.
- **Boundary/malformed values**: A stored tokens blob that is not valid JSON —
  MUST be treated as absent, never thrown (auth-client-014). A `sub` claim
  that decodes to a non-string — MUST be treated as absent
  (`read-token-subject-derivation`). A base64url segment with stripped
  padding — MUST still decode (auth-client-022). A base64url segment with an
  invalid UTF-8 byte sequence — MUST decode to `null`, never substitute
  U+FFFD (auth-client-023).
- **Concurrent access**: Two or more callers invoking `refreshAccessToken()`
  simultaneously — MUST dedup to exactly one network request
  (auth-client-027). A refresh racing a `clearTokens()` (logout) — MUST NOT
  resurrect the session (auth-client-031). A refresh racing another
  refresher's or a fresh login's `writeTokens` — MUST adopt the winner's
  token rather than clobber or wrongly clear it (auth-client-032,
  auth-client-034). A session-change listener that unsubscribes another
  listener from inside its own callback — MUST NOT suppress delivery to that
  other listener for the in-progress announcement (auth-client-020).
- **Error states**: Every network call in these 11 files that can fail (the
  refresh POST, `authedFetch`, `exchangeSsoCode`, every `centralLoginStep`
  call, `preflightSsoReturn`, every `account-security.ts` operation, every
  `mfa.ts` operation) MUST surface a typed `AuthHttpError` (status + code) or
  a plain `Error` with an extracted/fallback message to its caller — none
  silently drops a non-2xx response's failure. `preflightSsoReturn` alone
  fails closed to `false` on any error (network throw, non-200, wrong-shaped
  body) rather than propagating (auth-client-073) — a deliberate design
  choice (see Design Decisions), not an omission.
- **Offline/disconnected state**: A `fetch` that rejects at the network level
  (offline, DNS failure, connection reset) during a refresh — MUST be reported
  via `reportAuthError` and MUST clear tokens rather than leave a token the
  client can no longer confirm is still valid (auth-client-036). The same
  network-level failure during `exchangeSsoCode` — MUST retry exactly once
  after 750ms before giving up (auth-client-050); an HTTP-level failure (the
  server responded) is never retried, because the one-time exchange code is
  already spent (auth-client-051).
- **Storage unavailable** (private browsing, disabled storage — a web-specific
  edge case with no native-platform analog): `markSsoChecked`,
  `clearSsoChecked`, `stashReturnTo`, `takeReturnTo`, and
  `beginLinkProvider`'s nonce stash MUST all swallow a thrown storage
  exception; `beginLinkProvider` specifically MUST fail closed (return
  `false`, never navigate) rather than start an OAuth round-trip whose CSRF
  completion check is guaranteed to fail (auth-client-098).

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

## Deep Linking

Not applicable: `auth-client` is a browser-only web module with no app URL
scheme, Android intent filter, or platform deep-link registration of its
own. Inbound OAuth round-trip state travels as ordinary URL hash and query
parameters — `parseInboundSso` reads `#code`/`#error` from
`window.location.hash` and `readCentralParams` reads `clientId`/`return` from
`window.location.search` (`sso.ts`) — parsed by this module's own functions,
not resolved through any deep-link mechanism.

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

## Accessibility Options

Not applicable: this module renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior of its own. Those
display options act on whatever UI a host renders around `auth-client`'s
calls (login forms, MFA prompts, account-security screens), not on this
headless module.

## Feature Flags

Not applicable: no file in this component defines or reads a feature-flag
key. Every conditional path — whether an AS base is configured
(`asBaseConfigured`), whether the SSO hint cookie is present
(`ssoHintPresent`), whether the site is cross-apex (`isCrossApex`), whether a
preflight allows a silent restore — is derived from runtime configuration,
a cookie, or a server response, never from a flag this module owns.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event. `report.ts`'s `reportAuthError`/`reportUnexpectedAuthError`
send operational error diagnostics to an injected sink and `console.error`
(see Logging below) — these are failure telemetry for a host's error-tracking
SDK (e.g. Sentry), not product-analytics events.

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

## Logging

Subsystem: `agentictoolkit` | Category: `auth-client`

| Event | Level | Message |
|-------|-------|---------|
| Refresh network/parse failure | error (via `reportAuthError`, always reaches `console.error`) | `reportAuthError(err, { feature: 'auth', step: 'tokenRefresh' })` (`refresh.ts`) |
| Any reported auth error (unconditional path) | error | `console.error(err, context)` (`report.ts`) |
| Missing AS base at build/runtime (logged once per page load) | error | `'[adh-auth] NEXT_PUBLIC_AUTH_API_URL was not set when this site was built...'` (`sso.ts`) |

No file in this component uses `console.log`, `console.warn`, or `console.info` — every log call site is `console.error`, and every one is either an unexpected-failure report (`report.ts`, `refresh.ts`) or the one-time misconfiguration notice above (`sso.ts`). `report.ts`'s error-status gate (**report-unexpected-status-gate**) is specifically what keeps an expected 4xx (wrong password, stale code) off this log.

## Platform Notes

- **React/Web**: This is the reference implementation. `fetch` for
  networking, `window.localStorage`/`window.sessionStorage` for persistence,
  `@simplewebauthn/browser`'s `startAuthentication`/`startRegistration` for
  WebAuthn ceremonies, and plain `window.location`/top-level navigation for
  every AS round-trip (no client-side router is involved — the SSO/central
  login flows are deliberately full-page navigations, not `fetch` calls,
  because the central session cookie is host-only on the AS host).
- **SwiftUI / AppKit / UIKit**: `URLSession` replaces `fetch`; the Keychain
  (not `UserDefaults`) is the idiomatic store for the access token, though
  this component's own decision to never persist the refresh token still
  applies — a native port keeps the refresh token cookie-equivalent
  server-side only, never in the Keychain either. `ASWebAuthenticationSession`
  (for the AS navigation/callback round-trip) and
  `ASAuthorizationPlatformPublicKeyCredentialProvider`/
  `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` (for the WebAuthn
  ceremonies `mfa.ts`/`account-security.ts` run via `@simplewebauthn/browser`)
  are the platform equivalents. `NotificationCenter` or a `Combine`
  `PassthroughSubject` is the idiomatic equivalent of `onSessionChange`'s
  listener set.
- **Compose / Android**: `OkHttp` or `Ktor` replaces `fetch`;
  `EncryptedSharedPreferences` or Android `DataStore` is the idiomatic token
  store. `androidx.credentials` (Credential Manager) is the platform
  equivalent of the WebAuthn/passkey ceremonies. A `SharedFlow` or
  `LiveData` is the idiomatic equivalent of `onSessionChange`.
- **WinUI 3**: `HttpClient` replaces `fetch`, with `System.Text.Json` for
  every JSON parse/serialize this component does inline (`tokensFromResponse`,
  `extractErrorMessage`/`extractErrorCode`, every request/response body).
  `Windows.Storage.ApplicationData.Current.LocalSettings` is the equivalent
  of `localStorage` for the cached user object; a native port SHOULD still
  route the access token through `Windows.Security.Credentials.PasswordVault`
  rather than plain settings, since WinUI has no localStorage-equivalent
  XSS exposure to justify the web tradeoff — this is a stricter choice than
  the web source makes, not a divergence from its contract (the refresh
  token is still never stored, on any platform). `Task`/`async`-`await`
  replaces every `Promise`; an `ObservableCollection`/`INotifyPropertyChanged`-backed
  session object, or a C# `event`, is the idiomatic equivalent of
  `onSessionChange`'s subscriber set. `Windows.Security.Credentials.UI`
  (Windows Hello / passkeys) is the platform equivalent of the WebAuthn
  ceremonies; there is no equivalent of a top-level browser navigation for
  the SSO/central-login flows, so a WinUI port needs `WebAuthenticationBroker`
  or an embedded `WebView2` to carry the AS round-trip that `sso.ts` does
  with `window.location.href`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/auth/src/account-security.ts` |
| web | `packages/web/packages/auth/src/asBase.ts` |
| web | `packages/web/packages/auth/src/client.ts` |
| web | `packages/web/packages/auth/src/config.ts` |
| web | `packages/web/packages/auth/src/labels.ts` |
| web | `packages/web/packages/auth/src/mfa.ts` |
| web | `packages/web/packages/auth/src/refresh.ts` |
| web | `packages/web/packages/auth/src/report.ts` |
| web | `packages/web/packages/auth/src/sso.ts` |
| web | `packages/web/packages/auth/src/tokens.ts` |
| web | `packages/web/packages/auth/src/types.ts` |

## Design Decisions

**Decision**: The refresh token from a backend response is never read or
persisted by this package — `tokensFromResponse` always writes
`refreshToken: ''` regardless of what the response body contains.
**Rationale**: Refresh and revoke are cookie-first against an HttpOnly
refresh cookie the server sets and reads; keeping the refresh token out of
`localStorage` means it is never exposed to any script running on the page,
which is the strongest defense a client-side store can offer against a
successful XSS. The `AuthTokens` shape still requires the field (for
interface compatibility), so it is blanked rather than omitted.
**Approved**: pending

**Decision**: `refreshAccessToken()` is single-flight (deduped via a
module-scoped `inFlight` promise) and guarded by a `generation` counter that
`invalidateRefresh()` bumps on every login/logout.
**Rationale**: Without dedup, N concurrently-401ing requests would each kick
off their own refresh POST, racing to rotate the same one-time refresh
cookie against each other. The generation guard exists because a refresh
that started before a fresh login or logout must not be allowed to write
stale tokens (or clear fresh ones) once it resolves — the source's own
comment calls this "a refresh racing a fresh login can't clobber the tokens
that login just adopted, nor clear them on logout."
**Approved**: pending

**Decision**: A losing concurrent refresh (a `401` on the rotated cookie)
waits exactly 300ms (`LOSER_RECHECK_DELAY_MS`) and re-reads storage once
before deciding whether to clear the session.
**Rationale**: Two uncoordinated single-flight mutexes (this copy of the
client plus a toolkit twin elsewhere in the fleet) can race over one rotated
refresh cookie; without the wait, the loser would clear a session the winner
is about to (or just did) successfully refresh. 300ms is documented in the
source as long enough for the winner's `writeTokens` to land in the common
case, chosen empirically rather than derived from a protocol constant.
**Approved**: pending

**Decision**: `exchangeSsoCode` retries its network POST exactly once, after
a 750ms pause, and only on a network-level failure (never on an HTTP error
response).
**Rationale**: The one-time exchange code is consumed only if a request
actually reaches the backend; a `fetch` that rejects (dropped connection,
offline blip) means the code was never consumed and a retry can still redeem
it. An HTTP error response means the code was already read and rejected (or
already spent) — retrying would only reproduce the same failure, never
improve the outcome. 750ms is chosen to survive a brief connection drop
without making the callback page feel hung, and stays well inside the
exchange code's server-side TTL.
**Approved**: pending

**Decision**: `preflightSsoReturn` fails closed to `false` on any ambiguous
outcome — a non-200, a thrown/rejected fetch, a wrong-shaped body, or a
timeout after 2000ms (`PREFLIGHT_TIMEOUT_MS`) — never defaulting to `true`.
**Rationale**: The preflight exists specifically to make the silent
cold-load SSO probe safe to run on any route, including a public landing
page: its one failure mode is a top-level navigation that strands the
visitor on the central login page. Failing closed costs an avatar (the
visitor stays anonymous, exactly as before); failing open costs the visitor
the page they asked for. 2000ms is chosen because the answer is a small,
uncached, single-row JSON read — long enough to absorb ordinary latency,
short enough that a wedged AS does not hang the page's loading state
indefinitely.
**Approved**: pending

**Decision**: `centralLoginStep` throws immediately, before any network
call, when no AS base is configured — it does not fall back to the
same-origin `/api` proxy the way `asEndpoint`'s other callers do.
**Rationale**: A relayed central login's `Set-Cookie` for the central
session is host-only on the AS host; routed through this site's own proxy,
that cookie would land on the brand site instead of the AS, appearing to
succeed (a session is minted, the header fills in) while establishing no
central session at all — silently degrading a cross-site login into a
site-only one, which is exactly the defect central login exists to remove.
Refusing loudly is the lesser harm: a misconfigured build fails visibly
instead of shipping a login that works once, on one site.
**Approved**: pending

**Decision**: `beginLinkProvider` stashes an unguessable CSRF nonce in
sessionStorage before navigating, and refuses to navigate at all (returns
`false`) if the nonce cannot be stashed.
**Rationale**: The link-mode OAuth round-trip's completion is later proven
to have been started by this same browser only by that nonce matching; a
forged `#link_code` URL a user is lured to carries no matching nonce and is
refused by the completing consumer. If the nonce cannot even be stashed
(storage blocked), the completion check is guaranteed to fail closed anyway,
so sending the user through the round-trip regardless would only spend a
navigation on a foregone failure.
**Approved**: pending

**Decision**: `isCrossApex`/`registrableDomain` compares only the last two
dot-separated labels of a hostname to decide apex equality, with no Public
Suffix List.
**Rationale**: This is correct for every domain the fleet currently uses —
all single-label TLDs (`.com`, `.ai`, `.studio`, `.today`, …) — and the
source comment explicitly flags the known limitation: a multi-label public
suffix (e.g. `example.co.uk`) would resolve to `co.uk` and mis-compare. This
is documented technical debt with a stated remediation path (switch to a
Public Suffix List) if such a domain is ever added, not an unresolved gap.
**Approved**: pending

**Decision**: `reportUnexpectedAuthError` duck-types a numeric `.status` off
any thrown `Error`, rather than checking `instanceof AuthHttpError`.
**Rationale**: A host that layers its own auth client on top of this package
can define its own, distinct `AuthHttpError`-shaped class; an `instanceof`
check would fail to recognize that class's 4xx errors as expected and would
report them as noise. Duck-typing the shape both classes share (a numeric
`status` field) is what lets one dedupe/gate implementation serve both.
**Approved**: pending

**Decision**: This recipe carries roughly 115 behavioral requirements across
eleven source files, deliberately more than a typical `ingredient` recipe.
**Rationale**: The component genuinely spans five distinct sub-contracts —
token storage/cache-scoping, single-flight cookie refresh, the Bearer-authed
fetch/error layer, cross-site SSO and central-login navigation (including
silent restore and provider linking), and self-serve MFA/WebAuthn enrollment
— each with its own exported operations, error paths, and (for four of the
five) dedicated test files. Per the cross-recipe-consistency guideline, this
depth is warranted by that count of distinct behaviors and error conditions,
not by a lack of scoping discipline; there is no sibling `auth`-family
recipe yet against which to check terminology or tag-vocabulary
consistency.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`secure-storage` is **partial**: the refresh token is deliberately never
persisted client-side and the CSRF nonce/return-to path live in
short-lived `sessionStorage`, but the access token and cached user object
sit in plaintext `localStorage` with no encryption — an accepted SPA
tradeoff (see Privacy), not full conformance. `input-sanitization` is
**partial**: `safeReturnTo` strictly validates and normalizes its one
security-sensitive input (the return-to URL), but credentials, MFA codes,
and OAuth codes/identifiers pass through every request body unvalidated by
this client, relying entirely on the server. `explicit-error-handling`
**passed**: every failure path in these 11 files either throws a typed
`AuthHttpError`/`Error` the caller can branch on, or (in `report.ts`) is an
intentional fail-safe swallow of a telemetry sink's own failure — no path
silently drops a primary operation's error. `fault-tolerance` **passed**:
the refresh single-flight/generation/resurrection guards, the loser-recheck
window, and `exchangeSsoCode`'s bounded retry all exist specifically to keep
concurrent and transient-failure paths from corrupting session state.
`data-minimization` **passed**: the refresh token is never collected;
`ErrorContext` is typed scalars-only. `no-pii-in-logs` **passed**: every
`console.error` call logs only an `Error` object and a declared
scalar-only context, never a request body or token. `no-hardcoded-strings`
**failed**: every user-facing string in `labels.ts`, `mfa.ts`, and
`client.ts`'s fallbacks is hardcoded English with no lookup table or locale
parameter anywhere in this component (see Localization) — this is a plain,
honestly-reported gap in the source, not a hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
