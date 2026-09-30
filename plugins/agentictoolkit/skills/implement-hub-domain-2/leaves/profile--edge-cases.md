<!-- leaf: implement-hub-domain-2/profile--edge-cases · source: hub-domain-profile.md -->

# Hub Domain Profile

**Rules** (cite as `implement-hub-domain-2/profile--edge-cases#<slug>`):

- `null-and-empty-input-opts-workspace` MUST — MUST take the same no-query branch whether opts is entirely omitted or opts.workspace is the empty string "", since …
- `null-and-empty-input-sociallinkwrite-handle-sortorder` MUST — handle MUST be sent as the empty string unchanged when the caller supplies one (per profile.test.ts's own fixture, …
- `null-and-empty-input-resolveprivacylevel` MUST — MUST return "only-me", per privacy-level-resolution-default.
- `boundary-values-audiencemask-bit-combinations` MUST — resolvePrivacyLevel MUST test only bits 0 and 1; a mask with only higher bits set (e.g. 4) MUST fall through to …
- `concurrent-access` SHOULD — this module is stateless JavaScript with no shared mutable state beyond the fixed constants …
- `error-states-dependency-failure` MUST — neither profile.ts nor usage.ts catches a rejection from authedJson/authedRequest; a non-2xx backend response, a …
- `offline-or-disconnected-state` MUST — no call in either file guards against a fetch-level rejection; a connectivity loss mid-call MUST propagate as an …
- `no-timeout` MUST — no call sets a deadline or AbortSignal; a reachable-but-unresponsive backend MUST leave the call pending indefinitely …
- `no-cancellation` MUST — no exported function accepts an AbortSignal parameter, so a caller MUST NOT be able to cancel an in-flight …
- `no-retry-beyond-the-inherited-401-waterfall` MUST — every call issues exactly one request (plus, on a 401, whatever single refresh-and-retry authedFetch itself performs, …

## Edge Cases

- **Null and empty input — `opts.workspace`**: MUST take the same no-query branch whether `opts` is
  entirely omitted or `opts.workspace` is the empty string `""`, since JavaScript treats an empty
  string as falsy and `workspaceQuery`'s check is a plain truthiness test.
- **Null and empty input — `SocialLinkWrite.handle`/`sortOrder`**: `handle` MUST be sent as the
  empty string unchanged when the caller supplies one (per `profile.test.ts`'s own fixture,
  `handle: ""`); `sortOrder` MUST be omitted from the serialized body entirely when the caller does
  not supply it, since `JSON.stringify` drops `undefined`-valued keys.
- **Null and empty input — `resolvePrivacyLevel([], ...)`**: MUST return `"only-me"`, per
  `privacy-level-resolution-default`.
- **Boundary values — `audienceMask` bit combinations**: `resolvePrivacyLevel` MUST test only bits 0
  and 1; a mask with only higher bits set (e.g. `4`) MUST fall through to `"only-me"`, and a mask
  with bit 0 set together with any higher bits (e.g. `5`) MUST still resolve to `"public"`, since the
  bit-0 check runs first and unconditionally.
- **Concurrent access**: this module is stateless JavaScript with no shared mutable state beyond the
  fixed constants (`module-holds-no-mutable-state`), so two calls from the same tab cannot race on
  anything inside `profile.ts`/`usage.ts` itself. Two concurrent `setPrivacyGrant` or
  `createSocialLink`/`createAddress` calls for the same target SHOULD be expected by a caller to
  follow ordinary HTTP `PUT`/`POST` semantics with no client-side sequencing — the last response the
  caller applies wins; no ordering guarantee is implemented anywhere in these files, so this is a
  fact about caller responsibility, not a behavior this module enforces.
- **Error states — dependency failure**: neither `profile.ts` nor `usage.ts` catches a rejection from
  `authedJson`/`authedRequest`; a non-2xx backend response, a network failure, or a malformed
  response body all MUST propagate unmodified to the caller, per `violation-handling-inherited`.
- **Offline or disconnected state**: no call in either file guards against a `fetch`-level rejection;
  a connectivity loss mid-call MUST propagate as an unhandled promise rejection out of every exported
  function, with no retry, queuing, or offline-specific handling.
- **No timeout**: no call sets a deadline or `AbortSignal`; a reachable-but-unresponsive backend
  MUST leave the call pending indefinitely as far as these two files are concerned.
- **No cancellation**: no exported function accepts an `AbortSignal` parameter, so a caller MUST NOT
  be able to cancel an in-flight `profile.ts`/`usage.ts` request through this module.
- **No retry beyond the inherited 401 waterfall**: every call issues exactly one request (plus,
  on a `401`, whatever single refresh-and-retry `authedFetch` itself performs, outside these two
  files); nothing in `profile.ts`/`usage.ts` MUST retry a network failure or a non-401 error status.
