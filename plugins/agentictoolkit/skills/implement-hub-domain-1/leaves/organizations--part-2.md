<!-- leaf: implement-hub-domain-1/organizations--part-2 · source: hub-domain-organizations.md -->

# Hub Domain: Organizations — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/organizations--part-2#<slug>`):

- `organization-shape` MUST
- `organization-rdid-presence` MUST
- `organization-list-row-omits-owner` MUST
- `organization-create-input-shape` MUST
- `organization-provisioned-shape` MUST
- `organization-rename-input-shape` MUST
- `organization-renamed-alias-unused` MUST
- `organization-restored-shape` MUST
- `workspace-member-shape` MUST
- `workspace-member-nullable-fields` MUST
- `workspace-member-is-admin-definition` MUST
- `workspace-member-added-at-definition` MUST
- `organization-list-workspace-required` MUST
- `organization-list-request-shape` MUST
- `organization-list-semantics-by-workspace-kind` MUST
- `organization-resolve-request-shape` MUST
- `organization-resolve-key-polymorphic` MUST
- `organization-resolve-no-404-mapping` MUST
- `organization-create-request-shape` MUST
- `organization-create-workspace-required` MUST
- `organization-create-conflict-mapping` MUST
- `organization-rename-request-shape` MUST
- `organization-rename-conflict-mapping` MUST
- `organization-archive-request-shape` MUST
- `organization-restore-request-shape` MUST
- `organization-restore-conflict-status-based` MUST
- `organizations-query-key-is-prefix-only` MUST
- `organizations-query-key-distinct-from-workspaces-key` MUST
- `roster-request-shape` MUST
- `roster-distinct-customers` MUST
- `roster-not-found-semantics` MUST
- `every-call-url-encodes-identifiers` MUST
- `no-client-side-cache` MUST
- `module-holds-no-mutable-state` MUST

## Behavioral Requirements

### Types (`wire.ts`)

- **organization-shape**: `Organization` MUST carry `id`, `slug`, `name`, `description?: string |
  null`, and `rdid?: string`.
- **organization-rdid-presence**: `Organization.rdid` MUST be present only on the response to a
  POST create; a plain GET (`resolve`) or PATCH (`rename`) response MUST omit it, per the type's
  own doc comment.
- **organization-list-row-omits-owner**: `OrganizationListRow` MUST carry only `id`, `slug`,
  `name`, `description?` — it MUST NOT carry an `ownerKind`/`ownerId` pair. `wire.ts`'s own doc
  comment records that this pair was removed because nothing read it: which workspace was asked is
  already the answer to "why is this org in the list."
- **organization-create-input-shape**: `OrganizationCreateInput` MUST carry exactly `slug` and
  `name` — every other organization property is provisioned server-side, per the type's own doc
  comment ("Only slug + name").
- **organization-provisioned-shape**: `OrganizationProvisioned` MUST carry `organization`,
  `namespace` (`id`, `ownerKind`, `ownerId`, `slug`, `name`, `rdid`), `teamId`, and `ecosystem`
  (`id`, `slug`, `rdid`).
- **organization-rename-input-shape**: `OrganizationRenameInput` MUST make `name`, `slug`, and
  `description` independently optional; the type's own doc comment declares that a caller MUST
  supply at least one of the three.
- **organization-renamed-alias-unused**: `OrganizationRenamed` MUST be exported (re-exported by
  `organizations.ts`) as a type alias of `Organization`, but `organizationsApi.rename`'s declared
  return type MUST remain `Organization`, never `OrganizationRenamed`.
- **organization-restored-shape**: `OrganizationRestored` MUST carry exactly one field,
  `organization`.
- **workspace-member-shape**: `WorkspaceMember` MUST carry `userId`, `email?: string | null`,
  `displayName?: string | null`, `isAdmin`, and `addedAt`.
- **workspace-member-nullable-fields**: `WorkspaceMember.email` and `.displayName` MUST be `null`
  (not merely absent) for a member outside the caller's ecosystem, per the type's own doc comment
  describing this as an RLS-bounded read, the same pattern team rosters use.
- **workspace-member-is-admin-definition**: `WorkspaceMember.isAdmin` MUST represent admin of ANY
  of the organization's teams — the roster's strongest role — per the type's own doc comment.
- **workspace-member-added-at-definition**: `WorkspaceMember.addedAt` MUST represent the EARLIEST
  membership timestamp across the organization's teams, per the type's own doc comment.

### Listing and resolution (`organizationsApi.list`, `.resolve`)

- **organization-list-workspace-required**: `organizationsApi.list` MUST take `workspaceSlug` as a
  required parameter; no workspace-less listing exists.
- **organization-list-request-shape**: `list` MUST send `GET /api/organization/organizations` with
  a `workspace=<enc(workspaceSlug)>` query parameter, and MUST return the response body unwrapped
  as `OrganizationListRow[]`.
- **organization-list-semantics-by-workspace-kind**: the set of rows `list` returns MUST depend on
  the named workspace's kind, per the function's own doc comment: a personal workspace's rows MUST
  be the organizations the caller owns plus the organizations the caller belongs to; an
  organization workspace's rows MUST be only the organizations that organization owns.
- **organization-resolve-request-shape**: `resolve(key)` MUST send `GET
  /api/organization/organizations/<enc(key)>` and MUST return the parsed body verbatim as an
  `Organization`.
- **organization-resolve-key-polymorphic**: `resolve` MUST pass `key` through unmodified — per the
  function's own doc comment, `key` MAY be a UUID, a slug, or a reverse-domain rdid, and `resolve`
  MUST NOT attempt to detect which before sending the request.
- **organization-resolve-no-404-mapping**: `resolve` MUST NOT catch or remap a 404 response; a
  not-found `key` MUST propagate as a thrown `AuthHttpError` with `status: 404`, unchanged.

### Creation (`organizationsApi.create`)

- **organization-create-request-shape**: `create(input, workspaceSlug)` MUST send `POST
  /api/organization/organizations` with a `workspace=<enc(workspaceSlug)>` query parameter, a
  `Content-Type: application/json` header, and `input` JSON-serialized verbatim as the body (no
  `compact`), and MUST resolve to the parsed `OrganizationProvisioned` body on success.
- **organization-create-workspace-required**: `create` MUST take `workspaceSlug` as a required
  parameter, naming both the workspace the organization is created FROM and the workspace that
  WILL OWN it.
- **organization-create-conflict-mapping**: a conflict thrown by the create request MUST be
  remapped, via `rethrowConflict`, to `An organization with that slug already exists.`; any other
  error MUST propagate unchanged.

### Rename (`organizationsApi.rename`)

- **organization-rename-request-shape**: `rename(id, input)` MUST send `PATCH
  /api/organization/organizations/<enc(id)>` with a `Content-Type: application/json` header and
  `compact(input)` JSON-serialized as the body, and MUST resolve to the parsed `Organization` body
  on success.
- **organization-rename-conflict-mapping**: a conflict thrown by the rename request MUST be
  remapped, via `rethrowConflict`, to `That organization slug is already taken.`; any other error
  MUST propagate unchanged.

### Archive and restore (`organizationsApi.archive`, `.restore`)

- **organization-archive-request-shape**: `archive(id)` MUST send `DELETE
  /api/organization/organizations/<enc(id)>` via `authedRequest` (not `authedJson`) and MUST
  resolve to `void`, since a 204 response has no body to parse.
- **organization-restore-request-shape**: `restore(id)` MUST send `POST
  /api/organization/organizations/<enc(id)>/restore`, MUST parse the response as
  `OrganizationRestored` via `authedJson`, and MUST resolve to `body.organization`, never the
  envelope.
- **organization-restore-conflict-status-based**: a 409 response to `restore` MUST be detected via
  `isConflict` (status-based), not `rethrowConflict` (message-based), and remapped to `That
  organization's handle has been taken, so it can't be restored.`; any other error MUST propagate
  unchanged.

### Query caching contract (`ORGANIZATIONS_QUERY_KEY`)

- **organizations-query-key-is-prefix-only**: `ORGANIZATIONS_QUERY_KEY` MUST be the fixed
  one-element tuple `["organizations"]` — a PREFIX a caller MUST append a workspace slug to
  (`[...ORGANIZATIONS_QUERY_KEY, slug]`) to form one workspace's complete cache key.
- **organizations-query-key-distinct-from-workspaces-key**: `ORGANIZATIONS_QUERY_KEY` MUST remain
  a constant distinct from any workspace-membership query key a caller separately maintains, per
  the export's own doc comment, since the two keys cache the answers to two different questions
  over two different endpoints.

### Workspace member roster (`workspaceMembersApi.list`)

- **roster-request-shape**: `workspaceMembersApi.list(slug)` MUST send `GET
  /api/workspaces/<enc(slug)>/members` via `authedJson` and MUST resolve to the parsed body
  verbatim as a `WorkspaceMembersResponse` (not unwrapped to a bare array, unlike
  `organizationsApi.list`).
- **roster-distinct-customers**: the resolved `WorkspaceMembersResponse.members` MUST be the
  distinct customers across the organization's org-owned teams, per the function's own doc comment
  ("the distinct customers across the org's org-owned teams"); a customer belonging to more than
  one of the organization's teams MUST appear exactly once.
- **roster-not-found-semantics**: `list` MUST propagate a 404 unchanged both for a slug naming no
  organization workspace and for an organization workspace the caller is not a member of, per the
  function's own doc comment; it performs no client-side membership check of its own.

### Cross-cutting

- **every-call-url-encodes-identifiers**: every `organizationsApi` and `workspaceMembersApi` method
  MUST percent-encode every caller-supplied identifier it places in a URL (`workspaceSlug`, `key`,
  `id`, roster `slug`) via `enc` (`encodeURIComponent` aliased in `client-helpers.ts`).
- **no-client-side-cache**: `organizationsApi` and `workspaceMembersApi` MUST NOT cache or memoize
  any response themselves; every call issues exactly one HTTP request.
- **module-holds-no-mutable-state**: neither module MUST hold mutable module-level state across
  calls; the only module-level value besides the URL templates each method builds inline is the
  read-only `ORGANIZATIONS_QUERY_KEY` constant. Unlike the sibling `ecosystemsApi`/`accessApi`
  clients, no `BASE` route constant is extracted in either file.

