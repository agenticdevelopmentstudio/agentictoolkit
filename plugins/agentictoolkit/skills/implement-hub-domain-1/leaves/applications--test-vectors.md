<!-- leaf: implement-hub-domain-1/applications--test-vectors · source: hub-domain-applications.md -->

# Hub Domain Applications

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
