<!-- leaf: implement-hub-domain-2/security--edge-cases · source: hub-domain-security.md -->

# Hub Domain Security Client

**Rules** (cite as `implement-hub-domain-2/security--edge-cases#<slug>`):

- `boundary-values-mint-scope-expiry` MUST — MUST — mint accepts any string array for scope and any string (or null) for expiresAt with no length, format, or range …

## Edge Cases

- **Null and empty input — `createGroup`/`updateGroup` name**: `input.name.trim()` on an empty or
  all-whitespace string produces `""`, which is sent to the backend unchanged; neither method rejects
  it client-side.
- **Null and empty input — `addMember`/`upsertGrant` identifiers**: `memberId`, `targetId`, and
  `crud: ""` are all accepted as empty strings and sent verbatim; only `crud: ""` has documented
  meaning ("none"), per `access-crud-string-passthrough`.
- **Null and empty input — path-segment identifiers**: `enc("")`/`encodeURIComponent("")` on an empty
  `groupId`, `memberRowId`, `grantId`, `bucketId`, or token `id` produces an empty URL segment (e.g.
  `.../members/`); the resulting malformed request is still sent, with no client-side guard against
  it.
- **Boundary values — `mint` scope/expiry**: MUST — `mint` accepts any string array for `scope` and
  any string (or `null`) for `expiresAt` with no length, format, or range check; a caller-supplied
  malformed date string or an unbounded `scope` array is sent to the backend as-is.
- **Boundary values — `crud` grant string**: no minimum or maximum length, no de-duplication of
  repeated letters, and no validation that only `C`/`R`/`U`/`D` characters appear; `upsertGrant` sends
  whatever string the caller provides.
- **Concurrent access — module state**: neither `tokensApi` nor `bucketAccessApi` holds shared mutable
  state between calls (`stateless-module`), so there is nothing for two concurrent calls to race on
  within these files.
- **Concurrent access — competing name/member conflicts**: two concurrent `createGroup` calls with the
  same trimmed `name` in the same bucket, or two concurrent `addMember` calls with the same
  `memberId`, are resolved by the backend's uniqueness constraint; the loser's request receives the
  `409` that `access-group-create-conflict-friendly`/`access-member-add-conflict-friendly` translate to
  a friendly message — there is no client-side pre-check, only this post-hoc translation.
- **Concurrent access — competing grant/group writes**: two concurrent `upsertGrant` calls for the
  same `groupId`/`targetType`/`targetId`, or a `deleteGroup` racing an `updateGroup` for the same
  `groupId`, follow ordinary HTTP semantics — last response received wins, with no client-side
  sequencing, version check, or optimistic lock anywhere in either file.
- **Error states — validation failure vs. HTTP failure**: every error either client can throw is an
  `AuthHttpError` (via `authedFetch`) or, for the three `rethrowConflict` sites, a plain `Error`
  carrying only a friendly message and no `status`; `httpStatus()` (`http.ts`) distinguishes the two by
  duck-typing the `.status` property.
- **Error states — dependency unavailable**: neither client catches a `fetch`-level network rejection
  anywhere outside the `401` waterfall `authedFetch` already provides; a DNS failure, connection
  refusal, or TLS error propagates as an unhandled promise rejection out of whichever method was
  called.
- **Offline or disconnected state**: none of the twelve `tokensApi`/`bucketAccessApi` methods detects
  or reacts to a loss of connectivity mid-call; a connection dropped after the request was sent but
  before a response arrived surfaces only as the underlying `fetch` rejection described above.
- **No timeout**: no method in either file sets a deadline or `AbortSignal`; a reachable-but-
  unresponsive backend leaves the call pending until the underlying `fetch` implementation's own
  limit, if any.
- **No cancellation**: no method accepts an `AbortSignal` parameter, so a caller cannot cancel an
  in-flight request through either client.
- **No retry beyond the 401 waterfall**: every call issues exactly one request (plus, on a `401`, the
  single inherited refresh-and-retry); nothing in either file retries a network failure or a non-401
  error status.
- **token-mint-retry-duplication**: `mint` sends a plain `POST` with no idempotency key, client-generated request id, or de-duplication; a caller that retries `mint` after an ambiguous failure (a timeout or dropped connection after the first `POST` reached the backend) sends a second request, which can mint a second, independently-secreted token. Unlike `createGroup`/`addMember`, whose retries collide on a uniqueness constraint and surface a `409`, nothing in `tokens.ts` gives a retried `mint` an equivalent signal; any de-duplication belongs to the backend's `POST /api/auth/tokens` route.
- **token-member-revocation-orphan**: `MemberType` allows an API token to be a bucket access-group member (`memberType: "token"`), but `tokens.ts` and `bucket-access.ts` never coordinate: `tokensApi.revoke` sends only the revoke request and touches no `AccessGroupMember` row. Whether rows naming the revoked token are removed is decided by the backend's revocation handler, not by either client.
