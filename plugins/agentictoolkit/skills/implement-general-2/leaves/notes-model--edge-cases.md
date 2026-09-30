<!-- leaf: implement-general-2/notes-model--edge-cases · source: notes-model.md -->

# NotesModel

## Edge Cases

- An empty-content note (`Note.new(content: "")`) derives `Note.untitledTitle` (`MarkdownText.untitled`), never an empty string title (`blankTitleFallsBack`, `appCreatedNoteNeverGetsFrontmatter`).
- Writing `pinned` when the document's frontmatter already reads byte-identical to the value about to be written claims the key without mutating a single byte of content (`byteIdenticalPinnedValueIsClaimed`).
- A quoted foreign value the app would otherwise rewrite as an unquoted boolean — `pinned: "true"` — is left completely alone and never claimed, because rewriting it would change bytes that belong to the user (`quotedPinnedValueIsLeftAlone`).
- A frontmatter `title` written as a flow sequence (`title: [a, b]`), an empty string (`title: ""`), or a whitespace-only string (`title: "   "`) all fall through to the derived body-line title, exactly as `MarkdownText.deriveTitle` does for every other adh-authored document (`flowSequenceFrontmatterTitleFallsThrough`, `emptyFrontmatterTitleFallsThrough`, `whitespaceFrontmatterTitleFallsThrough`).
- A foreign frontmatter key unrelated to `pinned` (e.g. `author: mike`) survives a read and an unrelated no-op re-save byte-for-byte (`foreignFrontmatterSurvivesRead`, `foreignFrontmatterRoundTripIsByteStable`).
- `NoteFolder.tree` with no edges at all treats every category as an unparented root (`testFlatCategoriesWithNoEdgesAreAllRoots`).
- `deleteNote(id:)` for an id with no corresponding document does not throw: `store.deleteDocument` treats a missing id as success by design (see `agentictoolkit://recipes/markdown-core`'s delete-is-idempotent requirement), so calling `deleteNote` twice for the same note is safe.
- Toggling a pin while a debounced content save for the same note is still pending does not wait for it: `togglePin` writes through immediately against whatever `content` is already in memory, ahead of the debounced write.
- `MarkdownNoteStorage.updateNote`'s single-transaction read-merge-write buys atomicity against a concurrent writer, not ordering between two `updateNote` calls on the same note — the second one to commit always wins over the whole note, matching adh's own head-has-no-concurrency-token model.
