<!-- leaf: implement-general-1/auth-client--test-vectors-part-2 · source: auth-client.md -->

# Auth Client — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
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
