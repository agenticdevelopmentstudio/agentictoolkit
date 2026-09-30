<!-- leaf: implement-hub-domain-2/profile--part-2 · source: hub-domain-profile.md -->

# Hub Domain Profile — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/profile--part-2#<slug>`):

- `social-links-list-request-shape` MUST
- `social-links-create-request-shape` MUST
- `social-links-update-request-shape` MUST
- `social-links-delete-request-shape` MUST
- `addresses-list-request-shape` MUST
- `addresses-create-request-shape` MUST
- `addresses-update-request-shape` MUST
- `addresses-delete-request-shape` MUST
- `workspace-query-omitted-when-absent` MUST
- `workspace-query-percent-encoded` MUST
- `list-key-namespaced-by-owner` MUST
- `list-key-roots-not-exported` MUST
- `privacy-key-not-namespaced` MUST
- `privacy-grants-list-unwraps-envelope` MUST
- `privacy-grants-caller-scoped-only` MUST
- `privacy-grant-set-request-shape` MUST
- `privacy-level-resolution-default` MUST
- `privacy-level-resolution-match` MUST
- `privacy-level-resolution-public-precedence` MUST
- `privacy-level-resolution-hub` MUST
- `privacy-level-resolution-unmatched-bits` MUST
- `usage-summary-request-shape` MUST
- `usage-summary-subject-list-server-derived` MUST
- `owner-scoped-row-shape` MUST
- `write-shapes-exclude-server-managed-fields` MUST
- `social-link-sort-order-is-render-order` MUST
- `privacy-target-table-widened` MUST
- `usage-limits-enforced-flag` MUST
- `usage-row-kind-application-admin-only` MUST
- `every-write-call-serializes-verbatim` MUST
- `module-holds-no-mutable-state` MUST
- `no-runtime-response-validation` MUST
- `auth-delegated-to-shared-client` MUST
- `no-client-side-storage-of-sensitive-fields` MUST
- `audience-visibility-enforced-server-side` MUST
- `violation-handling-inherited` MUST

## Behavioral Requirements

**Social links (`listSocialLinks`, `createSocialLink`, `updateSocialLink`, `deleteSocialLink`)**

- **social-links-list-request-shape**: `listSocialLinks` MUST send `GET /api/content/social-links`,
  appending `?workspace=<enc(workspace)>` only when `opts.workspace` is given, and MUST return the
  parsed body as `SocialLink[]` with no transformation.
- **social-links-create-request-shape**: `createSocialLink` MUST send
  `POST /api/content/social-links` (with the same optional `?workspace=` suffix) and a body that
  is `body` (a `SocialLinkWrite`) JSON-serialized verbatim, and MUST return the parsed `SocialLink`.
- **social-links-update-request-shape**: `updateSocialLink` MUST send
  `PUT /api/content/social-links/<enc(id)>` (with the same optional `?workspace=` suffix) and a
  body that is `body` JSON-serialized verbatim, and MUST return the parsed `SocialLink`.
- **social-links-delete-request-shape**: `deleteSocialLink` MUST send
  `DELETE /api/content/social-links/<enc(id)>` (with the same optional `?workspace=` suffix) via
  `authedRequest`, not `authedJson`, and MUST resolve with no value, discarding whatever body the
  response carries.

**Addresses (`listAddresses`, `createAddress`, `updateAddress`, `deleteAddress`)**

- **addresses-list-request-shape**: `listAddresses` MUST send `GET /api/content/addresses`, with
  the same optional `?workspace=` suffix as `listSocialLinks`, and MUST return the parsed body as
  `Address[]` with no transformation.
- **addresses-create-request-shape**: `createAddress` MUST send `POST /api/content/addresses`
  (with the optional `?workspace=` suffix) and a body that is `body` (an `AddressWrite`)
  JSON-serialized verbatim, and MUST return the parsed `Address`.
- **addresses-update-request-shape**: `updateAddress` MUST send
  `PUT /api/content/addresses/<enc(id)>` (with the optional `?workspace=` suffix) and a body that
  is `body` JSON-serialized verbatim, and MUST return the parsed `Address`.
- **addresses-delete-request-shape**: `deleteAddress` MUST send
  `DELETE /api/content/addresses/<enc(id)>` (with the optional `?workspace=` suffix) via
  `authedRequest`, not `authedJson`, and MUST resolve with no value.

**Workspace scoping (`workspaceQuery`)**

- **workspace-query-omitted-when-absent**: `workspaceQuery` MUST return the empty string when
  `opts.workspace` is undefined or falsy, producing a request URL byte-identical to the personal
  (no-workspace) path.
- **workspace-query-percent-encoded**: `workspaceQuery` MUST return
  `?workspace=<encodeURIComponent(opts.workspace)>` when `opts.workspace` is given, percent-encoding
  the slug.

**Cache keys (`socialLinksKey`, `addressesKey`, `usageSummaryKey`, `PRIVACY_KEY`)**

- **list-key-namespaced-by-owner**: `socialLinksKey`, `addressesKey`, and `usageSummaryKey` MUST
  each return `[...ROOT, "org", workspaceSlug]` when a workspace slug is given and
  `[...ROOT, "self"]` otherwise, differing at the same array segment so neither branch is a prefix
  of the other.
- **list-key-roots-not-exported**: `SOCIAL_LINKS_KEY`, `ADDRESSES_KEY`, and `USAGE_SUMMARY_KEY`
  MUST NOT be exported; only their namespaced accessor functions (`socialLinksKey`, `addressesKey`,
  `usageSummaryKey`) are part of the module's public surface.
- **privacy-key-not-namespaced**: `PRIVACY_KEY` MUST be exported directly as the fixed constant
  `["account", "privacy"]`, unlike the other three root keys, because privacy grants are not
  owner-scoped by workspace (see `privacy-grants-caller-scoped-only`).

**Privacy grants (`getPrivacyGrants`, `setPrivacyGrant`, `resolvePrivacyLevel`)**

- **privacy-grants-list-unwraps-envelope**: `getPrivacyGrants` MUST send `GET /api/account/privacy`
  and MUST return the bare `items` array unwrapped from the `{ items }` response envelope.
- **privacy-grants-caller-scoped-only**: `getPrivacyGrants` and `setPrivacyGrant` MUST NOT accept
  or forward a `workspace` parameter; both operate only on the calling principal's own privacy
  grants.
- **privacy-grant-set-request-shape**: `setPrivacyGrant` MUST send `PUT /api/account/privacy` with
  body `{ targetTable, targetId, audienceMask }`, where `audienceMask` is looked up from `level` via
  the fixed map `{"only-me": 0, public: 1, hub: 2}`, and MUST return the parsed `PrivacyGrant`.
- **privacy-level-resolution-default**: `resolvePrivacyLevel` MUST return `"only-me"` when no grant
  in the supplied array matches the given `(targetTable, targetId)` pair.
- **privacy-level-resolution-match**: `resolvePrivacyLevel` MUST use the first grant in array order
  whose `targetTable` and `targetId` both match, ignoring any subsequent duplicate entries.
- **privacy-level-resolution-public-precedence**: `resolvePrivacyLevel` MUST return `"public"`
  whenever the matched grant's `audienceMask` has bit 0 set (`audienceMask & 1`), regardless of
  whether bit 1 is also set.
- **privacy-level-resolution-hub**: `resolvePrivacyLevel` MUST return `"hub"` when the matched
  grant's `audienceMask` has bit 1 set (`audienceMask & 2`) and bit 0 is not set.
- **privacy-level-resolution-unmatched-bits**: `resolvePrivacyLevel` MUST return `"only-me"` when a
  grant matches but its `audienceMask` has neither bit 0 nor bit 1 set.

**Usage (`getUsageSummary`, `usageSummaryKey`)**

- **usage-summary-request-shape**: `getUsageSummary` MUST send `GET /api/usage/summary`, appending
  `?workspace=<enc(workspace)>` only when `opts.workspace` is given, and MUST return the bare `rows`
  array unwrapped from the `{ rows }` response envelope.
- **usage-summary-subject-list-server-derived**: `getUsageSummary` MUST NOT send any parameter
  naming which principals' usage to return beyond `workspace` itself; the subject list is derived
  entirely on the backend, per the module's own top-of-file comment.

**Wire shapes (`wire.ts`)**

- **owner-scoped-row-shape**: `SocialLink` and `Address` MUST both extend `OwnerScopedRow`
  (`id`, `customerId`, `deletedAt`, `ecosystemId`, `ownerKind`, `ownerId`, `createdAt`, `updatedAt`,
  `syncVersion`, `syncStampedAt`, `syncTxid`) in addition to their own fields.
- **write-shapes-exclude-server-managed-fields**: `SocialLinkWrite`/`AddressWrite` MUST include
  only the caller-writable fields (`platform`/`url`/`handle`/`sortOrder?` for `SocialLinkWrite`;
  `label`/`line1`/`line2`/`city`/`region`/`postalCode`/`country` for `AddressWrite`) and MUST NOT
  include `id`, `customerId`, `ownerKind`, `ownerId`, the timestamps, or the sync fields, which the
  server manages.
- **social-link-sort-order-is-render-order**: `SocialLink.sortOrder` MUST be the field the list
  route sorts by for the order the public user card renders these in, per the field's own doc
  comment; this module performs no client-side sort of its own.
- **privacy-target-table-widened**: `PrivacyTargetTable` MUST be typed as a plain `string`, not a
  closed union of known target tables, so this client cannot refuse a target table the backend
  later adds.
- **usage-limits-enforced-flag**: `UsageLimits.enforced` MUST reflect the global kill switch already
  ANDed into the per-key enforcement decision, per the type's own doc comment; when `false`, the
  quota fields are recorded against but never refused (observe-then-enforce).
- **usage-row-kind-application-admin-only**: a `UsageRow` with `kind: "application"` MUST only
  appear in the platform-admin ecosystem view — an application belongs to its ecosystem and to no
  workspace, so neither the personal nor the workspace-scoped view can produce one, per
  `UsageRowKind`'s own doc comment.

**Cross-cutting**

- **every-write-call-serializes-verbatim**: `createSocialLink`, `updateSocialLink`,
  `createAddress`, `updateAddress`, and `setPrivacyGrant` MUST JSON-serialize their body argument
  with no field renaming, omission, or added field beyond what the type of that argument already
  carries.
- **module-holds-no-mutable-state**: neither `profile.ts` nor `usage.ts` MUST cache, memoize, or
  retain any response across calls; every exported network function issues exactly one HTTP request
  per call, and `resolvePrivacyLevel`/`workspaceQuery`/the key functions perform a pure computation
  with no I/O.
- **no-runtime-response-validation**: `listSocialLinks`, `listAddresses`, `getPrivacyGrants`, and
  `getUsageSummary` MUST return whatever `authedJson`'s generic-typed cast produces, applying no
  runtime shape check of their own to the response body — unlike this cookbook's sibling
  `hub-domain-access` recipe's `listFeatures`.

### Security

This module carries address rows (physical mailing addresses), the privacy audience settings that
decide who may see a principal's social links and addresses, and metered usage/cost figures
(`UsageRow.costMicros`) — all principal-identifying or financially sensitive data — but it
authenticates and authorizes none of it itself.

- **auth-delegated-to-shared-client**: every network call in `profile.ts`/`usage.ts` MUST go
  through `authedJson` or `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via
  `./http`), which attaches the bearer credential; this module MUST NOT read, store, or attach a
  token itself.
- **no-client-side-storage-of-sensitive-fields**: `profile.ts`/`usage.ts` MUST NOT persist any
  address, social link, privacy grant, or usage row to `localStorage`, `sessionStorage`, or any
  other client-side store; every value is held only for the duration of the call that produced it.
- **audience-visibility-enforced-server-side**: `setPrivacyGrant` MUST NOT perform any client-side
  check of who may currently see a target's content before or after the write; this module's role
  is limited to translating a `PrivacyLevel` to `audienceMask` and sending it — enforcement of who
  is shown what based on the resulting mask happens entirely outside these two files.
- **violation-handling-inherited**: a non-2xx response to any call in this module MUST propagate as
  whatever error `authedJson`/`authedRequest` throws; this module defines no security-violation
  handling of its own.

