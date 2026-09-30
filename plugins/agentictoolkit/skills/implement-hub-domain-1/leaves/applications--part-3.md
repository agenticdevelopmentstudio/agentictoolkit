<!-- leaf: implement-hub-domain-1/applications--part-3 · source: hub-domain-applications.md -->

# Hub Domain Applications — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/applications--part-3#<slug>`):

- `grants-list-item-mapping` MUST
- `add-schema-options-exclude-granted` MUST
- `add-schema-default-permissions` MUST
- `add-schema-requires-selection` MUST
- `grant-level-item-composition` MUST
- `schema-detail-fields` MUST
- `schema-detail-deleted-bucket-notice` MUST
- `schema-save-rewrites-whole-list` MUST
- `schema-remove-grant` MUST
- `table-grant-ceiling-enforcement` MUST
- `table-grant-row-level-rejected` MUST
- `table-grant-empty-removes-entry` MUST
- `table-grant-level-constant` MUST
- `tokens-list-item-mapping` MUST
- `token-creation-mints-and-reveals-secret` MUST
- `token-reveal-while-current` MUST
- `token-secret-expires-on-navigation` MUST
- `token-revoke-clears-secret-and-list` MUST
- `token-revoke-confirmation-text` MUST
- `main-actor-isolation` MUST
- `sendable-data-source-protocols` MUST
- `form-actions-run-off-main-actor` MUST
- `authorization-errors-propagate` MUST

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
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (`ApplicationsTopic.init`) | `any ApplicationsDataSource` | none (required) | Backs `list`/`get`/`create`/`update`/`delete`/`renameIdentifier`/`schemaGrants`/`setSchemaGrants`/`tokens`/`createToken`/`revokeToken`. |
| `buckets` (`ApplicationsTopic.init`) | `any BucketsDataSource` | none (required) | Supplies the ecosystem's bucket list and bucket-table list this topic uses to label and enumerate schema/table grants; owned by the separate Buckets feature. |
| `ConsumerKind` cases | `String` enum | decode fallback `.developer` | The three consumer kinds (`staff`, `developer`, `customer`) a caller can assign to an application. |
| `Slug.pattern` / `Slug.patternMessage` | `String` constants | fixed | Shared identifier rule enforced on both the create form's and the settings form's `slug` field. |
| Default grant permissions (`CrudPermissions.readOnly`) | `CrudPermissions` | `"R"` (read-only) | Starting permission set for a schema grant created by the "Add schema" save action. |

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

