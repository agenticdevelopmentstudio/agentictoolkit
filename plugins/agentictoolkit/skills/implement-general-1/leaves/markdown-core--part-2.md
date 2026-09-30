<!-- leaf: implement-general-1/markdown-core--part-2 · source: markdown-core.md -->

# MarkdownCore — continued (part 2)

**Rules** (cite as `implement-general-1/markdown-core--part-2#<slug>`):

- `tenancy-ids-required` MUST
- `db-path-shared-token` MUST
- `create-enqueues-payload` MUST
- `list-skips-unreadable-rows` MUST
- `update-refuses-authored-drift` MUST
- `update-payload-is-content-only` MUST
- `publish-invariant` MUST
- `delete-is-idempotent` MUST
- `delete-tombstones-both-flags` MUST
- `delete-drops-undelivered-create` MUST
- `outbox-order-is-sequence` MUST
- `outbox-column-corruption-signal` MUST
- `opposing-intents-cancel` MUST
- `update-folds-into-pending-create` MUST
- `drain-reads-remote-id-live` MUST
- `drain-preserves-order-on-failure` MUST
- `drain-clears-stale-claims-first` MUST
- `cycle-refusal` MUST
- `revive-on-conflict` MUST
- `no-phantom-mutation-on-existing-live-row` MUST
- `duplicate-label-refusal` MUST
- `assignment-requires-live-document-and-owner` MUST
- `category-delete-cascades-edges-and-items-not-documents` MUST
- `unassign-and-remove-edge-are-idempotent` MUST
- `note-count-is-direct-not-transitive` MUST
- `taxonomy-rides-generic-outbox` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `customerID` | `String` | none — required | Tenant-scoping value bound into every row; the store never substitutes a default, since an empty string is a value, not an absence. |
| `ecosystemID` | `String` | none — required | Same as `customerID`, scoping every row within one ecosystem. |
| `path` | file path `String` | `defaultPath(inHome:token:)`, resolving under one token-named directory | Overridable per store initialization; the default keeps this store and any other consumer of the same token on one SQLite file and its WAL state. |
| `token` | `String` | caller-supplied | Selects the token-named directory the default path resolves under. |

## Privacy

- **Data collected**: Every row is scoped by a required customer id and ecosystem id, plus the document's own content and frontmatter text, which is arbitrary user-authored Markdown, not just metadata.
- **Storage**: Local only, in one SQLite file under a per-token home directory; nothing in these six files encrypts the file at rest.
- **Transmission**: None from within this component today — `MarkdownRemoteWriter` has no concrete implementation here, per its own doc comment stating nothing implements it yet because this component holds no adh credentials; outbound activity is limited to maintaining the local outbox queue, never a network call this component makes itself.
- **Retention**: A deleted document is retained as a tombstoned row, not physically removed; only `truncate` and the identity-state purge physically delete rows, and the latter is scoped to identity-tracking tables, never document content.

