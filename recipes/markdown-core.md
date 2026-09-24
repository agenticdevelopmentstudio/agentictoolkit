---
id: 11f7a665-60e9-42df-853c-fe4de3af0fd8
title: MarkdownCore
domain: agentictoolkit://recipes/markdown-core
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The local SQLite/GRDB mirror and REST outbox for adh's content.markdown family
  — schema, sync projection, document lifecycle, taxonomy, and timestamp normalization.
platforms:
- swift
- macos
- ios
tags:
- markdown
- sqlite
- grdb
- sync
- offline
- taxonomy
- persistence
depends-on:
- agentictoolkit://recipes/adh-offline-sync-client
related: []
references:
- packages/apple/AgenticToolkit/Markdown/MarkdownSchema.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Markdown/MarkdownProjection.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Markdown/MarkdownStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Markdown/MarkdownTaxonomy.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Markdown/MarkdownTimestamp.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Markdown/MarkdownRemoteWriter.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

### Document Lifecycle & Outbox

- **tenancy-ids-required**: `MarkdownStore.init` MUST take a customer id and an ecosystem id with no defaults, since an empty string is a value the schema can store, not an absence the store should silently substitute.
- **db-path-shared-token**: The default database path MUST resolve under one token-named directory rather than a name derived from the token's display form, so this store and any other consumer of the same token agree on one SQLite file and its WAL state.
- **create-enqueues-payload**: `createDocument` MUST, in one write transaction, insert the row, add each requested marker row, and enqueue a create operation whose payload carries content and marker flags only — category, tags, and title are never included, since taxonomy rides its own outbox mutations and title is server-derived.
- **list-skips-unreadable-rows**: The document-list read path MUST skip and log a row whose timestamp cannot be parsed rather than throwing, on the stated reasoning that throwing on a list would remove every other row from the screen; the single-document read path MUST throw for the same condition when fetching one row by id.
- **update-refuses-authored-drift**: `updateDocument` MUST throw, naming the field and the correct method, if the row being written disagrees with the stored visibility, stage, or public route, and `updateRefusesVisibilityDrift`/`updateRefusesRouteDrift`/`updateRefusesStageDrift` confirm each field is checked.
- **update-payload-is-content-only**: The shared update path MUST enqueue an update operation whose payload carries only content, and `updatePayloadCarriesContentOnly`/`titleIsNeverQueued` confirm the server-derived title is never part of an outgoing payload.
- **publish-invariant**: `publishDocument` MUST refuse an empty route and otherwise set visibility and route together in the same update, and `publishSetsBothHalvesOfTheInvariant`/`publishRefusesABlankRoute` confirm both halves of the invariant move together.
- **delete-is-idempotent**: `deleteDocument` MUST treat a missing id as success rather than throwing not-found — the one lifecycle method where idempotency outranks fail-fast, since a retried drain or pull can legitimately call delete on a document already gone.
- **delete-tombstones-both-flags**: `deleteDocument` MUST set both delete columns together on the document and on every one of its marker rows, and `deleteSetsBothFlags` confirms both land in one write.
- **delete-drops-undelivered-create**: `deleteDocument` MUST drop a still-unclaimed pending create/delete pair entirely rather than enqueuing a delete, since adh never learned of a document whose create has not yet drained, and `deleteCancelsAPendingCreate`/`deleteQueuesADeleteOnceTheCreateHasDrained` confirm the two cases.
- **outbox-order-is-sequence**: The pending-operations read MUST order by the dedicated sequence column rather than a creation timestamp, which ties within a millisecond, or the operation id, whose sort order is effectively random, and `queueIsOrderedBySequenceNotTimestamp` confirms sequence order is what the drain honors.
- **outbox-column-corruption-signal**: The pending-operations read MUST throw a typed error rather than defaulting a value for an unreadable intent, payload, or timestamp column, since `MarkdownStore` is the sole writer of these columns and an unreadable value can only mean on-disk corruption.
- **opposing-intents-cancel**: The enqueue path MUST cancel a still-pending opposing operation outright rather than merging it in place, and `opposingIntentsCancelInsteadOfMergingInPlace`/`cancellingLeavesOneOpPerPair` confirm exactly one operation per pair survives — correct only because sends are idempotent and the newest instruction always drains last.
- **update-folds-into-pending-create**: The enqueue path MUST fold a queued update into a still-unclaimed pending create for the same document rather than adding a second operation, and `updateMergesIntoPendingCreate`/`updatesCoalesce` confirm the fold.
- **drain-reads-remote-id-live**: `drainRemoteQueue` MUST re-read a document's remote id immediately before sending each operation rather than trusting a batch snapshot, since an update queued behind its own create may only acquire that id partway through the drain, and `drainAdoptsTheServerMintedID` confirms the id is picked up.
- **drain-preserves-order-on-failure**: `drainRemoteQueue` MUST release the failing operation's claim and stop rather than skip ahead when the writer throws, so strict sequence order is preserved across retries, and `drainKeepsRejectedOps` confirms a rejected operation remains queued.
- **drain-clears-stale-claims-first**: `drainRemoteQueue` MUST clear every outstanding claim before reading pending operations, on the stated reasoning that a claim still standing when a drain begins can only be a pass that was killed mid-send, never a pass genuinely still in flight.
- **drain-mutual-exclusion**: one drain at a time is a caller precondition that `drainRemoteQueue`'s doc comment states; the store does not enforce it (no actor isolation, lock, or semaphore). Two concurrent calls on one store would each clear every claim, read their own snapshot of pending operations, claim the same unclaimed operation, and send it to adh twice.

### Taxonomy

- **cycle-refusal**: `addCategoryEdge` MUST refuse an edge that would close a cycle, walking downward from the child through a recursive descendant query scoped to the ecosystem before inserting, and `cycleIsRefused`/`diamondIsAllowed` confirm a genuine cycle is refused while a legitimate diamond shape is allowed.
- **revive-on-conflict**: `addCategoryEdge`, the shared item-assignment path backing both category and keyword assignment, and `createKeyword` MUST revive a tombstoned row on conflict rather than leaving a second, permanently hidden duplicate, and `tombstonedKeywordIsRevived`/`reassigningACategoryRevivesTheTombstonedRow`/`readdingACategoryEdgeRevivesTheTombstonedRow` confirm the revival.
- **no-phantom-mutation-on-existing-live-row**: The same revive-on-conflict update MUST be a no-op against a row that is already live, so re-adding an edge, assignment, or keyword that already exists stages no mutation into the taxonomy's own outbox, and `duplicateEdgeDoesNotStagePhantomMutation`/`duplicateCategoryAssignmentDoesNotStagePhantomMutation`/`duplicateKeywordAssignmentDoesNotStagePhantomMutation` confirm zero staged rows.
- **duplicate-label-refusal**: `createKeyword` MUST throw a duplicate error only when the label is held by a still-live keyword, and `duplicateKeywordThrows` confirms a live duplicate is refused while `tombstonedKeywordIsRevived` confirms a tombstoned one is not.
- **assignment-requires-live-document-and-owner**: The item-assignment path MUST throw not-found for a missing or already-deleted document, or a missing category or keyword owner, before staging an assignment, and `assignCategoryRefusesAMissingDocument`/`assignCategoryRefusesADeletedDocument`/`assignKeywordRefusesAMissingKeyword` confirm each precondition.
- **category-delete-cascades-edges-and-items-not-documents**: `deleteCategory` MUST tombstone the category row itself plus every edge naming it and every item filing a document under it, while leaving the documents themselves untouched, and `deletingAParentCategoryRemovesItsEdges`/`deletingACategoryLeavesItsDocumentsAlone` confirm the scope of the cascade.
- **unassign-and-remove-edge-are-idempotent**: `unassignCategory` and `removeCategoryEdge` MUST be no-ops — stage nothing, throw nothing — when the assignment or edge is already gone, and `unassigningANeverAssignedCategoryIsANoOp`/`removingANeverAddedEdgeIsANoOp` confirm both.
- **note-count-is-direct-not-transitive**: `categoryNoteCounts` MUST count only direct membership, never transitively through child categories, matching Apple Notes' own folder-badge semantics, per `categoryNoteCountsIsDirectNotTransitive`.
- **taxonomy-rides-generic-outbox**: Category and keyword mutations MUST stage their pushable fields onto the generic sync outbox in the same transaction as the local write, unlike `MarkdownStore`'s document mutations, which use the dedicated markdown outbox instead — taxonomy and documents push through two different queues by design.

## Appearance

Not applicable — this is a local SQLite persistence and sync-outbox layer, not a visual component.

## States

Not applicable — this is a local SQLite persistence and sync-outbox layer, not a visual component.

## Accessibility

Not applicable — this is a local SQLite persistence and sync-outbox layer, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| markdown-core-001 | delete-tombstones-both-flags | `deleteDocument` on a live document | Both delete columns set on the document row and every marker row (`deleteSetsBothFlags`) |
| markdown-core-002 | update-refuses-authored-drift | `updateDocument` called with visibility changed from the stored row | Throws the dedicated-intent error naming the visibility field (`updateRefusesVisibilityDrift`) |
| markdown-core-003 | publish-invariant | `publishDocument` called with an empty route | Throws the inconsistent-publication error (`publishRefusesABlankRoute`) |
| markdown-core-004 | outbox-order-is-sequence | Operations enqueued out of creation order but in sequence order | The pending-operations read returns them in sequence order (`queueIsOrderedBySequenceNotTimestamp`) |
| markdown-core-005 | opposing-intents-cancel | `publishDocument` followed by `unpublishDocument` before the queue drains | Exactly one operation remains queued (`opposingIntentsCancelInsteadOfMergingInPlace`, `cancellingLeavesOneOpPerPair`) |
| markdown-core-006 | cycle-refusal | `addCategoryEdge` where the proposed parent is already a descendant of the proposed child | Throws the category-cycle error (`cycleIsRefused`); a diamond shape is still allowed (`diamondIsAllowed`) |
| markdown-core-007 | revive-on-conflict | `createKeyword` for a label whose only holder is tombstoned | The tombstoned row is revived, not duplicated (`tombstonedKeywordIsRevived`) |
| markdown-core-008 | number-range-clamping | A pulled JSON number outside the 64-bit signed integer range | The value is stored as a lossy double rather than trapping (`oversizedNumbersDoNotTrap`) |
| markdown-core-009 | unencodable-value-throws | A pulled array or object value bound for a scalar column | Throws rather than binding a null (`unencodableValueThrows`) |
| markdown-core-010 | postgres-form-repair | `MarkdownTimestamp.date` given a Postgres wire-form timestamp with a space separator and a two-digit offset | Parses to the same instant the writer would produce for the ISO-8601 spelling (`postgresFormsNormalise`) |

## Edge Cases

- `documents(marker:)` and `document(id:)` deliberately disagree on how an unreadable timestamp is handled — the list skips and logs the row, the single fetch throws — so a caller reading the same corrupt row through the two paths sees different behavior by design.
- `document(from: Row)` reads the tombstone-timestamp column through a lenient conversion that becomes `nil` on an unparseable value, unlike the required `createdAt`/`updatedAt` columns, which throw; every code path that reaches this conversion already filters to rows the write-time dual-flag invariant keeps non-tombstoned, so the lenient path has no reachable corrupt input in this component as given.
- `mutateDocument`'s merge closure may call back into the store without deadlocking, because the underlying database is reentrant, but a nested write's changes are silently overwritten by the enclosing whole-row write that follows it — the method's own doc comment calls this out as a hazard for the caller to avoid, not a defect in the method.
- `MarkdownRemoteWriter` has no implementation among these six files; its own doc comment states nothing implements it yet, since this component holds no adh credentials to send with.
- Calling `deleteDocument` twice for the same id, or once after the row has already been purged by `truncate`, succeeds both times rather than throwing on the second call.
- Purging `notes`, `docs`, or `papers` alone succeeds when each has no rows; purging `content.markdown` alone while any marker table still has rows is refused regardless of whether that table is empty of *unrelated* rows.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `customerID` | `String` | none — required | Tenant-scoping value bound into every row; the store never substitutes a default, since an empty string is a value, not an absence. |
| `ecosystemID` | `String` | none — required | Same as `customerID`, scoping every row within one ecosystem. |
| `path` | file path `String` | `defaultPath(inHome:token:)`, resolving under one token-named directory | Overridable per store initialization; the default keeps this store and any other consumer of the same token on one SQLite file and its WAL state. |
| `token` | `String` | caller-supplied | Selects the token-named directory the default path resolves under. |

## Deep Linking

Not applicable: this component defines no URL scheme of its own; `publicRoute` on a document names a path on adh's public web surface once published, not a path this app opens.

## Localization

Not applicable: no user-facing string originates in these six files — every error surface is a typed Swift enum for the caller to interpret and present, not display text, and none conforms to a localized-description protocol.

## Accessibility Options

Not applicable: Reduce Motion, Increase Contrast, and Differentiate Without Color are rendering-time display options; this component has no rendering path for them to affect.

## Feature Flags

Not applicable: no flag lookup appears anywhere across the six source files that make up this component.

## Analytics

Not applicable: no analytics or event-tracking call appears anywhere across the six source files; the only instrumentation present is the log call documented under Logging.

## Privacy

- **Data collected**: Every row is scoped by a required customer id and ecosystem id, plus the document's own content and frontmatter text, which is arbitrary user-authored Markdown, not just metadata.
- **Storage**: Local only, in one SQLite file under a per-token home directory; nothing in these six files encrypts the file at rest.
- **Transmission**: None from within this component today — `MarkdownRemoteWriter` has no concrete implementation here, per its own doc comment stating nothing implements it yet because this component holds no adh credentials; outbound activity is limited to maintaining the local outbox queue, never a network call this component makes itself.
- **Retention**: A deleted document is retained as a tombstoned row, not physically removed; only `truncate` and the identity-state purge physically delete rows, and the latter is scoped to identity-tracking tables, never document content.

## Logging

Subsystem: the app's bundle identifier, or the literal string `nil` when none is set | Category: `MarkdownStore`

| Event | Level | Message |
|-------|-------|---------|
| A listed document row has an unreadable timestamp | error | Names the marker table and the underlying parse error, both marked public for the system log |

`MarkdownStore.logger` is spelled out directly through the platform logging type rather than a shared logging protocol, because this target does not link the framework that protocol lives in.

## Platform Notes

- **SwiftUI**: Not a view; a SwiftUI screen observes this store through an observable wrapper around `MarkdownStore`, never by subclassing it or reaching into the underlying database directly.
- **Compose**: The Kotlin equivalent would pair a Room- or SQLDelight-backed store with the same schema shape, exposed to Compose through a view-model and observable state, not observed directly.
- **React/Web**: The web equivalent has no local SQLite; the nearest analog is an IndexedDB-backed store with the same pull-only/outbox split, exposed to React through a hook, not a component prop.
- **AppKit / UIKit**: Same as SwiftUI — this store is UI-framework-agnostic; an AppKit or UIKit controller would hold a reference and observe it through the same wrapper any other consumer uses, never a delegate protocol specific to this component.
- **WinUI 3**: A Windows port would replace the GRDB-backed database with a `Microsoft.Data.Sqlite`-backed store, replace `MarkdownRemoteWriter.send` with `HttpClient` calls encoding payloads through `System.Text.Json`, replace the per-token home directory with a folder under `Windows.Storage.ApplicationData`, run the drain as a `Task`, and expose document lists to XAML through an `ObservableCollection` with `INotifyPropertyChanged` rather than this store's plain array return values.

## Design Decisions

**Decision**: Keep the revive-on-conflict update's guard clause — reviving only a row whose delete column is set — so that re-adding an edge, assignment, or keyword that is already live changes no columns, rather than letting the upsert unconditionally rewrite the updated-at and ordering columns on every call.
**Rationale**: An unconditional update would stage a mutation into the taxonomy outbox on every idempotent re-add, since staging follows the count of rows the database engine reports as actually changed; the guard makes "already exists and live" distinguishable from "actually changed" at the SQL level instead of requiring a pre-read.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

Separation of concerns holds structurally: `MarkdownSchema` owns DDL and migration, `MarkdownProjection` owns the sync-mirror translation contract, `MarkdownStore` owns document and outbox lifecycle, and `MarkdownTaxonomy` extends the store for categories and keywords rather than folding taxonomy concerns into it — six files, four clear responsibilities, no circular reach between them. Unit test coverage holds: the four test files covering this component between them exercise nearly every requirement above by name, including the schema-drift self-check against the live table definitions. Explicit error handling holds: every failure surface in this component is a typed enum thrown to the caller, never a swallowed optional-try or a silently substituted default — the two real optional-try uses in the projection guard a validity check with a proper fallthrough, not a discarded failure. Idempotent operations hold for every lifecycle method examined except the one place idempotency is explicitly not wanted: `deleteDocument` treats a missing id as success by design, and the taxonomy's revive-on-conflict pattern makes re-adding an edge, assignment, or keyword a no-op. Data integrity is marked partial: the dual-flag delete-state normalization, the cycle and self-edge refusals, and the orphan-purge refusal are all real integrity guards, but `drain-mutual-exclusion` in Behavioral Requirements leaves serializing drains to the caller: two concurrent drains would send one outbox operation to adh twice, with nothing in this component to prevent it.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
