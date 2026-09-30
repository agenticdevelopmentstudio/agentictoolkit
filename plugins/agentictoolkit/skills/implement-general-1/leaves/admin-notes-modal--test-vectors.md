<!-- leaf: implement-general-1/admin-notes-modal--test-vectors · source: admin-notes-modal.md -->

# AdminNotesModal

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| T1 | seeds-working-copy-on-mount | Mount with `notes=[a,b]` | Note list shows rows `a`, `b` |
| T2 | discards-staged-edits-on-close | Stage an edit, then flip `open` to `false` | Working list resets to `notes`; reopening (same instance) shows the unedited list |
| T3 | adopts-refreshed-notes-when-unedited | Open, stage nothing, caller supplies a new `notes` array | Note list updates to the new `notes` |
| T4 | preserves-staged-edits-across-refresh | Open, stage an edit, caller supplies a new `notes` array | Staged edit remains visible; new `notes` is not adopted |
| T5 | opens-new-note-editor-with-blank-draft | Click "New note" | Editor opens titled "New note" with an empty text field |
| T6 | opens-edit-note-editor-seeded-with-content | Select a note, click "Edit" | Editor opens titled "Edit note" with the text field containing that note's content |
| T7 | rejects-blank-editor-save | In the new-note editor, leave the field blank, click Save | Editor stays open; working list unchanged |
| T8 | appends-new-note-on-editor-save | In the new-note editor, type "Hello", click Save | Working list gains one note with `content="Hello"`, `author` = the `author` prop, `addedDate`/`modifiedDate` = today, `subjectTable`/`subjectId` = `""` |
| T8b | appends-new-note-on-editor-save | Open the new-note editor, wait, then click Save | The new note's `id` is generated at the moment Save is clicked, not when the editor was opened |
| T9 | updates-existing-note-on-editor-save | Edit an existing note's content, click Save | That note's `content` and `modifiedDate` change; `id`, `author`, `addedDate`, `subjectTable`, `subjectId` are unchanged |
| T10 | closes-editor-on-successful-save | Complete T8 or T9 | Editor closes; draft clears |
| T11 | discards-draft-on-editor-cancel | Type into the editor, click Cancel | Editor closes; working list unchanged; no confirmation prompt appears |
| T11b | discards-draft-on-editor-cancel | Type into the editor, dismiss via Escape or its close control | Editor closes; working list unchanged; no confirmation prompt appears |
| T12 | removes-deleted-notes-from-working | Select a note, confirm delete | That note is absent from the working list |
| T13 | disables-editor-save-when-draft-blank | Editor open, field empty or whitespace-only | Editor Save is disabled |
| T14 | computes-dirty-by-structural-comparison | Stage an edit, then revert it back to the original value | Outer Save is disabled again (matches `notes`) |
| T15 | disables-outer-save-when-not-dirty-or-busy | Working list unchanged from `notes` | Outer Save is disabled |
| T15b | disables-outer-save-when-not-dirty-or-busy | Working list dirty, `busy=true` | Outer Save is disabled |
| T16 | submits-id-and-content-only | Stage an add and an edit, click outer Save | `onSave` is called with an array of `{id, content}` entries only, one per working-list note |
| T16b | submits-id-and-content-only | Add a new note, click outer Save | The new note's submitted `id` carries the `note-` prefix; a pre-existing note's submitted `id` is unchanged from its loaded value |
| T17 | closes-without-confirmation | Stage edits, click outer Cancel | Working list resets to `notes`; `onClose` is called; no confirmation prompt appears |
| T18 | ignores-busy-for-dismissal | `busy=true`, press Escape | Outer dialog closes via the normal discard path |
| T18b | ignores-busy-for-dismissal | `busy=true`, click outer Cancel or the outer dialog's close control | Outer dialog closes via the normal discard path |
| T19 | renders-note-list-columns | Any non-empty `notes` | Columns headed "Author", "Added", "Modified" are present |
| T20 | renders-selected-note-detail | Select one note | Detail pane shows that note's content and an "Edit" button |
| T21 | labels-outer-dialog-title | Open the modal | Title text reads "Admin notes" |
| T22 | labels-editor-title-by-mode | Open new-note vs. edit-note editor | Title reads "New note" / "Edit note" respectively |
| T23 | supplies-note-list-aria-label | Inspect the note list's accessible name | Reads "Admin notes" |
| T24 | labels-note-content-field | Inspect the editor field's accessible name | Reads "Note content" |
| T25 | accepts-optional-busy-prop | Render without passing `busy` | Outer Save behaves as `busy=false` |
