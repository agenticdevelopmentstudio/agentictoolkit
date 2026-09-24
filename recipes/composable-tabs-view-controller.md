---
id: 0640ca96-95c5-4234-925e-386425cc4435
title: ComposableTabsViewController
domain: agentictoolkit://recipes/composable-tabs-view-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Recursive AppKit split-view controller that composes a tab's panes into a
  binary tree, with persisted sizing, spec-gated split/remove/move, and pane zoom/minimize.
platforms:
- swift
- macos
tags:
- composable-tabs
- split-view
- layout
- tabs
- appkit
depends-on: []
related:
- agentictoolkit://recipes/composable-tabs-pane-view-controller
- agentictoolkit://recipes/pane-spacing
references: []
approved-by: ''
approved-date: ''
---

# ComposableTabsViewController

## Overview

`ComposableTabsViewController` is a `@MainActor`, `final` `NSSplitViewController`
subclass (of `ThemedSplitViewController`) that is the recursive building block
of a project tab's pane layout. Each instance is either the tab's root or one
node of a binary tree nested beneath it: it holds at most two children —
`ComposableTabsPaneViewController` leaves, or further nested
`ComposableTabsViewController` splits — laid out along a `ComposableTabsAxis`
(`.horizontal` or `.vertical`). The tree's shape and each node's share of its
split (`thicknessFraction`) are captured to and rebuilt from a value-type
`LayoutNode`, so a project's stored layout can be persisted, restored, and
mirrored across tabs. On top of the tree itself, the type also conforms to
`PaneHost` (in `ComposableTabsPaneHost.swift`, the other half of this same
class): it is the object a pane calls to close, minimize/restore, or zoom
itself, and the one that resolves those requests against the layout spec and
the live `NSSplitViewItem`s.

## Behavioral Requirements

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
- **reapply-drops-stale-zoom**: `reapplyPaneState()` MUST clear the root's
  `zoomedLeaf` and un-collapse the tree when the zoomed leaf is no longer
  present among the tab's leaves.
- **reapply-reresolves-minimize-edge**: `reapplyPaneState()` MUST re-resolve
  each minimized leaf's edge against the current tree rather than trust the
  edge it was last minimized to, and MUST restore the pane instead when no
  edge remains valid.
- **refresh-pane-controls-notifies-every-leaf**: `refreshPaneControls()` MUST
  re-ask every leaf in the tab to refresh its own control availability.
- **may-supply-custom-arranger**: Component MAY be configured with a custom
  `PaneArranger` (for example `ProportionalArranger`) in place of the default
  `InheritedSlotArranger`, to redistribute thickness fractions along the
  arrangement axis differently than "leave what a split/remove already
  assigned."

## Appearance

- **Corner radius**: Not applicable — the split view and its items draw no
  custom layer or corner radius anywhere in source.
- **Padding**: Not set by this type directly. `PaneSpacing.contentInsets`
  (four independently configurable edge settings, each `0` by default) is the
  app-wide inset applied around the pane area by the window/container that
  hosts a root `ComposableTabsViewController`; this file itself sets no
  content insets on its own view.
- **Font**: Not applicable — this component draws no text of its own; any
  text belongs to the panes it hosts.
- **Background**: `PaneSplitView.drawDivider(in:)` fills a divider wider than
  1pt with `currentPalette.projectPaneBackdrop`, so a wide gutter reads as the
  same backdrop plane the frame spacing shows, not a colored bar; a divider at
  or under 1pt falls back to `ThemedSplitView`'s own (unspecified in this
  source) default drawing.
- **Foreground/Text**: Not applicable — no text is drawn by this type.
- **Border**: Not applicable — no border is configured on the split view or
  its items anywhere in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A pane's `minimumThickness` comes from its registered
  `ComposableTabsViewDescriptor.minimumThickness` (`120pt` by default per
  `ComposableTabsViewDescriptor.init`); a nested split's minimum is the sum of
  its children's minimums along the split's own axis, or the max of them
  across it. A divider's thickness is `PaneSpacing.current.betweenColumns`
  (vertical split) or `.betweenRows` (horizontal split) — both `1pt` by
  default — and its draggable hit area is widened to at least
  `PaneSpacing.minimumDividerGrab` (`6pt`) without changing the drawn gutter
  width. A minimized pane is pinned to a fixed thickness (its
  `minimumThickness == maximumThickness`) computed by the pane itself
  (`minimizedThickness(for:)`, outside this file's source).

## States

| State | Appearance change |
|-------|------------------|
| Default (arranged) | Panes/nested splits occupy the fractions of the split's extent recorded in `thicknessFraction`, or share evenly when none is set; dividers are drawn at the gutter thickness for the split's axis. |
| Dragging a divider | The user's drag moves the divider live via AppKit; once released, `splitViewDidResizeSubviews(_:)` schedules a 300ms-debounced write of the new fractions rather than persisting on every intermediate frame. |
| Minimized (rail) | The pane's owning split item is pinned to a fixed thickness (`minimumThickness == maximumThickness`) with `holdingPriority = .defaultHigh`; the item cannot be dragged narrower or wider, and a window resize is taken out of its neighbours instead. |
| Zoomed | Every split item off the path from the root to the zoomed leaf has `isCollapsed = true`; the zoomed leaf's ancestors on that path stay visible and sized as before. Only one leaf per tab may be zoomed at a time (`zoomedLeaf`, root-only). |
| Collapsed by spec | Not applicable in this file: `NSSplitViewItem.canCollapse` is set from the pane's descriptor `isCollapsible`, but nothing in this source ever collapses an item on that basis outside of the zoom path above — user-driven collapse-by-drag is AppKit's own default `NSSplitViewController` behavior for a `canCollapse` item. |
| Pressed | Not applicable: neither the split view nor its dividers expose a pressed/highlighted visual state in this source. |
| Disabled | Not applicable: no split item, divider, or child is ever disabled in this source. |
| Focused | Not applicable to the split itself: first responder moves among the *panes* it hosts (see `remove-rehomes-focus`); the split view controller has no focus appearance of its own. |
| Loading | Not applicable: every mutation (`split`, `remove`, `rebuild`, `move`) is synchronous; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set in source. `NSSplitViewController` and
  its `NSSplitView` expose AppKit's own default split-view accessibility role
  and divider semantics; this file overrides no accessibility API.
- **Label requirements**: Not applicable at this level — no accessibility
  label or identifier is assigned to the split view, a divider, or an item in
  this source; a pane's own accessible content is that pane's own concern
  (each pane is a separately hosted child view controller with its own view).
- **Announce state changes**: NEEDS REVIEW: Not implemented in source.
  Behavior undefined. A zoom, a minimize/restore, a split, a remove, or a move
  all change which panes are visible and how much space each has, but nothing
  in this source posts an `NSAccessibility.post(element:notification:)` call
  (or any other accessibility notification) when any of these happen; the
  refusal path even for a genuinely-blocked action is a plain audible beep
  (`RefusalFeedback.announce()`), not a VoiceOver-readable message. What is
  missing: whether a VoiceOver user is told a pane appeared, disappeared, or
  changed size, or hears nothing until navigating back into the split. What
  would settle it: a VoiceOver pass over a live project window while
  splitting, closing, zooming, and minimizing panes, or an explicit decision
  to post layout-changed/element-created/destroyed notifications from
  `persistTreeToDocument()` and the zoom/minimize paths.
- **Minimum tap target / non-pointer resize**: NEEDS REVIEW: Not implemented
  in source. Behavior undefined. A divider's thickness is resized only by a
  mouse drag (`NSSplitView`'s own dragging plus the widened hit-test rect from
  `widen-divider-grab-area`); no method in this source lets a keyboard-only or
  switch-control user change a `thicknessFraction` without a pointer. What is
  missing: whether AppKit's default `NSSplitView` keyboard-accessibility
  behavior (if any) is considered sufficient here, or whether a keyboard
  resize command should be added. What would settle it: a keyboard-only /
  VoiceOver pass attempting to resize a pane, or an explicit design decision
  that divider resize is mouse-only and out of scope for this component. The
  44×44pt (iOS) / 48×48dp (Android) tap-target minimum does not apply directly
  to this AppKit, pointer-driven desktop control; it applies to the
  touch-platform translations in Platform Notes.

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
| composable-tabs-096 | reassign-identifiers-on-root-load | Construct a non-root controller with two panes of the same `paneTypeIdentifier`, load the view | Neither pane's index is assigned by `viewDidLoad()` (no call to `reassignPaneIdentifiers()` on a non-root instance) |
| composable-tabs-097 | persisted-state-applies-once | Leaf X has a persisted minimize edge and lies off the path to leaf Y, the persisted `zoomedLeaf`; `applyPersistedPaneState()` is called | X's split item ends up both pinned (`minimumThickness == maximumThickness`) and collapsed (`isCollapsed == true`) — minimize pinned it before zoom collapsed it, so neither effect is lost |

## Edge Cases

- Null/empty input (MUST): `layoutChildren` MAY legitimately be empty (a
  degenerate node mid-teardown); `snapshotNode()` then returns a placeholder
  leaf rather than trapping (see `snapshot-empty-tree-is-placeholder`). Every
  child's `thicknessFraction` is `Optional<CGFloat>`, and `nil` (never sized)
  is handled throughout by falling back to the descriptor's
  `preferredThicknessFraction` or to an even split.
- Boundary values (MUST): The array-taking initializer asserts a hard upper
  bound of 2 children (`binary-or-solo-children`); the preferred-thickness
  loop over dividers (`0..<max(splitViewItems.count - 1, 0)`) degenerates to
  zero iterations for 0 or 1 children, so a solo-child split never attempts to
  place a divider that does not exist.
- Concurrent access: Not applicable — the type is declared `@MainActor`, and
  every mutating operation (`split`, `remove`, `rebuild`, `move`,
  `captureThicknessFractions`, the persistence debounce) reads and writes
  `layoutChildren` and its own stored properties only on the main actor;
  source provides no path for two threads to mutate one instance
  simultaneously.
- Error states: see the named requirements **split-no-ops-without-project**
  (`project` is a `weak var`, and a deallocated project makes
  `split(_:adding:direction:)` return immediately with no mutation) and
  **move-permitted-without-spec** (a resolved project with no layout spec
  configured permits a move rather than refusing it). `layoutParent` is
  `weak`; `rootSplit()`'s upward walk simply stops if that chain is broken,
  rather than throwing.
- Offline/disconnected: Not applicable — this component performs no
  networking; persistence is delegated entirely to the `onLayoutDidChange`
  callback the host installs, and durability of whatever that callback does
  with the snapshot is outside this file's source.
- Zoom and minimize are mutually exclusive (MUST): `paneDidRequestZoom(_:)`
  restores a minimized pane before zooming it, and `paneDidRequestMinimize(_:to:)`
  clears an existing zoom before pinning — a pane can be in at most one of the
  two states at a time.
- Refusing the tab's last pane with nowhere to send it (MUST): if the spec
  vetoes removing a tab's only pane and no `onLastPaneCloseRequest` handler is
  installed, `paneDidRequestClose(_:)` announces a refusal and leaves the pane
  in place; the pane simply cannot be closed through this path.
- Idempotent persistence (MUST): `persistThicknessesIfChanged()` compares a
  rounded thickness signature against the last one written and skips the
  `onLayoutDidChange` call entirely when nothing actually moved — a window
  resize that ends where it began, or a tab switch that re-triggers a layout
  pass, costs no write.
- A move the spec disallows leaves the tree untouched (MUST): `move(_:_:)`
  computes the candidate tree before deciding, and returns `false` with zero
  mutation when the spec refuses it — there is no partial move to roll back.
- Rebuilding onto a shape with fewer leaves than were live (MUST): every
  previously-live leaf whose id does not survive into the new shape has
  `paneWillBeRemoved()` called on it before the new tree is constructed (see
  **rebuild-tears-down-dropped-panes**), so its process/watcher resources are
  released rather than merely dereferenced.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nodeID` | `UUID` | — (required) | Identity of this node in the persisted `LayoutNode` tree; immutable after init. |
| `axis` | `ComposableTabsAxis` | — (required) | `.horizontal` or `.vertical`; may change via `rebuild(from:)` when the persisted shape re-lays the root along the other axis. |
| `workingDirectory` | `URL` | — (required) | The directory every pane in this split, and every split nested inside it, works in; set once at init. |
| `isRoot` | `Bool` | — (required) | Whether this instance is the tab's own root; gates persistence, `viewDidAppear` restore, and `reassignPaneIdentifiers` on load. |
| `thicknessFraction` | `CGFloat?` | `nil` | This node's share (`0...1`) of the split it sits in; `nil` means "never sized." |
| `arranger` | `PaneArranger` | `InheritedSlotArranger()` | Governs how thickness fractions are redistributed when panes come and go; `ProportionalArranger` is the built-in alternative. |
| `layoutOverride` | `ComposableTabsLayout?` | `nil` | A layout this subtree uses instead of the project's own, stamped down the whole subtree. |
| `stateOwnerNodeID` | `UUID?` | `nil` | The layout node every pane in this subtree should remember its per-pane state against, for panes that are not layout nodes themselves. |
| `clampsToContainer` | `Bool` | `false` | Whether this tree's width is the enclosing container's to decide rather than its own; stamped down the whole subtree. |
| `onLayoutDidChange` | `((LayoutNode) -> Void)?` | `nil` | Root-only callback fired with a fresh snapshot whenever a persistable layout change occurs. |
| `onLastPaneCloseRequest` | `((ComposableTabsPaneViewController) -> Void)?` | `nil` | Root-only callback that, when set, lets the tab's one required pane be emptied instead of refusing its close button. |
| `zoomedLeaf` | `ComposableTabsPaneViewController?` | `nil` | Root-only: the pane currently taking over the whole tab, if any. |

## Deep Linking

Not applicable: this is an in-process view controller composing a tab's
panes, with no URL scheme, route, or deep-link handler anywhere in source.

## Localization

Not applicable: this file defines and displays no user-facing string
literals of its own; every string a user sees inside a tab belongs to the
panes this controller hosts (a separate component's concern).

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call; every arrangement
  change (`applyPreferredThicknessesIfNeeded`, zoom's `isCollapsed` flags,
  minimize's pinning) is set directly and takes effect immediately, per the
  `zoom-collapses-off-path-items` comment's own note that `isCollapsed` is
  "set directly rather than through `animator()`."
- **Increase Contrast**: Not applicable — the only custom color usage in this
  source is `PaneSplitView.drawDivider(in:)` filling with
  `currentPalette.projectPaneBackdrop`, a theme-driven color with no
  independent Increase Contrast handling in this file; that concern belongs
  to the palette/theme system, not to this component.
- **Differentiate Without Color**: Not applicable — this component conveys no
  state (zoomed, minimized, collapsed) through color at all; those states are
  conveyed by which panes are visible and how much space each occupies, which
  is unaffected by this accessibility setting.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source; the tree always lays out and mutates once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call anywhere in
this file; `onLayoutDidChange`, `onLastPaneCloseRequest`, and the
`layoutDidChangeNotification` are structural callbacks/notifications for the
hosting app, not telemetry events.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  tree of node ids, view identifiers, and sizing fractions describing *how*
  panes are arranged — never the content displayed inside a pane.
- **Storage**: In-memory only, for the life of the tree (`layoutChildren`,
  `thicknessFraction`, `zoomedLeaf`, and related properties). Whether and how
  a snapshot handed to `onLayoutDidChange` is written to disk is entirely the
  host's responsibility and outside this file's source.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the controller's own lifetime; state is
  discarded when the tab/tree is torn down (`tearDownPanes()`,
  `detachSubtree()`).

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
`Logger`/`Loggable` reference anywhere in `ComposableTabsViewController.swift`
or `ComposableTabsPaneHost.swift`).

## Platform Notes

- **SwiftUI**: Model the tree as a recursive `enum LayoutNode` (already the
  persistence type) driving a recursive `View`: a `.split` node renders a
  custom recursive `HStack`/`VStack` (from the node's axis) around two
  recursive calls, each sized with a `GeometryReader`-driven
  `.frame(width:)`/`.frame(height:)` computed from `thicknessFraction`, with a
  custom `DragGesture` on a thin overlay divider between them — SwiftUI's
  built-in `HSplitView`/`VSplitView` expose no fraction API, so a hand-built
  stack-and-overlay is used instead — to reproduce the clamp-to-minimum
  behavior of **clamp-thickness-to-minimum**. A
  `.leaf` node renders the pane's own view. Persist sizes with a
  `.onChange(of:)` debounced through a `Task` with `Task.sleep(for: .milliseconds(300))`,
  mirroring `scheduleThicknessPersist()`, and skip the write when the rounded
  signature matches the last one sent, mirroring `dedupe-unchanged-persist`.
  Represent zoom as a `@State` "zoomed id" that conditionally renders only the
  zoomed leaf's subtree instead of collapsing sibling views, since SwiftUI has
  no `isCollapsed` flag to toggle.
- **Compose**: Mirror the same recursive `LayoutNode` with a recursive
  `@Composable` function: a split renders a `Row`/`Column` (from the node's
  axis) with each child's `Modifier.weight(fraction)`, and a divider composable
  using `Modifier.pointerInput` to drag-update a `mutableStateOf(Float)`
  fraction, clamped to a minimum-thickness `Dp` the way
  `clamp-thickness-to-minimum` does. Persist via a `snapshotFlow` debounced
  with `.debounce(300)`, mirroring the AppKit debounce exactly. Represent zoom
  by conditionally emitting only the ancestors-and-zoomed-leaf subtree (`if
  (onZoomPath) { ... }`), mirroring `applyZoom(target:)`'s collapse-by-flag
  approach translated to Compose's declarative recomposition model.
- **React/Web**: Render the same recursive tree with nested CSS `flex`
  containers (`flex-direction: row`/`column` from the node's axis), each
  child sized with an inline `flex-basis` percentage derived from
  `thicknessFraction` and a `min-width`/`min-height` from the descriptor's
  `minimumThickness`, using a library such as `react-resizable-panels` (or a
  hand-rolled `pointermove` divider handler) to reproduce drag-to-resize with
  a widened invisible hit area around each divider, mirroring
  `widen-divider-grab-area`. Debounce persistence with `setTimeout(..., 300)`,
  clearing the previous timer on every resize event, mirroring
  `debounce-thickness-persist`, and compare a rounded-fraction signature
  before calling the persistence callback, mirroring `dedupe-unchanged-persist`.
  Implement zoom by conditionally rendering `display: none` on every sibling
  not on the path to the zoomed leaf, the DOM analog of `isCollapsed`.
- **AppKit/UIKit** (source platform): Implemented across
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewController.swift`
  (the tree itself: init, layout, arrangement, thickness capture/persist,
  split/remove/move/rebuild, spec-gated mutation, and `LayoutNode`
  construction) and `ComposableTabsPaneHost.swift` (the `PaneHost` conformance
  on the same type: close, minimize/restore, zoom, and the two
  root-only re-apply passes `applyPersistedPaneState()`/`reapplyPaneState()`).
  It is a `final`, `@MainActor` `NSSplitViewController` subclass built as a
  recursive binary tree of itself and `ComposableTabsPaneViewController`
  leaves, with no UIKit code path in source at all — this is a macOS-only,
  pointer-and-window-driven component (draggable dividers, a rail-pinned
  minimize, a zoom that collapses `NSSplitViewItem`s). The requirements and
  test vectors above state everything in observable terms; the private
  symbols that implement them (`applyPreferredThicknessesIfNeeded()`,
  `hasAppliedPersistedPaneState`, `detachSubtree()`, the debounced
  `DispatchWorkItem`/`pendingThicknessPersist`, `lastPersistedThicknesses`,
  and `PaneMinimizeGeometry.resolvedEdge`) are named here because they are
  private to this source file and have no analog for another platform's port
  to match. A UIKit/iPadOS port has
  no direct analog to `NSSplitViewController`'s per-item collapse/pin/minimum
  API; it would most likely use `UISplitViewController` for the fixed
  two-column case, or a hand-built recursive container (mirroring this file's
  own recursive-controller structure) using `UIStackView` plus a custom
  pan-gesture-driven divider for the general N-level tree, and would need to
  invent its own zoom/minimize/pin equivalents from scratch.
- **WinUI 3** (the reason this recipe exists): Represent each `.split` node as
  a `Grid` with exactly two `ColumnDefinition`s (`.horizontal` axis) or two
  `RowDefinition`s (`.vertical` axis), sized `GridLength(fraction,
  GridUnitType.Star)` from each child's `thicknessFraction` (an even 1★/1★
  split, mirroring "the split divides evenly," when neither child has one
  yet), separated by a `GridSplitter` whose `ResizeBehavior="PreviousAndNext"`
  and whose thickness is bound to the between-columns/between-rows gutter
  setting, mirroring `PaneSplitView.dividerThickness`; set `GridSplitter`'s
  hit-test `Width`/`Height` to at least `PaneSpacing.minimumDividerGrab` (6
  device-independent pixels) independent of its drawn thickness, mirroring
  `widen-divider-grab-area`, via a transparent margin rather than a wider
  visible bar. Recurse into a nested `Grid` for a `.split` child and a plain
  content `Frame`/`ContentPresenter` for a `.leaf` child, exactly mirroring
  `buildSplit`/`buildChild`. Debounce a `GridSplitter.DragCompleted` (not
  every intermediate drag delta) through a `DispatcherQueueTimer` set to 300ms
  and reset on every new completion, mirroring
  `scheduleThicknessPersist`/`thicknessPersistDelay`, and skip the write when
  a rounded-fraction signature matches the last one sent, mirroring
  `dedupe-unchanged-persist`. Represent **minimize** by capturing the pane's
  `ColumnDefinition`/`RowDefinition.Width`/`Height` as a fixed pixel
  `GridLength` (not `Auto`, not `*`) sized to the pane's minimized chrome, the
  direct analog of pinning `minimumThickness == maximumThickness`, and
  restore by putting the previously-recorded `Star` value back, mirroring
  `restoreSizing(of:)`'s "ceiling before floor" ordering by clearing any fixed
  cap before reasserting the star weight. Represent **zoom** by collapsing
  (`Visibility="Collapsed"`, `Width`/`Height="0"`) every `Grid`/`GridSplitter`
  off the path from the outermost `Grid` down to the zoomed leaf's container,
  and restoring all of them to their prior `GridLength`s on unzoom — the
  direct analog of toggling `NSSplitViewItem.isCollapsed` down the same path
  in `applyZoom(target:)`. A `VisualStateManager` state group
  (`Default`/`Minimized`/`Zoomed`) on the pane's own container is a reasonable
  way to drive the chrome changes that accompany each transition, mirroring
  the mutual exclusivity in `minimize-clears-zoom-first`/`zoom-toggles-and-excludes-minimize`.

## Design Decisions

- **Decision**: One-shot `hasAppliedPreferredThicknesses` guard, reset
  explicitly by every mutation that changes the arrangement (split, remove,
  rebuild, `applySizes`) rather than on every `layoutChildren` assignment.
  **Rationale**: Per the `viewDidLayout` doc comment, "after the first real
  layout the user owns the dividers, and re-imposing a fraction on every
  layout pass would fight them"; resetting only where the arrangement actually
  changes keeps a plain window resize from re-snapping dividers back to their
  preferred fractions.
  **Approved**: pending
- **Decision**: `captureThicknessFractions()` refuses to run over a zoomed
  tree, and skips a whole split (not just its pinned item) when any item in it
  shows a rail.
  **Rationale**: Per the method's own doc comment, a zoom or a rail is "an
  arrangement of the screen rather than a decision about sizes," and reading
  either back would silently corrupt the persisted layout — a saved layout
  while zoomed would "restore unzoomed and wrong," and a captured rail
  fraction would make a dragged 200pt pane "reopen at its floor" after a
  relaunch.
  **Approved**: pending
- **Decision**: Thickness persistence is debounced 300ms and deduplicated by a
  rounded signature, rather than writing on every `splitViewDidResizeSubviews`.
  **Rationale**: A drag posts a resize notification per mouse event and a
  window resize posts one per frame; per the method's doc comment, writing on
  each "would put the database in the middle of a gesture," and the signature
  check drops writes "that changed nothing" — a resize that ends where it
  began costs no write.
  **Approved**: pending
- **Decision**: `restoreSizing(of:)` clears `maximumThickness` before it
  lowers `minimumThickness`/`holdingPriority`, rather than the reverse order.
  **Rationale**: Per the method's doc comment, raising the minimum first would
  briefly ask AppKit to satisfy a minimum at or above the still-pinned
  maximum — a pair AppKit "cannot satisfy, logs, and recovers from by
  breaking one of them." Lifting the ceiling first keeps every intermediate
  state satisfiable.
  **Approved**: pending
- **Decision**: A non-root split with one remaining child collapses itself out
  of the tree instead of being left in place holding a single child.
  **Rationale**: Per `remove(_:)`'s doc comment, "a non-root split left with
  one child is a degenerate split" that should collapse into its parent; the
  *root* is allowed to hold a single child, because that legitimately
  represents "a tab reduced to one full-size pane."
  **Approved**: pending
- **Decision**: `zoomedLeaf` and `onLastPaneCloseRequest` are stored on the
  root and read through `rootSplit()`, never on an intermediate split.
  **Rationale**: Per their doc comments, a zoom "is a fact about the tab
  rather than about one split," and the last-pane-close override is "the
  right answer for a window's own tree" but has to be installed per tab
  (root) since which container "has somewhere else for the request to go"
  differs by container.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | failed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | failed | Accessibility |

Keyboard-navigable is failed because no keyboard path exists in
source for resizing a divider (see the open question about non-pointer
divider resize in Accessibility) — arrow-key pane *movement* is a real
feature, but it is dispatched from elsewhere (out of this source) into
`move(_:_:)`, not implemented here. Screen-reader-support is failed because
no accessibility role, label, or announcement is set anywhere in this source;
the divider, split view, and zoom/minimize transitions rely entirely on
AppKit's unmodified defaults — a zoom, minimize, split, remove, or move
changes what's on screen with no accessibility notification posted (see the
open question about announcing state changes in Accessibility). No other
category's checks apply: this is a pointer/keyboard-driven macOS desktop
control, not a touch surface, drawing no user-facing text and performing no
networking, telemetry, or logging of its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `ComposableTabsViewController.swift` and `ComposableTabsPaneHost.swift`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated private-symbol requirements/vectors in observable terms; split a garbled move requirement into three and promoted two implicit edge cases to named requirements with vectors; added missing opposite-branch test vectors; fixed an untestable vector; resolved the conflicting SwiftUI platform note; renamed a non-kebab-case requirement; reformatted Design Decisions; fixed the Compliance table's invalid statuses and undefined checks; renumbered a broken test-vector ID sequence; trimmed tags to 5; populated `related`. |
