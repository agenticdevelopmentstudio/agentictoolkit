<!-- leaf: implement-general-1/auth-client-authentication--test-vectors · source: auth-client-authentication.md -->

# Authentication Client

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-001 | root-tokens-level, root-path-routing | `AuthenticationModule(apiTokens:storageTokens:).child(for: [])` | `.level` titled "Tokens" with items `api`, `storage`, `about` in that order |
| auth-client-002 | root-storage-uses-personal-scope | `child(for: [HTDVItem(id: "storage")])` against a fake `StorageTokensDataSource` recording calls | `list(ecosystemID:)` observed with `ecosystemID == nil` |
| auth-client-003 | root-unknown-routes-empty | `child(for: [HTDVItem(id: "bogus")])` | `.empty` |
| auth-client-004 | api-tokens-empty-scope-rejected | `createSpec(scopes: ["read", "write"])`'s save action invoked with every `scope:*` toggle `false` and `readOnly: true` | throws `HubError.validation` with `ApiTokensRail.noScopeSelectedMessage`; `dataSource.create` never called |
| auth-client-005 | api-tokens-scope-derivation | Same save action with `scope:read = true`, `readOnly = true` | `ApiTokensRail.scope(from:prefixes:)` returns `["read:read"]` |
| auth-client-006 | api-tokens-catalogue-unavailable-disables-create | `dataSource.scopes()` throws; `createSpec(scopes: nil)` | Returned `FormSpec` has one read-only `notice` field and `FormActions()` with `save == nil` |
| auth-client-007 | api-tokens-reveal-on-create, api-tokens-detail-field-order | Create succeeds with `created.token == "tmp_abc"`, then `detail(for: created-as-ApiToken)` is rendered | Detail includes `token = "tmp_abc"` and `notice = ApplicationsTopic.revealMessage` |
| auth-client-008 | api-tokens-reveal-once | After 007, `child(path: [HTDVItem(id: "other-token-id")])` is called | `revealedSecrets["created-id"]` is removed; a later `detail(for:)` for the created token shows no `token`/`notice` field |
| auth-client-009 | api-tokens-reveal-once | After 007, `child(path: [HTDVItem(id: "created-id")])` is called again (same token) | `revealedSecrets["created-id"]` is unchanged; the secret is still shown |
| auth-client-010 | api-tokens-revoke | Delete action invoked for a token whose secret is currently revealed | `dataSource.revoke(id:)` called; `revealedSecrets[token.id] == nil` afterward |
| auth-client-011 | storage-tokens-name-pattern | `createSpec(ecosystemID: nil)`'s `name` field validated against `Slug.pattern` with input `"My Token!"` | Field rejected with `Slug.patternMessage` |
| auth-client-012 | storage-tokens-create-conflict-message | `dataSource.create(ecosystemID:_:)` throws `HubError.conflict("...")` | Save action throws `HubError.validation(StorageTokensRail.nameTakenMessage)` |
| auth-client-013 | storage-tokens-create-error-tiering | `dataSource.create(ecosystemID:_:)` throws a plain `NSError` (not `HubError`) | Save action throws `HubError.unexpected(StorageTokensRail.createFailedMessage)` |
| auth-client-014 | storage-tokens-list-sorted-by-slug | Tokens with slugs `["zeta", "alpha"]` and names that would sort oppositely under localized comparison | `level(tokens:...)`'s items appear in raw-`<` slug order: `alpha`, `zeta` |
| auth-client-015 | storage-tokens-about-varies-by-scope | `StorageTokensRail.aboutText(ecosystemID: nil)` vs. `aboutText(ecosystemID: "eco-1")` | `aboutWithoutEcosystem` vs. `aboutWithEcosystem` respectively |
| auth-client-016 | storage-tokens-create-body-shape | Create save action invoked with `ecosystemID: "eco-1"` and `description: "  "` (whitespace only) | `StorageTokenCreate.description == nil`; `StorageTokenCreate.ecosystemId == nil`; `dataSource.create(ecosystemID: "eco-1", _:)` still called with that ecosystem id as the separate argument |
| auth-client-017 | access-groups-scoped-to-ecosystem | `dataSource.groups()` returns groups for two ecosystems; `child(for: ecosystem-A, path: [], rail:)` | `listLevel`'s items include only ecosystem A's groups |
| auth-client-018 | access-groups-sort-order | Two groups in the same bucket, one `kind: "everyone"` and one `kind: "custom"`, both alphabetically after other-bucket groups | Everyone group's row precedes the custom group's row within that bucket |
| auth-client-019 | access-create-rejects-duplicate-name-client-side | Save action invoked with `name: "Editors"` while `existing` already contains a group named `"editors"` (different case) in the same `bucketId` | Throws `HubError.validation` with the "already exists in that bucket" message; `dataSource.create` never called |
| auth-client-020 | access-everyone-name-locked, access-everyone-delete-blocked | `settingsDetail(group: <isEveryone: true>, bucketName:)` | `name` field is `.readOnly`; no delete action present; `deleteNote` field carries `everyoneDeleteBlocked` |
| auth-client-021 | access-everyone-members-is-notice | `child(for:path: [group, "members"], rail:)` where `group.isEveryone == true` | `.detail` is a `FormDetails.notice` with `everyoneMembersMessage`, no save/delete actions |
| auth-client-022 | access-member-type-options | `memberSpec(groupID:)`'s `memberType` select options | Values in order: `"user"`, `"organization"`, `"persona"`, `"app"`, `"token"` |
| auth-client-023 | access-member-add-conflict-message | `dataSource.addMember(groupID:_:)` throws `HubError.conflict("...")` | Save action throws `HubError.validation("That member is already in this access list.")` |
| auth-client-024 | access-grant-target-options-shrink | `existing` already contains a `.bucket` grant and a `.bucketType` grant for every table in `tables` | `grantSpec(...)`'s target options contain only `"Row"` |
| auth-client-025 | access-grant-row-id-length-limit | Save action invoked with `target: "row"`, `rowId` trimmed to exactly 36 characters, then to 37 characters | 36-character id accepted (upsert attempted); 37-character id throws `HubError.validation("Row id must be 36 characters or fewer.")` |
| auth-client-026 | access-grant-permission-required, access-grant-save-never-deletes | Existing grant's "Save" action invoked with all four CRUD toggles `false` | Throws `HubError.validation("Choose at least one permission.")`; `dataSource.upsertGrant`/`removeGrant` never called |
| auth-client-027 | access-crud-serialization | `AccessCRUD(create: true, read: false, update: true, delete: false).crud` and `AccessCRUD(crud: " r , c ")` | `"C,U"` and an `AccessCRUD` with `read == true, create == true, update == false, delete == false` respectively |
| auth-client-028 | access-grant-target-label | `targetLabel(grant-with-target-.bucketType-and-unknown-targetId, tables: [])` | Returns the bare `targetId` (no table matched) |
| auth-client-029 | access-detail-refetches-every-call | Two consecutive `child(for:path: [group], rail:)` calls against a fake data source that changes its `detail(id:)` response between calls | The second call's `groupLevel` reflects the changed response, proving no caching |
| auth-client-030 | main-actor-isolation | Compile-time: `ApiTokensRail`, `StorageTokensRail`, `AccessListsTopic`, `AuthenticationModule` are declared `@MainActor final class` | Confirmed by source declaration (no runtime test needed) |
