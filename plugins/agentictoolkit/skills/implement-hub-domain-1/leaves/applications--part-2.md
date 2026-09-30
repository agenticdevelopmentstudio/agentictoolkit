<!-- leaf: implement-hub-domain-1/applications--part-2 · source: hub-domain-applications.md -->

# Hub Domain Applications — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/applications--part-2#<slug>`):

- `applications-listing` MUST
- `application-lookup` MUST
- `application-creation` MUST
- `application-update` MUST
- `application-deletion` MUST
- `identifier-rename` MUST
- `schema-grants-read` MUST
- `schema-grants-write` MUST
- `token-listing` MUST
- `token-creation` MUST
- `token-revocation` MUST
- `application-identifier-shape` MUST
- `application-identifier-prefix` MUST
- `consumer-kind-decoding` MUST
- `consumer-kind-fallback-values` MUST
- `crud-permissions-wire-order` MUST
- `crud-permissions-parsing-tolerance` MUST
- `crud-permissions-summary-text` MUST
- `crud-permissions-ceiling-check` MUST
- `grant-types-are-domain-only` MUST
- `table-grant-level-is-ui-only` MUST
- `schema-grant-table-keying` MUST
- `application-token-shape` MUST
- `application-token-created-shape` MUST
- `rail-path-resolution` MUST
- `missing-application-returns-empty` MUST
- `errors-wrapped-and-propagated` MUST
- `unknown-section-returns-empty` MUST
- `secret-expiry-on-navigation` MUST
- `applications-list-item-mapping` MUST
- `create-application-fields` MUST
- `create-application-slug-lowercased` MUST
- `create-conflict-messaging` MUST
- `application-level-items` MUST
- `settings-form-fields` MUST
- `settings-save-without-rename` MUST
- `settings-save-with-rename` MUST
- `rename-conflict-messaging` MUST
- `grant-rehoming-write-order` MUST
- `delete-clears-grants-then-deletes` MUST
- `delete-confirmation-text` MUST

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
