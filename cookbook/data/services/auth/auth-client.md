---
id: 3ea9329e-5acc-4c43-b5ce-bb8c50570104
title: Authentication Client
domain: agentictoolkit://cookbook/data/services/auth/auth-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Headless authentication client providing bearer-token sessions with
  single-flight refresh, SSO/central-login navigation, WebAuthn/MFA ceremonies,
  and account-security enrollment.'
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

# Authentication Client

## Overview

This recipe is a headless authentication client: eleven dependency-free
modules that together give a host application a bearer-token session backed
by a same-origin, cookie-based refresh mechanism, cross-site single sign-on
against a shared authorization server (the AS), MFA/WebAuthn completion (both
at login time and in self-serve account security), and an authenticated
request wrapper the rest of the app builds on. It has no visual surface of
its own — every UI component in the auth family (login forms, callback pages,
account-security screens) is a consumer of this contract, not part of it.

## Behavioral Requirements

- **default-runtime-config**: the runtime configuration MUST default to
  `{ storageKey: 'auth_tokens', refreshPath: '/api/auth/refresh' }` before it
  has ever been reconfigured.
- **configure-auth-merges**: reconfiguring auth with a partial update MUST
  shallow-merge that update onto the current configuration, leaving any field
  the update omits unchanged.
- **auth-api-base-resolution**: AS base resolution MUST return an explicitly
  supplied base when given, else an environment-configured base, with any
  trailing `/` characters stripped, and MUST return nothing when neither is
  set.
- **as-endpoint-proxy-fallback**: AS endpoint resolution for a path MUST
  return `${base}${path}` when a base resolves, and MUST return `/api${path}`
  (the same-origin proxy) when no base is configured.
- **auth-tokens-shape**: the token bundle MUST carry exactly an access token
  (string) and a refresh token (string).
- **auth-user-shape**: the user record MUST carry `id`, `email`, `name`,
  `avatarUrl` (string), `capabilities` (string list), `authMethods` (a list of
  auth-method records), and `attributes` (a list of attribute records), and
  MAY carry `slug` (string or nothing).
- **has-capability-null-safe**: the capability check MUST return true if and
  only if the user's capabilities include the requested capability, and MUST
  return false when the user is absent.
- **is-admin-derived**: the admin check MUST return the result of the
  capability check for `'admin'`.
- **tokens-from-response-precedence**: token extraction from a response body
  MUST prefer an `accessToken` field over a `token` field when both are
  present.
- **tokens-from-response-refresh-token-blanked**: token extraction MUST
  always set the returned refresh token to `''`, regardless of whether the
  response body carries one — refresh/revoke are cookie-first against an
  HttpOnly cookie, and any refresh-token field the backend returns is
  deliberately never read or persisted.
- **tokens-from-response-throws-when-absent**: token extraction MUST throw
  `Error('Token response missing token/accessToken')` when neither an
  `accessToken` nor a `token` field is present.
- **token-storage-key-configurable**: reading, writing, and clearing the
  stored token bundle MUST read, write, and remove a persistent client-side
  store entry named by the current configuration's storage key, as JSON.
- **token-read-off-browser-returns-null**: reading the stored token bundle
  (and therefore reading the stored access token) MUST return nothing when no
  interactive host environment is present (e.g. during server-side
  rendering).
- **token-read-malformed-json-returns-null**: reading the stored token bundle
  MUST return nothing when the stored value is not valid JSON, without
  throwing.
- **write-tokens-persists-and-announces**: writing the token bundle MUST
  persist it under the storage key and then invoke every subscriber
  registered for session-change notifications.
- **clear-tokens-clears-sibling-user-key**: clearing the token bundle MUST
  remove both the tokens entry and the sibling cached-user entry (keyed as
  `${storageKey}:user`), then invoke every session-change subscriber.
- **read-access-token-derivation**: reading the stored access token MUST
  return the token bundle's access token, or nothing if no bundle is stored.
- **session-change-subscription**: session-change subscription MUST register
  a callback to be called on every subsequent token write/clear, and MUST
  return an unsubscribe function that removes that callback from the
  subscriber set.
- **session-change-payload-free**: session-change subscribers MUST be
  invoked with no arguments — the announcement communicates only that the
  session moved, never what it moved to.
- **session-change-snapshot-iteration**: the session-change announcement MUST
  iterate a snapshot of the subscriber set, so a subscriber that unsubscribes
  itself or another subscriber from inside its own callback does not affect
  delivery to the other subscribers in that same announcement.
- **decode-base64url-json-utf8-strict**: base64url-JSON segment decoding MUST
  base64url-decode the segment and decode the resulting bytes as UTF-8 using
  a strict decoder — never substituting U+FFFD for an invalid byte sequence —
  before parsing the text as JSON.
- **decode-base64url-json-tolerates-missing-padding**: base64url-JSON segment
  decoding MUST tolerate a segment whose `=` padding was stripped, by
  re-padding to a multiple of 4 characters before decoding.
- **decode-base64url-json-never-throws**: base64url-JSON segment decoding
  MUST return nothing, never throw, for input that fails at any step —
  invalid base64, invalid UTF-8, or invalid JSON.
- **read-token-subject-derivation**: reading the token's subject claim MUST
  return the string `sub` claim decoded from the second dot-separated segment
  of the stored access token, and MUST return nothing when no token is
  stored, the token has no second segment, decoding fails, or `sub` is not a
  string.
- **read-user-validates-shape**: reading the cached user record MUST return
  nothing — never the malformed value — when the cached user blob is absent,
  lacks a string `id`, or lacks a list `capabilities`.
- **write-user-persists-off-browser-noop**: writing the cached user record
  MUST persist it under the cached-user key as JSON, and MUST be a no-op when
  no interactive host environment is present.
- **refresh-single-flight-dedup**: the refresh operation MUST return the
  same in-flight promise to every caller while a refresh is outstanding,
  issuing exactly one network request regardless of how many callers invoke
  it concurrently.
- **refresh-request-shape**: a refresh attempt MUST `POST` the literal body
  `'{}'` to the configured refresh path with credentials included and header
  `Content-Type: application/json`.
- **invalidate-refresh-bumps-generation**: refresh invalidation MUST
  increment the module's generation counter and MUST discard any outstanding
  in-flight refresh reference, so a fresh login or logout invalidates a
  refresh that started before it.
- **refresh-generation-guard**: if the generation counter has changed
  between the start of a refresh attempt and its response arriving, that
  attempt MUST resolve to nothing on the success path without writing or
  clearing the token bundle.
- **refresh-success-adopts-current-storage**: on a successful refresh
  response, a refresh attempt MUST compare the access token currently in
  storage against the one read at the start of the attempt; if storage no
  longer holds that starting token (cleared by a logout, or replaced by
  another login/refresh), the attempt MUST return the current stored token
  (or nothing if storage was cleared) instead of writing the newly fetched
  tokens, and MUST only write the token bundle when storage still holds the
  unchanged starting token.
- **refresh-failure-adopts-concurrent-winner**: on a non-OK refresh response,
  if storage's current access token already differs from the one this
  attempt started with, the attempt MUST return that current token rather
  than clearing it.
- **refresh-failure-loser-recheck-delay**: on a non-OK refresh response with
  no immediately visible concurrent winner, the attempt MUST wait exactly
  300ms and re-read storage once before deciding, adopting a winner's token
  if one appeared during the wait.
- **refresh-failure-clears-when-unresolved**: if, after the loser-recheck
  wait, storage still holds the access token this attempt started with, and
  the generation counter has not changed, the attempt MUST clear the token
  bundle and resolve to nothing.
- **refresh-network-error-reports-and-clears**: a thrown network or parse
  error during a refresh attempt MUST be reported via unconditional error
  reporting (tagged with feature `'auth'`, step `'tokenRefresh'`), and MUST
  then clear the token bundle (subject to the same generation guard) and
  resolve to nothing.
- **authed-fetch-bearer-attach**: the authenticated request helpers MUST
  attach `Authorization: Bearer <token>` to the request whenever a stored
  access token is present.
- **authed-fetch-default-content-type**: the underlying request step MUST
  default a `Content-Type: application/json` header whenever a body is set
  and no `Content-Type` header was already supplied.
- **authed-fetch-default-init**: the authenticated request helpers MAY be
  called with no request-options argument; each MUST default it to an empty
  object rather than requiring the caller to pass one.
- **authed-fetch-401-refresh-retry-once**: on a `401` response, the base
  authenticated request helper MUST call the refresh operation exactly once
  and, if it resolves to a token, MUST retry the original request exactly
  once with that token; it MUST NOT call the refresh operation again or
  retry a second time if the retried request also fails.
- **authed-fetch-throws-on-non-ok**: the base authenticated request helper
  MUST throw a typed HTTP error — carrying the response's HTTP status and
  any machine-readable code extracted from the parsed JSON body — for any
  final non-OK response, after the one refresh-and-retry has already been
  attempted.
- **authed-json-rejects-204**: the JSON-parsing request helper MUST throw
  `Error('Unexpected empty response (204 No Content); use authedRequest for
  endpoints with no body')` when the response status is `204`.
- **authed-request-discards-body**: the body-discarding request helper MUST
  perform an authenticated request and resolve to nothing, discarding the
  response body.
- **auth-http-error-shape**: the typed HTTP error MUST behave as an error,
  MUST expose a numeric `status` and an optional string `code`, and MUST set
  its name to `'AuthHttpError'`.
- **extract-error-message-precedence**: error-message extraction (given a
  body and a fallback) MUST return, in order: a string top-level `error`;
  else a string `message` on a nested `error` object; else a string
  top-level `message`; else (RFC 9457 problem+json) `detail` when the body
  also has a string `title` and a numeric `status`; else a string `title`;
  else the fallback.
- **extract-error-code-precedence**: error-code extraction MUST return a
  string `code` from a nested `error.code`, else a top-level `code`, else
  nothing.
- **read-error-message-single-parse**: single-parse error-message reading
  MUST parse the response body exactly once and pass that single parsed
  value to error-message extraction.
- **exchange-sso-code-request-shape**: the SSO code exchange MUST `POST`
  `{ code }` as JSON to an exchange path, which MUST default to
  `'/api/oauth/signin/exchange'`.
- **exchange-sso-code-network-retry-once**: the SSO code exchange MUST retry
  the POST exactly once, after a 750ms delay, only when the first attempt
  fails at the network level (the request itself throws/rejects), and MUST
  propagate the second attempt's outcome — including a second network
  failure — without retrying again.
- **exchange-sso-code-no-http-retry**: the SSO code exchange MUST NOT retry
  when the server returns any HTTP response, including a non-OK one; only a
  network-level failure triggers the retry.
- **exchange-sso-code-success-result**: on a `2xx` response, the SSO code
  exchange MUST return `{ tokens, user }`, where `tokens` is built via token
  extraction and `user` is the response body's `user` field.
- **exchange-sso-code-failure-throws**: on a non-OK response, the SSO code
  exchange MUST throw a typed HTTP error carrying the status and the
  message/code extracted from the parsed body, with fallback message
  `'Sign-in failed'`.
- **link-provider-routes-to-as-host**: the provider-link request MUST
  resolve its target via AS endpoint resolution for `/auth/link-provider` —
  the authorization server directly, never a hard-coded same-origin path —
  falling back to `/api/auth/link-provider` only when no AS base is
  configured.
- **link-provider-authed-post**: the provider-link request MUST `POST` its
  input (`clientSlug`, `providerSlug`, `code`, `redirectUri`) as JSON through
  the body-discarding authenticated request helper (Bearer-authed, with the
  same one-refresh-then-retry waterfall as any other authenticated call), and
  MUST resolve on success or throw a typed HTTP error on failure.
- **retry-marker-hook**: the retry-marker hook MUST register a callback to be
  invoked with the exact request-options object handed to the underlying
  request step for a retried request — a post-refresh retry in the base
  authenticated request helper, or the network-failure retry in the SSO code
  exchange; passing nothing MUST unregister it, and with no callback
  registered, marking MUST be a silent no-op.
- **webauthn-assertion-ceremony-shared**: the shared WebAuthn assertion
  ceremony MUST `POST` a body to an options URL, throw using single-parse
  error-message reading on a non-OK response, otherwise run the platform's
  WebAuthn assertion ceremony with the returned options and return
  `{ token, response }`.
- **assert-second-factor-body**: the second-factor assertion MUST run the
  shared ceremony with body `{ token }` and fallback error `'Could not start
  the passkey check.'`.
- **assert-passwordless-passkey-body**: the passwordless-passkey assertion
  MUST run the shared ceremony with body `{ identifier }` and fallback error
  `'No passkey is available for this account.'`.
- **request-login-sms**: requesting a login SMS code MUST `POST` `{ token }`
  to a fixed same-origin SMS-send path and MUST throw on a non-OK response,
  with fallback message `'Could not send a code.'`.
- **complete-login-code**: completing login with a code MUST `POST`
  `{ token, method, code }` to `/api/auth/login/mfa` and return the parsed
  response on success, else throw with fallback `'That code didn't match.'`.
- **complete-login-passkey**: completing login with a passkey MUST run the
  second-factor assertion against a fixed same-origin WebAuthn-options path,
  then `POST` the resulting assertion to `/api/auth/login/mfa/webauthn`,
  returning the parsed response or throwing with fallback `'Passkey
  verification failed.'`.
- **passwordless-passkey-login**: passwordless passkey login MUST run the
  passwordless-passkey assertion against a fixed same-origin passkey-options
  path, then `POST` the resulting assertion to `/api/auth/login/webauthn`,
  returning the parsed response or throwing with fallback `'Passkey login
  failed.'`.
- **begin-login-navigation**: beginning login MUST be a no-op when no
  interactive host environment is present; otherwise it MUST stash a
  supplied return-to value when given and navigate the top-level view to the
  AS `/oauth/signin/authorize` URL for the given client id (default `'adh'`)
  and a return URL equal to `${origin}${callbackPath ?? '/auth/callback'}`.
- **authorize-url-shape**: building the authorize URL MUST resolve
  `/oauth/signin/authorize` via AS endpoint resolution and MUST include
  `clientId` and `return` query parameters, plus a `prompt` parameter only
  when one is given.
- **provider-signin-url-shape**: building the provider sign-in URL MUST
  resolve `/oauth/signin/start` via AS endpoint resolution with `clientId`,
  `providerId`, and `return` query parameters.
- **sso-hint-cookie-check**: the SSO-hint cookie check MUST return true if
  and only if a cookie named `adh_sso_hint` is present, and MUST return
  false when no interactive host environment is present.
- **sso-checked-guard-tolerates-storage-failure**: marking and clearing the
  once-per-tab restore guard MUST set/remove a fixed session-scoped flag
  (`adh_sso_checked`) and MUST swallow a thrown storage exception without
  propagating it.
- **silent-restore-guard-order**: the silent-restore decision MUST return
  false, checked in this order, when: no interactive host environment is
  present; the inbound fragment carries an SSO code/error (mid-flow); this
  tab has already checked; or no AS base is configured — all before any hint
  or cross-apex evidence is consulted.
- **silent-restore-evidence**: given none of the guards above apply, the
  silent-restore decision MUST return true when the SSO-hint cookie is
  present, and otherwise MUST return true if and only if the site is
  cross-apex with the configured AS host.
- **registrable-domain-apex-comparison**: the cross-apex comparison MUST
  compare the last two dot-separated labels of the AS host and the current
  hostname, treating them as different registrable domains if and only if
  those two-label suffixes differ.
- **preflight-sso-return-contract**: the silent-restore preflight check MUST
  `GET` the AS `/oauth/signin/preflight` endpoint (resolved via AS endpoint
  resolution) with `clientId` and `return` query parameters and credentials
  omitted, and MUST return true if and only if the response is OK and its
  parsed JSON body has `allowed === true`; any other outcome — non-OK,
  thrown/rejected request, or a body without `allowed === true` — MUST
  return false.
- **preflight-sso-return-timeout**: the silent-restore preflight check MUST
  bound its request with a 2000ms timeout when a runtime timeout primitive is
  available, and MUST proceed without one when it is not.
- **begin-silent-login-flow**: beginning a silent login attempt MUST return
  false without navigating when no interactive host environment is present;
  MUST always mark the once-per-tab restore guard first; MUST return false
  without navigating when no AS base is configured or when the silent-restore
  preflight check resolves false for the current URL; and, only when
  preflight allows it, MUST navigate the top-level view to the AS authorize
  URL with `prompt: 'none'` and a return URL equal to
  `${origin}${pathname}${search}` (dropping any existing fragment), returning
  true.
- **parse-inbound-sso**: parsing an inbound SSO fragment MUST return
  `{ code }` when the fragment has a `code` param, else `{ error }` when it
  has an `error` param, else nothing — including for an empty or absent
  fragment.
- **strip-sso-fragment-preserves-other-keys**: stripping the SSO fragment
  MUST remove only the `code` and `error` keys from the fragment, preserving
  every other key-value pair (e.g. a site-switch marker or scroll anchor) in
  its original order, and MUST return `''` when nothing remains.
- **sso-logout-navigation**: SSO logout MUST be a no-op when no interactive
  host environment is present; otherwise it MUST navigate the top-level view
  to the AS `/oauth/signin/logout` endpoint with `clientId` (default
  `'adh'`) and `return` (default `${origin}/`) query parameters.
- **sso-switch-url**: building a site-switch URL MUST return the destination
  URL unchanged when no AS base is configured, and otherwise MUST return a
  `prompt=none` authorize URL whose `return` parameter is the destination
  URL.
- **current-return-to**: the current return-to value MUST equal
  `${pathname}${search}${hash}` of the current location, and MUST return
  nothing when no interactive host environment is present.
- **safe-return-to-rejects-cross-origin**: the safe return-to check MUST
  return nothing for an absent/empty input or for a value that, resolved
  against the current origin, yields a different origin (an open-redirect
  defense that also refuses a protocol-relative `//evil.com/x` form), and
  otherwise MUST return only the resolved URL's `pathname + search + hash`,
  never the raw string.
- **stash-and-take-return-to-single-use**: stashing the return-to value MUST
  persist it in a session-scoped store under a fixed key, swallowing a
  thrown storage exception; taking the return-to value MUST read and remove
  that key (single use) and MUST return the result of the safe return-to
  check on the stored value, or nothing when no interactive host environment
  is present or a storage exception is thrown.
- **read-central-params**: reading relayed central-login parameters MUST
  return nothing when the query has no `return` parameter, and otherwise
  MUST return `{ clientId, returnUrl }` with `clientId` defaulting to
  `'adh'`.
- **central-login-target-resolution**: resolving the central-login target
  MUST return the AS-relayed `{ clientId, returnUrl }` unchanged (via
  reading relayed central-login parameters) when present; otherwise it MUST
  stash a supplied return-to value when given and synthesize
  `{ clientId, returnUrl: \`${origin}${callbackPath ?? '/auth/callback'}\` }`.
- **central-login-step-refuses-without-as-base**: a central-login step MUST
  throw, without making any network request, when no AS base is configured
  for the given target — it MUST NOT silently fall back to the same-origin
  proxy the way AS endpoint resolution does for other callers.
- **central-login-step-outcomes**: a central-login step MUST return the
  parsed MFA-challenge body on a `202` response; MUST navigate the top-level
  view to the response's `redirectUrl` and return nothing on any other OK
  response; and MUST throw a typed HTTP error (status + extracted
  message/code, with fallback `` `Server error (${status})` `` for a `5xx`
  and `'Login failed'` otherwise) on a non-OK, non-`202` response.
- **central-login-step-request-shape**: every central-login step POST MUST
  include credentials included and a JSON body merging the caller's fields
  with `clientId` and `return` (the target's return URL).
- **central-email-login**: central email/password login MUST `POST`
  `{ identifier, password }` (plus `clientId`/`return`) to
  `/oauth/signin/login` via a central-login step.
- **central-send-mfa-sms**: central SMS MFA send MUST `POST` `{ token }` to
  the SMS-send path on the AS and throw a typed HTTP error on a non-OK
  response, with fallback message `'Could not send a code.'`.
- **central-complete-mfa-code**: central MFA code completion MUST `POST`
  `{ token, method, code }` to `/oauth/signin/login/mfa` via a central-login
  step.
- **central-complete-mfa-passkey**: central MFA passkey completion MUST run
  the shared WebAuthn assertion ceremony against the AS's MFA options
  endpoint, then `POST` the assertion to `/oauth/signin/login/mfa/webauthn`
  via a central-login step.
- **central-passwordless-passkey**: central passwordless passkey login MUST
  run the passwordless assertion ceremony against the AS's passkey options
  endpoint, then `POST` the assertion to `/oauth/signin/login/webauthn` via a
  central-login step.
- **begin-link-provider-csrf-nonce**: beginning a provider-link MUST
  generate a random nonce, MUST stash it in a session-scoped store under a
  fixed key BEFORE navigating, and MUST return false without navigating when
  the nonce cannot be stashed; otherwise it MUST navigate the top-level view
  to the AS `/oauth/signin/start` URL with `link=1`, `clientId`,
  `providerId`, `return`, and `linkNonce` query parameters, returning true.
- **mfa-status-fetch**: fetching MFA status MUST `GET` `/api/account/mfa`
  through the JSON-parsing authenticated request helper and return the
  parsed MFA-status body.
- **totp-enroll**: enrolling TOTP MUST `POST` `/api/account/mfa/totp/enroll`
  through the JSON-parsing authenticated request helper and return
  `{ secret, otpauthUri }`.
- **totp-confirm**: confirming a TOTP code MUST `POST` `{ code }` to
  `/api/account/mfa/totp/confirm` through the JSON-parsing authenticated
  request helper.
- **totp-remove**: removing TOTP MUST `DELETE` `/api/account/mfa/totp`
  through the body-discarding authenticated request helper.
- **webauthn-list**: listing WebAuthn credentials MUST `GET`
  `/api/account/mfa/webauthn` through the JSON-parsing authenticated request
  helper and return `{ items }`.
- **webauthn-register-ceremony**: registering a WebAuthn credential MUST
  `POST` `{ kind }` to `/api/account/mfa/webauthn/register/options` through
  the JSON-parsing authenticated request helper, run the platform's WebAuthn
  registration ceremony with the returned options, then `POST`
  `{ token, response, name }` to `/api/account/mfa/webauthn/register/verify`
  through the JSON-parsing authenticated request helper.
- **webauthn-remove**: removing a WebAuthn credential MUST `DELETE`
  `` `/api/account/mfa/webauthn/${encodeURIComponent(id)}` `` through the
  body-discarding authenticated request helper.
- **recovery-codes-regenerate**: regenerating recovery codes MUST `POST`
  `/api/account/mfa/recovery/regenerate` through the JSON-parsing
  authenticated request helper and return `{ codes }`.
- **preferred-method-set**: setting the preferred MFA method MUST `PUT`
  `{ method }` to `/api/account/mfa/preference` through the JSON-parsing
  authenticated request helper and return `{ preferredMethod }`.
- **account-security-authed**: every account-security operation MUST go
  through the JSON-parsing or body-discarding authenticated request helper —
  Bearer-authed, with the same one-refresh-then-retry-on-401 waterfall as any
  other authenticated call — never a bare, unauthenticated request.
- **report-unexpected-status-gate**: unexpected-error reporting MUST NOT
  report (to the injected sink or the console) an error whose numeric status
  (duck-typed off any thrown error, not just this contract's own typed HTTP
  error) is less than 500 — an expected 4xx from either this contract's or a
  host's own error type.
- **report-unexpected-dedup-window**: unexpected-error reporting MUST report
  at most once per exact `` `${message}|${JSON.stringify(context)}` ``
  signature per 60000ms window, dropping duplicate reports of the same
  signature within that window.
- **report-auth-error-unconditional**: unconditional error reporting MUST
  call the injected reporter (if one is registered) and MUST always log the
  error to the console, regardless of the error's status.
- **report-never-throws**: unconditional error reporting MUST swallow any
  exception thrown by the injected reporter and MUST NOT propagate it to the
  caller.
- **set-auth-error-reporter-hook**: the error-reporter hook MUST register a
  callback as the sink error reporting calls; passing nothing MUST
  unregister it, leaving console-only reporting.
- **provider-label-known-and-fallback**: the provider label lookup MUST
  return `'GitHub'` for `'github'`, `'Google'` for `'google'`, and otherwise
  the slug with only its first character capitalized.
- **oauth-error-message-known-codes-and-fallback**: the OAuth error message
  lookup MUST return a fixed message for `'account_exists'`,
  `'user_not_found'`, and `'signups_closed'`; MUST return a fixed
  login-disabled body for `'login_disabled'`; and MUST otherwise return the
  code verbatim inside `` `Sign-in failed (${code})` ``.
- **link-copy-provider-substitution**: every account-linking modal copy
  function MUST substitute the provider label lookup's result for the given
  provider slug into its returned string.

### Security

This recipe is a security-relevant recipe: it handles bearer session tokens,
a cookie-based refresh mechanism, second-factor secrets, WebAuthn ceremonies,
and cross-site redirect targets. The following requirements are this
recipe's dedicated security treatment; each restates or cross-references a
requirement above under its security framing rather than duplicating its
mechanics.

- **sensitive-data-classification**: The following are sensitive within this
  contract: the access token (bearer credential), the deliberately-never-read
  refresh token, the cached user record, TOTP secrets/`otpauthUri`, WebAuthn
  registration/assertion payloads, recovery codes, the CSRF link nonce, and
  the return-to path (open-redirect surface via
  **safe-return-to-rejects-cross-origin**).
- **access-token-transmission**: The access token MUST be attached only via
  the `Authorization: Bearer` header (**authed-fetch-bearer-attach**) and
  MUST NEVER appear in a URL query string, a log message, or an error
  report's context value (the error-report context type is explicitly
  scalars-only — see **report-unexpected-status-gate**).
- **refresh-token-never-persisted**: The refresh token MUST NOT be read from
  a backend response or written to any client-side store —
  **tokens-from-response-refresh-token-blanked** always blanks it to `''`;
  refresh and revoke are cookie-first against an HttpOnly, server-controlled
  cookie this recipe never reads.
- **open-redirect-violation-handling**: A stashed or query-supplied
  return-to value that resolves to a different origin MUST be rejected
  outright (returned as nothing), never partially trusted or redirected to —
  see **safe-return-to-rejects-cross-origin**.
- **link-csrf-violation-handling**: A provider-link completion MUST be
  refused (fails closed, no navigation) when its CSRF nonce cannot be
  stashed before the redirect — see **begin-link-provider-csrf-nonce**; a
  completion callback whose returned nonce does not match the stashed one is
  rejected by the completing consumer (outside this recipe's own logic, but
  the nonce this recipe mints and stashes is the entire defense).
- **token-subject-not-an-authorization-decision**: The unverified, locally
  decoded subject claim read by **read-token-subject-derivation** MUST be
  used only for client-side cache scoping (keying cached data to the current
  principal so an account switch in another tab cannot serve stale rows) and
  MUST NEVER be used as an authorization decision — the token is not
  signature-verified client-side.

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
| auth-client-001 | default-runtime-config | The runtime configuration read with no prior reconfiguration | `{ storageKey: 'auth_tokens', refreshPath: '/api/auth/refresh' }` |
| auth-client-002 | configure-auth-merges | Reconfiguring with `{ storageKey: 'x' }`, then reading the configuration | `refreshPath` unchanged; `storageKey === 'x'` |
| auth-client-003 | auth-api-base-resolution | AS base resolution given `'https://x.example.com/'` explicitly | `'https://x.example.com'` (trailing slash stripped) |
| auth-client-004 | as-endpoint-proxy-fallback | AS endpoint resolution for `/a` with no base and no environment variable set | `'/api/a'` |
| auth-client-005 | auth-tokens-shape | `{ accessToken: 'a', refreshToken: 'b' }` assigned as the token bundle | Valid; no other fields required or permitted |
| auth-client-006 | auth-user-shape | A user record omitting `slug` | Valid |
| auth-client-007 | has-capability-null-safe | The capability check applied to an absent user and `'billing'` | `false` |
| auth-client-008 | is-admin-derived | The admin check applied to a user with capabilities `['user', 'admin']` | `true` |
| auth-client-009 | tokens-from-response-precedence | Token extraction from `{ accessToken: 'A', token: 'T' }` | `{ accessToken: 'A', refreshToken: '' }` |
| auth-client-010 | tokens-from-response-refresh-token-blanked | Token extraction from a body carrying `{ token: 'T', refreshToken: 'server-rt' }` | `refreshToken === ''` |
| auth-client-011 | tokens-from-response-throws-when-absent | Token extraction from `{}` | Throws `/missing token/i` |
| auth-client-012 | token-storage-key-configurable | Reconfiguring with `{ storageKey: 'other_key' }`, then writing the token bundle | The persistent store holds a value under `'other_key'`; the default key is absent |
| auth-client-013 | token-read-off-browser-returns-null | Reading the token bundle with no interactive host environment present | Nothing |
| auth-client-014 | token-read-malformed-json-returns-null | The persistent store holds `'not json'` under the tokens key; reading the token bundle | Nothing |
| auth-client-015 | write-tokens-persists-and-announces | Subscribing to session changes, then writing the token bundle | Subscriber invoked exactly once; storage contains the tokens |
| auth-client-016 | clear-tokens-clears-sibling-user-key | Writing the cached user record, then clearing the token bundle | Reading the cached user record returns nothing; tokens key absent |
| auth-client-017 | read-access-token-derivation | Writing `{ accessToken: 'A', refreshToken: '' }`, then reading the stored access token | `'A'` |
| auth-client-018 | session-change-subscription | Subscribing, then unsubscribing, then writing the token bundle | The subscriber is not called |
| auth-client-019 | session-change-payload-free | Subscribing, then writing the token bundle | The subscriber is called with zero arguments |
| auth-client-020 | session-change-snapshot-iteration | Subscriber A unsubscribes subscriber B from inside A's own callback, both registered before one write | B is still invoked for that same announcement |
| auth-client-021 | decode-base64url-json-utf8-strict | Base64url-JSON decoding of an encoded `{ name: '東京' }` | `{ name: '東京' }` |
| auth-client-022 | decode-base64url-json-tolerates-missing-padding | Unpadded base64url of `{ sub: 'u', iat: 1 }` | `{ sub: 'u', iat: 1 }` |
| auth-client-023 | decode-base64url-json-never-throws | Base64url-JSON decoding of an invalid byte sequence | Nothing, no throw |
| auth-client-024 | read-token-subject-derivation | An access token whose second segment decodes to `{ sub: 'user-1' }`, stored | Reading the token's subject claim returns `'user-1'` |
| auth-client-025 | read-user-validates-shape | The persistent store holds `{"name":"x"}` (no `id`/`capabilities`) under the user key | Reading the cached user record returns nothing |
| auth-client-026 | write-user-persists-off-browser-noop | Writing the cached user record with no interactive host environment present | No throw; no storage write |
| auth-client-027 | refresh-single-flight-dedup | Two concurrent refresh calls, the underlying request resolving `{ token: 'NEW' }` | The underlying request is issued exactly once; both results are `'NEW'` |
| auth-client-028 | refresh-request-shape | The refresh operation invoked | Request issued with method `'POST'`, credentials included, body `'{}'` |
| auth-client-029 | invalidate-refresh-bumps-generation | A refresh in flight; refresh invalidation called | The next refresh call starts a fresh in-flight attempt, not the old one |
| auth-client-030 | refresh-generation-guard | A refresh in flight; refresh invalidation fires before the response lands; response then resolves OK | Result is nothing; no token bundle write |
| auth-client-031 | refresh-success-adopts-current-storage | A refresh in flight; clearing the token bundle (logout) fires before the OK response lands | Result is nothing; storage stays cleared |
| auth-client-032 | refresh-success-adopts-current-storage | A refresh in flight; a concurrent write of `{ accessToken: 'WINNER' }` fires before this attempt's OK response lands with `{ token: 'MINE' }` | Result is `'WINNER'`; storage still `'WINNER'` |
| auth-client-033 | refresh-failure-adopts-concurrent-winner | Non-OK response; storage already holds a token different from the one this attempt started with | Result is that current stored token; no clearing |
| auth-client-034 | refresh-failure-loser-recheck-delay | Non-OK response; a winner's write of `{ accessToken: 'WINNER' }` lands during the 300ms wait | After the wait, result is `'WINNER'` |
| auth-client-035 | refresh-failure-clears-when-unresolved | Non-OK response; no winner appears during the 300ms wait | Result is nothing; the token bundle is cleared |
| auth-client-036 | refresh-network-error-reports-and-clears | The underlying request rejects with a network-level error | Unconditional error reporting called with `{ feature: 'auth', step: 'tokenRefresh' }`; result nothing; tokens cleared |
| auth-client-037 | authed-fetch-bearer-attach | Writing `{ accessToken: 'TOK' }`, then an authenticated request to `/api/x` | Request header `Authorization: 'Bearer TOK'` |
| auth-client-038 | authed-fetch-default-content-type | The JSON-parsing helper called against `/api/x` with a stringified empty-object body and no `Content-Type` given | Sent request has `Content-Type: application/json` |
| auth-client-039 | authed-fetch-default-init | The base authenticated request helper called against `/api/x` with no options argument | Resolves normally; no throw reading request options |
| auth-client-040 | authed-fetch-401-refresh-retry-once | First request → `401`; refresh → `{ token: 'NEW' }`; retry → `200` | 3 underlying requests total; final result uses `Authorization: 'Bearer NEW'` |
| auth-client-041 | authed-fetch-throws-on-non-ok | Response not OK, status `500`, JSON body `{ error: 'boom' }` | Throws a typed HTTP error with message `'boom'`, `status === 500` |
| auth-client-042 | authed-json-rejects-204 | Response OK, status `204` | Throws `/Unexpected empty response/` |
| auth-client-043 | authed-request-discards-body | The body-discarding helper called against `/api/x` with method `DELETE` on a `200` response with a JSON body | Resolves to nothing; body never parsed by the caller |
| auth-client-044 | auth-http-error-shape | A typed HTTP error constructed with status `409`, message `'conflict'`, code `'ALREADY_LINKED'` | `.status === 409`, `.code === 'ALREADY_LINKED'`, `.name === 'AuthHttpError'`, behaves as an error |
| auth-client-045 | extract-error-message-precedence | Error-message extraction on `{ error: 'E' }`, `{ message: 'M' }`, `{ title: 'T' }`, `{}`, each with fallback `'fb'` | `'E'`, `'M'`, `'T'`, `'fb'` respectively |
| auth-client-046 | extract-error-message-precedence | Error-message extraction on `{ title: 'Bad Request', status: 400, detail: 'no GitHub App is configured' }` with fallback `'fb'` | `'no GitHub App is configured'` (RFC 9457 `detail` wins) |
| auth-client-047 | extract-error-code-precedence | Error-code extraction on `{ error: { code: 'X' } }` and on `{}` | `'X'` and nothing respectively |
| auth-client-048 | read-error-message-single-parse | The response's body-parse mocked to resolve once with `{ message: 'M' }` | Returns `'M'`; the body is parsed exactly once |
| auth-client-049 | exchange-sso-code-request-shape | The SSO code exchange called with `'code-1'` | `POST` to `'/api/oauth/signin/exchange'` with body `{"code":"code-1"}` |
| auth-client-050 | exchange-sso-code-network-retry-once | First request rejects (network-level), second resolves `200` with tokens | The underlying request is issued twice; result resolves with the tokens |
| auth-client-051 | exchange-sso-code-no-http-retry | The underlying request resolves not OK, status `401` | The underlying request is issued once per exchange call — no internal retry |
| auth-client-052 | exchange-sso-code-success-result | `200` response with `{ token: 'A', user: { id: 'u1' } }` | `{ tokens: { accessToken: 'A', refreshToken: '' }, user: { id: 'u1' } }` |
| auth-client-053 | exchange-sso-code-failure-throws | `401` response with `{ error: { message: 'invalid or expired exchange code' } }` | Throws a typed HTTP error with that message |
| auth-client-054 | link-provider-routes-to-as-host | The AS base environment variable set to `'https://api.example.com'`; the provider-link request invoked | Underlying request targets `'https://api.example.com/auth/link-provider'` |
| auth-client-055 | link-provider-authed-post | Writing `{ accessToken: 'at' }`, then the provider-link request | Request header `authorization: 'Bearer at'`; body deep-equals the input |
| auth-client-056 | retry-marker-hook | The retry-marker hook registered; a post-refresh retry occurs | The registered callback is called once with the retried request's options |
| auth-client-057 | webauthn-assertion-ceremony-shared | The options endpoint returns not OK | The shared ceremony throws using the extracted/fallback message |
| auth-client-058 | assert-second-factor-body | The second-factor assertion called with `('tok', url)` | The options POST body is `{"token":"tok"}` |
| auth-client-059 | assert-passwordless-passkey-body | The passwordless-passkey assertion called with `('id', url)` | The options POST body is `{"identifier":"id"}` |
| auth-client-060 | request-login-sms | Requesting a login SMS code with `'tok'` | `POST` to `'/api/auth/login/mfa/sms/send'` with `{"token":"tok"}` |
| auth-client-061 | complete-login-code | Completing login with `('tok', 'totp', '123456')` on a `200` | `POST` to `'/api/auth/login/mfa'`; returns the parsed body |
| auth-client-062 | complete-login-passkey | Completing login with a passkey given `'tok'` | `POST` to `'/api/auth/login/mfa/webauthn'` with the ceremony's `{ token, response }` |
| auth-client-063 | passwordless-passkey-login | Passwordless passkey login given `'id'` | `POST` to `'/api/auth/login/webauthn'` with the ceremony's `{ token, response }` |
| auth-client-064 | begin-login-navigation | Beginning login with `{ clientId: 'cookbook', authApiBase: 'https://api.hub.example.com' }` | The top-level view's target origin is `'https://api.hub.example.com'`, path `/oauth/signin/authorize`, `clientId=cookbook`, `return=<site>/auth/callback` |
| auth-client-065 | authorize-url-shape | Building the authorize URL with `{ clientId: 'adh', returnUrl: 'r', prompt: 'none' }` | Query has `clientId=adh`, `return=r`, `prompt=none` |
| auth-client-066 | provider-signin-url-shape | Building the provider sign-in URL with `{ clientId: 'adh', providerId: 'github', returnUrl: 'r' }` | Path `/oauth/signin/start`; query has `clientId`, `providerId`, `return` |
| auth-client-067 | sso-hint-cookie-check | The SSO-hint cookie present | The SSO-hint cookie check returns `true` |
| auth-client-068 | sso-checked-guard-tolerates-storage-failure | The session-scoped store's write mocked to throw | Marking the once-per-tab restore guard does not throw |
| auth-client-069 | silent-restore-guard-order | The inbound fragment carries `#code=abc` | The silent-restore decision returns `false` regardless of hint |
| auth-client-070 | silent-restore-evidence | No hint cookie, same-apex site | The silent-restore decision on an empty fragment returns `false` |
| auth-client-071 | registrable-domain-apex-comparison | AS host `api.agenticdeveloperhub.com`, site host `cookbook.com` | Treated as cross-apex; the silent-restore decision may return `true` even without a hint |
| auth-client-072 | preflight-sso-return-contract | Preflight response `{ allowed: true }`, `200` | The preflight check returns `true` |
| auth-client-073 | preflight-sso-return-contract | The preflight request throws | The preflight check returns `false` |
| auth-client-074 | preflight-sso-return-timeout | The preflight request never resolves | The preflight check resolves `false` after ~2000ms via its timeout |
| auth-client-075 | begin-silent-login-flow | No AS base configured | Beginning a silent login attempt returns `false`; the once-per-tab guard is still marked; no navigation |
| auth-client-076 | begin-silent-login-flow | AS base configured; preflight resolves `true` | Beginning a silent login attempt returns `true`; navigates to the authorize URL with `prompt=none` |
| auth-client-077 | parse-inbound-sso | Parsing `'#code=abc'`, `'#error=login_required'`, `''` | `{ code: 'abc' }`, `{ error: 'login_required' }`, nothing |
| auth-client-078 | strip-sso-fragment-preserves-other-keys | Stripping `'#site-switch&code=abc'` | `'#site-switch'` |
| auth-client-079 | sso-logout-navigation | SSO logout with `{ clientId: 'cookbook', authApiBase: 'https://api.hub.example.com' }` | Navigates to `/oauth/signin/logout` with `clientId=cookbook`, `return=<origin>/` |
| auth-client-080 | sso-switch-url | No AS base configured; building a site-switch URL for `'https://site.example.com/home'` | Returns `'https://site.example.com/home'` unchanged |
| auth-client-081 | current-return-to | The current location is `/a?b=1#c` | The current return-to value is `'/a?b=1#c'` |
| auth-client-082 | safe-return-to-rejects-cross-origin | Taking the return-to value with a stashed `'//evil.com/x'` | Returns nothing; storage key cleared |
| auth-client-083 | safe-return-to-rejects-cross-origin | A stashed value `'https://site.example.com/home?x=1#y'` (same origin, absolute) | Returns `'/home?x=1#y'` |
| auth-client-084 | stash-and-take-return-to-single-use | Stashing `'/home/x'`, then taking the return-to value twice | First call `'/home/x'`; second call nothing |
| auth-client-085 | read-central-params | Reading relayed parameters from `'?return=https%3A%2F%2Fx.example.com%2Fcb'` | `{ clientId: 'adh', returnUrl: 'https://x.example.com/cb' }` |
| auth-client-086 | read-central-params | Reading relayed parameters from `'?clientId=adh'` (no `return`) | Nothing |
| auth-client-087 | central-login-target-resolution | The current query carries a relayed `return`/`clientId` | Resolving the central-login target returns those relayed values, not a synthesized target |
| auth-client-088 | central-login-step-refuses-without-as-base | No AS base configured; central email/password login invoked | Throws before any network request; the underlying request is never issued |
| auth-client-089 | central-login-step-outcomes | Central email/password login's response `202` with an MFA-challenge body | Returns that challenge; no navigation |
| auth-client-090 | central-login-step-outcomes | Central email/password login's response `200` with `{ redirectUrl: 'https://bitbag.example.com/auth/callback#code=abc' }` | The top-level view navigates to that URL; the function returns nothing |
| auth-client-091 | central-login-step-request-shape | Central email/password login invoked with a credentials object | Request has credentials included; body includes `clientId`/`return` merged with `identifier`/`password` |
| auth-client-092 | central-email-login | Central email/password login with `{ identifier: 'a@b.com', password: 'p', clientId: 'adh', returnUrl: 'r' }` | `POST` to `'/oauth/signin/login'` with `{identifier,password,clientId,return}` |
| auth-client-093 | central-send-mfa-sms | Non-OK response from the SMS-send path on the AS | Throws a typed HTTP error with fallback `'Could not send a code.'` |
| auth-client-094 | central-complete-mfa-code | Central MFA code completion with `(target, 'tok', 'sms', '123456')` | `POST` to `'/oauth/signin/login/mfa'` via a central-login step |
| auth-client-095 | central-complete-mfa-passkey | Central MFA passkey completion with `(target, 'tok')` | The ceremony runs against the AS's MFA options endpoint, then `POST` to `'/oauth/signin/login/mfa/webauthn'` |
| auth-client-096 | central-passwordless-passkey | Central passwordless passkey login with `(target, 'id')` | The ceremony runs against the AS's passkey options endpoint, then `POST` to `'/oauth/signin/login/webauthn'` |
| auth-client-097 | begin-link-provider-csrf-nonce | Beginning a provider-link with `{ providerId: 'github', returnTo: '/home' }` | Navigates to the AS `/oauth/signin/start` with `link=1`; the stashed nonce equals the `linkNonce` query value |
| auth-client-098 | begin-link-provider-csrf-nonce | The session-scoped store's write mocked to throw | Beginning a provider-link returns `false`; no navigation occurs |
| auth-client-099 | mfa-status-fetch | Fetching MFA status on a `200` with an MFA-status body | `GET /api/account/mfa`; returns the parsed body |
| auth-client-100 | totp-enroll | Enrolling TOTP on a `200` with `{ secret, otpauthUri }` | `POST /api/account/mfa/totp/enroll`; returns that body |
| auth-client-101 | totp-confirm | Confirming a TOTP code with `'123456'` | `POST /api/account/mfa/totp/confirm` with `{"code":"123456"}` |
| auth-client-102 | totp-remove | Removing TOTP | `DELETE /api/account/mfa/totp` |
| auth-client-103 | webauthn-list | Listing WebAuthn credentials on a `200` with `{ items: [...] }` | `GET /api/account/mfa/webauthn`; returns that body |
| auth-client-104 | webauthn-register-ceremony | Registering a WebAuthn credential with `('passkey', 'My key')` | An options POST, then the registration ceremony, then a verify POST with `{ token, response, name: 'My key' }` |
| auth-client-105 | webauthn-remove | Removing a WebAuthn credential `'cred id/with slash'` | The delete path has the id percent-encoded |
| auth-client-106 | recovery-codes-regenerate | Regenerating recovery codes on a `200` with `{ codes: [...] }` | `POST /api/account/mfa/recovery/regenerate`; returns that body |
| auth-client-107 | preferred-method-set | Setting the preferred method to `'totp'` | `PUT /api/account/mfa/preference` with `{"method":"totp"}` |
| auth-client-108 | account-security-authed | No access token stored; any account-security operation invoked | Request carries no `Authorization` header, then a `401` triggers the same refresh-and-retry waterfall as any authenticated call |
| auth-client-109 | report-unexpected-status-gate | Unexpected-error reporting given a `401` typed HTTP error and given a `403` host-defined error with a compatible shape | Neither the console nor the sink is called for either |
| auth-client-110 | report-unexpected-status-gate | Unexpected-error reporting given a `503` typed HTTP error | Both the console and the sink are called |
| auth-client-111 | report-unexpected-dedup-window | The same message + context reported twice within 60000ms | The sink/console is called once, not twice |
| auth-client-112 | report-auth-error-unconditional | Unconditional error reporting regardless of status | The sink and the console are both called |
| auth-client-113 | report-never-throws | A registered reporter that throws; unexpected-error reporting invoked | Does not throw; the console is still called |
| auth-client-114 | set-auth-error-reporter-hook | Registering a sink, then unexpected-error reporting with `(err, { feature: 'x' })` | The sink is called with `(err, { feature: 'x' })` |
| auth-client-115 | provider-label-known-and-fallback | The provider label lookup for `'github'`, `'google'`, `'discord'` | `'GitHub'`, `'Google'`, `'Discord'` |
| auth-client-116 | oauth-error-message-known-codes-and-fallback | The OAuth error message lookup for `'account_exists'` and `'weird_code'` | Fixed account-exists message; `'Sign-in failed (weird_code)'` |
| auth-client-117 | link-copy-provider-substitution | The link-confirm title copy for `'github'` | `'Add GitHub to your account?'` |
| auth-client-118 | sensitive-data-classification / access-token-transmission | Unconditional error reporting called with a context object that happens to include an access-token field | Not applicable as a runtime check — the error-report context type documents the scalar-only contract; this vector records that no call site in this recipe passes a token as context |
| auth-client-119 | refresh-token-never-persisted | Token extraction from a body carrying `{ token: 'T', refreshToken: 'server-side-rt' }`, then writing the resulting bundle; inspecting the persistent store | The stored JSON's `refreshToken` field is `''`, never `'server-side-rt'` |
| auth-client-120 | token-subject-not-an-authorization-decision | An access token with an unsigned/forged `sub` claim | Reading the token's subject claim returns that claim's value unverified — documents that callers MUST NOT treat it as an authorization fact |

## Edge Cases

- **Null/empty input**: token extraction from `{}` (neither field present) —
  MUST throw (auth-client-011). Reading relayed central-login parameters
  from an empty query (no query at all) — MUST return nothing
  (auth-client-086). Parsing an inbound SSO fragment from `''` — MUST return
  nothing (auth-client-077). Taking the return-to value with nothing
  stashed — MUST return nothing.
- **Boundary/malformed values**: A stored token bundle that is not valid
  JSON — MUST be treated as absent, never thrown (auth-client-014). A `sub`
  claim that decodes to a non-string — MUST be treated as absent
  (`read-token-subject-derivation`). A base64url segment with stripped
  padding — MUST still decode (auth-client-022). A base64url segment with an
  invalid UTF-8 byte sequence — MUST decode to nothing, never substitute
  U+FFFD (auth-client-023).
- **Concurrent access**: Two or more callers invoking the refresh operation
  simultaneously — MUST dedup to exactly one network request
  (auth-client-027). A refresh racing a clear of the token bundle (logout) —
  MUST NOT resurrect the session (auth-client-031). A refresh racing another
  refresher's or a fresh login's write of the token bundle — MUST adopt the
  winner's token rather than clobber or wrongly clear it (auth-client-032,
  auth-client-034). A session-change subscriber that unsubscribes another
  subscriber from inside its own callback — MUST NOT suppress delivery to
  that other subscriber for the in-progress announcement (auth-client-020).
- **Error states**: Every network call in this recipe that can fail (the
  refresh POST, the base authenticated request helper, the SSO code
  exchange, every central-login step, the silent-restore preflight check,
  every account-security operation, every MFA/passkey operation) MUST
  surface a typed HTTP error (status + code) or a plain error with an
  extracted/fallback message to its caller — none silently drops a non-2xx
  response's failure. The silent-restore preflight check alone fails closed
  to `false` on any error (network throw, non-200, wrong-shaped body) rather
  than propagating (auth-client-073) — a deliberate design choice (see
  Design Decisions), not an omission.
- **Offline/disconnected state**: A request that rejects at the network
  level (offline, DNS failure, connection reset) during a refresh — MUST be
  reported via unconditional error reporting and MUST clear the token
  bundle rather than leave a token the client can no longer confirm is still
  valid (auth-client-036). The same network-level failure during the SSO
  code exchange — MUST retry exactly once after 750ms before giving up
  (auth-client-050); an HTTP-level failure (the server responded) is never
  retried, because the one-time exchange code is already spent
  (auth-client-051).
- **No interactive host environment available** (a web-specific edge case —
  server-side rendering, or storage blocked by private browsing — with no
  native-platform analog): marking/clearing the once-per-tab restore guard,
  stashing/taking the return-to value, and beginning a provider-link's nonce
  stash MUST all swallow a thrown storage exception; beginning a
  provider-link specifically MUST fail closed (return `false`, never
  navigate) rather than start an OAuth round-trip whose CSRF completion
  check is guaranteed to fail (auth-client-098).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storageKey` | string (via reconfiguring auth) | `'auth_tokens'` | Persistent-store key for the persisted token bundle; the cached-user key is `` `${storageKey}:user` `` |
| `refreshPath` | string (via reconfiguring auth) | `'/api/auth/refresh'` | Same-origin path the cookie-first refresh POST targets |
| `NEXT_PUBLIC_AUTH_API_URL` | environment variable | unset | Absolute AS base URL; when unset, every AS-bound call falls back to the same-origin `/api` proxy (or, for a central-login step, refuses outright) |
| The default exchange path | exported constant | `'/api/oauth/signin/exchange'` | Default path the SSO code exchange posts the one-time code to |
| The exchange network-retry delay | internal constant | `750` ms | Pause before the SSO code exchange's single network-failure retry |
| The loser-recheck delay | internal constant | `300` ms | Pause a losing concurrent refresh waits before re-reading storage |
| The report dedupe window | internal constant | `60000` ms | Per-signature throttle window for unexpected-error reporting |
| The preflight timeout | internal constant | `2000` ms | Abort timeout for the silent-restore preflight check's GET |
| The login-time MFA/passkey paths | exported constants | `'/auth/login/mfa/sms/send'`, `'/auth/login/mfa/webauthn/options'`, `'/auth/login/webauthn/options'` | Shared login-time MFA/passkey paths, reused by both the site-login and central-login clients |
| The default callback path | internal constant | `'/auth/callback'` | Default in-site route the AS bounces the exchange code back to |
| `clientId` | caller-supplied option | `'adh'` | OAuth client id sent on every AS-bound navigation/POST |
| The error-reporter hook | injected hook | none | Host-supplied sink for error reporting; none means console-only |
| The retry-marker hook | injected hook | none | Host-supplied callback tagging the exact request options of a retried request |
| Session-change subscription | injected subscription | n/a | Caller-registered callback invoked on every token write/clear |

## Deep Linking

Not applicable in the sense of a registered URL scheme or platform deep-link
mechanism: inbound OAuth round-trip state instead travels as ordinary URL
fragment and query parameters — parsing an inbound SSO fragment reads
`#code`/`#error` from the current URL's fragment, and reading relayed
central-login parameters reads `clientId`/`return` from the current URL's
query — handled by this recipe's own logic, not resolved through any
deep-link registration.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `tokens.missingToken` | Token response missing token/accessToken | Thrown by token extraction |
| `client.exchangeFallback` | Sign-in failed | The SSO code exchange's fallback error message |
| `client.httpFallback` | HTTP {status} | The base authenticated request helper's fallback error message |
| `client.emptyResponse` | Unexpected empty response (204 No Content); use authedRequest for endpoints with no body | The JSON-parsing helper's 204 guard |
| `mfa.passkeyCheckFailed` | Could not start the passkey check. | The second-factor assertion's fallback |
| `mfa.noPasskey` | No passkey is available for this account. | The passwordless-passkey assertion's fallback |
| `mfa.smsSendFailed` | Could not send a code. | Requesting a login SMS code's fallback |
| `mfa.codeMismatch` | That code didn't match. | Completing login with a code's fallback |
| `mfa.passkeyVerifyFailed` | Passkey verification failed. | Completing login with a passkey's fallback |
| `mfa.passkeyLoginFailed` | Passkey login failed. | Passwordless passkey login's fallback |
| `labels.accountExistsTitle` | Account already exists | The account-exists title copy |
| `labels.oauthAccountExists` | An account already exists for this email — sign in with your email and password instead. | The OAuth error message lookup for `'account_exists'` |
| `labels.linkFailedTitle` | Couldn't connect account | The link-failed title copy |
| `labels.loginDisabledTitle` / `loginDisabledBody` | We're not open just yet / The Hub isn't quite ready for visitors yet — please check back soon. | Shown when logins are disabled |
| `sso.misconfigured` | Sign-in is misconfigured on this site: NEXT_PUBLIC_AUTH_API_URL was not set when it was built... | A central-login step's thrown message when no AS base is configured |

Every string above is hardcoded English with no lookup table, ICU message, or
locale parameter anywhere in this recipe — there is no localization
mechanism in this component at all. This is a plain fact about the source,
not a gap: a port to a platform with an i18n layer MUST decide, as a design
choice outside this contract, whether and how to route these strings through
it.

## Accessibility Options

Not applicable: this component renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior of its own. Those
display options act on whatever UI a host renders around this recipe's
calls (login forms, MFA prompts, account-security screens), not on this
headless module.

## Feature Flags

Not applicable: no part of this component defines or reads a feature-flag
key. Every conditional path — whether an AS base is configured, whether the
SSO-hint cookie is present, whether the site is cross-apex, whether a
preflight allows a silent restore — is derived from runtime configuration, a
cookie, or a server response, never from a flag this module owns.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
telemetry event. Unexpected-error reporting sends operational error
diagnostics to an injected sink and the console (see Logging below) — this
is failure telemetry for a host's error-tracking system, not
product-analytics events.

## Privacy

- **Data collected**: The access token (a bearer credential, not itself
  PII); a cached user record (`id`, `email`, `name`, `avatarUrl`, `slug`,
  `capabilities`, `authMethods`, `attributes`); TOTP secrets/`otpauthUri`
  and WebAuthn ceremony payloads pass through this module in memory only and
  are never persisted by any part of it; recovery codes are returned once by
  the recovery-codes regeneration and are likewise not persisted here. The
  refresh token is explicitly never read or persisted
  (**refresh-token-never-persisted**). The error-report context is typed
  scalars-only (no PII, request bodies, or ids) by declared contract.
- **Storage**: The access token and cached user live in a persistent
  client-side store under the configured storage key and
  `` `${storageKey}:user` `` as plaintext JSON — readable by any script
  running on the page (the standard SPA storage/XSS tradeoff; this contract
  does not encrypt or otherwise protect that value beyond keeping the
  refresh token out of it). The CSRF link nonce, the post-login return-to
  path, the once-per-tab restore guard, and the pending-link intent live in
  a session-scoped client-side store, scoped to one tab and cleared when it
  closes.
- **Transmission**: The access token is sent only via the `Authorization:
  Bearer` header (see Security). Credentials are included on the refresh
  endpoint and every central-login/MFA endpoint so the HttpOnly
  refresh/central-session cookies travel with the request; the
  silent-restore preflight check deliberately omits credentials because its
  question needs no session context. This module never reads the HttpOnly
  refresh or central session cookies itself — only the server sets and
  reads them.
- **Retention**: The access token and cached user persist in the persistent
  client-side store until an explicit clear (logout, or a refresh that gives
  up — **refresh-failure-clears-when-unresolved**) or until the host clears
  its own storage; this module enforces no client-side TTL on the access
  token — expiry is discovered only when the server returns a `401`, which
  triggers a refresh attempt.

## Logging

Subsystem: `agentictoolkit` | Category: `auth-client`

| Event | Level | Message |
|-------|-------|---------|
| Refresh network/parse failure | error (via unconditional error reporting, always reaches the console) | Reported with `{ feature: 'auth', step: 'tokenRefresh' }` |
| Any reported auth error (unconditional path) | error | Logged with the error and its context |
| Missing AS base at build/runtime (logged once per page load) | error | `'[adh-auth] NEXT_PUBLIC_AUTH_API_URL was not set when this site was built...'` |

No part of this component logs at an informational or warning level — every
log call site is an error-level report, and every one is either an
unexpected-failure report or the one-time misconfiguration notice above. The
error-status gate (**report-unexpected-status-gate**) is specifically what
keeps an expected 4xx (wrong password, stale code) off this log.

## Platform Notes

- **React/Web**: This is the reference implementation. `fetch` for
  networking, `window.localStorage`/`window.sessionStorage` for persistence,
  `@simplewebauthn/browser`'s `startAuthentication`/`startRegistration` for
  WebAuthn ceremonies, and plain `window.location`/top-level navigation for
  every AS round-trip (no client-side router is involved — the SSO/central
  login flows are deliberately full-page navigations, not `fetch` calls,
  because the central session cookie is host-only on the AS host). Browser-
  global presence checks (`window`/`document`) are what this recipe's
  "no interactive host environment" guards resolve to in source — they gate
  every operation that would otherwise run during server-side rendering.
- **SwiftUI / AppKit / UIKit**: `URLSession` replaces `fetch`; the Keychain
  (not `UserDefaults`) is the idiomatic store for the access token, though
  this component's own decision to never persist the refresh token still
  applies — a native port keeps the refresh token cookie-equivalent
  server-side only, never in the Keychain either. `ASWebAuthenticationSession`
  (for the AS navigation/callback round-trip) and
  `ASAuthorizationPlatformPublicKeyCredentialProvider`/
  `ASAuthorizationSecurityKeyPublicKeyCredentialProvider` (for the WebAuthn
  ceremonies this recipe runs via `@simplewebauthn/browser` in source) are
  the platform equivalents. `NotificationCenter` or a `Combine`
  `PassthroughSubject` is the idiomatic equivalent of the session-change
  subscriber set.
- **Compose / Android**: `OkHttp` or `Ktor` replaces `fetch`;
  `EncryptedSharedPreferences` or Android `DataStore` is the idiomatic token
  store. `androidx.credentials` (Credential Manager) is the platform
  equivalent of the WebAuthn/passkey ceremonies. A `SharedFlow` or
  `LiveData` is the idiomatic equivalent of the session-change subscription.
- **WinUI 3**: `HttpClient` replaces `fetch`, with `System.Text.Json` for
  every JSON parse/serialize this component does inline (token extraction,
  error-message/code extraction, every request/response body).
  `Windows.Storage.ApplicationData.Current.LocalSettings` is the equivalent
  of a persistent client-side store for the cached user object; a native
  port SHOULD still route the access token through
  `Windows.Security.Credentials.PasswordVault` rather than plain settings,
  since WinUI has no localStorage-equivalent XSS exposure to justify the web
  tradeoff — this is a stricter choice than the web source makes, not a
  divergence from its contract (the refresh token is still never stored, on
  any platform). `Task`/`async`-`await` replaces every promise; an
  `ObservableCollection`/`INotifyPropertyChanged`-backed session object, or a
  C# `event`, is the idiomatic equivalent of the session-change subscriber
  set. `Windows.Security.Credentials.UI` (Windows Hello / passkeys) is the
  platform equivalent of the WebAuthn ceremonies; there is no equivalent of a
  top-level browser navigation for the SSO/central-login flows, so a WinUI
  port needs `WebAuthenticationBroker` or an embedded `WebView2` to carry the
  AS round-trip that this recipe does with `window.location.href` in source.

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to data/services/auth/. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
