<!-- leaf: implement-file/tree-outline-view-controller--part-2 · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller — continued (part 2)

**Rules** (cite as `implement-file/tree-outline-view-controller--part-2#<slug>`):

- `top-level-rows-are-managers` MUST
- `child-ordering-directories-first` MUST
- `hidden-file-visibility` MUST
- `empty-root-placeholder-text` MUST
- `placeholder-not-selectable` MUST
- `unread-directory-shows-triangle` MUST
- `leaf-hides-triangle` MUST
- `expand-loads-children-lazily` MUST
- `expand-watches-children-publisher` MUST
- `children-arrival-reloads-subtree-only` MUST
- `children-arrival-preserves-expansion-and-selection` MUST
- `collapse-stops-watching-children` MUST
- `expand-persists-to-restoration` MUST
- `collapse-persists-to-restoration` MUST
- `programmatic-expand-collapse-not-persisted` MUST
- `lone-root-auto-expands-once` MUST
- `restore-expanded-paths-on-reload` MUST
- `restore-descends-incrementally` MUST
- `missing-selection-abandonment` MUST
- `select-root-sets-target-root` MUST
- `select-node-sets-node-and-target-root` MUST
- `select-persists-path-unless-restore-pending` MUST
- `select-opens-file` MUST
- `open-skips-plain-directories` MUST
- `open-opens-files-and-packages` MUST
- `external-selection-highlights-and-scrolls` MUST
- `external-selection-suppresses-writeback` MUST
- `external-deselect-clears-highlight` MUST
- `target-root-header-emphasis` MUST
- `target-root-change-redraws-headers` MUST
- `managers-list-change-reloads` MUST
- `root-node-change-reloads` MUST
- `syncing-change-reloads` MUST
- `reload-preserves-selection` MUST
- `reload-clears-selection-when-row-gone` MUST
- `path-lookup-correct-after-structural-change` MUST
- `row-lookup-avoids-full-scan` SHOULD
- `dirty-updates-row-in-place` MUST
- `dirty-falls-back-to-item-reload` MUST
- `dirty-ignored-when-row-not-drawn` MUST
- `dirty-marker-always-built` MUST
- `reveal-noop-if-already-shown` MUST
- `reveal-expands-drawn-ancestors` MUST
- `reveal-selects-and-scrolls-when-drawn` MUST
- `reveal-writes-model-directly` MUST
- `reveal-defers-when-not-drawn` MUST
- `reveal-nothing-clears-selection` MUST

## Behavioral Requirements

- **top-level-rows-are-managers**: The outline's top-level rows MUST be
  exactly `roots.managers`, one row per `FileTreeManager`, in the order that
  array supplies.
- **child-ordering-directories-first**: Rows for a directory's contents MUST
  list subdirectories before files, each group sorted alphabetically and
  case-insensitively (`FileTreeNode.loadChildren`).
- **hidden-file-visibility**: Rows MUST include hidden
  (dot-prefixed) files and directories, but MUST NOT include a `.DS_Store`
  entry (`FileTreeNode.loadChildren`).
- **empty-root-placeholder-text**: A root manager with no children currently
  loaded MUST render a single placeholder row reading "Scanning…" while
  `manager.isSyncing` is `true`, or "Empty" otherwise.
- **placeholder-not-selectable**: A placeholder row MUST NOT be selectable.
- **unread-directory-shows-triangle**: A directory whose contents have not yet
  been read (`children == []`) MUST be reported expandable, so its disclosure
  triangle appears before anything is known to be inside it.
- **leaf-hides-triangle**: A file, a package, or a directory whose read
  completed with nothing inside (`children == nil`) MUST NOT be reported
  expandable.
- **expand-loads-children-lazily**: Expanding a directory row MUST call
  `loadChildrenIfNeeded()` on its node, which starts an asynchronous read of
  that one directory's contents.
- **expand-watches-children-publisher**: Expanding a directory row MUST begin
  watching that node's `children` publisher (`watchChildren(of:)`) so the rows
  update once the read finishes.
- **children-arrival-reloads-subtree-only**: When a watched directory's
  children publish a new value, only that item's row and subtree MUST be
  reloaded (`reloadItem(_:reloadChildren:)`); the rest of the outline MUST NOT
  be reloaded.
- **children-arrival-preserves-expansion-and-selection**: A subtree reload
  triggered by arriving children MUST re-expand the item if it was expanded
  immediately beforehand, and MUST restore whichever row was selected
  beforehand, provided that row is still present afterward.
- **collapse-stops-watching-children**: Collapsing a directory row MUST remove
  its child-change subscription.
- **expand-persists-to-restoration**: A user-initiated expansion (one not
  performed while restoring state) MUST record that path as expanded in
  `restoration` (`setExpanded(true, path:)`).
- **collapse-persists-to-restoration**: A user-initiated collapse MUST record
  that path as not expanded in `restoration` (`setExpanded(false, path:)`).
- **programmatic-expand-collapse-not-persisted**: An expansion or collapse
  performed by the controller itself — restoring saved disclosure, expanding
  a reveal's ancestors, or `collapseAllForTesting()` — MUST NOT be written to
  `restoration`.
- **lone-root-auto-expands-once**: The first time the outline reloads while
  `restoration.expandedPaths` is empty and there is exactly one root manager,
  that root MUST be expanded automatically; this automatic expansion MUST
  happen at most once for the life of the controller.
- **restore-expanded-paths-on-reload**: After any full reload, every currently
  drawn row whose path `restoration.isExpanded(path)` reports `true`, and
  which is not already expanded, MUST be expanded.
- **restore-descends-incrementally**: Restoring a selected path more than one
  unread level deep MUST proceed one additional level per reload triggered by
  that level's children arriving, rather than requiring the whole path to be
  drawn in a single pass.
- **missing-selection-abandonment**: If the directory that should contain
  a pending restored selection is drawn, expanded, and has finished reading
  its contents without that path appearing in them, the pending restoration
  MUST be dropped rather than left standing indefinitely.
- **select-root-sets-target-root**: Selecting a root's header row MUST set
  `selection.selectedRoot` to that root's URL.
- **select-node-sets-node-and-target-root**: Selecting a file or directory row
  MUST set `selection.selectedNode` to that row's node, and, if the node's URL
  falls under one of `directories`' roots, MUST also set
  `selection.selectedRoot` to that root.
- **select-persists-path-unless-restore-pending**: A selection change MUST be
  written to `restoration.setSelectedPath(_:)`, except while a selection
  restore from a previous launch is still pending.
- **select-opens-file**: Selecting a row MUST invoke `openIfFile(_:)` with the
  newly selected node.
- **open-skips-plain-directories**: `openIfFile(_:)` MUST NOT invoke
  `onOpenRequest` for a node that is a directory and not a package.
- **open-opens-files-and-packages**: `openIfFile(_:)` MUST invoke
  `onOpenRequest` with the node's URL and `.current` for a file or a package.
- **external-selection-highlights-and-scrolls**: When `selection.selectedNode`
  changes to a value different from what the outline currently has selected,
  and the corresponding row is drawn, that row MUST become the outline's
  selection and MUST be scrolled into view.
- **external-selection-suppresses-writeback**: Applying an externally-driven
  selection change (the previous requirement) MUST NOT cause that same value
  to be written back into `selection` through the outline's own
  selection-changed delegate callback.
- **external-deselect-clears-highlight**: When `selection.selectedNode`
  becomes `nil` while a `FileTreeNode` row is the outline's selection, the
  outline MUST deselect all rows.
- **target-root-header-emphasis**: The root header row whose URL equals
  `selection.selectedRoot` MUST render its label with the `.primaryText` role;
  every other root header row MUST render with `.secondaryText`.
- **target-root-change-redraws-headers**: A change to `selection.selectedRoot`
  MUST reload the outline so header emphasis is redrawn; a republish of the
  same value MUST NOT trigger a reload.
- **managers-list-change-reloads**: A change to `roots.managers` MUST rebuild
  the per-manager subscriptions and reload the outline.
- **root-node-change-reloads**: A change to any manager's `rootNode` MUST
  reload the outline.
- **syncing-change-reloads**: A change to any manager's `isSyncing` MUST
  reload the outline.
- **reload-preserves-selection**: A full reload MUST re-select whatever row
  was selected immediately beforehand, if that row (by identity, or by path
  when identity changed) is still present afterward.
- **reload-clears-selection-when-row-gone**: If the row selected before a full
  reload is a `FileTreeNode` and is no longer present afterward (by identity
  or by path), `selection.selectedNode` MUST be set to `nil`.
- **path-lookup-correct-after-structural-change**: A lookup for the row
  currently displaying a given path MUST return the row that is actually
  showing that path (or report "not drawn") immediately after any reload,
  expansion, or collapse — never a stale answer left over from before that
  change.
- **row-lookup-avoids-full-scan**: A path lookup SHOULD be answered from a
  cached path-to-row index rather than scanning every drawn row on each call,
  rebuilding that index only when a structural change may have invalidated it.
- **dirty-updates-row-in-place**: A document open, change, dirty-state-change,
  or close event for a URI whose row is drawn and whose row view is currently
  instantiated MUST update only that row view's unsaved-changes marker
  (`setDirty(_:)`), without reloading or reselecting anything.
- **dirty-falls-back-to-item-reload**: If the drawn row's view has been
  recycled away, the same event MUST instead reload that one item, in a way
  that does not clear the outline's current selection.
- **dirty-ignored-when-row-not-drawn**: A document event for a URI with no
  currently drawn row MUST be ignored.
- **dirty-marker-always-built**: A file row's unsaved-changes marker view MUST
  always be constructed as part of the row, and MUST be shown or hidden rather
  than added or removed after construction.
- **reveal-noop-if-already-shown**: Calling `reveal(_:)` with the URL already
  selected MUST do nothing.
- **reveal-expands-drawn-ancestors**: Calling `reveal(_:)` MUST expand every
  ancestor directory of the target URL that is currently drawn and not
  already expanded.
- **reveal-selects-and-scrolls-when-drawn**: If the target row is drawn once
  its ancestors are expanded, `reveal(_:)` MUST select it and scroll it into
  view.
- **reveal-writes-model-directly**: `reveal(_:)` and `revealNothing()` MUST
  write the resulting selection into `selection.selectedNode` (and
  `selection.selectedRoot`, when the URL falls under a known root) directly,
  rather than relying on the outline's own selection-changed delegate
  callback to do it.
- **reveal-defers-when-not-drawn**: If the target row is not yet drawn,
  `reveal(_:)` MUST record it as a pending selection that later reloads
  complete once the relevant directory's contents arrive.
- **reveal-nothing-clears-selection**: Calling `revealNothing()` MUST deselect
  all rows and MUST set `selection.selectedNode` to `nil`.
