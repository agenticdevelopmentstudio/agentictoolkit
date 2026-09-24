---
id: 519d4419-8f80-478d-aa08-912b66bbe5cf
title: Hub Domain Applications
domain: agentictoolkit://recipes/hub-domain-applications
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The client-side contract for the Hub''s Applications feature: ApplicationsDataSource''s
  CRUD/rename/grants/tokens operations, ApplicationsModels'' wire and domain types
  (ConsumerKind, CrudPermissions, SchemaGrant/TableGrant), and ApplicationsTopic''s
  rail navigation, identifier-rename/grant-rehoming sequence, and mint/reveal-once/revoke
  token lifecycle, cited to their Swift sources and tests.'
platforms:
- swift
- macos
- ios
tags:
- hub
- applications
- access-control
- api-tokens
depends-on: []
related:
- agentictoolkit://recipes/auth-client-authentication
references:
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsDataSource.swift
  (apple)
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsModels.swift
  (apple)
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsTopic.swift
  (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/ApplicationsTopicTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# Hub Domain Applications

## Overview

Three Swift files under `packages/apple/AgenticToolkit/Hub/Features/Applications/` form the
client-side contract for the Hub's "Applications" product topic: `ApplicationsDataSource`
(`ApplicationsDataSource.swift`) is the `AnyObject, Sendable` protocol every network call is
delegated to; `ApplicationsModels.swift` holds the `Codable`/`Sendable` wire types (`Application`,
`ApplicationCreate`, `ApplicationUpdate`, `ConsumerKind`, `ApplicationToken`,
`ApplicationTokenCreated`) plus the domain-only, deliberately non-`Codable` grant types
(`CrudPermissions`, `TableGrant`, `SchemaGrant`); and `ApplicationsTopic`
(`ApplicationsTopic.swift`) is the `@MainActor` `EcosystemTopicProvider` that resolves the rail
path into list/detail panes for an application's Settings, Bucket permissions, and Access tokens
sections, using an injected `BucketsDataSource` to label and enumerate the buckets/tables a grant
can target. Every thrown error is normalized to `HubError` before it reaches a caller
(`HubError.wrap`), and every token secret this component ever holds is a transient,
reveal-once-then-drop entry in an in-memory dictionary — the same pattern the sibling
Authentication feature (`agentictoolkit://recipes/auth-client-authentication`) uses for its own
API and storage tokens.

## Behavioral Requirements

**Data source contract (`ApplicationsDataSource`)**

- **applications-listing**: `list(ecosystemID:)` MUST return the applications belonging to the
  given ecosystem, asynchronously, and MUST throw rather than return a partial or empty result on
  failure.
- **application-lookup**: `get(id:)` MUST return the single `Application` matching `id`, or throw
  (a not-found is signaled as an error, not an optional).
- **application-creation**: `create(_:)` MUST create and return a new `Application` from an
  `ApplicationCreate` body.
- **application-update**: `update(id:_:)` MUST apply an `ApplicationUpdate` (each of whose
  `slug`/`displayName`/`consumerKind` fields is independently optional) and return the resulting
  `Application`.
- **application-deletion**: `delete(id:)` MUST remove the application identified by `id`.
- **identifier-rename**: `renameIdentifier(_:to:)` MUST issue `PATCH
  /registry/identifiers/{current}` with body `{rdid: next}` (per the protocol's own doc comment)
  and MUST throw `HubError.conflict` when `next` is already taken by another identifier.
- **schema-grants-read**: `schemaGrants(applicationID:)` MUST return the full current list of
  `SchemaGrant`s for that application.
- **schema-grants-write**: `setSchemaGrants(applicationID:_:)` MUST replace the application's
  entire schema-grant list with the given array in one call (a whole-list write, not a per-grant
  patch).
- **token-listing**: `tokens(applicationID:)` MUST return the application's `ApplicationToken`
  rows (never including a plaintext secret).
- **token-creation**: `createToken(applicationID:name:)` MUST mint a new token and return an
  `ApplicationTokenCreated`, whose `token` field carries the plaintext secret exactly once.
- **token-revocation**: `revokeToken(applicationID:tokenID:)` MUST withdraw the token identified
  by `tokenID`.

**Data shapes**

- **application-identifier-shape**: `Application.id` MUST be a reverse-domain identifier of the
  form `app.<ecosystem>.<leaf>`; renaming the leaf through `renameIdentifier` MUST change this
  value (per the type's own doc comment).
- **application-identifier-prefix**: `Application.identifierPrefix` MUST return everything up to
  and including the id's last `.` (e.g. `"app.acme.shop."` for `"app.acme.shop.web"`), and MUST
  return the empty string when the id contains no `.`.
- **consumer-kind-decoding**: `ConsumerKind.init(from:)` MUST decode the wire's free `string`
  field (documented as `maxLength: 16`, no enum) and MUST narrow any value that is not
  `"staff"`/`"developer"`/`"customer"` to `.developer` rather than failing the decode — per the
  type's own doc comment, this is what keeps one unrecognized row from failing the whole
  `[Application]` array decode and blanking the rail.
- **consumer-kind-fallback-values**: when a `consumerKind` string cannot be parsed into a
  `ConsumerKind` case, the component MUST fall back to one of three different defaults depending
  on the call site: `.developer` when decoding a wire `Application` (`ConsumerKind.init(from:)`),
  `.customer` when the "New application" form's `consumerKind` value is unparsable
  (`ApplicationsTopic.createSpec`'s save action), and the application's own current
  `consumerKind` when the "Settings" form's value is unparsable (`settingsDetail`'s save action).
  Because `Self.kindOptions` is built from `ConsumerKind.allCases`, both form-side fallbacks are
  unreachable through the rendered UI and matter only if a value is missing or tampered with.
- **crud-permissions-wire-order**: `CrudPermissions.wire` MUST serialize to a comma-separated
  subset of `"C"`, `"R"`, `"U"`, `"D"` in that fixed order regardless of the order the flags were
  set in.
- **crud-permissions-parsing-tolerance**: `CrudPermissions.init(wire:)` MUST parse a
  comma-separated wire string case-insensitively, trimming whitespace around each token, and MUST
  treat any unrecognized token as simply absent rather than throwing.
- **crud-permissions-summary-text**: `CrudPermissions.summary` MUST return `"No access"` when
  every flag is `false`, and otherwise the enabled flags' words (`"Create"`, `"Read"`, `"Update"`,
  `"Delete"`) joined with `", "` in that fixed order.
- **crud-permissions-ceiling-check**: `CrudPermissions.isWithin(_:)` MUST return `true` only when
  every flag that is `true` on `self` is also `true` on the given `ceiling`.
- **grant-types-are-domain-only**: `TableGrant` and `SchemaGrant` MUST NOT conform to `Codable`;
  per their own doc comments this is deliberate — the wire shape (`{schemaId, crud, tables:
  [{tableId, crud}]}`) lives in an adapter outside these files, so it is impossible to serialize
  these domain types onto the API by accident.
- **table-grant-level-is-ui-only**: `TableGrant.level` MUST carry no wire counterpart (per its own
  doc comment, `"table"` vs. the not-yet-supported `"row"` is a UI-only concept) and MUST never be
  sent to the server.
- **schema-grant-table-keying**: `SchemaGrant.tables` MUST be keyed by a table's `id` (the wire's
  `tableId`), never by its `sqlTableName`.
- **application-token-shape**: `ApplicationToken` MUST expose `id`, `name`, `prefix`, and an
  optional `createdAt`, and MUST NOT carry a secret field.
- **application-token-created-shape**: `ApplicationTokenCreated` (the `POST …/tokens` response)
  MUST expose the same fields as `ApplicationToken` plus a `token` field holding the plaintext
  secret.

**Navigation (`ApplicationsTopic.child`)**

- **rail-path-resolution**: `child(for:path:rail:)` MUST resolve `path` in order — an application
  id at position 0, then a section id (`"settings"`, `"grants"`, or `"tokens"`) at position 1, then
  any remaining segments handed to that section's own resolver — and MUST return
  `.level(listLevel(...))` when `path` is empty.
- **missing-application-returns-empty**: when `dataSource.get(id:)` throws `HubError.notFound` for
  the application id in `path`, `child(for:)` MUST return `.empty`, not propagate the error.
- **errors-wrapped-and-propagated**: any error other than `HubError.notFound` from `get`, `list`,
  or any other `ApplicationsDataSource`/`BucketsDataSource` call MUST be passed through
  `HubError.wrap(_:)` and rethrown — never swallowed.
- **unknown-section-returns-empty**: a section id other than `"settings"`, `"grants"`, or
  `"tokens"` MUST resolve to `.empty`.
- **secret-expiry-on-navigation**: every call to `child(for:path:rail:)` MUST call
  `expireRevealedSecret(unless:)` first, passing the token id from `path` only when the path is
  presently inside that same token's detail (`RailPath.id(at: 1, in: path) == "tokens"` gives the
  token id at position 2, else `nil`); that call MUST drop the currently revealed secret from
  `revealedSecrets` and clear `revealedOnScreen` whenever the resolved token id differs from
  `revealedOnScreen`, and MUST leave both untouched when it matches (a re-render of the same
  detail).

**Applications list and create**

- **applications-list-item-mapping**: `listLevel(for:)` MUST map each `Application` to an
  `HTDVItem` with `id` = the application's `id`, `label` = `displayName`, `sublabel` = `id`,
  `systemImage` = `consumerKind.systemImage`, and `leadsTo: .list`.
- **create-application-fields**: the "New application" form (`createSpec(for:)`) MUST present, in
  order, a required `displayName` text field, a required `slug` text field validated against
  `Slug.pattern`/`Slug.patternMessage`, and a required `consumerKind` select field offering
  `ConsumerKind.allCases`.
- **create-application-slug-lowercased**: the create save action MUST lowercase the submitted
  `slug` before constructing `ApplicationCreate`, and MUST trim leading/trailing whitespace from
  `displayName`.
- **create-conflict-messaging**: when `dataSource.create(_:)` throws `HubError.conflict`, the save
  action MUST throw `HubError.validation("An application with identifier \"{slug}\" already
  exists.")` instead of the raw conflict; any other error MUST pass through `HubError.wrap(_:)`.

**Application level and settings**

- **application-level-items**: `applicationLevel(for:)` MUST return exactly three items, in
  order: `"settings"` ("Settings", leads to `.detail`), `"grants"` ("Bucket permissions", leads to
  `.list`), and `"tokens"` ("Access tokens", leads to `.list`).
- **settings-form-fields**: the settings detail MUST present `displayName`, `slug`, a read-only
  `identifier`, and `consumerKind`, pre-filled from the current `Application`.
- **settings-save-without-rename**: when the submitted `slug` equals the application's current
  `slug`, the save action MUST call `dataSource.update(id:_:)` with the application's existing
  `id` and MUST NOT call `renameIdentifier`.
- **settings-save-with-rename**: when the submitted `slug` differs from the current `slug`, the
  save action MUST call `renameIdentifier(app.id, to: app.identifierPrefix + slug)` before calling
  `update(id:_:)`, and MUST target the update at the new id.
- **rename-conflict-messaging**: when `renameIdentifier` throws `HubError.conflict`, the save
  action MUST throw `HubError.validation("The identifier \"{next}\" is already in use.")`.
- **grant-rehoming-write-order**: on a successful rename, the save action MUST read the old id's
  schema grants, write them to the new id, and only then clear the old id's grants (write-new,
  then-clear-old) — never the reverse order, and never a single combined write.
- **delete-clears-grants-then-deletes**: the "Delete application" action MUST call
  `setSchemaGrants(applicationID: app.id, [])` before calling `dataSource.delete(id: app.id)`.
- **delete-confirmation-text**: the delete action's confirmation text MUST be exactly `Delete
  application "{displayName}"? This cannot be undone.`.

**Bucket permission grants**

- **grants-list-item-mapping**: `grantsLevel(_:ecosystem:)` MUST map each `SchemaGrant` to an item
  labeled with the matching `Bucket.name`, or `ApplicationsTopic.deletedSchemaLabel`
  (`"(deleted schema)"`) when no bucket with that `schemaId` exists among the ecosystem's buckets,
  with `sublabel` = `CrudPermissions(wire: grant.permissions).summary`.
- **add-schema-options-exclude-granted**: the "Add schema" form MUST offer only buckets whose id
  is not already present among the application's current `SchemaGrant.schemaId`s.
- **add-schema-default-permissions**: a newly added grant MUST start with permissions
  `CrudPermissions.readOnly.wire` (`"R"`) and an empty `tables` map.
- **add-schema-requires-selection**: when no ungranted bucket exists, the "Add schema" save action
  MUST throw `HubError.validation(ApplicationsTopic.noSchemasMessage)` ("No schemas defined yet.
  Create one in the Buckets section first.") without calling `setSchemaGrants`.
- **grant-level-item-composition**: `grantLevel(_:grant:)` MUST list a `"schema"` item ("Schema
  permissions", `dividerAfter: true`, leads to `.detail`) followed by one item per table in that
  schema, each labeled with the table's `name` and sublabeled with that table's grant summary or
  `"No access"` when the table has no `TableGrant` entry.
- **schema-detail-fields**: the schema permissions detail MUST present a read-only `schema` field
  plus four toggle fields (`create`, `read`, `update`, `delete`), pre-filled from
  `CrudPermissions(wire: grant.permissions)`.
- **schema-detail-deleted-bucket-notice**: when the grant's bucket no longer exists, the `schema`
  field's value MUST append ` — This schema no longer exists. Remove the grant, or recreate the
  bucket.` to the deleted-schema label.
- **schema-save-rewrites-whole-list**: saving the schema detail MUST recompute `permissions` from
  the four toggles, then rewrite the application's entire grants list (remove the prior entry for
  that `schemaId`, append the replacement, call `setSchemaGrants` with the full array) — never a
  partial or per-field update.
- **schema-remove-grant**: the schema detail's "Remove grant" action MUST drop that schema's grant
  entirely (the same whole-list rewrite with no replacement) with confirmation text `Remove the
  "{label}" grant? This application will lose access to its tables.`.
- **table-grant-ceiling-enforcement**: saving a table's permissions MUST throw
  `HubError.validation("\"{table.name}\" can't exceed the schema's permissions.")` when the
  submitted `CrudPermissions` is not `isWithin` the schema grant's own permissions.
- **table-grant-row-level-rejected**: selecting `"row"` as the permission `level` MUST cause the
  save action to throw `HubError.validation(ApplicationsTopic.rowLevelMessage)` ("Per-row
  permissions are coming soon. Choose \"Table\".") without persisting anything.
- **table-grant-empty-removes-entry**: when the submitted permissions are empty
  (`CrudPermissions.isEmpty`), saving MUST remove that table's entry from `grant.tables` rather
  than storing an empty-permission `TableGrant`.
- **table-grant-level-constant**: every `TableGrant` this component persists MUST have
  `level == "table"` — `"row"` is rejected before it can be saved (`table-grant-row-level-rejected`)
  and there is no other path that writes a `TableGrant`.
- **grants-write-concurrency**: NEEDS REVIEW: Not implemented in source. `rewriteGrant` and the "Add schema" save action both read the application's full `[SchemaGrant]` list, mutate an in-memory copy, and write the whole array back with no version token, ETag, or compare-and-swap; two overlapping writers (two devices, tabs, or concurrent form submissions against the same application) can each read the same snapshot and the second `setSchemaGrants` call silently discards the first writer's change. Settling this needs either a server-side optimistic-lock primitive this protocol does not expose, or evidence that the backend itself serializes `setSchemaGrants` calls per application (neither is visible from these three files).

**Access tokens**

- **tokens-list-item-mapping**: the tokens level MUST map each `ApplicationToken` to an item with
  `label` = `name` and `sublabel` = `"{prefix}… · {HubDates.display(createdAt)}"`.
- **token-creation-mints-and-reveals-secret**: the "New token" save action MUST call
  `createToken(applicationID:name:)` and, on success, MUST store the returned
  `ApplicationTokenCreated.token` into `revealedSecrets[created.id]`.
- **token-reveal-while-current**: the token detail MUST include a read-only `token` field (the
  plaintext secret) and a read-only `notice` field (`ApplicationsTopic.revealMessage`, "Copy this
  token now — you won't be able to see it again.") only while `revealedSecrets[token.id]` holds a
  value, and MUST set `revealedOnScreen = token.id` whenever it does.
- **token-secret-expires-on-navigation**: resolving any path other than that same token's detail
  MUST remove its entry from `revealedSecrets` (per `secret-expiry-on-navigation`), so navigating
  to a sibling token or anywhere else and back MUST NOT re-show the plaintext secret.
- **token-revoke-clears-secret-and-list**: the "Revoke token" action MUST call
  `revokeToken(applicationID:tokenID:)` and, on success, MUST remove that token's entry from
  `revealedSecrets`.
- **token-revoke-confirmation-text**: the revoke action's confirmation text MUST be exactly
  `Revoke token "{name}"? Applications using it will lose access.`.

**Concurrency and isolation**

- **main-actor-isolation**: `ApplicationsTopic` MUST be declared `@MainActor final class`; its
  stored state (`revealedSecrets`, `revealedOnScreen`) and every method MUST run only on the main
  actor, so no lock, queue, or other synchronization primitive is needed to serialize reads and
  writes of that state within a process.
- **sendable-data-source-protocols**: `ApplicationsDataSource` and `BucketsDataSource` MUST be
  declared `AnyObject, Sendable`, so a conforming instance can be safely injected into and called
  from the `@MainActor`-isolated `ApplicationsTopic` while performing its own network work off the
  main actor.
- **form-actions-run-off-main-actor**: because `FormAction.perform` is a plain `@Sendable async
  throws -> Void` closure, not `@MainActor`-isolated, a save action that mutates
  `revealedSecrets` (the "New token" create action) MUST hop that mutation onto the main actor
  explicitly via `await MainActor.run { ... }` — it cannot write the `@MainActor`-isolated property
  directly from the closure's own execution context.
- **authorization-errors-propagate**: `HubError.unauthorized`/`.forbidden` thrown by
  `ApplicationsDataSource` or `BucketsDataSource` MUST propagate unchanged to the caller through
  `HubError.wrap(_:)` rather than being caught, retried, or downgraded locally.

## Appearance

Not applicable — this is the client-side Applications data-source contract and rail-navigation
logic (`ApplicationsDataSource` + `ApplicationsModels` + `ApplicationsTopic`), not a visual
component.

## States

Not applicable — this is the client-side Applications data-source contract and rail-navigation
logic, not a visual component; the `HTDVLevel`/`HTDVDetail`/`FormSpec` values it returns are
consumed by a separate presentation layer that owns any loading/error/empty visual state.

## Accessibility

Not applicable — this is the client-side Applications data-source contract and rail-navigation
logic, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-apps-001 | applications-listing, applications-list-item-mapping | `rail.level([])` against a fake data source with two applications | Items in insertion order with `label`/`sublabel`/`systemImage` matching `displayName`/`id`/`consumerKind.systemImage`; `emptyMessage == "No applications yet."` |
| hub-apps-002 | consumer-kind-decoding | Decode `[Application]` JSON where one row's `consumerKind` is `"service"` (unrecognized) and a sibling's is `"customer"` | Both rows decode; the unrecognized row's `consumerKind == .developer`, the sibling's stays `.customer` |
| hub-apps-003 | crud-permissions-wire-order, crud-permissions-parsing-tolerance | `CrudPermissions(wire: "R, D,C").wire` | `"C,R,D"` |
| hub-apps-004 | crud-permissions-summary-text | `CrudPermissions(wire: "").summary` and `CrudPermissions(wire: "C,R,U,D").summary` | `"No access"` and `"Create, Read, Update, Delete"` |
| hub-apps-005 | application-identifier-prefix | `Application.fixture().identifierPrefix` where `id == "app.acme.shop.web"` | `"app.acme.shop."` |
| hub-apps-006 | create-application-slug-lowercased, create-conflict-messaging | `createSpec(for:)`'s save action invoked with `slug: "mobile"`, then again after `apps.createFailure = .conflict("dup")` | First call: `apps.creates` contains an `ApplicationCreate` with the given fields; second call: save fails and `saveError == "An application with identifier \"mobile\" already exists."` |
| hub-apps-007 | application-level-items | `rail.level(["app.acme.shop.web"])` | `items.map(\.id) == ["settings", "grants", "tokens"]`; `rail.child(["nope"])` (unknown application id) returns `.empty` |
| hub-apps-008 | settings-save-without-rename | Settings form saved with `slug` unchanged | `apps.renames.isEmpty == true`; `apps.updates` contains one update targeting the existing `id` |
| hub-apps-009 | settings-save-with-rename, grant-rehoming-write-order | Settings form saved with `slug` changed from `"web"` to `"store"`, application already having one schema grant | `apps.renames == [("app.acme.shop.web", "app.acme.shop.store")]`; `apps.grantWrites` is `[("app.acme.shop.store", [<the grant>]), ("app.acme.shop.web", [])]` in that order |
| hub-apps-010 | rename-conflict-messaging | `renameIdentifier` throws `HubError.conflict("dup")` for a submitted rename | Save fails with `saveError == "The identifier \"app.acme.shop.web\" is already in use."` |
| hub-apps-011 | grant-rehoming-write-order | Rename succeeds but the SECOND grant write (clearing the old id) fails (`grantWriteFailureIndex: 1`) | Save reports failure, but `apps.grants["app.acme.shop.store"]` and `apps.grants["app.acme.shop.web"]` both still hold the original grant — no data loss |
| hub-apps-012 | delete-clears-grants-then-deletes, delete-confirmation-text | Delete action invoked for `"Web Storefront"` | `confirmationText == "Delete application \"Web Storefront\"? This cannot be undone."`; `apps.grantWrites` records a `[]` write for the app before `apps.deletes` records the id |
| hub-apps-013 | grants-list-item-mapping | `grantsLevel` with one grant for an existing bucket and one for `schemaId: "b-gone"` (no matching bucket) | Items' labels are the bucket's name and `"(deleted schema)"` respectively |
| hub-apps-014 | add-schema-options-exclude-granted, add-schema-default-permissions | `addSchemaSpec` with one bucket already granted and one ungranted, then saved | The select field offers only the ungranted bucket; after save, the new `SchemaGrant.permissions == "R"` and `tables == [:]` |
| hub-apps-015 | add-schema-requires-selection | `addSchemaSpec` invoked with `ungranted: []`, then saved | Throws `HubError.validation` with message `"No schemas defined yet. Create one in the Buckets section first."` |
| hub-apps-016 | grant-level-item-composition | `grantLevel` for a grant with two tables, one having a `TableGrant` and one not | Items are `["schema", <table with grant's sqlTableName>, <table without>]`; the table without a grant sublabels `"No access"` |
| hub-apps-017 | schema-save-rewrites-whole-list, schema-remove-grant | Schema detail saved with `delete` toggled on, then its "Remove grant" action invoked | After save, the grant's `permissions` includes `"D"`; after remove, `apps.grants[appID] == []` |
| hub-apps-018 | table-grant-ceiling-enforcement | Table detail saved with `update: true` while the schema grant's permissions are `"C,R"` | Throws `HubError.validation("\"{table.name}\" can't exceed the schema's permissions.")`; `apps.grants` unchanged |
| hub-apps-019 | table-grant-row-level-rejected | Table detail saved with `level: "row"` | Throws `HubError.validation(ApplicationsTopic.rowLevelMessage)`; `apps.grants` unchanged |
| hub-apps-020 | table-grant-empty-removes-entry | Table detail saved with every CRUD toggle `false` after previously having `read: true` | `grant.tables` no longer contains an entry for that table id |
| hub-apps-021 | tokens-list-item-mapping, token-creation-mints-and-reveals-secret | "New token" saved with `name: "CI deploy"` | `apps.tokenCreates == [(applicationID, "CI deploy")]`; `topic.revealedSecrets[created.id] == created.token` |
| hub-apps-022 | token-reveal-while-current, token-secret-expires-on-navigation | After creating a token, resolve that token's detail, then a sibling token's detail, then the original token's detail again | First resolution shows `token`/`notice` fields; after visiting the sibling, `revealedSecrets[originalID] == nil`; the return visit's field list omits `token`/`notice` |
| hub-apps-023 | token-revoke-clears-secret-and-list, token-revoke-confirmation-text | Revoke action invoked for a token whose secret is not currently revealed | `confirmationText == "Revoke token \"{name}\"? Applications using it will lose access."`; `apps.tokenRevokes` records the call |
| hub-apps-024 | errors-wrapped-and-propagated | `apps.failure = .unauthorized`; `rail.child([])` invoked | Throws `HubError.unauthorized` unchanged (not swallowed, not downgraded) |
| hub-apps-025 | missing-application-returns-empty | `dataSource.get(id:)` throws `HubError.notFound` for the requested application id | `child(for:)` returns `.empty`, no error propagates |

## Edge Cases

- **Empty applications list**: an empty `[Application]` result MUST render `listLevel`'s
  `emptyMessage` ("No applications yet.") rather than an error (MUST).
- **No schemas to grant**: when the ecosystem has no ungranted buckets, "Add schema" MUST fail with
  `ApplicationsTopic.noSchemasMessage` rather than presenting an empty, unusable picker (MUST).
- **Deleted bucket still referenced by a grant**: a `SchemaGrant` whose `schemaId` no longer
  matches any bucket MUST still list and remain editable/removable, labeled
  `ApplicationsTopic.deletedSchemaLabel` (MUST).
- **Boundary: table permissions exactly at the schema ceiling**: a table's submitted permissions
  equal to the schema grant's own permissions MUST be accepted (`isWithin` is inclusive of
  equality) (MUST).
- **Boundary: table permissions exceeding the ceiling by one flag**: MUST be rejected with the
  `table-grant-ceiling-enforcement` message even when only one extra flag is set (MUST).
- **Malformed/garbage CRUD wire string**: `CrudPermissions(wire:)` MUST NOT throw on an
  unrecognized token (e.g. `"x,y,z"`); it parses to a fully-`false`, `isEmpty == true` value,
  because parsing is a case-insensitive substring match against `{"C","R","U","D"}` with no
  validation that every token is recognized (MUST).
- **Identifier rename racing a settings save's other field changes**: `settingsDetail`'s save
  action performs the rename, the grant re-home, and the field update as three sequential awaited
  calls with no rollback of an earlier step if a later one fails — a failed `update(id:_:)` call
  after a successful rename and grant re-home leaves the application renamed and re-homed but with
  its display name/consumer kind unchanged; the source's own comment on the grant-write ordering
  acknowledges there is "no compensating write" for the grant step specifically, and the same is
  true, undocumented, for the trailing `update` call (MUST NOT roll back — matches source; NEEDS
  REVIEW below covers the concurrent-writer variant, this line covers the single-writer partial-
  failure sequence).
- **Concurrent schema-grant writers**: see the open question on grants-write-concurrency — two
  overlapping `setSchemaGrants` calls for the same application MUST NOT be assumed to compose; the
  last writer's full-array write wins and silently discards the other's change (SHOULD be
  addressed before this component is relied on for multi-writer scenarios; currently undefined).
- **Cancellation**: every `ApplicationsDataSource`/`BucketsDataSource` call is a plain `try await`
  with no explicit cancellation handling in these files; Swift's structured concurrency propagates
  a surrounding task's cancellation as a thrown `CancellationError` through the same `try await`
  path that any other error takes, so it is passed through `HubError.wrap(_:)` like any other
  failure — no code in `ApplicationsTopic` distinguishes cancellation from a network failure
  (MUST — this is what the language guarantees with no extra code, not a gap).
- **Offline or unreachable backend**: `HubError.offline`/`.transport(...)` thrown by the injected
  data source MUST propagate unchanged through `HubError.wrap(_:)`; none of these three files
  retries, queues, or caches a request to paper over the failure — a failed call simply throws and
  the caller decides whether to retry (MUST).
- **Empty/blank required text fields**: `displayName` and the "New token" `name` field are marked
  `isRequired: true` on their `FormTextField`, so blank submission is rejected by the shared form
  validator (documented in the `htdv-engine` recipe) before `ApplicationsTopic`'s own save closures
  ever run; slug format (not blankness) is the one constraint `ApplicationsTopic` itself enforces
  via `Slug.pattern` (MUST — enforcement is delegated, not absent).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (`ApplicationsTopic.init`) | `any ApplicationsDataSource` | none (required) | Backs `list`/`get`/`create`/`update`/`delete`/`renameIdentifier`/`schemaGrants`/`setSchemaGrants`/`tokens`/`createToken`/`revokeToken`. |
| `buckets` (`ApplicationsTopic.init`) | `any BucketsDataSource` | none (required) | Supplies the ecosystem's bucket list and bucket-table list this topic uses to label and enumerate schema/table grants; owned by the separate Buckets feature. |
| `ConsumerKind` cases | `String` enum | decode fallback `.developer` | The three consumer kinds (`staff`, `developer`, `customer`) a caller can assign to an application. |
| `Slug.pattern` / `Slug.patternMessage` | `String` constants | fixed | Shared identifier rule enforced on both the create form's and the settings form's `slug` field. |
| Default grant permissions (`CrudPermissions.readOnly`) | `CrudPermissions` | `"R"` (read-only) | Starting permission set for a schema grant created by the "Add schema" save action. |

## Deep Linking

Not applicable: none of these three files registers a URL scheme, universal link, or
`NSUserActivity`; navigation is entirely through `HTDVItem`/`HTDVChild` path arrays supplied by the
presentation layer that hosts this topic.

## Localization

The source contains no localization mechanism (no `String(localized:)`, no `.strings`/`.xcstrings`
catalog, no `NSLocalizedString`) — every user-facing string below is a hardcoded English literal,
stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `No applications yet.` | `listLevel`'s `emptyMessage` |
| — | `An application with identifier "{slug}" already exists.` | `createSpec` conflict message |
| — | `The identifier "{next}" is already in use.` | Settings save rename-conflict message |
| — | `Delete application "{displayName}"? This cannot be undone.` | Settings delete confirmation |
| — | `No schemas defined yet. Create one in the Buckets section first.` | `ApplicationsTopic.noSchemasMessage` |
| — | `Remove the "{label}" grant? This application will lose access to its tables.` | Schema detail remove confirmation |
| — | `Per-row permissions are coming soon. Choose "Table".` | `ApplicationsTopic.rowLevelMessage` |
| — | `"{table.name}" can't exceed the schema's permissions.` | Table detail ceiling-violation message |
| — | `Copy this token now — you won't be able to see it again.` | `ApplicationsTopic.revealMessage` |
| — | `Revoke token "{name}"? Applications using it will lose access.` | Token revoke confirmation |

(This is a representative sample of the roughly two dozen literals across the three files, not the
full set — every one follows the same pattern: a plain `String` with no key, no catalog entry, and
no pluralization rule beyond ad hoc string interpolation.)

## Accessibility Options

Not applicable: this is a data-source contract and rail-navigation controller with no UI of its
own, so it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: none of these three files reads a feature-flag key or contains conditional
feature-gating logic.

## Analytics

Not applicable: the source contains no analytics/event-emission call.

## Privacy

- **Data collected**: a plaintext bearer secret (`ApplicationTokenCreated.token`) is returned
  exactly once, in the response to a successful `createToken(applicationID:name:)` call.
- **Storage**: `ApplicationsTopic` never persists the secret; `revealedSecrets` is an in-memory
  `[String: String]` on the `@MainActor`-isolated topic instance, with no file, `UserDefaults`, or
  Keychain write anywhere in these three files.
- **Transmission**: this component never transmits the secret itself — it receives it once from
  `createToken`'s response and places it into a read-only form field for on-screen display; actual
  network transmission is the injected `ApplicationsDataSource`'s concern, out of scope of these
  files.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (`token-secret-expires-on-navigation`), which drops the secret from `revealedSecrets` the moment
  navigation moves away from that token's detail, and the `ApplicationsTopic` instance's own
  lifetime (the dictionary holds nothing once the instance is deallocated).
- **Disclosure safeguard**: `ApplicationTokenCreated` — the one type that carries a raw plaintext
  secret in its `token` field — declares no `CustomStringConvertible`/`CustomDebugStringConvertible`
  override, so its synthesized default description includes the secret in full.
  `ApplicationsTopic.swift` never logs or prints a `created` value; it stores only its `token` into
  `revealedSecrets`. A port MUST NOT log this value.

## Logging

Not applicable: the source contains no `os_log`, `Logger`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not applicable to these files directly — `ApplicationsTopic` returns
  `HTDVLevel`/`HTDVDetail`/`FormSpec` values consumed by the shared `FormViewController`/HTDV
  presentation layer; a SwiftUI-based presenter would consume the same values unchanged, since
  `ApplicationsTopic.swift` imports no SwiftUI and performs no rendering itself.
- **AppKit / UIKit**: this is the source. `ApplicationsDataSource.swift`, `ApplicationsModels.swift`,
  and `ApplicationsTopic.swift` live in the `Hub` module shared between the
  `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS` targets (both declared in `project.yml`,
  one source set). None of the three files imports `AppKit` or `UIKit` directly — each is plain
  `Foundation` (`ApplicationsTopic.swift` also imports `AgenticToolkitHTDV`), with the
  platform-specific `NSViewController`/`UIViewController` split handled entirely inside
  `FormViewController`, one layer below where these types operate.
- **Compose**: a Kotlin port would model `Application`/`ApplicationCreate`/`ApplicationUpdate`/
  `ApplicationToken`/`ApplicationTokenCreated` as immutable `data class`es, `ConsumerKind` as a
  Kotlin `enum class` with a custom deserializer mirroring the `.developer` fallback,
  `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain (non-`@Serializable`) domain classes kept
  out of the wire-decoding path on purpose, and `ApplicationsTopic` as a class exposing a
  `suspend fun child(...)` returning a sealed `HtdvChild`; `revealedSecrets` becomes a
  `MutableMap<String, String>` confined to a single `Dispatchers.Main`-bound coroutine scope,
  mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  runtime narrowing function for `ConsumerKind` (mirroring the `.developer` fallback instead of
  `zod`'s default throw-on-mismatch behavior), plain objects (not classes) for
  `CrudPermissions`/`TableGrant`/`SchemaGrant` kept out of any `JSON.stringify` path that reaches
  the network, and `async` functions returning `Promise<HtdvChild>` for `child(...)`; the
  reveal-once mechanic needs an explicit teardown (a router's route-leave hook keyed by the
  outgoing path's token id) to reproduce `expireRevealedSecret(unless:)`'s "same detail re-renders,
  anything else expires" rule — JavaScript's single-threaded event loop already gives the map
  mutation itself the safety `@MainActor` provides in Swift, so no extra confinement primitive is
  needed for that part.
- **WinUI 3**: a .NET port would model `Application`, `ApplicationCreate`, `ApplicationUpdate`,
  `ApplicationToken`, and `ApplicationTokenCreated` as `record`s (free structural equality,
  mirroring the Swift `Hashable` conformances), `ConsumerKind` as an `enum` with a custom
  `JsonConverter` that narrows an unrecognized `System.Text.Json` string to `Developer` instead of
  throwing, and `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain classes with no
  `[JsonPropertyName]`/serialization attributes at all — kept deliberately unreachable from
  `System.Text.Json.JsonSerializer` the same way the Swift types are kept off `Codable`.
  `IApplicationsDataSource` would expose `Task<Application[]> ListAsync(string ecosystemId)`,
  `Task<ApplicationTokenCreated> CreateTokenAsync(string applicationId, string name)`, etc., backed
  by `HttpClient` + `System.Text.Json`. `ApplicationsTopic`'s equivalent would be a view-model class
  with `async Task<HtdvChild> ChildAsync(...)`; `revealedSecrets` becomes a
  `Dictionary<string, string>` field on a view model instantiated per-window/per-`ContentDialog`,
  with the one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view
  model's `Dispose`) rather than a `@MainActor`-checked property, and UI-bound lists
  (`ObservableCollection<T>`) rebuilt wholesale on every re-fetch rather than incrementally patched,
  mirroring the whole-list-rewrite pattern in `schema-save-rewrites-whole-list`.

## Design Decisions

**Decision**: `settingsDetail`'s save action re-homes an application's schema grants by writing
them to the new identifier BEFORE clearing them from the old one, rather than clearing first or
writing both in one call.
**Rationale**: per the source's own comment, there is no compensating write if the second call
fails; ordering the writes this way means a transient failure on the second (clearing) call merely
leaves a harmless duplicate of the grants under the now-stale old id, whereas the reverse order
would let a transient failure on the second (writing) call lose the grants outright.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in `revealedSecrets` only until navigation
departs from the detail screen currently showing it, enforced by calling
`expireRevealedSecret(unless:)` at the top of every `child(...)` call rather than on a timer or a
view-disappear callback.
**Rationale**: per the source's own comment, retaining the secret for the whole session "made the
notice a lie" — `ApplicationsTopic.revealMessage` promises the secret disappears once the reader
has navigated away. Tying the check to the navigation path itself, rather than a lifecycle event a
presentation layer would have to remember to call, means the guarantee holds regardless of which
presentation layer drives it.
**Approved**: pending

**Decision**: `CrudPermissions`, `TableGrant`, and `SchemaGrant` are kept out of `Codable`
entirely, with the wire shape's translation left to an adapter outside these three files.
**Rationale**: per their own doc comments, this makes it impossible to serialize these domain
types onto the API by accident — a caller reaching for `JSONEncoder` on a `SchemaGrant` fails to
compile rather than silently producing the wrong wire shape (`{schemaId, crud, tables:
[{tableId, crud}]}` is not what the struct's stored properties would naively encode to).
**Approved**: pending

**Decision**: a table's permissions are rejected outright (not clamped or silently ignored) when
they exceed the schema grant's own ceiling, and selecting `"row"` as the permission level is
rejected outright rather than silently treated as `"table"`.
**Rationale**: both are explicit `HubError.validation` throws with user-facing messages
(`table-grant-ceiling-enforcement`, `table-grant-row-level-rejected`) rather than a quiet
downgrade, so the caller always knows why a save did not take effect instead of discovering a
narrower grant than requested only by inspecting it afterward.
**Approved**: pending

**Decision**: schema and table grant edits are persisted by rewriting the application's entire
`[SchemaGrant]` array on every save (`rewriteGrant`), rather than a per-field or per-grant PATCH.
**Rationale**: this keeps `ApplicationsTopic`'s write path uniform — one shape of call
(`setSchemaGrants(applicationID:_:)`) handles add, edit, and remove for both schema- and
table-level grants — at the cost of the concurrency exposure covered by the open question on
grants-write-concurrency; the source does not indicate whether this tradeoff was made knowingly or
because the backend has historically been treated as single-writer-per-application.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` passes: `ApplicationsDataSource` isolates every network call behind a
protocol `ApplicationsTopic` depends on but never implements, and the wire/domain model split
(`ApplicationsModels.swift`'s `Codable` types vs. the non-`Codable` `CrudPermissions`/
`TableGrant`/`SchemaGrant`) keeps the API's exact shape out of the domain layer. `unit-test-coverage`
passes: `ApplicationsTopicTests.swift` exercises every operation with a fake data source, including
the rename/re-home sequence, the reveal-once/expiry mechanic, and multiple failure paths.
`explicit-error-handling` passes: every throwing path in `ApplicationsTopic` routes through
`HubError.wrap(_:)` or a specific `catch HubError.conflict`/`.notFound` mapping — nothing is
silently discarded. `secure-storage` passes: no plaintext token secret is ever written to disk,
`UserDefaults`, or the Keychain — `revealedSecrets` is transient, in-memory, and actively
self-expiring. `no-hardcoded-strings` fails outright — see Localization; there is no localization
mechanism anywhere in these three files. `error-recovery` fails: none of the three files retries,
backs off, or queues a failed call — every `ApplicationsDataSource`/`BucketsDataSource` invocation
is a single `try await` that throws straight through to the caller on any failure, transient or
not. `data-integrity` is `partial`: individual writes are internally consistent (each
`setSchemaGrants` call replaces the array atomically from the caller's point of view, and
`table-grant-ceiling-enforcement` validates cross-field consistency before a save), but see the
open question on grants-write-concurrency — the whole-list read-modify-write pattern has no
protection against two overlapping writers silently discarding one another's changes.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
