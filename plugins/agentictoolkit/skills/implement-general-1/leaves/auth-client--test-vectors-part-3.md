<!-- leaf: implement-general-1/auth-client--test-vectors-part-3 · source: auth-client.md -->

# Auth Client — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
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
