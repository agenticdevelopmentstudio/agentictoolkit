---
id: 0640ca96-95c5-4234-925e-386425cc4435
title: Composable Tabs
domain: agentictoolkit://cookbook/ui/layout/composable-tabs
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A recursive split node that composes a tab's panes into a binary tree,
  with persisted sizing, spec-gated split/remove/move, and pane zoom/minimize.
platforms:
- swift
- macos
tags:
- composable-tabs
- split-view
- layout
- tabs
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
- agentictoolkit://cookbook/ui/layout/composable-tabs/pane-spacing
references: []
approved-by: ''
approved-date: ''
---

# Composable Tabs

## Overview

The composable tabs split tree is the recursive building block of a project
tab's pane layout. Each instance is either the tab's root or one node of a
binary tree nested beneath it: it holds at most two children — panes, or
further nested split nodes — laid out along an axis (horizontal or vertical).
The tree's shape and each node's share of its split (a thickness fraction)
are captured to and rebuilt from a value-type layout node, so a project's
stored layout can be persisted, restored, and mirrored across tabs. On top of
the tree itself, the split node also acts as the pane host — the object a
pane calls to close, minimize/restore, or zoom itself, and the one that
resolves those requests against the layout spec and the live split items.

## Behavioral Requirements

- **binary-or-solo-children**: Component's multi-child constructor MUST trap
  (in a debug build) when given more than two children; a split MUST be
  nested rather than given a third child directly.
- **vertical-split-set-from-axis**: Component MUST orient its divider from
  its axis — vertical when the axis is horizontal, horizontal when the axis
  is vertical — both at initial load and after every rebuild.
- **thin-divider-style**: Component MUST use a thin divider style, set at
  initial load.
- **custom-split-view-type**: Component MUST use its own themed split view
  implementation, rather than a generic one, as its split view.
- **gutter-spacing-observers**: Component MUST observe both gutter settings
  (the between-columns and between-rows spacing) from initial load onward,
  and MUST notify the split view whenever either one changes.
- **add-split-item-per-child**: Component MUST add exactly one split item for
  each of its children, in order, at initial load.
- **reassign-identifiers-on-root-load**: Component MUST reassign pane
  identifiers at initial load only when it is the tab's root.
- **schedule-persist-on-resize**: Component MUST schedule a debounced
  thickness persist, from the root, whenever the split view reports that its
  layout was resized, but only once preferred thicknesses have already been
  applied at least once for the current arrangement.
- **apply-preferred-thickness-on-layout**: Component MUST attempt to apply
  preferred/persisted thickness fractions to the split's dividers on every
  layout pass, until that application succeeds once for the current
  arrangement.
- **preferred-thickness-one-shot**: Component MUST NOT reapply preferred
  thickness fractions on a later layout pass once they have been applied for
  the current arrangement, and MUST reset that one-shot guard whenever the
  arrangement changes (a split, a removal, a rebuild, or applying sizes from
  a template).
- **skip-zero-thickness-pass**: Component MUST NOT apply preferred
  thicknesses when the split view's total extent along its axis is `1` or
  less, or when the number of installed split items does not yet equal the
  number of children.
- **dragged-fraction-outranks-descriptor**: When applying preferred
  thicknesses, Component MUST prefer a child's own thickness fraction (what
  the user dragged, or what was restored from storage) over the split item's
  preferred thickness fraction, and MUST fall back to the item's preferred
  thickness fraction only when the child has no stored fraction.
- **clamp-thickness-to-minimum**: When a fraction is being applied for a
  divider, Component MUST clamp the resulting thickness to at least that
  item's minimum thickness.
- **widen-divider-grab-area**: Component MUST widen a divider's effective
  (draggable) hit-test area, on the axis it is drawn thinner than the minimum
  divider grab width (6pt), to at least that width, without changing the area
  actually drawn.
- **stamp-ownership-on-children**: Component MUST set itself as host on every
  pane among its children and as layout parent on every nested split node
  among its children, both at initialization and whenever its children are
  reassigned.
- **inherit-arranger-to-nested-splits**: When stamping ownership, Component
  MUST propagate its own arranger to every nested split child.
- **inherit-layout-override**: When stamping ownership, Component MUST
  propagate its own layout override to every pane and nested split child.
- **inherit-state-owner-node-id**: When stamping ownership, Component MUST
  propagate its own state-owner node identifier to every pane and nested
  split child.
- **inherit-clamps-to-container**: When stamping ownership, Component MUST
  propagate its own clamps-to-container setting to every pane and nested
  split child.
- **default-arranger-is-inherited-slot**: Component MUST default its arranger
  to the inherited-slot arranger, which returns its input tree with thickness
  fractions unchanged.
- **apply-arrangement-no-op-for-default-arranger**: Applying the arrangement
  MUST have no observable effect when the installed arranger is the
  inherited-slot arranger (see **default-arranger-is-inherited-slot** for
  why: that arranger returns its input unchanged).
- **apply-arrangement-resolves-actual-axis**: When applying a non-default
  arranger, Component MUST hand the arranger the axis of its own snapshot's
  split orientation when that snapshot is itself a split node, rather than
  always using its own axis.
- **apply-arrangement-matches-by-id**: Component MUST match the fractions an
  arranger returns back onto the live children by comparing node identifier,
  and MUST leave any live child the arranger's result did not describe with
  its existing fraction unchanged.
- **capture-thicknesses-on-mutation**: Component MUST capture the live
  divider thicknesses of the whole tab into each child's thickness fraction,
  from the root, immediately before a split or remove mutation changes the
  tree.
- **capture-skips-zoomed-tree**: Component MUST NOT capture thickness
  fractions anywhere in the tab's tree while the root's zoomed leaf is set.
- **capture-skips-rail-split**: Component MUST NOT capture thickness
  fractions for a split any of whose visible items is pinned to a fixed rail
  thickness (a maximum thickness that is no longer unspecified).
- **capture-only-uncollapsed-items**: When capturing thicknesses, Component
  MUST record a fraction only for items that are not currently collapsed.
- **capture-recurses-into-children**: Capturing thickness fractions MUST
  recurse into every nested split child regardless of whether the split
  itself just captured a fraction.
- **apply-sizes-matches-existing-shape**: Applying sizes from a template MUST
  copy thickness fractions from the template layout node onto the live tree
  only at levels where the live child count (`1` or `2`) matches the
  template's shape, and MUST leave a mismatched subtree untouched rather than
  partially applying sizes to it.
- **apply-sizes-forces-relayout**: After adopting new sizes, applying sizes
  from a template MUST reset the one-shot thickness-application guard and
  MUST immediately reapply thicknesses for any subtree whose view is already
  loaded.
- **debounce-thickness-persist**: Component MUST debounce a divider-driven
  persist by 300ms after each reported resize, canceling any still-pending
  write each time a new resize notification arrives.
- **dedupe-unchanged-persist**: Component MUST NOT invoke its layout-change
  callback when the rounded thickness signature of the current snapshot is
  unchanged from the last one persisted.
- **flush-pending-persist-on-demand**: Component MUST provide a way to flush
  a pending thickness persist immediately, which MUST write a still-pending
  debounced persist immediately and MUST do nothing when no persist is
  currently pending.
- **persist-only-from-root**: Component MUST schedule, flush, and perform a
  thickness persist only when it is the root; a non-root split MUST NOT
  independently start or flush a persist timer.
- **split-creates-sibling-pane**: Splitting a pane MUST create a new pane
  showing the given view identifier as a sibling of the pane being split, and
  MUST place the new sibling first or second in the resulting inner split
  according to whether the given direction places the new pane first.
- **split-wraps-in-inner-split**: Splitting a pane MUST replace the split
  pane's slot with a new nested split node holding exactly the original pane
  and the new sibling, laid out along the given direction's own axis.
- **split-inherits-slot-size**: The new inner split created by a split MUST
  inherit the thickness fraction the original pane held in its slot, and the
  original pane's own fraction MUST be cleared, so the two panes start out
  sharing the inner split evenly.
- **split-propagates-configuration**: The inner split created by a split MUST
  end up with the enclosing split's arranger, layout override, state-owner
  node identifier, and clamps-to-container setting, per
  **inherit-arranger-to-nested-splits**, **inherit-layout-override**,
  **inherit-state-owner-node-id**, and **inherit-clamps-to-container**.
- **split-persists-and-rearranges**: After a split completes, Component MUST
  apply the arrangement and persist the tree, both from the root.
- **split-no-ops-without-project**: A split MUST return immediately,
  performing no mutation, when its project has already gone away.
- **remove-refuses-non-direct-child**: Removing a pane MUST have no effect
  when the given pane is not a direct child of the split it is called on.
- **remove-honors-spec-veto**: Removing a pane MUST have no effect when the
  root's layout spec refuses to remove the given leaf.
- **remove-tears-down-pane-content**: Removing a pane MUST clear the removed
  pane's host and MUST notify it that it is being removed, after detaching it
  from the split view.
- **remove-clears-sibling-fractions**: After a removal, Component MUST clear
  the thickness fraction of every remaining child in that split, since those
  fractions described a split that no longer exists.
- **remove-collapses-degenerate-split**: When a non-root split is left with
  exactly one child after a removal, Component MUST collapse that split out
  of the tree, promoting the surviving child into the collapsing split's own
  slot (inheriting its thickness fraction) in the parent split.
- **remove-rehomes-focus**: If the removed pane held input focus, removing it
  MUST move input focus to the root's first leaf (depth-first order) once
  removal completes.
- **remove-persists-and-rearranges**: After a removal completes, Component
  MUST apply the arrangement and persist the tree, both from the root.
- **move-refused-by-spec**: Moving a pane MUST compute the candidate new tree
  via the move-resolution logic against the root's current snapshot, and MUST
  return `false` without mutating the tree when the project's layout spec
  disallows the resulting tree.
- **move-permitted-without-spec**: Moving a pane MUST treat a resolved
  project that has no layout spec configured at all as permitting the move,
  rather than refusing it.
- **move-rebuilds-root**: When the candidate tree is permitted (by
  **move-refused-by-spec** or **move-permitted-without-spec**), moving a pane
  MUST rebuild the root from that tree and return `true`.
- **available-directions-filtered-by-spec**: Computing the available move
  directions for a pane MUST return only the directions, among those the
  move-resolution logic reports as available, for which the resulting moved
  tree is allowed by the project's layout spec.
- **rebuild-reuses-live-panes**: Rebuilding from a template MUST reuse an
  existing live pane for any leaf id that survives into the new shape, rather
  than constructing a new pane for that id.
- **rebuild-tears-down-dropped-panes**: Rebuilding MUST notify every
  previously-live leaf whose id does not appear among the new shape's leaf
  ids that it is being removed.
- **rebuild-detaches-before-rehosting**: Rebuilding MUST detach every current
  child (clearing its host/layout-parent, and removing its split item when
  the view is loaded) before constructing the new tree.
- **rebuild-single-leaf-becomes-root-child**: When the rebuilt shape is a
  single leaf, rebuilding MUST host it as the split's sole child rather than
  wrapping it in a further nested split.
- **rebuild-carries-thickness-fractions**: Every child constructed or reused
  during a rebuild MUST receive the thickness fraction recorded on its
  corresponding layout node.
- **rebuild-persists-from-root**: Rebuilding MUST persist the tree from the
  root after rebuilding.
- **allowed-insertions-delegates-to-spec**: Computing the allowed insertions
  beside a leaf MUST return the result of asking the layout spec, given the
  root's current snapshot and view registry, and MUST return an empty list
  when the split has no root.
- **can-remove-leaf-delegates-to-spec**: Checking whether a leaf may be
  removed MUST return the result of asking the layout spec whether the given
  leaf may be removed from the root's current snapshot, and MUST return
  `false` when the split has no root.
- **root-split-walk-uses-is-root**: Finding the root split MUST walk up
  through each split's layout parent until it reaches the node marked as
  root, and MUST NOT stop merely because a node currently has no visible
  parent in the view hierarchy.
- **tear-down-panes-notifies-every-leaf**: Tearing down panes MUST notify
  every leaf in the subtree that it is being removed.
- **reassign-ambiguous-pane-numbers**: Reassigning pane identifiers MUST
  assign a 1-based index only to leaves whose pane type occurs more than once
  among the tab's leaves (in depth-first order), and MUST clear the index
  (assign none) on every leaf whose type is unique in the tab.
- **persist-tree-only-from-root**: Persisting the tree MUST have no effect
  when Component is not the root.
- **persist-tree-sequence**: When Component is the root, persisting the tree
  MUST, in this order: reassign pane identifiers, reapply pane state, refresh
  pane controls, invoke the layout-change callback with the current snapshot,
  and post a layout-changed notification with itself as the notification's
  subject.
- **snapshot-unwraps-single-child**: Taking a snapshot MUST return the
  snapshot of its sole child directly, without an enclosing split node, when
  the split holds exactly one child.
- **snapshot-empty-tree-is-placeholder**: Taking a snapshot MUST return a
  placeholder leaf node when the split holds zero children.
- **make-item-sizing**: Building a split item for a child MUST set the
  resulting item's minimum thickness from the recursive minimum-thickness
  computation over the registered view descriptor(s) beneath that child, MUST
  set whether it can collapse from the pane's descriptor (`false` for a
  non-pane child), and MUST set its preferred thickness fraction from the
  descriptor when the descriptor declares one.
- **make-item-holding-priority**: Building a split item MUST set the item's
  holding priority to the descriptor's resolved holding priority unless the
  split's clamps-to-container setting is `true`, in which case it MUST use
  the fixed, minimal priority.
- **clamped-tree-has-no-minimum**: When clamps-to-container is `true`, an
  item's minimum thickness MUST be left unspecified regardless of the
  descriptor's declared minimum.
- **restore-sizing-order**: Restoring an item's sizing MUST clear the item's
  maximum thickness before it lowers its minimum thickness and resets its
  holding priority back to their registered values.
- **build-from-persisted-leaf-wraps-in-root-split**: Constructing from a
  persisted layout node MUST host a top-level leaf node inside a newly
  created, non-persisted wrapper split (a fresh node identifier, horizontal
  axis) when building the root, so a tab always has a split at its root.
- **build-carries-fraction-to-child**: Constructing a child from a persisted
  layout node MUST transfer that node's thickness fraction onto the
  constructed or reused child.
- **close-checks-membership**: Requesting a pane's close MUST decline the
  request, announcing a refusal, when the pane is not currently a direct
  child of the split that receives the request.
- **close-honors-spec-veto-with-fallback**: Requesting a pane's close MUST
  refuse (announcing a refusal) when the root's layout spec disallows
  removing the pane and either no last-pane-close handler is installed on the
  root or the tab holds more than that one pane; when a handler is installed
  and the pane is the tab's only pane, it MUST invoke that handler instead of
  removing the pane.
- **close-clears-zoom-before-removal**: Requesting a pane's close MUST clear
  the root's zoomed leaf before removing a pane that is currently the zoomed
  leaf.
- **can-close-mirrors-close-refusal**: Checking whether a pane can close MUST
  return `true` exactly when requesting its close would actually remove the
  pane or hand it to a last-pane-close handler (the spec allows removing it,
  or a handler exists and the tab holds exactly one pane).
- **minimize-refuses-unresolvable-edge**: Requesting a pane's minimize MUST
  have no effect when the requested edge cannot be resolved against the axis
  of the tree at that pane's position.
- **minimize-clears-zoom-first**: Requesting a pane's minimize MUST clear any
  existing zoom before minimizing a pane, and in that case MUST NOT
  re-capture thickness fractions (the fractions captured on the way into the
  zoom are preserved instead).
- **minimize-pins-split-item**: Requesting a pane's minimize MUST pin the
  owning split item to the pane's minimized thickness for the resolved edge
  by setting its minimum thickness equal to its maximum thickness and raising
  its holding priority to a high priority, without altering its preferred
  thickness fraction.
- **minimize-is-unconditional-on-model**: Requesting a pane's minimize MUST
  record the pane's minimized state even when the tab has never been
  displayed and no split item yet exists to pin.
- **restore-unpins-and-clears**: Requesting a pane's restore MUST restore the
  owning split item's sizing when an item exists, and MUST clear the pane's
  minimized state regardless of whether an item exists.
- **zoom-toggles-and-excludes-minimize**: Requesting a pane's zoom MUST
  restore a minimized pane before zooming it, and MUST toggle the root's
  zoomed leaf between the given pane and none.
- **zoom-collapses-off-path-items**: Setting the zoomed leaf MUST collapse
  every split item that does not lie on the path from the root down to the
  zoomed leaf, and MUST un-collapse every item when the target is cleared.
- **zoom-preserves-tree-shape**: Zooming MUST NOT reparent, remove, or resize
  (in thickness-fraction terms) any node in the tree; only each split item's
  collapsed flag changes.
- **persisted-state-applies-once**: Applying persisted pane state MUST run at
  most once per root instance, MUST apply minimize state before zoom state,
  and MUST have no effect when Component is not the root.
- **persisted-minimize-restores-if-edge-invalid**: When a leaf's persisted
  minimize edge cannot be resolved against the current tree, applying
  persisted pane state MUST restore that pane instead of leaving it minimized
  with no way for the user to undo it.
- **reapply-pane-state-is-idempotent**: Reapplying pane state MUST run on
  every rebuild (it holds no one-shot latch), and re-applying a collapsed or
  pinned state that is already correct MUST NOT trigger an additional resize
  notification.
- **reapply-drops-stale-zoom**: Reapplying pane state MUST clear the root's
  zoomed leaf and un-collapse the tree when the zoomed leaf is no longer
  present among the tab's leaves.
- **reapply-reresolves-minimize-edge**: Reapplying pane state MUST
  re-resolve each minimized leaf's edge against the current tree rather than
  trust the edge it was last minimized to, and MUST restore the pane instead
  when no edge remains valid.
- **refresh-pane-controls-notifies-every-leaf**: Refreshing pane controls
  MUST re-ask every leaf in the tab to refresh its own control availability.
- **custom-arranger**: Component MAY be configured with a custom arranger
  (for example, a proportional arranger) in place of the default
  inherited-slot arranger, to redistribute thickness fractions along the
  arrangement axis differently than "leave what a split/remove already
  assigned."

## Appearance

- **Corner radius**: Not applicable — the split and its items draw no custom
  layer or corner radius anywhere in this component's own drawing.
- **Padding**: Not set by this component directly. A separate, app-wide
  content-inset setting (four independently configurable edge values, each
  `0` by default) is applied around the pane area by the window/container
  that hosts a root split node; this component itself sets no content insets
  on its own view.
- **Font**: Not applicable — this component draws no text of its own; any
  text belongs to the panes it hosts.
- **Background**: A divider wider than 1pt is filled with the theme's
  pane-backdrop color, so a wide gutter reads as the same backdrop plane the
  frame spacing shows, not a colored bar; a divider at or under 1pt falls
  back to the split view's own default drawing.
- **Foreground/Text**: Not applicable — no text is drawn by this component.
- **Border**: Not applicable — no border is configured on the split view or
  its items anywhere in source.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A pane's minimum thickness comes from its registered view
  descriptor (`120pt` by default); a nested split's minimum is the sum of its
  children's minimums along the split's own axis, or the max of them across
  it. A divider's thickness is the between-columns spacing (vertical split)
  or the between-rows spacing (horizontal split) — both `1pt` by default —
  and its draggable hit area is widened to at least the minimum divider grab
  width (`6pt`) without changing the drawn gutter width. A minimized pane is
  pinned to a fixed thickness (its minimum thickness equal to its maximum
  thickness) computed by the pane itself.

## States

| State | Appearance change |
|-------|------------------|
| Default (arranged) | Panes/nested splits occupy the fractions of the split's extent recorded in their thickness fraction, or share evenly when none is set; dividers are drawn at the gutter thickness for the split's axis. |
| Dragging a divider | The user's drag moves the divider live; once released, the split view's resize notification schedules a 300ms-debounced write of the new fractions rather than persisting on every intermediate frame. |
| Minimized (rail) | The pane's owning split item is pinned to a fixed thickness (minimum thickness equal to maximum thickness) with a high holding priority; the item cannot be dragged narrower or wider, and a window resize is taken out of its neighbours instead. |
| Zoomed | Every split item off the path from the root to the zoomed leaf is collapsed; the zoomed leaf's ancestors on that path stay visible and sized as before. Only one leaf per tab may be zoomed at a time (root-only). |
| Collapsed by spec | Not applicable in this component: whether an item can collapse is set from the pane's descriptor, but nothing here ever collapses an item on that basis outside of the zoom path above — user-driven collapse-by-drag is the split view's own default behavior for a collapsible item. |
| Pressed | Not applicable: neither the split view nor its dividers expose a pressed/highlighted visual state in source. |
| Disabled | Not applicable: no split item, divider, or child is ever disabled in source. |
| Focused | Not applicable to the split itself: input focus moves among the *panes* it hosts (see **remove-rehomes-focus**); the split node has no focus appearance of its own. |
| Loading | Not applicable: every mutation (split, remove, rebuild, move) is synchronous; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: Not explicitly set in source. The underlying split control
  exposes its platform's own default split-view accessibility role and
  divider semantics; this component overrides no accessibility API of its
  own.
- **Label requirements**: Not applicable at this level — no accessibility
  label or identifier is assigned to the split view, a divider, or an item in
  this source; a pane's own accessible content is that pane's own concern
  (each pane is a separately hosted child component with its own view).
- **Announce state changes**: Not implemented in source. A zoom, a
  minimize/restore, a split, a remove, or a move all change which panes are
  visible and how much space each has, but nothing in this source posts an
  accessibility notification when any of these happen; the refusal path even
  for a genuinely-blocked action is a plain audible beep, not a
  screen-reader-readable message. A screen reader user is not told a pane
  appeared, disappeared, or changed size, and hears nothing until navigating
  back into the split.
- **non-pointer-resize**: NEEDS REVIEW: Not implemented in source. A
  divider's thickness changes only via a pointer drag (plus the widened
  hit-test area from `widen-divider-grab-area`); no method here lets a
  keyboard-only or switch-control user change a thickness fraction without a
  pointer, and whether the platform's own default keyboard-accessibility
  behavior (if any) is sufficient, or a keyboard resize command should be
  added, needs a keyboard-only/screen-reader pass over a live project window
  to settle. Touch tap-target minimum guidance does not apply here: this is a
  pointer-driven, not touch-driven, control.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-001 | binary-or-solo-children | The multi-child constructor is given 3 children | Construction traps (an assertion failure) in a debug build |
| composable-tabs-003 | vertical-split-set-from-axis | Construct with a horizontal axis, then load | The divider is drawn vertically |
| composable-tabs-004 | thin-divider-style | Load the split | The divider style is thin |
| composable-tabs-005 | custom-split-view-type | Inspect the split view after it loads | The split view is the component's own themed implementation, not a stock one |
| composable-tabs-006 | gutter-spacing-observers | The view is loaded with a spy split view that records spacing-change notifications; the between-columns pane spacing setting is changed | The spy records exactly one spacing-change notification, and the split view is marked for redraw immediately afterward |
| composable-tabs-007 | add-split-item-per-child | Construct with 2 children, then load | There are exactly 2 split items, in the same order as the children |
| composable-tabs-008 | reassign-identifiers-on-root-load | Construct a root split with two panes of the same pane type, then load | Both panes receive non-none, sequential indices from reassigning pane identifiers |
| composable-tabs-009 | schedule-persist-on-resize | Preferred thicknesses already applied once; the split view reports a resize | A debounced persist is scheduled on the root; flushing the pending persist now performs a write |
| composable-tabs-010 | apply-preferred-thickness-on-layout | A layout pass runs with a real (non-placeholder) split-view width | Divider positions are set from each child's thickness fraction |
| composable-tabs-011 | preferred-thickness-one-shot | Thicknesses already applied for the current arrangement; a further layout pass runs | No divider position is changed by the second pass |
| composable-tabs-012 | skip-zero-thickness-pass | The split view's width is `0`; a layout pass runs | No divider position is set; when a layout pass later runs with a real width, thicknesses are still applied then (the skip did not consume the one-shot) |
| composable-tabs-013 | dragged-fraction-outranks-descriptor | Child's own thickness fraction is `0.7`; its split item's preferred thickness fraction is `0.3` | The divider is placed using `0.7`, not `0.3` |
| composable-tabs-014 | clamp-thickness-to-minimum | Fraction implies a thickness below the item's minimum thickness | The divider is placed at the minimum thickness, not the smaller fraction-derived value |
| composable-tabs-015 | widen-divider-grab-area | Gutter is set to `0`pt (vertical split); the platform asks for the divider's effective hit-test rectangle | The returned rectangle is inset to at least the minimum divider grab width (6pt) wide while the drawn rectangle stays at 0pt |
| composable-tabs-016 | stamp-ownership-on-children | Assign children = [pane, nestedSplit] | The pane's host is this component and the nested split's layout parent is this component |
| composable-tabs-017 | inherit-arranger-to-nested-splits | Set arranger to a proportional arranger with a nested split among the children | The nested split's arranger is the same proportional-arranger instance |
| composable-tabs-018 | inherit-layout-override | Set layout override to a non-none value | Every pane and nested split among the children reports the same layout override |
| composable-tabs-019 | inherit-state-owner-node-id | Set state-owner node identifier to a fresh identifier | Every pane and nested split among the children reports the same state-owner node identifier |
| composable-tabs-020 | inherit-clamps-to-container | Set clamps-to-container to `true` | Every pane and nested split among the children reports clamps-to-container `true` |
| composable-tabs-021 | default-arranger-is-inherited-slot | Read the arranger on a freshly constructed component | It is the inherited-slot arranger, and applying it returns the node unchanged |
| composable-tabs-022 | apply-arrangement-no-op-for-default-arranger | Arranger is the default; apply the arrangement | No thickness fraction on any child changes and no layout pass is forced |
| composable-tabs-023 | apply-arrangement-resolves-actual-axis | Root holds one child that is itself a vertical split; apply a non-default arranger | The arranger is invoked with the vertical axis, not the root's own axis |
| composable-tabs-024 | apply-arrangement-matches-by-id | Arranger's result omits one child's identifier | That child's existing thickness fraction is left unchanged after fractions are applied |
| composable-tabs-025 | capture-thicknesses-on-mutation | User has dragged a divider; a split is performed | The pre-split live thickness is captured into the affected child's thickness fraction before the tree changes |
| composable-tabs-026 | capture-skips-zoomed-tree | Root's zoomed leaf is set; thicknesses are captured | No child's thickness fraction anywhere in the tree is modified |
| composable-tabs-027 | capture-skips-rail-split | One split's visible item is pinned to a fixed rail thickness; thicknesses are captured on it | No item in that split has its thickness fraction written |
| composable-tabs-028 | capture-only-uncollapsed-items | One item in a split is collapsed; thicknesses are captured | The collapsed item's child does not have its thickness fraction overwritten |
| composable-tabs-029 | capture-recurses-into-children | A rail split contains a nested split with its own children | Capturing thicknesses still descends into and updates the nested split's own children |
| composable-tabs-030 | apply-sizes-matches-existing-shape | Live tree has 1 child; template layout node is a 2-child split | Applying sizes leaves the live tree's single child untouched |
| composable-tabs-031 | apply-sizes-forces-relayout | Sizes are applied from a template on a loaded view | The one-shot thickness guard is reset and dividers move to the new fractions before the next natural layout pass |
| composable-tabs-032 | debounce-thickness-persist | Two resize notifications arrive 100ms apart | Only one layout-change callback happens, timed 300ms after the second notification |
| composable-tabs-033 | dedupe-unchanged-persist | A pending persist's rounded thickness signature matches the signature already delivered to the layout-change callback | The layout-change callback is not invoked |
| composable-tabs-034 | flush-pending-persist-on-demand | No persist is currently pending; a flush is requested | The layout-change callback is not invoked and no error occurs |
| composable-tabs-035 | persist-only-from-root | A persist is scheduled on a non-root split | No persist is armed and no write ever occurs from that instance; a subsequent flush on it still does nothing |
| composable-tabs-036 | split-creates-sibling-pane | Split a pane, adding a new view to its right | A new pane showing that view is added as the second child of a new inner split, the original pane as the first |
| composable-tabs-037 | split-wraps-in-inner-split | Same split as above | The original slot is replaced by a new split node laid out horizontally (from the given direction's axis) |
| composable-tabs-038 | split-inherits-slot-size | Pane's thickness fraction is `0.4` before the split | The new inner split's thickness fraction is `0.4`; the pane's own fraction is none afterward |
| composable-tabs-039 | split-propagates-configuration | Enclosing split has a custom arranger, layout override, state-owner node identifier, clamps-to-container `true` | The new inner split reports all four of the same values |
| composable-tabs-040 | split-persists-and-rearranges | A split completes | The arrangement is applied and the layout-change callback fires from the root |
| composable-tabs-041 | remove-refuses-non-direct-child | Remove a pane not in this split | The children are unchanged and no split item is removed |
| composable-tabs-042 | remove-honors-spec-veto | Layout spec's remove-check returns `false` for the given leaf | Removal returns with the children unchanged |
| composable-tabs-043 | remove-tears-down-pane-content | Removal of a pane succeeds | The pane's host is none and it has been notified of its removal exactly once |
| composable-tabs-044 | remove-clears-sibling-fractions | Split has 2 children, each with a non-none fraction; one is removed | The remaining child's thickness fraction is none after removal |
| composable-tabs-045 | remove-collapses-degenerate-split | Non-root split with 2 children; one is removed | The split itself is replaced in its parent by the surviving child, at the collapsing split's former thickness fraction |
| composable-tabs-046 | remove-rehomes-focus | Removed pane's view held input focus | After removal, the root's first leaf (depth-first) receives input focus |
| composable-tabs-047 | remove-persists-and-rearranges | A removal completes | The arrangement is applied and the layout-change callback fires from the root |
| composable-tabs-048 | move-refused-by-spec | Spec disallows the moved tree | Moving the leaf left returns `false`; the children are unchanged |
| composable-tabs-049 | available-directions-filtered-by-spec | Available move directions report left and right; spec disallows left's resulting tree | Only right remains available for the leaf |
| composable-tabs-050 | rebuild-reuses-live-panes | New shape's leaf id matches a currently-live pane's node identifier | Rebuilding reuses the exact same pane instance for that id |
| composable-tabs-051 | rebuild-tears-down-dropped-panes | New shape omits a leaf id that was live before | That leaf is notified of its removal exactly once |
| composable-tabs-052 | rebuild-detaches-before-rehosting | Rebuild is called on a loaded view | Every prior split item is removed and every prior child's host/layout-parent is none before any new item is added |
| composable-tabs-053 | rebuild-single-leaf-becomes-root-child | New shape is a single leaf node | The root's children has exactly 1 entry: that leaf's pane, with no extra nested split |
| composable-tabs-054 | rebuild-carries-thickness-fractions | Template layout node for a child has thickness fraction `0.25` | The constructed/reused child's thickness fraction is `0.25` |
| composable-tabs-055 | rebuild-persists-from-root | Rebuild completes | The layout-change callback fires from the root with the new snapshot |
| composable-tabs-056 | allowed-insertions-delegates-to-spec | Split has a root; allowed insertions beside a leaf are requested | Returns exactly what the layout spec returns for the root's snapshot |
| composable-tabs-057 | can-remove-leaf-delegates-to-spec | Split has no root | Checking whether a leaf may be removed returns `false` |
| composable-tabs-058 | root-split-walk-uses-is-root | A non-root split's view has never loaded (no parent in the view hierarchy) but its layout-parent chain reaches a node marked as root | Finding the root split returns that root, not none |
| composable-tabs-059 | tear-down-panes-notifies-every-leaf | Subtree has 3 leaves; panes are torn down | All 3 leaves are notified of removal exactly once each |
| composable-tabs-060 | reassign-ambiguous-pane-numbers | Tab has 2 terminals and 1 file browser | Both terminals get non-none, sequential indices; the file browser's index is none |
| composable-tabs-061 | persist-tree-only-from-root | Persisting the tree is requested on a non-root split | No pane identifiers are reassigned and the layout-change callback is not invoked |
| composable-tabs-062 | persist-tree-sequence | Root's tree persist is requested | Pane identifiers are reassigned, pane state is reapplied, pane controls are refreshed, the layout-change callback fires, then the notification is posted, all in that order |
| composable-tabs-063 | snapshot-unwraps-single-child | Split has exactly 1 child | The snapshot returns that child's own snapshot, not a wrapping split node |
| composable-tabs-064 | snapshot-empty-tree-is-placeholder | Split has 0 children | The snapshot returns a placeholder leaf |
| composable-tabs-065 | make-item-sizing | Pane's descriptor has minimum thickness `200`, is collapsible, preferred thickness fraction `0.3` | The built item has minimum thickness `200`, can collapse, preferred thickness fraction `0.3` |
| composable-tabs-066 | make-item-holding-priority | Clamps-to-container is `true` | The built item's holding priority is the fixed minimal value regardless of the descriptor |
| composable-tabs-067 | clamped-tree-has-no-minimum | Clamps-to-container is `true`; descriptor declares minimum thickness `300` | The built item's minimum thickness is left unspecified |
| composable-tabs-068 | restore-sizing-order | Item is currently pinned (rail); its sizing is restored | Its maximum thickness is cleared before minimum thickness/holding priority are reset (no transient invalid constraint pair is ever observed) |
| composable-tabs-069 | build-from-persisted-leaf-wraps-in-root-split | Construct from a persisted leaf node as root | The returned split's children has exactly 1 entry; its own axis is horizontal and its node identifier is freshly minted, not the leaf's id |
| composable-tabs-070 | build-carries-fraction-to-child | Persisted leaf node has thickness fraction `0.6` | The constructed pane's thickness fraction is `0.6` |
| composable-tabs-071 | close-checks-membership | Pane is not among the children of the split receiving the request | A refusal is announced; removal is never attempted |
| composable-tabs-072 | close-honors-spec-veto-with-fallback | Spec vetoes removal; no last-pane-close handler is set | A refusal is announced; the pane is not removed |
| composable-tabs-073 | close-honors-spec-veto-with-fallback | Spec vetoes removal; a last-pane-close handler is set; tab holds exactly 1 pane | The handler is invoked with the pane; removal is not attempted |
| composable-tabs-074 | close-clears-zoom-before-removal | Pane is the root's zoomed leaf; close is requested and permitted | The zoomed leaf is cleared by the time removal runs |
| composable-tabs-075 | can-close-mirrors-close-refusal | Spec allows removing the pane | Checking whether it can close returns `true` |
| composable-tabs-076 | minimize-refuses-unresolvable-edge | The requested edge cannot be resolved against the axis of the tree at the pane's position (for example, a leading/trailing edge requested where the enclosing split's axis is vertical) | No item is pinned and the pane's minimized state is not set |
| composable-tabs-077 | minimize-clears-zoom-first | Root is zoomed; a pane is minimized | The zoomed leaf becomes none; thicknesses are not re-captured for this minimize |
| composable-tabs-078 | minimize-pins-split-item | Minimize succeeds and an item exists | The item's minimum and maximum thickness both equal the pane's minimized thickness for the resolved edge; holding priority is high; preferred thickness fraction is unchanged |
| composable-tabs-079 | minimize-is-unconditional-on-model | Tab has never been displayed (no split item exists) | The pane's minimized state is still recorded |
| composable-tabs-080 | restore-unpins-and-clears | An item exists for a minimized pane; restore is requested | The item's sizing is restored and the pane's minimized state is cleared |
| composable-tabs-081 | zoom-toggles-and-excludes-minimize | A minimized pane is zoomed | The pane is restored first, then the zoomed leaf is set to that pane |
| composable-tabs-082 | zoom-collapses-off-path-items | Deep tree; a leaf 3 levels down is zoomed | Every split item not on the root-to-leaf path is collapsed; items on the path are not |
| composable-tabs-083 | zoom-preserves-tree-shape | A pane is zoomed then unzoomed | The snapshot before and after report identical structure and thickness fractions |
| composable-tabs-084 | persisted-state-applies-once | Applying persisted pane state is called twice on the same root instance | The second call has no additional effect: no leaf's minimize or zoom state changes as a result of it |
| composable-tabs-085 | persisted-minimize-restores-if-edge-invalid | A leaf's persisted edge no longer resolves against the current tree | The leaf is restored instead of minimized |
| composable-tabs-086 | reapply-pane-state-is-idempotent | Pane state is reapplied twice in a row with no tree change between calls | No additional resize notification or persist is triggered by the second call |
| composable-tabs-087 | reapply-drops-stale-zoom | Zoomed leaf points to a pane no longer among the tab's leaves | The zoomed leaf becomes none and every item is un-collapsed |
| composable-tabs-088 | reapply-reresolves-minimize-edge | A rebuild changed the axis under a minimized pane so its stored edge no longer applies, but a different edge does | The pane is minimized with the re-resolved edge, not the stale one |
| composable-tabs-089 | refresh-pane-controls-notifies-every-leaf | Tab has 3 leaves; pane controls are refreshed | Each of the 3 leaves' control-availability refresh is called exactly once |
| composable-tabs-090 | split-no-ops-without-project | The project has already gone away; a split adding a new view to the right is requested | The children are unchanged and no split item is added |
| composable-tabs-091 | move-permitted-without-spec | Resolved project has no layout spec configured at all | Moving the leaf left returns `true` and rebuilds the root from the moved tree |
| composable-tabs-092 | move-rebuilds-root | Spec permits the moved tree | Moving returns `true` and the root's children match the moved tree's shape |
| composable-tabs-093 | can-close-mirrors-close-refusal | Spec disallows removing the pane and no last-pane-close handler is installed | Checking whether it can close returns `false` |
| composable-tabs-094 | flush-pending-persist-on-demand | A resize notification has armed a pending debounced persist; a flush is requested before the debounce timer fires | The write happens immediately and no later timer-driven write follows |
| composable-tabs-095 | vertical-split-set-from-axis | Construct with a vertical axis, then load | The divider is drawn horizontally |
| composable-tabs-096 | reassign-identifiers-on-root-load | Construct a non-root split with two panes of the same pane type, then load | Neither pane's index is assigned by loading (reassignment does not run on a non-root instance) |
| composable-tabs-097 | persisted-state-applies-once | Leaf X has a persisted minimize edge and lies off the path to leaf Y, the persisted zoomed leaf; persisted pane state is applied | X's split item ends up both pinned (minimum thickness equal to maximum thickness) and collapsed — minimize pinned it before zoom collapsed it, so neither effect is lost |

## Edge Cases

- Null/empty input (MUST): The list of children MAY legitimately be empty (a
  degenerate node mid-teardown); taking a snapshot then returns a placeholder
  leaf rather than trapping (see `snapshot-empty-tree-is-placeholder`). Every
  child's thickness fraction may be unset, and unset (never sized) is handled
  throughout by falling back to the descriptor's preferred thickness fraction
  or to an even split.
- Boundary values (MUST): Construction traps at a hard upper bound of 2
  children (`binary-or-solo-children`); the preferred-thickness loop over
  dividers degenerates to zero iterations for 0 or 1 children, so a
  solo-child split never attempts to place a divider that does not exist.
- Concurrent access: Not applicable — the type is confined to run on a single
  thread, and every mutating operation (split, remove, rebuild, move,
  capturing thickness fractions, the persistence debounce) reads and writes
  its children and its own stored state only there; source provides no path
  for two threads to mutate one instance simultaneously.
- Error states: see the named requirements **split-no-ops-without-project**
  (the project reference is held weakly, and a project that has already gone
  away makes a split return immediately with no mutation) and
  **move-permitted-without-spec** (a resolved project with no layout spec
  configured permits a move rather than refusing it). The layout-parent
  reference is also held weakly; finding the root's upward walk simply stops
  if that chain is broken, rather than throwing.
- Offline/disconnected: Not applicable — this component performs no
  networking; persistence is delegated entirely to the layout-change callback
  the host installs, and durability of whatever that callback does with the
  snapshot is outside this component's own concern.
- Zoom and minimize are mutually exclusive (MUST): requesting zoom restores a
  minimized pane before zooming it, and requesting minimize clears an
  existing zoom before pinning — a pane can be in at most one of the two
  states at a time.
- Refusing the tab's last pane with nowhere to send it (MUST): if the spec
  vetoes removing a tab's only pane and no last-pane-close handler is
  installed, requesting close announces a refusal and leaves the pane in
  place; the pane simply cannot be closed through this path.
- Idempotent persistence (MUST): comparing a rounded thickness signature
  against the last one written and skipping the layout-change callback
  entirely when nothing actually moved — a window resize that ends where it
  began, or a tab switch that re-triggers a layout pass, costs no write.
- A move the spec disallows leaves the tree untouched (MUST): moving
  computes the candidate tree before deciding, and returns `false` with zero
  mutation when the spec refuses it — there is no partial move to roll back.
- Rebuilding onto a shape with fewer leaves than were live (MUST): every
  previously-live leaf whose id does not survive into the new shape is
  notified of its removal before the new tree is constructed (see
  **rebuild-tears-down-dropped-panes**), so its process/watcher resources are
  released rather than merely dereferenced.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nodeID` | identifier | — (required) | Identity of this node in the persisted layout-node tree; immutable after construction. |
| `axis` | axis (horizontal or vertical) | — (required) | The direction children are arranged along; may change via a rebuild when the persisted shape re-lays the root along the other axis. |
| `workingDirectory` | path | — (required) | The directory every pane in this split, and every split nested inside it, works in; set once at construction. |
| `isRoot` | boolean | — (required) | Whether this instance is the tab's own root; gates persistence, state restoration on first appearance, and reassigning pane identifiers at load. |
| `thicknessFraction` | number or unset | unset | This node's share (`0` to `1`) of the split it sits in; unset means "never sized." |
| `arranger` | arranger | inherited-slot arranger | Governs how thickness fractions are redistributed when panes come and go; a proportional arranger is the built-in alternative. |
| `layoutOverride` | layout override or none | none | A layout this subtree uses instead of the project's own, stamped down the whole subtree. |
| `stateOwnerNodeID` | identifier or none | none | The layout node every pane in this subtree should remember its per-pane state against, for panes that are not layout nodes themselves. |
| `clampsToContainer` | boolean | `false` | Whether this tree's width is the enclosing container's to decide rather than its own; stamped down the whole subtree. |
| `onLayoutDidChange` | callback or none | none | Root-only callback fired with a fresh snapshot whenever a persistable layout change occurs. |
| `onLastPaneCloseRequest` | callback or none | none | Root-only callback that, when set, lets the tab's one required pane be emptied instead of refusing its close button. |
| `zoomedLeaf` | pane or none | none | Root-only: the pane currently taking over the whole tab, if any. |

## Deep Linking

Not applicable: this component composes a tab's panes in-process, with no
URL scheme, route, or deep-link handler anywhere in source.

## Localization

Not applicable: this file defines and displays no user-facing string
literals of its own; every string a user sees inside a tab belongs to the
panes this component hosts (a separate component's concern).

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation or
  transition; every arrangement change (applying preferred thicknesses,
  zoom's collapsed flags, minimize's pinning) is set directly and takes
  effect immediately.
- **Increase Contrast**: Not applicable — the only custom color usage in this
  source is the divider fill using the theme's pane-backdrop color, with no
  independent Increase Contrast handling of its own; that concern belongs to
  the palette/theme system, not to this component.
- **Differentiate Without Color**: Not applicable — this component conveys no
  state (zoomed, minimized, collapsed) through color at all; those states
  are conveyed by which panes are visible and how much space each occupies,
  which is unaffected by this accessibility setting.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source; the tree always lays out and mutates once constructed.

## Analytics

Not applicable: source contains no analytics or telemetry call anywhere in
this file; the layout-change callback, the last-pane-close callback, and the
layout-changed notification are structural hooks for the hosting app, not
telemetry events.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  tree of node ids, view identifiers, and sizing fractions describing *how*
  panes are arranged — never the content displayed inside a pane.
- **Storage**: In-memory only, for the life of the tree (its children,
  thickness fractions, zoomed leaf, and related state). Whether and how a
  snapshot handed to the layout-change callback is written to disk is
  entirely the host's responsibility and outside this file's source.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the component's own lifetime; state is
  discarded when the tab/tree is torn down.

## Logging

Not applicable: source contains no logging call anywhere in this component.

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
  minimize, a zoom that collapses `NSSplitViewItem`s). It also does not
  support construction via a coder-based initializer — Cocoa's
  `NSCoder`-driven `init(coder:)` — which this type overrides to trigger a
  fatal error immediately, since no code path in this app constructs a split
  node from an archived storyboard/xib. The requirements and
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewController.swift` |

## Design Decisions

- **Decision**: One-shot `hasAppliedPreferredThicknesses` guard, reset
  explicitly by every mutation that changes the arrangement (split, remove,
  rebuild, `applySizes`) rather than on every `layoutChildren` assignment.
  **Rationale (AppKit)**: Per the `viewDidLayout` doc comment, "after the first real
  layout the user owns the dividers, and re-imposing a fraction on every
  layout pass would fight them"; resetting only where the arrangement actually
  changes keeps a plain window resize from re-snapping dividers back to their
  preferred fractions.
  **Approved**: pending
- **Decision**: `captureThicknessFractions()` refuses to run over a zoomed
  tree, and skips a whole split (not just its pinned item) when any item in it
  shows a rail.
  **Rationale (AppKit)**: Per the method's own doc comment, a zoom or a rail is "an
  arrangement of the screen rather than a decision about sizes," and reading
  either back would silently corrupt the persisted layout — a saved layout
  while zoomed would "restore unzoomed and wrong," and a captured rail
  fraction would make a dragged 200pt pane "reopen at its floor" after a
  relaunch.
  **Approved**: pending
- **Decision**: Thickness persistence is debounced 300ms and deduplicated by a
  rounded signature, rather than writing on every `splitViewDidResizeSubviews`.
  **Rationale (AppKit)**: A drag posts a resize notification per pointer event and a
  window resize posts one per frame; per the method's doc comment, writing on
  each "would put the database in the middle of a gesture," and the signature
  check drops writes "that changed nothing" — a resize that ends where it
  began costs no write.
  **Approved**: pending
- **Decision**: `restoreSizing(of:)` clears `maximumThickness` before it
  lowers `minimumThickness`/`holdingPriority`, rather than the reverse order.
  **Rationale (AppKit)**: Per the method's doc comment, raising the minimum first would
  briefly ask the platform to satisfy a minimum at or above the still-pinned
  maximum — a pair the platform "cannot satisfy, logs, and recovers from by
  breaking one of them." Lifting the ceiling first keeps every intermediate
  state satisfiable.
  **Approved**: pending
- **Decision**: A non-root split with one remaining child collapses itself out
  of the tree instead of being left in place holding a single child.
  **Rationale (AppKit)**: Per `remove(_:)`'s doc comment, "a non-root split left with
  one child is a degenerate split" that should collapse into its parent; the
  *root* is allowed to hold a single child, because that legitimately
  represents "a tab reduced to one full-size pane."
  **Approved**: pending
- **Decision**: `zoomedLeaf` and `onLastPaneCloseRequest` are stored on the
  root and read through `rootSplit()`, never on an intermediate split.
  **Rationale (AppKit)**: Per their doc comments, a zoom "is a fact about the tab
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
source for resizing a divider (see the open question on non-pointer-resize
in Accessibility) — arrow-key pane *movement* is a real
feature, but it is dispatched from elsewhere (out of this source) into
`move(_:_:)`, not implemented here. Screen-reader-support is failed because
no accessibility role, label, or announcement is set anywhere in this source;
the divider, split view, and zoom/minimize transitions rely entirely on
AppKit's unmodified defaults — a zoom, minimize, split, remove, or move
changes what's on screen with no accessibility notification posted (see
**Announce state changes** in Accessibility). No other
category's checks apply: this is a pointer/keyboard-driven macOS desktop
control, not a touch surface, drawing no user-facing text and performing no
networking, telemetry, or logging of its own.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `ComposableTabsViewController.swift` and `ComposableTabsPaneHost.swift`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restated private-symbol requirements/vectors in observable terms; split a garbled move requirement into three and promoted two implicit edge cases to named requirements with vectors; added missing opposite-branch test vectors; fixed an untestable vector; resolved the conflicting SwiftUI platform note; renamed a non-kebab-case requirement; reformatted Design Decisions; fixed the Compliance table's invalid statuses and undefined checks; renumbered a broken test-vector ID sequence; trimmed tags to 5; populated `related`. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-24 | Mike Fullerton | Renamed `may-supply-custom-arranger` to the subject-only `custom-arranger`. |
| 1.1.3 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/. |
