---
id: 201572ee-2e0f-4839-94f5-252f8044c4bf
title: 'Hub Domain: Ecosystems'
domain: agentictoolkit://recipes/hub-domain-ecosystems
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Products/ecosystems domain logic: the Apple Hub rail (topics, forms,
  and an HTDVDataSource) and the web ecosystemsApi/identifiersApi/ecosystemFeaturesApi
  clients, unified by the rdid slug/address contract.'
platforms:
- swift
- macos
- ios
- typescript
- web
tags:
- hub
- ecosystems
- products
- rdid
- slug
- forms
- htdv
- react-query
- features
depends-on: []
related:
- agentictoolkit://recipes/auth-client
references:
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemsDataSource.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemsModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemsModule.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemSettingsTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/HubError.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubError+Wrap.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/RailPath.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/Slug.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/FormDetails.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/EcosystemsModuleTests.swift (agentictoolkit)
- packages/web/packages/data/src/ecosystems/ecosystems.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/identifiers.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/use-workspace-default-ecosystem.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/ecosystem-invitations.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/ecosystem-features.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/wire.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/__tests__/ecosystems.test.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystems/__tests__/use-workspace-default-ecosystem.test.tsx (agentictoolkit)
- packages/web/packages/data/src/ecosystems/__tests__/ecosystem-features.test.tsx (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Ecosystems

## Overview

`hub-domain-ecosystems` is the Ecosystems ("Products") domain of the hub: the
non-UI logic that lists, creates, renames, and deletes an *ecosystem* — a
reverse-domain-identified (rdid) product row that can itself own child
ecosystems, and that other domains (applications, buckets, customers) hang
off of. It has two independent, source-of-truth implementations that this
recipe covers together because they model the identical contract from
opposite ends of one system:

- **Apple** (`packages/apple/AgenticToolkit/Hub/Features/Ecosystems/`, Swift,
  macOS + iOS): `EcosystemsDataSource` (the I/O protocol an app adapter
  implements over the real hub API), `Ecosystem`/`EcosystemCreate`/
  `EcosystemUpdate` (the models), `EcosystemsModule` (the top-level
  `HTDVDataSource` that lists products and resolves each product's topics
  rail), `EcosystemTopicProvider`/`EcosystemTopicGroup`/`EcosystemNoticeTopic`
  (the topic-composition framework from `EcosystemTopic.swift`),
  `EcosystemSettingsTopic` (the product's own record — name/slug/identifier/
  description, plus delete), and `ChildEcosystemsTopic` (an ecosystem's own
  child ecosystems, recursing back through the same rail).
- **Web** (`packages/web/packages/data/src/ecosystems/`, TypeScript):
  `ecosystemsApi` (`ecosystems.ts` — list/create/update/delete/resolve
  against `/api/ecosystem/ecosystems`), `identifiersApi` (`identifiers.ts` —
  rename-in-place and availability probe against
  `/api/registry/identifiers`), `useWorkspaceDefaultEcosystemId`
  (`use-workspace-default-ecosystem.ts` — the react-query resolver every
  workspace-scoped pane and create-dialog preview shares), the
  Invitations topic's react-query hooks (`ecosystem-invitations.ts`), and
  `ecosystemFeaturesApi` plus its react-query hooks
  (`ecosystem-features.ts` — the data behind the ecosystem feature picker:
  the catalog of addable features, including "Coming soon" unbuilt ones,
  what an ecosystem is provisioned with, adding a batch, and removing one,
  against the bespoke `/api/ecosystem/features` route). The feature picker
  has no Apple counterpart in these sources.

Both sides model the same backend fact: an ecosystem's public identity is a
*stored, mutable* rdid (`id` / `identifier`), but the row's *own* address is
*derived* from `(parent chain, slug)` — `slug` is the one field a create or a
rename actually supplies, and the two names for the same value can drift
(a handle renamed by the OTHER route, `identifiers.rename`/`registry.identifiers`
PATCH, leaves the slug column behind). Every behavior below that looks like
string manipulation (`identifierPrefix`, `addressLeaf`) exists to keep a
caller on the correct side of that distinction.

## Behavioral Requirements

### Apple — models

- **ecosystem-model-shape**: `Ecosystem` MUST conform to `Codable, Hashable,
  Sendable, Identifiable` and carry `id`, `slug`, `name`,
  `description: String?`, `region: String?`, `primaryDomain: String?`,
  `createdAt: String?`, `updatedAt: String?`, `isDefault: Bool`,
  `isInfrastructure: Bool?`, `parentId: String?`, `canManage: Bool?`
  (`EcosystemsModels.swift`).
- **ecosystem-decode-default-fallback**: `Ecosystem.init(from:)` MUST decode
  `isDefault` as `false` when the key is absent from the payload, never
  throw for its absence (`EcosystemsModels.swift`; pinned by
  `testDecodesEcosystemWithMissingIsDefault`).
- **ecosystem-identifier-prefix**: `Ecosystem.identifierPrefix` MUST return
  everything up to and including the last `.` of `id` (e.g. `"org.acme."`
  for `"org.acme.shop"`), and MUST return `""` when `id` contains no `.`
  (`EcosystemsModels.swift`).
- **ecosystem-is-manageable**: `Ecosystem.isManageable` MUST equal
  `canManage ?? true` — an absent `canManage` (the server omits it for the
  caller's own ecosystems) MUST be treated as manageable; only an explicit
  `false` MUST block the rail (`EcosystemsModels.swift`).
- **ecosystem-create-input-defaults**: `EcosystemCreate.init` MUST default
  `region` and `primaryDomain` to `""` when the caller omits them
  (`EcosystemsModels.swift`).
- **ecosystem-update-input-shape**: `EcosystemUpdate` MUST make every field
  (`slug`, `name`, `description`, `region`, `primaryDomain`) optional, so a
  caller can patch a subset (`EcosystemsModels.swift`).

### Apple — data source protocol

- **ecosystems-data-source-contract**: `EcosystemsDataSource` MUST be
  `AnyObject, Sendable` and expose exactly `list()`, `children(of:)`,
  `get(id:)`, `infrastructureID()`, `identifierExists(_:)`,
  `create(_:parentID:)`, `update(id:_:)`, and `delete(id:)`, every one
  `async throws` (`EcosystemsDataSource.swift`).
- **ecosystems-list-includes-defaults**: `list()`'s own contract note MUST
  hold: the data source's `list()` includes default rows — hiding
  `isDefault` rows is `EcosystemsModule.rootLevel()`'s job, not the data
  source's (`EcosystemsDataSource.swift`).

### Apple — `EcosystemsModule` (root + rail)

- **root-level-hides-defaults**: `rootLevel()` MUST filter out every
  `ecosystem.isDefault == true` row before building items
  (`EcosystemsModule.swift`; pinned by
  `testRootLevelListsProductsWithoutDefaultRows`).
- **root-level-shape**: `rootLevel()` MUST return an `HTDVLevel` with
  `id: "ecosystems"`, `title: "Products"`, `emptyMessage: "No products yet."`,
  and a create action titled `"New Product"` that presents
  `EcosystemCreateForm(dataSource:parent: nil).spec()`
  (`EcosystemsModule.swift`).
- **root-level-errors-wrap**: `rootLevel()` MUST wrap any error from
  `dataSource.list()` via `HubError.wrap` before rethrowing
  (`EcosystemsModule.swift`; pinned by
  `testDataSourceFailuresSurfaceAsHubError`).
- **ecosystem-item-shape**: `EcosystemsModule.item(for:)` MUST build an
  `HTDVItem` with `id: ecosystem.id`, `label: ecosystem.name`,
  `sublabel: ecosystem.id`, `systemImage: "shippingbox"`
  (`EcosystemsModule.swift`).
- **child-by-id-not-found-is-empty**: `child(for path:)` MUST resolve the
  ecosystem via `dataSource.get(id:)` and return `.empty` when that throws
  `HubError.notFound`, wrapping any other error via `HubError.wrap`
  (`EcosystemsModule.swift`).
- **child-manageability-gate-first**: `child(for ecosystem:path:)` MUST
  check `ecosystem.isManageable` BEFORE resolving any topic — an
  unmanageable ecosystem MUST return a notice detail
  (`id: "ecosystem:\(ecosystem.id):not-manageable"`, `title:
  EcosystemsModule.notManageableTitle`, `message:
  EcosystemsModule.notManageableMessage`) regardless of what path segment
  follows (`EcosystemsModule.swift`; pinned by
  `testNotManageableProductShowsNotice`).
- **not-manageable-copy**: `EcosystemsModule.notManageableTitle` MUST be
  `"You don't have admin access to this ecosystem"` and
  `notManageableMessage` MUST be `"Viewing an ecosystem's contents needs
  organization admin access — ask one of the organization's admins."`
  (`EcosystemsModule.swift`).
- **topics-level-shape**: with no further path segment,
  `child(for ecosystem:path:)` MUST return `.level` with
  `id: "ecosystem-topics"`, `title: ecosystem.name`, and items built from
  the module's own `topics` array in the order the caller supplied it —
  `EcosystemsModule` MUST NOT impose a fixed topic order of its own
  (`EcosystemsModule.swift`).
- **topic-dispatch-by-entry-id**: with a topic-id path segment,
  `child(for ecosystem:path:)` MUST look up the matching provider by
  `entry.id` in the `topics` array and return `.empty` when none matches,
  else delegate to that provider's `child(for:path:rail:)`
  (`EcosystemsModule.swift`; pinned by
  `testUnknownProductOrTopicIsEmpty`).

### Apple — topic composition framework (`EcosystemTopic.swift`)

- **topic-entry-to-item**: `EcosystemTopicEntry.item()` MUST produce an
  `HTDVItem` carrying `id`, `label`, `sublabel: description`,
  `systemImage`, `dividerAfter`, and `leadsTo` (default `.list`)
  (`EcosystemTopic.swift`).
- **topic-group-level-shape**: `EcosystemTopicGroup.child(for:path:rail:)`
  with no further segment MUST return `.level` with
  `id: "ecosystem-group:\(entry.id)"`, `title: entry.label`, and its
  `children` mapped to items; with a segment, it MUST delegate to the
  matching child by `entry.id` or return `.empty`
  (`EcosystemTopic.swift`; pinned by
  `testGroupTopicListsItsChildrenAndDelegates`).
- **notice-topic-detail-shape**: `EcosystemNoticeTopic.child(for:path:rail:)`
  MUST always return `.detail` with
  `id: "ecosystem:\(ecosystem.id):\(entry.id)"`, `title: entry.label`,
  and the fixed `message` it was constructed with — it MUST NOT branch on
  `path` (`EcosystemTopic.swift`).

### Apple — `EcosystemCreateForm`

- **create-form-fields**: `spec()` MUST define exactly three fields, in
  order: `name` (text, required), `slug` (text, required, pattern
  `Slug.pattern`, message `Slug.patternMessage`), `description` (text area,
  optional, `minLines: 3`) (`EcosystemsModule.swift`; pinned by
  `testCreateFormDerivesIdentifierFromInfrastructure`).
- **create-form-slug-lowercased**: the save action MUST lowercase the
  submitted `slug` before deriving the identifier or probing existence,
  independent of `FormValidator`'s own pattern check
  (`EcosystemsModule.swift`; pinned by `testCreateActionLowercasesSlug`).
- **create-form-slug-max-length**: the save action MUST throw
  `HubError.validation("Slug must be 64 characters or fewer.")` when the
  lowercased slug exceeds 64 characters (`EcosystemCreateForm.slugMaxLength`)
  (`EcosystemsModule.swift`; pinned by
  `testCreateFormValidationMessages`).
- **create-form-prefix-resolution**: the save action MUST use the parent
  ecosystem's `id` as the address prefix when a parent was supplied at
  construction, and MUST otherwise call `dataSource.infrastructureID()`
  for the prefix, wrapping any error from that call via `HubError.wrap`
  (`EcosystemsModule.swift`; pinned by
  `testCreateFormForChildUsesParentPrefix`).
- **create-form-identifier-derivation**: the derived identifier MUST be
  exactly `"\(prefix).\(slug)"` (`EcosystemsModule.swift`).
- **create-form-duplicate-probe**: before creating, the save action MUST
  call `dataSource.identifierExists(identifier)` and throw
  `HubError.validation("Identifier \"\(identifier)\" is already in use.")`
  when it returns `true`, without ever calling `dataSource.create`
  (`EcosystemsModule.swift`; pinned by
  `testCreateFormValidationMessages`).
- **create-form-conflict-mapping**: a `HubError.conflict` thrown by
  `dataSource.create` MUST be re-thrown as
  `HubError.validation("An ecosystem with identifier \"\(identifier)\"
  already exists.")`; any other error MUST be wrapped via `HubError.wrap`
  (`EcosystemsModule.swift`; pinned by
  `testCreateFormValidationMessages`).

### Apple — `EcosystemSettingsTopic`

- **settings-form-fields**: `spec(for:)` MUST define, in order: `name`
  (text), `slug` (text, pattern `Slug.pattern`), `id` (read-only,
  monospaced, labeled `"Identifier"`), `description` (text area), `region`
  (read-only, labeled `"Geographic Region"`)
  (`EcosystemSettingsTopic.swift`; pinned by
  `testSettingsFormValuesAndSave`).
- **settings-values-region-hardcoded**: `values(for:)` MUST set the
  `region` field to the literal string `"coming soon"` regardless of the
  ecosystem's actual `region` property (`EcosystemSettingsTopic.swift`).
- **settings-save-identifier-derivation**: the save action MUST derive the
  target identifier as `ecosystem.identifierPrefix + slug` (the lowercased
  submitted slug), never from the form's `id` field, which is read-only
  (`EcosystemSettingsTopic.swift`).
- **settings-save-slug-lowercased**: the save action MUST lowercase the
  submitted `slug` before deriving the identifier, independent of
  `FormValidator`'s pattern check (`EcosystemSettingsTopic.swift`; pinned
  by `testSettingsSaveActionLowercasesSlug`).
- **settings-save-slug-validation**: the save action MUST validate the
  lowercased slug via `Slug.isValid` and throw `HubError.validation` with
  a message naming the derived identifier and describing the allowed
  character set when it fails (`EcosystemSettingsTopic.swift`).
- **settings-save-excludes-region**: the `EcosystemUpdate` the save action
  builds MUST carry only `slug`, `name`, and `description` — it MUST NOT
  set `region` or `primaryDomain`, even though the form displays a
  `region` value (`EcosystemSettingsTopic.swift`; pinned by
  `testSettingsFormValuesAndSave`, whose asserted update has
  `input.region == nil`).
- **settings-save-conflict-mapping**: a `HubError.conflict` thrown by
  `dataSource.update` MUST be re-thrown as
  `HubError.validation("Identifier \"\(identifier)\" is already in
  use.")`; any other error MUST be wrapped via `HubError.wrap`
  (`EcosystemSettingsTopic.swift`; pinned by
  `testSettingsSaveConflictBecomesIdentifierInUse`).
- **settings-delete-action**: the delete action MUST be a
  `FormDeleteAction` titled `"Delete Product"` with confirmation text
  `EcosystemSettingsTopic.deleteWarning`, and MUST call
  `dataSource.delete(id: ecosystem.id)`, wrapping any error via
  `HubError.wrap` (`EcosystemSettingsTopic.swift`; pinned by
  `testSettingsDeleteCallsDataSource`).

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

### Web — Invitations topic hooks (`ecosystem-invitations.ts`)

- **eco-invitations-keys-namespaced-by-rdid**: every query key in `KEYS`
  MUST include the ecosystem's `rdid` as its second element, so two
  ecosystems' Invitations caches never collide
  (`ecosystem-invitations.ts`).
- **eco-invitations-list-hooks-map-rows**: `useEcoInvitationRequests`,
  `useEcoPendingUsers`, and `useEcoInvites` MUST fetch from
  `ecosystemInvitationEndpoints(rdid)`'s corresponding endpoint and map
  every row through the shared `toRequest`/`toPendingUser`/`toInvite`
  mappers before returning them (`ecosystem-invitations.ts`).
- **eco-invitations-notes-history-gated-on-subject**: `useEcoRowNotes` and
  `useEcoRowHistory` MUST be `enabled: !!subjectId` — neither query MUST
  run for an empty subject id (`ecosystem-invitations.ts`).
- **eco-invitations-save-notes-invalidates-notes-and-history**:
  `useEcoSaveNotes`'s mutation, on success, MUST invalidate both the
  matching notes key and the matching history key for the same
  `(subjectTable, subjectId)` (`ecosystem-invitations.ts`).
- **eco-invitations-send-invalidates-pending-and-invites**:
  `useEcoSendInvitations`'s mutation, on success, MUST invalidate both
  the pending-users key and the invites key for the ecosystem
  (`ecosystem-invitations.ts`).
- **eco-invitations-add-pending-invalidates-pending**:
  `useEcoAddPendingUsers`'s mutation, on success, MUST invalidate the
  pending-users key (`ecosystem-invitations.ts`).
- **eco-invitations-delete-row-dispatch**: `useEcoDeleteRow(rdid, kind)`
  MUST select the DELETE endpoint (`requestItem`, `pendingUserItem`, or
  `invitationItem`) by `kind`, and on success MUST invalidate exactly the
  one list query key matching that same `kind` (`ecosystem-invitations.ts`).

### Web — feature picker data (`ecosystem-features.ts`)

- **features-bespoke-route**: every `ecosystemFeaturesApi` call MUST target
  the hand-written `/api/ecosystem/features` base route (`catalog`,
  `<ecosystemId>`, `<ecosystemId>/<featureKey>`), never the generic
  ecosystems CRUD base, because provisioning a feature has server-side side
  effects (its storage bucket, child ecosystem and roles are created when
  the feature is added and at no other time) (`ecosystem-features.ts`,
  header comment).
- **features-path-segments-encoded**: `list`, `provision` and `remove` MUST
  URL-encode `ecosystemId` (an rdid or uuid) and `featureKey` via `enc`
  (`encodeURIComponent`) before placing them in the path
  (`ecosystem-features.ts`).
- **features-catalog-order-preserved**: `ecosystemFeaturesApi.catalog()`
  MUST GET `/api/ecosystem/features/catalog` and return the response's
  `features` array unchanged, in the backend's own order — the client
  MUST NOT sort or filter it (alphabetising by `label` is the picker's and
  the rail's job) (`ecosystem-features.ts`).
- **features-catalog-entry-shape**: a `CatalogFeature` MUST carry `key`
  (stable, permanent; what a provisioned row is keyed by), `label`,
  `description`, `subscriptionTier`, and the optional flags `featureSite`
  and `comingSoon` (`ecosystem-features.ts`).
- **features-subscription-tier-open-string**: `FeatureSubscriptionTier`
  MUST be typed as a plain `string`, not a closed union, so a tier the
  backend adds later renders instead of failing to parse; the client MUST
  only display it, never branch on it (`ecosystem-features.ts`, doc
  comment on `FeatureSubscriptionTier`).
- **features-coming-soon-passthrough**: a catalog entry with
  `comingSoon: true` MUST be returned by `catalog()` like any other entry —
  this client MUST NOT filter it out; it is listed so the owner can see it
  is coming, the picker shows it under "Coming soon" with its checkbox
  disabled, and the backend refuses to provision it
  (`ecosystem-features.ts`, doc comment on `comingSoon`).
- **features-list-all-states**: `ecosystemFeaturesApi.list(ecosystemId)`
  MUST GET `/api/ecosystem/features/<ecosystemId>` and return every
  `ProvisionedFeature` in every `FeatureState` (`provisioning`, `active`,
  `removed`) unfiltered — callers filter (`ecosystem-features.ts`).
- **features-provisioned-shape**: a `ProvisionedFeature` MUST carry
  `featureKey`, `state: FeatureState`, `provisionedAt`,
  `provisionedBy: string | null`, and `updatedAt`
  (`ecosystem-features.ts`).
- **features-provision-one-request**: `ecosystemFeaturesApi.provision
  (ecosystemId, keys)` MUST send exactly one POST to
  `/api/ecosystem/features/<ecosystemId>` with header
  `Content-Type: application/json` and body `{ "keys": [...] }` carrying
  the whole batch, never one request per key (`ecosystem-features.ts`).
- **features-provision-returns-full-list**: `provision` MUST resolve to the
  response's `features` array — the ecosystem's FULL provisioned list after
  the add, not only the added rows (`ecosystem-features.ts`).
- **features-remove-single-delete**: `ecosystemFeaturesApi.remove
  (ecosystemId, featureKey)` MUST send one DELETE to
  `/api/ecosystem/features/<ecosystemId>/<featureKey>` with no body and
  resolve to `void` (`ecosystem-features.ts`; pinned by "resolves normally
  when the DELETE succeeds outright" in `ecosystem-features.test.tsx`).
- **features-remove-404-is-success**: `remove` MUST resolve (not throw) when
  the DELETE fails with `isNotFound` (404), because the row is already
  gone (`ecosystem-features.ts`; pinned by "treats a 404 as success" in
  `ecosystem-features.test.tsx`).
- **features-remove-rethrows-other-errors**: `remove` MUST rethrow every
  non-404 failure unchanged (`ecosystem-features.ts`; pinned by "still
  throws on a real failure" in `ecosystem-features.test.tsx`).
- **features-query-keys**: the catalog query key MUST be
  `["eco-features", "catalog"]` (no ecosystem id — the catalog is a
  property of the server build, shared by every ecosystem), and the
  provisioned query key MUST be `["eco-features", ecosystemId ?? ""]`
  (`ecosystem-features.ts`).
- **features-catalog-stale-time**: `useFeatureCatalog()` MUST configure
  `staleTime` as 30 minutes (1,800,000 ms) so opening the picker again
  within that window does not refetch the catalog
  (`ecosystem-features.ts`).
- **features-provisioned-query-gated**: `useProvisionedFeatures(ecosystemId)`
  MUST be `enabled: Boolean(ecosystemId)` — no request MUST run while the
  id is `null`, `undefined`, or `""` (`ecosystem-features.ts`).
- **features-hooks-context-client**: the feature hooks MUST use the query
  client from React context (`useQuery` without an explicit client,
  `useQueryClient()` in the mutations) — unlike
  `useWorkspaceDefaultEcosystemId`, which passes the module singleton
  explicitly (`ecosystem-features.ts`).
- **features-provision-writes-cache-then-invalidates**:
  `useProvisionFeatures`'s mutation, on success, MUST first write the
  returned full list into the provisioned query's cache via `setQueryData`
  and then invalidate that same key, so the rail redraws on the same tick
  and still picks up a concurrent session's changes
  (`ecosystem-features.ts`).
- **features-remove-hook-invalidates**: `useRemoveFeature`'s mutation, on
  success, MUST invalidate the provisioned query key and MUST NOT write the
  cache (the DELETE returns no list) (`ecosystem-features.ts`).
- **features-apply-adds-first**: `useApplyFeatureChange`'s mutation MUST
  await the single `provision` POST for `add` before issuing any removal,
  so a failed removal never costs the owner the features just added; a
  failed POST MUST reject the mutation before any DELETE is sent
  (`ecosystem-features.ts`).
- **features-apply-skips-empty-add**: `useApplyFeatureChange` MUST NOT send
  a POST when `add` is empty (`ecosystem-features.ts`).
- **features-apply-removals-all-settled**: `useApplyFeatureChange` MUST
  issue one `remove` per key in `remove` concurrently and wait for all of
  them via `Promise.allSettled`, so one rejected removal MUST NOT prevent
  the others from being attempted (`ecosystem-features.ts`; pinned by
  "runs every removal even when one fails" in
  `ecosystem-features.test.tsx`).
- **features-apply-names-failed-keys**: when one or more removals reject,
  `useApplyFeatureChange` MUST reject with an `Error` whose message is
  `Couldn't remove: ` followed by the failed keys, in `remove` order,
  joined by `, ` (`ecosystem-features.ts`; pinned by the
  `"Couldn't remove: b"` assertion in `ecosystem-features.test.tsx`).
- **features-apply-404-removal-succeeds**: a removal that 404s MUST count
  as success, so a change whose only removal failures are 404s MUST
  resolve (`ecosystem-features.ts`; pinned by "succeeds when every removal
  succeeds (or is a 404, already-gone)").
- **features-apply-invalidates-on-settle**: `useApplyFeatureChange` MUST
  invalidate the provisioned query key in `onSettled` — after success AND
  after failure, since a failure partway still changed part of the list
  (`ecosystem-features.ts`).
- **features-no-client-dedupe**: `useApplyFeatureChange` MUST pass `add`
  and `remove` through as given — it does not deduplicate keys or reject a
  key present in both lists; because adds run first, such a key is
  provisioned and then removed (`ecosystem-features.ts`).
- **features-mutation-null-id**: NEEDS REVIEW: Not implemented in source. `useProvisionFeatures`, `useRemoveFeature` and `useApplyFeatureChange` accept `ecosystemId: string | null | undefined` but cast it `as string` without a guard, so a mutation fired before the id resolves sends a request to a path segment of `null`/`undefined` (encoded as that literal text) instead of failing fast client-side; a guard (or a non-nullable parameter type) in `ecosystem-features.ts` would settle it.

## Appearance

Not applicable — this is domain logic (a data source protocol, a form/rail
model, and two API clients), not a visual component. The Apple side composes
`FormSpec`/`HTDVDetail` values that a separate, generic Forms/HTDV rendering
layer draws; the web side returns typed data and react-query hook state that
a separate set of panes render.

## States

Not applicable — this is domain logic, not a visual component. Its
observable "states" are the ordinary async-operation states a caller already
handles generically: in-flight (`isPending`/`isFetching` on the web hooks, an
awaited `async throws` call on Apple), succeeded, and failed (a thrown
`HubError` on Apple, a thrown `Error`/`AuthHttpError` on web).

## Accessibility

Not applicable — this is domain logic, not a visual component. Every string
this component defines (form field labels, delete-confirmation text, error
messages) is plain text handed to the generic Forms/HTDV rendering layer,
which owns accessibility presentation.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-ecosystems-001 | ecosystem-decode-default-fallback, ecosystem-identifier-prefix | Decode `{"id":"org.acme.shop","slug":"shop","name":"Shop","createdAt":"...","updatedAt":"..."}` (no `isDefault`, no `canManage`) | `isDefault == false`, `isManageable == true`, `identifierPrefix == "org.acme."` (`testDecodesEcosystemWithMissingIsDefault`) |
| hub-domain-ecosystems-002 | ecosystem-identifier-prefix | `Ecosystem.fixture(id: "shop").identifierPrefix` (no `.` in id) | `""` (`testDecodesEcosystemWithMissingIsDefault`) |
| hub-domain-ecosystems-003 | root-level-hides-defaults, root-level-shape | `rootLevel()` over `[acme(isDefault:true), shop, blog]` | items `["org.acme.shop","org.acme.blog"]`; `title == "Products"`; `emptyMessage == "No products yet."`; `createAction?.title == "New Product"` (`testRootLevelListsProductsWithoutDefaultRows`) |
| hub-domain-ecosystems-004 | topics-level-shape | `child(for: [shopItem])` with topics `[storageGroup, ChildEcosystemsTopic, EcosystemSettingsTopic]` | `.level` with `id == "ecosystem-topics"`, items `["storage","child-ecosystems","settings"]` in that caller-supplied order (`testProductChildIsTopicsRailInProviderOrder`) |
| hub-domain-ecosystems-005 | child-manageability-gate-first, not-manageable-copy | `child(for: [shopItem])` where `shop.canManage == false` | `.detail` with `id == "ecosystem:org.acme.shop:not-manageable"`, `title == "You don't have admin access to this ecosystem"`, notice value the fixed `notManageableMessage` (`testNotManageableProductShowsNotice`) |
| hub-domain-ecosystems-006 | topic-group-level-shape | Descend into the `"storage"` group topic, then its `"all-data"` child | Group level `id == "ecosystem-group:storage"`; child detail `id == "ecosystem:org.acme.shop:all-data"` (`testGroupTopicListsItsChildrenAndDelegates`) |
| hub-domain-ecosystems-007 | topic-dispatch-by-entry-id, child-by-id-not-found-is-empty | `child(for: [unknownItem])` and `child(for: [shopItem, unknownTopicItem])` | Both `.empty` (`testUnknownProductOrTopicIsEmpty`) |
| hub-domain-ecosystems-008 | settings-form-fields, settings-values-region-hardcoded | Open the Settings detail for `shop` (`description: "Storefront"`) | Fields `["name","slug","id","description","region"]`; values `name="Shop"`, `slug="shop"`, `id="org.acme.shop"`, `description="Storefront"`, `region="coming soon"`; `id` field not editable; delete title `"Delete Product"` (`testSettingsFormValuesAndSave`) |
| hub-domain-ecosystems-009 | settings-save-identifier-derivation, settings-save-excludes-region | Set `name="Web Shop"`, `slug="web-shop"`; save | `update` called with `id="org.acme.shop"`, `input.slug=="web-shop"`, `input.name=="Web Shop"`, `input.description=="Storefront"`, `input.region == nil` (`testSettingsFormValuesAndSave`) |
| hub-domain-ecosystems-010 | settings-save-conflict-mapping | `dataSource.update` throws `.conflict("dup")`; save with `slug="blog"` | Save fails; `saveError == "Identifier \"org.acme.blog\" is already in use."` (`testSettingsSaveConflictBecomesIdentifierInUse`) |
| hub-domain-ecosystems-011 | settings-delete-action | Invoke the delete action for `shop` | `dataSource.deletes == ["org.acme.shop"]` (`testSettingsDeleteCallsDataSource`) |
| hub-domain-ecosystems-012 | child-ecosystems-list-shape, child-ecosystems-recurse-via-rail | Descend `shop → child-ecosystems`, list has one child `shop.eu`, then descend into it and its `settings` topic | List `id == "child-ecosystems-list"`, `createAction?.title == "New Ecosystem"`; nested settings detail `id == "ecosystem:org.acme.shop.eu:settings"` (`testChildEcosystemsLevelAndDescent`) |
| hub-domain-ecosystems-013 | create-form-prefix-resolution, create-form-identifier-derivation | `EcosystemCreateForm(dataSource, parent: nil)`; `infrastructure == "org.acme"`; slug `"shop"` | Created `input.id == "org.acme.shop"`, `parentID == nil` (`testCreateFormDerivesIdentifierFromInfrastructure`) |
| hub-domain-ecosystems-014 | create-form-prefix-resolution | `EcosystemCreateForm(dataSource, parent: .fixture())` (`shop`); slug `"eu"` | Created `input.id == "org.acme.shop.eu"`, `parentID == "org.acme.shop"` (`testCreateFormForChildUsesParentPrefix`) |
| hub-domain-ecosystems-015 | create-form-slug-max-length, create-form-duplicate-probe, create-form-conflict-mapping | Three saves: 65-char slug; slug `"taken"` (already existing); slug `"fresh"` with `dataSource.createFailure = .conflict` | Errors respectively `"Slug must be 64 characters or fewer."`, `"Identifier \"org.acme.taken\" is already in use."`, `"An ecosystem with identifier \"org.acme.fresh\" already exists."`; `dataSource.creates` stays empty throughout (`testCreateFormValidationMessages`) |
| hub-domain-ecosystems-016 | create-form-slug-lowercased | `spec().actions.save!.perform(["name": "Shop", "slug": "SHOP", "description": "Storefront"])` | `creates[0].input.slug == "shop"`, `input.id == "org.acme.shop"` (`testCreateActionLowercasesSlug`) |
| hub-domain-ecosystems-017 | settings-save-slug-lowercased | `EcosystemSettingsTopic.spec(for: shop).actions.save!.perform(["name":"Shop","slug":"SHOP","description":"Storefront"])` | `updates[0].id == "org.acme.shop"`, `input.slug == "shop"` (`testSettingsSaveActionLowercasesSlug`) |
| hub-domain-ecosystems-018 | root-level-errors-wrap | `dataSource.failure = .offline`; call `rootLevel()` | Throws `HubError.offline` (`testDataSourceFailuresSurfaceAsHubError`) |
| hub-domain-ecosystems-019 | to-ecosystem-field-mapping | `toEcosystem({id:"com.acme", primaryDomain:"acme.com", ...})` | `.id=="com.acme"`, `.identifier=="com.acme"`, `.domain=="acme.com"` (`toEcosystem` describe, `ecosystems.test.ts`) |
| hub-domain-ecosystems-020 | to-ecosystem-field-mapping | `toEcosystem({..., description:null, region:null, primaryDomain:null})` | `.description==""`, `.region==""`, `.domain==""` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-021 | create-body-shape | `create({identifier:"ecosystem.fishlamp.adh", ...})` | Sent body `id=="ecosystem.fishlamp.adh"`, `slug=="adh"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-022 | create-body-shape | `create({identifier:"ecosystem.adh", ...})` | Sent body `slug=="adh"` (two-segment identifier) (`ecosystems.test.ts`) |
| hub-domain-ecosystems-023 | create-scoping-url | `create({identifier:"ecosystem.fishlamp.adh.sub"}, {parent:"ecosystem.fishlamp.adh"})` | URL `/api/ecosystem/ecosystems?parent=ecosystem.fishlamp.adh`; `slug=="sub"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-024 | create-scoping-url | `create({identifier:"ecosystem.fishlamp.adh"}, {workspace:"fishlamp"})` | URL `/api/ecosystem/ecosystems?workspace=fishlamp` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-025 | update-slug-sent-on-presence, update-single-put | `update("ecosystem.fishlamp.adh", {identifier:"ecosystem.fishlamp.adh2", name:"N"})` | Exactly one call; URL `/api/ecosystem/ecosystems/ecosystem.fishlamp.adh`; body `slug=="adh2"`, `name=="N"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-026 | update-slug-sent-on-presence | `update("ecosystem.fishlamp.adh", {identifier:"ecosystem.fishlamp.adh"})` (identifier equals stored id, but the row's slug column had drifted to `"chosen"`) | Sent `slug=="adh"`; returned `.slug=="adh"` — the healing rename (`"sends the HEALING rename"`, `ecosystems.test.ts`) |
| hub-domain-ecosystems-027 | update-omits-unset-fields | `update("ecosystem.fishlamp.adh", {name:"Renamed"})` (no `identifier`) | Body has no `slug` key; `name=="Renamed"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-028 | update-returns-server-derived-row | `update("ecosystem.fishlamp.adh", {identifier:"ecosystem.WRONG.adh2"})`; server echoes `ecosystem.fishlamp.adh2` | Returned `.id`/`.identifier == "ecosystem.fishlamp.adh2"`, never the caller's `"ecosystem.WRONG.adh2"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-029 | workspace-default-ecosystem-id-shape | `workspaceDefaultEcosystemId("fishlamp")` with one matching row | URL has `workspace=fishlamp&infrastructure=true`; result `{id, canManage:true}` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-030 | workspace-default-ecosystem-id-shape | `workspaceDefaultEcosystemId()` (no slug) | URL has bare `infrastructure=true`, no `workspace` param (`ecosystems.test.ts`) |
| hub-domain-ecosystems-031 | workspace-default-ecosystem-id-shape | `workspaceDefaultEcosystemId("fishlamp")` with an empty row array | `null` (never `undefined`) (`ecosystems.test.ts`) |
| hub-domain-ecosystems-032 | workspace-default-ecosystem-id-shape | Row carries `canManage: false` | Result `canManage === false` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-033 | ecosystem-id-for-slug-ownership-first | `ecosystemIdForSlug("fishlamp")` resolves via workspace lookup on the first call | Exactly one request; URL `workspace=fishlamp&infrastructure=true` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-034 | ecosystem-id-for-slug-ownership-first | `ecosystemIdForSlug("zed")` where the workspace lookup 404s | Falls back to a raw list scan and returns the row whose `slug == "zed"` (`ecosystems.test.ts`) |
| hub-domain-ecosystems-035 | ecosystem-id-for-slug-ownership-first | `ecosystemIdForSlug("fishlamp")` where the workspace lookup 403s | Rethrows `"HTTP 403"`; exactly one request made (no fallback scan) (`"rethrows a non-404 instead of picking a row"`, `ecosystems.test.ts`) |
| hub-domain-ecosystems-036 | workspace-default-hook-always-enabled, workspace-default-hook-no-retry | Render `useWorkspaceDefaultEcosystemId(undefined)` | Query runs immediately (not disabled); `retry: false` configured (`use-workspace-default-ecosystem.ts`) |
| hub-domain-ecosystems-037 | features-remove-404-is-success | `ecosystemFeaturesApi.remove("eco-1", "widgets")`; DELETE rejects with `{status: 404}` | Resolves `undefined` ("treats a 404 as success", `ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-038 | features-remove-rethrows-other-errors | `remove("eco-1", "widgets")`; DELETE rejects with `{status: 500}` | Rejects with `"HTTP 500"` ("still throws on a real failure", `ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-039 | features-remove-single-delete, features-bespoke-route | `remove("eco-1", "widgets")`; DELETE resolves | One DELETE to `/api/ecosystem/features/eco-1/widgets`; resolves `undefined` ("resolves normally when the DELETE succeeds outright", `ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-040 | features-apply-removals-all-settled, features-apply-names-failed-keys, features-apply-skips-empty-add | `useApplyFeatureChange("eco-1").mutate({add: [], remove: ["a","b","c"]})`; DELETE for `b` rejects 500, `a` and `c` resolve | Exactly 3 DELETEs issued, no POST; mutation status `error`; error message `"Couldn't remove: b"` (`ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-041 | features-apply-404-removal-succeeds | Same mutation; `b` rejects 404, `a` and `c` resolve | Mutation status `success`; no error (`ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-042 | features-provision-one-request, features-provision-returns-full-list | `provision("org.acme.shop", ["storage","users"])`; server answers `{features: [storage, users, research]}` | One POST to `/api/ecosystem/features/org.acme.shop`, `Content-Type: application/json`, body `{"keys":["storage","users"]}`; resolves the 3-row list (`ecosystem-features.ts`) |
| hub-domain-ecosystems-043 | features-catalog-order-preserved, features-coming-soon-passthrough | `catalog()`; server answers `{features: [zeta, alpha(comingSoon:true)]}` | Resolves `[zeta, alpha]` in that order, `alpha` still present with `comingSoon: true` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-044 | features-list-all-states | `list("eco-1")`; server answers rows in states `active`, `provisioning`, `removed` | All three rows returned unfiltered (`ecosystem-features.ts`) |
| hub-domain-ecosystems-045 | features-provisioned-query-gated, features-query-keys | Render `useProvisionedFeatures(null)` | No request issued; query key `["eco-features", ""]` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-046 | features-provision-writes-cache-then-invalidates | `useProvisionFeatures("eco-1").mutate(["storage"])`; POST returns list `L` | Cache for `["eco-features","eco-1"]` equals `L` immediately on success, then that key is invalidated (`ecosystem-features.ts`) |
| hub-domain-ecosystems-047 | features-apply-adds-first, features-apply-invalidates-on-settle | `useApplyFeatureChange("eco-1").mutate({add:["storage"], remove:["users"]})`; POST rejects 500 | Mutation rejects with the POST's error; no DELETE sent; `["eco-features","eco-1"]` still invalidated (`ecosystem-features.ts`) |
| hub-domain-ecosystems-048 | features-catalog-stale-time, features-query-keys | Render `useFeatureCatalog()` twice within 30 minutes | Query key `["eco-features","catalog"]`; one catalog fetch, second mount served from cache (`staleTime` 1,800,000 ms) (`ecosystem-features.ts`) |
| hub-domain-ecosystems-049 | features-path-segments-encoded | `remove("eco 1", "a/b")` | DELETE URL `/api/ecosystem/features/eco%201/a%2Fb` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-050 | features-remove-hook-invalidates | `useRemoveFeature("eco-1").mutate("storage")`; DELETE resolves | `["eco-features","eco-1"]` invalidated; no `setQueryData` write (`ecosystem-features.ts`) |
| hub-domain-ecosystems-051 | ecosystem-id-for-slug-ownership-first | `ecosystemIdForSlug("fishlamp")` where the workspace lookup resolves `null` (empty array) | Falls back to the raw base-route scan (`ecosystems.ts`) |

## Edge Cases

- **Null/empty input**: A slug of `""` after lowercasing — `Slug.pattern`
  requires at least one leading/trailing alphanumeric, so both
  `FormValidator`'s pattern check and `Slug.isValid` reject it before any
  network call. `workspaceDefaultEcosystemId` with an empty result array
  MUST resolve to `null`, never `undefined` or a thrown error
  (hub-domain-ecosystems-031); `ecosystemIdForSlug` then falls back to the
  raw scan, and MUST resolve to `null` only when that scan is also empty
  (hub-domain-ecosystems-051).
- **Boundary/malformed values**: A slug at exactly 64 characters — MUST be
  accepted; at 65 — MUST be rejected with the fixed message
  (hub-domain-ecosystems-015). A non-rdid `identifier` passed to
  `ecosystemsApi.create`/`update` (no `.` at all) — the client MUST pass
  its whole value through as `slug` unmodified via `addressLeaf`'s
  `lastIndexOf` fallback, deliberately letting the SERVER reject the
  malformed address rather than fabricating a different-looking error
  client-side (`"passes a non-rdid identifier through untouched"`,
  `ecosystems.ts`).
- **Concurrent access**: Two closely-timed `EcosystemCreateForm` saves for
  the same slug — the client-side `identifierExists` probe (Apple) is a
  courtesy check only; a probe that returns `false` right before a
  competing create lands is a real race the backend's own unique
  constraint resolves via a `409`, which both the Apple form and the web
  `create()` map to a friendly "already exists" message
  (create-form-conflict-mapping, create-conflict-mapping) — the probe
  narrows the window, it does not close it.
- **Error states**: Every `EcosystemsDataSource`/`ecosystemsApi` call that
  can fail surfaces a typed error to its caller — `HubError` on Apple
  (never a raw `Error` reaching a topic or the module), an `Error` with a
  numeric `.status` (`AuthHttpError`-shaped) on web. `HubError.notFound`
  is the one case multiple call sites treat as a structural, non-error
  outcome (`.empty` on Apple; `null` from `ecosystemsApi.get`) rather than
  a failure to surface.
- **Manageability / authorization**: An ecosystem whose `canManage` is
  explicitly `false` — the Apple rail MUST refuse to resolve ANY topic
  under it, including `child-ecosystems` and `settings`, returning only
  the not-manageable notice (child-manageability-gate-first). The web
  side carries the equivalent `canManage` through `toEcosystem` and
  `workspaceDefaultEcosystemId`, but enforcing it against a pane is each
  host's own responsibility — this component only reports the flag.
- **Identifier drift (handle vs. derived address)**: A row whose stored
  `id`/`identifier` (handle) and `slug` column have diverged — because
  something renamed the handle without moving the slug (the deprecated
  `identifiers.rename`/`registry.identifiers` PATCH path, or an old
  ancestor-cascade bug) — derives to a DIFFERENT address than its own
  handle claims. `ecosystemsApi.update` heals this specific case: sending
  the handle's own current value as the new `identifier` is a genuine
  slug change (`chosen` → `adh`, matching the stale handle) that a naive
  diff-against-`id` would have silently skipped
  (update-slug-sent-on-presence, hub-domain-ecosystems-026).
- **Feature removal already done**: a `remove` whose DELETE 404s (a
  double-click, a stale list, a second tab racing the same removal) MUST
  resolve as success, and inside `useApplyFeatureChange` it MUST count as
  a successful removal (hub-domain-ecosystems-037, -041).
- **Feature batch partial failure**: a `useApplyFeatureChange` whose adds
  succeed but some removals fail with a non-404 error MUST keep the adds,
  still attempt every other removal, reject naming only the failed keys,
  and invalidate the provisioned list (hub-domain-ecosystems-040). A
  failed add POST MUST reject before any removal is sent
  (hub-domain-ecosystems-047); whether the backend's batch transaction
  rolls back whole is the backend's contract, which this client relies on
  and does not verify.
- **Empty feature change**: `useApplyFeatureChange` with `add: []` MUST send
  no POST; with `remove: []` it MUST send no DELETE and resolve (an
  `allSettled` over zero promises). With both empty it sends nothing and
  still invalidates the provisioned list. `useProvisionFeatures` has no
  such guard: `mutate([])` MUST send a POST with `{"keys": []}`.
- **Already-active or stale feature keys**: provisioning a key that is
  already `active` is a backend no-op, not a conflict — the client sends it
  unchanged and surfaces whatever the backend answers; a `provisioning`-state
  row is the picker's concern to show as already taken.
- **Coming-soon feature submitted**: `provision` sends a `comingSoon` key
  unchanged if a caller supplies one; the backend refuses it and the
  rejection surfaces unchanged to the caller — this client performs no
  client-side refusal.
- **Feature hooks with no ecosystem id**: `useProvisionedFeatures` MUST NOT
  fetch while the id is `null`/`undefined`/`""`; the mutation hooks do not
  guard it (see the open question on features-mutation-null-id).
- **Concurrent feature changes**: the removals inside one
  `useApplyFeatureChange` run in parallel; they touch distinct keys, so
  their completion order does not affect the result, and the list is
  re-read once on settle. Two sessions changing the same ecosystem are
  reconciled only by the post-mutation invalidation re-reading the
  server's list.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `topics` | `[any EcosystemTopicProvider]` (Apple, `EcosystemsModule.init`) | none — required | The ordered set of topic providers a product's rail exposes; `EcosystemsModule` imposes no fixed order or fixed membership |
| `parent` | `Ecosystem?` (Apple, `EcosystemCreateForm.init`) | `nil` | When set, the new ecosystem is created as a child of this ecosystem; when `nil`, the prefix comes from `dataSource.infrastructureID()` |
| `EcosystemCreateForm.slugMaxLength` | `Int` constant (Apple) | `64` | Client-side slug length ceiling enforced before any network call |
| `workspaceSlug` | `string \| undefined` (web, `workspaceDefaultEcosystemId`/the hook) | `undefined` | Selects the workspace principal's infrastructure row; omitted resolves the caller's own |
| `opts.parent` / `opts.workspace` | `string \| undefined` (web, `ecosystemsApi.create`) | both `undefined` | Scope a create to a parent ecosystem or a workspace's principal; `parent` wins if both are given |
| `BASE` (`/api/ecosystem/ecosystems`) | internal constant (web, `ecosystems.ts`) | fixed | Base route for every generic-CRUD ecosystems call |
| `BASE` (`/api/registry/identifiers`) | internal constant (web, `identifiers.ts`) | fixed | Base route for rdid rename/availability |
| `BASE` (`/api/ecosystem/features`) | internal constant (web, `ecosystem-features.ts`) | fixed | Base route for the feature catalog, provisioned list, add and remove |
| `ecosystemId` | `string \| null \| undefined` (web, feature hooks) | none — required | The ecosystem (rdid or uuid) whose features are listed or changed; the list query is disabled while it is falsy |
| `keys` | `string[]` (web, `provision`/`useProvisionFeatures`) | none — required | Catalog `key`s to add in one batch |
| `FeatureChange` `{ add, remove }` | `string[]` each (web, `useApplyFeatureChange`) | none — required | One picker visit: keys to add (one POST), provisioned keys to remove (one DELETE each) |
| catalog `staleTime` | internal constant (web, `useFeatureCatalog`) | `30 * 60 * 1000` ms | How long the session-wide catalog is served from cache before a refetch |

## Deep Linking

Not applicable — this component owns no URL scheme, Android intent filter,
or platform deep-link registration. Apple navigation position is expressed
as an `[HTDVItem]` path resolved through `RailPath.id(at:in:)`, which a
separate rail-hosting view controller (not part of this recipe) is
responsible for turning into or out of any real deep link. The web routes
(`/api/ecosystem/ecosystems`, `/api/registry/identifiers`) are HTTP API
routes, not front-end deep links.

## Localization

- **Apple hardcoded strings**: `"Products"`, `"No products yet."`,
  `"New Product"`, `"Child Ecosystems"`, `"No child ecosystems yet."`,
  `"New Ecosystem"`, `"Settings"`, `"Delete Product"`,
  `EcosystemSettingsTopic.deleteWarning` ("Deleting a product deletes all
  the data associated with the product, including applications, buckets,
  and users. Do you wish to proceed?"), `EcosystemsModule.notManageableTitle`/
  `notManageableMessage`, `EcosystemCreateForm.slugTooLongMessage`
  ("Slug must be 64 characters or fewer."), every field label
  (`"Display Name"`, `"Slug"`, `"Identifier"`, `"Description"`,
  `"Geographic Region"`), and every "already in use"/"already exists"
  validation message this recipe's requirements quote.
- **Web hardcoded strings**: every thrown-error friendly message
  (`rethrowConflict`'s "An ecosystem with identifier ... already exists.",
  "The identifier ... is already in use."), and `useApplyFeatureChange`'s
  `Couldn't remove: <keys>` error. Catalog `label`/`description`/
  `subscriptionTier` text is served by the backend and passed through
  untranslated.

Neither implementation has a lookup table, i18n key, or locale parameter
anywhere in these files — every user-facing string above is fixed English.
This is a plain, honestly-reported fact about the current source, not a
hidden gap (see Compliance).

## Accessibility Options

Not applicable — this component renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior. Those act on
whatever UI a host renders around the `FormSpec`/`HTDVDetail` values (Apple)
or the query/mutation results (web) this component returns.

## Feature Flags

Not applicable — no file in either implementation defines or reads a
feature-flag key. Every conditional path (manageability, notFound-as-empty,
slug drift healing, workspace vs. caller scoping) is derived from a model
field, a thrown error's shape, or a caller-supplied option, never from a
flag this component owns.

## Analytics

Not applicable — no file in either implementation emits a client-side
analytics or telemetry event.

## Privacy

- **Data collected**: Ecosystem administrative metadata only — `name`,
  `slug`/`identifier`, `description`, `region`, `primaryDomain`/`domain`,
  timestamps, and the caller's own `canManage` flag. None of these fields
  are personal data about an end user; they describe a product/ecosystem
  record, not a person.
- **Storage**: Apple holds no cache of its own — every `EcosystemsModule`/
  topic call is a live `async throws` round-trip to whatever
  `EcosystemsDataSource` adapter the app supplies. Web holds the results
  in the shared react-query client's in-memory cache, keyed as documented
  under each hook/query above; nothing in this component writes to
  `localStorage`/`sessionStorage`/`IndexedDB`.
- **Transmission**: All calls travel through the injected data source
  (Apple) or `authedJson`/`authedRequest` (web, `@agentic-toolkit/auth`'s
  Bearer-token client — see `auth-client`); this component itself attaches
  no credentials and reads no cookies.
- **Retention**: Apple retains nothing between calls. Web's react-query
  cache entries persist per their query key until invalidated by the
  matching mutation (as documented per hook above) or garbage-collected by
  react-query's own cache lifetime; the only custom cache settings are the
  workspace-default hook's `retry: false` and the feature catalog's
  30-minute `staleTime`, and no `gcTime` is set anywhere. Provisioned
  feature rows carry `provisionedBy` (a principal id or `null`), held only
  in that in-memory cache.

## Logging

No file in either implementation calls a logger, `console.log`,
`console.warn`, `console.error`, or any platform logging API. Every
failure this component detects is surfaced to its caller as a thrown
`HubError` (Apple) or `Error`/`AuthHttpError` (web); any logging of that
failure is the responsibility of the caller or host application, not of
this domain component.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: This is one of the two reference
  implementations. `EcosystemsModule`/topics are `@MainActor` and
  `Sendable`-safe under Swift 6 strict concurrency; the same `FormSpec`
  values these topics build are rendered by both the macOS `FormSheet`/
  `FormViewController` (`HTDV/Views/macOS/`) and the iOS
  `FormSheet+UIKit`/`FormViewController+UIKit` (`HTDV/Views/iOS/`)
  presenters, so this domain logic is genuinely shared, unmodified,
  across macOS and iOS — only the presenting view layer differs.
- **React/Web**: This is the other reference implementation.
  `ecosystemsApi`/`identifiersApi` are plain async functions over `fetch`
  (via `authedJson`/`authedRequest`); `useWorkspaceDefaultEcosystemId` and
  the Invitations and feature hooks are `@tanstack/react-query` wrappers
  around them. Only `useWorkspaceDefaultEcosystemId` passes the module
  query-client singleton explicitly; the Invitations and feature hooks read
  the client from context. `ecosystem-features.ts` (with its test
  `ecosystem-features.test.tsx`) is web-only: the Apple Hub has no feature
  picker data source in these sources, so a port of the picker starts from
  the web contract.
- **Compose / Android**: `OkHttp`/`Ktor` (or `Retrofit`) would replace
  `fetch`/`URLSession` for the web/Apple network calls respectively; a
  `ViewModel` exposing a `StateFlow`/`LiveData` of the resolved ecosystem
  list is the idiomatic equivalent of both `EcosystemsModule.rootLevel()`
  and the react-query list hooks. `androidx.lifecycle.SavedStateHandle` or
  a `Room`-backed repository would be where a native Android port adds a
  local cache neither reference implementation currently has. For the
  feature picker, `coroutineScope { keys.map { async { runCatching {
  remove(it) } } }.awaitAll() }` is the equivalent of `Promise.allSettled`,
  run after the provision call returns.
- **WinUI 3**: `HttpClient` with `System.Text.Json` replaces both
  `fetch` and `URLSession` for every ecosystems/identifiers request this
  recipe documents. A `NavigationView`/`TreeView` with a
  `TreeViewNode`-backed hierarchy is the idiomatic equivalent of the
  Apple rail's recursive `HTDVLevel`/`HTDVChild` model (products → topics
  → child ecosystems, recursing arbitrarily deep per
  child-ecosystems-recurse-via-rail); a `ContentDialog` hosting a form
  built from `Microsoft.UI.Xaml.Controls` (`TextBox` for `name`/`slug`,
  a read-only `TextBlock` for `id`, a multi-line `TextBox` for
  `description`) is the equivalent of `FormSheet`'s create dialog, and a
  second `ContentDialog` with a destructive-styled primary button is the
  equivalent of `FormDeleteAction`'s confirmation flow. `Task`/`async`-
  `await` replaces every `Promise`/Swift `async throws` call; a custom
  `HubError`-equivalent exception hierarchy (or a `Result<T, HubError>`)
  should carry the same `notFound`/`conflict`/`validation` distinctions
  this recipe's error-mapping requirements rely on, since WinUI has no
  built-in typed-error convention of its own to inherit. For the feature
  picker: a `FeaturesClient` over `HttpClient` exposes `GetCatalogAsync`
  (deserialize `{ features }` with `System.Text.Json`, keep server order),
  `ListAsync`, `ProvisionAsync` (one `PostAsJsonAsync` with
  `{ keys }`, returning the full list) and `RemoveAsync` (`DeleteAsync`,
  treating `HttpStatusCode.NotFound` as success), with path segments
  escaped by `Uri.EscapeDataString`. The picker is a `ContentDialog`
  hosting a `ListView` of `CheckBox` items bound to an
  `ObservableCollection<FeatureRow>` whose rows implement
  `INotifyPropertyChanged`; a `comingSoon` row goes in a separate
  "Coming soon" group (a `CollectionViewSource` with `IsSourceGrouped`) with
  `IsEnabled="False"`, and a `provisioning` row shows as already checked.
  Applying a change awaits `ProvisionAsync` first, then
  `Task.WhenAll` over per-key tasks that each catch their own exception
  and return a success flag (plain `Task.WhenAll` throws on the first
  fault, unlike `Promise.allSettled`), then throws
  `Couldn't remove: <keys>` for the failures and always re-reads the list
  in a `finally`. The 30-minute catalog cache has no built-in equivalent:
  keep the catalog and a fetched-at `DateTimeOffset` in a
  session-lifetime service.

## Design Decisions

**Decision**: `EcosystemSettingsTopic.values(for:)` always reports
`region` as the literal string `"coming soon"`, and its save action never
includes `region` (or `primaryDomain`) in the `EcosystemUpdate` it sends,
regardless of what the form displays.
**Rationale**: The Apple settings form has not yet built real region
editing; showing a fixed placeholder is an honest "not yet available"
signal rather than either fabricating a value from the model's real
(currently unused) `region` field or omitting the row entirely. Never
sending it on save is a direct consequence: there is nothing real to send.
**Approved**: pending

**Decision**: `EcosystemsModule.child(for ecosystem:path:)` checks
`ecosystem.isManageable` before resolving any topic, so an unmanageable
ecosystem's `child-ecosystems`/`settings`/other topics are unreachable —
never partially reachable with per-action 403s.
**Rationale**: The alternative (resolve the topic, let the eventual
mutation 403) would let a non-admin org member browse an ecosystem's full
settings/child list read-only before hitting a wall on save/delete — worse
UX than one honest, upfront notice, and it would require every downstream
topic to independently re-check manageability.
**Approved**: pending

**Decision**: `ecosystemsApi.update` sends `slug` whenever the caller
supplies `identifier` at all, never only when it differs from the stored
`id`.
**Rationale**: `id` is the stored, mutable HANDLE; what a settings form
actually edits is the address the row DERIVES to from `(parent chain,
slug)`. The two disagree on exactly the rows this matters most for — a
row whose handle still says `…mike` while its slug column already says
`chosen` — where diffing against `id` would silently drop the one save
that heals the drift (a rename back to `…mike`, which equals `id` but is
a genuine slug change). Sending an already-correct slug costs nothing:
the route's own stored-value diff rules out a true no-op before any
cascade runs.
**Approved**: pending

**Decision**: The old two-call rename sequence (a PUT of ordinary fields
followed by a `registry.identifiers` PATCH of the handle) was removed in
favor of the single `ecosystemsApi.update` PUT carrying `slug`.
**Rationale**: The address is derived from `(parent chain, slug)`, so
moving the slug IS the rename; PATCHing the handle separately retitles it
without moving the slug column, leaving the row deriving its OLD address
— and the next ancestor cascade re-leafs the handle back, silently undoing
the rename. The two-call sequence also needed a 404-recovery branch for
the case where the first call lands and the second fails; the single-PUT
shape has no such window, because a failed PUT changes nothing.
`identifiersApi.rename` remains the correct mechanism for other,
non-address-bearing entity types (or a future purely-cosmetic handle
retitle) — it is simply not the ecosystems rename path anymore.
**Approved**: pending

**Decision**: `useWorkspaceDefaultEcosystemId` is never disabled
(`enabled`) on the absence of `workspaceSlug`.
**Rationale**: A disabled query stays `isPending` forever; a caller that
treats `isPending` as "still resolving, wait for it" then waits on an
answer that never comes. Every slug-less host (a feature-site mount whose
creates are caller-owned, not workspace-owned) needs the CALLER's own
infrastructure row, which is a real, resolvable answer, not the absence
of one — so the query must actually run for that case too.
**Approved**: pending

**Decision**: The Apple `Ecosystem` model and `EcosystemSettingsTopic`'s
form expose no `primaryDomain`/`domain` field, while the web `Ecosystem`
interface and settings-equivalent panes do (`domain`, mapped from
`primaryDomain`).
**Rationale**: This is a genuine, current cross-platform divergence, not
an inconsistency in this recipe's sourcing: the Apple Hub UI for editing a
custom domain has not been built yet, while the web client already models
the field end-to-end (`EcosystemInput.domain`, `toEcosystem`,
`EcosystemPutBody.primaryDomain`). A future Apple settings field for it
should follow the same read-only-until-built pattern `region` uses today,
not invent new semantics.
**Approved**: pending

**Decision**: `ecosystem-invitations.ts`'s row-shape mappers
(`toRequest`, `toPendingUser`, `toInvite`, `toAdminNote`,
`toHistoryEntry`) and their backend types are imported from
`@agentic-toolkit/adh-ui/invitations-types` rather than defined in this
recipe.
**Rationale**: Those mappers are shared with the platform-admin
invitations hooks referenced in this file's own header comment
(`websites/main/admin/src/api/invitations.ts`) — they belong to the
Invitations feature's own contract, not to Ecosystems. This recipe
documents what the Ecosystems-owned hooks in `ecosystem-invitations.ts`
do with their query keys, endpoints, and cache invalidation, and treats
the mappers' internal field-by-field shape as a different component's
concern, out of scope here.
**Approved**: pending

**Decision**: Features are added as one plural POST per batch, while
removals are one DELETE per key, run concurrently and collected with
`Promise.allSettled`, adds first.
**Rationale**: The picker confirms a batch of adds behind one "Add N
features?" prompt and the backend runs the batch in one transaction, so a
partial failure never leaves the owner with three of five features and no
way to tell which. The DELETE route removes one key, so removals cannot
share a request; `allSettled` keeps one 5xx from silently aborting the
rest the way a sequential `for … await` would, and naming the failed keys
tells the caller which features are still provisioned. Adds go first so a
failed removal never costs the features just added.
**Approved**: pending

**Decision**: `ecosystemFeaturesApi.remove` treats a 404 as success.
**Rationale**: The caller's goal is that the row is gone; a double-click, a
stale list, or a second tab racing the same removal would otherwise report
failure for an outcome that already happened. Every other status still
throws.
**Approved**: pending

**Decision**: The feature catalog is cached under a key with no ecosystem id
and a 30-minute `staleTime`, and "Coming soon" entries stay in it.
**Rationale**: The catalog is a property of the server build, not of any
ecosystem, so one list serves the whole session; refetching it on every
picker open would re-download the same rows each time. Unbuilt features are
kept so the owner can see what is coming; the picker disables them and the
backend refuses to provision them, so the client needs no filter.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [retry-with-backoff](agenticdevelopercookbook://compliance/access-patterns#retry-with-backoff) | failed | Access Patterns |
| [offline-behavior](agenticdevelopercookbook://compliance/access-patterns#offline-behavior) | failed | Access Patterns |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | partial | Reliability |

`separation-of-concerns` **passed**: `EcosystemsDataSource` is a pure I/O
boundary the module never bypasses; topics compose via the
`EcosystemTopicProvider` protocol rather than subclassing or reaching into
each other's state, and the web client keeps wire shapes (`wire.ts`)
separate from the UI-facing `Ecosystem` type. `explicit-error-handling`
**passed**: every catch on both platforms either re-maps a specific error
(`HubError.notFound`→`.empty`, `HubError.conflict`→`.validation`,
`isNotFound`→`null`, a 409→`rethrowConflict`) or wraps/rethrows
unconditionally (`HubError.wrap`) — no path silently swallows a failure.
`unit-test-coverage` **passed**: `EcosystemsModuleTests.swift` exercises
every public path this recipe documents (root listing, manageability
gate, topic dispatch, settings save/delete, child-ecosystem recursion,
create-form validation and prefix resolution), and `ecosystems.test.ts`
does the same for the web client's mapper, create/update body shapes, and
`ecosystemIdForSlug`'s ownership-first resolution; `ecosystem-features.test.tsx`
pins `remove`'s 404-as-success and rethrow paths and `useApplyFeatureChange`'s
all-settled removal and failed-key message (the catalog, list and provision
calls and their hooks' cache writes have no direct test). `error-response-handling`
**passed**: `isNotFound`/`isConflict` and `HubError.notFound`/`.conflict`
consistently distinguish "missing" from "already exists" from every other
failure on both platforms, and `ecosystemIdForSlug` explicitly rethrows a
non-404 rather than treating it as license to fall back
(hub-domain-ecosystems-035). `retry-with-backoff` **failed**: no file in
either implementation retries a failed ecosystems/identifiers request —
the underlying `authedJson`'s 401-refresh-and-retry-once is a different,
cross-cutting auth concern (see `auth-client`), not a retry of this
domain's own operations. `offline-behavior` **failed**: neither
implementation defines an offline-cache-first read path or a
queued-write-when-offline behavior; every operation is a live round-trip
that fails outright when the network is unavailable.
`idempotent-operations` **partial**: the feature client is idempotent on
both mutating paths — `remove` treats an already-gone row (404) as success,
and `provision` of an already-active key is a backend no-op — and
`ecosystemsApi.update`'s PUT is
documented as idempotent by the backend's own locked-value diff (sending
an unchanged `slug` is a no-op, per the source's `addressPatchMoves`
comment), but `create` has no idempotency key on either platform — a
client-level retry of a create (were one ever added) could not safely be
distinguished from a genuine duplicate request without one.
`input-sanitization` **partial**: `Slug.pattern`/`FormValidator` (Apple)
validate the slug's character set client-side, and `addressLeaf` is a
pure slice with no validation of its own by design (see Edge Cases); the
server's unique-address constraint and `id`-vs-leaf assertion are the
real authority on both platforms, which this component deliberately
relies on rather than duplicating. `data-minimization` **passed**: every
field this component reads or writes is ecosystem/product metadata, never
end-user personal data. `no-hardcoded-strings` **failed**: every
user-facing string this recipe documents (labels, warnings, validation
messages) is fixed English with no lookup table or locale parameter on
either platform (see Localization) — a plain, honestly-reported gap, not
a hidden one. `fault-tolerance` **partial**: `useApplyFeatureChange`
keeps going past a failed removal and reports it by name rather than
aborting, and `FeatureSubscriptionTier` is an open string so an unknown
tier cannot break parsing; but the feature mutation hooks accept a
nullable `ecosystemId` and send it unguarded (see the open question on
features-mutation-null-id).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-24 | Claude | Add the web feature picker data (`ecosystem-features.ts`): catalog with "Coming soon" entries, provisioned list, batch add, 404-tolerant remove, all-settled apply; correct `ecosystemIdForSlug`'s null-result fallback and the cache-settings note. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe: Apple `EcosystemsModule`/topics/data source/models and the web `ecosystemsApi`/`identifiersApi`/`useWorkspaceDefaultEcosystemId`/Invitations-hooks contract. |
