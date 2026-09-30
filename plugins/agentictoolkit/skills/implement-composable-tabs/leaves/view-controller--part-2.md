<!-- leaf: implement-composable-tabs/view-controller--part-2 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — continued (part 2)

**Rules** (cite as `implement-composable-tabs/view-controller--part-2#<slug>`):

- `binary-or-solo-children` MUST
- `coder-initialization-unsupported` MUST
- `vertical-split-set-from-axis` MUST
- `thin-divider-style` MUST
- `custom-split-view-type` MUST
- `gutter-spacing-observers` MUST
- `add-split-item-per-child` MUST
- `reassign-identifiers-on-root-load` MUST
- `schedule-persist-on-resize` MUST
- `apply-preferred-thickness-on-layout` MUST
- `preferred-thickness-one-shot` MUST
- `skip-zero-thickness-pass` MUST
- `dragged-fraction-outranks-descriptor` MUST
- `clamp-thickness-to-minimum` MUST
- `widen-divider-grab-area` MUST
- `stamp-ownership-on-children` MUST
- `inherit-arranger-to-nested-splits` MUST
- `inherit-layout-override` MUST
- `inherit-state-owner-node-id` MUST
- `inherit-clamps-to-container` MUST
- `default-arranger-is-inherited-slot` MUST
- `apply-arrangement-no-op-for-default-arranger` MUST
- `apply-arrangement-resolves-actual-axis` MUST
- `apply-arrangement-matches-by-id` MUST
- `capture-thicknesses-on-mutation` MUST
- `capture-skips-zoomed-tree` MUST
- `capture-skips-rail-split` MUST
- `capture-only-uncollapsed-items` MUST
- `capture-recurses-into-children` MUST
- `apply-sizes-matches-existing-shape` MUST
- `apply-sizes-forces-relayout` MUST
- `debounce-thickness-persist` MUST
- `dedupe-unchanged-persist` MUST
- `flush-pending-persist-on-demand` MUST
- `persist-only-from-root` MUST
- `split-creates-sibling-pane` MUST
- `split-wraps-in-inner-split` MUST
- `split-inherits-slot-size` MUST
- `split-propagates-configuration` MUST
- `split-persists-and-rearranges` MUST
- `split-no-ops-without-project` MUST
- `remove-refuses-non-direct-child` MUST
- `remove-honors-spec-veto` MUST
- `remove-tears-down-pane-content` MUST
- `remove-clears-sibling-fractions` MUST

- **binary-or-solo-children**: The array-taking initializer MUST trap (via
  `assert`) when given more than two children; a split MUST be nested rather
  than given a third child directly.
- **coder-initialization-unsupported**: Component MUST NOT support
  initialization via `init(coder:)` and MUST fail fast (fatal error) if it is
  invoked.
- **vertical-split-set-from-axis**: Component MUST set `splitView.isVertical`
  to `true` when `axis == .horizontal` and to `false` when `axis == .vertical`,
  both in `viewDidLoad()` and after every `rebuild(from:)`.
- **thin-divider-style**: Component MUST set the split view's `dividerStyle`
  to `.thin` in `viewDidLoad()`.
- **custom-split-view-type**: Component MUST use `PaneSplitView` (a
  `ThemedSplitView` subclass) as its split view, via `makeSplitView()`.
- **gutter-spacing-observers**: Component MUST observe every setting in
  `PaneSpacing.gutterSettings` (the between-columns and between-rows gutters)
  from `viewDidLoad()` onward, and MUST call `spacingDidChange()` on the split
  view whenever any of them changes.
- **add-split-item-per-child**: Component MUST add exactly one
  `NSSplitViewItem` for each entry in `layoutChildren`, in order, during
  `viewDidLoad()`.
- **reassign-identifiers-on-root-load**: Component MUST call
  `reassignPaneIdentifiers()` from `viewDidLoad()` only when `isRoot` is
  `true`.
- **schedule-persist-on-resize**: Component MUST schedule a debounced
  thickness persist (`scheduleThicknessPersist()`, on the root) whenever the
  split view reports `splitViewDidResizeSubviews(_:)`, but only once preferred
  thicknesses have already been applied at least once for the current
  arrangement.
- **apply-preferred-thickness-on-layout**: Component MUST attempt to apply
  preferred/persisted thickness fractions to the split's dividers on every
  `viewDidLayout()` call, until that application succeeds once for the
  current arrangement.
- **preferred-thickness-one-shot**: Component MUST NOT reapply preferred
  thickness fractions on a later layout pass once they have been applied for
  the current arrangement, and MUST reset that one-shot guard whenever the
  arrangement changes (a split, a removal, a rebuild, or `applySizes(from:)`).
- **skip-zero-thickness-pass**: Component MUST NOT apply preferred thicknesses
  when the split view's total extent along its axis is `1` or less, or when
  the number of installed split items does not yet equal the number of
  `layoutChildren`.
- **dragged-fraction-outranks-descriptor**: When applying preferred
  thicknesses, Component MUST prefer a child's own `thicknessFraction` (what
  the user dragged, or what was restored from storage) over the split item's
  `preferredThicknessFraction`, and MUST fall back to the item's
  `preferredThicknessFraction` only when the child has no stored fraction.
- **clamp-thickness-to-minimum**: When a fraction is being applied for a
  divider, Component MUST clamp the resulting thickness to at least that
  item's `minimumThickness`.
- **widen-divider-grab-area**: Component MUST widen a divider's effective
  (draggable) hit-test rectangle, on the axis it is drawn thinner than
  `PaneSpacing.minimumDividerGrab` (6pt), to at least that width, without
  changing the rectangle actually drawn.
- **stamp-ownership-on-children**: Component MUST set itself as `host` on
  every `ComposableTabsPaneViewController` in `layoutChildren` and as
  `layoutParent` on every nested `ComposableTabsViewController` in
  `layoutChildren`, both at initialization and whenever `layoutChildren` is
  reassigned.
- **inherit-arranger-to-nested-splits**: When stamping ownership, Component
  MUST propagate its own `arranger` to every nested split child.
- **inherit-layout-override**: When stamping ownership, Component MUST
  propagate its own `layoutOverride` to every pane and nested split child.
- **inherit-state-owner-node-id**: When stamping ownership, Component MUST
  propagate its own `stateOwnerNodeID` to every pane and nested split child.
- **inherit-clamps-to-container**: When stamping ownership, Component MUST
  propagate its own `clampsToContainer` to every pane and nested split child.
- **default-arranger-is-inherited-slot**: Component MUST default `arranger` to
  `InheritedSlotArranger`, which returns its input tree with thickness
  fractions unchanged.
- **apply-arrangement-no-op-for-default-arranger**: `applyArrangement()` MUST
  have no observable effect when the installed `arranger` is
  `InheritedSlotArranger` (see **default-arranger-is-inherited-slot** for why:
  that arranger returns its input unchanged).
- **apply-arrangement-resolves-actual-axis**: When applying a non-default
  arranger, Component MUST hand the arranger the axis of its own snapshot's
  split orientation when that snapshot is itself a split node, rather than
  always using `self.axis`.
- **apply-arrangement-matches-by-id**: Component MUST match the fractions an
  arranger returns back onto the live children by comparing `nodeID`, and MUST
  leave any live child the arranger's result did not describe with its
  existing fraction unchanged.
- **capture-thicknesses-on-mutation**: Component MUST capture the live
  divider thicknesses of the whole tab into each child's `thicknessFraction`
  (`captureThicknessFractions()`, from the root) immediately before a
  `split(_:adding:direction:)` or `remove(_:)` mutation changes the tree.
- **capture-skips-zoomed-tree**: Component MUST NOT capture thickness
  fractions anywhere in the tab's tree while the root's `zoomedLeaf` is
  non-`nil`.
- **capture-skips-rail-split**: Component MUST NOT capture thickness
  fractions for a split any of whose visible items is pinned to a fixed rail
  thickness (`maximumThickness != NSSplitViewItem.unspecifiedDimension`).
- **capture-only-uncollapsed-items**: When capturing thicknesses, Component
  MUST record a fraction only for items that are not currently collapsed.
- **capture-recurses-into-children**: `captureThicknessFractions()` MUST
  recurse into every nested split child regardless of whether the split
  itself just captured a fraction.
- **apply-sizes-matches-existing-shape**: `applySizes(from:)` MUST copy
  thickness fractions from a template `LayoutNode` onto the live tree only at
  levels where the live child count (`1` or `2`) matches the template's shape,
  and MUST leave a mismatched subtree untouched rather than partially
  applying sizes to it.
- **apply-sizes-forces-relayout**: After adopting new sizes, `applySizes(from:)`
  MUST reset the one-shot thickness-application guard and MUST immediately
  reapply thicknesses for any subtree whose view is already loaded.
- **debounce-thickness-persist**: Component MUST debounce a divider-driven
  persist by 300ms (`thicknessPersistDelay`) after each reported resize,
  canceling any still-pending write each time a new resize notification
  arrives.
- **dedupe-unchanged-persist**: Component MUST NOT invoke `onLayoutDidChange`
  when the rounded thickness signature of the current snapshot is unchanged
  from the last one persisted.
- **flush-pending-persist-on-demand**: Component MUST provide
  `flushPendingThicknessPersist()`, which MUST write a still-pending debounced
  persist immediately and MUST do nothing when no persist is currently
  pending.
- **persist-only-from-root**: Component MUST schedule, flush, and perform a
  thickness persist only when `isRoot` is `true`; a non-root split MUST NOT
  independently start or flush a persist timer.
- **split-creates-sibling-pane**: `split(_:adding:direction:)` MUST create a
  new pane showing the given view ID as a sibling of the pane being split, and
  MUST place the new sibling first or second in the resulting inner split
  according to `Direction.placesNewPaneFirst`.
- **split-wraps-in-inner-split**: `split(_:adding:direction:)` MUST replace
  the split pane's slot with a new nested `ComposableTabsViewController`
  holding exactly the original pane and the new sibling, laid out along
  `Direction.axis`.
- **split-inherits-slot-size**: The new inner split created by
  `split(_:adding:direction:)` MUST inherit the thickness fraction the
  original pane held in its slot, and the original pane's own fraction MUST
  be cleared, so the two panes start out sharing the inner split evenly.
- **split-propagates-configuration**: The inner split created by
  `split(_:adding:direction:)` MUST end up with the enclosing split's
  `arranger`, `layoutOverride`, `stateOwnerNodeID`, and `clampsToContainer`, per
  **inherit-arranger-to-nested-splits**, **inherit-layout-override**,
  **inherit-state-owner-node-id**, and **inherit-clamps-to-container**.
- **split-persists-and-rearranges**: After a `split(_:adding:direction:)` call
  completes, Component MUST call `applyArrangement()` and persist the tree,
  both from the root.
- **split-no-ops-without-project**: `split(_:adding:direction:)` MUST return
  immediately, performing no mutation, when its project has already been
  deallocated.
- **remove-refuses-non-direct-child**: `remove(_:)` MUST have no effect when
  the given pane is not a direct child of the split it is called on.
- **remove-honors-spec-veto**: `remove(_:)` MUST have no effect when the
  root's `canRemoveLeaf(_:)` refuses to remove the given leaf.
- **remove-tears-down-pane-content**: `remove(_:)` MUST clear the removed
  pane's `host` and MUST call `paneWillBeRemoved()` on it after detaching it
  from the split view.
- **remove-clears-sibling-fractions**: After a removal, Component MUST clear
  the thickness fraction of every remaining child in that split, since those
  fractions described a split that no longer exists.
