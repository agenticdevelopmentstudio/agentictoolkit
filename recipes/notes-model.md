---
id: d46b3e1c-9cd9-41b6-bdd2-524ece5e294b
title: NotesModel
domain: agentictoolkit://recipes/notes-model
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The on-device model, storage protocol, and main-actor orchestrator behind
  AgenticToolkit's Notes feature — Note, NoteFolder, NoteStorage, MarkdownNoteStorage,
  and NotesManager.
platforms:
- swift
- macos
tags:
- notes
- markdown
- persistence
- frontmatter
- debounce
- concurrency
- taxonomy
depends-on:
- agentictoolkit://recipes/markdown-core
- agenticdevelopertoolkit://recipes/markdown-core
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/Note.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/NoteFolder.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/NoteStorage.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/NoteTaxonomyProviding.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/MarkdownNoteStorage.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/NotesWindow/NotesManager.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a model, storage protocol, and orchestrator with no visual surface, not a visual component.

## States

Not applicable — this is a model, storage protocol, and orchestrator with no visual surface, not a visual component.

## Accessibility

Not applicable — this is a model, storage protocol, and orchestrator with no visual surface, not a visual component.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` | `NoteStorage` (`Sendable`) | none — required init parameter | `NotesManager.init(storage:)` takes no default; the concrete backend (e.g. `MarkdownNoteStorage`) is supplied by the caller. |
| `store` | `MarkdownStore` | none — required init parameter | `MarkdownNoteStorage.init(store:)` takes no default; the caller constructs and owns the `MarkdownStore`. |
| `saveDebounce` | `Duration` | `.seconds(1)` | `NotesManager`'s private `static let saveDebounce`; a compile-time constant, not externally configurable in the given sources. |
| `pinnedKey` | `String` | `"pinned"` | `MarkdownNoteStorage`'s private `static let pinnedKey`; the sole frontmatter key this class ever writes, likewise a compile-time constant. |

## Deep Linking

Not applicable: none of these six sources exposes a URL scheme, route, or path — `Note`, `NoteFolder`, `NoteStorage`, `MarkdownNoteStorage`, and `NotesManager` are an in-process persistence and orchestration layer with no addressable location of their own.

## Localization

- **notes-storage-failure-titles**: `NotesStorageFailure.Operation.title` returns four hardcoded English literals — "Couldn't Load Notes", "Couldn't Create Note", "Couldn't Save Note", "Couldn't Delete Note" — with no `String(localized:)`, `NSLocalizedString`, or other localization mechanism wrapping any of them; a caller presenting `storageFailure` sees exactly this English text.
- **notes-storage-failure-consequences**: `NotesStorageFailure.Operation.consequence` likewise returns four hardcoded English sentences describing what the failure means for what is on screen; the `.delete` case interpolates `AppStorageLocation.displayName` (a separately-localized product name) into an otherwise unlocalized English sentence.
- **notes-storage-failure-message-passthrough**: `NotesStorageFailure.message` is the underlying error's `localizedDescription`, shown verbatim; whatever localization that error itself carries, or lacks, passes through this layer unchanged — `MarkdownNoteStorage` and `NotesManager` neither translate nor re-wrap it.

## Accessibility Options

Not applicable: this layer renders nothing and animates nothing to adapt — Reduce Motion, Increase Contrast, and Differentiate Without Color are presentation concerns for a host view controller (out of scope here), not for `Note`, `NoteFolder`, `NoteStorage`, `MarkdownNoteStorage`, or `NotesManager`.

## Feature Flags

Not applicable: none of these six sources reads a feature-flag key, a `UserDefaults` toggle, or a remote-config value to gate any behavior described above.

## Analytics

Not applicable: none of these six sources emits an analytics event; the only instrumentation present is the diagnostic logging documented under Logging below.

## Privacy

- **Data collected**: A note's markdown `content` (arbitrary user-authored text, including any frontmatter the user hand-types into it) plus per-note metadata: `id` (`UUID`), `createdDate`, `modifiedDate`, and `isPinned`.
- **Storage**: Persisted locally by whatever `NoteStorage` the host injects. `MarkdownNoteStorage` persists a note as a row in a local `MarkdownStore` (SQLite via GRDB, per `agentictoolkit://recipes/markdown-core`), keyed by the note's id lowercased to a string; none of the six sources given here adds encryption, Keychain storage, or any protection beyond what `MarkdownStore` itself already applies.
- **Transmission**: None of these six sources calls out to a network directly. `MarkdownNoteStorage.insertNote` does enqueue a create operation onto `MarkdownStore`'s own remote outbox (per `agentictoolkit://recipes/markdown-core`), so a note's content and metadata eventually leave the device through that separate, already-documented sync path, on a schedule this layer does not control.
- **Retention**: A note's content and metadata persist indefinitely until `deleteNote(id:)` removes the row. `flushPendingSaves()` shortens the window in which an edit exists only in memory and not yet on disk, but it is the caller's responsibility to invoke it (e.g. before termination); nothing in these six sources calls it automatically.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable.makeLogger()`) | Category: `NotesManager`

| Event | Level | Message |
|-------|-------|---------|
| A storage read or write fails | error | `"<operation> failed: <error.localizedDescription>"`, where `<operation>` is `load`, `create`, `save`, or `delete` |
| `loadNotes()` succeeds | info | `"Loaded <count> notes"` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | reliability |

Separation of concerns holds structurally: `NoteStorage` is a narrow, four-method persistence seam that knows nothing about markdown, frontmatter, or ownership; `MarkdownNoteStorage` is the only conformer that reaches into `MarkdownStore`, and it alone carries the entire frontmatter-ownership contract; `NotesManager` owns in-memory state, notification, debouncing, and failure surfacing without ever touching a document's bytes directly. Unit test coverage holds: `MarkdownNoteStorageTests`, `NoteFolderTests`, `NotesStorageFailureTests`, `NotesManagerStorageOrderingTests`, and `NotesManagerMarkdownStoreTests` between them exercise nearly every requirement above by name, including the concurrency-ordering and ownership-race cases. Explicit error handling holds: every one of the four `NoteStorage` methods is `throws`, and every `NotesManager` call site either propagates the failure to its caller (`createNote` returning `nil`) or records it as a typed `NotesStorageFailure` with a log line — nothing here discards an error silently. Error recovery holds for the debounced save path specifically: `KeyedDebouncer`'s contract keeps a note whose write threw pending and retries it with backoff, rather than dropping it once and logging. Data integrity holds: `MarkdownNoteStorage.note(from:)` skips a document whose id fails `UUID(uuidString:)` rather than crashing or corrupting the list, and `updateNote`'s single-transaction read-merge-write is what lets another writer's concurrent, in-transaction mark survive rather than being silently overwritten. State recovery is marked partial: `flushPendingSaves()` exists precisely to drain every pending debounced save before termination and to report which ones still failed, but nothing in the six sources given here calls it automatically — invoking it is a caller precondition (the host app's own termination handling, out of scope for this recipe), so a host that never calls it can still lose an in-flight edit to a crash or a forced quit.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
