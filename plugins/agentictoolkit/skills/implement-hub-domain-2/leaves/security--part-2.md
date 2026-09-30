<!-- leaf: implement-hub-domain-2/security--part-2 · source: hub-domain-security.md -->

# Hub Domain Security Client — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/security--part-2#<slug>`):

- `token-list-request-shape` MUST
- `token-scopes-unwraps-envelope` MUST
- `token-mint-request-shape` MUST
- `token-revoke-request-shape` MUST
- `token-created-secret-returned-once` MUST
- `token-metadata-never-carries-secret` MUST
- `access-list-all-groups-cross-bucket` MUST
- `access-group-detail-request-shape` MUST
- `access-group-create-scoped-to-bucket` MUST
- `access-group-create-conflict-friendly` MUST
- `access-group-update-request-shape` MUST
- `access-group-update-conflict-friendly` MUST
- `access-group-delete-request-shape` MUST
- `access-member-add-request-shape` MUST
- `access-member-add-conflict-friendly` MUST
- `access-member-remove-request-shape` MUST
- `access-grant-upsert-request-shape` MUST
- `access-grant-delete-request-shape` MUST
- `access-crud-string-passthrough` MUST
- `access-metadata-not-writable` MUST
- `every-bucket-access-call-url-encodes-identifiers` MUST
- `no-compact-on-write-bodies` MUST
- `no-client-side-cache` MUST
- `stateless-module` MUST
- `auth-delegated-to-shared-client` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST
- `token-scope-passthrough-unvalidated` MUST
- `token-can-be-a-grant-principal` MUST

## Behavioral Requirements

**Personal API tokens (`tokensApi`)**

- **token-list-request-shape**: `list` MUST send `GET {BASE}` (`BASE` = the fixed constant
  `/api/auth/tokens`) and MUST return the parsed `ApiToken[]` body verbatim, applying no
  transformation.
- **token-scopes-unwraps-envelope**: `scopes` MUST send `GET {BASE}/scopes` and MUST return the bare
  `prefixes` array unwrapped from the `{ prefixes }` response envelope, not the envelope itself.
- **token-mint-request-shape**: `mint` MUST send `POST {BASE}` with the caller's `MintTokenBody`
  (`name`, `expiresAt?`, `scope?`) JSON-serialized verbatim as the body, with no `compact()` or other
  transformation applied first, and MUST return the parsed `ApiTokenCreated` body.
- **token-revoke-request-shape**: `revoke` MUST send `DELETE {BASE}/{id}`, with `id` percent-encoded
  via the global `encodeURIComponent` (not the `enc` alias `bucket-access.ts` uses for the same
  purpose), and MUST resolve with no value, discarding whatever body the response carries.
- **token-created-secret-returned-once**: `ApiTokenCreatedRow`'s own doc comment states its `token`
  field is "the raw token value — shown exactly once"; `mint` MUST return that field to the caller
  unmodified as part of the resolved `ApiTokenCreated`, and MUST NOT retain, log, or resend it itself.
- **token-metadata-never-carries-secret**: every other `tokensApi` operation (`list`, `scopes`,
  `revoke`) MUST operate only on `ApiTokenRow`, whose fields are `id`, `name`, `prefix` (documented as
  "non-secret leading chars, for display"), `createdAt`, `expiresAt`, `lastUsedAt`, and an optional
  `scope`; none of these three operations MUST ever receive or return the raw secret.

**Bucket access lists (`bucketAccessApi`)**

- **access-list-all-groups-cross-bucket**: `listAllGroups` MUST send `GET {GROUPS}` (`GROUPS` = the
  fixed constant `/api/bucket/access-groups`, unscoped to any single bucket) and MUST return the
  `accessGroups` array unwrapped from the `{ accessGroups }` envelope; per the source's own comment,
  this is the one cross-bucket call for the Access pane, in place of a per-bucket `listGroups`
  fan-out, and the caller — not this module — MUST join bucket names locally and filter to the
  ecosystem it is displaying.
- **access-group-detail-request-shape**: `getGroup` MUST send `GET {GROUPS}/{enc(groupId)}` and MUST
  return the parsed `AccessGroupDetail` verbatim, including its nested `members` and `grants` arrays.
- **access-group-create-scoped-to-bucket**: `createGroup` MUST send
  `POST {BUCKETS}/{enc(bucketId)}/access-groups` (`BUCKETS` = the fixed constant
  `/api/bucket/buckets`) with a body of `{ name, description? }`, where `name` is `input.name.trim()`
  and `description` is included only when `input.description` is truthy.
- **access-group-create-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `createGroup` MUST rethrow a plain `Error` with the message `An access list named
  "<trimmed name>" already exists.`; any other caught error MUST be rethrown unchanged.
- **access-group-update-request-shape**: `updateGroup` MUST send `PATCH {GROUPS}/{enc(groupId)}` with
  a body built key-by-key: `name` is included, trimmed, only when `patch.name !== undefined`, and
  `description` is included, unmodified, only when `patch.description !== undefined`.
- **access-group-update-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `updateGroup` MUST rethrow a plain `Error` with the message `An access list named
  "<trimmed patch.name, or empty string if patch.name is undefined>" already exists.`; any other
  caught error MUST be rethrown unchanged.
- **access-group-delete-request-shape**: `deleteGroup` MUST send `DELETE {GROUPS}/{enc(groupId)}` and
  MUST resolve with no value; unlike `createGroup`/`updateGroup`, it wraps the call in no `try`/`catch`
  of its own, so any error the backend returns — including the `409` the source's top comment says
  the seeded "everyone" group's delete always answers with — propagates to the caller unchanged and
  un-translated.
- **access-member-add-request-shape**: `addMember` MUST send
  `POST {GROUPS}/{enc(groupId)}/members` with a body of exactly `{ memberType, memberId }`.
- **access-member-add-conflict-friendly**: on a caught error whose message matches `/already
  exists/i`, `addMember` MUST rethrow a plain `Error` with the message `That member is already in
  this access list.`; any other caught error MUST be rethrown unchanged.
- **access-member-remove-request-shape**: `removeMember` MUST send
  `DELETE {GROUPS}/{enc(groupId)}/members/{enc(memberRowId)}` and MUST resolve with no value; per the
  source's own comment, `memberRowId` is the membership row's `id` (`AccessGroupMember.id`), never the
  principal's own id — the backend `DELETE` matches on the row id.
- **access-grant-upsert-request-shape**: `upsertGrant` MUST send `PUT {GROUPS}/{enc(groupId)}/grants`
  with a body of exactly `{ targetType, targetId, crud }` and MUST return the parsed `AccessGrant`;
  like `deleteGroup`, it wraps the call in no `try`/`catch`, so any backend error propagates
  unchanged.
- **access-grant-delete-request-shape**: `deleteGrant` MUST send
  `DELETE {GROUPS}/{enc(groupId)}/grants/{enc(grantId)}` and MUST resolve with no value.
- **access-crud-string-passthrough**: `upsertGrant` MUST send whatever `crud` string the caller
  supplies (documented on `AccessGrantPutBody`/`AccessGrantRow` as "comma-separated CRUD subset, e.g.
  `'C,R,U,D'` or `''` (none)") verbatim, with no client-side charset, ordering, or length check.
- **access-metadata-not-writable**: `AccessGroupCreateBody` and `AccessGroupPatchBody` MUST NOT
  include a `metadata` field; neither `createGroup` nor `updateGroup` can set the `metadata` a
  `BucketAccessGroup` row carries, even though `getGroup`/`listAllGroups` MUST return whatever
  `metadata` the backend supplies.

**Cross-cutting**

- **every-bucket-access-call-url-encodes-identifiers**: every `bucketAccessApi` method MUST
  percent-encode `bucketId`, `groupId`, `memberRowId`, and `grantId` via `enc` (`encodeURIComponent`
  aliased in `client-helpers.ts`) before placing them in a URL.
- **no-compact-on-write-bodies**: neither `mint`, `createGroup`, `updateGroup`, `addMember`, nor
  `upsertGrant` MUST call `compact()` from `client-helpers.ts` on its body before serializing it; each
  builds its own conditional object literal (or, for `mint`, serializes the caller's object directly),
  and `JSON.stringify`'s built-in omission of `undefined`-valued keys is what actually drops absent
  optionals.
- **no-client-side-cache**: neither `tokensApi` nor `bucketAccessApi` MUST cache or memoize any
  response; every call issues exactly one HTTP request.
- **stateless-module**: neither client MUST hold mutable module-level state across calls; the only
  module-level values are the fixed path constants `BASE`, `GROUPS`, and `BUCKETS`.

### Security

This is a security-relevant recipe: `tokensApi` issues and revokes the caller's own bearer-style API
credentials, and `bucketAccessApi` is the client for a resource-level authorization surface (who may
read/write which buckets, bucket types, or rows). Neither client carries the caller's own *session*
credential — that lives in `@agentic-toolkit/auth/client`, which both modules compose rather than
reimplement.

- **auth-delegated-to-shared-client**: every `tokensApi`/`bucketAccessApi` network call MUST go
  through `authedJson` or `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via
  `./http`), which attaches `Authorization: Bearer <token>` from `readAccessToken()`; neither module
  MUST read, store, or attach a session token itself.
- **session-refresh-waterfall**: a `401` response to any call from either client MUST trigger exactly
  one token refresh and one retried request, inherited unconditionally from `authedFetch`; a second
  `401` on the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. Neither
  file defines any refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one,
  a machine-readable `code`, per `authedFetch`'s shared implementation.
- **token-scope-passthrough-unvalidated**: `mint`'s `scope` parameter (documented on `ApiTokenRow` as
  "REST path prefixes this token may reach ... optional `:read` suffix, `*` = all") MUST be sent
  exactly as the caller supplies it, with no client-side check that a prefix is well-formed or that
  `expiresAt` is a valid future date; both are backend-validated concerns per this module's own lack
  of any such check.
- **token-can-be-a-grant-principal**: `MemberType` (`"user" | "organization" | "persona" | "app" |
  "token"`) includes `"token"`; `addMember` MUST accept a `memberId` that names an API token as a
  bucket access-group member exactly as it would a user or organization, with no distinct handling
  for that case.
- **server-side-grant-and-ceiling-validation**: per `bucket-access.ts`'s own top comment, the backend
  enforces "grant-target validity and the bucket ≥ type ≥ row ceiling" for every grant `upsertGrant`
  sends; this module performs no client-side check of a grant's target hierarchy before sending it.
- **server-side-seeded-group-protection**: per the same comment, the seeded `"everyone"` access group
  (`AccessGroupRow.kind === "everyone"`) is undeletable server-side — "delete → 409" — and
  `deleteGroup` contains no client-side check of `kind` before sending the request; the protection is
  enforced entirely by the backend and surfaced to the caller as an untranslated `409`, per
  `access-group-delete-request-shape`.

