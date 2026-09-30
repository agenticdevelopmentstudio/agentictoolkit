<!-- leaf: implement-general-1/admin-notes-modal--states · source: admin-notes-modal.md -->

# AdminNotesModal

## States

| State | Appearance change |
|-------|--------------------|
| Closed | Nothing rendered (`open=false`); working list reset to `notes`. |
| Open, notes present | Note list shows Author/Added/Modified columns via `ListWithDetailsPane`. |
| Open, zero notes | List shows "No admin notes yet." instead of rows. |
| Row selected | Detail pane shows the note's content and an "Edit" action. |
| No row selected | Detail pane shows "Select a note to read it." |
| Note editor open, new | Editor titled "New note"; blank text field; editor Save disabled until non-blank input. |
| Note editor open, edit | Editor titled "Edit note"; text field pre-filled with the note's content. |
| Working list dirty | Outer Save enabled (unless `busy`). |
| Working list not dirty | Outer Save disabled. |
| `busy=true` | Outer Save disabled regardless of dirty state; Cancel, Escape, and close remain active. |
