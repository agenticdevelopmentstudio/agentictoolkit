<!-- leaf: implement-general-2/notes-model--part-3 · source: notes-model.md -->

# NotesModel — continued (part 3)

## Platform Notes

- **SwiftUI**: These six types are plain Swift/Foundation with no AppKit dependency, so a SwiftUI host can wrap `NotesManager` in an `@Observable` or `ObservableObject` adapter (it is neither itself — see Design Decisions) and drive a `List`/`ForEach` from `notes`, observing `notesDidChangeNotification` and `storageDidFailNotification` the same way an AppKit host does.
- **Compose**: Port `Note` as a `data class`, `NoteFolder` as a recursive `data class`, and `NoteStorage` as a Kotlin `interface` of four functions (suspend or blocking, matching the source's synchronous-and-throwing shape). `NotesManager` becomes a `ViewModel` holding a `StateFlow<List<Note>>` in place of the notification pair, with the debounced save mapped onto a coroutine job keyed by note id (the role `KeyedDebouncer` plays here) and the storage-issue-ordering guarantee reproduced with a single-threaded dispatcher or a `Mutex`.
- **React/Web**: `Note`/`NoteFolder` become plain TypeScript interfaces; `NoteStorage` an interface of four `Promise`-returning methods. `NotesManager` becomes a store (a hook backed by `useSyncExternalStore`, or a small class with subscribers in place of `NotificationCenter`), with the per-note debounce implemented via `setTimeout` keyed by note id and the write-ordering guarantee implemented as a per-instance promise chain, exactly mirroring `performStorage(_:)`'s `storageChain`.
- **AppKit / UIKit**: The six sources given here — `Note.swift`, `NoteFolder.swift`, `NoteStorage.swift`, `NoteTaxonomyProviding.swift`, `MarkdownNoteStorage.swift`, and `NotesManager.swift`, all under `packages/apple/AgenticToolkit/macOS/Features/NotesWindow/` — are the source platform: a macOS-only target consumed by `NotesCoordinator`/`NotesSplitViewController` (out of scope for this recipe) via `NotificationCenter` observation and `@MainActor` calls. Nothing in these six files is itself AppKit-specific — they import only `Foundation`, `os`, `AgenticToolkitCore`, `AgenticToolkitMarkdown`, and `AgenticToolkitDatabase` — so the same files would compile unchanged into a UIKit iOS target.
- **WinUI 3**: `Note`/`NoteFolder` become a `record`/`class` pair (or a lightweight `INotifyPropertyChanged` model if the folder tree needs to bind directly to a `TreeView`). `NoteStorage` becomes an interface returning `Task<T>` per method. `NotesManager` becomes a class backed by an `ObservableCollection<Note>` in place of `notes`, replacing `notesDidChangeNotification`/`storageDidFailNotification` with `INotifyCollectionChanged` and a plain C# event; a `SemaphoreSlim(1, 1)` awaited before each storage call reproduces the one-at-a-time, issue-ordered `storageChain`, and a `System.Threading.Timer` per note id, restarted on each edit, reproduces `KeyedDebouncer`'s per-key debounce-with-retry.

## Design Decisions

**Decision**: Track frontmatter key ownership explicitly (`ownedFrontmatterKeys`, recorded in the same transaction as the document) rather than inferring ownership from a key's value.
**Rationale**: Two prior ad-hoc value-based guards disagreed with each other and produced two distinct defects — an unpin that could not clear its own `pinned:` key, and a foreign `pinned: true` pasted from a Hugo or Jekyll document that silently pinned the note. Recording the fact instead of guessing removes both special cases in one stroke.
**Approved**: pending

**Decision**: A note has no stored `title` field at all — `title` is always `MarkdownText.deriveTitle(content)`, and `MarkdownNoteStorage` never claims a `title` frontmatter key.
**Rationale**: A stored title can go stale against edited content between an edit and the next save. A third historical defect, on the `title` key this class used to also own, came from exactly that: a save overwrote a hand-typed `title:` fence because the app assumed any title it did not recognize was stale.
**Approved**: pending

**Decision**: `updateNote`'s read, merge, and write happen inside one `MarkdownStore.mutateDocument` transaction rather than as three separate calls.
**Rationale**: Nothing today needs it — `NotesCoordinator` builds one `NotesManager` shared by every host, and that manager already serializes its own storage calls — but the transaction is cheap enough to pay for up front, before the writer that would need it (a background sync pull, a second coordinator) exists, because the read-and-write layer is the only layer that can make the pair indivisible later.
**Approved**: pending

**Decision**: `NotesManager` runs every storage call off the main actor, but re-serializes them into one `storageChain` so they still execute strictly in the order they were issued.
**Rationale**: Each write hands storage a whole `Note` snapshot taken on the main actor. Before storage moved off the main actor, issue order and execution order were the same thing for free — no suspension point existed inside a call. Detaching each call independently would silently give that up, letting a stale content-save land after a newer pin-toggle write and resurrect superseded content.
**Approved**: pending

**Decision**: A debounced save whose write throws stays pending and is retried with backoff (via `KeyedDebouncer`), rather than being dropped after a log line.
**Rationale**: Three prior, independent copies of this cancel-and-reschedule-then-flush-once pattern (in this manager, `TextDocumentSaveScheduler`, and `SemanticTokenHighlightProvider`) each dropped a note whose write threw. A dropped note left the user's edit unsaved with no further attempt and no visible failure until the next launch, at which point it was already gone.
**Approved**: pending

**Decision**: `storageFailure` is one optional value, overwritten by the next failure, rather than a queue of past failures.
**Rationale**: A failing storage backend fails every subsequent operation identically, so a second queued alert would only repeat what the first one already said. A single slot is the smallest shape that still makes a failure visible to the user.
**Approved**: pending

**Decision**: Pinning a note is implemented by editing the note's own markdown `content` (a `pinned:` frontmatter line) rather than as a separate, local-only column.
**Rationale**: The cost is named directly in `MarkdownNoteStorage`'s own comments: once a remote writer exists, pinning appends a version on the server. That cost is accepted because the alternative — a local-only column — would silently vanish on the note's first sync.
**Approved**: pending
