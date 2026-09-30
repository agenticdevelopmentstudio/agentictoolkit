<!-- leaf: implement-file/tree-outline-view-controller--part-5 · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller — continued (part 5)

## Platform Notes

- **SwiftUI**: The source is pure AppKit (`NSViewController`/`NSOutlineView`),
  deliberately, not SwiftUI — the file's own header comment states that a
  SwiftUI `List` row's tap gesture does not fire reliably when attached to
  arbitrary row content, and that a directory's row, being a disclosure-group
  label, is not something a `List` will select at all; `NSOutlineView`
  selects on mouse-down for every row it draws, which this component relies
  on directly. A SwiftUI port would need `OutlineGroup` or a hand-rolled
  recursive `DisclosureGroup`/`List` combination verified specifically for
  whole-row tap and directory-row selection before adopting it, not a
  drop-in `List(rootNode, children: \.children)`.
- **Compose**: Flatten the currently-visible nodes (respecting each
  directory's expanded/collapsed state) into a single list driven by a
  `LazyColumn`, the way a Compose file-tree is conventionally built; back
  expansion/selection with `remember`/`mutableStateOf` or a `ViewModel`
  exposing `StateFlow`s equivalent to `FileBrowserSelection`/
  `FileBrowserRestorationState`, and trigger a lazy child load from the same
  "row entered the visible window and is a directory with no children yet"
  condition this file expresses as `outlineViewItemWillExpand`.
- **React/Web**: Model the tree as a virtualized list or a headless tree
  library (row-per-visible-node, like the Compose approach) rather than
  nested `<ul>`/`<li>` DOM for every directory, to avoid the DOM cost of a
  large monorepo tree; a row's whole clickable area maps to a single
  `onClick` handler rather than a nested interactive control, mirroring why
  this file avoids a component-per-row tap gesture.
- **AppKit / UIKit**: This is the source platform. `FileTreeOutlineViewController.swift`
  configures a single-column `NSOutlineView` (`ThemedOutlineView`) with
  `rowHeight = 22`, `indentationPerLevel = 14`, `style = .inset`, and a
  hidden header, driving it as both `NSOutlineViewDataSource` and
  `NSOutlineViewDelegate`. `NSOutlineView` itself has no direct iOS
  counterpart (`UIOutlineView` does not exist), but a `UICollectionView`
  configured with `UICollectionLayoutListConfiguration` and driven by an
  `NSDiffableDataSourceSectionSnapshot` has supported a native, hierarchical,
  disclosure-triangle outline since iOS 14 — that combination, not a manually
  flattened/indented `UITableView`, is the platform-idiomatic substitute.
- **WinUI 3**: Model the
  tree as a `TreeView` bound to a hierarchical `ItemsSource` mirroring
  `FileTreeManager`/`FileTreeNode` (one top-level `TreeViewNode` per root,
  matching `top-level-rows-are-managers`); use `TreeViewNode.HasUnrealizedChildren`
  plus the `Expanding` event to drive the same lazy-load-on-first-expand
  behavior as `expand-loads-children-lazily`, and the `Collapsed`/`Expanded`
  events to persist disclosure the way `expand-persists-to-restoration`/
  `collapse-persists-to-restoration` do. Drive `TreeView.SelectionChanged`
  into the same selection/target-root logic as
  `select-node-sets-node-and-target-root`, and use `TreeView.ItemInvoked`
  (or a double-tap gesture) for `double-click-opens-otherwise`. Build the
  context menu from `TreeViewItem.ContextFlyout` populated with
  `MenuFlyoutItem`s in the same Open/Open-in-New-Tab/Open-to-the-Side,
  separator, Reveal, Copy-Path order as `context-menu-item-order`, keyed off
  the flyout's own target node rather than the current selection — the WinUI
  analog of `context-menu-uses-clicked-row`. Represent the root-header
  emphasis (`target-root-header-emphasis`) as a `FontWeight`/`Foreground`
  binding on each root `TreeViewNode`'s content, driven by whichever root is
  the current target. Render the git-status badge as a `TextBlock` whose text
  and `Foreground` both bind to the node's status through a value converter
  mirroring `GitFileStatus.nsColor`'s fixed enum-to-color mapping, and the
  unsaved-changes marker as a small `Ellipse`/`FontIcon` whose `Visibility`
  binds to the same dirty flag, always present in the item template and
  toggled by binding rather than added/removed — the WinUI analog of
  `dirty-marker-always-built`.

## Design Decisions

**Decision**: Use `NSOutlineView` rather than a SwiftUI `List` for the tree.
**Rationale**: the file's own header comment states a SwiftUI list row's tap
gesture attached to the row's content never fires, and a directory's row,
being a disclosure-group label, is not something a `List` will select at
all — half the tree answered a click with nothing. `NSOutlineView` selects on
mouse-down for every row it draws, which is the behavior this component
needs.
**Approved**: pending.

**Decision**: Use `children == nil` for a leaf, a package, *and* a directory that
was read and found empty — rather than reserving `nil` for leaves only — and
disambiguate the "was this a directory?" question downstream in
`openIfFile(_:)` via `!isDirectory || isPackage`, not via the children value
itself.
**Rationale**: `FileTreeNode` deliberately sets `children = nil` (not `[]`) for a
directory that reads empty, "so the outline reads an empty array as
'expandable, not yet read'" — keeping `[]` would leave a disclosure triangle
that opens onto nothing. `openIfFile(_:)`'s own guard is what then stops a
double-click or single-click on that now-leaf-shaped empty directory from
being sent to the document viewer as if it were a file.
**Approved**: pending.

**Decision**: Cache path→row lookups (`rowIndexByPath`) lazily, and verify a
cache hit against the row's actual content before trusting it, rather than
either always scanning or always trusting the cache.
**Rationale**: the source comment explains this controller is a
`TextDocumentStore` observer, so every keystroke in *any* open document, in
*every* open file browser, used to cost an O(rows) path-string scan; the
verify-before-trust step exists because a stale hit would otherwise silently
redraw or reselect the wrong file rather than fail loudly.
**Approved**: pending.

**Decision**: Use two independent guard flags, `isSyncingSelection` and
`isSyncingExpansion`, rather than a single "the controller is currently
driving the outline" flag.
**Rationale**: each guards a different feedback loop — `isSyncingSelection`
stops a model-driven selection change from being reported back through
`outlineViewSelectionDidChange`, and `isSyncingExpansion` stops a
restoration- or reveal-driven expand/collapse from being reported back
through `outlineViewItemDidExpand`/`outlineViewItemDidCollapse` — and the two
kinds of programmatic change do not always happen together (restoring
disclosure without touching selection, or vice versa).
**Approved**: pending.

**Decision**: `reveal(_:)`/`revealNothing()` write `selection.selectedNode` and
`selection.selectedRoot` directly (`adoptRevealedSelection(_:)`) instead of
relying on the outline's own selection-changed delegate callback to record
the change.
**Rationale**: the source comment distinguishes "the highlight" from "the
selection" — `isSyncingSelection` deliberately stops the outline's own report
from being written back (so a reveal is not echoed to whatever editor pane it
came from), which would otherwise leave `selection` naming a stale file and
`selectedRoot` pointing at the wrong project root.
**Approved**: pending.

**Decision**: Restore a deeply nested expanded/selected path incrementally,
across as many reloads as the depth requires, rather than requiring the
whole path to already be drawn.
**Rationale**: expanding a directory only *starts* an asynchronous read of its
contents; the source comment explains the loop terminates naturally because
a pass that expands nothing triggers no further reload, so a fixed-depth
single pass would leave anything below the first unread level permanently
unrestored.
**Approved**: pending.

**Decision**: Leave `selection.selectedRoot`/orphaned-selection cleanup, when a
root disappears entirely, to the hosting `FileBrowserViewController` rather
than handling it in this file.
**Rationale**: `reselect(_:)` only clears `selection.selectedNode` when the
outgoing selection was a `FileTreeNode`; a selected root *header*
(`FileTreeManager`) that disappears from a reload is not cleared here. The
sibling `file-browser-view-controller` recipe's
`teardown-clears-orphaned-root-selection` requirement is what actually
guarantees `selection.selectedRoot` is cleared when its root is removed.
**Approved**: pending.
