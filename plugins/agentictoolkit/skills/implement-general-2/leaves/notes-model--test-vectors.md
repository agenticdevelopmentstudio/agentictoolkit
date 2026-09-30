<!-- leaf: implement-general-2/notes-model--test-vectors · source: notes-model.md -->

# NotesModel

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| notes-model-001 | markdownnotestorage-note-mapping | `insertNote(Note(content: "# Groceries\n\nMilk"))`, then `fetchAllNotes()` | The returned note's `id` matches the inserted id, `title == "Groceries"`, `content == "# Groceries\n\nMilk"` (`insertRoundTrips`) |
| notes-model-002 | markdownnotestorage-title-never-written | `insertNote(Note(content: "# Groceries\n\nMilk"))` | The stored document's frontmatter is empty; no `title` key is ever written (`derivedTitleIsNotStored`) |
| notes-model-003 | markdownnotestorage-frontmatter-ownership, markdownnotestorage-pin-claim-rule | Insert an unpinned note, `updateNote` with `isPinned = true`, then again with `isPinned = false` | Frontmatter is empty before the pin, holds a `pinned` fence while pinned, and is empty again after the unpin (`pinRoundTrips`) |
| notes-model-004 | markdownnotestorage-update-atomicity | 30 tasks each call `updateNote(seed)` (a no-op content revert) racing 30 tasks each appending `"\|index"` to the same document's `ownerID` via `store.mutateDocument` | Every one of the 30 `ownerID` marks survives in the final document (`updateNoteIsAtomicAgainstAnotherWriter`) |
| notes-model-005 | markdownnotestorage-update-missing-throws | `updateNote(note)` for a note never inserted | The call throws (`updateOfMissingNoteThrows`) |
| notes-model-006 | markdownnotestorage-note-mapping | `store.createDocument(content:, markers: [.note], id: "srv_1")` (a non-UUID id), then `fetchAllNotes()` | The returned list is empty — the non-UUID document is skipped, not crashed on (`serverIdsAreSkipped`) |
| notes-model-007 | markdownnotestorage-pin-claim-rule | `store.createDocument` with `"---\npinned: true\nlayout: post\n---\n# Groceries\n\nMilk"` (a foreign, never-owned `pinned` key), then `fetchAllNotes()` | `note.isPinned == false`; `note.content` still contains `"pinned: true"` untouched (`foreignPinDoesNotPin`) |
| notes-model-008 | markdownnotestorage-pin-release-rule | Pin a note, then in one `updateNote` call set `content` to `"---\npinned: true\n---\n# Groceries\n\nMilk\nBread"` (a hand-typed fence) and `isPinned = false` | The hand-typed `"pinned: true"` line survives byte-for-byte; `ownedFrontmatterKeys(forDocument:)` is empty afterward (`editingTheTextReleasesOwnership`) |
| notes-model-009 | note-title-derivation | `store.createDocument(content: "---\ntitle: 42\n---\n# Groceries\n\nMilk")`, then `fetchAllNotes()` | `note.title == "Groceries"` — a numeric frontmatter title falls through to the body line (`numericFrontmatterTitleFallsThrough`) |
| notes-model-010 | notefolder-tree-cycle-safety | `NoteFolder.tree` with edges `a → b → c → a` (a 3-node cycle, no true root) | The returned `roots` array is not empty — the cycle degrades to treating all three categories as roots (`testACycleInBadDataTruncatesRatherThanHanging`) |
| notes-model-011 | notesmanager-storage-issue-order | 24 `createNote` calls, then 24 concurrently-issued `togglePin` tasks against a storage double that dwells 50ms per call and records arrival order | `storage.peakConcurrency == 1`; `storage.updateArrivals` equals the exact order the 24 tasks were issued in (`testStorageWritesRunOneAtATimeInIssueOrder`) |
| notes-model-012 | notesmanager-failure-surface, notesmanager-create-rollback | `createNote(content:)` against a storage double whose `insertNote` always throws | Returns `nil`; `manager.storageFailure?.operation == .create`; `manager.notes` stays empty (`testAFailedCreateIsRecordedAndTheNoteIsNotListed`) |
| notes-model-013 | notesmanager-markdown-store-accessor | `NotesManager(storage: MarkdownNoteStorage(store:))` versus `NotesManager(storage:)` with a `NoteStorage` that is not `NoteTaxonomyProviding` | `markdownStore` returns the same `MarkdownStore` instance in the first case, `nil` in the second (`NotesManagerMarkdownStoreTests`) |
