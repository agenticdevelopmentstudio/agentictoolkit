---
id: ded9b397-958d-437d-8235-48ef85ae7386
title: Project Layout Persistence
domain: agentictoolkit://cookbook/workspace/projects/project-database-layout
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: SQLite persistence for a project's tab arrangement, split-tree layout,
  pane state, and extra browsed directories, scoped to one git_repo row.
platforms:
- swift
- macos
tags:
- git
- projects
- persistence
- sqlite
- database
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
- agentictoolkit://cookbook/workspace/projects/git-repo
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase+Layout.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectDatabaseLayoutTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectDatabaseWorkingDirectoryTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Layout Persistence

## Overview

This is an extension of the project database that persists everything a
project window's tab-and-pane arrangement needs to survive a relaunch: the
tabs docked to each edge, the split tree of panes inside each tab, per-pane
UI state (sizes, expansion, selection — whatever a caller stores under a
string key), and the extra directories a project's file browser shows
beyond the repository root. The project database itself owns the SQLite
connection, the schema migrations that create the five tables this
extension reads and writes (`project_tabs`, `layout_nodes`,
`project_state`, `pane_state`, `project_directories`), and the low-level
execute/query helpers this extension calls; this extension adds no schema
and no connection state of its own — it is purely a set of operations
layered onto the base component.

Every row this extension touches is scoped to one `repo_id`, matching a
`git_repo.id` row owned by the project database's core methods; nothing
here reads or writes a row for any repository id other than the one a
caller passes in. The project database carries no concurrency-safety
guarantee of its own (see the sibling
`agentictoolkit://cookbook/workspace/projects/project-database` recipe),
so this extension's operations carry no concurrency guarantee of their own
either — they run wherever the caller runs, synchronously, against one
shared SQLite connection.

## Behavioral Requirements

### Reading tabs

- **load-tabs-empty-default** — Loading tabs MUST return `(tabs: [],
  activeTabID: nil, enabledEdges: [top])` for a repository id with no
  `project_tabs` or `project_state` rows.
- **load-tabs-order** — MUST return tabs ordered ascending by the
  `project_tabs.position` column, via `ORDER BY position` in the query.
- **load-tabs-malformed-row-dropped** — MUST silently exclude a
  `project_tabs` row from the returned list when its `id` or
  `root_node_id` column fails to parse as a valid identifier.
- **load-tabs-corrupt-row-signal**: NEEDS REVIEW: Not implemented in
  source. Neither loading tabs nor reading node rows throws, logs, or
  otherwise signals when a row is dropped for failing identifier parsing;
  a caller has no way to detect that its persisted arrangement came back
  incomplete. Resolving this needs either a design decision that this can
  only happen from manual file tampering (this extension is the schema's
  only writer) or an error/signal path added to loading tabs.
- **load-tabs-edge-fallback** — MUST default a tab's edge to the top edge
  when the stored `edge` column is `NULL` or fails to parse as a valid
  edge value.
- **load-tabs-title-fallback** — MUST default a tab's title to the empty
  string when the stored `title` column is `NULL`.
- **load-tabs-group-id-fallback** — MUST fall back to the tab's own id for
  its group id when the stored `group_id` column is `NULL` or fails
  identifier parsing, defaulting a tab record's group id to its own id
  when none was stored.
- **load-tabs-working-directory-empty-to-nil** — MUST map an empty-string
  `working_directory` column to an absent value rather than to a location,
  so an unset working directory round-trips as unset rather than as the
  process's current directory.
- **load-tabs-working-directory-is-directory-url** — MUST construct any
  non-empty `working_directory` value as a directory location, always
  marking it as a directory regardless of whether it currently exists on
  disk.
- **load-tabs-tree-reconstruction** — MUST reconstruct each tab's root
  layout-node tree from `layout_nodes` rows, resolving a split row into
  exactly two ordered children by position.
- **load-tabs-active-tab-default** — MUST read `active_tab_id` and
  `enabled_edges` from the single `project_state` row for the repository
  id, or fall back to (no active tab, the top edge alone) when no such row
  exists.
- **load-tabs-active-tab-consistency**: Loading tabs reads
  `project_tabs`/`layout_nodes` and `project_state` as two separate,
  non-transactional statements, and never re-validates the returned
  active-tab id against the returned tabs, unlike writing tabs' validation
  check on write. This component carries no concurrency-safety guarantee
  of its own and loading tabs is synchronous, so no write on the same
  instance can run between the two reads; a commit through a different
  connection to the same file between them can make the returned
  active-tab id name no tab in the result.
- **load-tabs-enabled-edges-fallback** — MUST discard a stored
  `enabled_edges` value that is empty, or that parses to zero valid edge
  entries, and keep the default (the top edge alone) rather than return an
  empty list.

### Writing tabs

- **save-tabs-whole-replace** — Writing tabs MUST replace the entire
  arrangement for a repository id: it deletes every existing
  `project_tabs`, `layout_nodes`, and `project_state` row for that
  repository id before reinserting from the given tabs.
- **save-tabs-atomic-rollback** — MUST wrap the whole replace in `BEGIN
  IMMEDIATE TRANSACTION` / `COMMIT`, and MUST roll back and rethrow the
  original error unchanged if any step fails, leaving the previously
  persisted arrangement intact.
- **save-tabs-default-enabled-edges** — The enabled edges MUST default to
  the top edge alone when the caller omits them.
- **save-tabs-tab-position** — MUST persist each tab's
  `project_tabs.position` as its index in the given tab list, in that
  order.
- **save-tabs-tree-insert-order** — MUST insert each tab's root node, and
  recursively its children, assigning a split's two children position 0
  and 1 in first/second order and a parent id equal to the split's own id.
- **save-tabs-active-tab-validated** — MUST validate the active-tab id
  against the given tab list and persist `NULL` for
  `project_state.active_tab_id` when it names no tab in that list, rather
  than persist a reference to a tab that was not saved.
- **save-tabs-state-row-always-written** — MUST always insert exactly one
  `project_state` row for the repository id, even when the validated
  active tab is absent, so the enabled edges still persist.
- **save-tabs-enabled-edges-canonical-order** — MUST persist the enabled
  edges as a comma-joined string in a fixed canonical order (top, right,
  bottom, left), filtered to only the edges present in the caller's
  argument — not in the argument's own order.
- **save-tabs-pane-state-orphan-sweep** — MUST delete every `pane_state`
  row for the repository id whose `node_id` is absent from the
  just-rewritten `layout_nodes` for that repository id.
- **save-tabs-pane-state-content-change-sweep** — MUST additionally delete
  a `pane_state` row for any `node_id` whose leaf content type differs
  between the previous arrangement and the new one, even when that node id
  is still present in the new `layout_nodes`.
- **insert-node-column-nulls-by-kind** — Inserting a node MUST write
  `NULL` for `orientation` on a leaf row and `NULL` for
  `content_type`/`pane_label` on a split row.

### Rebuilding the tree

- **build-tree-missing-node-error** — Rebuilding the tree MUST throw an
  invalid-schema error when a referenced node id — the root, or either
  split child — is absent from the fetched rows.
- **build-tree-split-child-count** — MUST throw an invalid-schema error
  when a row whose `kind` is split has any number of children other than
  exactly 2.
- **build-tree-unknown-kind-error** — MUST throw an invalid-schema error
  when a row's `kind` column is neither "leaf" nor "split".
- **build-tree-orientation-fallback** — MUST default a split's orientation
  to horizontal when the stored `orientation` value is `NULL` or fails to
  parse as a valid orientation.
- **build-tree-content-type-fallback** — MUST default a leaf's content
  type to the placeholder content type when the stored `content_type`
  column is `NULL`.
- **fetch-node-rows-malformed-id-dropped** — Reading node rows MUST
  silently exclude any `layout_nodes` row whose `id` column fails
  identifier parsing from the returned collection; this is the same class
  of gap as **load-tabs-corrupt-row-signal** above, one level lower.

### Pane state

- **pane-state-read** — Reading pane state MUST return the stored value
  for the exact (repository id, node id, key) triple, or nothing when no
  such row exists.
- **pane-state-write-upsert** — Setting pane state with a present value
  MUST upsert via `INSERT ... ON CONFLICT(repo_id, node_id, key) DO UPDATE
  SET value = excluded.value`, so writing the same triple twice replaces
  the row rather than duplicating it.
- **pane-state-write-nil-deletes** — Setting pane state with an absent
  value MUST delete the row rather than persist an empty string.
- **prune-nested-pane-state-scope** — Pruning nested pane state MUST
  delete only `pane_state` rows under (repository id, node id) whose key
  embeds at least one dot-separated identifier component absent from the
  given live-ids set, and MUST leave untouched any key with no identifier
  component.
- **prune-nested-pane-state-read-then-delete** — MUST fully exhaust the
  `SELECT` over candidate rows before issuing any `DELETE`, matching this
  component's own design rationale that deleting from a table while
  stepping a cursor over it is undefined in SQLite.

### Project directories

- **project-directories-order** — Loading project directories MUST return
  paths ordered by the stored `position` column.
- **project-directories-empty-means-none** — an empty `project_directories`
  result MUST be treated as "this project has no extra browsed
  directories," not as "this project has never been saved".
- **project-directories-whole-replace** — Saving project directories MUST
  delete every existing `project_directories` row for the repository id
  and reinsert the given paths at their list index as position, inside
  one transaction that rolls back and rethrows on failure.

### Concurrency and lifetime

- **caller-must-synchronize-cross-thread-access** — This component's
  underlying store MUST be treated as unsafe to share across concurrency
  domains without the caller's own synchronization; every operation in
  this extension inherits that lack of built-in isolation, so a caller
  MUST NOT share one instance across concurrency domains without its own
  synchronization.
- **write-serialized-via-busy-timeout** — a writer contending for the same
  database file MUST wait up to 5000ms (via SQLite's busy-timeout
  mechanism) before the underlying call surfaces a busy failure as an
  execution or prepare failure; this extension does not retry beyond that
  timeout.
- **cascade-delete-on-repo-removal** — deleting a `git_repo` row MUST
  cascade-delete every `project_tabs`, `layout_nodes`, `project_state`,
  `pane_state`, and `project_directories` row for that repository id, via
  the `ON DELETE CASCADE` foreign keys declared on each table's `repo_id`
  column. `pane_state.node_id` carries no foreign key of its own — which
  is why **save-tabs-pane-state-orphan-sweep** and
  **prune-nested-pane-state-scope** exist as explicit application-level
  sweeps rather than relying on cascade.

## Appearance

Not applicable: this is a non-UI persistence extension — it renders
nothing and owns no view.

## States

Not applicable: this component has no view lifecycle states. Its only
state machine is the migration/transaction sequencing described under
Behavioral Requirements (**save-tabs-atomic-rollback**,
**project-directories-whole-replace**) and the crash-recovery behavior
documented on the base project database component (its idempotent, `IF
NOT EXISTS`/conditional-`ALTER`-guarded migrations, exercised by this
extension's own working-directory test fixture that crashes
mid-migration).

## Accessibility

Not applicable: this component has no UI surface to make accessible.

## Conformance Test Vectors

1. `git-client-projects-project-database-layout-001` — Loading tabs on a
   repository id with no rows → no tabs, no active tab, the top edge alone
   (empty-project case backing **load-tabs-empty-default**).
2. `git-client-projects-project-database-layout-002` — Writing two tabs,
   then loading tabs on the same repository id → tabs returned in the same
   order, each root tree structurally equal to what was saved (backing
   **save-tabs-whole-replace**, **load-tabs-order**,
   **load-tabs-tree-reconstruction**).
3. `git-client-projects-project-database-layout-003` — Writing tabs with
   the active-tab id set to an identifier not present in the tab list →
   loading tabs returns no active tab (backing
   **save-tabs-active-tab-validated**).
4. `git-client-projects-project-database-layout-004` — Two tabs sharing
   one group id, saved and reloaded → both come back tagged with the same
   group id (backing **load-tabs-group-id-fallback** on the
   non-fallback path).
5. `git-client-projects-project-database-layout-005` — Writing tabs for
   repository A and, separately, for repository B → loading tabs for A is
   unaffected by B's arrangement (backing the repo-scoping guarantee in
   Overview).
6. `git-client-projects-project-database-layout-006` — Setting pane state
   with a thickness fraction, then reading pane state on the same triple →
   the same value round-trips, and an unset pane's thickness fraction
   stays absent rather than coercing to 0.0 (backing **pane-state-read**,
   **pane-state-write-upsert**).
7. `git-client-projects-project-database-layout-007` — Setting pane state
   to an absent value on a triple that previously had a value → a
   subsequent read for that triple returns nothing (backing
   **pane-state-write-nil-deletes**).
8. `git-client-projects-project-database-layout-008` — Closing a pane and
   pruning nested pane state with the surviving ids as the live-ids set →
   keys naming the closed pane's id are removed, keys with no identifier
   component are untouched (backing **prune-nested-pane-state-scope**).
9. `git-client-projects-project-database-layout-009` — Saving project
   directories ["/a", "/b"] then loading them → ["/a", "/b"] in the same
   order; a second save with an empty list then reload → an empty list
   (backing **project-directories-whole-replace**,
   **project-directories-empty-means-none**).
10. `git-client-projects-project-database-layout-010` — A working
    directory containing a space and a non-ASCII character, saved and
    reloaded → the exact same path string, constructed as a directory
    location (backing **load-tabs-working-directory-is-directory-url**).
11. `git-client-projects-project-database-layout-011` — A fresh database
    opened at the current schema version and a hand-built
    schema-version-3 fixture opened the same way → both migrate/open
    successfully and the working directory round-trips on the migrated
    database (backing the crash-recovery note under States).

## Edge Cases

- **Empty/missing input**: A repository id with zero rows → loading tabs'
  documented default tuple (**load-tabs-empty-default**); writing tabs
  with an empty tab list → every existing row for the repository id is
  deleted and `project_state.active_tab_id` is written `NULL`
  (**save-tabs-state-row-always-written**); saving an empty
  project-directories list → the table ends empty for the repository id
  (**project-directories-whole-replace**); setting pane state to an
  absent value on a key with no existing row is a no-op delete, not an
  error (the delete matches zero rows silently).
- **Distinguishing "empty" from "absent"**: `pane_state.value` is `TEXT
  NOT NULL`, so a caller can persist the empty string `""` as a real
  value, distinct from reading pane state returning nothing for a row
  that does not exist at all.
- **Malformed persisted data**: a `project_tabs`/`layout_nodes` row with
  an unparseable identifier is dropped rather than surfaced
  (**load-tabs-malformed-row-dropped**,
  **fetch-node-rows-malformed-id-dropped**, both tied to the
  **load-tabs-corrupt-row-signal** gap); a `layout_nodes` row with a
  `kind` outside {"leaf","split"}, a split row with other than exactly two
  children, or a tree with a dangling child reference instead throws an
  invalid-schema error rather than being silently dropped
  (**build-tree-unknown-kind-error**, **build-tree-split-child-count**,
  **build-tree-missing-node-error**) — this file has no test coverage
  exercising any of those three throw paths.
- **Boundary values**: Tab/node positions are stored as SQLite integers
  with no range check in this extension — a tab or sibling-child list
  whose index exceeds what the underlying binding call accepts is not
  guarded here; a thickness fraction of exactly `0.0` is a distinct, valid
  stored value from absent (unsized) per test vector 6.
- **Concurrent access to one repository id**: covered by
  **load-tabs-active-tab-consistency** above — the same instance cannot
  interleave a write between loading tabs' two reads, and a commit
  through another connection is not guarded against; concurrent access to
  two different repository ids is unaffected by each other (test
  vector 5).
- **Error states**: a SQLite prepare or step failure at any point in
  writing tabs or saving project directories throws a prepare-failure or
  execution-failure error from the inherited execute helpers and rolls
  back the open transaction (**save-tabs-atomic-rollback**); the
  rollback's own `ROLLBACK` statement discards its own result so a
  rollback failure cannot mask or replace the original error, which is
  rethrown unchanged.
- **Disk/filesystem failure mid-write**: not distinguished from any other
  execution-failure/prepare-failure case above — a full disk or a revoked
  file permission surfaces through the same inherited error path as a
  malformed statement; nothing in this extension retries or backs off.
- **Offline/disconnected**: Not applicable — this component makes no
  network call; its only external dependency is the local SQLite file the
  project database opened.
- **Cancellation/timeouts**: Not applicable — every operation in this
  extension is synchronous, so there is nothing to cancel; the only
  timeout in play is the connection-level busy-timeout already covered
  under **write-serialized-via-busy-timeout**.

## Configuration

| Input | Supplied by | Default | Effect |
|---|---|---|---|
| `repoID` | caller, every public method | none (required) | Scopes every read/write to one repository id; no method here accepts an unscoped or wildcard query. |
| `tabs` | caller, writing tabs | none (required) | The whole tab-and-tree arrangement to persist; replaces whatever was previously stored for the repository id. |
| `activeTabID` | caller, writing tabs | none (required, may be absent) | Persisted only if it names one of the given tabs; otherwise dropped to `NULL` (**save-tabs-active-tab-validated**). |
| `enabledEdges` | caller, writing tabs | the top edge alone | Which tab-bar edges are shown; persisted in canonical order regardless of the argument's own order. |
| `nodeID`, `key` | caller, pane-state operations | none (required) | Identifies one pane-scoped state slot. |
| `value` | caller, setting pane state | none (required, may be absent) | An absent value deletes the row; any other value upserts it verbatim, with no format validation. |
| `liveIDs` | caller, pruning nested pane state | none (required) | The set of node ids the caller currently considers alive; anything embedded in a stored key but absent from this set is pruned. |
| `paths` | caller, saving project directories | none (required) | The full replacement list of extra browsed directories for the repository id, in order. |

This extension reads no environment variable and no settings key of its
own; the database file's location is entirely the base project database's
concern, not this extension's.

## Deep Linking

Not applicable: this extension defines no URL scheme, route, or deep-link
target — it is called directly by in-process calls, not addressed from
outside the process.

## Localization

Not applicable: this file contains no user-facing string literal. The
diagnostic strings embedded in the invalid-schema errors it throws
(**build-tree-missing-node-error**, **build-tree-split-child-count**,
**build-tree-unknown-kind-error**) carry no localized-description
conformance in the given source, so nothing in this file formats a string
for display to an end user.

## Accessibility Options

Not applicable: this component has no UI surface for an accessibility
option to affect.

## Feature Flags

Not applicable: no build configuration, feature flag, or capability check
gates any behavior in this file — every method runs unconditionally once
called.

## Analytics

Not applicable: this file contains no analytics or event-tracking call.

## Privacy

This extension persists user-chosen filesystem paths and arbitrary
caller-supplied strings to local disk:

- **Data persisted**: a tab record's working directory (an absolute
  filesystem path, may embed the user's home-directory name),
  `project_directories.path` (absolute filesystem paths),
  `pane_state.value` (an arbitrary string set by the caller — file paths,
  selection state, or other UI state), and a tab record's title
  (user-chosen or caller-generated text).
- **Storage**: written to the same local SQLite file the base project
  database opens; this extension applies no encryption of its own, and
  nothing in the project database's setup sets an encryption pragma.
- **Transmission**: none — this file makes no network call anywhere.
- **Retention**: rows persist until explicitly replaced or deleted — a
  whole-arrangement replace on every write-tabs/save-project-directories
  call, a cascade delete when the owning `git_repo` row is deleted
  (**cascade-delete-on-repo-removal**), and an explicit sweep for orphaned
  `pane_state` rows (**save-tabs-pane-state-orphan-sweep**,
  **prune-nested-pane-state-scope**); nothing here expires a row by age.

## Logging

Not applicable: this extension contains no logging call anywhere,
including on its error and drop paths — this is precisely the gap named
in **load-tabs-corrupt-row-signal**.

## Platform Notes

- **SwiftUI**: this extension itself has no SwiftUI dependency — it
  imports only `Foundation` and calls the C `SQLite3` API through the
  base class's helpers; a SwiftUI caller observes its results the same way
  an AppKit caller does, through whatever wrapper (e.g. an
  `ObservableObject`) the call site builds around `loadTabs`/`saveTabs`.
  The base `ProjectDatabase` is a `public final class` with no `Sendable`
  conformance and no `actor`/`@MainActor` isolation — the mechanism behind
  **caller-must-synchronize-cross-thread-access** — so this extension's
  methods carry no concurrency guarantee of their own. `ProjectDatabaseError`
  is likewise declared `public enum ProjectDatabaseError: Error` with no
  `Sendable` conformance, so the error type itself carries the same
  absence of a compiler-enforced concurrency-safety marker as the store it
  is thrown from.
- **AppKit/UIKit**: same as SwiftUI — no direct AppKit dependency in this
  file; the file's location under `macOS/Features/Projects` reflects
  where the base `ProjectDatabase` and its call sites live today, not a
  hard macOS-only API dependency in this extension's own code.
- **Compose (Android)**: use Room or `android.database.sqlite.SQLiteDatabase`
  in place of the raw `SQLite3` C calls; represent `LayoutNode` as a
  Kotlin `sealed class` (`Leaf`/`Split`) in place of Swift's `indirect
  enum`, `Edge` as a Kotlin `enum class`, and serialize the same
  whole-replace/transaction pattern through Room's `@Transaction`
  methods; because `ProjectDatabase` is not `Sendable` here, the Android
  equivalent should confine writes to a single coroutine dispatcher (e.g.
  `Dispatchers.IO` behind a `Mutex`) rather than assume SQLite's own
  locking is enough.
- **React/Web**: there is no native filesystem or SQLite file; use
  IndexedDB or a WASM SQLite (e.g. wa-sqlite) inside a Worker, and treat
  `workingDirectory`/`project_directories.path` as opaque identifiers
  (e.g. a File System Access API handle key) rather than real filesystem
  paths, since a browser has no equivalent of
  `URL(fileURLWithPath:isDirectory:)`.
- **WinUI 3**: use `Microsoft.Data.Sqlite` with parameterized
  `SqliteCommand`s mirroring the `?`-bound statements here, and a
  `SqliteTransaction` wrapping each whole-replace exactly as
  `saveTabs`/`saveProjectDirectories` wrap theirs in `BEGIN
  IMMEDIATE`/`COMMIT`; represent `LayoutNode` as an `abstract record
  LayoutNode` with `LeafNode`/`SplitNode` subtypes in place of Swift's
  `indirect enum`, and `Edge`/`ComposableTabsAxis` as C# `enum`s; set
  `SqliteConnection`'s command timeout to mirror `sqlite3_busy_timeout`'s
  5000ms rather than relying on the driver's own default.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase+Layout.swift` |

## Design Decisions

- **Whole-arrangement replace instead of a diff.** `saveTabs` and `saveProjectDirectories` both delete everything for `repoID` and reinsert from the argument, rather than diffing against what is stored.
  Why: the caller already holds the complete, current arrangement in memory (there is no incremental "move this one tab" entry point), so a diff would duplicate state the caller already reconciled for no benefit.
  Trade-off: every save rewrites every row for `repoID`, even when only one field changed, and any two-statement read racing a save sees a representation that briefly does not exist (**load-tabs-active-tab-consistency**).

- **`pane_state.node_id` carries no foreign key.** The `pane_state` table's `repo_id` cascades from `git_repo`, but its `node_id` column references no other table (`ProjectDatabase.swift`).
  Why: a pane's node id changes shape across saves — a leaf can be replaced by a different leaf carrying the same visual slot — so a hard foreign key to `layout_nodes.id` would either block a legitimate rewrite or require deleting and reinserting `pane_state` on every save regardless of whether that pane survived.
  Trade-off: orphaned `pane_state` rows are only removed by the application-level sweeps in **save-tabs-pane-state-orphan-sweep** and **prune-nested-pane-state-scope**; a caller that saves tabs through a path other than `saveTabs` (there is none in this extension) could leave orphans behind indefinitely.

- **Content-change sweep beyond id-based orphaning.** `saveTabs` deletes a `pane_state` row when a still-present node id's leaf `contentType` changed, not only when the id itself disappeared.
  Why: a node id can be reused across a rebuild for a pane that now shows different content (per `LayoutNode.swift`'s `reshaped(toMatch:)` id-reuse contract), and pane state keyed to the old content (e.g. a scroll position for a file that is no longer there) would otherwise silently apply to the new content.
  Trade-off: this requires reading the previous arrangement's leaf content types before the delete, adding a second full tree walk to every `saveTabs` call.

- **`activeTabID` validated on write, not on read.** `saveTabs` drops an `activeTabID` that names no tab in `tabs` to `NULL` before persisting; `loadTabs` performs no equivalent check on the way out (**load-tabs-active-tab-consistency**).
  Why: at write time the full, authoritative `tabs` array is right there in the same call; at read time, re-validating would mean either a second query or holding both result sets in a shared transaction, which the current two-statement read does not do.
  Trade-off: the write-side guarantee only holds until the next write from any caller; a read racing a concurrent write is not covered by it, which is exactly the residual gap the marker names.

- **`working_directory` empty string means unset, not "here".** An empty `working_directory` column maps to `nil`, never to a `URL` for the empty path or the current directory.
  Why: `TabRecord.workingDirectory == nil` has an existing meaning elsewhere in the type ("use the project directory"); coercing an empty string to a concrete `URL` would silently reassign that meaning to whatever directory the process happened to be running in when the row was read.
  Trade-off: `isDirectory: true` is forced on every non-empty value even when the directory no longer exists on disk, so a moved or deleted working directory round-trips as a URL that fails to resolve rather than as `nil`.

## Compliance

| Check | Status | Notes |
|---|---|---|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | This extension owns only the layout/tabs/pane-state/directories schema and queries; connection setup, migrations, and the shared `execute`/`executeBound`/`forEachRow`/`bindText`/`columnText` primitives all stay in the base `ProjectDatabase.swift`, and this file adds no UI, networking, or presentation code of its own. |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | `ProjectDatabaseLayoutTests.swift` and `ProjectDatabaseWorkingDirectoryTests.swift` cover every happy-path round-trip in this extension (tabs, ordering, active-tab validity, groups, cross-project isolation, pane size/state, pruning, project directories, migration) with 24 test methods between them, but a grep for `invalidSchema`, `buildTree`, `prepareFailed`, `executionFailed`, and `openFailed` across all three test files in this target returns zero matches — none of `buildTree`'s three throw paths (**build-tree-missing-node-error**, **build-tree-split-child-count**, **build-tree-unknown-kind-error**) is exercised by a test. |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | `buildTree` throws a typed `ProjectDatabaseError.invalidSchema` for every malformed-tree case it can detect (missing node, wrong split-child count, unknown kind), and `saveTabs`/`saveProjectDirectories` roll back and rethrow unchanged on any failure — but `loadTabs`/`fetchNodeRows` handle a malformed row's UUID by silently dropping it rather than by raising or logging anything, which is the gap named in **load-tabs-corrupt-row-signal**. |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Every multi-row write in this file (`saveTabs`, `saveProjectDirectories`) is wrapped in an explicit transaction with rollback on failure, and `saveTabs` validates `activeTabID` against `tabs` before persisting — but `loadTabs` performs its two reads outside any shared transaction and applies no equivalent validation to what it returns, which is the gap named in **load-tabs-active-tab-consistency**. |

Notes: both `partial` findings above trace to the same underlying property of this extension — every integrity check it makes (the malformed-row guards, the `activeTabID` validation) sits on the write side; the read side (`loadTabs`, `fetchNodeRows`) trusts what is in the tables and either drops what it cannot parse or returns it unvalidated. Given that this extension is the only writer of these five tables, that asymmetry may be an acceptable design rather than a defect, but nothing in the given source states that invariant explicitly, which is why both gaps are marked rather than resolved.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial recipe, documenting `ProjectDatabase+Layout.swift` as of its current form — tab/tree/pane-state/project-directories persistence, the two open gaps around malformed-row signaling and read-side active-tab consistency, and the schema-migration crash-recovery behavior it inherits from the base `ProjectDatabase`. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
