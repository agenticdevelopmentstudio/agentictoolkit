<!-- leaf: implement-status-server/auth--edge-cases · source: status-server-auth.md -->

# Status Server Auth

**Rules** (cite as `implement-status-server/auth--edge-cases#<slug>`):

- `null-and-empty-input` MUST — a missing code, missing state, missing gh_oauth_state cookie, or an empty Authorization header all resolve to a defined …
- `boundary-values` MUST — a bearer value of exactly 'Bearer ' (trailing space, empty token) slices to the empty string (header.slice(7).trim()); …

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
