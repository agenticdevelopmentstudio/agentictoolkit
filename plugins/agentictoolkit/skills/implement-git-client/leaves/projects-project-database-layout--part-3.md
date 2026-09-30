<!-- leaf: implement-git-client/projects-project-database-layout--part-3 · source: git-client-projects-project-database-layout.md -->

# ProjectDatabase+Layout — continued (part 3)

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

## Privacy

This extension persists user-chosen filesystem paths and arbitrary caller-supplied strings to local disk:

- **Data persisted**: `TabRecord.workingDirectory` (an absolute filesystem path, may embed the user's home-directory name), `project_directories.path` (absolute filesystem paths), `pane_state.value` (an arbitrary string set by the caller — file paths, selection state, or other UI state), and `TabRecord.title` (user-chosen or caller-generated text).
- **Storage**: written to the same local SQLite file the base `ProjectDatabase` opens; this extension applies no encryption of its own, and nothing in `ProjectDatabase.swift`'s setup sets an encryption pragma.
- **Transmission**: none — this file makes no network call anywhere.
- **Retention**: rows persist until explicitly replaced or deleted — a whole-arrangement replace on every `saveTabs`/`saveProjectDirectories` call, a cascade delete when the owning `git_repo` row is deleted (**cascade-delete-on-repo-removal**), and an explicit sweep for orphaned `pane_state` rows (**save-tabs-pane-state-orphan-sweep**, **prune-nested-pane-state-scope**); nothing here expires a row by age.

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
