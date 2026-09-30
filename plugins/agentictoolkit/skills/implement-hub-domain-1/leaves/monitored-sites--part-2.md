<!-- leaf: implement-hub-domain-1/monitored-sites--part-2 · source: hub-domain-monitored-sites.md -->

# Hub Domain Monitored Sites — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/monitored-sites--part-2#<slug>`):

- `site-group-view-shape` MUST
- `site-view-renames-group-id` MUST
- `endpoint-view-shape` MUST
- `group-list-request` MUST
- `group-list-sorted-by-name` MUST
- `group-create-request` MUST
- `group-update-request` MUST
- `group-delete-request` MUST
- `group-delete-cascades` MUST
- `site-belongs-to-exactly-one-group` MUST
- `site-list-request` MUST
- `site-list-sorted-by-name` MUST
- `site-list-single-request-only` MUST
- `site-create-request` MUST
- `site-update-request` MUST
- `site-delete-request` MUST
- `site-delete-cascades` MUST
- `endpoint-list-request` MUST
- `endpoint-list-double-filtered` MUST
- `endpoint-list-sorted-by-url` MUST
- `endpoint-create-request` MUST
- `endpoint-update-request` MUST
- `endpoint-delete-request` MUST
- `every-write-url-encodes-identifiers` MUST
- `optional-fields-omitted-not-nulled` MUST
- `no-client-side-cache` MUST
- `owner-scoping-server-side` MUST
- `workspace-param-repins-owner` MUST
- `auth-delegated-to-shared-client` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST
- `no-conflict-friendly-mapping` MUST

## Behavioral Requirements

**Mappers (`toGroup`, `toSite`, `toEndpoint`)**

- **site-group-view-shape**: `toGroup` MUST map a `GroupRow` verbatim to a `SiteGroupView` carrying
  `id`, `slug`, `name`, `retentionDays`, `createdAt`, and `updatedAt`, with no field renamed.
- **site-view-renames-group-id**: `toSite` MUST copy a `SiteRow`'s `siteGroupId` field into
  `SiteView.groupId`; every other field (`id`, `slug`, `name`, `createdAt`, `updatedAt`) MUST be copied
  unchanged.
- **endpoint-view-shape**: `toEndpoint` MUST map an `EndpointRow` verbatim to an `EndpointView` carrying
  `id`, `siteId`, `url`, `kind`, `expectedStatus`, `checkIntervalSeconds`, `isActive`, `createdAt`, and
  `updatedAt`, with no field renamed.

**Groups (`listGroups`, `createGroup`, `updateGroup`, `deleteGroup`)**

- **group-list-request**: `listGroups` MUST send `GET /api/monitoring/site-groups` with the query string
  `workspaceQuery(opts)` appends (empty when `opts.workspace` is absent).
- **group-list-sorted-by-name**: `listGroups` MUST return the mapped `SiteGroupView[]` sorted by `name`
  via `sortByText`'s locale-aware `localeCompare`, without mutating the array `authedJson` returned.
- **group-create-request**: `createGroup` MUST send `POST /api/monitoring/site-groups` (plus
  `workspaceQuery`) with a body built by `compact()` from `{ name, slug, retentionDays }`, dropping
  `retentionDays` from the JSON payload when the caller omits it, and MUST return `toGroup(row)`.
- **group-update-request**: `updateGroup` MUST send `PUT /api/monitoring/site-groups/<enc(id)>` (plus
  `workspaceQuery`) with a `compact()` patch of `{ name, slug, retentionDays }`, and MUST return
  `toGroup(row)`.
- **group-delete-request**: `deleteGroup` MUST send `DELETE /api/monitoring/site-groups/<enc(id)>` (plus
  `workspaceQuery`) via `authedRequest`, discarding any response body, and MUST resolve with no value.
- **group-delete-cascades**: per the module's own comment on `deleteGroup`, deleting a group MUST cascade
  at the database level (`FK ON DELETE CASCADE`) to remove every site in that group and every endpoint of
  those sites; this client issues one `DELETE` request and performs no separate cleanup call of its own.

**Sites (`listSites`, `createSite`, `updateSite`, `deleteSite`)**

- **site-belongs-to-exactly-one-group**: a `SiteView` MUST carry exactly one `groupId` as a required
  field — the interface's own doc comment states "the single group this site belongs to (1:M;
  required)" — and this client models no many-to-many group membership.
- **site-list-request**: `listSites` MUST send `GET /api/monitoring/sites` (plus `workspaceQuery`).
- **site-list-sorted-by-name**: `listSites` MUST return `sortByText(rows.map(toSite), name)`.
- **site-list-single-request-only**: `listSites` MUST NOT issue a second request to the site-groups
  endpoint or perform any client-side intersection against group membership. Per the function's own
  comment, an earlier implementation did both — a second round-trip, plus a silent-hiding bug, since
  generic-CRUD lists cap at 500 rows and a workspace with more than 500 groups could drop sites whose
  group fell past that cap even though the server still monitors them; the current single-request form
  replaced it.
- **site-create-request**: `createSite` MUST send `POST /api/monitoring/sites` (plus `workspaceQuery`)
  with a body of exactly `{ name, slug, siteGroupId: body.groupId }`, renaming `groupId` to
  `siteGroupId`, sent without passing through `compact()` — all three fields are required by
  `CreateSiteBody`, so none can be `undefined`.
- **site-update-request**: `updateSite` MUST send `PUT /api/monitoring/sites/<enc(id)>` (plus
  `workspaceQuery`) with a `compact()` patch of `{ name, slug, siteGroupId: body.groupId }` built from
  the optional `UpdateSiteBody` fields.
- **site-delete-request**: `deleteSite` MUST send `DELETE /api/monitoring/sites/<enc(id)>` (plus
  `workspaceQuery`), discarding the body, and MUST resolve with no value.
- **site-delete-cascades**: per the module's own comment on `deleteSite`, deleting a site MUST cascade at
  the database level to remove every endpoint that belongs to it.

**Endpoints (`listEndpoints`, `createEndpoint`, `updateEndpoint`, `deleteEndpoint`)**

- **endpoint-list-request**: `listEndpoints` MUST send `GET /api/monitoring/endpoints` with a query
  string built from `URLSearchParams({ siteId })`, appending `workspace=<opts.workspace>` via `qs.set`
  only when `opts.workspace` is given — this is the one function in the file that builds its query string
  by hand instead of through the shared `workspaceQuery` helper every other function here uses.
- **endpoint-list-double-filtered**: `listEndpoints` MUST re-filter the mapped rows client-side to
  `e.siteId === siteId`, in addition to the server-side `siteId` equality filter the query string already
  applies. Per the function's own comment, this client filter is retained as defense-in-depth and is
  redundant once the server has already scoped the response.
- **endpoint-list-sorted-by-url**: `listEndpoints` MUST return the filtered rows sorted by `url` via
  `sortByText`.
- **endpoint-create-request**: `createEndpoint` MUST send `POST /api/monitoring/endpoints` (plus
  `workspaceQuery`) with a `compact()` body of `{ siteId, url, kind, expectedStatus,
  checkIntervalSeconds, isActive }`, where `siteId` comes from the function's own `siteId` parameter, not
  from `body`.
- **endpoint-update-request**: `updateEndpoint` MUST send `PUT /api/monitoring/endpoints/<enc(id)>`
  (plus `workspaceQuery`) with a `compact()` patch of `{ url, kind, expectedStatus,
  checkIntervalSeconds, isActive }`; `siteId` MUST NOT appear in this patch, so this operation cannot
  reparent an endpoint to a different site.
- **endpoint-delete-request**: `deleteEndpoint` MUST send `DELETE /api/monitoring/endpoints/<enc(id)>`
  (plus `workspaceQuery`), discarding the body, and MUST resolve with no value.
- **endpoint-kind-validation**: NEEDS REVIEW: Not implemented in source. `ENDPOINT_KINDS` declares the three valid endpoint kinds (`http`, `tcp`, `icmp`), but `CreateEndpointBody.kind`/`UpdateEndpointBody.kind` are typed as an unconstrained `string`, and neither `createEndpoint` nor `updateEndpoint` narrows the caller's value against `ENDPOINT_KINDS` (the `narrow` helper exported by `client-helpers.ts` exists for exactly this and is never called from this file) before sending it to the backend; a caller can create an endpoint with `kind: "ssh"` with no client-side signal that it will never be checked. Evidence that would settle it: whether `POST /api/monitoring/endpoints`/`PUT /api/monitoring/endpoints/:id` validates `kind` server-side, which is not present in this checkout.

**Cross-cutting**

- **every-write-url-encodes-identifiers**: every group, site, and endpoint `id` interpolated into a URL
  path segment MUST be percent-encoded via `enc` (`encodeURIComponent`, aliased in `client-helpers.ts`);
  every `workspace` value MUST likewise be percent-encoded, by `workspaceQuery` in every function except
  `listEndpoints`, which percent-encodes it via `URLSearchParams`/`qs.set` instead.
- **optional-fields-omitted-not-nulled**: `compact()` MUST drop only `undefined`-valued keys from a
  write body before it is serialized, preserving any explicit `null` a caller supplies — per `compact()`'s
  own doc comment, "`null` is preserved — it is an explicit 'clear this column'" — though no
  `CreateXBody`/`UpdateXBody` field in this module is typed to accept `null` itself, so this only matters
  if a caller bypasses the TypeScript types.
- **no-client-side-cache**: none of the twelve exported functions in `monitored-sites.ts` MUST cache or
  memoize a response; every call issues exactly one HTTP request (aside from the inherited `401`
  refresh-and-retry described below).
- **module-holds-no-mutable-state**: the only module-level values are the `GROUPS`/`SITES`/`ENDPOINTS`
  path-string constants and the `ENDPOINT_KINDS` tuple, all read-only; no shared mutable state exists for
  concurrent calls in this module to race on.

### Security

Monitored-sites configuration is not credential data, but every operation is owner/workspace-scoped, so
this recipe carries a dedicated security subsection per the cookbook's cross-cutting authorization
guidance.

- **owner-scoping-server-side**: per the module's own top-of-file comment, every operation MUST be
  owner-scoped server-side: `site_groups` by the caller's `user_id`; `sites` and `endpoints` inherit
  `user_id` and owner from their parent at create/reparent time.
- **workspace-param-repins-owner**: the optional `workspace` parameter, when supplied, MUST be sent as
  `?workspace=<slug>` on every operation (via `workspaceQuery`, or `listEndpoints`' equivalent
  `qs.set`), which per the comment pins the operation to the workspace's owning principal instead of the
  caller's own scope; list operations under a workspace MUST return only that principal's rows, and
  item update/delete under a workspace MUST resolve an org-owned row another member created.
- **auth-delegated-to-shared-client**: every network call in this module MUST go through `authedJson` or
  `authedRequest` (imported from `./http`, itself re-exporting `@agentic-toolkit/auth/client`); this
  module MUST NOT read, store, or attach a bearer token itself.
- **session-refresh-waterfall**: a `401` response to any call in this module MUST trigger exactly one
  token refresh and one retried request, inherited unconditionally from `authedFetch`; a second `401` on
  the retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`. This module defines
  no refresh or retry logic of its own.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved `401` MUST cause the
  call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body supplies one, a
  machine-readable `code`.
- **no-conflict-friendly-mapping**: no function in this module calls `rethrowConflict` (exported by
  `./http` for exactly this purpose elsewhere in the codebase) to translate a `409` "already exists"
  backend error into an entity-named friendly message; a duplicate group/site/endpoint slug MUST
  propagate as the raw `AuthHttpError` message the backend supplied.

