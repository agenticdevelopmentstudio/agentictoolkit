<!-- leaf: implement-general-2/notes-model--logging · source: notes-model.md -->

# NotesModel

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable.makeLogger()`) | Category: `NotesManager`

| Event | Level | Message |
|-------|-------|---------|
| A storage read or write fails | error | `"<operation> failed: <error.localizedDescription>"`, where `<operation>` is `load`, `create`, `save`, or `delete` |
| `loadNotes()` succeeds | info | `"Loaded <count> notes"` |
