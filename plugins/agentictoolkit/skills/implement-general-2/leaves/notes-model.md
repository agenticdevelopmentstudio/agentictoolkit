<!-- leaf: implement-general-2/notes-model · source: notes-model.md -->

**Rules** (cite as `implement-general-2/notes-model#<slug>`):

- `note-identity` MUST
- `note-fields` MUST
- `note-title-derivation` MUST
- `note-excerpt-derivation` MUST
- `note-untitled-sentinel` MUST
- `note-default-sort` MUST
- `note-factory` MUST
- `notefolder-value-semantics` MUST
- `notefolder-all-notes-sentinel` MUST
- `notefolder-tree-multi-parent` MUST
- `notefolder-tree-direct-counts` MUST
- `notefolder-tree-total-independent` MUST
- `notefolder-tree-cycle-safety` MUST
- `notefolder-tree-orphan-edges` MUST
- `notestorage-contract` MUST
- `notetaxonomyproviding-contract` MUST
- `markdownnotestorage-sendable` MUST
- `markdownnotestorage-note-mapping` MUST
- `markdownnotestorage-fetch-sort` MUST
- `markdownnotestorage-timestamps` MUST
- `markdownnotestorage-frontmatter-ownership` MUST
- `markdownnotestorage-pin-claim-rule` MUST
- `markdownnotestorage-pin-release-rule` MUST
- `markdownnotestorage-title-never-written` MUST
- `markdownnotestorage-strip-on-read` MUST
- `markdownnotestorage-update-atomicity` MUST
- `markdownnotestorage-update-missing-throws` MUST
- `markdownnotestorage-delete` MUST

# NotesModel

## Overview

`Note`, `NoteFolder`, `NoteStorage`, `NoteTaxonomyProviding`, `MarkdownNoteStorage`, and `NotesManager` are the model, persistence-protocol, and orchestration layer behind AgenticToolkit's Notes feature (`packages/apple/AgenticToolkit/macOS/Features/NotesWindow/`): a local, on-device notes store with no UI of its own. `Note` is an immutable-id value type whose title and excerpt are always derived from its markdown `content`, never stored. `NoteFolder` is the tree shape a folders pane displays, built from a flat category/edge read. `NoteStorage` is the abstract, `Sendable` four-method persistence seam `NotesManager` depends on; `MarkdownNoteStorage` is the concrete conformer that maps a note onto a `MarkdownStore` document, and is also the layer that owns the entire frontmatter-ownership contract for the one key it writes, `pinned`. `NotesManager` is the `@MainActor` object that owns the in-memory `[Note]` array, issues every storage call off the main actor in strict issue order, runs a per-note debounced autosave, and surfaces a failed read or write as a single `NotesStorageFailure`.

This is a different, unrelated contract from the web-side notes client documented in `agentictoolkit://recipes/hub-domain-notes` — that recipe's own text says as much: its notes are a backend content resource reached over a REST API, these are a local, on-device store reached through `NoteStorage`, and the shared name is a coincidence, not a shared contract.

## Behavioral Requirements

### Note

- **note-identity**: `Note` MUST be an `Identifiable`, `Equatable`, `Sendable` struct whose `id: UUID` is immutable (`let`).
- **note-fields**: `Note` MUST carry exactly `content: String`, `createdDate: Date` (immutable), `modifiedDate: Date`, and `isPinned: Bool` as its stored state; it MUST have no stored `title` field.
- **note-title-derivation**: `Note.title` MUST be computed on every access from `content` via `MarkdownText.deriveTitle(content)`, never stored, so it can never go stale against `content` between an edit and the next save.
- **note-excerpt-derivation**: `Note.excerpt` MUST be computed via `MarkdownText.deriveExcerpt(MarkdownText.excerptSource(content), frontmatterFrom: content)`, which MUST skip the line `title` was derived from so a heading used as the title is never repeated as the first line of the excerpt underneath it.
- **note-untitled-sentinel**: `Note.untitledTitle` MUST be `MarkdownText.untitled` itself, not a second string with the same text, so a comparison against it can never disagree with the markdown layer's own sentinel (`untitledSentinelIsShared`).
- **note-default-sort**: `Note.defaultSort` MUST order pinned notes before unpinned notes, and within each group by `modifiedDate` descending (`listingOrderMatchesDefaultSort`).
- **note-factory**: `Note.new(content:)` MUST create a note with a fresh `UUID`, `createdDate` and `modifiedDate` both set to the current `Date`, and `isPinned` false.

### NoteFolder

- **notefolder-value-semantics**: `NoteFolder` MUST be `Identifiable`, `Equatable`, `Hashable`, and `Sendable`, with `Hashable` an explicit, non-accidental conformance — an `NSOutlineView` bridges a Swift value lacking `Hashable` to a boxed object whose hash falls back to that box's own identity, so two differently-boxed-but-equal folders from two separate `reload()`s would hash unequally and `isItemExpanded(_:)`/`row(forItem:)` could never match one across a reload.
- **notefolder-all-notes-sentinel**: `id == ""` MUST be reserved for the synthetic "All Notes" root; `NoteFolder.tree(from:counts:edges:total:)` MUST never itself produce a node with an empty id, since every real category id is a lowercased UUID minted by `createCategory` (`testAllNotesIDIsEmptyAndIsAllNotesIsTrue`).
- **notefolder-tree-multi-parent**: `NoteFolder.tree` MUST build a category reachable from more than one parent once per parent, so it appears as an independent value under each parent rather than a shared reference (`testATwoParentNodeAppearsUnderBothParents`).
- **notefolder-tree-direct-counts**: Each built `NoteFolder.noteCount` MUST be the category's own direct count from `counts`, never a sum over its children; a parent's count MAY therefore be smaller than the sum of its children's counts (`testFolderCarriesItsDirectNoteCount`).
- **notefolder-tree-total-independent**: The caller MUST supply `total` separately (e.g. from `store.noteCount(marker: .note)`) rather than deriving the "All Notes" count from `counts.values.reduce(0, +)`, because a note filed under two categories would double-count that sum and an uncategorized note would be missed by it entirely (`testTotalIsIndependentOfADoubleCountedNote`).
- **notefolder-tree-cycle-safety**: `NoteFolder.tree` MUST bound every downward walk with a `visited` set of the ids already on the current path, so a cycle in the edge data truncates that branch instead of recursing forever; when every category lies on a cycle with no true root, `tree` MUST fall back to treating every category as a root rather than losing the graph entirely (`testACycleInBadDataTruncatesRatherThanHanging`).
- **notefolder-tree-orphan-edges**: `NoteFolder.tree` MUST ignore any edge whose parent or child id is not present in the supplied `categories` array.

### NoteStorage & NoteTaxonomyProviding

- **notestorage-contract**: `NoteStorage` MUST declare exactly four synchronous, throwing operations — `fetchAllNotes() throws -> [Note]`, `insertNote(_:) throws`, `updateNote(_:) throws`, and `deleteNote(id:) throws` — and MUST itself be `Sendable`, since `NotesManager` calls these methods from outside the main actor; the thread safety of the concrete storage is the conformer's own responsibility, stated as a precondition, not enforced by the protocol.
- **notetaxonomyproviding-contract**: A `NoteStorage` conformer MAY additionally conform to `NoteTaxonomyProviding` to expose its backing `store: MarkdownStore` for taxonomy (folder) queries; `NoteStorage` itself MUST NOT reference categories, so a storage backend with no taxonomy concept can conform to `NoteStorage` alone and simply not support folders.

### MarkdownNoteStorage

- **markdownnotestorage-sendable**: `MarkdownNoteStorage` MUST be `Sendable`; its only stored state is a `let store: MarkdownStore` (itself `@unchecked Sendable`) and a `static let` constant, so the conformance is sound as written with no additional synchronization.
- **markdownnotestorage-note-mapping**: `MarkdownNoteStorage` MUST represent a note as a markdown document carrying the `.note` marker, and `fetchAllNotes` MUST skip (via `compactMap`) any document whose `id` does not parse as a `UUID` rather than crashing on a force-unwrap — a document with a non-UUID id is server-authored and outside this UUID-keyed model's addressing scheme (`serverIdsAreSkipped`).
- **markdownnotestorage-fetch-sort**: `fetchAllNotes` MUST return its notes sorted by `Note.defaultSort` (pinned-first, then `modifiedDate` descending).
- **markdownnotestorage-timestamps**: `insertNote` MUST stamp the underlying document's `now:` and `createdAt:` parameters separately, from the note's `modifiedDate` and `createdDate` respectively, so a note's original creation date is preserved distinctly from its last-modified date rather than both collapsing onto one write timestamp.
- **markdownnotestorage-frontmatter-ownership**: `MarkdownNoteStorage` MUST record, per document, which frontmatter keys it itself wrote (`MarkdownStore.ownedFrontmatterKeys`/`ownedFrontmatterKeysByDocument`), and MUST use that recorded fact — never the key's value — to decide whether a `pinned` key found in a document's frontmatter reflects this app's own pin state or a foreign key a user or another tool wrote (`pinnedLiteralAgreesWithIsPinned`, and the class's own "MARK: - Ownership" block).
- **markdownnotestorage-pin-claim-rule**: `MarkdownNoteStorage` MAY claim (write and own) the `pinned` key only when it is currently absent from the document's frontmatter, or when writing the desired value would change no bytes of the document's content; it MUST NOT claim or rewrite a `pinned` key that already holds a different, foreign value or a differently-quoted/differently-styled equivalent value (`quotedPinnedValueIsLeftAlone`, `byteIdenticalPinnedValueIsClaimed`, `foreignPinDoesNotPin`).
- **markdownnotestorage-pin-release-rule**: Whenever `updateNote` finds the note's `content` differs from what this class last derived for it (the stored content with owned keys stripped), it MUST treat the entire frontmatter as released — the user edited the text — clearing the ownership record for that document before deciding whether to write `pinned` again in the same call (`editingTheTextReleasesOwnership`).
- **markdownnotestorage-title-never-written**: `MarkdownNoteStorage` MUST NOT write a `title` frontmatter key under any circumstance; a note's title is always derived from `content`, and a hand-typed `title:` fence MUST be left untouched, exactly like any other foreign frontmatter key (`savingANoteNeverWritesATitleKey`, `aHandTypedTitleKeyIsHonouredAndLeftInTheEditor`).
- **markdownnotestorage-strip-on-read**: `MarkdownNoteStorage` MUST strip only the frontmatter keys it owns from the text it exposes as `Note.content`; every other line — including a foreign `pinned:` key — MUST remain visible, in its original order, in that content (`foreignPinDoesNotPin`, `foreignFrontmatterSurvivesRead`).
- **markdownnotestorage-update-atomicity**: `updateNote` MUST perform its read, merge, and write as a single transaction (`MarkdownStore.mutateDocument`), not as separate read-then-write calls, so a concurrent writer's in-transaction append to the same document (e.g. to an unrelated field) survives an `updateNote` call on that document (`updateNoteIsAtomicAgainstAnotherWriter`); this buys atomicity, not ordering — two concurrent `updateNote` calls on the same note still resolve last-writer-wins over the whole note.
- **markdownnotestorage-update-missing-throws**: `updateNote` MUST throw when the note's id does not correspond to an existing document (`updateOfMissingNoteThrows`).
- **markdownnotestorage-delete**: `deleteNote(id:)` MUST remove the corresponding document from the store by delegating to `store.deleteDocument`.

