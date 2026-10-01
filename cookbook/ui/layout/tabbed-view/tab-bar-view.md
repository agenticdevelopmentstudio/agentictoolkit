---
id: 5c0cc9f5-bc89-4e06-8d24-3db6424ff075
title: Tab Bar View
domain: agentictoolkit://cookbook/ui/layout/tabbed-view/tab-bar-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Edge-docked pill tab bar for the multi-edge tabbed view, with selection
  restyling and vertical card stacking.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
depends-on: []
related:
- agentictoolkit://cookbook/ui/layout/tabbed-view
references: []
approved-by: ''
approved-date: ''
---

# Tab Bar View

## Overview

The tab bar renders the edge-aligned tab strip for the multi-edge tabbed
view: one pill-style button per tab, laid out in a row for a top/bottom bar
or a column for a left/right bar, following the bar's own edge. It owns no
selection or ordering policy of its own — its items and selected id are
handed to it by its owner, and it reports user intent back to its owner
purely through three callbacks (select, close, reorder) so it stays
decoupled from the tabbed view's own public interface. Two helper roles live
alongside it and are described here because neither has a recipe of its own
within this file's scope: a hosted-item wrapper, which wraps a
content-hosting item's view so a click anywhere on it selects the tab, and a
tab button, the pill control that renders a title item with its own close
icon.

## Behavioral Requirements

- **thickness-floor-by-edge**: The bar's preferred thickness MUST be `28pt`
  for a top/bottom bar and `140pt` for a left/right bar. These are fixed
  constants with no stated rationale beyond a sensible default; a port
  SHOULD treat them as theme-tunable rather than hardcoding them verbatim.
- **orientation-follows-edge**: The bar MUST lay out its arranged content
  horizontally for a top/bottom bar and vertically for a left/right bar.
- **alignment-favors-workspace-side**: The bar MUST align its arranged
  content to the side of the bar adjacent to the workspace/content area it
  frames: the bottom for a top bar, the top for a bottom bar, the trailing
  edge for a left bar, and the leading edge for a right bar.
- **item-spacing-by-orientation**: The bar MUST set the gap between arranged
  items to `4pt` when it is horizontal and to `-16pt` (a negative gap) when
  it is vertical; the vertical overlap makes the column read as a deck being
  turned rather than a list, while a horizontal bar has room along its
  length and does not need it.
- **start-inset-defaults-to-end-padding**: The bar's start inset MUST
  default to `8pt` and MUST re-apply the bar's edge insets whenever it is
  changed.
- **host-may-override-start-inset**: A host MAY set the start inset to a
  value other than the default, to line a bar's first item up with chrome
  outside the bar; the bar itself has no opinion on what that chrome is.
- **outer-padding-on-window-side-only**: The bar MUST apply `6pt` of inset
  on its outer (window) side and `0pt` on its workspace side, with the start
  inset applied at the bar's start (along its length) and `8pt` at its end.
- **bar-fills-perpendicular-and-pins-length**: For a top/bottom bar, the bar
  MUST pin its arranged content's top, leading, trailing, and bottom edges to
  its own corresponding edges and hold a fixed height matching its
  thickness; for a left/right bar, MUST pin its arranged content's top,
  leading, and trailing edges to its own, hold a fixed width matching its
  thickness, and constrain its arranged content's bottom edge to be no
  farther down than its own bottom (not pinned exactly).
- **vertical-bar-packs-from-top**: On a left/right bar, unused column height
  below the arranged content MUST remain empty rather than stretching the
  arranged items, as a direct consequence of the inequality-only bottom
  constraint described in **bar-fills-perpendicular-and-pins-length**.
- **bar-fills-window-background**: The bar MUST paint its own background
  with the `windowBackground` palette role and MUST repaint it whenever the
  resolved theme palette changes.
- **set-items-triggers-rebuild**: Setting the bar's items MUST store the
  given items and selected id and MUST rebuild the bar's arranged content to
  match them.
- **set-selected-restyles-and-reorders**: Setting the selected tab MUST
  update the bar's selected id, MUST set the highlighted state to `true` on
  exactly the tab button and any hosted content that supports highlight
  reporting whose id equals the new selection, and to `false` on every
  other one, and MUST update every hosted item's reported stack depth and,
  on a vertical bar, its front-to-back order to match (see
  **stack-depth-by-distance-from-selection** and
  **vertical-edge-cards-overlap-and-order-by-distance**).
- **stack-depth-by-distance-from-selection**: A selection change MUST
  compute each item's depth as the absolute difference between its index
  and the selected item's index, or `1` for every item when nothing is
  selected, and MUST report that depth to any hosted content that supports
  stack-depth reporting.
- **vertical-edge-cards-overlap-and-order-by-distance**: On a left/right
  bar, a selection change MUST reorder each content-hosting item's wrapper
  view, deepest-first, so the item nearest the selection ends up frontmost
  in both z-order and hit-testing; ties in depth MUST be broken by
  descending index.
- **rename-title-item**: Renaming an item by id MUST set the matching
  item's payload to a title item with the new text and MUST update that
  id's tab button title when an item with the given id exists, and MUST be
  a silent no-op when no item has that id.
- **rebuild-clears-and-repopulates**: Setting new items MUST discard every
  previously rendered item's view and any per-item state associated with
  the old items before repopulating the bar from the new list.
- **cross-edge-move-preserves-foreign-content**: When reconciling hosted
  content, the bar MUST remove a superseded item's view from its superview
  and remove its parent relationship only when that view is still sitting
  in a wrapper this bar itself created; it MUST leave the view and parent
  relationship untouched when the view has already been reparented onto a
  different bar.
- **rebuild-drops-stale-hosted-content**: Setting new items MUST stop
  tracking a content-hosting item's hosted content whenever that id's
  current payload differs by identity from the previously hosted content
  (including when the id is no longer present in the new items at all),
  independent of whether **cross-edge-move-preserves-foreign-content** also
  tore down its view.
- **title-item-becomes-button**: For each title item, the bar MUST create a
  tab button, set its highlighted state to match the selected id, wire its
  select/close actions to the bar's own select/close callbacks, add it as
  an arranged item, and MUST additionally pin its cross-axis edges only
  when the bar's orientation is vertical.
- **content-item-becomes-hosted-view**: For each content-hosting item, the
  bar MUST add the content as a child of its host content when it is not
  already its parent, set its highlighted state and close action on it when
  it supports those hooks, wrap its view in a hosted-item wrapper wired to
  the bar's select callback, add that wrapper as an arranged item, and MUST
  pin the wrapper's cross-axis edges unconditionally (regardless of the
  bar's orientation).
- **thickness-grows-with-hosted-content**: The bar MUST set its thickness to
  the greater of its preferred thickness floor and (the largest hosted
  item's preferred size on the bar's thickness axis, plus `6pt`), and MUST
  recompute it whenever its items change.
- **host-view-fills-hosted-content**: The hosted-item wrapper MUST pin its
  wrapped content view's top, leading, trailing, and bottom edges to its own
  corresponding edges.
- **host-view-click-selects**: The hosted-item wrapper MUST select its tab
  for a click that lands on the wrapper itself, without intercepting a
  click an interior subview (such as a hosted item's own close control)
  already handles as the frontmost hit-tested view.
- **close-icon-hit-routes-to-close**: A tab button MUST route a pointer-down
  that lands within the close icon's own bounds to that icon's own native
  handling, and MUST NOT also select the tab in that case; it MUST select
  the tab for a pointer-down anywhere else in the view.
- **accessibility-press-always-selects**: An assistive-technology press on a
  tab button MUST always select the tab and report success, regardless of
  where the press targets the element — unlike a physical click, it never
  routes to the close action.
- **tab-button-is-accessible-element**: Creating a tab button MUST expose it
  as a single accessibility element with a button role, and MUST set its
  initial accessibility title and value from the given title text and
  highlighted state.
- **tab-button-title-updates-accessibility**: Setting a tab button's title
  MUST update both the visible title text and its accessibility title to
  the new value.
- **tab-button-highlight-updates-accessibility-value**: Setting a tab
  button's highlighted state MUST update its accessibility value to the new
  value and MUST restyle the button to match (see
  **selecting-a-tab-restyles-its-button**).
- **close-button-republished-as-sole-child**: A tab button's reported
  accessibility children MUST be exactly its close button, so the close
  control stays reachable in the accessibility tree once the tab button
  becomes a single accessibility element.
- **close-button-carries-per-tab-identifier**: Creating a tab button MUST
  give its close button the accessibility identifier `tab-bar.close.<id>`
  and MUST give the tab button itself `tab-bar.select.<id>`, both keyed by
  the tab's own id.
- **selecting-a-tab-restyles-its-button**: Selecting a tab MUST fill its
  background with the `selection` palette role, set its title's color role
  to `selectionText`, and set its close icon's tint to `selectionText` when
  highlighted; it MUST use transparent, `secondaryText`, and `tertiaryText`
  respectively when not highlighted.
- **declares-reorder-callback**: The bar MUST expose a reorder notification,
  in addition to its select and close notifications, for a caller to
  observe tab reordering.

- **onreorder-never-fires**: NEEDS REVIEW: Not implemented. The bar
  declares a reorder notification and documents it as firing "after the
  user finishes dragging a tab to a new index," and the tabbed view wires
  that notification straight to its own delegate callback — but nothing in
  the bar itself ever invokes it; there is no drag-and-drop or
  keyboard-driven reordering mechanism anywhere in this concept, and an
  item list's only path to a new order is a caller directly setting new
  items, which does not go through the reorder notification at all. What is
  missing: the interaction — a pointer drag or a keyboard equivalent — that
  determines a target index and invokes the reorder notification. What
  would settle it: an implementation of a drag interaction, or confirmation
  that reordering is a future, not-yet-built feature and the notification
  exists ahead of it.

## Appearance

- **Corner radius**: `4pt` on a tab button's background pill. The bar and
  hosted-item wrapper set no corner radius of their own.
- **Padding**: Inside a tab button: `10pt` from the background's leading
  edge to the title label; `4pt` between the title label and the
  background's top/bottom; `6pt` between the title label and the close
  button; `6pt` from the close button to the background's trailing edge;
  the background itself is inset `2pt` from the button's own top and
  bottom. Inside the bar: `6pt` between an item and the bar's outer
  (window) side only — the workspace side is flush; `8pt` at each end of
  the bar along its length, overridable per instance via the start inset;
  `4pt` between items on a horizontal bar, or `-16pt` (a negative gap) on a
  vertical bar.
- **Font**: The `caption` text role for a tab button's title label —
  resolved size and weight come from the active theme's typography, not a
  fixed point size; the role does not change with selection, only the
  label's color role does (see Foreground/Text).
- **Background**: The bar fills with the `windowBackground` palette role. A
  tab button's background fills with the `selection` role when highlighted
  and is transparent otherwise. The hosted-item wrapper draws no background
  of its own.
- **Foreground/Text**: A tab button's title color role is `selectionText`
  when highlighted, `secondaryText` otherwise; its close icon's tint
  follows the same pair (`selectionText` / `tertiaryText`). Both roles are
  resolved by the theme's palette system, outside this component's own
  concern.
- **Border**: Not drawn — no border width, color, or bezel style other than
  the close button's own borderless-icon-button style appears anywhere in
  this concept.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  this concept.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or
  `140pt` (left/right), growing to the largest hosted item's preferred size
  on that axis plus `6pt` when that sum is larger
  (**thickness-grows-with-hosted-content**). A tab button has no explicit
  width/height constraint of its own; its size is whatever its content and
  fixed insets produce. The close button's hit area is a fixed `14×14pt`;
  its glyph (a circular X) renders at `10pt`, regular weight.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected) | Tab button background transparent; label role `secondaryText`; close icon tint `tertiaryText`. |
| Selected | Tab button background fills with `selection`; label role `selectionText`; close icon tint `selectionText`; the accessibility value reports `true`; a hosted item that supports highlight reporting has its highlighted state set `true`. |
| Stacked (vertical bar, content-hosting items only) | An item recedes behind items nearer the selection: its stack depth (index distance from the selected item) is reported to any hosted item that supports it, and its `-16pt`-overlapping wrapper view is drawn and hit-tested beneath nearer items (see the Edge Cases entry on title tabs not being depth-reordered). |
| Pressed | Not applicable: a pointer-down resolves directly to selection or to the close action inside the same pointer-down handling; there is no separate, visually distinct pressed appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar exposes a disabled appearance; any item present is always selectable. |
| Focused | Not applicable: the tab button and hosted-item wrapper are plain view types with no keyboard-focus or focus-ring appearance defined (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every operation (setting items, setting the selection, renaming, rebuilding, restacking, resizing) is synchronous; this concept defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: A tab button exposes itself as a single accessibility
  element with a button role, which stops its subviews from being
  separately exposed (**tab-button-is-accessible-element**). The
  hosted-item wrapper and the bar itself set no accessibility role of their
  own — they are plain layout/click-forwarding containers, not controls; a
  content-hosting item's own accessible content is entirely the hosted
  content's concern.
- **Label requirements**: A title tab exposes its title text via its
  accessibility title (**tab-button-title-updates-accessibility**); its
  close button carries its own identifier (`tab-bar.close.<uuid>`, distinct
  per tab since several bars can be on screen at once) and the description
  "Close Tab", and is the sole entry the tab button republishes as its
  accessibility children once it becomes its own element
  (**close-button-republished-as-sole-child**).
- **Announce state changes**: A tab button's highlighted-state change
  updates that button's own accessibility value on every change, whether it
  originates from a click or from a caller setting the selection
  (**tab-button-highlight-updates-accessibility-value**) — so, unlike a
  purely click-driven implementation, this concept's own value updates are
  consistent for both origins. No accessibility notification is posted
  anywhere in this concept when the active tab changes; a screen-reader
  user whose cursor is positioned elsewhere is not told that a different
  tab became selected — the update relies entirely on the moved focus
  element's own accessibility value being read if and when the cursor lands
  there.
- **Keyboard / assistive-technology navigation**: The tab button and
  hosted-item wrapper are plain view types with no keyboard-focus
  acceptance, key-handling, or key-view-loop wiring; a tab is reachable
  only by a pointer click or an existing assistive-technology cursor's
  activation gesture. The close button is a real button control and so
  remains independently reachable through the platform's own
  keyboard-navigation loop, meaning a keyboard-only user may be able to
  close a tab yet has no way at all to select one — there is no
  keyboard-only path to move focus onto a tab and activate it without a
  pointer or assistive cursor already positioned there.
- **Minimum tap target**: The close button's hit area is a fixed
  `14×14pt`; the rest of the tab button (background, label) is clickable
  everywhere outside that frame. This is a pointer-driven desktop concept;
  the `44×44pt` (phone) / `48×48dp` (Android) touch-target minimums do not
  apply directly here and instead inform the touch-platform translations in
  Platform Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-bar-view-001 | thickness-floor-by-edge | Query the bar's preferred thickness for the top edge, then for the left edge | Returns `28`; the left edge returns `140` |
| tab-bar-view-002 | orientation-follows-edge | A bar is built for the right edge | Its arranged content lays out vertically (top-to-bottom) |
| tab-bar-view-003 | alignment-favors-workspace-side | A bar is built for the top edge | Items align to the bar's bottom edge |
| tab-bar-view-004 | item-spacing-by-orientation | A bar is built for the left edge | The gap between adjacent items is `-16pt` (items overlap) |
| tab-bar-view-005 | start-inset-defaults-to-end-padding | A new bar is built | The start inset is `8`; the first item begins `8pt` from the bar's start |
| tab-bar-view-006 | host-may-override-start-inset | The start inset is set to `20` | The first item now begins `20pt` from the bar's start |
| tab-bar-view-007 | outer-padding-on-window-side-only | A bar is built for the bottom edge | Items sit `6pt` from the bar's outer (window) edge, flush (`0pt`) against the workspace edge, and `8pt` from each end along the bar's length |
| tab-bar-view-008 | bar-fills-perpendicular-and-pins-length | A bar is built for the top edge and laid out in a 300pt-wide container | The bar's arranged content spans the bar's own leading/trailing edges; the bar's height is `28` at rest |
| tab-bar-view-009 | vertical-bar-packs-from-top | A bar is built for the left edge with 2 short items in a tall container | The bar's arranged content is shorter than the bar's own height; the gap below is empty, not stretched |
| tab-bar-view-010 | bar-fills-window-background | The active theme changes from theme A to theme B | The bar's background updates to theme B's `windowBackground` color |
| tab-bar-view-011 | set-items-triggers-rebuild | Set the bar's items to a single item, selected | The bar renders exactly one item, matching the new item |
| tab-bar-view-012 | set-selected-restyles-and-reorders | Two title items; select the second one | The tab for the second item is highlighted; the tab for the first is not |
| tab-bar-view-013 | stack-depth-by-distance-from-selection | 3 content-hosting items at indices 0,1,2; select index 0 | Depths reported to the hosted items are `0, 1, 2` |
| tab-bar-view-014 | stack-depth-by-distance-from-selection | Same 3 items; nothing selected | Every item's reported depth is `1` |
| tab-bar-view-015 | vertical-edge-cards-overlap-and-order-by-distance | A left-edge bar, 3 hosted items, the middle one selected | The middle item's wrapper view is above both neighbors (frontmost, topmost hit-tested) |
| tab-bar-view-016 | rename-title-item | Rename an existing title tab to "New" | The item's payload is a title item reading "New"; the tab button's displayed title reads "New" |
| tab-bar-view-017 | rename-title-item | Rename a tab using an id with no matching item | No crash; the items and rendered buttons are unchanged |
| tab-bar-view-018 | rebuild-clears-and-repopulates | Set items to [a, b], then set items to [c] | The bar renders exactly one item, c's; no rendered element for a or b remains |
| tab-bar-view-019 | cross-edge-move-preserves-foreign-content | A hosted item's view is reparented onto a different bar's wrapper, then this bar is given new items | The item's parent and view are unaffected by this bar's reconciliation |
| tab-bar-view-020 | rebuild-drops-stale-hosted-content | A content-hosting item is removed from the items and the bar re-renders | The removed item's content no longer receives highlight or stack-depth updates from the bar |
| tab-bar-view-021 | title-item-becomes-button | A title item on a left-edge bar | The created tab button has active constraints pinning its leading/trailing edges to the bar's interior |
| tab-bar-view-022 | title-item-becomes-button | A title item on a top-edge bar | The created tab button has no cross-axis pin installed by the bar (relies on the bar's own alignment) |
| tab-bar-view-023 | content-item-becomes-hosted-view | A content-hosting item on a top-edge bar | The wrapping hosted-item view has active top/bottom constraints pinning it to the bar's interior |
| tab-bar-view-024 | thickness-grows-with-hosted-content | A left-edge bar hosts an item with a preferred width of `200` | The bar's thickness (width) is `206` (`200 + 6`, above the `140` floor) |
| tab-bar-view-025 | thickness-grows-with-hosted-content | A left-edge bar with no hosted items | The bar's thickness (width) is `140` (the floor) |
| tab-bar-view-026 | host-view-fills-hosted-content | A hosted-item wrapper is constructed around a content view | The content view's top/leading/trailing/bottom equal the wrapper's own edges |
| tab-bar-view-027 | host-view-click-selects | A pointer-down lands inside the wrapper but outside any interior control | The tab is selected |
| tab-bar-view-028 | close-icon-hit-routes-to-close | A pointer-down lands inside the close button's frame | The close action fires; the tab is not also selected by this pointer-down |
| tab-bar-view-029 | close-icon-hit-routes-to-close | A pointer-down lands outside the close button's frame | The tab is selected; close is not triggered |
| tab-bar-view-030 | accessibility-press-always-selects | An assistive-technology press is performed while the assistive cursor is conceptually "over" the close child | The tab is selected (never the close action); the press reports success |
| tab-bar-view-031 | tab-button-is-accessible-element | A tab button is constructed with title "Notes", highlighted state left at its default (not highlighted) | It exposes itself as a single accessibility element with a button role; its accessibility title reads "Notes"; its accessibility value reads `false` |
| tab-bar-view-032 | tab-button-title-updates-accessibility | The tab button's title is set to "Renamed" | The visible title text reads "Renamed"; the accessibility title reads "Renamed" |
| tab-bar-view-033 | tab-button-highlight-updates-accessibility-value | The tab button's highlighted state is set to `true` | The accessibility value reads `true`; the tab restyles to its selected appearance (see vectors 036-037) |
| tab-bar-view-034 | close-button-republished-as-sole-child | The tab button's accessibility children are queried | Returns a list containing exactly the close button |
| tab-bar-view-035 | close-button-carries-per-tab-identifier | A tab button is constructed for a given id | The tab button's own accessibility identifier reads `tab-bar.select.<id>`; the close button's reads `tab-bar.close.<id>` |
| tab-bar-view-036 | selecting-a-tab-restyles-its-button | The tab button's highlighted state is set to `true` | The tab's background fills with the `selection` color; its title's color role becomes `selectionText`; its close icon's tint becomes `selectionText` |
| tab-bar-view-037 | selecting-a-tab-restyles-its-button | The tab button's highlighted state is set to `false` | The tab's background becomes transparent; its title's color role becomes `secondaryText`; its close icon's tint becomes `tertiaryText` |
| tab-bar-view-038 | declares-reorder-callback | A new bar is constructed | Its reorder notification is a settable, externally observable property |
| tab-bar-view-041 | vertical-edge-cards-overlap-and-order-by-distance | A left-edge bar, 3 hosted items at indices 0,1,2; index 1 selected | Between the tied depth-1 neighbors (indices 0 and 2), index 0's wrapper view ends up more frontmost than index 2's, per the descending-index tie-break; index 1 (depth 0, selected) is frontmost of all three |

## Edge Cases

- Null/empty input (MUST): Setting the bar's items to an empty list with no
  selection MUST leave the bar with no arranged subviews, and recomputing
  thickness MUST fall back to the bar's preferred thickness floor since no
  hosted content remains (see tab-bar-view-025). Renaming a tab using an id
  absent from the items MUST be a silent no-op (see tab-bar-view-017).
- Boundary values (MUST): A single-item bar MUST compute a stack depth of
  `0` for that item whether or not it is selected; the vertical-bar
  reordering pass still runs with only one view to raise, producing no
  visible reordering.
- Concurrent access: Not applicable — the bar and its constituent parts are
  all confined to a single thread (see Platform Notes), so this concept
  provides no path for two threads to mutate one instance at the same time.
- Error states: Not applicable — this concept makes no network, database,
  or file-system call. Its only fallible lookups resolve to silent no-ops
  or default values rather than throwing or trapping.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind.
- Unset host content (MUST): When no host content is set, a
  content-hosting item's parenting step is skipped entirely, so the hosted
  content never receives a parent — but its view is still wrapped in the
  hosted-item wrapper and added to the stack regardless, so the tab still
  renders and is still clickable; only parent-based lifecycle callbacks are
  missing.
- Renaming a content-hosting tab (documented quirk, not a deliberate design
  choice): Renaming an item performs no check on the existing item's
  payload type. Renaming an id whose current item hosts content overwrites
  that entry with a title item in the item list, while no button was ever
  created for a content-hosting item, so updating that (nonexistent)
  button's title is a no-op — the model now disagrees with what is rendered
  until the next rebuild. This concept's own documentation states this is
  safe only because the caller (the tabbed view's rename operation) already
  refuses to call it for a content-hosting item, so there is nothing left
  to guard against here; the invariant is enforced entirely by the caller,
  not by this component itself. This is recorded as technical debt rather
  than a supported code path.
- Title tabs on a vertical bar are not depth-reordered (documented quirk,
  not a deliberate design choice): a title tab on a left/right bar receives
  the same `-16pt` overlapping spacing as a hosted content item (see
  **item-spacing-by-orientation**), but
  **vertical-edge-cards-overlap-and-order-by-distance**'s front-to-back
  reordering only ever touches hosted content items — a title tab's
  z-order (and so which overlapping title tab draws and hit-tests on top)
  is whatever order it was originally added in, regardless of selection.
  Nothing suggests this was a deliberate choice for the title-tab case
  rather than an oversight; it is recorded here, per source fidelity,
  rather than smoothed over.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `edge` | Edge | (required, set at construction) | Which side of the container this bar is docked to; fixed for the bar's lifetime. |
| `startInset` | Number (points) | `8` | Where the first item begins, measured along the bar from its start. |
| `hostController` | Content reference (optional, held weakly) | None | Parent a content-hosting item's content is added to; unset means hosted content is never parented (see Edge Cases). |
| `onSelect` | Callback (tab id, optional) | None | Invoked when a tab is clicked, or when an assistive-technology press activates one. |
| `onClose` | Callback (tab id, optional) | None | Invoked when a tab's close control is activated. |
| `onReorder` | Callback (tab id and new index, optional) | None | Declared for a caller to observe reordering; never invoked by this concept itself (see the open question on onreorder-never-fires). |

## Deep Linking

Not applicable: this concept defines no URL scheme, system activity-handoff,
route, or deep-link handler anywhere; it is a rendering surface driven
entirely by direct, in-process calls from its owner.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | A tab button's close icon's accessibility description |

"Close Tab" is a hardcoded English literal set directly as an accessibility
description, not routed through any localization mechanism used in this
concept — it is the one non-data-driven, user/assistive-technology-facing
string this component owns (a tab's own title text is always supplied by
the caller, so it carries no localization concern of this component's
making). No translated string table entry exists for it.

## Accessibility Options

- **Reduce Motion**: Not applicable — this concept defines no animation or
  transition anywhere; every appearance change (selection restyle,
  thickness change, layout rebuild) applies immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`selection`, `selectionText`, `secondaryText`, `tertiaryText`,
  `windowBackground`) is a semantic palette role; increased-contrast
  handling, if any, belongs to the theme/palette system this component
  defers to, not to this concept itself.
- **Differentiate Without Color**: The tab button distinguishes selected
  from unselected purely by fill color (`selection` vs. transparent) and a
  text/icon color-role swap (`selectionText` vs.
  `secondaryText`/`tertiaryText`); the title label's text role (and
  therefore its font) never changes, so no weight, size, border, or icon
  accompanies the change, and this concept does not implement
  Differentiate Without Color support. A content-hosting item on a
  vertical bar gets a color-independent stacking/overlap cue from its
  stack depth, but a title tab never gets one, on any edge.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
this concept; every item, once added, renders and behaves identically
regardless of any external flag.

## Analytics

Not applicable: this concept contains no analytics or telemetry call
anywhere; the select/close/reorder notifications are structural
notifications for the owner, not telemetry events.

## Privacy

- **Data collected**: None by this component itself. It holds only the tab
  ids, titles, and content references it is given, describing how tabs are
  arranged — never content a hosted item chooses to display.
- **Storage**: In-memory only, for the life of the bar instance. Nothing in
  this concept persists tab state to disk.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this concept.
- **Retention**: None beyond the bar's own lifetime; all state is discarded
  when it is deallocated.

## Logging

Not applicable: this concept contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: Model the item list as an array of a lightweight identifiable
  struct plus an external `selectedID`, both owned by the caller (mirroring
  `items`/`selectedID` being handed in rather than owned). Render one edge's
  bar as an `HStack` (top/bottom) or `VStack` (left/right) of pill `Button`s,
  each with a `.background(RoundedRectangle(cornerRadius: 4).fill(...))` that
  swaps between the `.selection` and clear fills and a text-color swap between
  `.selectionText`/`.secondaryText`, matching `updateAppearance()`; overlay a
  trailing close `Button` sized `14×14` the way `closeButton` sits inside
  `backgroundView`, giving it its own tap target so a tap there does not also
  select (SwiftUI's default hit-testing already scopes a nested `Button`'s
  tap to itself, unlike the manual frame-containment check
  **close-icon-hit-routes-to-close** performs). There is no SwiftUI analog to
  `NSStackView.addSubview(_:positioned:relativeTo:)`; reproduce the
  vertical-edge overlap and depth ordering with `.offset`/`.zIndex` driven by
  each item's index distance from the selection, recomputed the way
  `applyStackOrder()` does.
- **Compose**: Keep the item list and `selectedId` in a `ViewModel`. Render a
  horizontal bar as a `Row` and a vertical bar as a `Column` of
  `Surface`/`FilterChip`-based pill composables, driving the same fill/text/
  icon-tint swap from `MaterialTheme`-derived colors; give each pill a
  trailing icon `IconButton` for close, sized to mirror the `14×14pt` hit
  area, and let Compose's own click-consumption on that inner control keep it
  from also triggering the pill's `Modifier.clickable` (no manual
  frame-containment test is needed, unlike the source's `mouseDown` check).
  Reproduce the `-16dp` vertical overlap and depth ordering with
  `Modifier.offset` and `zIndex()` computed from each item's index distance
  from the selected one.
- **React/Web**: Keep the tab array and `selectedId` in component state.
  Render a bar as a flex container (`flex-direction: row` for top/bottom,
  `column` for left/right), each tab a `<button>` toggling a selected/
  unselected class (background + text/icon color, matching
  `updateAppearance()`'s role swap) and containing a nested close `<button>`
  whose click handler calls `event.stopPropagation()` — the direct web analog
  of `TabButton.mouseDown`'s frame-containment check — so a close click never
  also selects. Reproduce the vertical overlap with a negative `margin-top`
  (mirroring `-16pt`) and a `z-index` computed from each item's index
  distance from the selected tab.
- **AppKit/UIKit** (source platform): Implemented entirely in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabBarView.swift`
  as three types: `TabBarView` (an `NSView` hosting an `NSStackView`), the
  private `TabItemHostView` (click-to-select wrapper for a `.viewController`
  item's view), and the private `TabButton` (the `.title` item's pill,
  including its own `NSButton`-based close icon). This is macOS/AppKit-only —
  there is no UIKit code path in source. `TabBarView`, `TabItemHostView`, and
  `TabButton` each fatal-error if constructed through `init?(coder:)`
  (`rejects-coder-initializer`), and all three are `@MainActor`-isolated,
  usable only on the main actor (`confines-to-main-actor`) — which is what
  backs the single-thread confinement described under Edge Cases. A
  UIKit/iPadOS port would replace `NSStackView` with `UIStackView`,
  `closeButton`'s `.inline` `NSButton` bezel with a plain `UIButton`
  (`.image(systemName: "xmark.circle.fill")`), and the `mouseDown`-based
  frame-containment hit test with a `UITapGestureRecognizer` on the wrapper
  plus the close button's own `.touchUpInside`, ordered (or
  `cancelsTouchesInView`-configured) so the close button's own target fires
  instead of the wrapper's when both would otherwise match. Internally,
  `TabBarView` tracks its items through a private `NSStackView`, per-id
  `TabButton`/`TabItemHostView` dictionaries, a hosted-controller map, and a
  thickness constraint; the Behavioral Requirements above describe the
  resulting observable behavior rather than these private names directly, so
  a refactor that keeps the behavior intact does not break conformance.
- **WinUI 3** (the reason this recipe exists): No built-in WinUI 3 control is
  shaped like this — `TabView` supports only a single top-docked strip, not
  a per-edge bar with vertical overlap. Build the bar as a `StackPanel`
  (`Orientation="Horizontal"` for top/bottom, `"Vertical"` for left/right)
  hosting an `ItemsRepeater` (or `ListView` with its `ItemsPanel` swapped to
  a `StackPanel`), one `ToggleButton`-templated pill per tab: a `Border` with
  `CornerRadius="4"` (mirroring `backgroundView.layer.cornerRadius`) around a
  `TextBlock` bound to the tab title (`FontSize`/`FontWeight` from the
  theme's caption-equivalent resource, mirroring the `.caption` text role)
  and a small close `Button` templated to the Segoe Fluent Icons "Cancel"
  glyph (``), sized to `14×14` `Width`/`Height` to mirror `closeButton`'s
  fixed hit area. Drive the selected/unselected swap with a
  `VisualStateManager` `Selected`/`Unselected` state group that swaps
  `Background`/`Foreground` brush resources — matching
  `.selection`/`.selectionText` vs. transparent/`.secondaryText` — rather
  than `ToggleButton`'s own default checked brush, so one brush pair serves
  every tab. Apply `outerPadding`/`endPadding` as `Margin` on the strip's
  outer (window) edge and at its two length-wise ends only, leaving the
  workspace-side edge flush (mirroring `applyEdgeInsets()`). Reproduce the
  vertical bar's card overlap and depth ordering with a negative `Margin`
  (`-16`) between items plus `Canvas.ZIndex` recomputed from each item's
  index distance from the selected one, the same calculation
  `applyStackOrder()` performs, since `ItemsRepeater`/`StackPanel` has no
  native reordering-on-selection behavior. There is no WinUI analog to
  `mouseDown`'s point-in-`closeButton`-frame test: set `e.Handled = true` in
  the close `Button`'s own `Click`/`PointerPressed` handler so the event never
  bubbles up to fire the pill's own selection `Click`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabBarView.swift` |

## Design Decisions

**Decision**: `startInset` defaults to `endPadding` (`8pt`) rather than `0`.
**Rationale**: Per the source's own doc comment, this is "where the first
item begins... `endPadding` unless a host says otherwise. A host whose
workspace has chrome of its own can line the first tab up with it, and the
bar stays ignorant of what it is lining up with" — the default keeps a bar
with no special host chrome visually consistent with its own trailing-end
inset. (AppKit/UIKit.)
**Approved**: pending

**Decision**: `TabButton`'s cross-axis pin (`pinCrossAxis(_:)`) is applied
only on a vertical bar, while a `.viewController` item's `TabItemHostView`
gets it unconditionally, on every edge.
**Rationale**: Per the source's own comments, a vertical bar's buttons "fill
the bar's interior width so labels and close buttons line up flush," while a
hosted item's content "reports no intrinsic size" on the cross axis and "has
to be told to fill the bar's interior" regardless of orientation, since only
its length along the stack's main axis is otherwise constrained (via
`preferredContentSize`). The asymmetry is a direct consequence of `TabButton`
having its own intrinsic cross-axis size (from its label and padding) on a
horizontal bar, and a hosted controller's view not having one on either axis.
(AppKit/UIKit.)
**Approved**: pending

**Decision**: `rebuildButtons()` tears down a superseded hosted controller's
view only when that view's current superview is still this bar's own
(now-stale) `TabItemHostView`.
**Rationale**: Per the method's own comment, a cross-edge move "reparents the
controller's view onto the new bar's wrapper before the old bar notices the
id is gone from its own items," so tearing it down unconditionally there too
"would rip the view out of the new bar's display and cut the controller's
`preferredContentSizeDidChange` routing." (AppKit/UIKit.)
**Approved**: pending

**Decision**: `TabButton.accessibilityPerformPress()` always selects the
tab, even though a physical click can instead route to the close action.
**Rationale**: The source's own comment reads "`AXPress` selects the tab, the
same call `mouseDown` makes — so a driven press and a click are the same
event as far as anything downstream knows." Assistive technology presses the
element as a whole (the tab), not a sub-region of it the way a pointer click
can land inside `closeButton`'s frame; the close control is reached
separately, as its own republished accessibility child. (AppKit/UIKit.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | failed | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

Screen-reader-support is partial: `.title` tabs get a real accessibility
role, title, value, and republished close-button child from `TabButton`, but
a `.viewController` tab's `TabItemHostView` exposes no role or label of its
own beyond whatever its hosted content provides. Keyboard-navigable is
failed because neither `TabButton` nor `TabItemHostView` has any
key-view-loop or `keyDown` wiring (see Accessibility). Dynamic-type-support
is partial because `TabButton`'s title uses a `.caption`-style role, but the
actual point-size scaling for that role is resolved by `ThemeTypography`
outside this file. Contrast-ratio is partial for the same reason: colors are
semantic palette tokens (`.selection`, `.selectionText`, `.secondaryText`,
`.tertiaryText`, `.windowBackground`) whose resolution and contrast are
defined entirely outside `TabBarView.swift`, in the theme/palette system it
defers to. String-externalization is failed because the close button's
"Close Tab" accessibility description is a hardcoded English literal (see
Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: state requirements and test vectors as observable behavior instead of private internals, rebuild the Compliance table to only the checks that apply with corrected statuses and categories, move documented quirks from Design Decisions to Edge Cases, correct the WinUI glyph and SwiftUI shape, sharpen test vector precision, add a stack-order tie-break vector, and shorten the summary. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/tabbed-view/. |
