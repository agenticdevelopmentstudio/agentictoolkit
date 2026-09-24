---
id: ded9b397-958d-437d-8235-48ef85ae7386
title: ProjectDatabase+Layout
domain: agentictoolkit://recipes/git-client-projects-project-database-layout
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- agentictoolkit://recipes/composable-tabs-window-controller
- agentictoolkit://recipes/git-client-projects-git-repo
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

# ProjectDatabase+Layout

## Overview

`ProjectDatabase+Layout.swift` is a `ProjectDatabase` extension that persists everything a project window's tab-and-pane arrangement needs to survive a relaunch: the tabs docked to each edge, the split tree of panes inside each tab, per-pane UI state (sizes, expansion, selection — whatever a caller stores under a string key), and the extra directories a project's file browser shows beyond the repository root. `ProjectDatabase` itself (`ProjectDatabase.swift`) owns the SQLite connection, the schema migrations that create the five tables this extension reads and writes (`project_tabs`, `layout_nodes`, `project_state`, `pane_state`, `project_directories`), and the low-level `execute`/`executeBound`/`forEachRow` helpers this extension calls; this extension adds no schema and no connection state of its own — it is purely a set of methods layered onto the base class.

Every row this extension touches is scoped to one `repo_id`, matching a `git_repo.id` row owned by `ProjectDatabase`'s core methods; nothing here reads or writes a row for any `repoID` other than the one a caller passes in. `ProjectDatabase` is a `public final class` with no `Sendable` conformance and no `actor`/`@MainActor` isolation (`ProjectDatabase.swift`), so this extension's methods carry no concurrency guarantee of their own — they run wherever the caller runs, synchronously, against one shared SQLite connection.

## Behavioral Requirements

### Reading tabs

- **load-tabs-empty-default** — `loadTabs(repoID:)` MUST return `(tabs: [], activeTabID: nil, enabledEdges: [.top])` for a `repoID` with no `project_tabs` or `project_state` rows.
- **load-tabs-order** — MUST return tabs ordered ascending by the `project_tabs.position` column, via `ORDER BY position` in the query.
- **load-tabs-malformed-row-dropped** — MUST silently exclude a `project_tabs` row from the returned array when its `id` or `root_node_id` column fails `UUID(uuidString:)` parsing (`guard ... else { return }` inside the row callback).
- **load-tabs-corrupt-row-signal**: NEEDS REVIEW: Not implemented in source. Neither `loadTabs` nor `fetchNodeRows` throws, logs, or otherwise signals when a row is dropped for failing UUID parsing; a caller has no way to detect that its persisted arrangement came back incomplete. Resolving this needs either a design decision that this can only happen from manual file tampering (this extension is the schema's only writer) or an error/signal path added to `loadTabs`.
- **load-tabs-edge-fallback** — MUST default a tab's `edge` to `.top` when the stored `edge` column is `NULL` or fails `Edge(rawValue:)`.
- **load-tabs-title-fallback** — MUST default a tab's `title` to `""` when the stored `title` column is `NULL`.
- **load-tabs-group-id-fallback** — MUST fall back to the tab's own `id` for `groupID` when the stored `group_id` column is `NULL` or fails UUID parsing, via `TabRecord.init`'s `groupID ?? id` default (`LayoutNode.swift`; called from the tab loader).
- **load-tabs-working-directory-empty-to-nil** — MUST map an empty-string `working_directory` column to `nil` rather than to a URL, so an unset working directory round-trips as unset rather than as the process's current directory.
- **load-tabs-working-directory-is-directory-url** — MUST construct any non-empty `working_directory` value with `URL(fileURLWithPath:isDirectory: true)`, always passing `isDirectory: true` regardless of whether the directory currently exists on disk.
- **load-tabs-tree-reconstruction** — MUST reconstruct each tab's `root` `LayoutNode` tree from `layout_nodes` rows via `buildTree(id:rows:)`, resolving a `split` row into exactly two ordered children by `position`.
- **load-tabs-active-tab-default** — MUST read `active_tab_id` and `enabled_edges` from the single `project_state` row for `repoID`, or fall back to `(nil, [.top])` when no such row exists.
- **load-tabs-active-tab-consistency**: `loadTabs` reads `project_tabs`/`layout_nodes` and `project_state` as two separate, non-transactional statements, and never re-validates the returned `activeTabID` against the returned `tabs`, unlike `saveTabs`'s `validActive` check on write. `ProjectDatabase` is a non-`Sendable` `final class` and `loadTabs` is synchronous, so no `saveTabs` on the same instance can run between the two reads; a commit through a different SQLite connection to the same file between them can make the returned `activeTabID` name no tab in `tabs`.
- **load-tabs-enabled-edges-fallback** — MUST discard a stored `enabled_edges` value that is empty, or that parses to zero valid `Edge` entries, and keep the default `[.top]` rather than return an empty array.

### Writing tabs

- **save-tabs-whole-replace** — `saveTabs(_:activeTabID:enabledEdges:repoID:)` MUST replace the entire arrangement for `repoID`: it deletes every existing `project_tabs`, `layout_nodes`, and `project_state` row for `repoID` before reinserting from the `tabs` argument.
- **save-tabs-atomic-rollback** — MUST wrap the whole replace in `BEGIN IMMEDIATE TRANSACTION` / `COMMIT`, and MUST roll back and rethrow the original error unchanged if any step fails, leaving the previously persisted arrangement intact.
- **save-tabs-default-enabled-edges** — `enabledEdges` MUST default to `[.top]` when the caller omits it.
- **save-tabs-tab-position** — MUST persist each tab's `project_tabs.position` as its index in the `tabs` array argument, in that order.
- **save-tabs-tree-insert-order** — MUST insert each tab's root node, and recursively its children, via `insertNode`, assigning a split's two children `position` 0 and 1 in `first`/`second` order and `parent_id` equal to the split's own id.
- **save-tabs-active-tab-validated** — MUST validate `activeTabID` against the `tabs` argument and persist `NULL` for `project_state.active_tab_id` when it names no tab in `tabs`, rather than persist a reference to a tab that was not saved.
- **save-tabs-state-row-always-written** — MUST always insert exactly one `project_state` row for `repoID`, even when the validated active tab is `nil`, so `enabledEdges` still persists.
- **save-tabs-enabled-edges-canonical-order** — MUST persist `enabledEdges` as a comma-joined string in `Edge.allCases`'s fixed order (top, right, bottom, left), filtered to only the edges present in the caller's argument — not in the argument's own order.
- **save-tabs-pane-state-orphan-sweep** — MUST delete every `pane_state` row for `repoID` whose `node_id` is absent from the just-rewritten `layout_nodes` for that `repoID`.
- **save-tabs-pane-state-content-change-sweep** — MUST additionally delete a `pane_state` row for any `node_id` whose leaf `contentType` differs between the previous arrangement and the new one, even when that node id is still present in the new `layout_nodes`.
- **insert-node-column-nulls-by-kind** — `insertNode` MUST write `NULL` for `orientation` on a leaf row and `NULL` for `content_type`/`pane_label` on a split row.

### Rebuilding the tree

- **build-tree-missing-node-error** — `buildTree(id:rows:)` MUST throw `ProjectDatabaseError.invalidSchema` when a referenced node id — the root, or either split child — is absent from the fetched rows.
- **build-tree-split-child-count** — MUST throw `ProjectDatabaseError.invalidSchema` when a row whose `kind` is `split` has any number of children other than exactly 2.
- **build-tree-unknown-kind-error** — MUST throw `ProjectDatabaseError.invalidSchema` when a row's `kind` column is neither `"leaf"` nor `"split"`.
- **build-tree-orientation-fallback** — MUST default a split's orientation to `.horizontal` when the stored `orientation` value is `NULL` or fails `ComposableTabsAxis(rawValue:)`.
- **build-tree-content-type-fallback** — MUST default a leaf's `contentType` to `ComposableTabsViewID.placeholder` when the stored `content_type` column is `NULL`.
- **fetch-node-rows-malformed-id-dropped** — `fetchNodeRows(repoID:)` MUST silently exclude any `layout_nodes` row whose `id` column fails `UUID(uuidString:)` parsing from the returned dictionary; this is the same class of gap as **load-tabs-corrupt-row-signal** above, one level lower.

### Pane state

- **pane-state-read** — `paneState(repoID:nodeID:key:)` MUST return the stored `value` for the exact `(repoID, nodeID, key)` triple, or `nil` when no such row exists.
- **pane-state-write-upsert** — `setPaneState(repoID:nodeID:key:value:)` with a non-nil `value` MUST upsert via `INSERT ... ON CONFLICT(repo_id, node_id, key) DO UPDATE SET value = excluded.value`, so writing the same triple twice replaces the row rather than duplicating it.
- **pane-state-write-nil-deletes** — `setPaneState` with `value: nil` MUST delete the row rather than persist an empty string.
- **prune-nested-pane-state-scope** — `pruneNestedPaneState(repoID:nodeID:keeping:)` MUST delete only `pane_state` rows under `(repoID, nodeID)` whose `key` embeds at least one dot-separated UUID component absent from `liveIDs`, and MUST leave untouched any key with no UUID component.
- **prune-nested-pane-state-read-then-delete** — MUST fully exhaust the `SELECT` over candidate rows before issuing any `DELETE`, matching its own comment that deleting from a table while stepping a cursor over it is undefined in SQLite.

### Project directories

- **project-directories-order** — `loadProjectDirectories(repoID:)` MUST return paths ordered by the stored `position` column.
- **project-directories-empty-means-none** — an empty `project_directories` result MUST be treated as "this project has no extra browsed directories," not as "this project has never been saved".
- **project-directories-whole-replace** — `saveProjectDirectories(_:repoID:)` MUST delete every existing `project_directories` row for `repoID` and reinsert `paths` at their array index as `position`, inside one transaction that rolls back and rethrows on failure.

### Concurrency and lifetime

- **non-sendable-isolation** — `ProjectDatabase` MUST be treated as non-`Sendable`: it is declared `public final class ProjectDatabase` with no `Sendable` conformance, no `actor` keyword, and no `@MainActor` isolation anywhere in `ProjectDatabase.swift`; every method in this extension inherits that lack of isolation, so a caller MUST NOT share one instance across concurrency domains without its own synchronization.
- **error-type-non-sendable** — `ProjectDatabaseError` MUST likewise be treated as non-`Sendable`: it is declared `public enum ProjectDatabaseError: Error` with no `Sendable` conformance (`ProjectDatabase.swift`).
- **write-serialized-via-busy-timeout** — a writer contending for the same database file MUST wait up to 5000ms (`sqlite3_busy_timeout(database, 5_000)`, `ProjectDatabase.swift`) before the underlying call surfaces `SQLITE_BUSY` as `ProjectDatabaseError.executionFailed`/`.prepareFailed` from `execute`/`executeBound`; this extension does not retry beyond that timeout.
- **cascade-delete-on-repo-removal** — deleting a `git_repo` row via `ProjectDatabase.delete(id:)` (`ProjectDatabase.swift`) MUST cascade-delete every `project_tabs`, `layout_nodes`, `project_state`, `pane_state`, and `project_directories` row for that `repoID`, via the `ON DELETE CASCADE` foreign keys declared on each table's `repo_id` column (`ProjectDatabase.swift`). `pane_state.node_id` carries no foreign key of its own — which is why **save-tabs-pane-state-orphan-sweep** and **prune-nested-pane-state-scope** exist as explicit application-level sweeps rather than relying on cascade.

## Appearance

Not applicable: this is a non-UI persistence extension — it renders nothing and owns no view.

## States

Not applicable: this component has no view lifecycle states. Its only state machine is the migration/transaction sequencing described under Behavioral Requirements (**save-tabs-atomic-rollback**, **project-directories-whole-replace**) and the crash-recovery behavior documented on the base class (`ProjectDatabase.swift`'s idempotent, `IF NOT EXISTS`/conditional-`ALTER`-guarded migrations, exercised by `ProjectDatabaseWorkingDirectoryTests.swift`'s crash-mid-migration fixture).

## Accessibility

Not applicable: this component has no UI surface to make accessible.

## Conformance Test Vectors

1. `git-client-projects-project-database-layout-001` — `loadTabs(repoID:)` on a `repoID` with no rows → `(tabs: [], activeTabID: nil, enabledEdges: [.top])` (`ProjectDatabaseLayoutTests.swift`, empty-project case backing **load-tabs-empty-default**).
2. `git-client-projects-project-database-layout-002` — `saveTabs` with two tabs, then `loadTabs` on the same `repoID` → tabs returned in the same order, each `root` tree structurally equal to what was saved (`ProjectDatabaseLayoutTests.swift` tabs-round-trip and ordering tests, backing **save-tabs-whole-replace**, **load-tabs-order**, **load-tabs-tree-reconstruction**).
3. `git-client-projects-project-database-layout-003` — `saveTabs` with `activeTabID` set to a UUID not present in `tabs` → `loadTabs` returns `activeTabID: nil` (`ProjectDatabaseLayoutTests.swift` active-tab-validity/drop test, backing **save-tabs-active-tab-validated**).
4. `git-client-projects-project-database-layout-004` — two tabs sharing one `groupID`, saved and reloaded → both come back tagged with the same `groupID` (`ProjectDatabaseLayoutTests.swift` tab-groups test, backing **load-tabs-group-id-fallback** on the non-fallback path).
5. `git-client-projects-project-database-layout-005` — `saveTabs` called for `repoID` A and, separately, for `repoID` B → `loadTabs(repoID: A)` is unaffected by B's arrangement (`ProjectDatabaseLayoutTests.swift` cross-project-isolation test, backing the repo-scoping guarantee in Overview).
6. `git-client-projects-project-database-layout-006` — `setPaneState` with a `thicknessFraction`, then `paneState` on the same triple → the same value round-trips, and an unset pane's `thicknessFraction` stays `nil` rather than coercing to `0.0` (`ProjectDatabaseLayoutTests.swift` pane-size round-trip / unsized-pane-stays-nil tests, backing **pane-state-read**, **pane-state-write-upsert**).
7. `git-client-projects-project-database-layout-007` — `setPaneState(..., value: nil)` on a triple that previously had a value → a subsequent `paneState` call for that triple returns `nil` (`ProjectDatabaseLayoutTests.swift` pane-state-delete test, backing **pane-state-write-nil-deletes**).
8. `git-client-projects-project-database-layout-008` — closing a pane and calling `pruneNestedPaneState` with the surviving ids in `liveIDs` → keys naming the closed pane's id are removed, keys with no UUID component are untouched (`ProjectDatabaseLayoutTests.swift` pane-state-pruning-on-close test, backing **prune-nested-pane-state-scope**).
9. `git-client-projects-project-database-layout-009` — `saveProjectDirectories(["/a", "/b"])` then `loadProjectDirectories` → `["/a", "/b"]` in the same order; a second `saveProjectDirectories([])` then reload → `[]` (`ProjectDatabaseLayoutTests.swift` project-directories round-trip test, backing **project-directories-whole-replace**, **project-directories-empty-means-none**).
10. `git-client-projects-project-database-layout-010` — a `working_directory` containing a space and a non-ASCII character, saved and reloaded → the exact same path string, constructed with `isDirectory: true` (`ProjectDatabaseWorkingDirectoryTests.swift`, backing **load-tabs-working-directory-is-directory-url**).
11. `git-client-projects-project-database-layout-011` — a fresh database opened at `ProjectDatabase.currentSchemaVersion == 4` and a hand-built schema-version-3 fixture opened the same way → both migrate/open successfully and `working_directory` round-trips on the migrated database (`ProjectDatabaseWorkingDirectoryTests.swift` migration and crash-mid-migration-recovery tests, backing the crash-recovery note under States).

## Edge Cases

- **Empty/missing input**: `repoID` with zero rows → `loadTabs`'s documented default tuple (**load-tabs-empty-default**); `saveTabs` with an empty `tabs` array → every existing row for `repoID` is deleted and `project_state.active_tab_id` is written `NULL` (**save-tabs-state-row-always-written**); `saveProjectDirectories([])` → the table ends empty for `repoID` (**project-directories-whole-replace**); `setPaneState(..., value: nil)` on a key with no existing row is a no-op delete, not an error (the `DELETE` matches zero rows silently).
- **Distinguishing "empty" from "absent"**: `pane_state.value` is `TEXT NOT NULL`, so a caller can persist the empty string `""` as a real value, distinct from `paneState` returning `nil` for a row that does not exist at all.
- **Malformed persisted data**: a `project_tabs`/`layout_nodes` row with an unparseable UUID is dropped rather than surfaced (**load-tabs-malformed-row-dropped**, **fetch-node-rows-malformed-id-dropped**, both tied to the **load-tabs-corrupt-row-signal** gap); a `layout_nodes` row with a `kind` outside `{"leaf","split"}`, a `split` row with other than exactly two children, or a tree with a dangling child reference instead throws `ProjectDatabaseError.invalidSchema` rather than being silently dropped (**build-tree-unknown-kind-error**, **build-tree-split-child-count**, **build-tree-missing-node-error**) — this file has no test coverage exercising any of those three throw paths (confirmed by grep over `ProjectDatabaseTests.swift`/`ProjectDatabaseLayoutTests.swift`/`ProjectDatabaseWorkingDirectoryTests.swift` for `invalidSchema`, `buildTree`, `prepareFailed`, `executionFailed`, `openFailed`: no matches).
- **Boundary values**: `Int` tab/node positions are cast to SQLite's `INTEGER` with no range check in this extension — a `tabs` or sibling-child array whose index exceeds what `sqlite3_bind_int` accepts is not guarded here; a `thicknessFraction` of exactly `0.0` is a distinct, valid stored value from `nil` (unsized) per test vector 6.
- **Concurrent access to one `repoID`**: covered by **load-tabs-active-tab-consistency** above — the same instance cannot interleave a `saveTabs` between `loadTabs`'s two reads, and a commit through another connection is not guarded against; concurrent access to two different `repoID`s is unaffected by each other (test vector 5).
- **Error states**: a SQLite prepare or step failure at any point in `saveTabs`/`saveProjectDirectories` throws `ProjectDatabaseError.prepareFailed`/`.executionFailed` from the inherited `execute`/`executeBound` helpers and rolls back the open transaction (**save-tabs-atomic-rollback**); the rollback's own `ROLLBACK` statement is issued with `try?` (its result is discarded) so a rollback failure cannot mask or replace the original error, which is rethrown unchanged.
- **Disk/filesystem failure mid-write**: not distinguished from any other `executionFailed`/`prepareFailed` case above — a full disk or a revoked file permission surfaces through the same inherited error path as a malformed statement; nothing in this extension retries or backs off.
- **Offline/disconnected**: Not applicable — this component makes no network call; its only external dependency is the local SQLite file `ProjectDatabase` opened.
- **Cancellation/timeouts**: Not applicable — every method in this extension is synchronous and non-`async`, so there is nothing to cancel; the only timeout in play is the connection-level `sqlite3_busy_timeout` already covered under **write-serialized-via-busy-timeout**.

## Configuration

| Input | Supplied by | Default | Effect |
|---|---|---|---|
| `repoID: UUID` | caller, every public method | none (required) | Scopes every read/write to one `git_repo.id`; no method here accepts an unscoped or wildcard query. |
| `tabs: [TabRecord]` | caller, `saveTabs` | none (required) | The whole tab-and-tree arrangement to persist; replaces whatever was previously stored for `repoID`. |
| `activeTabID: UUID?` | caller, `saveTabs` | none (required, may be `nil`) | Persisted only if it names one of `tabs`; otherwise dropped to `NULL` (**save-tabs-active-tab-validated**). |
| `enabledEdges: [Edge]` | caller, `saveTabs` | `[.top]` | Which tab-bar edges are shown; persisted in `Edge.allCases` order regardless of the argument's own order. |
| `nodeID: UUID`, `key: String` | caller, `paneState`/`setPaneState`/`pruneNestedPaneState` | none (required) | Identifies one pane-scoped state slot. |
| `value: String?` | caller, `setPaneState` | none (required, may be `nil`) | A `nil` value deletes the row; any other value upserts it verbatim, with no format validation. |
| `liveIDs: Set<UUID>` | caller, `pruneNestedPaneState` | none (required) | The set of node ids the caller currently considers alive; anything embedded in a stored key but absent from this set is pruned. |
| `paths: [String]` | caller, `saveProjectDirectories` | none (required) | The full replacement list of extra browsed directories for `repoID`, in order. |

This extension reads no environment variable and no user-defaults/settings key of its own; the database file's location is entirely the base `ProjectDatabase`'s concern (`ProjectDatabase.swift`'s `init(path:)`), not this extension's.

## Deep Linking

Not applicable: this extension defines no URL scheme, route, or deep-link target — it is called directly by Swift call sites, not addressed from outside the process.

## Localization

Not applicable: this file contains no user-facing string literal. The diagnostic strings embedded in the `ProjectDatabaseError.invalidSchema` cases it throws (**build-tree-missing-node-error**, **build-tree-split-child-count**, **build-tree-unknown-kind-error**) carry no `errorDescription`/`LocalizedError` conformance in the given source, so nothing in this file formats a string for display to an end user.

## Accessibility Options

Not applicable: this component has no UI surface for an accessibility option to affect.

## Feature Flags

Not applicable: no build configuration, feature flag, or capability check gates any behavior in this file — every method runs unconditionally once called.

## Analytics

Not applicable: this file contains no analytics or event-tracking call.

## Privacy

This extension persists user-chosen filesystem paths and arbitrary caller-supplied strings to local disk:

- **Data persisted**: `TabRecord.workingDirectory` (an absolute filesystem path, may embed the user's home-directory name), `project_directories.path` (absolute filesystem paths), `pane_state.value` (an arbitrary string set by the caller — file paths, selection state, or other UI state), and `TabRecord.title` (user-chosen or caller-generated text).
- **Storage**: written to the same local SQLite file the base `ProjectDatabase` opens; this extension applies no encryption of its own, and nothing in `ProjectDatabase.swift`'s setup sets an encryption pragma.
- **Transmission**: none — this file makes no network call anywhere.
- **Retention**: rows persist until explicitly replaced or deleted — a whole-arrangement replace on every `saveTabs`/`saveProjectDirectories` call, a cascade delete when the owning `git_repo` row is deleted (**cascade-delete-on-repo-removal**), and an explicit sweep for orphaned `pane_state` rows (**save-tabs-pane-state-orphan-sweep**, **prune-nested-pane-state-scope**); nothing here expires a row by age.

## Logging

Not applicable: `ProjectDatabase+Layout.swift` contains no `Logger`, `os.log`, `print`, or other logging call anywhere, including on its error and drop paths — this is precisely the gap named in **load-tabs-corrupt-row-signal**.

## Platform Notes

- **SwiftUI**: this extension itself has no SwiftUI dependency — it imports only `Foundation` and calls the C `SQLite3` API through the base class's helpers; a SwiftUI caller observes its results the same way an AppKit caller does, through whatever wrapper (e.g. an `ObservableObject`) the call site builds around `loadTabs`/`saveTabs`.
- **AppKit/UIKit**: same as SwiftUI — no direct AppKit dependency in this file; the file's location under `macOS/Features/Projects` reflects where the base `ProjectDatabase` and its call sites live today, not a hard macOS-only API dependency in this extension's own code.
- **Compose (Android)**: use Room or `android.database.sqlite.SQLiteDatabase` in place of the raw `SQLite3` C calls; represent `LayoutNode` as a Kotlin `sealed class` (`Leaf`/`Split`) in place of Swift's `indirect enum`, `Edge` as a Kotlin `enum class`, and serialize the same whole-replace/transaction pattern through Room's `@Transaction` methods; because `ProjectDatabase` is not `Sendable` here, the Android equivalent should confine writes to a single coroutine dispatcher (e.g. `Dispatchers.IO` behind a `Mutex`) rather than assume SQLite's own locking is enough.
- **React/Web**: there is no native filesystem or SQLite file; use IndexedDB or a WASM SQLite (e.g. wa-sqlite) inside a Worker, and treat `workingDirectory`/`project_directories.path` as opaque identifiers (e.g. a File System Access API handle key) rather than real filesystem paths, since a browser has no equivalent of `URL(fileURLWithPath:isDirectory:)`.
- **WinUI 3**: use `Microsoft.Data.Sqlite` with parameterized `SqliteCommand`s mirroring the `?`-bound statements here, and a `SqliteTransaction` wrapping each whole-replace exactly as `saveTabs`/`saveProjectDirectories` wrap theirs in `BEGIN IMMEDIATE`/`COMMIT`; represent `LayoutNode` as an `abstract record LayoutNode` with `LeafNode`/`SplitNode` subtypes in place of Swift's `indirect enum`, and `Edge`/`ComposableTabsAxis` as C# `enum`s; set `SqliteConnection`'s command timeout to mirror `sqlite3_busy_timeout`'s 5000ms rather than relying on the driver's own default.

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

- 1.0.0 (2026-09-24): Initial recipe, documenting `ProjectDatabase+Layout.swift` as of its current form — tab/tree/pane-state/project-directories persistence, the two open gaps around malformed-row signaling and read-side active-tab consistency, and the schema-migration crash-recovery behavior it inherits from the base `ProjectDatabase`.
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
