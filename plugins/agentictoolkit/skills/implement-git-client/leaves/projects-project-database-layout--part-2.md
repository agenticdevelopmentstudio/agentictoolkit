<!-- leaf: implement-git-client/projects-project-database-layout--part-2 · source: git-client-projects-project-database-layout.md -->

# ProjectDatabase+Layout — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-database-layout--part-2#<slug>`):

- `load-tabs-empty-default` MUST
- `load-tabs-order` MUST
- `load-tabs-malformed-row-dropped` MUST
- `load-tabs-edge-fallback` MUST
- `load-tabs-title-fallback` MUST
- `load-tabs-group-id-fallback` MUST
- `load-tabs-working-directory-empty-to-nil` MUST
- `load-tabs-working-directory-is-directory-url` MUST
- `load-tabs-tree-reconstruction` MUST
- `load-tabs-active-tab-default` MUST
- `load-tabs-enabled-edges-fallback` MUST
- `save-tabs-whole-replace` MUST
- `save-tabs-atomic-rollback` MUST
- `save-tabs-default-enabled-edges` MUST
- `save-tabs-tab-position` MUST
- `save-tabs-tree-insert-order` MUST
- `save-tabs-active-tab-validated` MUST
- `save-tabs-state-row-always-written` MUST
- `save-tabs-enabled-edges-canonical-order` MUST
- `save-tabs-pane-state-orphan-sweep` MUST
- `save-tabs-pane-state-content-change-sweep` MUST
- `insert-node-column-nulls-by-kind` MUST
- `build-tree-missing-node-error` MUST
- `build-tree-split-child-count` MUST
- `build-tree-unknown-kind-error` MUST
- `build-tree-orientation-fallback` MUST
- `build-tree-content-type-fallback` MUST
- `fetch-node-rows-malformed-id-dropped` MUST
- `pane-state-read` MUST
- `pane-state-write-upsert` MUST
- `pane-state-write-nil-deletes` MUST
- `prune-nested-pane-state-scope` MUST
- `prune-nested-pane-state-read-then-delete` MUST
- `project-directories-order` MUST
- `project-directories-empty-means-none` MUST
- `project-directories-whole-replace` MUST
- `non-sendable-isolation` MUST
- `error-type-non-sendable` MUST
- `write-serialized-via-busy-timeout` MUST
- `cascade-delete-on-repo-removal` MUST

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

