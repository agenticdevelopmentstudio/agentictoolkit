<!-- leaf: implement-file/tree-outline-view-controller--test-vectors · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-tree-outline-001 | top-level-rows-are-managers | Construct with `roots.managers` containing three `FileTreeManager`s. | The outline has exactly 3 top-level rows, in that order. |
| file-tree-outline-002 | child-ordering-directories-first | Expand a directory containing `zeta.txt`, `Alpha/`, `beta.txt`. | Rows appear as `Alpha/`, `beta.txt`, `zeta.txt`. |
| file-tree-outline-003 | hidden-file-visibility | Expand a directory containing `.env`, `.DS_Store`, `readme.md`. | `.env` and `readme.md` appear as rows; `.DS_Store` does not. |
| file-tree-outline-004 | empty-root-placeholder-text | A root manager with no `rootNode` children, `isSyncing == true`, then set to `false`. | Placeholder row reads "Scanning…", then "Empty" after the change. |
| file-tree-outline-005 | placeholder-not-selectable | Attempt to click-select a placeholder row. | The outline's selection does not change to the placeholder row. |
| file-tree-outline-006 | unread-directory-shows-triangle | A directory node with `children == []`. | `isItemExpandable` returns `true` for that node. |
| file-tree-outline-007 | leaf-hides-triangle | A file node, and a directory node whose read completed with `children == nil`. | `isItemExpandable` returns `false` for both. |
| file-tree-outline-008 | expand-loads-children-lazily | Expand an unread directory row. | `loadChildrenIfNeeded()` is called on that node. |
| file-tree-outline-009 | expand-watches-children-publisher | Expand a directory row, then publish a new `children` value on its node. | The row's subtree reloads without a further explicit call. |
| file-tree-outline-010 | children-arrival-reloads-subtree-only | Expand one directory among several drawn rows; its children arrive. | Only that directory's row/subtree is reloaded; sibling rows are untouched. |
| file-tree-outline-011 | children-arrival-preserves-expansion-and-selection | Expand directory A, select a file inside it, then have A's children publish again. | A remains expanded and the same file remains selected afterward. |
| file-tree-outline-012 | collapse-stops-watching-children | Expand then collapse a directory, then publish new `children` on its node. | No reload occurs as a result of that publish. |
| file-tree-outline-013 | expand-persists-to-restoration | Expand a directory row by clicking its disclosure triangle. | `restoration.isExpanded(path)` becomes `true` for that path. |
| file-tree-outline-014 | collapse-persists-to-restoration | Collapse a previously expanded directory row. | `restoration.isExpanded(path)` becomes `false` for that path. |
| file-tree-outline-015 | programmatic-expand-collapse-not-persisted | Call `collapseAllForTesting()`, then reload the outline while `restoration` still marks those paths expanded. | `restoration`'s stored expanded set is unchanged by the collapse-all call itself; after the reload, those same paths are re-expanded per `restore-expanded-paths-on-reload`, since their entries in `restoration` were never cleared. |
| file-tree-outline-016 | lone-root-auto-expands-once | Construct with one root manager and an empty `restoration.expandedPaths`; reload; collapse the root; reload again. | The root auto-expands on the first reload only; it stays collapsed after the user closes it and a later reload. |
| file-tree-outline-017 | restore-expanded-paths-on-reload | Set `restoration` to mark two drawn directory paths expanded, then reload. | Both directories are expanded after the reload. |
| file-tree-outline-018 | restore-descends-incrementally | Set a pending restored selection three unread levels deep, then reload. | The selection is reached only after 3 triggered reloads, one per unread level: after the 1st and 2nd, one further ancestor is expanded and the target row is still not drawn; after the 3rd, the target row is drawn, becomes selected, and `pendingSelectionPath` is cleared. |
| file-tree-outline-019 | missing-selection-abandonment | Set a pending restored selection for a file that has since been deleted, with its parent directory drawn, expanded, and fully read. | The pending selection is cleared and no further restoration attempt occurs. |
| file-tree-outline-020 | select-root-sets-target-root | Click a root header row. | `selection.selectedRoot` equals that root's URL. |
| file-tree-outline-021 | select-node-sets-node-and-target-root | Click a file row under root R. | `selection.selectedNode` is that file's node; `selection.selectedRoot` becomes R. |
| file-tree-outline-022 | select-persists-path-unless-restore-pending | Click a file row with no pending restoration in progress. | `restoration.selectedPath` equals that file's path. |
| file-tree-outline-023 | select-opens-file | Click a file row. | `onOpenRequest` is called with that file's URL and `.current`. |
| file-tree-outline-024 | open-skips-plain-directories | Click a plain (non-package) directory row. | `onOpenRequest` is not called. |
| file-tree-outline-025 | open-opens-files-and-packages | Click a package row. | `onOpenRequest` is called with the package's URL and `.current`. |
| file-tree-outline-026 | external-selection-highlights-and-scrolls | Set `selection.selectedNode` to a drawn, off-screen row from outside the outline. | That row becomes selected and is scrolled into view. |
| file-tree-outline-027 | external-selection-suppresses-writeback | Perform the previous scenario. | `selection.selectedNode` is not reassigned a second time as a side effect. |
| file-tree-outline-028 | external-deselect-clears-highlight | With a `FileTreeNode` row selected, set `selection.selectedNode` to `nil`. | The outline's selection is cleared. |
| file-tree-outline-029 | target-root-header-emphasis | Set `selection.selectedRoot` to root B among three roots. | Root B's header renders `.primaryText`; the other two render `.secondaryText`. |
| file-tree-outline-030 | target-root-change-redraws-headers | Set `selection.selectedRoot` to the same value it already holds. | No reload occurs. |
| file-tree-outline-031 | managers-list-change-reloads | Append a new `FileTreeManager` to `roots.managers`. | The outline reloads and shows the new root. |
| file-tree-outline-032 | root-node-change-reloads | Replace a manager's `rootNode`. | The outline reloads. |
| file-tree-outline-033 | syncing-change-reloads | Toggle a manager's `isSyncing`. | The outline reloads. |
| file-tree-outline-034 | reload-preserves-selection | Select a file, then trigger a full reload without removing that file. | The same file remains selected afterward. |
| file-tree-outline-035 | reload-clears-selection-when-row-gone | Select a file, delete its underlying node from the model, then trigger a full reload. | `selection.selectedNode` becomes `nil`. |
| file-tree-outline-036 | path-lookup-correct-after-structural-change | Expand a directory (adding rows), then immediately look up the row for a path below it. | The lookup returns the row currently showing that path, not a pre-expansion index. |
| file-tree-outline-037 | row-lookup-avoids-full-scan | Build two outlines that differ only in drawn-row count (e.g. 50 rows vs. 5,000), perform one lookup in each to build its index, then time a second lookup for the same path in each with no structural change between calls. | The second lookup's time does not scale with the number of drawn rows: the 5,000-row outline's second lookup is not measurably slower than the 50-row outline's — an O(1) index hit rather than the O(rows) scan a linear implementation would show. |
| file-tree-outline-038 | dirty-updates-row-in-place | Mark an open, drawn file's document dirty. | Only that row's marker becomes visible; no reload or reselection occurs. |
| file-tree-outline-039 | dirty-falls-back-to-item-reload | Mark a drawn file dirty after its row view has been recycled away by the outline. | That one item is reloaded, and the current selection is unchanged afterward. |
| file-tree-outline-040 | dirty-ignored-when-row-not-drawn | Fire a dirty-state-change event for a file whose row is not currently drawn (its parent is collapsed). | No row update, reload, or crash occurs. |
| file-tree-outline-041 | dirty-marker-always-built | Inspect a clean file's row view. | The marker view exists in the view hierarchy and is hidden. |
| file-tree-outline-042 | reveal-noop-if-already-shown | Call `reveal(url)` for the URL that is already selected. | No selection, expansion, or scroll change occurs. |
| file-tree-outline-043 | reveal-expands-drawn-ancestors | Call `reveal(url)` for a file two collapsed, drawn levels deep. | Both ancestor directories expand. |
| file-tree-outline-044 | reveal-selects-and-scrolls-when-drawn | Call `reveal(url)` for a file whose row becomes drawn after its ancestors expand. | That row is selected and scrolled into view. |
| file-tree-outline-045 | reveal-writes-model-directly | Call `reveal(url)` for a drawn target. | `selection.selectedNode` equals the revealed node without relying on a separate selection click. |
