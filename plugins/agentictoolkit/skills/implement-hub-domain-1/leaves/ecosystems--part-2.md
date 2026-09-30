<!-- leaf: implement-hub-domain-1/ecosystems--part-2 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/ecosystems--part-2#<slug>`):

- `ecosystem-model-shape` MUST
- `ecosystem-decode-default-fallback` MUST
- `ecosystem-identifier-prefix` MUST
- `ecosystem-is-manageable` MUST
- `ecosystem-create-input-defaults` MUST
- `ecosystem-update-input-shape` MUST
- `ecosystems-data-source-contract` MUST
- `ecosystems-list-includes-defaults` MUST
- `root-level-hides-defaults` MUST
- `root-level-shape` MUST
- `root-level-errors-wrap` MUST
- `ecosystem-item-shape` MUST
- `child-by-id-not-found-is-empty` MUST
- `child-manageability-gate-first` MUST
- `not-manageable-copy` MUST
- `topics-level-shape` MUST
- `topic-dispatch-by-entry-id` MUST
- `topic-entry-to-item` MUST
- `topic-group-level-shape` MUST
- `notice-topic-detail-shape` MUST
- `create-form-fields` MUST
- `create-form-slug-lowercased` MUST
- `create-form-slug-max-length` MUST
- `create-form-prefix-resolution` MUST
- `create-form-identifier-derivation` MUST
- `create-form-duplicate-probe` MUST
- `create-form-conflict-mapping` MUST
- `settings-form-fields` MUST
- `settings-values-region-hardcoded` MUST
- `settings-save-identifier-derivation` MUST
- `settings-save-slug-lowercased` MUST
- `settings-save-slug-validation` MUST
- `settings-save-excludes-region` MUST
- `settings-save-conflict-mapping` MUST
- `settings-delete-action` MUST

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

