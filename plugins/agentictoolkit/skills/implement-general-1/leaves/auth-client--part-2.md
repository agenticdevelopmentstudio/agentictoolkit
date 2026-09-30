<!-- leaf: implement-general-1/auth-client--part-2 · source: auth-client.md -->

# Auth Client — continued (part 2)

**Rules** (cite as `implement-general-1/auth-client--part-2#<slug>`):

- `default-runtime-config` MUST
- `configure-auth-merges` MUST
- `auth-api-base-resolution` MUST
- `as-endpoint-proxy-fallback` MUST
- `auth-tokens-shape` MUST
- `auth-user-shape` MUST
- `has-capability-null-safe` MUST
- `is-admin-derived` MUST
- `tokens-from-response-precedence` MUST
- `tokens-from-response-refresh-token-blanked` MUST
- `tokens-from-response-throws-when-absent` MUST
- `token-storage-key-configurable` MUST
- `token-read-off-browser-returns-null` MUST
- `token-read-malformed-json-returns-null` MUST
- `write-tokens-persists-and-announces` MUST
- `clear-tokens-clears-sibling-user-key` MUST
- `read-access-token-derivation` MUST
- `session-change-subscription` MUST
- `session-change-payload-free` MUST
- `session-change-snapshot-iteration` MUST
- `decode-base64url-json-utf8-strict` MUST
- `decode-base64url-json-tolerates-missing-padding` MUST
- `decode-base64url-json-never-throws` MUST
- `read-token-subject-derivation` MUST
- `read-user-validates-shape` MUST
- `write-user-persists-off-browser-noop` MUST
- `refresh-single-flight-dedup` MUST
- `refresh-request-shape` MUST
- `invalidate-refresh-bumps-generation` MUST
- `refresh-generation-guard` MUST
- `refresh-success-adopts-current-storage` MUST
- `refresh-failure-adopts-concurrent-winner` MUST
- `refresh-failure-loser-recheck-delay` MUST
- `refresh-failure-clears-when-unresolved` MUST
- `refresh-network-error-reports-and-clears` MUST
- `authed-fetch-bearer-attach` MUST
- `authed-fetch-default-content-type` MUST
- `authed-fetch-default-init` MUST
- `authed-fetch-401-refresh-retry-once` MUST
- `authed-fetch-throws-on-non-ok` MUST
- `authed-json-rejects-204` MUST

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
