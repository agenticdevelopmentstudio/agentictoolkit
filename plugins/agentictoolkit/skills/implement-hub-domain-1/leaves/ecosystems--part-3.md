<!-- leaf: implement-hub-domain-1/ecosystems--part-3 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/ecosystems--part-3#<slug>`):

- `child-ecosystems-list-shape` MUST
- `child-ecosystems-descend-not-found-empty` MUST
- `child-ecosystems-recurse-via-rail` MUST
- `address-leaf-extraction` MUST
- `to-ecosystem-field-mapping` MUST
- `list-hides-defaults-sorted` MUST
- `list-for-workspace-scoped` MUST
- `workspace-default-ecosystem-id-shape` MUST
- `list-children-scoped` MUST
- `get-404-is-null` MUST
- `create-body-shape` MUST
- `create-scoping-url` MUST
- `create-conflict-mapping` MUST
- `update-slug-sent-on-presence` MUST
- `update-omits-unset-fields` MUST
- `update-single-put` MUST
- `update-returns-server-derived-row` MUST
- `delete-no-body` MUST
- `ecosystem-id-for-slug-ownership-first` MUST
- `auth-settings-bespoke-routes` MUST
- `identifier-exists-never-404s` MUST
- `identifier-rename-conflict-mapping` MUST
- `identifier-rename-is-not-ecosystems-renaming-route` MUST
- `workspace-default-hook-always-enabled` MUST
- `workspace-default-hook-query-key` MUST
- `workspace-default-hook-shared-client` MUST
- `workspace-default-hook-result-shape` MUST
- `workspace-default-hook-no-retry` MUST

### Apple — `ChildEcosystemsTopic`

- **child-ecosystems-list-shape**: with no further path segment,
  `child(for:path:rail:)` MUST return `.level` with
  `id: "child-ecosystems-list"`, `title: entry.label` (`"Child
  Ecosystems"`), `emptyMessage: "No child ecosystems yet."`, and a create
  action titled `"New Ecosystem"` presenting
  `EcosystemCreateForm(dataSource:parent: ecosystem).spec()`
  (`EcosystemSettingsTopic.swift`; pinned by
  `testChildEcosystemsLevelAndDescent`).
- **child-ecosystems-descend-not-found-empty**: resolving a child id via
  `dataSource.get(id:)` MUST return `.empty` on `HubError.notFound` and
  wrap any other error via `HubError.wrap`
  (`EcosystemSettingsTopic.swift`).
- **child-ecosystems-recurse-via-rail**: once a child ecosystem resolves,
  `ChildEcosystemsTopic` MUST delegate the remaining path to
  `rail.child(for: child, path:)` rather than resolving it itself — this
  is what lets an arbitrarily deep chain of child ecosystems reuse the
  exact same topics rail (manageability gate, topic dispatch, settings,
  further child ecosystems) at every level
  (`EcosystemSettingsTopic.swift`; pinned by
  `testChildEcosystemsLevelAndDescent`).

### Web — types and the row↔UI mapper (`ecosystems.ts`)

- **address-leaf-extraction**: `addressLeaf(identifier)` MUST return
  `identifier.slice(identifier.lastIndexOf(".") + 1)` — a pure string
  slice with no rdid-grammar validation, deliberately mirroring the
  backend's own leaf extraction character for character (`ecosystems.ts`).
- **to-ecosystem-field-mapping**: `toEcosystem(row)` MUST map `id`→both
  `id` and `identifier`, `slug`→`slug`, `description`/`region` nullable
  columns → `""` when `null`, `primaryDomain`→`domain` (`""` when
  `null`), and MUST include `canManage` in the result only when the row
  defines it (never as an explicit `undefined` key) (`ecosystems.ts`;
  pinned by the `toEcosystem` describe block in `ecosystems.test.ts`).
- **list-hides-defaults-sorted**: `list()` MUST filter out every
  `isDefault === true` row and sort the remainder by `name` via
  `sortByText` (locale-aware) (`ecosystems.ts`).
- **list-for-workspace-scoped**: `listForWorkspace(workspaceSlug)` MUST
  request `?workspace=<slug>` and sort by `name`; it MUST NOT client-filter
  `isDefault`, since the server already excludes both structural defaults
  and the principal's infrastructure row for this scope (`ecosystems.ts`).
- **workspace-default-ecosystem-id-shape**: `workspaceDefaultEcosystemId
  (workspaceSlug?)` MUST request `?workspace=<slug>&infrastructure=true`
  when given a slug, else `?infrastructure=true`; MUST return `null`
  (never `undefined`) when the response is an empty array; and MUST
  return `canManage: row.canManage !== false` (defaulting to `true`
  unless the server explicitly says `false`) (`ecosystems.ts`; pinned by
  the `ecosystemsApi.workspaceDefaultEcosystemId` describe block in
  `ecosystems.test.ts`).
- **list-children-scoped**: `listChildren(parentId)` MUST request
  `?parent=<parentId>` and sort by `name` (`ecosystems.ts`).
- **get-404-is-null**: `get(id)` MUST return `null` when the request fails
  with `isNotFound`, and MUST rethrow any other error unchanged
  (`ecosystems.ts`).
- **create-body-shape**: `create(input, opts?)` MUST send
  `id: input.identifier` and `slug: addressLeaf(input.identifier)` — the
  address's last segment, never the whole dotted identifier — plus
  `name`, `description`, `region`, and `primaryDomain: input.domain`
  (`ecosystems.ts`; pinned by the "sends the rdid's LAST SEGMENT as the
  slug" tests in `ecosystems.test.ts`).
- **create-scoping-url**: `create` MUST POST to `?parent=<opts.parent>`
  when `opts.parent` is given, else `?workspace=<opts.workspace>` when
  `opts.workspace` is given, else the bare base URL; `parent` MUST win
  when both are supplied (`ecosystems.ts`; pinned by the child-create and
  workspace-scoped tests in `ecosystems.test.ts`).
- **create-conflict-mapping**: a conflict (409) from the create request
  MUST be surfaced via `rethrowConflict` with the message `An ecosystem
  with identifier "<identifier>" already exists.` (`ecosystems.ts`).
- **update-slug-sent-on-presence**: `update(id, input)` MUST send `slug:
  addressLeaf(input.identifier)` whenever `input.identifier` is not
  `null`/`undefined` — including when the submitted identifier equals the
  stored `id` — and MUST NOT diff the submitted identifier against `id`
  to decide whether to send it, because `id` is the stored handle, not
  the address the row currently derives to, and the two can disagree on
  a drifted row (`ecosystems.ts`; pinned by the "still sends slug when
  the identifier equals the stored handle" and "sends the HEALING
  rename" tests in `ecosystems.test.ts`).
- **update-omits-unset-fields**: `update`'s body MUST be built via
  `compact` so any field the caller did not supply (including `slug`
  when `input.identifier` is `null`/`undefined`) is omitted from the
  request body entirely, never sent as `undefined`
  (`ecosystems.ts`; pinned by "omits slug when the caller edits fields
  without touching the identifier").
- **update-single-put**: `update` MUST be exactly one PUT request — it
  MUST NOT follow up with a second call to rename a handle
  (`ecosystems.ts`; pinned by `expect(mockedJson).toHaveBeenCalledTimes(1)`
  in "sends the new LEAF as slug, in the one PUT").
- **update-returns-server-derived-row**: `update`'s resolved `Ecosystem`
  MUST reflect the address the server derived from the PUT, never the
  identifier the caller typed, since a malformed or stale prefix in the
  caller's identifier can derive to a different address than what the
  caller assumed (`ecosystems.ts`; pinned by "returns the address the
  SERVER derived, never the identifier the caller typed").
- **delete-no-body**: `delete(id)` MUST send a DELETE request with no
  body and resolve to `void` (`ecosystems.ts`).
- **ecosystem-id-for-slug-ownership-first**: `ecosystemIdForSlug(slug)`
  MUST call `workspaceDefaultEcosystemId(slug)` first; on any error other
  than `isNotFound`, it MUST rethrow without falling back to a list scan;
  when that call resolves a row it MUST return that row's `id`; only a 404
  (the slug names no workspace) or a resolved `null` (no infrastructure
  row) MUST license the fallback raw scan of the unfiltered base route,
  which returns the first row matching `slug`, else the first `isDefault`
  row, else the first row, else `null`
  (`ecosystems.ts`; pinned by the `ecosystemsApi.ecosystemIdForSlug`
  describe block in `ecosystems.test.ts`, including "rethrows a non-404
  instead of picking a row").
- **auth-settings-bespoke-routes**: `authSettings(id)`/
  `updateAuthSettings(id, patch)` MUST call the hand-declared
  `/api/ecosystem/auth-settings/<id>` route (GET / PUT with a `compact`d
  patch) rather than the generic ecosystems CRUD base
  (`ecosystems.ts`).

### Web — `identifiers.ts`

- **identifier-exists-never-404s**: `identifiersApi.exists(rdid)` MUST
  call the `/exists` endpoint and return its boolean `exists` field
  directly — this probe MUST NOT itself throw for a rdid that is not
  taken (`identifiers.ts`).
- **identifier-rename-conflict-mapping**: `identifiersApi.rename
  (currentRdid, nextRdid)` MUST PATCH `{ rdid: nextRdid }` to
  `/api/registry/identifiers/<currentRdid>` and MUST surface a 409 via
  `rethrowConflict` with the message `The identifier "<nextRdid>" is
  already in use.` (`identifiers.ts`).
- **identifier-rename-is-not-ecosystems-renaming-route**: `identifiers.rename`
  is the generic, entity-agnostic rdid-rename mechanism (a
  `registry.identifiers` PATCH) shared across ecosystem/application/
  persona/namespace/organization; it MUST NOT be used to rename an
  ecosystem's address — `ecosystemsApi.update`'s `slug`-carrying PUT is
  the correct route for that, per **update-slug-sent-on-presence**
  (`identifiers.ts`, `ecosystems.ts`).

### Web — `useWorkspaceDefaultEcosystemId` (`use-workspace-default-ecosystem.ts`)

- **workspace-default-hook-always-enabled**: the underlying `useQuery`
  MUST NOT be gated (`enabled`) on `workspaceSlug` being defined — the
  hook MUST always run, resolving the caller's own row when
  `workspaceSlug` is `undefined` (`use-workspace-default-ecosystem.ts`).
- **workspace-default-hook-query-key**: the query key MUST be
  `["workspace-default-ecosystem", tenantId, workspaceSlug ?? null]`, so
  the cache entry is scoped per tenant and per slug (or the caller's own
  scope when no slug is given) (`use-workspace-default-ecosystem.ts`).
- **workspace-default-hook-shared-client**: the hook MUST pass the
  module-scoped `useToolkitQueryClient()` singleton explicitly to
  `useQuery` rather than reading a client from React context, so the
  cache entry is shared platform-wide across every mounting host
  (`use-workspace-default-ecosystem.ts`).
- **workspace-default-hook-result-shape**: the hook MUST return
  `ecosystemId` (`query.data?.id ?? undefined`), `canManage`
  (`query.data?.canManage ?? true`), `isError`, `isPending` (no answer
  yet — distinct from a resolved-but-empty answer), and `isFetching` (a
  read in flight, whether or not cached data already exists)
  (`use-workspace-default-ecosystem.ts`).
- **workspace-default-hook-no-retry**: the underlying query MUST be
  configured `retry: false` — a failed resolution MUST NOT be retried
  automatically (`use-workspace-default-ecosystem.ts`).

