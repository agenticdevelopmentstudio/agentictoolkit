---
id: 18ea2506-0cbc-4c6a-880b-e94abcdc55b2
title: 'Hub Domain: Buckets'
domain: agentictoolkit://cookbook/hub/features/buckets
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Hub''s Buckets domain: a data-access protocol and Codable models for
  storage buckets and their tables, and the topic provider that lists, creates, edits,
  and deletes them.'
platforms:
- swift
- macos
- ios
tags:
- hub
- buckets
- data-source
- forms
- crud
depends-on: []
related:
- agentictoolkit://cookbook/htdv
references:
- packages/apple/AgenticToolkit/Hub/Features/Buckets/BucketsDataSource.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Buckets/BucketsModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Buckets/BucketsTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/BucketsTopicTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Buckets

## Overview

The Buckets domain is the Hub's storage-bucket management: buckets (rows of
`/bucket/buckets`) and the tables each one contains (rows of
`/bucket/bucket-types`). It is three cooperating pieces:

- **`BucketsDataSource`** (`BucketsDataSource.swift`) — the protocol
  through which the Buckets topic reaches the server: list/get/create/
  update/delete for buckets, and the parallel five for tables.
- **The data shapes** (`BucketsModels.swift`) — `Bucket`, `BucketMetadata`,
  `BucketCreate`, `BucketUpdate`, `BucketTable`, `BucketTableCreate`, and
  `BucketTableUpdate`, the `Codable` payloads the data source sends and
  receives.
- **`BucketsTopic`** (`BucketsTopic.swift`) — the `EcosystemTopicProvider`
  that renders this domain into the Hub's rail/detail (HTDV) navigation:
  a bucket list, each bucket's Settings and Tables panes, and the create/
  edit/delete forms for both buckets and tables. `BucketsTopic` builds on
  the HTDV navigation and Forms types (`HTDVLevel`, `HTDVChild`, `FormSpec`,
  `FormState`, and the rest) documented in the related HTDV Engine recipe;
  those types are not redescribed here.

`FormSheet`, `FormDetails`, `RailPath`, `HubError`, `EcosystemTopicProvider`,
`EcosystemRail`, and `Ecosystem` are Hub-wide helpers `BucketsTopic` is built
on but that are not among this recipe's three given sources; they are
described here only to the extent needed to state what `BucketsTopic` itself
does with them.

## Behavioral Requirements

### BucketsDataSource.swift — server data-access contract

- **data-source-contract**: `BucketsDataSource` MUST be a `Sendable`,
  `AnyObject`-constrained protocol declaring nine `async throws` operations:
  `list(ecosystemID:)`, `get(id:)`, `create(_:)`, `update(id:_:)`,
  `delete(id:)`, `tables(ecosystemID:)`, `createTable(_:)`,
  `updateTable(id:_:)`, and `deleteTable(id:)`.
- **list-is-ecosystem-scoped**: `list(ecosystemID:)` MUST return only the
  buckets belonging to the given ecosystem, per the source's own comment
  "Lists are ecosystem-scoped."
- **tables-spans-every-bucket-in-the-ecosystem**: `tables(ecosystemID:)`
  MUST return every table of every bucket in the given ecosystem in a
  single call; per the source's own comment, the topic itself is
  responsible for grouping the result "by `bucketId`" rather than the data
  source filtering per bucket.
- **data-source-is-class-bound**: `BucketsDataSource` MUST be constrained
  to `AnyObject`, so an implementation is a class or actor, never a value
  type; per the source's own comment on the concrete equivalent in the
  HTDV Engine recipe's `HTDVDataSource`, such implementations are typically
  actors or `@unchecked Sendable` classes wrapping a network client — none
  of which is among this recipe's three given sources.

### BucketsModels.swift — data shapes

- **bucket-metadata-shape**: `BucketMetadata` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing a single optional `description:
  String?`, defaulting to `nil`.
- **bucket-shape**: `Bucket` MUST be a `Codable`, `Hashable`, `Sendable`,
  `Identifiable` struct exposing `id: String`, `ecosystemId: String`,
  `name: String`, `kind: String`, `metadata: BucketMetadata?`,
  `createdAt: String?`, and `updatedAt: String?`.
- **bucket-decoding-tolerates-missing-kind-and-optionals**: `Bucket.init(from:)`
  MUST decode `kind` via `decodeIfPresent` defaulting to the literal
  `"custom"` when the key is absent, and MUST decode `metadata`,
  `createdAt`, and `updatedAt` via `decodeIfPresent` defaulting each to
  `nil`, so a payload that omits any of these four keys decodes
  successfully rather than throwing.
- **bucket-description-derivation**: `Bucket.description` MUST return
  `metadata?.description ?? ""`, collapsing both an absent `metadata` and a
  present `metadata` with a `nil` `description` into the empty string.
- **bucket-is-built-in-derivation**: `Bucket.isBuiltIn` MUST be `true` if
  and only if `kind != "custom"`; any `kind` value other than the literal
  `"custom"` — not only a specific enumerated set — is treated as built-in.
- **bucket-create-requires-metadata**: `BucketCreate` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing `ecosystemId: String`,
  `name: String`, and a non-optional `metadata: BucketMetadata` — unlike
  `Bucket.metadata`, a create payload always carries a metadata value
  (possibly one whose own `description` is `nil`).
- **bucket-update-is-a-partial-patch**: `BucketUpdate` MUST be a
  `Codable`, `Hashable`, `Sendable` struct exposing `name: String?` and
  `metadata: BucketMetadata?`, both defaulting to `nil`, so an update
  payload can carry either field independently of the other.
- **bucket-table-shape**: `BucketTable` MUST be a `Codable`, `Hashable`,
  `Sendable`, `Identifiable` struct exposing four non-optional fields:
  `id: String`, `bucketId: String`, `sqlTableName: String`, and
  `name: String`, with no custom decoding — every field MUST be present in
  the payload.
- **bucket-table-create-shape**: `BucketTableCreate` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing `ecosystemId: String`,
  `bucketId: String`, `sqlTableName: String`, and `name: String`, all
  non-optional.
- **bucket-table-update-has-no-sql-name-field**: `BucketTableUpdate` MUST
  be a `Codable`, `Hashable`, `Sendable` struct exposing only
  `name: String?`, defaulting to `nil`; it exposes no field for
  `sqlTableName`, so a table's SQL identifier cannot be changed through
  this payload once the table exists.

### BucketsTopic.swift — navigation, listing, and forms

- **topic-identity**: `BucketsTopic.entry` MUST be the static
  `EcosystemTopicEntry` with `id: "buckets"`, `label: "Buckets"`,
  `systemImage: "tablecells"`, and `description: "Storage buckets and the
  tables they contain."`.
- **topic-actor-confinement**: `BucketsTopic` MUST be declared `@MainActor`
  and `final`, conforming to `EcosystemTopicProvider`, and holds a single
  stored `dataSource` supplied through its public `init`.
- **table-name-derivation-is-nonisolated-and-pure**: `BucketsTopic.tableName(from:)`
  MUST be a `nonisolated static` function so it is callable off the main
  actor — per the source's own comment, because `createTableSpec`'s save
  action calls it from inside a `FormAction.perform` closure that runs off
  the main actor. It MUST lowercase the input, keep every scalar in the
  ASCII ranges "a" through "z" and "0" through "9" unchanged, and collapse
  any run of one or more other scalars — including whitespace, punctuation,
  and any non-ASCII scalar such as a CJK character — into a single `"_"`
  separator, with no leading or trailing underscore in the result.
- **table-name-of-unusable-input-is-empty-string**: `tableName(from:)` MUST
  return the empty string both when the input is empty and when the input
  is non-empty but contains no ASCII letter or digit (for example, an
  all-CJK name), per the source's own comment: "A name can be non-empty and
  still derive an EMPTY SQL identifier (every character stripped, e.g. an
  all-non-ASCII name)."
- **table-count-pluralization**: `BucketsTopic.tableCount(_:)` MUST return
  the literal `"1 table"` when the count equals exactly `1`, and
  `"<count> tables"` for every other count, including `0`.
- **child-dispatch-by-rail-path-depth**: `child(for:path:rail:)` MUST
  dispatch on the depth of the given `path`: an empty path yields the
  buckets list level; a path whose first item id names a bucket reveals
  that bucket's level; a second item id of `"settings"` reveals the
  settings detail, a second item id of `"tables"` reveals the tables
  level (optionally followed by a third item id naming one table's
  detail); any other second item id, or a third item id that names no
  table in the bucket, MUST yield `.empty` rather than throwing.
- **missing-bucket-yields-empty-not-error**: When `dataSource.get(id:)`
  throws `HubError.notFound` for the bucket named at path index `0`,
  `child` MUST return `.empty`; any other error thrown by `get(id:)` MUST
  be re-thrown after `HubError.wrap`.
- **buckets-list-level-shape**: The root level MUST have `id:
  "buckets-list"`, `title: "Buckets"`, `emptyMessage: "No buckets yet."`,
  and one item per bucket returned by `list(ecosystemID:)`, each item's
  `label` set to the bucket's `name`, `sublabel` set to
  `tableCount(_:)` of that bucket's own table count (matched by
  `bucketId` against every table `tables(ecosystemID:)` returns for the
  ecosystem), `systemImage: "tablecells"`, and `leadsTo: .list`; it MUST
  carry a `createAction` titled `"New bucket"` that presents `createSpec`
  through `FormSheet.present`.
- **bucket-level-shape**: A selected bucket's level MUST have `id:
  "bucket:<bucketID>"`, `title` set to the bucket's `name`, and exactly two
  fixed items: `id: "settings"` (`sublabel: "Name and description."`,
  `leadsTo: .detail`) and `id: "tables"` (`sublabel: "The tables this
  bucket contains."`, `leadsTo: .list`).
- **tables-of-bucket-refetches-the-whole-ecosystem**: The private
  `tables(of:in:)` helper MUST call `dataSource.tables(ecosystemID:)` —
  fetching every table of every bucket in the ecosystem — and filter the
  result client-side to the given bucket's `bucketId`, rather than calling
  any bucket-scoped table-listing operation; both the buckets-list item
  count and the tables level reuse this same helper.
- **tables-level-shape**: A bucket's tables level MUST have `id:
  "bucket-tables:<bucketID>"`, `title: "Tables"`, `emptyMessage: "No tables
  yet."`, one item per table with `label` set to the table's `name` and
  `sublabel` set to its `sqlTableName`, each with `leadsTo: .detail`, and a
  `createAction` titled `"New table"` that presents `createTableSpec`
  through `FormSheet.present`.
- **create-bucket-form-fields**: `createSpec(for:)` MUST return a
  `FormSpec` with exactly two fields in order: a required `.text` field
  keyed `"name"` (placeholder `"Profile Basics"`) and an optional
  `.textArea` field keyed `"description"` (`minLines: 2`, placeholder
  `"What this bucket is for."`).
- **create-bucket-precheck-rejects-case-insensitive-duplicate**: The create
  save action MUST trim the entered name of leading/trailing whitespace and
  newlines, fetch the ecosystem's current bucket list via `list(ecosystemID:)`,
  and throw `HubError.validation("A bucket named \"<name>\" already exists.")`
  when an existing bucket's `name` matches the trimmed name
  case-insensitively — before calling `dataSource.create`.
- **create-bucket-conflict-fallback**: When the precheck passes but
  `dataSource.create` itself throws `HubError.conflict`, the save action
  MUST catch it and throw the identical `"A bucket named \"<name>\" already
  exists."` validation message rather than propagating the raw conflict
  (see Design Decisions).
- **create-bucket-empty-description-becomes-nil-metadata**: The create save
  action MUST post `BucketMetadata(description: nil)` when the (untrimmed)
  entered description is exactly the empty string, and
  `BucketMetadata(description: <text>)` otherwise — a description
  consisting only of whitespace is posted as non-`nil` metadata, since only
  exact emptiness triggers the `nil` substitution.
- **settings-form-fields-and-seed-values**: `settingsDetail(for:)` MUST
  build an `HTDVDetail` with `id: "bucket:<bucketID>:settings"`, `title:
  "Bucket"`, the same two fields as `createSpec` (`"name"`, required;
  `"description"`, optional `.textArea`), and initial values seeded from
  the bucket's `name` and its computed `description`.
- **settings-form-conflict-fallback-without-a-precheck**: The settings save
  action MUST call `dataSource.update(id:_:)` directly, with no client-side
  duplicate lookup beforehand, and MUST catch a thrown `HubError.conflict`
  and re-throw it as `"A bucket named \"<name>\" already exists."` — the
  same message `createSpec`'s save produces, but reached only through the
  server's conflict response, never a local list check.
- **settings-form-delete-gated-by-built-in**: The settings `FormSpec`'s
  `actions.delete` MUST be `nil` when the bucket's `isBuiltIn` is `true`,
  and otherwise MUST be a `FormDeleteAction` titled `"Delete bucket"` with
  `confirmationText: "Delete bucket \"<name>\"? Applications that granted
  it will lose those tables."` that invokes `dataSource.delete(id:)`.
- **create-table-form-field-is-not-marked-required**: `createTableSpec(for:bucket:)`
  MUST return a `FormSpec` with exactly one field, a `.text` field keyed
  `"name"` (placeholder `"contacts"`) whose `isRequired` is `false` at the
  field level — required-ness for this field is enforced by the save
  action itself, not by the Forms subsystem's own required-field check
  (see Design Decisions).
- **create-table-requires-a-non-empty-trimmed-name**: The create-table save
  action MUST trim the entered name and throw `HubError.validation("Every
  table needs a name.")` when the trimmed name is empty, before deriving a
  SQL name.
- **create-table-rejects-a-name-with-no-usable-characters**: When
  `tableName(from:)` derives the empty string from a non-empty trimmed
  name, the save action MUST throw `HubError.validation(BucketsTopic.unusableTableNameMessage)`
  — the literal message "That name has no letters or digits that can be
  used in a SQL table name. Use at least one a–z letter or 0–9 digit." —
  rather than proceeding to post an empty `sqlTableName`.
- **create-table-duplicate-check-is-by-name-or-derived-sql-name**: The
  create-table save action MUST fetch the bucket's existing tables via the
  `tables(of:in:)` helper and throw `HubError.validation("Two tables share
  the name \"<name>\". Names must be unique.")` when an existing table's
  `name` matches case-insensitively, OR its `sqlTableName` equals the newly
  derived `sqlTableName`, whichever condition is met first.
- **create-table-conflict-fallback**: When `dataSource.createTable` itself
  throws `HubError.conflict`, the save action MUST catch it and throw the
  identical `"Two tables share the name \"<name>\". Names must be unique."`
  message rather than propagating the raw conflict.
- **table-detail-shape**: `tableDetail(for:in:)` MUST build an `HTDVDetail`
  with `id: "bucket-table:<tableID>"`, `title` set to the table's `name`,
  and two fields: a `.text` field keyed `"name"` (`isRequired: false`,
  placeholder `"contacts"`) and a `.readOnly` field keyed `"sqlTableName"`
  (`isMonospaced: true`), seeded from the table's `name` and `sqlTableName`.
- **table-detail-save-updates-name-only**: The table-detail save action
  MUST throw `HubError.validation("Every table needs a name.")` on an empty
  trimmed name, and otherwise MUST call `updateTable(id:_:)` with a
  `BucketTableUpdate` carrying only the new `name` — `sqlTableName` cannot
  be resubmitted through this action, per `bucket-table-update-has-no-sql-name-field`.
- **table-detail-delete**: The table-detail `FormSpec`'s `actions.delete`
  MUST be a `FormDeleteAction` titled `"Remove table"` with
  `confirmationText: "Remove table \"<name>\"? Data in it is not deleted
  until the bucket is."` that invokes `deleteTable(id:)`.
- **every-other-thrown-error-is-wrapped-not-swallowed**: Every `catch`
  block in `BucketsTopic` other than the specific `HubError.notFound` and
  `HubError.conflict` re-mappings described above MUST re-throw via
  `HubError.wrap(error)`, so no code path in this file allows a
  non-`HubError` to escape unconverted or a caught error to be dropped
  without being re-thrown in some form.

## Appearance

Not applicable — this is the Buckets domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component.

## States

Not applicable — this is the Buckets domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component. The one
runtime state distinction this file makes — a bucket being built-in
(`kind != "custom"`) versus custom, which gates whether its settings form
exposes a delete action — is captured above as a requirement
(`bucket-is-built-in-derivation`, `settings-form-delete-gated-by-built-in`),
not in a visual-state table.

## Accessibility

Not applicable — this is the Buckets domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component. `BucketsDataSource`,
`BucketsModels`, and `BucketsTopic` produce no view, role, trait, or label
of their own; any accessibility surface belongs to the `FormViewController`/
`AgenticToolkitHTDVViewController` presentation layer that renders the
`HTDVLevel`/`HTDVDetail`/`FormSpec` values these sources build (out of this
recipe's given sources; see the related HTDV Engine recipe).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-buckets-001 | bucket-decoding-tolerates-missing-kind-and-optionals | Decode a JSON bucket payload whose `metadata` is `null` and whose `kind` key is absent (`testDecodesBucketWithMissingKindAndMetadata`). | `bucket.kind == "custom"`, `bucket.isBuiltIn == false`, `bucket.description == ""`. |
| hub-domain-buckets-002 | table-name-derivation-is-nonisolated-and-pure | `BucketsTopic.tableName(from: "Contact Notes")` (`testTableNameAndCount`). | Returns `"contact_notes"`. |
| hub-domain-buckets-003 | table-name-derivation-is-nonisolated-and-pure | `BucketsTopic.tableName(from: "  Órders-2 ")` (`testTableNameAndCount`). | Returns `"rders_2"` — the accented "Ó" and the hyphen are both treated as separators, and the accent is dropped rather than transliterated. |
| hub-domain-buckets-004 | table-name-of-unusable-input-is-empty-string | `BucketsTopic.tableName(from: "")` (`testTableNameAndCount`). | Returns `""`. |
| hub-domain-buckets-005 | table-name-of-unusable-input-is-empty-string | `BucketsTopic.tableName(from:)` on a two-character all-CJK string (`testTableNameAndCount`). | Returns `""`. |
| hub-domain-buckets-006 | table-name-derivation-is-nonisolated-and-pure | `BucketsTopic.tableName(from: "  Contact   Notes!  ")` (`testTableNameAndCount`). | Returns `"contact_notes"` — the run of spaces, and the trailing `"!  "`, each collapse without producing a leading or trailing underscore. |
| hub-domain-buckets-007 | table-count-pluralization | `BucketsTopic.tableCount(0)`, `tableCount(1)`, `tableCount(3)` (`testTableNameAndCount`). | Returns `"0 tables"`, `"1 table"`, `"3 tables"` respectively. |
| hub-domain-buckets-008 | buckets-list-level-shape | `child([])` against two buckets in the target ecosystem (one with two tables, one with zero) plus a third bucket in a different ecosystem (`testListShowsBucketsWithTableCounts`). | Returns a `.level` with `id == "buckets-list"`, items labeled `["Profile Basics", "Orders"]`, sublabels `["2 tables", "0 tables"]`, and `createAction?.title == "New bucket"`; the other-ecosystem bucket does not appear. |
| hub-domain-buckets-009 | create-bucket-precheck-rejects-case-insensitive-duplicate | `createSpec(for:)`'s save action with `name` set to `"profile basics"` where a bucket named `"Profile Basics"` already exists (`testCreateFormValidatesAndCreates`). | `save()` returns `false`; `saveError == "A bucket named \"profile basics\" already exists."`; `dataSource.create` is never called. |
| hub-domain-buckets-010 | create-bucket-empty-description-becomes-nil-metadata | The same save action with `name: "Orders"`, `description: "Carts and receipts"`, no existing bucket named "Orders" (`testCreateFormValidatesAndCreates`). | `save()` returns `true`; `dataSource.creates` records one `BucketCreate(ecosystemId: "org.acme.shop", name: "Orders", metadata: BucketMetadata(description: "Carts and receipts"))`. |
| hub-domain-buckets-011 | create-bucket-conflict-fallback | The create save action passes the precheck (no matching name in the fetched list) but `dataSource.create` throws `HubError.conflict("...")` — derived directly from the source's `catch HubError.conflict { throw HubError.validation(...) }` block; no test in `BucketsTopicTests.swift` exercises this branch. | `save()` returns `false`; `saveError == "A bucket named \"<name>\" already exists."`, not the raw conflict detail. |
| hub-domain-buckets-012 | bucket-level-shape | `child(["b-profile"])` (`testBucketLevelHasSettingsAndTables`). | Returns a `.level` with `id == "bucket:b-profile"`, `title == "Profile Basics"`, items `["settings", "tables"]` with `leadsTo` `[.detail, .list]`. |
| hub-domain-buckets-013 | missing-bucket-yields-empty-not-error | `child(["nope"])` against a data source with no bucket `"nope"` (`testUnknownBucketIsEmpty`). | Returns `.empty`. |
| hub-domain-buckets-014 | settings-form-fields-and-seed-values | `child(["b-profile", "settings"])`, then set `name` to `"Profile"` and save (`testSettingsFormSavesNameAndDescription`). | `detail.id == "bucket:b-profile:settings"`; initial `name`/`description` values equal the bucket's own; after save, `dataSource.updates` records `(id: "b-profile", input: BucketUpdate(name: "Profile", metadata: BucketMetadata(description: "Names and avatars")))`. |
| hub-domain-buckets-015 | settings-form-delete-gated-by-built-in | Settings form for a bucket with `kind: "system"` versus one with `kind: "custom"` (`testBuiltInBucketHasNoDeleteAndCustomDeletes`). | The `"system"` bucket's `spec.actions.delete` is `nil`; the custom bucket's `delete.title == "Delete bucket"` and, once invoked, `dataSource.deletes == ["b-profile"]`. |
| hub-domain-buckets-016 | tables-level-shape, tables-of-bucket-refetches-the-whole-ecosystem | `child(["b-profile", "tables"])` with one table in the bucket (`testTablesLevelListsTables`). | Returns a `.level` with `id == "bucket-tables:b-profile"`, one item labeled `"Contacts"` with sublabel `"contacts"`, `createAction?.title == "New table"`. |
| hub-domain-buckets-017 | create-table-requires-a-non-empty-trimmed-name | `createTableSpec`'s save action with `name` set to three spaces (`testNewTableFormDerivesSQLNameAndRejectsDuplicates`). | `save()` returns `false`; `saveError == "Every table needs a name."`. |
| hub-domain-buckets-018 | create-table-duplicate-check-is-by-name-or-derived-sql-name | The same save action with `name: "contacts"` where a table with `sqlTableName: "contacts"` already exists in the bucket (`testNewTableFormDerivesSQLNameAndRejectsDuplicates`). | `save()` returns `false`; `saveError == "Two tables share the name \"contacts\". Names must be unique."`. |
| hub-domain-buckets-019 | create-table-duplicate-check-is-by-name-or-derived-sql-name | The same save action with `name: "Contact Notes"` and no existing collision (`testNewTableFormDerivesSQLNameAndRejectsDuplicates`). | `save()` returns `true`; `dataSource.tableCreates` records one `BucketTableCreate(ecosystemId: "org.acme.shop", bucketId: "b-profile", sqlTableName: "contact_notes", name: "Contact Notes")`. |
| hub-domain-buckets-020 | create-table-rejects-a-name-with-no-usable-characters | `createTableSpec`'s save action with `name` set to a two-character all-CJK string (`testNewTableFormRejectsANameWithNoUsableCharacters`). | `save()` returns `false`; `saveError == BucketsTopic.unusableTableNameMessage`; `dataSource.tableCreates` stays empty. |
| hub-domain-buckets-021 | create-table-conflict-fallback | `dataSource.createTable` throws `HubError.conflict("...")` after the duplicate precheck passes — derived directly from the source's `catch HubError.conflict { throw HubError.validation(...) }` block; no test in `BucketsTopicTests.swift` exercises this branch. | `save()` returns `false`; `saveError == "Two tables share the name \"<name>\". Names must be unique."`. |
| hub-domain-buckets-022 | table-detail-shape, table-detail-save-updates-name-only | `child(["b-profile", "tables", "t1"])`, then set `name` to `"People"` and save (`testTableDetailRenamesAndRemoves`). | `detail.id == "bucket-table:t1"`; the `sqlTableName` field `isEditable == false`; after save, `dataSource.tableUpdates == [(id: "t1", input: BucketTableUpdate(name: "People"))]`. |
| hub-domain-buckets-023 | table-detail-delete | Invoking the table-detail `FormDeleteAction.perform()` (`testTableDetailRenamesAndRemoves`). | `dataSource.tableDeletes == ["t1"]`; `delete.confirmationText == "Remove table \"Contacts\"? Data in it is not deleted until the bucket is."`. |
| hub-domain-buckets-024 | every-other-thrown-error-is-wrapped-not-swallowed | `child([])` where `dataSource.list`/`dataSource.tables` throws `HubError.offline` (`testFailuresSurfaceAsHubError`). | The call throws `HubError.offline` unchanged — wrapped but not altered, since `HubError.wrap` returns an existing `HubError` as-is. |

## Edge Cases

- **Null and empty input**: An empty or whitespace-only bucket `name` on
  create or settings-save is rejected before this file's own save action
  runs, because `createSpec`/`settingsDetail` both mark the `"name"` field
  `isRequired: true`, and the Forms subsystem's own required-field
  validation (documented in the related HTDV Engine recipe) blocks `save()`
  from invoking the action at all (MUST, by construction of the field). An
  empty or whitespace-only table `name`, by contrast, MUST be caught by
  this file's own save action with `"Every table needs a name."`, because
  `createTableSpec`/`tableDetail` deliberately mark that field
  `isRequired: false` (MUST, see `create-table-requires-a-non-empty-trimmed-name`,
  `table-detail-save-updates-name-only`). An exactly-empty description MUST
  post `nil` metadata; a whitespace-only description is non-empty by this
  check and MUST post as literal whitespace (MUST, see
  `create-bucket-empty-description-becomes-nil-metadata`).
- **Boundary values**: A table count of exactly `1` MUST use the singular
  `"1 table"`; every other count, including `0`, MUST use the plural form
  (MUST, see `table-count-pluralization`). A name that is non-empty after
  trimming but derives an empty SQL identifier — every character stripped —
  MUST be rejected with the dedicated "no letters or digits" message rather
  than silently producing an empty `sqlTableName` (MUST, see
  `table-name-of-unusable-input-is-empty-string`,
  `create-table-rejects-a-name-with-no-usable-characters`).
- **Concurrent access**: `BucketsTopic` is `@MainActor`-confined with no
  `Sendable` conformance of its own, so its own state (the single stored
  `dataSource` reference) is not mutated concurrently from another
  isolation domain. The data it depends on can still race across separate
  requests to the server: two overlapping "create bucket" (or "create
  table") calls can both pass this file's client-side duplicate precheck
  before either has landed, because the precheck lists existing state,
  then the create call happens later with no lock in between; this file's
  own defense is that a resulting server-side `HubError.conflict` is caught
  and re-thrown as the same duplicate-name validation message the precheck
  would have produced (MUST, see `create-bucket-conflict-fallback`,
  `create-table-conflict-fallback`, and Design Decisions). `settingsDetail`'s
  save action runs no precheck at all and depends on this same
  conflict-to-validation mapping alone (MUST, see
  `settings-form-conflict-fallback-without-a-precheck`).
- **Error states**: Every operation in `BucketsDataSource` is `async
  throws`; `BucketsTopic` converts every error it does not specifically
  remap (`HubError.notFound` on `get(id:)`, `HubError.conflict` on the
  three create/update save actions) into a `HubError` via `HubError.wrap`
  and re-throws it, so no failure is dropped silently (MUST, see
  `missing-bucket-yields-empty-not-error`,
  `every-other-thrown-error-is-wrapped-not-swallowed`,
  `testFailuresSurfaceAsHubError`). `HTDVCreateAction.perform` (the
  closures passed to `HTDVLevel.createAction`) is non-throwing per its own
  declared signature (documented in the related HTDV Engine recipe), so a
  failure while presenting the "New bucket"/"New table" sheet through
  `FormSheet.present` has no channel back into this file's own error
  handling — it is the sheet's own responsibility.
- **Offline or disconnected state**: None of the three given sources make
  a network call directly or define a timeout, retry, or connectivity-aware
  behavior of their own; every call to `BucketsDataSource` either succeeds
  or throws, and a thrown error surfaces exactly as described under Error
  states above (fact, not a gap — the failure is reported, not lost, just
  with no time bound or automatic retry defined at this layer).

- **table-name-length-bound**: NEEDS REVIEW: Not implemented in source. `tableName(from:)` strips a table name down to its ASCII letters, digits, and single-underscore separators with no maximum length enforced anywhere in either `tableName(from:)` or `createTableSpec`'s save action, even though deriving a valid SQL identifier is the explicit purpose of this function; most SQL engines cap identifier length (for example, 63 bytes on PostgreSQL), so a sufficiently long table name could produce a `sqlTableName` some downstream schema-creation step truncates or rejects unpredictably, and nothing in these three sources says which system is responsible for that bound — resolvable by inspecting whichever `BucketsDataSource` implementation and server-side schema-creation code consume `sqlTableName` (not among the given sources), or by a decision from the Hub team on where the length limit belongs.

- **bucket-ecosystem-scoping**: NEEDS REVIEW: Not implemented in source. `child(for:path:rail:)` fetches a bucket by `dataSource.get(id: bucketID)` using only the raw bucket id taken from the rail path, and never compares the returned `bucket.ecosystemId` against the `ecosystem` parameter `child` was itself given before proceeding to `get`/`update(id:_:)`/`delete(id:)`/`createTable`/`updateTable(id:_:)`/`deleteTable(id:)`; `list(ecosystemID:)` is documented as ecosystem-scoped in its own doc comment, but none of the id-only operations carries or checks an ecosystem, so nothing in these three sources stops a rail path holding a bucket or table id from a different ecosystem from resolving and mutating it — resolvable by inspecting whether the deployed `BucketsDataSource` implementation enforces this scoping server-side (not among the given sources), or by a decision from the Hub team on whether client-side scoping is also required.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (parameter to `BucketsTopic.init`) | `any BucketsDataSource` | none — required | The server access point this topic navigates and posts through; the host supplies its own implementation. |
| `ecosystem` (parameter to every `child(for:path:rail:)` call, and to `createSpec(for:)`/`createTableSpec(for:bucket:)`) | `Ecosystem` | none — required | Supplies the `ecosystemId` value posted with every create call and, per `list-is-ecosystem-scoped`, the scope of `list`/`tables` reads; not among this recipe's given sources beyond its `id` field. |

None of the three given sources reads an environment variable or a named
settings key; every value `BucketsTopic` needs is supplied by its `init`
parameter, the `Ecosystem`/`Bucket`/`BucketTable` values passed into its
methods, or the user's own form input.

## Deep Linking

Not applicable: none of the three given sources define a URL scheme, route,
or app-level navigation destination. `BucketsTopic`'s rail-path ids
(`"settings"`, `"tables"`, a bucket or table id) are in-memory arguments to
`child(for:path:rail:)`, consumed by the HTDV navigation state machine
documented in the related HTDV Engine recipe, not a deep-linkable URL.

## Localization

None of the three given sources reference a string-key or localization
table; every user-facing string `BucketsTopic` produces is a hardcoded
English literal composed inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Buckets` | `BucketsTopic.entry.label` and the buckets-list level's `title`. |
| (none — literal, no key) | `Storage buckets and the tables they contain.` | `BucketsTopic.entry.description`. |
| (none — literal, no key) | `No buckets yet.` | Buckets list level's `emptyMessage`. |
| (none — literal, no key) | `New bucket` / `New table` | The two levels' `createAction.title`. |
| (none — literal, no key) | `Name and description.` / `The tables this bucket contains.` | The bucket level's fixed item sublabels. |
| (none — literal, no key) | `Tables` / `No tables yet.` | The tables level's `title`/`emptyMessage`. |
| (none — literal, no key) | `A bucket named "<name>" already exists.` | Create/settings save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Every table needs a name.` | Create-table/table-detail save-action empty-name message. |
| (none — literal, no key) | `That name has no letters or digits that can be used in a SQL table name. Use at least one a–z letter or 0–9 digit.` | `BucketsTopic.unusableTableNameMessage`. |
| (none — literal, no key) | `Two tables share the name "<name>". Names must be unique.` | Create-table save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Delete bucket "<name>"? Applications that granted it will lose those tables.` | Settings form's delete confirmation text. |
| (none — literal, no key) | `Remove table "<name>"? Data in it is not deleted until the bucket is.` | Table-detail form's delete confirmation text. |
| (none — literal, no key) | `Bucket` | Settings detail's fixed `title`. |
| (none — literal, no key) | `Name`, `Description`, `SQL table name` | Field labels across the four form specs. |

## Accessibility Options

Not applicable: none of the three given sources present any UI of their own,
so none responds to Reduce Motion, Increase Contrast, or Differentiate
Without Color; any such handling belongs to the presentation layer that
renders the `HTDVLevel`/`HTDVDetail`/`FormSpec` values this file builds.

## Feature Flags

Not applicable: none of the three given sources read a feature-flag or an
on/off settings key. Every behavior described above is unconditional given
its inputs (the data source's responses and the user's form entries), with
no flag gating any of it.

## Analytics

Not applicable: none of the three given sources contain an analytics or
event-tracking call.

## Privacy

- **Data collected**: `BucketsTopic` and `BucketsDataSource` handle
  whatever bucket `name`/`description` and table `name` the user types
  into the create/settings forms, plus the server-assigned `id`,
  `ecosystemId`, `kind`, `sqlTableName`, `createdAt`, and `updatedAt`
  values `Bucket`/`BucketTable` decode; none of it is inherently
  distinguished as sensitive by these sources.
- **Storage**: None of the three given sources persist anything to disk,
  a database, or `UserDefaults`; `Bucket`/`BucketTable` values and the
  `FormState` values built from them (documented in the related HTDV
  Engine recipe) exist only in memory for the lifetime of the loaded
  level/detail.
- **Transmission**: `BucketsDataSource`'s nine operations transmit
  whatever a concrete implementation does internally (not among the given
  sources); none of the three given sources performs a network call
  directly or applies any encryption, redaction, or transformation to the
  values before handing them to `dataSource`.
- **Retention**: Not applicable at this layer — how long a bucket, a
  table, or their `description`/`name` text is retained is a server-side
  policy outside these three sources; nothing here defines a
  client-side expiry or cache.

## Logging

Not applicable: none of the three given sources make a logging call (no
`import os`, no `Logger`, no `print` appears in any of them). A failure
surfaces only as a thrown `HubError` as described under Behavioral
Requirements and Edge Cases; if a host wants to log it, that logging
happens outside these sources.

## Platform Notes

- **SwiftUI**: A SwiftUI host would keep `BucketsDataSource`,
  `BucketsModels`, and `BucketsTopic`'s pure static helpers
  (`tableName(from:)`, `tableCount(_:)`) unchanged, since none of them
  depends on AppKit/UIKit or on `BucketsTopic`'s own `@MainActor` class,
  and would drive `createSpec`/`createTableSpec`/`settingsDetail`/`tableDetail`'s
  `FormSpec` values through the same `FormState` bridge described in the
  related HTDV Engine recipe's SwiftUI note, presenting the "New bucket"/
  "New table" forms with `.sheet` in place of `FormSheet.present`.
- **Compose**: Model `BucketsDataSource` as a suspend-function interface
  and `Bucket`/`BucketTable`/their create/update payloads as `@Serializable`
  Kotlin data classes with the same default-tolerant decoding (`kind`
  defaulting to `"custom"` via a custom deserializer or a default
  constructor parameter); reimplement `tableName(from:)` with
  `String.lowercase()` plus a manual scan keeping only ASCII letters and
  digits and collapsing runs of everything else to `"_"`, matching the
  no-leading/trailing-underscore behavior exactly; present the create
  forms as a `ModalBottomSheet`/`AlertDialog` in place of `FormSheet.present`.
- **React/Web**: Model `BucketsDataSource` as an async client interface
  returning the same shapes, with `Bucket` decoding applying the same
  `kind ?? "custom"` and optional-field defaults at the point a response
  is parsed; reimplement `tableName(from:)` as a small function that
  lowercases the input, iterates its code points keeping ASCII
  `a`-`z`/`0`-`9`, and collapses runs of other code points (including
  non-ASCII ones) into a single underscore with no leading or trailing
  underscore, exactly mirroring the Swift scan rather than using a
  locale-aware `String.replace`. Present the create/edit forms as a modal
  dialog in place of `FormSheet.present`, and keep the same
  precheck-then-server-conflict double guard for duplicate names.
- **AppKit / UIKit**: This is the source: `BucketsDataSource.swift`,
  `BucketsModels.swift`, and `BucketsTopic.swift` hold no AppKit/UIKit
  import of their own — `BucketsTopic` depends only on `Foundation` and the
  `AgenticToolkitHTDV` module (`HTDVItem`, `HTDVLevel`, `HTDVChild`,
  `HTDVCreateAction`, `FormSpec`/`FormSection`/`FormAction`/`FormDeleteAction`/
  `FormActions`), and presents its create sheets through the shared
  `FormSheet.present` rather than any AppKit/UIKit API of its own.
- **WinUI 3**: Model `BucketsDataSource` as a C# interface with nine
  `Task`-returning methods, backed by `HttpClient` and `System.Text.Json`
  for a concrete implementation (not among the given sources). Model
  `Bucket`/`BucketTable`/their create/update payloads as C# records with
  `[JsonPropertyName]` attributes; give `Bucket` a custom `JsonConverter`
  (or a `[JsonConstructor]` with nullable parameters) so a missing `kind`
  defaults to `"custom"` and a missing `metadata`/`createdAt`/`updatedAt`
  defaults to `null`, and expose `Description`/`IsBuiltIn` as computed
  read-only properties exactly mirroring `Bucket.description`/`isBuiltIn`.
  Reimplement `tableName(from:)` with `char.IsAsciiLetterOrDigit` and a
  `StringBuilder`, appending `'_'` only when a pending-separator flag is
  set and the builder is non-empty — reproducing the no-leading/trailing-
  underscore behavior exactly, including that a non-ASCII character (an
  accented letter, a CJK character) is a separator, not a candidate for
  transliteration. Use a `ContentDialog` (or a `TeachingTip`-hosted form)
  in place of `FormSheet.present` for the "New bucket"/"New table" flows,
  and compare names with `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)`
  in place of `caseInsensitiveCompare`, keeping the same
  precheck-then-server-conflict double guard for both buckets and tables.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Buckets/` |

## Design Decisions

**Decision**: `createSpec`'s and `createTableSpec`'s save actions both
check for a duplicate name against a freshly fetched list *before* calling
`create`/`createTable`, and also catch an `HubError.conflict` the create
call itself might throw, re-throwing it as the identical duplicate-name
message either way.
**Rationale**: The precheck-then-create sequence has an unavoidable
check-then-act window — nothing in these three sources locks the ecosystem
between the list read and the create write — so a second, concurrent
create for the same name can still reach the server after the precheck
passed. Catching the server's own conflict response and re-mapping it to
the same user-facing message means a caller sees one consistent duplicate-
name error regardless of which guard actually caught it, rather than
surfacing a raw conflict detail from the second path.
**Approved**: pending

**Decision**: `createTableSpec`'s and `tableDetail`'s `"name"` field is
declared `isRequired: false` at the `FormTextField` level, and emptiness is
instead checked explicitly inside each save action with the message
`"Every table needs a name."`, unlike `createSpec`/`settingsDetail`'s
`"name"` field, which is `isRequired: true` and relies on the Forms
subsystem's own generic `"<label> is required"` validation.
**Rationale**: Per the source's own comment on `createTableSpec`'s save
action deriving a SQL name, this file needs to distinguish "no name at all"
from "a name that derives no usable SQL identifier" — two failure messages
the generic Forms required-field check cannot produce — so it takes over
required-ness checking for this one field rather than delegating it, even
though `createSpec`'s save action never needed to.
**Approved**: pending

**Decision**: `settingsDetail`'s save action performs no client-side
duplicate-name lookup before calling `update(id:_:)`, unlike `createSpec`'s
save action, which lists existing buckets first.
**Rationale**: The source does not state why; the observable effect is
that renaming a bucket to a name already in use is caught only by the
server's `HubError.conflict` response, one network round trip later than
the create path's precheck. Documented here as a real asymmetry between
the two forms, not smoothed over, since a port that unifies the two code
paths would otherwise silently add a precheck the original settings form
never had.
**Approved**: pending

**Decision**: `BucketsTopic.tableName(from:)` treats every non-ASCII
scalar as a separator rather than attempting any transliteration (for
example, folding an accented Latin letter to its unaccented form).
**Rationale**: The function's contract, per its own doc comment, is to
produce a valid SQL identifier; ASCII `a`-`z`/`0`-`9` is a safe, universally
valid identifier character set for that purpose, and folding accented or
CJK characters into their nearest ASCII equivalent would require a
transliteration table this file does not have and does not attempt — the
tradeoff is that visually similar names in different scripts, or an
accented and unaccented version of the same word, can either collide on
the same derived SQL name or both derive the empty string, depending on
how many ASCII characters survive.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |

Notes: unit-test-coverage passes because `BucketsTopicTests.swift` carries
meaningful, behavior-specific assertions for every level, form, and error
path described above — 15 test methods, including the decode-defaults,
table-name-derivation, and duplicate-rejection paths — though the
server-`HubError.conflict` fallback branches (`create-bucket-conflict-fallback`,
`create-table-conflict-fallback`) are exercised only by inspection of the
source's `catch` blocks, not by a dedicated test, per Conformance Test
Vectors 011 and 021. separation-of-concerns passes because all three given
sources import only `Foundation` (plus `AgenticToolkitHTDV` for the HTDV/
Forms types) and hold no AppKit/UIKit dependency of their own.
explicit-error-handling passes because every `throws` boundary in these
three sources is caught and converted into an explicit `HubError` (via a
specific re-mapping or `HubError.wrap`), per
`every-other-thrown-error-is-wrapped-not-swallowed`. error-recovery fails
because none of the three given sources retries a failed operation or
backs off — a failed `list`/`get`/`create`/etc. call is reported once and
left to whatever caller invoked `child`/a save action (the HTDV
Engine recipe's `HTDVController.retry()`/`FormState.save()` re-invocation
lives one layer up, outside these three sources) to decide what happens
next. data-integrity passes because both create-and-edit paths validate
before writing — case-insensitive duplicate names, a derived-SQL-name
usability check, and a required-name check — and the custom `Bucket`
decoder defensively defaults missing `kind`/`metadata`/`createdAt`/
`updatedAt` rather than failing decode outright.
error-response-handling passes because `BucketsTopic` explicitly branches
on the two `HubError` cases it can act on (`notFound`, `conflict`) and
uniformly wraps every other case for the caller to display via
`HubError.message` (out of these given sources), rather than leaving any
case unhandled. no-hardcoded-strings fails because every user-facing
string these sources produce — labels, sublabels, validation messages,
and delete confirmation text — is a hardcoded English literal with no
localization key, per Localization above. input-sanitization passes
because `tableName(from:)` reduces arbitrary user input to a
character set restricted to ASCII letters, digits, and single-underscore
separators before it is ever posted as `sqlTableName`, and every save
action trims and length-checks (for emptiness) the raw name before use —
though see the open question on the derived name's maximum length under
Edge Cases.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
