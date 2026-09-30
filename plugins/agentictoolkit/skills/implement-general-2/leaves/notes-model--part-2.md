<!-- leaf: implement-general-2/notes-model--part-2 · source: notes-model.md -->

# NotesModel — continued (part 2)

**Rules** (cite as `implement-general-2/notes-model--part-2#<slug>`):

- `notesmanager-actor-isolation` MUST
- `notesmanager-change-notification` MUST
- `notesmanager-failure-surface` MUST
- `notesmanager-clear-failure` MUST
- `notesmanager-load-failure-keeps-loaded-true` MUST
- `notesmanager-create-rollback` MUST
- `notesmanager-content-update-debounced` MUST
- `notesmanager-debounce-reread` MUST
- `notesmanager-debounce-retry` MUST
- `notesmanager-pin-toggle-immediate` MUST
- `notesmanager-delete-optimistic` MUST
- `notesmanager-storage-off-main-actor` MUST
- `notesmanager-storage-issue-order` MUST
- `notesmanager-markdown-store-accessor` MUST
- `notesmanager-flush-before-termination` MUST
- `notesmanager-logging` MUST

### NotesManager

- **notesmanager-actor-isolation**: `NotesManager` MUST be `@MainActor`; its published state (`notes`, `isLoaded`, `storageFailure`) MUST be read and mutated only on the main actor.
- **notesmanager-change-notification**: `NotesManager` MUST post `notesDidChangeNotification` (with `object` set to the manager instance and no payload) after every operation that changes `notes` — a load, a create, a content update, a pin toggle, or a delete — so an observer re-reads `notes` from the posting manager rather than from a `userInfo` snapshot that could already be stale by the time it is read.
- **notesmanager-failure-surface**: `NotesManager` MUST record a failed storage operation as a single `storageFailure: NotesStorageFailure?` carrying the operation and the error's `localizedDescription`, log it via `logger.error`, and post `storageDidFailNotification`; a new failure MUST overwrite rather than queue behind a previous one, since a failing store fails every subsequent operation identically. `reportStorageFailure(_:_:)` MUST apply this same recording for a failure the manager did not itself trigger — a caller that wrote to the manager's wrapped `MarkdownStore` directly.
- **notesmanager-clear-failure**: `clearStorageFailure()` MUST set `storageFailure` to `nil`; it is the only way `storageFailure` is cleared, so whichever host shows the failure is responsible for calling it.
- **notesmanager-load-failure-keeps-loaded-true**: When `fetchAllNotes` throws, `loadNotes()` MUST still set `isLoaded = true` and MUST leave `notes` as it was (empty, on first launch) rather than leaving the manager perpetually unloaded (`testAFailedLoadIsRecorded`).
- **notesmanager-create-rollback**: When `insertNote` throws, `createNote(content:)` MUST record the failure, return `nil`, and MUST NOT append the note to `notes` — a note that was never durably persisted MUST NOT remain visible in the list (`testAFailedCreateIsRecordedAndTheNoteIsNotListed`).
- **notesmanager-content-update-debounced**: `updateNote(_:content:)` MUST update the in-memory note, re-sort `notes`, and post the change notification synchronously, then MUST schedule the actual storage write through a per-note debounced save (`KeyedDebouncer<UUID>`, `saveDebounce = .seconds(1)`) rather than writing to storage immediately.
- **notesmanager-debounce-reread**: A scheduled debounced save MUST re-look-up the note by id inside the scheduled work rather than capturing a snapshot at schedule time, so a save that runs late, or is retried after a failure, persists the note as it stands when the save actually executes, not as it stood when the keystroke landed.
- **notesmanager-debounce-retry**: A debounced save whose write throws MUST remain pending and be retried with backoff (`KeyedDebouncer`'s contract), rather than being dropped after a single log line.
- **notesmanager-pin-toggle-immediate**: `togglePin(note:)` MUST update the in-memory note, then write it through storage immediately on a snapshot of the just-toggled note, bypassing the content-update debounce entirely (`testAFailedSaveIsRecorded`'s own comment: "`togglePin` writes through immediately").
- **notesmanager-delete-optimistic**: `deleteNote(id:)` MUST remove the note from `notes` before attempting the storage delete, and MUST record — but MUST NOT use to reinstate the note — a failure of that storage delete.
- **notesmanager-storage-off-main-actor**: Every storage operation `NotesManager` issues MUST run off the main actor, through `performStorage(_:)`'s `Task.detached`, because the concrete storage's I/O (e.g. `MarkdownNoteStorage`'s SQLite calls) would otherwise block every other main-actor-isolated host sharing this manager (a second notes window, Quick Note) for the duration of the call.
- **notesmanager-storage-issue-order**: `NotesManager` MUST serialize its own storage calls into one `storageChain`, so each next call awaits the previous one and they execute in the exact order they were issued, never overlapping and never reordered — because `updateNote` carries a whole `Note` snapshot taken on the main actor, and an out-of-order write (a stale content save landing after a newer pin toggle) would resurrect superseded content (`testStorageWritesRunOneAtATimeInIssueOrder`, asserting both `peakConcurrency == 1` and that the storage-arrival order matches the issue order). This ordering covers only calls issued by this one `NotesManager` instance; a second, independent writer against the same `NoteStorage` is outside its scope.
- **notesmanager-markdown-store-accessor**: `markdownStore` MUST return the wrapped `MarkdownStore` only when `storage` also conforms to `NoteTaxonomyProviding`, and MUST return `nil` otherwise, so a host whose storage is not `MarkdownStore`-backed (e.g. a test double) can treat the folders feature as simply unavailable (`NotesManagerMarkdownStoreTests`).
- **notesmanager-flush-before-termination**: `flushPendingSaves()` MUST synchronously drain every pending debounced save and MUST return the ids of any note whose flushed write still failed, so a caller invoked before app termination can act on what did not reach disk.
- **notesmanager-logging**: `NotesManager` MUST log every storage failure via `logger.error`, including the operation's `rawValue` and the error's `localizedDescription`, and MUST log a successful load via `logger.info`, including the count of notes loaded.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` | `NoteStorage` (`Sendable`) | none — required init parameter | `NotesManager.init(storage:)` takes no default; the concrete backend (e.g. `MarkdownNoteStorage`) is supplied by the caller. |
| `store` | `MarkdownStore` | none — required init parameter | `MarkdownNoteStorage.init(store:)` takes no default; the caller constructs and owns the `MarkdownStore`. |
| `saveDebounce` | `Duration` | `.seconds(1)` | `NotesManager`'s private `static let saveDebounce`; a compile-time constant, not externally configurable in the given sources. |
| `pinnedKey` | `String` | `"pinned"` | `MarkdownNoteStorage`'s private `static let pinnedKey`; the sole frontmatter key this class ever writes, likewise a compile-time constant. |

## Localization

- **notes-storage-failure-titles**: `NotesStorageFailure.Operation.title` returns four hardcoded English literals — "Couldn't Load Notes", "Couldn't Create Note", "Couldn't Save Note", "Couldn't Delete Note" — with no `String(localized:)`, `NSLocalizedString`, or other localization mechanism wrapping any of them; a caller presenting `storageFailure` sees exactly this English text.
- **notes-storage-failure-consequences**: `NotesStorageFailure.Operation.consequence` likewise returns four hardcoded English sentences describing what the failure means for what is on screen; the `.delete` case interpolates `AppStorageLocation.displayName` (a separately-localized product name) into an otherwise unlocalized English sentence.
- **notes-storage-failure-message-passthrough**: `NotesStorageFailure.message` is the underlying error's `localizedDescription`, shown verbatim; whatever localization that error itself carries, or lacks, passes through this layer unchanged — `MarkdownNoteStorage` and `NotesManager` neither translate nor re-wrap it.

## Privacy

- **Data collected**: A note's markdown `content` (arbitrary user-authored text, including any frontmatter the user hand-types into it) plus per-note metadata: `id` (`UUID`), `createdDate`, `modifiedDate`, and `isPinned`.
- **Storage**: Persisted locally by whatever `NoteStorage` the host injects. `MarkdownNoteStorage` persists a note as a row in a local `MarkdownStore` (SQLite via GRDB, per `agentictoolkit://recipes/markdown-core`), keyed by the note's id lowercased to a string; none of the six sources given here adds encryption, Keychain storage, or any protection beyond what `MarkdownStore` itself already applies.
- **Transmission**: None of these six sources calls out to a network directly. `MarkdownNoteStorage.insertNote` does enqueue a create operation onto `MarkdownStore`'s own remote outbox (per `agentictoolkit://recipes/markdown-core`), so a note's content and metadata eventually leave the device through that separate, already-documented sync path, on a schedule this layer does not control.
- **Retention**: A note's content and metadata persist indefinitely until `deleteNote(id:)` removes the row. `flushPendingSaves()` shortens the window in which an edit exists only in memory and not yet on disk, but it is the caller's responsibility to invoke it (e.g. before termination); nothing in these six sources calls it automatically.

