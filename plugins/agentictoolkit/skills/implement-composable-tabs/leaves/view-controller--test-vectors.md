<!-- leaf: implement-composable-tabs/view-controller--test-vectors · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-001 | binary-or-solo-children | Call the array-taking initializer with 3 children | The initializer traps (assertion failure) in a debug build |
| composable-tabs-002 | coder-initialization-unsupported | Attempt `ComposableTabsViewController(coder:)` | The call traps with a fatal error; no instance is returned |
| composable-tabs-003 | vertical-split-set-from-axis | Construct with `axis: .horizontal`, then load the view | `splitView.isVertical == true` |
| composable-tabs-004 | thin-divider-style | Load the view | `splitView.dividerStyle == .thin` |
| composable-tabs-005 | custom-split-view-type | Inspect `splitView` after `loadView` | `splitView` is a `PaneSplitView` instance |
| composable-tabs-006 | gutter-spacing-observers | View is loaded with a spy `PaneSplitView` subclass overriding `spacingDidChange()`; `UserSettings.paneSpacingBetweenColumns` value is changed | The spy records exactly one `spacingDidChange()` invocation, and `splitView.needsDisplay == true` immediately afterward |
| composable-tabs-007 | add-split-item-per-child | Construct with 2 children, then call `viewDidLoad()` | `splitViewItems.count == 2`, in the same order as `layoutChildren` |
| composable-tabs-008 | reassign-identifiers-on-root-load | Construct a root controller with two panes of the same `paneTypeIdentifier`, load the view | Both panes receive non-nil, sequential indices from `reassignPaneIdentifiers()` |
| composable-tabs-009 | schedule-persist-on-resize | Preferred thicknesses already applied once; split view posts a resize notification | `scheduleThicknessPersist()` runs on the root; a subsequent call to `flushPendingThicknessPersist()` now performs a write (a persist is pending) |
| composable-tabs-010 | apply-preferred-thickness-on-layout | `viewDidLayout()` is called with a real (non-placeholder) split-view width | Divider positions are set from each child's `thicknessFraction` |
| composable-tabs-011 | preferred-thickness-one-shot | Thicknesses already applied for the current arrangement; a further `viewDidLayout()` fires | No divider position is changed by the second call |
| composable-tabs-012 | skip-zero-thickness-pass | Split view's bounds width is `0`; `viewDidLayout()` fires | No divider position is set; when `viewDidLayout()` later fires with a real width, thicknesses are still applied then (the skip did not consume the one-shot) |
| composable-tabs-013 | dragged-fraction-outranks-descriptor | Child's own `thicknessFraction == 0.7`; its split item's `preferredThicknessFraction == 0.3` | The divider is placed using `0.7`, not `0.3` |
| composable-tabs-014 | clamp-thickness-to-minimum | Fraction implies a thickness below the item's `minimumThickness` | The divider is placed at `minimumThickness`, not the smaller fraction-derived value |
| composable-tabs-015 | widen-divider-grab-area | Gutter is set to `0`pt (vertical split); AppKit asks for `effectiveRect(forDrawnRect:ofDividerAt:)` | The returned rect is inset to at least `PaneSpacing.minimumDividerGrab` (6pt) wide while the drawn rect stays at 0pt |
| composable-tabs-016 | stamp-ownership-on-children | Assign `layoutChildren = [pane, nestedSplit]` | `pane.host === self` and `nestedSplit.layoutParent === self` |
| composable-tabs-017 | inherit-arranger-to-nested-splits | Set `arranger` to `ProportionalArranger()` with a nested split among `layoutChildren` | The nested split's `arranger` is the same `ProportionalArranger` instance |
| composable-tabs-018 | inherit-layout-override | Set `layoutOverride` to a non-nil `ComposableTabsLayout` | Every pane and nested split in `layoutChildren` reports the same `layoutOverride` |
| composable-tabs-019 | inherit-state-owner-node-id | Set `stateOwnerNodeID` to a UUID | Every pane and nested split in `layoutChildren` reports the same `stateOwnerNodeID` |
| composable-tabs-020 | inherit-clamps-to-container | Set `clampsToContainer = true` | Every pane and nested split in `layoutChildren` reports `clampsToContainer == true` |
| composable-tabs-021 | default-arranger-is-inherited-slot | Read `arranger` on a freshly constructed controller | It is an `InheritedSlotArranger`, and `arrange(node:along:)` returns `node` unchanged |
| composable-tabs-022 | apply-arrangement-no-op-for-default-arranger | `arranger` is the default; call `applyArrangement()` | No `thicknessFraction` on any child changes and no layout pass is forced |
| composable-tabs-023 | apply-arrangement-resolves-actual-axis | Root holds one child that is itself a `.vertical` split; call `applyArrangement()` with a non-default arranger | The arranger is invoked with axis `.vertical`, not the root's own axis |
| composable-tabs-024 | apply-arrangement-matches-by-id | Arranger's result omits one child's id | That child's existing `thicknessFraction` is left unchanged after `applyFractions(from:)` |
| composable-tabs-025 | capture-thicknesses-on-mutation | User has dragged a divider; `split(_:adding:direction:)` is called | The pre-split live thickness is captured into the affected child's `thicknessFraction` before the tree changes |
| composable-tabs-026 | capture-skips-zoomed-tree | Root's `zoomedLeaf` is non-nil; `captureThicknessFractions()` is called | No child's `thicknessFraction` anywhere in the tree is modified |
| composable-tabs-027 | capture-skips-rail-split | One split's visible item has `maximumThickness != unspecifiedDimension`; `captureThicknessFractions()` is called on it | No item in that split has its `thicknessFraction` written |
| composable-tabs-028 | capture-only-uncollapsed-items | One item in a split is collapsed; `captureThicknessFractions()` is called | The collapsed item's child does not have its `thicknessFraction` overwritten |
| composable-tabs-029 | capture-recurses-into-children | A rail split contains a nested split with its own children | `captureThicknessFractions()` still descends into and updates the nested split's own children |
| composable-tabs-030 | apply-sizes-matches-existing-shape | Live tree has 1 child; template `LayoutNode` is a 2-child split | `applySizes(from:)` leaves the live tree's single child untouched |
| composable-tabs-031 | apply-sizes-forces-relayout | `applySizes(from:)` is called on a loaded view | The one-shot thickness guard is reset and dividers move to the new fractions before the next natural layout pass |
| composable-tabs-032 | debounce-thickness-persist | Two resize notifications arrive 100ms apart | Only one `onLayoutDidChange` call happens, timed 300ms after the second notification |
| composable-tabs-033 | dedupe-unchanged-persist | A pending persist's rounded thickness signature matches the signature already delivered to `onLayoutDidChange` | `onLayoutDidChange` is not invoked |
| composable-tabs-034 | flush-pending-persist-on-demand | No persist is currently pending; `flushPendingThicknessPersist()` is called | `onLayoutDidChange` is not invoked and no error occurs |
| composable-tabs-035 | persist-only-from-root | Call `scheduleThicknessPersist()` on a non-root split | No persist is armed and no write ever occurs from that instance; a subsequent `flushPendingThicknessPersist()` on it still does nothing |
| composable-tabs-036 | split-creates-sibling-pane | Call `split(pane, adding: viewID, direction: .right)` | A new pane showing `viewID` is added as the second child of a new inner split, `pane` as the first |
| composable-tabs-037 | split-wraps-in-inner-split | Same call as above | `layoutChildren[index]` is replaced by a new `ComposableTabsViewController` with `axis == .horizontal` (from `Direction.right.axis`) |
| composable-tabs-038 | split-inherits-slot-size | `pane.thicknessFraction == 0.4` before the split | The new inner split's `thicknessFraction == 0.4`; `pane.thicknessFraction` is `nil` afterward |
| composable-tabs-039 | split-propagates-configuration | Enclosing split has a custom `arranger`, `layoutOverride`, `stateOwnerNodeID`, `clampsToContainer == true` | The new inner split reports all four of the same values |
| composable-tabs-040 | split-persists-and-rearranges | `split(_:adding:direction:)` completes | `applyArrangement()` runs and `onLayoutDidChange` fires from the root |
| composable-tabs-041 | remove-refuses-non-direct-child | Call `remove(paneNotInThisSplit)` | `layoutChildren` is unchanged and no split view item is removed |
| composable-tabs-042 | remove-honors-spec-veto | Layout spec's `canRemove` returns `false` for the given leaf | `remove(_:)` returns with `layoutChildren` unchanged |
| composable-tabs-043 | remove-tears-down-pane-content | `remove(pane)` succeeds | `pane.host == nil` and `pane.paneWillBeRemoved()` has been called exactly once |
| composable-tabs-044 | remove-clears-sibling-fractions | Split has 2 children, each with a non-nil fraction; one is removed | The remaining child's `thicknessFraction` is `nil` after removal |
| composable-tabs-045 | remove-collapses-degenerate-split | Non-root split with 2 children; one is removed | The split itself is replaced in its parent by the surviving child, at the collapsing split's former `thicknessFraction` |
| composable-tabs-046 | remove-rehomes-focus | Removed pane's view was first responder | After removal, the root's first leaf (depth-first) becomes first responder |
| composable-tabs-047 | remove-persists-and-rearranges | `remove(_:)` completes | `applyArrangement()` runs and `onLayoutDidChange` fires from the root |
| composable-tabs-048 | move-refused-by-spec | Spec disallows the moved tree | `move(leaf, .left)` returns `false`; `layoutChildren` is unchanged |
