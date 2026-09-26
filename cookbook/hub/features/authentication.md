---
id: 65fbb2b1-ca41-499f-ac03-7ecc0e206dcc
title: Authentication Client
domain: agentictoolkit://cookbook/hub/features/authentication
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The client-side contract for personal API tokens, storage tokens, and per-ecosystem bucket access lists: AuthenticationModule's root routing, ApiTokensRail and StorageTokensRail's mint/reveal-once/revoke lifecycle, and AccessListsTopic's groups/members/grants tree, cited to their Swift sources and tests."
platforms:
- swift
- macos
- ios
tags:
- authentication
- api-tokens
- storage-tokens
- access-control
- hub
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AccessListsTopic.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/ApiTokensRail.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AuthenticationModels.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AuthenticationModule.swift
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/StorageTokensRail.swift
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/EcosystemConfigModels.swift
approved-by: ''
approved-date: ''
---

# Authentication Client

## Overview

Four Swift types under `packages/apple/AgenticToolkit/Hub/Features/Authentication/` and one sibling
under `.../EcosystemConfig/` form the client-side contract for everything the Hub's "Authentication"
surface manages: `AuthenticationModule` (`AuthenticationModule.swift`) is the `HTDVDataSource` root —
"Tokens" — that routes to two child rails and an explainer; `ApiTokensRail` (`ApiTokensRail.swift`)
mints, lists, reveals-once, and revokes the caller's personal API tokens (`tmp_…`, scoped by REST
path); `StorageTokensRail` (`StorageTokensRail.swift`, shared with the separate `EcosystemConfig`
feature) does the same for storage tokens (`adh_…`, each its own principal with one isolated bucket),
parameterized by an optional ecosystem id so the identical rail serves both the caller's own tokens
(`ecosystemID: nil`) and a specific ecosystem's tokens; and `AccessListsTopic`
(`AccessListsTopic.swift`) is a separate `EcosystemTopicProvider` — the "Access" product-rail topic —
managing bucket access-control lists (groups), their members, and their C/R/U/D grants, nested three
levels deep. `AuthenticationModels.swift` holds the `Codable`/`Sendable` wire types and the four
`AnyObject, Sendable` data-source protocols (`ApiTokensDataSource`, `BucketAccessDataSource`, plus
`StorageTokensDataSource` in `EcosystemConfigModels.swift`) that all four types depend on but never
implement themselves — every network call is delegated to an injected data source, and every thrown
error is normalized to `HubError` before it reaches a caller. `AccessListsTopic` is not reachable from
`AuthenticationModule`'s tree — the two live in the same folder and share vocabulary (`HubError`,
`FormSpec`, reveal-once secrets) but are wired into the app as two independent entry points.

## Behavioral Requirements

**Root module (`AuthenticationModule`)**

- **root-tokens-level**: `rootLevel()` MUST return an `HTDVLevel` titled "Tokens" with exactly three
  items, in order: `"api"` ("API tokens"), `"storage"` ("Storage tokens", `dividerAfter: true`), and
  `"about"` ("About tokens"), and MUST set `emptyMessage: ""` and `createAction: nil` (the level itself
  offers no create action; creation happens one level down, inside each rail).
- **root-path-routing**: `child(for:)` MUST route a path whose first item's `id` is `"api"` to
  `apiTokens.child(path:)` with the remaining path, `"storage"` to
  `storageTokens.child(path:ecosystemID:levelID:title:)` with the remaining path and
  `ecosystemID: nil`, and `"about"` with an empty remaining path to a read-only notice detail showing
  `AuthenticationModule.overviewMessage`; an empty path MUST return `.level(rootLevel())`.
- **root-unknown-routes-empty**: `child(for:)` MUST return `.empty` for any first-item id other than
  `"api"`/`"storage"`/`"about"`, and for `"about"` with a non-empty remaining path.
- **root-storage-uses-personal-scope**: the root's `"storage"` route MUST always call
  `storageTokens.child(...)` with `ecosystemID: nil`, so the root "Storage tokens" section lists only
  the caller's own (workspace) storage tokens, never an ecosystem's.

**Personal API tokens (`ApiTokensRail`)**

- **api-tokens-list-sorted-by-name**: `level(tokens:)` MUST sort tokens by `name` using
  `localizedCaseInsensitiveCompare` (ascending).
- **api-tokens-list-item-shape**: each row's `id` MUST be the token's `id`, `label` its `name`,
  `sublabel` `"\(prefix)… · \(scopeLine)"`, `systemImage` `"key"`, and `leadsTo` `.detail`.
- **api-tokens-scope-line-legacy-fallback**: `ApiToken.scopeLine` MUST be `"legacy"` when `scope` is
  `nil` or empty, otherwise the scopes joined with `", "`.
- **api-tokens-catalogue-fetched-per-open**: the "New API token" create action MUST call
  `dataSource.scopes()` fresh every time the sheet is opened; it MUST NOT reuse a catalogue fetched by
  an earlier open.
- **api-tokens-catalogue-unavailable-disables-create**: when `scopes()` throws, `createSpec(scopes:
  nil)` MUST return a form with exactly one read-only field (key `"notice"`, label "Scope catalogue")
  and `FormActions()` with no save action, so the sheet can display
  `ApiTokensRail.catalogueUnavailableMessage` but cannot mint a token.
- **api-tokens-create-fields**: `createSpec(scopes:)` with a non-nil catalogue MUST build, in order:
  a required `name` text field, a read-only `scopeHelp` field, one toggle field per catalogue prefix
  (key `"scope:" + prefix`, label the bare prefix), a `readOnly` toggle ("Read-only (GET/HEAD only)"),
  and an `expiresAt` date field.
- **api-tokens-empty-scope-rejected**: the create save action MUST throw
  `HubError.validation(ApiTokensRail.noScopeSelectedMessage)` when `ApiTokensRail.scope(from:prefixes:)`
  returns `nil` (no scope toggle selected), regardless of the `readOnly` toggle's value, and MUST NOT
  call `dataSource.create(_:)` in that case.
- **api-tokens-scope-derivation**: `ApiTokensRail.scope(from:prefixes:)` MUST return, in catalogue
  order, every prefix whose toggle is `true`, each suffixed `":read"` when the `readOnly` toggle is
  `true` and left bare otherwise, and MUST return `nil` when no prefix toggle is `true`.
- **api-tokens-name-trimmed**: the create save action MUST trim leading/trailing whitespace from the
  `name` field before constructing `ApiTokenCreate`.
- **api-tokens-reveal-on-create**: on a successful `dataSource.create(_:)`, the save action MUST store
  the returned `created.token` into `revealedSecrets[created.id]`.
- **api-tokens-reveal-once**: `child(path:)` MUST call `expireRevealedSecret(unless: path.first?.id)`
  before doing anything else on every call; that call MUST remove the currently-revealed secret from
  `revealedSecrets` and clear `revealedOnScreen` whenever the requested path's first id differs from
  `revealedOnScreen`, and MUST leave both untouched when the first id equals `revealedOnScreen` (a
  re-render of the same detail).
- **api-tokens-detail-field-order**: `detail(for:)` MUST list read-only fields in the order `name`,
  `prefix`, `scope`, `created`, `lastUsed`, `expires`, followed by `token` and `notice` only when a
  revealed secret exists for that token.
- **api-tokens-detail-fallbacks**: `detail(for:)` MUST render `scope` as `"legacy (curated-only)"` when
  `token.scope` is `nil` or empty (else the scopes joined by `"\n"`), `lastUsed` as `"never used"` when
  `lastUsedAt` is `nil`, and `expires` as `"never"` when `expiresAt` is `nil`.
- **api-tokens-revoke**: the detail's delete action MUST be titled "Revoke token" with confirmation
  text `Revoke API token "{name}"? Anything using it will stop working.`, MUST call
  `dataSource.revoke(id:)`, and on success MUST clear `revealedSecrets[token.id]`.
- **api-tokens-unknown-path-empty**: `child(path:)` MUST return `.empty` when `path.count == 1` and no
  token matches `path[0].id`, and MUST return `.empty` for any `path.count` other than `0` or `1`.
- **api-tokens-errors-wrapped**: every call into `dataSource` MUST be routed through `HubError.wrap`
  (directly, or via the create save action's own `try await`, which only ever surfaces `HubError` since
  `create(_:)` and `revoke(id:)`'s calls are the only throwing operations besides the two validation
  checks above, both of which already throw `HubError.validation`).

**Storage tokens (`StorageTokensRail`, shared with `EcosystemConfig`)**

- **storage-tokens-ecosystem-scoped**: every `StorageTokensRail` operation (`child`, `level`,
  `createSpec`, `detail`) MUST take an `ecosystemID: String?` and pass it through unchanged to
  `dataSource.list(ecosystemID:)`, `dataSource.create(ecosystemID:_:)`, and
  `dataSource.revoke(ecosystemID:id:)`; `nil` means the caller's own (workspace) tokens, a non-nil value
  means that ecosystem's tokens.
- **storage-tokens-list-sorted-by-slug**: `level(tokens:...)` MUST sort tokens by the raw `<` operator
  on `slug` (NOT `localizedCaseInsensitiveCompare`, unlike `ApiTokensRail`'s name sort).
- **storage-tokens-list-item-shape**: each row's `label` MUST be `token.rdid ?? token.slug`, `sublabel`
  `"\(prefix)… · \(bucketRdid ?? "no bucket")"`, `systemImage` `"externaldrive"`, `leadsTo` `.detail`.
- **storage-tokens-about-varies-by-scope**: `StorageTokensRail.aboutText(ecosystemID:)` MUST return
  `aboutWithoutEcosystem` when `ecosystemID` is `nil` and `aboutWithEcosystem` otherwise; the create
  sheet's `"about"` value MUST come from this function.
- **storage-tokens-name-pattern**: the create form's `name` field MUST enforce `Slug.pattern` with
  `Slug.patternMessage` as its violation message.
- **storage-tokens-create-body-shape**: the create save action MUST trim the `name` field, MUST pass
  `HubText.nonBlank(...)` of the `description` field (nil when blank/missing), and MUST construct
  `StorageTokenCreate` with `ecosystemId: nil` unconditionally — the actual ecosystem scope is conveyed
  exclusively through `dataSource.create(ecosystemID:_:)`'s separate `ecosystemID` argument, never
  through the request body's own `ecosystemId` field.
- **storage-tokens-create-conflict-message**: the create save action MUST catch `HubError.conflict`
  specifically and rethrow `HubError.validation(StorageTokensRail.nameTakenMessage)`.
- **storage-tokens-create-error-tiering**: the create save action MUST rethrow any other `HubError`
  case unchanged, and MUST convert any non-`HubError` throw into
  `HubError.unexpected(StorageTokensRail.createFailedMessage)` — a three-way catch chain distinct from
  the single `HubError.wrap(_:)` pattern every other create/update/delete path in this component uses.
- **storage-tokens-reveal-on-create**: on success, the save action MUST store `created.token` into
  `revealedSecrets[created.id]`, mirroring `api-tokens-reveal-on-create`.
- **storage-tokens-reveal-once**: `child(path:ecosystemID:levelID:title:)` MUST call
  `expireRevealedSecret(unless: path.first?.id)` first on every call, with the same drop/keep semantics
  as `api-tokens-reveal-once`.
- **storage-tokens-detail-field-order**: `detail(for:ecosystemID:)` MUST list read-only fields in the
  order `name`, `identifier`, `prefix`, `bucket`, `description`, `created`, `lastUsed`, `expires`,
  followed by `token`/`notice` only when a revealed secret exists.
- **storage-tokens-detail-fallbacks**: `detail(for:)` MUST render `name` as `token.slug` (not `rdid`),
  `identifier` as `token.rdid ?? "—"`, `bucket` as `token.bucketRdid ?? "no bucket"`, and `description`
  as `"—"` when `token.description.isEmpty`.
- **storage-tokens-revoke**: the detail's delete action MUST be titled "Revoke token" with confirmation
  text `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.`, MUST call
  `dataSource.revoke(ecosystemID:id:)`, and on success MUST clear `revealedSecrets[token.id]`.
- **storage-tokens-unknown-path-empty**: `child(path:...)` MUST return `.empty` when `path.count == 1`
  and no token matches, and for any `path.count` other than `0` or `1`.

**Access lists (`AccessListsTopic`)**

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

- **security-secret-not-persisted**: `ApiTokensRail`/`StorageTokensRail` MUST NOT write a revealed
  plaintext secret to disk, `UserDefaults`, or the Keychain; `revealedSecrets` is a plain in-memory
  dictionary with no backing store.
- **security-secret-single-source**: the plaintext secret MUST be obtainable only from the response of
  `dataSource.create(_:)`/`create(ecosystemID:_:)`; no operation in this contract re-fetches or
  re-derives a previously issued secret once its reveal has expired (`api-tokens-reveal-once` /
  `storage-tokens-reveal-once`).
- **security-unauthorized-propagates**: `HubError.unauthorized`/`.forbidden` thrown by any data source
  MUST propagate unchanged to the caller through `HubError.wrap(_:)` rather than being caught, retried,
  or downgraded locally.
- **security-revocation-is-the-response**: the only way this component withdraws a previously granted
  credential or permission is outright removal — `revoke(id:)`/`revoke(ecosystemID:id:)` for tokens,
  `removeMember(groupID:memberRowID:)`/`removeGrant(groupID:grantID:)` for access — MUST NOT offer any
  "soft-disable" or partial-trust intermediate state.

## Appearance

Not applicable — this is the client-side token/access-list management contract
(`AuthenticationModule` + `ApiTokensRail` + `StorageTokensRail` + `AccessListsTopic`), not a visual
component.

## States

Not applicable — this is the client-side token/access-list management contract, not a visual
component; the `HTDVLevel`/`HTDVDetail` values it returns are consumed by a separate presentation layer
that owns any loading/error/empty visual state.

## Accessibility

Not applicable — this is the client-side token/access-list management contract, not a visual component.

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

## Edge Cases

- **Empty lists**: an empty `[ApiToken]`/`[StorageToken]`/`[AccessGroup]` result MUST render the rail's
  `emptyMessage` ("No API tokens yet.", "No tokens yet.", "No access lists yet.") rather than an error.
- **Row id exactly at the boundary**: a trimmed grant row id of exactly 36 characters MUST be accepted;
  37 characters MUST be rejected (`access-grant-row-id-length-limit`).
- **All-CRUD-false on create vs. on an existing grant**: both paths MUST reject identically
  (`access-grant-permission-required`); the existing-grant path additionally MUST NOT treat the
  all-false state as an implicit delete (`access-grant-save-never-deletes`) — a fixed regression the
  source's own comment documents ("Save with every toggle off used to DELETE the grant, silently and
  with no confirmation").
- **Scope catalogue unavailable at create time**: `ApiTokensRail` MUST disable create entirely
  (`api-tokens-catalogue-unavailable-disables-create`) rather than falling back to an unscoped/legacy
  token, because a `nil` scope selection is itself the broad-legacy-token footgun the disable exists to
  prevent.
- **Scope catalogue available but nothing selected**: MUST be rejected the same way as an unavailable
  catalogue (`api-tokens-empty-scope-rejected`) — for the same reason: an empty selection would silently
  mint the broadest possible token.
- **Concurrent duplicate-name creation (two clients, same bucket)**: `access-create-rejects-duplicate-name-client-side`'s
  pre-check only sees the `existing` list snapshot the caller supplied when it built the form; two
  concurrent creates racing past that check both reach `dataSource.create(bucketID:_:)`, and the loser
  is caught by `access-create-conflict-message`'s server-side `HubError.conflict` handling — the
  client-side check is an early UX shortcut, not the actual concurrency guard.
- **Everyone group protections apply narrowly**: only `name` (rename) and delete are blocked for the
  everyone group (`access-everyone-name-locked`, `access-everyone-delete-blocked`); its `description`
  remains editable, and its grants/members-viewing (but not members-editing,
  `access-everyone-members-is-notice`) remain reachable like any other group.
- **`lastUsed`/`expires` double fallback**: when the field itself is `nil`, both rails show
  `"never used"`/`"never"`; when the field is a non-nil but unparseable ISO string, `HubDates.display`'s
  own internal fallback (`"—"`) applies instead — two different fallback strings reachable from the
  same UI field depending on which condition holds.
- **`AccessCRUD.init(crud:)` with garbage input**: an input string like `"x,y,z"` (no recognized
  letters) MUST NOT throw; it parses to a fully-`false` `AccessCRUD` (`isEmpty == true`), since parsing
  is a case-insensitive substring match against `{"C","R","U","D"}` with no validation that every token
  is recognized.
- **`AccessMemberType` from an unrecognized `memberType` string**: `AccessGroupMember.type` MUST be
  `nil` and `typeTitle` MUST fall back to the raw `memberType` string; `membersLevel`'s row falls back to
  `"questionmark.circle"` for `systemImage`.
- **`AccessGrant` with an unrecognized `targetType`**: `AccessGrant.target` MUST be `nil`;
  `targetLabel(_:tables:)` falls back to the bare `targetId`, and `grantDetail`'s own target line falls
  back to `"{targetType} · {targetId}"` — a different fallback string from `targetLabel`'s, since the
  two format the unknown case independently. Saving that grant MUST throw
  `access-grant-unknown-target-blocked-on-save`'s error rather than silently upserting with a
  meaningless `targetType`.
- **Member id / row id with no client-side format validation**: `memberSpec`'s `memberId` field accepts
  any non-blank, trimmed string with no pattern check (unlike `StorageTokensRail`'s `Slug`-validated
  `name`); member identifiers are caller-supplied external ids (user/org/persona/app/token ids), not a
  slug this component mints.
- **Offline or transport failure from any data source**: every operation propagates the resulting
  `HubError.offline`/`.transport(...)` unchanged (through `HubError.wrap`, or, for
  `StorageTokensRail`'s create path, through the "any other `HubError`" branch of
  `storage-tokens-create-error-tiering`); none of the four types retries, queues, or caches a request to
  paper over a failure — a failed `child(...)` call simply throws, and the caller decides whether to
  retry.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apiTokens` | `ApiTokensDataSource` | none (required) | `AuthenticationModule`'s collaborator for personal API tokens; wrapped internally into an `ApiTokensRail`. |
| `storageTokens` | `StorageTokensDataSource` | none (required) | `AuthenticationModule`'s collaborator for storage tokens; wrapped internally into a `StorageTokensRail`. |
| `dataSource` (`ApiTokensRail.init`) | `ApiTokensDataSource` | none (required) | Backs `list()`, `scopes()`, `create(_:)`, `revoke(id:)`. |
| `dataSource` (`StorageTokensRail.init`) | `any StorageTokensDataSource` | none (required) | Backs `list(ecosystemID:)`, `create(ecosystemID:_:)`, `revoke(ecosystemID:id:)`. |
| `dataSource` (`AccessListsTopic.init`) | `BucketAccessDataSource` | none (required) | Backs `groups()`, `detail(id:)`, `create/update/delete`, `addMember`/`removeMember`, `upsertGrant`/`removeGrant`. |
| `buckets` (`AccessListsTopic.init`) | `BucketsDataSource` | none (required) | Supplies the bucket list/names and bucket-table list this topic renders alongside access lists; owned by the separate Buckets feature. |
| `ecosystemID` (`StorageTokensRail` calls) | `String?` | caller-supplied per call | `nil` selects the caller's own (workspace) tokens; non-nil selects that ecosystem's tokens. |
| `scopes` (`ApiTokensRail.createSpec`) | `[String]?` | caller-supplied per call | The scope catalogue for this create sheet; `nil` disables the save action entirely. |
| Row id length limit | `Int` literal `36` | fixed | Inline bound in `AccessListsTopic`'s grant save action; not a named constant or injectable configuration. |
| `Slug.pattern` / `Slug.patternMessage` | `String` constants | fixed | Shared identifier rule (`Slug.pattern`: one lowercase letter or digit, optionally followed by lowercase letters, digits, or hyphens and ending in a letter or digit) enforced on `StorageTokensRail`'s `name` field. |

## Deep Linking

Not applicable: none of the four types registers a URL scheme, universal link, or `NSUserActivity`;
navigation is entirely through `HTDVItem`/`HTDVChild` path arrays supplied by the presentation layer.

## Localization

The source contains no localization mechanism (no `String(localized:)`, no `.strings`/`.xcstrings`
catalog, no `NSLocalizedString`) — every user-facing string below is a hardcoded English literal, per
Extra Rule 14 stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Choose at least one scope. An empty selection mints a broad legacy token, not the scoped one you intended.` | `ApiTokensRail.noScopeSelectedMessage` |
| — | `Couldn't load the scope catalogue. Token creation is disabled until it loads — otherwise an empty selection would silently mint a broad legacy token instead of the scoped one you intended.` | `ApiTokensRail.catalogueUnavailableMessage` |
| — | `Revoke API token "{name}"? Anything using it will stop working.` | `ApiTokensRail` revoke confirmation |
| — | `That name is already in use. Token names stay reserved even after revoke — pick a different one.` | `StorageTokensRail.nameTakenMessage` |
| — | `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.` | `StorageTokensRail` revoke confirmation |
| — | `An access list named "{name}" already exists in that bucket.` | `AccessListsTopic` create validation |
| — | `The built-in "everyone" list applies to every principal and can't be renamed.` | `AccessListsTopic.everyoneNameHelp` |
| — | `That member is already in this access list.` | `AccessListsTopic` member-add conflict |
| — | `Row id must be 36 characters or fewer.` | `AccessListsTopic` grant validation |
| — | `Choose at least one permission.` | `AccessListsTopic` grant validation (create and save) |

(This is a representative sample of the roughly two dozen literals across the four files, not the full
set; every one of them follows the same pattern — a plain `String` with no key, no catalog entry, and
no pluralization/formatting rule beyond ad hoc string interpolation.)

## Accessibility Options

Not applicable: this is the client-side token/access-list management contract with no UI of its own, so
it responds to no Reduce Motion, Increase Contrast, or Differentiate Without Color setting.

## Feature Flags

Not applicable: none of the four types reads a feature-flag key or contains conditional feature-gating
logic (the sibling `FeatureFlagsDataSource` in `EcosystemConfigModels.swift` manages a *different*
ecosystem-level feature — flags an admin configures — and is not consulted by, or related to, this
component).

## Analytics

Not applicable: the source contains no analytics/event-emission call.

## Privacy

- **Data collected**: a plaintext bearer secret (`ApiTokenCreated.token` / `StorageTokenCreated.token`)
  is returned exactly once, in the response to a successful create call.
- **Storage**: none of the four types persists the secret; `revealedSecrets` is an in-memory
  `[String: String]` on the `@MainActor`-isolated rail instance, with no file, `UserDefaults`, or
  Keychain write anywhere in this component.
- **Transmission**: this component never transmits the secret itself — it receives it once from
  `create(_:)`'s/`create(ecosystemID:_:)`'s response and places it into a `FormDetails.form`'s read-only
  field for on-screen display; actual network transmission is the injected data source's concern, out
  of scope of these files.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (`security-secret-single-source`), which drops a secret from `revealedSecrets` the moment navigation
  moves away from its detail, and the rail instance's own lifetime (the dictionary holds nothing once
  the instance is deallocated, e.g. on app relaunch).
- **Disclosure safeguard**: `ApiTokenCreated` and `StorageTokenCreated` — the two types that
  carry a raw plaintext secret in their `token` field — declare no
  `CustomStringConvertible`/`CustomDebugStringConvertible` override, so their synthesized default
  description includes the secret in full. Neither `ApiTokensRail.swift` nor `StorageTokensRail.swift`
  logs or prints a `created` value; both store only its `token` into `revealedSecrets`. A port MUST NOT
  log these values.

## Logging

Not applicable: the source contains no `os_log`, `Logger`, `print`, or other logging call.

## Platform Notes

- **SwiftUI**: not applicable to these files directly — all four types return `HTDVLevel`/`HTDVDetail`/
  `FormSpec` values consumed by the shared `FormViewController`/HTDV presentation layer; a SwiftUI-based
  presenter would consume the same values unchanged, since none of the four imports SwiftUI or performs
  any rendering itself.
- **AppKit / UIKit**: this is the source. `AuthenticationModule.swift`, `ApiTokensRail.swift`,
  `AuthenticationModels.swift`, and `AccessListsTopic.swift` live in the `Hub` module of the
  `AgenticToolkitHub-macOS`/`AgenticToolkitHub-iOS` targets (both declared in `project.yml`, sharing one
  source set); `StorageTokensRail.swift` lives in the sibling `EcosystemConfig` feature folder of the
  same module. None of the five files imports `AppKit` or `UIKit` directly — each is plain
  `AgenticToolkitHTDV` + `Foundation`, with the platform-specific `NSViewController`/`UIViewController`
  split handled entirely inside `FormViewController` (a different file), one level below where these
  types operate.
- **Compose**: a Kotlin port would model each `Codable` struct (`ApiToken`, `AccessGroup`,
  `AccessGrant`, `StorageToken`, etc.) as an immutable `data class`; the four rails/topics as classes
  exposing `suspend fun` equivalents of `child(...)` returning a sealed `HtdvChild` class
  (`Level`/`Detail`/`Empty`); `HubError` as a Kotlin `sealed class` with the same eight cases, each
  computing its own `message`; `revealedSecrets` as a `MutableMap<String, String>` guarded by
  confinement to a single `Dispatchers.Main`-bound coroutine scope, mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  discriminated-union `HubError` type (`{kind: "conflict", detail: string} | ...`) with a
  `hubErrorMessage()` helper mirroring `HubError.message`, and plain `async` functions returning
  `Promise<HtdvChild>` for each `child(...)`/`level(...)`/`detail(...)` equivalent; the reveal-once
  mechanic would need an explicit teardown (e.g., a router's `onBeforeRouteLeave`/`useEffect` cleanup
  keyed by the outgoing route's first path segment) to reproduce `expireRevealedSecret(unless:)`'s
  "same detail re-renders, anything else expires" rule, since there is no `@MainActor`-style confinement
  to lean on for correctness — the map mutation itself would need to happen on the same thread
  (JavaScript's single-threaded event loop already guarantees this, unlike a truly concurrent runtime).
- **WinUI 3**: a .NET port would model the wire types as `record`s (free structural equality, mirroring
  the Swift `Hashable` conformances) and the four rails/topics as classes with `async Task<HtdvChild>`
  methods, backed by an `HttpClient` + `System.Text.Json` implementation of each `*DataSource` protocol
  (`IApiTokensDataSource`, `IBucketAccessDataSource`, `IStorageTokensDataSource`) with method shapes
  matching the Swift protocols one-to-one (`Task<ApiToken[]> ListAsync()`,
  `Task<ApiTokenCreated> CreateAsync(ApiTokenCreate body)`, etc.); `revealedSecrets` as a
  `Dictionary<string, string>` field on a class instantiated per-window/per-`ContentDialog`, with the
  one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view model's disposal)
  rather than a `@MainActor`-checked property; `Slug.pattern`/`Slug.patternMessage` port directly to a
  `System.Text.RegularExpressions.Regex` constant plus a `TextBox` validation error string; UI-bound
  collections (the token/group/member/grant lists) become `ObservableCollection<T>` wrapped in a view
  model implementing `INotifyPropertyChanged`, with each list rebuilt (not incrementally patched) on
  every re-fetch, mirroring `access-detail-refetches-every-call`'s "no caching" rule.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Authentication/` |

## Design Decisions

**Decision**: `StorageTokensRail` is a single class parameterized by an optional `ecosystemID`, shared
verbatim between `AuthenticationModule`'s "the caller's own tokens" use (`ecosystemID: nil`) and the
separate `EcosystemConfig` feature's "this ecosystem's tokens" use, rather than two separate types.
**Rationale**: the list/create/detail/revoke logic is identical in both cases — only the value passed to
`dataSource.list/create/revoke` and the `about`/level title text differ — so a shared class with the
`ecosystemID` threaded through every call avoids duplicating the reveal-once mechanic and the
create-error-tiering logic in two places.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in `revealedSecrets` only until navigation departs
from the detail screen currently showing it, enforced by calling `expireRevealedSecret(unless:)` at the
top of every `child(...)` call rather than, say, on a timer or on view-disappear.
**Rationale**: per the source's own comment, retaining the secret "for the session made the notice a
lie" — the copy-once affordance (`ApplicationsTopic.revealMessage`) promises the secret disappears once
the reader has navigated away; tying the check to the navigation path itself (rather than a lifecycle
event the presentation layer would have to remember to call) means the guarantee holds regardless of
which presentation layer drives it.
**Approved**: pending

**Decision**: `ApiTokensRail.createSpec(scopes:)` disables its own save action entirely (a notice-only
form) when the scope catalogue fails to load, and separately rejects an empty scope selection when the
catalogue *did* load, rather than falling back to an unscoped ("legacy") token in either case.
**Rationale**: a `nil`/empty scope selection mints the *broadest* token this system can issue, not the
narrowest — the source's own comment calls this out explicitly as a footgun that was once unguarded when
the catalogue loaded successfully. Both guards exist to make the failure mode "creation is blocked" for
a reason the caller can see, rather than "a wide-open token was minted silently."
**Approved**: pending

**Decision**: saving an existing access grant with every CRUD toggle cleared is rejected with a
validation error, not treated as an implicit delete; a grant is removable only through its own explicit
"Remove grant" action.
**Rationale**: the source's own comment documents this as a fixed regression — the previous behavior
made a destructive action ("delete the grant") reachable through a button labelled "Save" with no
confirmation, "behind clearing the last checkbox." The current contract makes "no permissions selected"
an error identical to the one the create form already throws, and reserves actual deletion for the
button whose label and confirmation text say so.
**Approved**: pending

**Decision**: `StorageTokensRail`'s create path uses a three-way `catch` (rethrow a specific
`HubError.conflict` as a friendlier validation message, rethrow any other `HubError` unchanged, and
convert anything else into a fixed `HubError.unexpected(createFailedMessage)`) instead of the single
`HubError.wrap(_:)` call every other create/update/delete path in this component uses; `StorageTokensRail`
also sorts its list by raw `slug` rather than `localizedCaseInsensitiveCompare`d name, unlike
`ApiTokensRail`.
**Rationale**: both divergences are observed, deliberate facts of the current source, not oversights to
be silently unified — `slug` is a `Slug`-pattern-constrained ASCII identifier, so a locale-aware compare
buys nothing there, while a token's display `name` in `ApiTokensRail` is free-form caller text where
locale-aware ordering matters. This recipe states both divergences as requirements
(`storage-tokens-list-sorted-by-slug`, `storage-tokens-create-error-tiering`) rather than smoothing them
into the other rail's pattern.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`secure-storage` passes: no plaintext secret is ever written to disk, `UserDefaults`, or the Keychain by
this component — `revealedSecrets` is transient, in-memory, and actively self-expiring
(`security-secret-not-persisted`). `input-sanitization` is `partial`: the fields whose shape actually
matters downstream are validated (`Slug.pattern` on storage-token names, the 36-character row-id bound,
the required-field checks on every create/add form), but free-text fields like a group's or token's
`description` and a member's `memberId` are only trimmed, not pattern- or length-checked, leaving that
enforcement to the server. `explicit-error-handling` passes: every throwing path surfaces only
`HubError`, with the one intentional, documented divergence in `StorageTokensRail`'s create path
(covered above) rather than a silently swallowed exception. `no-hardcoded-strings` fails outright — see
Localization; there is no localization mechanism anywhere in these five files. `data-minimization` is
`partial`: `revealedSecrets` can hold more than one plaintext secret at once (every token created in a
session without its detail ever being opened keeps accumulating), and neither `ApiTokenCreated` nor
`StorageTokenCreated` carries a redaction safeguard against being logged or printed whole (the
Disclosure safeguard under Privacy). `idempotent-operations` passes for the one operation named that way in the
source: `upsertGrant(groupID:_:)` — calling it twice with the same `target`/`crud` body produces the
same end state each time, by design (`AccessGrantUpsert` is explicitly an upsert, not an append).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
