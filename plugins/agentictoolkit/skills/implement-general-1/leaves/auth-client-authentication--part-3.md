<!-- leaf: implement-general-1/auth-client-authentication--part-3 · source: auth-client-authentication.md -->

# Authentication Client — continued (part 3)

**Rules** (cite as `implement-general-1/auth-client-authentication--part-3#<slug>`):

- `access-topic-entry` MUST
- `access-groups-scoped-to-ecosystem` MUST
- `access-groups-sort-order` MUST
- `access-create-requires-bucket` MUST
- `access-create-rejects-duplicate-name-client-side` MUST
- `access-create-conflict-message` MUST
- `access-group-level-composition` MUST
- `access-everyone-name-locked` MUST
- `access-everyone-delete-blocked` MUST
- `access-settings-save-name` MUST
- `access-settings-delete` MUST
- `access-everyone-members-is-notice` MUST
- `access-members-list-item-shape` MUST
- `access-member-type-options` MUST
- `access-member-add-required-fields` MUST
- `access-member-add-conflict-message` MUST
- `access-member-remove` MUST
- `access-grants-list-item-shape` MUST
- `access-grant-target-label` MUST
- `access-grant-target-options-shrink` MUST
- `access-grant-target-required` MUST
- `access-grant-bucket-type-required` MUST
- `access-grant-row-id-required` MUST
- `access-grant-row-id-length-limit` MUST
- `access-grant-permission-required` MUST
- `access-grant-save-never-deletes` MUST
- `access-grant-remove` MUST
- `access-grant-unknown-target-blocked-on-save` MUST
- `access-crud-serialization` MUST
- `access-unknown-path-empty` MUST
- `access-detail-refetches-every-call` MUST
- `error-domain-is-hub-error` MUST
- `main-actor-isolation` MUST
- `models-are-sendable-value-types` MUST
- `form-actions-run-off-main-actor` MUST

- **access-topic-entry**: `AccessListsTopic.entry` MUST have `id: "access"`, `label: "Access"`,
  `systemImage: "lock.shield"`.
- **access-groups-scoped-to-ecosystem**: `child(for:path:rail:)` MUST filter `dataSource.groups()` down
  to groups whose `ecosystemId` equals the given `Ecosystem.id` before building the list level or
  resolving `path[0]` against it.
- **access-groups-sort-order**: `listLevel` MUST sort groups first by their owning bucket's
  `localizedCaseInsensitiveCompare`d name (falling back to the raw `bucketId` when no bucket in
  `bucketList` matches), then by `isEveryone` (the everyone group first within its bucket), then by the
  group's own `localizedCaseInsensitiveCompare`d name.
- **access-create-requires-bucket**: the "New access list" save action MUST throw
  `HubError.validation("Choose a bucket.")` when the `bucketId` select field has no value.
- **access-create-rejects-duplicate-name-client-side**: the save action MUST reject, before calling
  `dataSource.create(bucketID:_:)`, a trimmed `name` that case-insensitively matches an existing group's
  `name` within the same `bucketId`, with
  `An access list named "{name}" already exists in that bucket.`.
- **access-create-conflict-message**: the save action MUST catch `HubError.conflict` from
  `dataSource.create(bucketID:_:)` and rethrow `HubError.validation("An access list named \"{name}\"
  already exists.")`; any other thrown error MUST be passed through `HubError.wrap(_:)`.
- **access-group-level-composition**: `groupLevel(detail:)` MUST return exactly three items — `settings`
  (leads to `.detail`), `members` (leads to `.list`, sublabel `"Applies to everyone"` when
  `group.isEveryone` else `"{N} member(s)"`), `grants` (leads to `.list`, sublabel `"{N} grant(s)"`) —
  and MUST set `emptyMessage: ""` and `createAction: nil`.
- **access-everyone-name-locked**: `settingsDetail(group:bucketName:)` MUST render `name` as a
  non-editable read-only field (plus a read-only `nameHelp` note carrying
  `AccessListsTopic.everyoneNameHelp`) when `group.isEveryone`, and as an editable required text field
  otherwise.
- **access-everyone-delete-blocked**: `settingsDetail` MUST omit the delete action and instead append a
  read-only `deleteNote` field carrying `AccessListsTopic.everyoneDeleteBlocked` when
  `group.isEveryone`.
- **access-settings-save-name**: the settings save action MUST send `AccessGroupUpdate.name` as `nil`
  when `group.isEveryone`, and otherwise as the trimmed `name` field's value.
- **access-settings-delete**: for a non-everyone group, the delete action MUST be titled "Delete access
  list" with confirmation text `Delete access list "{name}"? Its members and grants will be removed.`
  and MUST call `dataSource.delete(id:)`.
- **access-everyone-members-is-notice**: `child(for:path:rail:)` MUST resolve `[group, "members"]` for
  an everyone group to a read-only `FormDetails.notice` carrying
  `AccessListsTopic.everyoneMembersMessage`, never to the editable members level.
- **access-members-list-item-shape**: `membersLevel`'s items MUST use `member.id` as `id`,
  `member.memberId` as `label`, `member.typeTitle` as `sublabel`, and
  `member.type?.systemImage ?? "questionmark.circle"` as `systemImage`.
- **access-member-type-options**: the "Add member" form's `memberType` select field MUST offer exactly
  `AccessMemberType.allCases` in declaration order (`user`, `organization`, `persona`, `application`,
  `token`), each option's value being that case's `rawValue` — including `application`, whose
  `rawValue` is the literal string `"app"`, not `"application"`.
- **access-member-add-required-fields**: the "Add member" save action MUST throw
  `HubError.validation("Choose a type.")` when `memberType` does not decode to an `AccessMemberType`,
  and MUST trim the `memberId` field before constructing `AccessMemberAdd`.
- **access-member-add-conflict-message**: the save action MUST catch `HubError.conflict` and rethrow
  `HubError.validation("That member is already in this access list.")`.
- **access-member-remove**: the member detail's delete action MUST be titled "Remove member" with
  confirmation text `Remove {typeTitle} "{memberId}" from this access list?` and MUST call
  `dataSource.removeMember(groupID:memberRowID:)`.
- **access-grants-list-item-shape**: `grantsLevel`'s items MUST use `AccessListsTopic.targetLabel(_:
  tables:)` as `label` and `grant.permissions.summary` as `sublabel`.
- **access-grant-target-label**: `targetLabel(_:tables:)` MUST return `"Whole bucket"` for `.bucket`,
  the matching `BucketTable.name` (or the bare `targetId` when no table in `tables` matches its `id`)
  for `.bucketType`, `"Row {targetId}"` for `.row`, and the bare `targetId` when `grant.target` is `nil`
  (an unrecognized `targetType`).
- **access-grant-target-options-shrink**: `grantSpec(group:tables:existing:)`'s target select MUST
  offer `"Whole bucket"` only while no entry in `existing` has `target == .bucket`; MUST offer `"Bucket
  type"` only while at least one table in `tables` has no entry in `existing` targeting it as
  `.bucketType`; and MUST always offer `"Row"`.
- **access-grant-target-required**: the "Add grant" save action MUST throw
  `HubError.validation("Choose a target.")` when `target` does not decode to an `AccessTargetType`.
- **access-grant-bucket-type-required**: when `target == .bucketType`, the save action MUST throw
  `HubError.validation("Choose a bucket type.")` when the `bucketType` field is blank.
- **access-grant-row-id-required**: when `target == .row`, the save action MUST trim the `rowId` field
  and throw `HubError.validation("Enter a row id.")` when the trimmed value is blank.
- **access-grant-row-id-length-limit**: when `target == .row`, the save action MUST throw
  `HubError.validation("Row id must be 36 characters or fewer.")` when the trimmed row id's `count`
  (Unicode grapheme-cluster count, not byte length) exceeds 36; a length of exactly 36 MUST be accepted.
- **access-grant-permission-required**: both the "Add grant" save action and the existing-grant "Save"
  action MUST throw `HubError.validation("Choose at least one permission.")` when every CRUD toggle
  (`create`/`read`/`update`/`delete`) is `false`.
- **access-grant-save-never-deletes**: saving an existing grant with every CRUD toggle `false` MUST NOT
  delete the grant (MUST throw `access-grant-permission-required`'s error instead); a grant MUST be
  removable only through its own "Remove grant" delete action.
- **access-grant-remove**: the grant detail's delete action MUST be titled "Remove grant" with
  confirmation text `Remove the grant for {label}?` and MUST call
  `dataSource.removeGrant(groupID:grantID:)`.
- **access-grant-unknown-target-blocked-on-save**: saving an existing grant whose `target` is `nil`
  (an unrecognized `targetType`) MUST throw `HubError.validation("Unknown grant target
  \"{targetType}\".")` rather than attempting an upsert.
- **access-crud-serialization**: `AccessCRUD.crud` MUST serialize as a comma-separated, upper-case
  subset of `"C"`,`"R"`,`"U"`,`"D"` in that fixed order (only the `true` flags present, `""` when none);
  `AccessCRUD.init(crud:)` MUST parse a comma-separated string case-insensitively, trimming whitespace
  around each token.
- **access-unknown-path-empty**: `child(for:path:rail:)` MUST return `.empty` for any group id, second
  path segment, or member/grant row id it cannot match against the currently fetched
  groups/detail/members/grants.
- **access-detail-refetches-every-call**: `child(for:path:rail:)` MUST re-fetch `buckets.list(...)`,
  `dataSource.groups()`, and — whenever `path` is non-empty — `dataSource.detail(id:)` and
  `buckets.tables(...)` on every call; it MUST NOT cache any of the four across calls.

**Shared across all four types**

- **error-domain-is-hub-error**: every one of the four types MUST surface only `HubError` to its
  caller; `AuthenticationModule`, `ApiTokensRail`, and `AccessListsTopic` achieve this by routing every
  data-source call through `HubError.wrap(_:)`, while `StorageTokensRail`'s create path uses the
  three-way catch chain in `storage-tokens-create-error-tiering` instead — that divergence is
  intentional and MUST be preserved, not unified, when this component is ported or refactored.
- **main-actor-isolation**: `AuthenticationModule`, `ApiTokensRail`, `StorageTokensRail`, and
  `AccessListsTopic` are each declared `@MainActor final class`; every stored property
  (`revealedSecrets`, `revealedOnScreen`) and method MUST be read and written only on the main actor —
  none of the four declares any lock, queue, or other synchronization primitive, because none is
  needed under that isolation.
- **models-are-sendable-value-types**: every wire model in `AuthenticationModels.swift` and the
  storage-token types in `EcosystemConfigModels.swift` (`ApiToken`, `ApiTokenCreated`, `ApiTokenCreate`,
  `AccessGroup`, `AccessGroupMember`, `AccessGrant`, `AccessGroupDetail`, `AccessCRUD`,
  `StorageToken`, `StorageTokenCreated`, `StorageTokenCreate`, etc.) MUST be a `Codable, Hashable,
  Sendable` value type, so an instance MAY cross actor-isolation boundaries freely; the four
  `*DataSource` protocols (`ApiTokensDataSource`, `BucketAccessDataSource`, `StorageTokensDataSource`)
  MUST be `AnyObject, Sendable`, so any conforming implementation MUST itself be safe to invoke from the
  main actor while doing its own work off it.
- **form-actions-run-off-main-actor**: because `FormAction.perform`/`FormDeleteAction.perform` are
  plain `@Sendable ... async throws -> Void` closures (not `@MainActor`), every message constant a save
  or delete closure reads (`noScopeSelectedMessage`, `nameTakenMessage`, `createFailedMessage`) MUST be
  declared `nonisolated`, and any mutation those closures make to a rail's `@MainActor`-isolated state
  (e.g., `revealedSecrets`) MUST be hopped back onto the main actor explicitly (each of `ApiTokensRail`
  and `StorageTokensRail` does this with `await MainActor.run { self?.revealedSecrets[...] = ... }`).

**Security**
