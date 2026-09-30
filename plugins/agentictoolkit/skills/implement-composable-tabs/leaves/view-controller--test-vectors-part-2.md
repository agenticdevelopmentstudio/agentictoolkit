<!-- leaf: implement-composable-tabs/view-controller--test-vectors-part-2 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-049 | available-directions-filtered-by-spec | `ComposableTabsMove.availableDirections` reports `.left, .right`; spec disallows `.left`'s resulting tree | `availableMoveDirections(for: leaf) == [.right]` |
| composable-tabs-050 | rebuild-reuses-live-panes | New shape's leaf id matches a currently-live pane's `nodeID` | `rebuild(from:)` reuses the exact same `ComposableTabsPaneViewController` instance for that id |
| composable-tabs-051 | rebuild-tears-down-dropped-panes | New shape omits a leaf id that was live before | That leaf's `paneWillBeRemoved()` is called exactly once |
| composable-tabs-052 | rebuild-detaches-before-rehosting | `rebuild(from:)` is called on a loaded view | Every prior split view item is removed and every prior child's `host`/`layoutParent` is `nil` before any new item is added |
| composable-tabs-053 | rebuild-single-leaf-becomes-root-child | New shape is a single `.leaf` node | The root's `layoutChildren` has exactly 1 entry: that leaf's pane, with no extra nested split |
| composable-tabs-054 | rebuild-carries-thickness-fractions | Template `LayoutNode` for a child has `thicknessFraction == 0.25` | The constructed/reused child's `thicknessFraction == 0.25` |
| composable-tabs-055 | rebuild-persists-from-root | `rebuild(from:)` completes | `onLayoutDidChange` fires from the root with the new snapshot |
| composable-tabs-056 | allowed-insertions-delegates-to-spec | Split has a root; `allowedInsertions(beside: leaf)` is called | Returns exactly what `layout.spec.allowedInsertions(at:in:registry:)` returns for the root's snapshot |
| composable-tabs-057 | can-remove-leaf-delegates-to-spec | Split has no root (`rootSplit() == nil`) | `canRemoveLeaf(_:)` returns `false` |
| composable-tabs-058 | root-split-walk-uses-is-root | A non-root split's view has never loaded (no AppKit `parent`) but its `layoutParent` chain reaches an `isRoot == true` node | `rootSplit()` returns that root, not `nil` |
| composable-tabs-059 | tear-down-panes-notifies-every-leaf | Subtree has 3 leaves; `tearDownPanes()` is called | All 3 leaves' `paneWillBeRemoved()` are called exactly once each |
| composable-tabs-060 | reassign-ambiguous-pane-numbers | Tab has 2 terminals and 1 file browser | Both terminals get non-nil, sequential indices; the file browser's index is `nil` |
| composable-tabs-061 | persist-tree-only-from-root | `persistTreeToDocument()` is called on a non-root split | No pane identifiers are reassigned and `onLayoutDidChange` is not invoked |
| composable-tabs-062 | persist-tree-sequence | Root's `persistTreeToDocument()` is called | `reassignPaneIdentifiers()`, `reapplyPaneState()`, `refreshPaneControls()`, `onLayoutDidChange`, then the notification post all occur, in that order |
| composable-tabs-063 | snapshot-unwraps-single-child | Split has exactly 1 child | `snapshotNode()` returns that child's own snapshot, not a wrapping `.split` node |
| composable-tabs-064 | snapshot-empty-tree-is-placeholder | Split has 0 children | `snapshotNode()` returns `LayoutNode.leaf(contentType: .placeholder)` |
| composable-tabs-065 | make-item-sizing | Pane's descriptor has `minimumThickness: 200`, `isCollapsible: true`, `preferredThicknessFraction: 0.3` | The built item has `minimumThickness == 200`, `canCollapse == true`, `preferredThicknessFraction == 0.3` |
| composable-tabs-066 | make-item-holding-priority | `clampsToContainer == true` | The built item's `holdingPriority.rawValue == 1` regardless of the descriptor |
| composable-tabs-067 | clamped-tree-has-no-minimum | `clampsToContainer == true`; descriptor declares `minimumThickness: 300` | The built item's `minimumThickness == NSSplitViewItem.unspecifiedDimension` |
| composable-tabs-068 | restore-sizing-order | Item is currently pinned (rail); `restoreSizing(of:)` is called | `maximumThickness` is cleared before `minimumThickness`/`holdingPriority` are reset (no transient invalid constraint pair is ever observed) |
| composable-tabs-069 | build-from-persisted-leaf-wraps-in-root-split | `make(from: .leaf(...), project:, workingDirectory:, isRoot: true)` | Returned controller's `layoutChildren.count == 1`; its own `axis == .horizontal` and `nodeID` is freshly minted, not the leaf's id |
| composable-tabs-070 | build-carries-fraction-to-child | Persisted leaf node has `thicknessFraction == 0.6` | The constructed pane's `thicknessFraction == 0.6` |
| composable-tabs-071 | close-checks-membership | `pane` is not in `layoutChildren` of the split receiving the request | `RefusalFeedback.announce()` fires; `remove(_:)` is never called |
| composable-tabs-072 | close-honors-spec-veto-with-fallback | Spec vetoes removal; `onLastPaneCloseRequest` is `nil` | Refusal is announced; the pane is not removed |
| composable-tabs-073 | close-honors-spec-veto-with-fallback | Spec vetoes removal; `onLastPaneCloseRequest` is set; tab holds exactly 1 pane | The handler is invoked with the pane; `remove(_:)` is not called |
| composable-tabs-074 | close-clears-zoom-before-removal | `pane` is the root's `zoomedLeaf`; close is requested and permitted | `zoomedLeaf` is `nil` by the time `remove(_:)` runs |
| composable-tabs-075 | can-close-mirrors-close-refusal | Spec allows removing the pane | `canClose(pane) == true` |
| composable-tabs-076 | minimize-refuses-unresolvable-edge | The requested edge cannot be resolved against the axis of the tree at the pane's position (for example, a leading/trailing edge requested where the enclosing split is `.vertical`-axis) | No item is pinned and `leaf.setMinimized(to:)` is not called |
| composable-tabs-077 | minimize-clears-zoom-first | Root is zoomed; a pane is minimized | `zoomedLeaf` becomes `nil`; `captureThicknessFractions()` is not invoked for this minimize |
| composable-tabs-078 | minimize-pins-split-item | Minimize succeeds and an item exists | `item.minimumThickness == item.maximumThickness == leaf.minimizedThickness(for: resolved)`; `holdingPriority == .defaultHigh`; `preferredThicknessFraction` unchanged |
| composable-tabs-079 | minimize-is-unconditional-on-model | Tab has never been displayed (no split view item exists) | `leaf.setMinimized(to: edge)` is still called |
| composable-tabs-080 | restore-unpins-and-clears | An item exists for a minimized pane; restore is requested | `restoreSizing(of: item)` runs and `leaf.setMinimized(to: nil)` is called |
| composable-tabs-081 | zoom-toggles-and-excludes-minimize | A minimized pane is zoomed | The pane is restored first, then `zoomedLeaf` is set to that pane |
| composable-tabs-082 | zoom-collapses-off-path-items | Deep tree; a leaf 3 levels down is zoomed | Every split item not on the root-to-leaf path has `isCollapsed == true`; items on the path do not |
| composable-tabs-083 | zoom-preserves-tree-shape | A pane is zoomed then unzoomed | `snapshotNode()` before and after report identical structure and thickness fractions |
| composable-tabs-084 | persisted-state-applies-once | `applyPersistedPaneState()` is called twice on the same root instance | The second call has no additional effect: no leaf's minimize or zoom state changes as a result of the second call |
| composable-tabs-085 | persisted-minimize-restores-if-edge-invalid | A leaf's persisted edge no longer resolves against the current tree | The leaf is restored (`paneDidRequestRestore`) instead of minimized |
| composable-tabs-086 | reapply-pane-state-is-idempotent | `reapplyPaneState()` is called twice in a row with no tree change between calls | No additional resize notification or persist is triggered by the second call |
| composable-tabs-087 | reapply-drops-stale-zoom | `zoomedLeaf` points to a pane no longer among `allLeaves()` | `zoomedLeaf` becomes `nil` and every item is un-collapsed |
| composable-tabs-088 | reapply-reresolves-minimize-edge | A rebuild changed the axis under a minimized pane so its stored edge no longer applies, but a different edge does | `leaf.setMinimized(to: newEdge)` is called with the re-resolved edge, not the stale one |
| composable-tabs-089 | refresh-pane-controls-notifies-every-leaf | Tab has 3 leaves; `refreshPaneControls()` is called | Each of the 3 leaves' `refreshControlAvailability()` is called exactly once |
| composable-tabs-090 | split-no-ops-without-project | `project` has already been deallocated; `split(pane, adding: viewID, direction: .right)` is called | `layoutChildren` is unchanged and no split view item is added |
| composable-tabs-091 | move-permitted-without-spec | Resolved project has no layout spec configured at all | `move(leaf, .left)` returns `true` and rebuilds the root from the moved tree |
| composable-tabs-092 | move-rebuilds-root | Spec permits the moved tree | `move(_:_:)` returns `true` and the root's `layoutChildren` match the moved tree's shape |
| composable-tabs-093 | can-close-mirrors-close-refusal | Spec disallows removing the pane and no `onLastPaneCloseRequest` handler is installed | `canClose(pane) == false` |
| composable-tabs-094 | flush-pending-persist-on-demand | A resize notification has armed a pending debounced persist; `flushPendingThicknessPersist()` is called before the debounce timer fires | The write happens immediately and no later timer-driven write follows |
| composable-tabs-095 | vertical-split-set-from-axis | Construct with `axis: .vertical`, then load the view | `splitView.isVertical == false` |
