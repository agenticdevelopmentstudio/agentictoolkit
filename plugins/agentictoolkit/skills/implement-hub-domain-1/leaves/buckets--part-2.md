<!-- leaf: implement-hub-domain-1/buckets--part-2 · source: hub-domain-buckets.md -->

# Hub Domain: Buckets — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/buckets--part-2#<slug>`):

- `topic-identity` MUST
- `topic-actor-confinement` MUST
- `table-name-derivation-is-nonisolated-and-pure` MUST
- `table-name-of-unusable-input-is-empty-string` MUST
- `table-count-pluralization` MUST
- `child-dispatch-by-rail-path-depth` MUST
- `missing-bucket-yields-empty-not-error` MUST
- `buckets-list-level-shape` MUST
- `bucket-level-shape` MUST
- `tables-of-bucket-refetches-the-whole-ecosystem` MUST
- `tables-level-shape` MUST
- `create-bucket-form-fields` MUST
- `create-bucket-precheck-rejects-case-insensitive-duplicate` MUST
- `create-bucket-conflict-fallback` MUST
- `create-bucket-empty-description-becomes-nil-metadata` MUST
- `settings-form-fields-and-seed-values` MUST
- `settings-form-conflict-fallback-without-a-precheck` MUST
- `settings-form-delete-gated-by-built-in` MUST
- `create-table-form-field-is-not-marked-required` MUST
- `create-table-requires-a-non-empty-trimmed-name` MUST
- `create-table-rejects-a-name-with-no-usable-characters` MUST
- `create-table-duplicate-check-is-by-name-or-derived-sql-name` MUST
- `create-table-conflict-fallback` MUST
- `table-detail-shape` MUST
- `table-detail-save-updates-name-only` MUST
- `table-detail-delete` MUST
- `every-other-thrown-error-is-wrapped-not-swallowed` MUST

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

