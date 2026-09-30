<!-- leaf: implement-composable-tabs/view-controller--part-3 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — continued (part 3)

**Rules** (cite as `implement-composable-tabs/view-controller--part-3#<slug>`):

- `remove-collapses-degenerate-split` MUST
- `remove-rehomes-focus` MUST
- `remove-persists-and-rearranges` MUST
- `move-refused-by-spec` MUST
- `move-permitted-without-spec` MUST
- `move-rebuilds-root` MUST
- `available-directions-filtered-by-spec` MUST
- `rebuild-reuses-live-panes` MUST
- `rebuild-tears-down-dropped-panes` MUST
- `rebuild-detaches-before-rehosting` MUST
- `rebuild-single-leaf-becomes-root-child` MUST
- `rebuild-carries-thickness-fractions` MUST
- `rebuild-persists-from-root` MUST
- `allowed-insertions-delegates-to-spec` MUST
- `can-remove-leaf-delegates-to-spec` MUST
- `root-split-walk-uses-is-root` MUST
- `tear-down-panes-notifies-every-leaf` MUST
- `reassign-ambiguous-pane-numbers` MUST
- `persist-tree-only-from-root` MUST
- `persist-tree-sequence` MUST
- `snapshot-unwraps-single-child` MUST
- `snapshot-empty-tree-is-placeholder` MUST
- `make-item-sizing` MUST
- `make-item-holding-priority` MUST
- `clamped-tree-has-no-minimum` MUST
- `restore-sizing-order` MUST
- `build-from-persisted-leaf-wraps-in-root-split` MUST
- `build-carries-fraction-to-child` MUST
- `close-checks-membership` MUST
- `close-honors-spec-veto-with-fallback` MUST
- `close-clears-zoom-before-removal` MUST
- `can-close-mirrors-close-refusal` MUST
- `minimize-refuses-unresolvable-edge` MUST
- `minimize-clears-zoom-first` MUST
- `minimize-pins-split-item` MUST
- `minimize-is-unconditional-on-model` MUST
- `restore-unpins-and-clears` MUST
- `zoom-toggles-and-excludes-minimize` MUST
- `zoom-collapses-off-path-items` MUST
- `zoom-preserves-tree-shape` MUST
- `persisted-state-applies-once` MUST
- `persisted-minimize-restores-if-edge-invalid` MUST
- `reapply-pane-state-is-idempotent` MUST

- **remove-collapses-degenerate-split**: When a non-root split is left with
  exactly one child after a removal, Component MUST collapse that split out of
  the tree, promoting the surviving child into the collapsing split's own slot
  (inheriting its thickness fraction) in the parent split.
- **remove-rehomes-focus**: If the removed pane held first responder,
  `remove(_:)` MUST move first responder to the root's first leaf (depth-first
  order) once removal completes.
- **remove-persists-and-rearranges**: After a `remove(_:)` call completes,
  Component MUST call `applyArrangement()` and persist the tree, both from the
  root.
- **move-refused-by-spec**: `move(_:_:)` MUST compute the candidate new tree
  via `ComposableTabsMove.moving(_:_:in:)` against the root's current snapshot,
  and MUST return `false` without mutating the tree when the project's layout
  spec disallows the resulting tree.
- **move-permitted-without-spec**: `move(_:_:)` MUST treat a resolved project
  that has no layout spec configured at all as permitting the move, rather than
  refusing it.
- **move-rebuilds-root**: When the candidate tree is permitted (by
  **move-refused-by-spec** or **move-permitted-without-spec**), `move(_:_:)`
  MUST rebuild the root from that tree and return `true`.
- **available-directions-filtered-by-spec**: `availableMoveDirections(for:)`
  MUST return only the directions, among those `ComposableTabsMove.availableDirections`
  reports, for which the resulting moved tree is allowed by the project's
  layout spec.
- **rebuild-reuses-live-panes**: `rebuild(from:)` MUST reuse an existing live
  `ComposableTabsPaneViewController` for any leaf id that survives into the
  new shape, rather than constructing a new pane controller for that id.
- **rebuild-tears-down-dropped-panes**: `rebuild(from:)` MUST call
  `paneWillBeRemoved()` on every previously-live leaf whose id does not appear
  among the new shape's leaf ids.
- **rebuild-detaches-before-rehosting**: `rebuild(from:)` MUST detach every
  current child (clearing `host`/`layoutParent`, and removing its split view
  item when the view is loaded) before constructing the new tree.
- **rebuild-single-leaf-becomes-root-child**: When the rebuilt shape is a
  single leaf, `rebuild(from:)` MUST host it as the split's sole child rather
  than wrapping it in a further nested split.
- **rebuild-carries-thickness-fractions**: Every child constructed or reused
  during `rebuild(from:)` MUST receive the thickness fraction recorded on its
  corresponding `LayoutNode`.
- **rebuild-persists-from-root**: `rebuild(from:)` MUST persist the tree from
  the root after rebuilding.
- **allowed-insertions-delegates-to-spec**: `allowedInsertions(beside:)` MUST
  return the result of asking the layout spec, given the root's current
  snapshot and view registry, and MUST return an empty array when the split
  has no root.
- **can-remove-leaf-delegates-to-spec**: `canRemoveLeaf(_:)` MUST return the
  result of asking the layout spec whether the given leaf may be removed from
  the root's current snapshot, and MUST return `false` when the split has no
  root.
- **root-split-walk-uses-is-root**: `rootSplit()` MUST walk up through
  `enclosingSplit` until it reaches the node whose `isRoot` is `true`, and
  MUST NOT stop merely because a node currently has no visible AppKit parent.
- **tear-down-panes-notifies-every-leaf**: `tearDownPanes()` MUST call
  `paneWillBeRemoved()` on every leaf in the subtree.
- **reassign-ambiguous-pane-numbers**: `reassignPaneIdentifiers()` MUST assign
  a 1-based index only to leaves whose `paneTypeIdentifier` occurs more than
  once among the tab's leaves (in depth-first order), and MUST clear the index
  (assign `nil`) on every leaf whose type is unique in the tab.
- **persist-tree-only-from-root**: `persistTreeToDocument()` MUST have no
  effect when `isRoot` is `false`.
- **persist-tree-sequence**: When `isRoot` is `true`, `persistTreeToDocument()`
  MUST, in this order: reassign pane identifiers, reapply pane state, refresh
  pane controls, invoke `onLayoutDidChange` with the current snapshot, and
  post `layoutDidChangeNotification` with itself as the notification's object.
- **snapshot-unwraps-single-child**: `snapshotNode()` MUST return the snapshot
  of its sole child directly, without an enclosing split node, when the split
  holds exactly one child.
- **snapshot-empty-tree-is-placeholder**: `snapshotNode()` MUST return a
  placeholder leaf node when the split holds zero children.
- **make-item-sizing**: `makeItem(for:)` MUST set the resulting split item's
  `minimumThickness` from the recursive minimum-thickness computation over the
  registered view descriptor(s) beneath that child, MUST set `canCollapse`
  from the pane's descriptor `isCollapsible` (`false` for a non-pane child),
  and MUST set `preferredThicknessFraction` from the descriptor when the
  descriptor declares one.
- **make-item-holding-priority**: `makeItem(for:)` MUST set the item's
  `holdingPriority` to the descriptor's `resolvedHoldingPriority` unless the
  split's `clampsToContainer` is `true`, in which case it MUST use the fixed,
  minimal priority (`rawValue: 1`).
- **clamped-tree-has-no-minimum**: When `clampsToContainer` is `true`, an
  item's `minimumThickness` MUST be `NSSplitViewItem.unspecifiedDimension`
  regardless of the descriptor's declared minimum.
- **restore-sizing-order**: `restoreSizing(of:)` MUST clear the item's
  `maximumThickness` before it lowers `minimumThickness` and resets
  `holdingPriority` back to their registered values.
- **build-from-persisted-leaf-wraps-in-root-split**: `make(from:project:workingDirectory:isRoot:)`
  MUST host a top-level leaf `LayoutNode` inside a newly created,
  non-persisted wrapper split (a fresh `nodeID`, `.horizontal` axis) so a tab
  always has a split at its root.
- **build-carries-fraction-to-child**: Constructing a child from a persisted
  `LayoutNode` MUST transfer that node's `thicknessFraction` onto the
  constructed or reused child.
- **close-checks-membership**: `paneDidRequestClose(_:)` MUST decline the
  request, announcing a refusal (`RefusalFeedback.announce()`), when the pane
  is not currently a direct child of the split that receives the request.
- **close-honors-spec-veto-with-fallback**: `paneDidRequestClose(_:)` MUST
  refuse (announcing a refusal) when the root's layout spec disallows removing
  the pane and either no `onLastPaneCloseRequest` handler is installed on the
  root or the tab holds more than that one pane; when a handler is installed
  and the pane is the tab's only pane, it MUST invoke that handler instead of
  removing the pane.
- **close-clears-zoom-before-removal**: `paneDidRequestClose(_:)` MUST clear
  the root's `zoomedLeaf` before removing a pane that is currently the zoomed
  leaf.
- **can-close-mirrors-close-refusal**: `canClose(_:)` MUST return `true`
  exactly when `paneDidRequestClose(_:)` would actually remove the pane or
  hand it to a last-pane-close handler (the spec allows removing it, or a
  handler exists and the tab holds exactly one pane).
- **minimize-refuses-unresolvable-edge**: `paneDidRequestMinimize(_:to:)` MUST
  have no effect when the requested edge cannot be resolved against the axis
  of the tree at that pane's position.
- **minimize-clears-zoom-first**: `paneDidRequestMinimize(_:to:)` MUST clear
  any existing zoom before minimizing a pane, and in that case MUST NOT
  re-capture thickness fractions (the fractions captured on the way into the
  zoom are preserved instead).
- **minimize-pins-split-item**: `paneDidRequestMinimize(_:to:)` MUST pin the
  owning split item to the pane's minimized thickness for the resolved edge by
  setting `minimumThickness == maximumThickness` and raising `holdingPriority`
  to `.defaultHigh`, without altering `preferredThicknessFraction`.
- **minimize-is-unconditional-on-model**: `paneDidRequestMinimize(_:to:)` MUST
  record the pane's minimized state even when the tab has never been
  displayed and no split view item yet exists to pin.
- **restore-unpins-and-clears**: `paneDidRequestRestore(_:)` MUST restore the
  owning split item's sizing (via `restoreSizing(of:)`) when an item exists,
  and MUST clear the pane's minimized state regardless of whether an item
  exists.
- **zoom-toggles-and-excludes-minimize**: `paneDidRequestZoom(_:)` MUST
  restore a minimized pane before zooming it, and MUST toggle the root's
  `zoomedLeaf` between the given pane and `nil`.
- **zoom-collapses-off-path-items**: `setZoomedLeaf(_:)`/`applyZoom(target:)`
  MUST collapse every split item that does not lie on the path from the root
  down to the zoomed leaf, and MUST un-collapse every item when the target is
  `nil`.
- **zoom-preserves-tree-shape**: Zooming MUST NOT reparent, remove, or resize
  (in thickness-fraction terms) any node in the tree; only each
  `NSSplitViewItem`'s `isCollapsed` flag changes.
- **persisted-state-applies-once**: `applyPersistedPaneState()` MUST run at
  most once per root controller instance, MUST apply minimize state before
  zoom state, and MUST have no effect when `isRoot` is `false`.
- **persisted-minimize-restores-if-edge-invalid**: When a leaf's persisted
  minimize edge cannot be resolved against the current tree,
  `applyPersistedPaneState()` MUST restore that pane instead of leaving it
  minimized with no way for the user to undo it.
- **reapply-pane-state-is-idempotent**: `reapplyPaneState()` MUST run on every
  rebuild (it holds no one-shot latch), and re-applying a collapsed or pinned
  state that is already correct MUST NOT trigger an additional resize
  notification.
