<!-- leaf: implement-general-1/markdown-core · source: markdown-core.md -->

**Rules** (cite as `implement-general-1/markdown-core#<slug>`):

- `table-set` MUST
- `marker-table-shape` MUST
- `document-column-checks` MUST
- `author-route-uniqueness` MUST
- `adh-source-uniqueness` MUST
- `self-edge-refusal` MUST
- `keyword-label-uniqueness` MUST
- `migration-sequence` MUST
- `frontmatter-owner-backfill` MUST
- `title-claim-release` MUST
- `outbox-shape-frozen` MUST
- `single-formatter-pair` MUST
- `millisecond-write-precision` MUST
- `postgres-form-repair` MUST
- `missing-offset-is-utc` MUST
- `formatter-thread-safety` MUST
- `pull-only-family` MUST
- `remote-id-remapping` MUST
- `partial-patch-delete-guard` MUST
- `delete-state-normalization` MUST
- `truthy-parsing` MUST
- `frontmatter-claim-release` MUST
- `number-range-clamping` MUST
- `frontmatter-json-guard` MUST
- `unencodable-value-throws` MUST
- `orphan-purge-refusal` MUST
- `required-column-defaults` MUST
- `schema-drift-guard` MUST

# MarkdownCore

## Overview

MarkdownCore is the local persistence and outbound-sync layer for adh's `content.markdown` resource family. Six files divide the work: `MarkdownSchema` owns the SQLite DDL and migrations; `MarkdownProjection` translates pulled rows into and out of that schema as a `SyncMirrorProjection`; `MarkdownStore` owns document creation, update, lifecycle (publish/unpublish/finalize/definalize/delete), and a dedicated outbox queue; `MarkdownTaxonomy` extends the store with categories, category edges, and keywords; `MarkdownTimestamp` is the one place a column becomes a `Date` and back; and `MarkdownRemoteWriter` declares — without yet implementing — the contract a host uses to actually send a queued operation to adh.

A `MarkdownStore` owns one `BoundedDatabase` (SQLite via GRDB) holding `markdown` rows plus three marker tables (`notes`, `docs`, `papers`) and a taxonomy of `categories`/`category_edges`/`category_items`/`keywords`/`keyword_items`. Local writes land synchronously in the database and enqueue a row in the local-only `_markdown_outbox` table; `drainRemoteQueue` later sends each queued operation through a caller-supplied `MarkdownRemoteWriter` in strict `seq` order. Remote pulls arrive through the generic `SyncMirrorProjection`/`GRDBSyncStore` engine via `MarkdownProjection`, the only place adh's rows are translated into this schema's columns; `content.markdown`, `content.notes`, `content.docs`, and `content.papers` are pull-only, while taxonomy resources ride the same generic push path documents deliberately do not.

## Behavioral Requirements

### Schema & Migration

- **table-set**: The schema MUST define exactly the tables named in `MarkdownSchema.tables` (`markdown`, `notes`, `docs`, `papers`, `categories`, `category_edges`, `category_items`, `keywords`, `keyword_items`), and `MarkdownProjection.resources`/`syncResources` MUST derive from that same array rather than a hand-copied list, so the sync engine's resource set cannot drift from the DDL.
- **marker-table-shape**: `notes`, `docs`, and `papers` MUST share one generated shape from `markerTable(_:)`: a `UNIQUE(ecosystem_id, id)` constraint plus a partial unique index scoped to `markdown_id` where `deleted_at IS NULL`, so a document may hold at most one live marker row of each kind.
- **document-column-checks**: The `markdown` table MUST enforce `visibility IN ('private','public')`, `stage IN ('draft','final')`, `owner_kind IN ('customer','organization')`, and `is_deleted IN (0,1)` as CHECK constraints, so an invalid enum value is a write-time SQL failure rather than a value the reader must tolerate.
- **author-route-uniqueness**: The `markdown` table MUST enforce a partial unique index over customer and `public_route` scoped to non-null, non-deleted rows, so two live documents from the same customer can never publish the same route.
- **adh-source-uniqueness**: The `markdown` table MUST enforce a partial unique expression index on the `adh_source` key extracted from `frontmatter`, so a document already linked to one adh id cannot be duplicated under a second local row.
- **self-edge-refusal**: `category_edges` MUST enforce a CHECK constraint refusing `parent_id` to equal `child_id`, so a category cannot become its own parent independent of any application-level cycle check.
- **keyword-label-uniqueness**: `keywords` MUST enforce a unique constraint over customer, ecosystem, and label together, so a label is unique per author within one ecosystem.
- **migration-sequence**: `MarkdownSchema.migrator()` MUST apply its five migrations, `markdown-v1` through `markdown-v5-outbox-claim`, in order through `DatabaseMigrator`, and `migrate(_:)` MUST turn on foreign-key enforcement before migrating, so enforcement is active before any migrated row is written.
- **frontmatter-owner-backfill**: The `markdown-v3-frontmatter-owner` migration MUST claim the `pinned` frontmatter key for every document that already carries it on disk, so a database upgraded from an earlier version does not silently show `pinned` as unowned.
- **title-claim-release**: The `markdown-v4-release-title-claims` migration MUST delete every stale `title` claim, and `migratingAnExistingDatabaseReleasesEveryTitleClaim` confirms an upgraded database ends with no `title` claim outstanding.
- **outbox-shape-frozen**: The `_markdown_outbox` table's original shape MUST stay frozen; ordering was added by a separate `seq` column in `markdown-v2-outbox-order` and in-flight tracking by a separate `claimed_at` column in `markdown-v5-outbox-claim`, rather than by altering the original columns.

### Timestamp Normalization

- **single-formatter-pair**: Every column-to-date conversion in this component MUST go through `MarkdownTimestamp`'s one writer/reader pair rather than an ad hoc formatter, because two formatters that disagree by a fractional second or a `Z` produce rows that sort against each other in the wrong order under an `updated_at` ordering.
- **millisecond-write-precision**: `MarkdownTimestamp.string` MUST write with millisecond precision and an explicit `Z`, so two edits inside the same second still order correctly against each other.
- **postgres-form-repair**: `MarkdownTimestamp.date` MUST fall back to a repair pass when the strict ISO-8601 formatters fail, turning a Postgres wire form — a space separator, a two-digit offset, a fraction of any length — into the shape the writer itself produces, and `postgresFormsNormalise` confirms the repair.
- **missing-offset-is-utc**: The repair pass MUST read a timestamp with no zone as UTC rather than the local time zone, matching every other value already in these columns.
- **formatter-thread-safety**: Access to the two `nonisolated(unsafe)` `ISO8601DateFormatter` statics MUST be serialized through one lock, since `ISO8601DateFormatter` publishes no thread-safety guarantee and `MarkdownStore`'s read path runs on a pool of concurrent readers.

### Sync Projection

- **pull-only-family**: `content.markdown`, `content.notes`, `content.docs`, and `content.papers` MUST be registered as pull-only resources, so a local edit to a document or its marker reaches adh only through `MarkdownStore`'s own outbox, never through the generic sync-push path.
- **remote-id-remapping**: `MarkdownProjection.upsert` MUST resolve an incoming row's id, and, for marker rows, its `markdown_id` foreign key, through the local remote-id table before writing, so a row adh identifies by its own minted id lands on the local row created before that id was known.
- **partial-patch-delete-guard**: `upsert` MUST reject a partial patch whose delete columns disagree with the row already on disk, and `partialPatchWithDisagreeingDeleteStateIsRefused`/`partialPatchNamingOneDeleteColumnLeavesTheOtherAlone` confirm a patch naming only one of the two delete columns leaves the other alone rather than being treated as a disagreement.
- **delete-state-normalization**: On a full-row `content.markdown` pull, `upsert` MUST derive one delete fact from both delete columns — a non-null tombstone timestamp wins over a falsy boolean flag — and `falsyIsDeletedBesideATombstoneStaysDeleted`/`deletedAtWithoutIsDeletedHidesTheRowEverywhere` confirm the row is hidden under either signal.
- **truthy-parsing**: `isTruthy` MUST treat Postgres's own truthy text spellings, case-insensitively, as true in addition to numeric one, since `stringIsDeletedIsTruthy` exercises a text-typed delete flag.
- **frontmatter-claim-release**: `upsert` MUST release only the frontmatter claims whose incoming value actually differs from what is stored, never a blanket release, so a pull that merely echoes back the app's own last write does not disown a key the app still owns.
- **number-range-clamping**: The column-encoding step MUST clamp an incoming JSON number to a 64-bit signed integer range and store an out-of-range number as a lossy double rather than trapping, since every JSON number decodes as a double and `oversizedNumbersDoNotTrap` exercises a value outside that range.
- **frontmatter-json-guard**: The column-encoding step MUST store a non-JSON `frontmatter` value by wrapping it as a JSON string literal rather than dropping it or erroring, because the JSON-extract expression index on that column would raise a malformed-JSON error on read and wedge the sync cursor permanently if the column ever held non-JSON text.
- **unencodable-value-throws**: The column-encoding step MUST throw for an array or object value it cannot encode to JSON text rather than binding a null, and `unencodableValueThrows` confirms the throw.
- **orphan-purge-refusal**: `truncate` MUST refuse to purge `content.markdown`, `content.categories`, or `content.keywords` while a dependent resource still holds rows and is not itself included in the same purge, and `partialFamilyPurgeIsRefused`/`wholeFamilyPurgeSucceeds`/`partialPurgeWithNoDependentRowsIsAllowed` exercise the three cases.
- **required-column-defaults**: Every required-with-no-default column MUST always be bound on `upsert` — a throwaway value on a partial patch that never lands on an existing row, or the real value on a full-row pull — so a column with no schema default can never be omitted from the write.
- **schema-drift-guard**: The projection's hand-maintained per-resource column lists MUST match `PRAGMA table_info` at runtime, and `columnListsMatchTheRealSchema`/`requiredColumnListsMatchTheRealSchema`/`nullableColumnListsMatchTheRealSchema` cross-check that the two cannot silently drift apart.

