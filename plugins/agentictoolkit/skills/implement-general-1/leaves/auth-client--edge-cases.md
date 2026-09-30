<!-- leaf: implement-general-1/auth-client--edge-cases · source: auth-client.md -->

# Auth Client

**Rules** (cite as `implement-general-1/auth-client--edge-cases#<slug>`):

- `null-empty-input` MUST — tokensFromResponse({}) (neither field present) — MUST throw (auth-client-011). readCentralParams('') (no query at all) …
- `boundary-malformed-values` MUST — A stored tokens blob that is not valid JSON — MUST be treated as absent, never thrown (auth-client-014). A sub claim …
- `concurrent-access` MUST — Two or more callers invoking refreshAccessToken() simultaneously — MUST dedup to exactly one network request …
- `error-states` MUST — Every network call in these 11 files that can fail (the refresh POST, authedFetch, exchangeSsoCode, every …
- `offline-disconnected-state` MUST — A fetch that rejects at the network level (offline, DNS failure, connection reset) during a refresh — MUST be reported …
- `storage-unavailable` MUST (private browsing, disabled storage — a web-specific edge case with no native-platform analog) — markSsoChecked, clearSsoChecked, stashReturnTo, takeReturnTo, and beginLinkProvider's nonce stash MUST all swallow a …

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
