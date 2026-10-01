---
id: d46b3e1c-9cd9-41b6-bdd2-524ece5e294b
title: Notes Model
domain: agentictoolkit://cookbook/workspace/notes/notes-model
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The on-device model, storage contract, and orchestrator behind the
  Notes feature — a note, a note folder, a storage seam, a markdown-backed
  conformer, and the manager coordinating them.
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
- agentictoolkit://cookbook/adh/hub/content/markdown-store
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

# Notes Model

## Overview

This is the model, persistence-contract, and orchestration layer behind
the Notes feature:
a local, on-device notes store with no UI of its own. A note is an
immutable-id value whose title and excerpt are always derived from its
markdown content, never stored. A note folder is the tree shape a folders
pane displays, built from a flat category/edge read. The storage contract
is the abstract, four-operation persistence seam the manager depends on,
required to be safe to call from multiple threads; the markdown-backed
conformer is the concrete implementation that maps a note onto a
markdown-store document, and is also the layer that owns the entire
frontmatter-ownership contract for the one key it writes, `pinned`. The
manager is the object, confined to the primary UI thread, that owns the
in-memory list of notes, issues every storage call off that thread in
strict issue order, runs a per-note debounced autosave, and surfaces a
failed read or write as a single failure record.

This is a different, unrelated contract from the web-side notes client
documented in `agentictoolkit://cookbook/adh/hub/content/notes-client` —
that recipe's own text says as much: its notes are a backend content
resource reached over a REST API, these are a local, on-device store
reached through the storage contract described here, and the shared name
is a coincidence, not a shared contract.

## Behavioral Requirements

### Note

- **note-identity**: A note MUST be uniquely identifiable and comparable
  for equality, MUST be safe to pass across concurrent contexts, and its
  id MUST be immutable once created.
- **note-fields**: A note MUST carry exactly `content` (text),
  `createdDate` (immutable), `modifiedDate`, and `isPinned` as its stored
  state; it MUST have no stored `title` field.
- **note-title-derivation**: A note's title MUST be computed on every
  access from its content via the shared markdown title-derivation
  utility, never stored, so it can never go stale against content
  between an edit and the next save.
- **note-excerpt-derivation**: A note's excerpt MUST be computed via the
  shared markdown excerpt-derivation utility, applied to the note's
  content together with its frontmatter, which MUST skip the line the
  title was derived from so a heading used as the title is never repeated
  as the first line of the excerpt underneath it.
- **note-untitled-sentinel**: A note's untitled-title sentinel MUST be the
  same sentinel value the markdown utilities themselves define for
  "untitled," not a second string with the same text, so a comparison
  against it can never disagree with the markdown layer's own sentinel.
- **note-default-sort**: A note's default sort order MUST place pinned
  notes before unpinned notes, and within each group order by
  `modifiedDate` descending.
- **note-factory**: Creating a new note from content MUST produce a note
  with a fresh unique id, `createdDate` and `modifiedDate` both set to the
  current time, and `isPinned` false.

### NoteFolder

- **notefolder-value-semantics**: A note folder MUST be uniquely
  identifiable, comparable for equality, and hashable by value — not by
  object identity — and MUST be safe to pass across concurrent contexts.
  Value-based hashing here is deliberate, not an accidental default: a UI
  element that tracks expansion or selection state by matching folder
  values across reloads needs two equal folders produced by two separate
  reads to hash equally, which a reference/object-identity-based hash
  would not guarantee (see Platform Notes).
- **notefolder-all-notes-sentinel**: An id of the empty string MUST be
  reserved for the synthetic "All Notes" root; the folder-tree-building
  operation MUST never itself produce a node with an empty id, since
  every real category id is a lowercased unique identifier minted at
  category-creation time.
- **notefolder-tree-multi-parent**: The folder-tree-building operation
  MUST build a category reachable from more than one parent once per
  parent, so it appears as an independent value under each parent rather
  than a shared reference.
- **notefolder-tree-direct-counts**: Each built folder's note count MUST
  be the category's own direct count from the supplied counts, never a
  sum over its children; a parent's count MAY therefore be smaller than
  the sum of its children's counts.
- **notefolder-tree-total-independent**: The caller MUST supply the "All
  Notes" total count separately (e.g. from the store's own note-count
  query) rather than deriving it by summing the per-category counts,
  because a note filed under two categories would double-count that sum
  and an uncategorized note would be missed by it entirely.
- **notefolder-tree-cycle-safety**: The folder-tree-building operation
  MUST bound every downward walk with a set of the ids already on the
  current path, so a cycle in the edge data truncates that branch instead
  of recursing forever; when every category lies on a cycle with no true
  root, it MUST fall back to treating every category as a root rather
  than losing the graph entirely.
- **notefolder-tree-orphan-edges**: The folder-tree-building operation
  MUST ignore any edge whose parent or child id is not present in the
  supplied category list.

### NoteStorage & NoteTaxonomyProviding

- **notestorage-contract**: The storage contract MUST declare exactly
  four operations that can fail — fetch all notes, insert a note, update
  a note, and delete a note by id — and MUST itself be safe to call from
  multiple threads, since the manager calls these operations off the
  primary thread; the thread safety of the concrete storage is the
  conformer's own responsibility, stated as a precondition, not enforced
  by the contract itself.
- **notetaxonomyproviding-contract**: A storage implementation MAY
  additionally support a taxonomy-provider extension to expose its
  backing document store for taxonomy (folder) queries; the base storage
  contract itself MUST NOT reference categories, so a storage backend
  with no taxonomy concept can implement the base contract alone and
  simply not support folders.

### MarkdownNoteStorage

- **markdownnotestorage-safe-for-concurrent-use**: The markdown-backed
  conformer MUST be safe to use concurrently; its only stored state is a
  reference to the markdown document store (itself declared safe to
  share across threads, by a manually-verified guarantee) and a fixed
  constant, so this safety property holds as written with no additional
  synchronization.
- **markdownnotestorage-note-mapping**: The markdown-backed conformer
  MUST represent a note as a markdown document carrying the `.note`
  marker, and fetching all notes MUST skip any document whose id does not
  parse as a valid unique identifier rather than crashing on it — a
  document with a non-unique-identifier id is server-authored and outside
  this model's addressing scheme.
- **markdownnotestorage-fetch-sort**: Fetching all notes MUST return its
  notes sorted by the note's default sort order (pinned-first, then
  `modifiedDate` descending).
- **markdownnotestorage-timestamps**: Inserting a note MUST stamp the
  underlying document's current-time and created-time parameters
  separately, from the note's `modifiedDate` and `createdDate`
  respectively, so a note's original creation date is preserved
  distinctly from its last-modified date rather than both collapsing
  onto one write timestamp.
- **markdownnotestorage-frontmatter-ownership**: The markdown-backed
  conformer MUST record, per document, which frontmatter keys it itself
  wrote, and MUST use that recorded fact — never the key's value — to
  decide whether a `pinned` key found in a document's frontmatter
  reflects this app's own pin state or a foreign key a user or another
  tool wrote.
- **markdownnotestorage-pin-claim-rule**: The markdown-backed conformer
  MAY claim (write and own) the `pinned` key only when it is currently
  absent from the document's frontmatter, or when writing the desired
  value would change no bytes of the document's content; it MUST NOT
  claim or rewrite a `pinned` key that already holds a different, foreign
  value or a differently-quoted/differently-styled equivalent value.
- **markdownnotestorage-pin-release-rule**: Whenever updating a note
  finds the note's content differs from what this layer last derived for
  it (the stored content with owned keys stripped), it MUST treat the
  entire frontmatter as released — the user edited the text — clearing
  the ownership record for that document before deciding whether to
  write `pinned` again in the same call.
- **markdownnotestorage-title-never-written**: The markdown-backed
  conformer MUST NOT write a `title` frontmatter key under any
  circumstance; a note's title is always derived from its content, and a
  hand-typed `title:` fence MUST be left untouched, exactly like any
  other foreign frontmatter key.
- **markdownnotestorage-strip-on-read**: The markdown-backed conformer
  MUST strip only the frontmatter keys it owns from the text it exposes
  as a note's content; every other line — including a foreign `pinned:`
  key — MUST remain visible, in its original order, in that content.
- **markdownnotestorage-update-atomicity**: Updating a note MUST perform
  its read, merge, and write as a single transaction, not as separate
  read-then-write calls, so a concurrent writer's in-transaction append to
  the same document (e.g. to an unrelated field) survives an update call
  on that document; this buys atomicity, not ordering — two concurrent
  updates on the same note still resolve last-writer-wins over the whole
  note.
- **markdownnotestorage-update-missing-throws**: Updating a note MUST
  fail when the note's id does not correspond to an existing document.
- **markdownnotestorage-delete**: Deleting a note by id MUST remove the
  corresponding document from the store by delegating to the store's own
  document-delete operation.

### NotesManager

- **notesmanager-confined-to-primary-thread**: The manager MUST be
  confined to the primary UI thread; its published state (the notes list,
  the load-completion flag, the storage failure) MUST be read and
  mutated only there.
- **notesmanager-change-notification**: The manager MUST post a change
  notification (with the manager itself as the subject and no payload)
  after every operation that changes the notes list — a load, a create, a
  content update, a pin toggle, or a delete — so an observer re-reads the
  notes list from the posting manager rather than from a stale payload
  snapshot that could already be out of date by the time it is read.
- **notesmanager-failure-surface**: The manager MUST record a failed
  storage operation as a single failure record carrying the operation and
  the error's description, log it as an error, and post a storage-failure
  notification; a new failure MUST overwrite rather than queue behind a
  previous one, since a failing store fails every subsequent operation
  identically. The manager's failure-reporting entry point MUST apply
  this same recording for a failure the manager did not itself trigger —
  a caller that wrote to the manager's wrapped document store directly.
- **notesmanager-clear-failure**: Clearing the storage failure MUST set it
  to unset; it is the only way the storage failure is cleared, so
  whichever host shows the failure is responsible for calling it.
- **notesmanager-load-failure-keeps-loaded-true**: When fetching all notes
  fails, loading notes MUST still mark the manager as loaded and MUST
  leave the notes list as it was (empty, on first launch) rather than
  leaving the manager perpetually unloaded.
- **notesmanager-create-rollback**: When inserting a note fails, creating
  a note from content MUST record the failure, return nothing, and MUST
  NOT append the note to the notes list — a note that was never durably
  persisted MUST NOT remain visible in the list.
- **notesmanager-content-update-debounced**: Updating a note's content
  MUST update the in-memory note, re-sort the notes list, and post the
  change notification synchronously, then MUST schedule the actual
  storage write through a per-note debounced save (a 1-second debounce,
  keyed by note id) rather than writing to storage immediately.
- **notesmanager-debounce-reread**: A scheduled debounced save MUST
  re-look-up the note by id inside the scheduled work rather than
  capturing a snapshot at schedule time, so a save that runs late, or is
  retried after a failure, persists the note as it stands when the save
  actually executes, not as it stood when the keystroke landed.
- **notesmanager-debounce-retry**: A debounced save whose write fails
  MUST remain pending and be retried with backoff, rather than being
  dropped after a single log line.
- **notesmanager-pin-toggle-immediate**: Toggling a note's pin state MUST
  update the in-memory note, then write it through storage immediately on
  a snapshot of the just-toggled note, bypassing the content-update
  debounce entirely.
- **notesmanager-delete-optimistic**: Deleting a note by id MUST remove
  the note from the notes list before attempting the storage delete, and
  MUST record — but MUST NOT use to reinstate the note — a failure of
  that storage delete.
- **notesmanager-storage-off-primary-thread**: Every storage operation
  the manager issues MUST run off the primary UI thread, through a
  detached unit of work, because the concrete storage's I/O (e.g. the
  markdown-backed conformer's local-database calls) would otherwise block
  every other host confined to that thread and sharing this manager (a
  second notes window, Quick Note) for the duration of the call.
- **notesmanager-storage-issue-order**: The manager MUST serialize its own
  storage calls into one ordered chain, so each next call awaits the
  previous one and they execute in the exact order they were issued,
  never overlapping and never reordered — because updating a note carries
  a whole note snapshot taken on the primary thread, and an out-of-order
  write (a stale content save landing after a newer pin toggle) would
  resurrect superseded content. This ordering covers only calls issued by
  this one manager instance; a second, independent writer against the
  same storage contract is outside its scope.
- **notesmanager-markdown-store-accessor**: The manager's markdown-store
  accessor MUST return the wrapped document store only when the storage
  implementation also supports the taxonomy-provider extension, and MUST
  return nothing otherwise, so a host whose storage is not
  markdown-store-backed (e.g. a test double) can treat the folders
  feature as simply unavailable.
- **notesmanager-flush-before-termination**: Flushing pending saves MUST
  synchronously drain every pending debounced save and MUST return the
  ids of any note whose flushed write still failed, so a caller invoked
  before app termination can act on what did not reach disk.
- **notesmanager-logging**: The manager MUST log every storage failure as
  an error, including the operation's name and the error's description,
  and MUST log a successful load as informational, including the count of
  notes loaded.

## Appearance

Not applicable — this is a model, storage contract, and orchestrator with
no visual surface, not a visual component.

## States

Not applicable — this is a model, storage contract, and orchestrator with
no visual surface, not a visual component.

## Accessibility

Not applicable — this is a model, storage contract, and orchestrator with
no visual surface, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| notes-model-001 | markdownnotestorage-note-mapping | Insert a note with content `"# Groceries\n\nMilk"`, then fetch all notes. | The returned note's id matches the inserted id, its title is `"Groceries"`, and its content is `"# Groceries\n\nMilk"`. |
| notes-model-002 | markdownnotestorage-title-never-written | Insert a note with content `"# Groceries\n\nMilk"`. | The stored document's frontmatter is empty; no title key is ever written. |
| notes-model-003 | markdownnotestorage-frontmatter-ownership, markdownnotestorage-pin-claim-rule | Insert an unpinned note, update it with pinned set to true, then again with pinned set to false. | Frontmatter is empty before the pin, holds a pinned fence while pinned, and is empty again after the unpin. |
| notes-model-004 | markdownnotestorage-update-atomicity | 30 concurrent tasks each update the same note (a no-op content revert), racing 30 concurrent tasks each appending an index marker to the same document's owner-id field through a separate in-transaction write. | Every one of the 30 owner-id marks survives in the final document. |
| notes-model-005 | markdownnotestorage-update-missing-throws | Update a note that was never inserted. | The call fails. |
| notes-model-006 | markdownnotestorage-note-mapping | Create a document directly with a non-unique-identifier id (a server-style id), then fetch all notes. | The returned list is empty — the non-unique-identifier document is skipped, not crashed on. |
| notes-model-007 | markdownnotestorage-pin-claim-rule | Create a document directly with a foreign, never-owned pinned key set to true alongside an unrelated layout key, then fetch all notes. | The note's pinned flag is false; its content still contains the foreign pinned line untouched. |
| notes-model-008 | markdownnotestorage-pin-release-rule | Pin a note, then in one update call set its content to a hand-typed pinned fence plus new body text, and set pinned to false in the same call. | The hand-typed pinned line survives byte-for-byte; the frontmatter-ownership record for that document is empty afterward. |
| notes-model-009 | note-title-derivation | Create a document directly with a numeric frontmatter title, then fetch all notes. | The note's title is the body heading — a numeric frontmatter title falls through to the body line. |
| notes-model-010 | notefolder-tree-cycle-safety | Build the folder tree from edges forming a 3-node cycle with no true root. | The returned roots list is not empty — the cycle degrades to treating all three categories as roots. |
| notes-model-011 | notesmanager-storage-issue-order | 24 create-note calls, then 24 concurrently-issued pin-toggle tasks against a storage double that dwells 50ms per call and records arrival order. | The storage double never observes more than one call in flight at a time, and the arrival order of the updates equals the exact order the 24 tasks were issued in. |
| notes-model-012 | notesmanager-failure-surface, notesmanager-create-rollback | Create a note from content against a storage double whose insert operation always fails. | Returns nothing; the manager's recorded failure names the create operation; the notes list stays empty. |
| notes-model-013 | notesmanager-markdown-store-accessor | Construct the manager with a markdown-backed storage implementation, versus a storage implementation that does not support the taxonomy-provider extension. | The markdown-store accessor returns the same document store instance in the first case, nothing in the second. |

## Edge Cases

- An empty-content note (created from an empty string) derives the
  untitled-title sentinel, never an empty string title.
- Writing `pinned` when the document's frontmatter already reads
  byte-identical to the value about to be written claims the key without
  mutating a single byte of content.
- A quoted foreign value the app would otherwise rewrite as an unquoted
  boolean — `pinned: "true"` — is left completely alone and never
  claimed, because rewriting it would change bytes that belong to the
  user.
- A frontmatter `title` written as a flow sequence (`title: [a, b]`), an
  empty string (`title: ""`), or a whitespace-only string
  (`title: "   "`) all fall through to the derived body-line title,
  exactly as the shared markdown title-derivation utility does for every
  other document authored the same way.
- A foreign frontmatter key unrelated to `pinned` (e.g. `author: mike`)
  survives a read and an unrelated no-op re-save byte-for-byte.
- Building the folder tree with no edges at all treats every category as
  an unparented root.
- Deleting a note by an id with no corresponding document does not fail:
  the store's delete operation treats a missing id as success by design
  (see `agentictoolkit://cookbook/adh/hub/content/markdown-store`'s
  delete-is-idempotent requirement), so calling delete twice for the same
  note is safe.
- Toggling a pin while a debounced content save for the same note is
  still pending does not wait for it: toggling the pin writes through
  immediately against whatever content is already in memory, ahead of
  the debounced write.
- Updating a note's single-transaction read-merge-write buys atomicity
  against a concurrent writer, not ordering between two update calls on
  the same note — the second one to commit always wins over the whole
  note, matching this system's own head-has-no-concurrency-token model.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storage` | the storage contract (safe for concurrent use) | none — required init parameter | The manager takes no default; the concrete backend (e.g. the markdown-backed conformer) is supplied by the caller. |
| `store` | the markdown document store | none — required init parameter | The markdown-backed conformer takes no default; the caller constructs and owns the document store. |
| `saveDebounce` | duration | 1 second | A fixed internal constant, not externally configurable in the given sources. |
| `pinnedKey` | text | `"pinned"` | The sole frontmatter key the markdown-backed conformer ever writes, likewise a fixed internal constant. |

## Deep Linking

Not applicable: none of these six sources exposes a URL scheme, route, or
path — the note model, note folder, storage contract, markdown-backed
conformer, and manager are an in-process persistence and orchestration
layer with no addressable location of their own.

## Localization

- **notes-storage-failure-titles**: A storage failure's operation titles
  are four hardcoded English literals — "Couldn't Load Notes", "Couldn't
  Create Note", "Couldn't Save Note", "Couldn't Delete Note" — with no
  localization mechanism wrapping any of them; a caller presenting the
  storage failure sees exactly this English text.
- **notes-storage-failure-consequences**: A storage failure's operation
  consequences likewise are four hardcoded English sentences describing
  what the failure means for what is on screen; the delete case
  interpolates a separately-localized product/location name into an
  otherwise unlocalized English sentence.
- **notes-storage-failure-message-passthrough**: A storage failure's
  message is the underlying error's own localized description, shown
  verbatim; whatever localization that error itself carries, or lacks,
  passes through this layer unchanged — the markdown-backed conformer and
  the manager neither translate nor re-wrap it.

## Accessibility Options

Not applicable: this layer renders nothing and animates nothing to adapt —
Reduce Motion, Increase Contrast, and Differentiate Without Color are
presentation concerns for a host view (out of scope here), not for the
note model, note folder, storage contract, markdown-backed conformer, or
manager.

## Feature Flags

Not applicable: none of these six sources reads a feature-flag key, a
settings-store toggle, or a remote-config value to gate any behavior
described above.

## Analytics

Not applicable: none of these six sources emits an analytics event; the
only instrumentation present is the diagnostic logging documented under
Logging below.

## Privacy

- **Data collected**: A note's markdown content (arbitrary user-authored
  text, including any frontmatter the user hand-types into it) plus
  per-note metadata: a unique id, `createdDate`, `modifiedDate`, and
  `isPinned`.
- **Storage**: Persisted locally by whatever storage implementation the
  host injects. The markdown-backed conformer persists a note as a row in
  a local document store (a local database, per
  `agentictoolkit://cookbook/adh/hub/content/markdown-store`), keyed by
  the note's id lowercased to a string; none of the six sources given
  here adds encryption, secure-credential storage, or any protection
  beyond what that document store itself already applies.
- **Transmission**: None of these six sources calls out to a network
  directly. The markdown-backed conformer's insert operation does enqueue
  a create operation onto the document store's own remote outbox (per
  `agentictoolkit://cookbook/adh/hub/content/markdown-store`), so a
  note's content and metadata eventually leave the device through that
  separate, already-documented sync path, on a schedule this layer does
  not control.
- **Retention**: A note's content and metadata persist indefinitely until
  deleting it by id removes the row. Flushing pending saves shortens the
  window in which an edit exists only in memory and not yet on disk, but
  it is the caller's responsibility to invoke it (e.g. before
  termination); nothing in these six sources calls it automatically.

## Logging

Subsystem: the app's own bundle identifier (via the shared logger
factory) | Category: the manager's name

| Event | Level | Message |
|-------|-------|---------|
| A storage read or write fails | error | `"<operation> failed: <error.localizedDescription>"`, where `<operation>` is `load`, `create`, `save`, or `delete` |
| Loading notes succeeds | info | `"Loaded <count> notes"` |

## Platform Notes

- **SwiftUI**: These six types are plain Swift/Foundation with no AppKit
  dependency, so a SwiftUI host can wrap `NotesManager` in an
  `@Observable` or `ObservableObject` adapter (it is neither itself — see
  Design Decisions) and drive a `List`/`ForEach` from `notes`, observing
  `notesDidChangeNotification` and `storageDidFailNotification` the same
  way an AppKit host does.
- **Compose**: Port `Note` as a `data class`, `NoteFolder` as a recursive
  `data class`, and `NoteStorage` as a Kotlin `interface` of four
  functions (suspend or blocking, matching the source's synchronous-and-throwing
  shape). `NotesManager` becomes a `ViewModel` holding a
  `StateFlow<List<Note>>` in place of the notification pair, with the
  debounced save mapped onto a coroutine job keyed by note id (the role
  `KeyedDebouncer` plays here) and the storage-issue-ordering guarantee
  reproduced with a single-threaded dispatcher or a `Mutex`.
- **React/Web**: `Note`/`NoteFolder` become plain TypeScript interfaces;
  `NoteStorage` an interface of four `Promise`-returning methods.
  `NotesManager` becomes a store (a hook backed by
  `useSyncExternalStore`, or a small class with subscribers in place of
  `NotificationCenter`), with the per-note debounce implemented via
  `setTimeout` keyed by note id and the write-ordering guarantee
  implemented as a per-instance promise chain, exactly mirroring
  `performStorage(_:)`'s `storageChain`.
- **AppKit / UIKit**: The six sources given here — `Note.swift`,
  `NoteFolder.swift`, `NoteStorage.swift`, `NoteTaxonomyProviding.swift`,
  `MarkdownNoteStorage.swift`, and `NotesManager.swift`, all under
  `packages/apple/AgenticToolkit/macOS/Features/NotesWindow/` — are the
  source platform: a macOS-only target consumed by
  `NotesCoordinator`/`NotesSplitViewController` (out of scope for this
  recipe) via `NotificationCenter` observation and `@MainActor` calls.
  `Note`, `NoteFolder`, and `MarkdownNoteStorage` are `Sendable`;
  `NotesManager` is itself `@MainActor`, and every storage call it issues
  runs off the main actor through `Task.detached`, serialized into its
  own `storageChain` (see `notesmanager-confined-to-primary-thread` and
  `notesmanager-storage-off-primary-thread`). `NoteFolder`'s explicit,
  non-accidental `Hashable` conformance exists because an `NSOutlineView`
  bridges a Swift value lacking that conformance to a boxed object whose
  hash falls back to that box's own identity, so two
  differently-boxed-but-equal folders from two separate `reload()`s would
  hash unequally and `isItemExpanded(_:)`/`row(forItem:)` could never
  match one across a reload (see `notefolder-value-semantics`).
  `MarkdownNoteStorage` persists through SQLite via GRDB, and neither it
  nor `NotesManager` add Keychain storage or any protection beyond what
  that store applies (see Privacy). Nothing in these six files is itself
  AppKit-specific — they import only `Foundation`, `os`,
  `AgenticToolkitCore`, `AgenticToolkitMarkdown`, and
  `AgenticToolkitDatabase` — so the same files would compile unchanged
  into a UIKit iOS target.
- **WinUI 3**: `Note`/`NoteFolder` become a `record`/`class` pair (or a
  lightweight `INotifyPropertyChanged` model if the folder tree needs to
  bind directly to a `TreeView`). `NoteStorage` becomes an interface
  returning `Task<T>` per method. `NotesManager` becomes a class backed
  by an `ObservableCollection<Note>` in place of `notes`, replacing
  `notesDidChangeNotification`/`storageDidFailNotification` with
  `INotifyCollectionChanged` and a plain C# event; a
  `SemaphoreSlim(1, 1)` awaited before each storage call reproduces the
  one-at-a-time, issue-ordered `storageChain`, and a
  `System.Threading.Timer` per note id, restarted on each edit,
  reproduces `KeyedDebouncer`'s per-key debounce-with-retry.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/NotesWindow/` |

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

**Decision** (AppKit/macOS): `NotesManager` runs every storage call off the main actor, but re-serializes them into one `storageChain` so they still execute strictly in the order they were issued.
**Rationale**: Each write hands storage a whole `Note` snapshot taken on the main actor. Before storage moved off the main actor, issue order and execution order were the same thing for free — no suspension point existed inside a call. Detaching each call independently would silently give that up, letting a stale content-save land after a newer pin-toggle write and resurrect superseded content.
**Approved**: pending

**Decision** (AppKit/macOS): A debounced save whose write throws stays pending and is retried with backoff (via `KeyedDebouncer`), rather than being dropped after a log line.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/notes/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
