---
id: d1257c76-fb28-47a5-bc2b-d4fb1ef87b53
title: Multi-Edge Tabbed View
domain: agentictoolkit://cookbook/ui/layout/tabbed-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An IDE-style view hosting up to four independently toggleable edge-docked
  tab bars sharing one shared content area, with at most one tab active at a time.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- view-controller
- layout
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# Multi-Edge Tabbed View

## Overview

The multi-edge tabbed view hosts up to four edge-docked tab bars — top, right, bottom, left — around a single shared content area, IDE-style. Each enabled edge owns its own tab list; edges can be shown or hidden independently and a hidden edge keeps its tabs so re-enabling it restores them. At most one tab is active across the whole view at any time, and that tab's own content fills the center; a designated main content, if set, fills the center instead while no tab is active. A tab's group id ties it to its siblings on other edges — one thing the user thinks of as "a tab" can have a member on each edge, and selecting any member selects all of them; a tab given no explicit group is its own group of one. Tab bar rendering, per-tab click/close handling, and vertical-edge card stacking are implemented by the tab bar and tab button roles in the same directory and are described here as part of this component, since neither has a recipe of its own.

## Behavioral Requirements

- **top-edge-enabled-by-default**: The view MUST initialize with the top
  edge enabled and the right, bottom, and left edges disabled.
- **edge-toggle-updates-bar-visibility**: Once loaded, the view MUST update
  that edge's bar visibility to match its enabled state and rebuild the edge
  layout whenever an edge's enabled state is changed, and MUST do nothing (no
  state change, no layout rebuild) when the requested state already matches
  the edge's current state.
- **hidden-edge-retains-tabs**: The view MUST NOT discard a disabled edge's
  tab list; its tabs MUST still be reported for that edge and MUST reappear
  in that edge's bar once the edge is re-enabled.
- **edge-state-change-triggers-fallback-activation**: The view MUST run
  fallback activation when disabling the edge currently holding the active
  tab, and MUST also run it when enabling an edge while no tab is currently
  active.
- **disabled-edge-excluded-from-layout**: The view MUST pin the shared
  content area directly to the view's own edge, rather than to a hidden bar,
  for every disabled edge, and MUST leave a disabled edge's bar with no
  layout constraints connecting it to the content area.
- **bar-spans-content-perpendicular-dimension**: The view MUST constrain a
  top/bottom bar's leading and trailing edges to the content area's leading
  and trailing edges, and a left/right bar's top and bottom edges to the
  content area's top and bottom edges, so each bar spans the full width or
  height of what it frames.
- **add-tab-appends-to-edge**: Adding a tab MUST insert it at the end of the
  specified edge's tab list.
- **insert-tab-clamps-index**: Inserting a tab at a given index MUST clamp
  the requested index into the range from `0` to the edge's current tab
  count, rather than trapping or ignoring an out-of-range value.
- **remove-tab-locates-owning-edge**: Removing a tab by id MUST locate the
  edge that owns the given id itself (the caller does not name an edge) and
  remove the tab from that edge's list.
- **move-tab-clamps-index-within-edge**: Moving a tab to a given index MUST
  clamp the requested index into the range from `0` to one less than the
  edge's tab count, and MUST reorder the tab only within the edge given,
  never across edges.
- **move-tab-no-op-when-index-unchanged**: Moving a tab MUST leave the tab
  list unchanged and MUST NOT invoke the reorder notification when the
  clamped target index equals the tab's current index.
- **rename-tab-title-items-only**: Renaming a tab MUST update the displayed
  text of a tab whose item is a title, and MUST have no effect at all on a
  tab whose item hosts content.
- **set-tab-item-preserves-mounted-content**: Replacing a tab's item MUST
  replace only what the tab shows in its bar; it MUST NOT alter, remount, or
  otherwise disturb that tab's own content in the center area.
- **single-active-tab-invariant**: The view MUST have at most one active tab
  across the entire view, spanning all four edges, at any time.
- **tab-defaults-to-own-group**: Creating a tab MUST default its group id to
  its own id when no explicit group id is supplied.
- **group-siblings-share-selection-across-edges**: The view MUST show every
  tab that shares the active tab's group id as selected on its own edge's
  bar, even though only one of them is the tab whose content the center
  shows.
- **ungrouped-tab-shows-no-selection-on-other-edges**: The view MUST show no
  selection on an edge whose tabs include no member of the active tab's
  group.
- **first-tab-on-enabled-edge-auto-activates**: Inserting a tab MUST
  activate it when there is currently no active tab and the target edge is
  enabled.
- **active-tab-removal-neighbor**: Removing a tab MUST activate the tab left
  at the removed tab's clamped index on the same edge when the removed tab
  was active and tabs remain on that edge.
- **removing-last-tab-on-edge-triggers-fallback**: Removing a tab MUST run
  fallback activation when removing the active tab leaves its edge with no
  tabs left.
- **fallback-prefers-active-group**: Fallback activation MUST prefer a tab,
  on any enabled edge, that shares the previously active tab's group id,
  over the first tab of the first enabled edge.
- **fallback-clears-when-nothing-found**: Fallback activation MUST set the
  active tab to none when no enabled edge has any tab at all.
- **active-tab-change-notification**: The view MUST notify its delegate of
  the active-tab change with an empty id and edge, rather than skipping the
  notification, whenever the active tab is cleared.
- **select-tab-refuses-non-member-id**: Selecting a tab by id on a given
  edge MUST have no effect when the given id is not a member of that edge's
  own tab list (it MUST NOT search other edges).
- **center-shows-active-tab-content**: The view MUST mount the active tab's
  content as the sole child filling the shared content area.
- **center-falls-back-to-main-content**: The view MUST mount the designated
  main content in the shared content area whenever no tab is active, and
  MUST leave the area unmounted when both the active tab and the main
  content are absent.
- **center-mount-skips-redundant-remount**: The view MUST NOT tear down and
  remount the currently mounted content when refreshing center content
  resolves to the content already mounted (identity match).
- **content-insets-applied-to-mounted-view**: The view MUST offset the
  mounted content from the shared content area's edges by the four insets
  configured via content insets (top, leading, bottom, trailing).
- **center-outline-reflects-color-override-or-fallback**: The view MUST
  draw a `1pt` border around the shared content area using the configured
  outline-color override when it is set, and the theme's `outline` role when
  it is not.
- **preferred-content-size-change-refreshes-every-bar**: Whenever any hosted
  content reports a changed preferred size, every edge's bar — not only the
  bar hosting the changed content — MUST reflect its own hosted items'
  current preferred size in its thickness.
- **tab-bar-orientation-follows-edge**: A tab bar MUST lay out a top or
  bottom bar's items in a horizontal row and a left or right bar's items in
  a vertical column.
- **tab-bar-thickness-floor-and-growth**: A tab bar MUST size its thickness
  to at least `28pt` for a top/bottom bar or `140pt` for a left/right bar,
  and MUST grow it to the largest hosted item's preferred size on that axis
  plus `6pt` whenever that sum exceeds the floor.
- **tab-item-padding-flush-to-content-side**: A tab bar MUST apply `6pt` of
  padding between an item and the bar's outer (window) side, and MUST leave
  the content (workspace) side of the bar flush against its items with no
  padding.
- **tab-button-selection-style**: A tab button MUST fill a selected tab's
  background with the `selection` palette role and leave an unselected
  tab's background transparent, and MUST switch its label between the
  `selectionText` and `secondaryText` roles, and its close icon's tint
  between `selectionText` and `tertiaryText`, to match.
- **hosted-item-highlight-follows-selection**: The view MUST set a
  content-hosting tab's highlighted state to match the selection state,
  whenever the hosted item supports highlight reporting.
- **close-icon-hit-region**: A tab button MUST select the tab when a
  pointer-down lands outside the close button's frame, and MUST route a
  pointer-down inside the close button's frame to the close action instead
  of selecting.
- **clicking-hosted-item-selects-its-tab**: The hosted-item wrapper MUST
  select its tab when any point inside the hosted content is clicked,
  without preventing an interior control (such as the hosted item's own
  close control) from handling its own click first.
- **vertical-edge-cards-overlap-and-order-by-distance**: On a left or right
  edge, a tab bar MUST lay out content-hosting items with a `-16pt` overlap
  and MUST order them, back to front, by each item's distance (in index
  positions) from the currently selected item, so an item nearer the
  selection draws and is hit-tested above one farther away. (This ordering
  and the `-16pt` overlap spacing itself only apply to content-hosting
  items — see the Design Decisions entry on title-only tabs on a vertical
  edge.)
- **cross-edge-move-preserves-foreign-content**: When reconciling a bar's
  items, a tab bar MUST leave a hosted content's parent and mounted view
  untouched if that content's view has already been reparented onto a
  different bar's wrapper (a cross-edge move in progress), rather than
  tearing it down because its id is no longer present in this bar's own
  items.
- **new-tab-hook-delegates-without-mutating**: Requesting a new tab MUST
  forward to the delegate's new-tab-needed notification and MUST NOT itself
  add, remove, or otherwise mutate any tab.
- **explicit-group-override**: A caller MAY supply an explicit group id when
  creating a tab, differing from its own id, to tie multiple tab instances
  (typically one per edge) together as siblings of one logical tab.

## Appearance

- **Corner radius**: `4pt` on each tab button's background pill.
- **Padding**: Inside a tab button: `10pt` leading from the background to
  the title label, `4pt` top/bottom between the label and the background,
  `6pt` between the label and the close button, `6pt` from the close button
  to the background's trailing edge, and the background itself is inset
  `2pt` from the button's own top/bottom. Inside a tab bar: `6pt` between an
  item and the bar's outer (window) side only — the content (workspace)
  side is flush; `8pt` at each end of the bar along its length, overridable
  per edge; `4pt` between items on a horizontal bar, or `-16pt` (a negative
  gap) between items on a vertical bar.
- **Font**: The `caption` text role (size and weight resolved by the active
  theme's typography, not a fixed point size) for a tab button's title
  label.
- **Background**: A tab bar fills with the `windowBackground` palette
  role. The shared content area fills with the configured background-color
  override when set, or the `windowBackground` role when not. A tab
  button's background is the `selection` role when selected, or transparent
  when not.
- **Foreground/Text**: A tab button's title label uses the `selectionText`
  role when selected or `secondaryText` when not; its close icon tints
  `selectionText` when selected or `tertiaryText` when not.
- **Border**: The shared content area draws a `1pt` border in the
  configured outline-color override when set, or the theme's `outline` role
  when not. No tab button or bar itself draws a border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  this concept.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or
  `140pt` (left/right), and grows to the largest hosted item's preferred
  size on that axis plus `6pt` when that is larger. The close button's hit
  area is a fixed `14×14pt`; its glyph (a circular X) renders at `10pt`,
  regular weight.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected tab) | Tab button background transparent; label role `secondaryText`; close icon tint `tertiaryText`. |
| Selected (active tab / group) | Tab button background fills with `selection`; label role `selectionText`; close icon tint `selectionText`; its selected-state indicator reports `true`; a content-hosting item's highlighted state is set `true`. |
| Stacked (vertical edge, content-hosting items only) | An item recedes visually behind items nearer the selection: its stack depth (index distance from the selected item) is reported to any hosted item that supports it, and its `-16pt`-overlapping card is drawn and hit-tested beneath nearer items. Title-only items receive the overlap spacing but not the depth reordering — see Design Decisions. |
| Edge hidden | The edge's bar is hidden and dropped from the edge layout entirely; its tabs are preserved but not drawn. |
| Pressed | Not applicable: a click resolves directly to selection or to the close action in the same pointer-down handling; there is no separate, visually distinct pressed appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar has a disabled appearance; a tab that exists is always selectable, and an edge that is off is hidden entirely rather than shown disabled. |
| Focused | Not applicable: the tab button and hosted-item wrapper have no keyboard-focus-ring appearance defined (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every tab operation (add, remove, move, rename, select) is synchronous; this concept defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: A tab button exposes itself as a button-role accessibility
  element and suppresses its subviews from being separately exposed, so it
  reads as one control rather than several. The view's own container and the
  shared content area expose no accessibility role — not applicable, they
  are plain layout containers, not controls.
- **Label requirements**: A title-only tab exposes its title text as its
  accessibility title; its close button carries its own identifier
  (`tab-bar.close.<uuid>`, distinct per tab since several bars can be on
  screen at once) and description ("Close Tab"), and is the sole element
  republished as that tab's accessible child once the tab becomes its own
  accessibility element. A content-hosting tab's own accessible content is
  entirely the hosted content's concern — this component only forwards a
  highlighted state and a close notification when the hosted content opts
  in.
- **Announce state changes**: A tab button's highlighted-state change
  updates that button's own accessibility value, so a click-driven selection
  is reflected on the pressed element itself, but no accessibility
  notification is posted anywhere in this concept when the active tab
  changes programmatically — a fallback activation after removing a tab,
  toggling an edge, or the sibling-selection update across an edge's other
  tabs. A screen-reader user tracking a different element is not told the
  active tab changed when no click of their own caused it.
- **Keyboard / assistive-technology navigation**: The tab button and
  hosted-item wrapper are plain view types with no keyboard-focus
  acceptance, key-handling, or key-view-loop wiring; a tab is reachable only
  by a pointer click or an existing assistive-technology cursor's activation
  gesture. There is no way for a keyboard-only or switch-access user to move
  focus onto a tab and activate it without a pointer or assistive cursor
  already positioned there.
- **Minimum tap target**: The close button's hit area is a fixed `14×14pt`;
  the tab body (background, label, close button) is larger than that and is
  clickable everywhere outside the close button's own frame. This is a
  pointer-driven desktop concept; the `44×44pt` (phone) / `48×48dp`
  (Android) touch-target minimums do not apply directly here and instead
  inform the touch-platform translations in Platform Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| multi-tabbed-001 | top-edge-enabled-by-default | Construct a new view | The top edge is enabled; the right, bottom, and left edges are disabled |
| multi-tabbed-002 | edge-toggle-updates-bar-visibility | View loaded; enable the bottom edge | The bottom edge's tab bar becomes visible (no longer hidden) in the view hierarchy; the edge layout is rebuilt |
| multi-tabbed-003 | hidden-edge-retains-tabs | Add a tab on the bottom edge; disable the bottom edge; re-enable it | The bottom edge's tabs are unchanged throughout, and its button reappears once re-enabled |
| multi-tabbed-004 | edge-state-change-triggers-fallback-activation | Active tab lives on the top edge; disable the top edge | Fallback activation runs; the active tab changes (to another tab or none) |
| multi-tabbed-005 | disabled-edge-excluded-from-layout | The left edge is disabled | The content area's leading edge is pinned directly to the view's own leading edge, not to the left bar (which is hidden and unconstrained) |
| multi-tabbed-006 | bar-spans-content-perpendicular-dimension | The top edge is enabled | The top bar spans the full width of the content area: its leading and trailing edges align with the content area's leading and trailing edges |
| multi-tabbed-007 | add-tab-appends-to-edge | Edge already has 2 tabs; add a new tab to it | The new tab is now last in that edge's tab list |
| multi-tabbed-008 | insert-tab-clamps-index | Edge has 2 tabs; insert a tab at index 99 | The tab is inserted at index `2` (the end), not out of bounds |
| multi-tabbed-009 | remove-tab-locates-owning-edge | Tab lives on the right edge; remove it by id with no edge argument | The right edge's tabs no longer contain it |
| multi-tabbed-010 | move-tab-clamps-index-within-edge | Edge has 3 tabs; move the first tab to index 50 | The tab moves to index `2` (the last valid index) |
| multi-tabbed-011 | move-tab-no-op-when-index-unchanged | Tab already at index `1`; move it to index `1` | The tab list order is unchanged; the reorder notification is not invoked |
| multi-tabbed-012 | rename-tab-title-items-only | Rename a content-hosting tab | The tab's displayed title is unchanged |
| multi-tabbed-013 | set-tab-item-preserves-mounted-content | Replace the active tab's item | The tab's content (and, if it is the active tab, the mounted center content) is unchanged |
| multi-tabbed-014 | single-active-tab-invariant | Tabs exist on 2 enabled edges with unrelated groups; select a tab on the top edge, then select a different (ungrouped) tab on the left edge | After the second selection, the active tab names only the left edge's tab; the top bar shows no tab as selected |
| multi-tabbed-015 | tab-defaults-to-own-group | Create a tab with no group id | The tab's group id equals its own id |
| multi-tabbed-016 | group-siblings-share-selection-across-edges | Top and bottom tabs share a group id; select the bottom one | The top bar shows its own member of the group as selected, even though the bottom tab is the one whose content is shown |
| multi-tabbed-017 | ungrouped-tab-shows-no-selection-on-other-edges | The top tab has no shared group with any bottom tab; select the top tab | The bottom bar shows no tab as selected |
| multi-tabbed-018 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; add a tab to it | The added tab becomes active |
| multi-tabbed-019 | active-tab-removal-neighbor | Active tab at index 1 of 3 on its edge is removed | The tab now at index 1 (the old index 2) becomes active |
| multi-tabbed-020 | removing-last-tab-on-edge-triggers-fallback | Active tab is the only tab on its edge; remove it | Fallback activation runs |
| multi-tabbed-021 | fallback-prefers-active-group | Active tab's group has a sibling on another enabled edge; a tab unrelated to the group sits first on the first enabled edge | Fallback activates the group sibling, not the unrelated first tab |
| multi-tabbed-022 | fallback-clears-when-nothing-found | No enabled edge has any tab; fallback runs | The active tab is now none |
| multi-tabbed-023 | active-tab-change-notification | The last tab on the last enabled edge is removed | The delegate is notified of an active-tab change with no tab and no edge |
| multi-tabbed-024 | select-tab-refuses-non-member-id | Select an id that is not in the given edge's tabs | The active tab is unchanged |
| multi-tabbed-025 | center-shows-active-tab-content | A tab is activated | The shared content area mounts the active tab's content as its sole child view |
| multi-tabbed-026 | center-falls-back-to-main-content | No tab active; a main content is designated | The shared content area mounts that main content's view |
| multi-tabbed-027 | center-mount-skips-redundant-remount | Center content is refreshed twice in a row with the same resolved target | The mounted content's view is not removed and re-added on the second call |
| multi-tabbed-028 | content-insets-applied-to-mounted-view | Content insets set to `4` on every side | The mounted content sits 4pt in from the content area's top and leading edges, and 4pt in from its bottom and trailing edges (inset inward) |
| multi-tabbed-029 | center-outline-reflects-color-override-or-fallback | No outline-color override set | The content area's visible border renders in the theme's `outline` color |
| multi-tabbed-030 | preferred-content-size-change-refreshes-every-bar | Hosted content on the left edge changes its preferred size and reports the change | Every edge's bar — not only the left edge's — recalculates its thickness to reflect its own hosted items' current preferred size |
| multi-tabbed-031 | tab-bar-orientation-follows-edge | A right-edge tab bar is built | The right bar lays out its items down a vertical column, not across a row |
| multi-tabbed-032 | tab-bar-thickness-floor-and-growth | The left bar hosts an item with a preferred width of `200` | The left bar's thickness (frame width) grows to `206pt` (200 + 6pt padding), above its `140pt` floor |
| multi-tabbed-033 | tab-item-padding-flush-to-content-side | A top bar is built | The top bar's first item sits `6pt` from the bar's outer (top) edge; on the workspace-facing (bottom) edge, items sit flush with a `0pt` gap |
| multi-tabbed-034 | tab-button-selection-style | A tab button is set highlighted | The selected tab's background fills with the `selection` palette color, and its title text switches to the `selectionText` role |
| multi-tabbed-035 | hosted-item-highlight-follows-selection | A content-hosting tab that supports highlight reporting is selected | Its highlighted state reads `true` |
| multi-tabbed-036 | close-icon-hit-region | A pointer-down lands inside the close button's frame | The close action fires, closing that tab; the click does not also select the tab |
| multi-tabbed-037 | clicking-hosted-item-selects-its-tab | A real pointer-down is hit-tested onto a hosted item's interior label | The hosted tab becomes selected |
| multi-tabbed-038 | vertical-edge-cards-overlap-and-order-by-distance | The left bar has 3 hosted items; the middle one is selected | The middle item's neighbors are drawn and hit-tested behind it: it visually overlaps and receives clicks over both neighbors |
| multi-tabbed-039 | cross-edge-move-preserves-foreign-content | A hosted content is moved from the left bar to the right bar (insert-then-remove); the left bar reconciles afterward | The content's parent and mounted view are unaffected by the left bar's reconciliation |
| multi-tabbed-040 | new-tab-hook-delegates-without-mutating | Request a new tab with a delegate installed | The delegate's new-tab-needed notification is invoked; no tab is added by this call itself |
| multi-tabbed-041 | explicit-group-override | Create two tab instances with the same explicit group id, one per edge; select one | The other tab, sharing the same group id, is also shown as selected on its own edge's bar |
| multi-tabbed-042 | Null/empty input (Edge Cases) | Query the tabs for an edge with no tabs ever added | Returns an empty list, without trapping |
| multi-tabbed-043 | Error states (Edge Cases) | Set a delegate, then let it deallocate (no strong reference remains); remove the last tab on an edge | The tab is removed from that edge's tabs (the mutation completes); no crash occurs even though the delegate reference is now empty |
| multi-tabbed-044 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; insert a tab at index 0 directly (not the append operation) | The inserted tab becomes active |

## Edge Cases

- Null/empty input (MUST): Querying an edge's tabs MUST return an empty list
  for an edge with no tabs, never trap. Querying the selected tab or its id
  MUST return none when the active tab (if any) is not a member of the given
  edge. With both the main content and the active tab absent, the shared
  content area MUST be left with no mounted content at all rather than
  showing a blank placeholder.
- Boundary values (MUST): Inserting a tab's index clamp and moving a tab's
  index clamp MUST both handle an index below `0` or past the end of the
  list the same way as one already in range — neither traps nor silently
  ignores the call.
- Concurrent access: Not applicable — the view, its per-edge tab storage,
  and its tab bars are all confined to a single thread; every mutating
  entry point (adding, removing, moving, or selecting a tab, toggling an
  edge, and the internal sync/activation logic) runs on that same thread, so
  this concept provides no path for two threads to mutate one instance at
  the same time.
- Error states (MUST): Looking up the edge for an unknown tab id returning
  none MUST make removing, renaming, or replacing a tab's item silent
  no-ops rather than trap. Selecting a tab MUST be silently ignored when the
  id is not a member of the given edge's own list — it does not search other
  edges for it. The delegate reference is held weakly; a deallocated
  delegate MUST make every delegate notification a no-op without preventing
  the underlying tab mutation from completing.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind; it manages an in-memory set of tab bars and
  mounts caller-supplied content.
- Reusing one content instance across two tabs: unguarded caller
  precondition. Nothing in adding or inserting a tab refuses or dedupes a
  tab whose content is already parented elsewhere or already mounted as
  another tab's content; callers MUST supply distinct content per tab, and
  the platform's own content-containment mechanism is the only thing that
  reacts to a violation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `delegate` | Delegate reference (optional, held weakly) | None | Receives tab lifecycle callbacks: new-tab request, select, active-tab change, close request, reorder. |
| `mainContentViewController` | Content reference (optional) | None | Shown in the shared content area while no tab is active. |
| `contentInsets` | Insets (top/left/bottom/right, points) | All zero | Gap held between the mounted content and the tab bars/edges around it. |
| `centerBackgroundColor` | Color (optional) | None | Overrides the shared content area's fill; unset falls back to the `windowBackground` role. |
| `centerOutlineColor` | Color (optional) | None | Overrides the shared content area's `1pt` border color; unset falls back to the palette's `outline` role. |
| Tab start inset | Number (points) per edge | `8` | Where a bar's first tab begins, measured along the bar from its start. |
| Edge enabled state | Boolean per edge | `true` for the top edge; `false` for the right/bottom/left edges | Whether an edge's tab bar and tabs are shown at all. |

## Deep Linking

Not applicable: this concept defines no URL scheme, system activity-handoff,
route, or deep-link handler anywhere; tabs are added and removed only by
direct, in-process calls from the host.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | A tab button's close icon's accessibility description |

"Close Tab" is a hardcoded English literal set directly as an accessibility
description, not routed through any localization mechanism used in this
concept — it is the one non-data-driven, user/assistive-technology-facing
string this component itself owns (a tab's own title text is always supplied
by the caller, so it carries no localization concern of this component's
making).

## Accessibility Options

- **Reduce Motion**: Not applicable — this concept defines no animation or
  transition anywhere; every appearance change (selection restyle, thickness
  change, layout rebuild) applies immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`selection`, `selectionText`, `secondaryText`, `tertiaryText`,
  `windowBackground`, `outline`) is a semantic palette role; increased-
  contrast handling, if any, belongs entirely to the theme/palette system
  this component defers to, not to this concept.
- **Differentiate Without Color**: The tab button distinguishes selected
  from unselected purely by fill color (`selection` vs. transparent) and a
  text-role swap (`selectionText` vs. `secondaryText`); no border, icon,
  weight, or other non-color cue accompanies the change. A content-hosting
  item on a vertical edge gets a color-independent stacking/overlap cue from
  its stack depth, but a title-only tab never gets one, on any edge.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
this concept; every edge, once enabled by the host, and every tab, once
added, behaves identically regardless of any external flag.

## Analytics

Not applicable: this concept contains no analytics or telemetry call
anywhere; the delegate callbacks are structural notifications for the host,
not telemetry events.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  list of tab ids, group ids, display titles, and content references
  describing *how* tabs are arranged — never content the host chooses to
  display inside hosted content.
- **Storage**: In-memory only, for the life of the view. Nothing in this
  concept persists tab state to disk; any such persistence is entirely the
  host's own responsibility, outside this component.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this concept.
- **Retention**: None beyond the view's own lifetime; all tab and edge state
  is discarded when the view is deallocated.

## Logging

Not applicable: this concept contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: Model each edge's tab list as an `@State`/`@Observable` array
  keyed by a stable id, and the active tab as a single shared id (or a
  `groupID`, to reproduce cross-edge sibling selection). Render each enabled
  edge's bar as an `HStack`/`VStack` (chosen by `Edge.isVertical`) of pill
  buttons inside a `ScrollView`, each with a `.background` capsule that swaps
  fill/foreground on selection the way `TabButton.updateAppearance()` does,
  and a trailing close `Button`. Compose the four bars and the center content
  with nested `VStack`/`HStack`s mirroring `rebuildEdgeConstraints()`'s
  top/bottom-row, left/right-column arrangement, hiding a disabled edge's bar
  with `if isEdgeEnabled(edge) { ... }` rather than an `isHidden` flag. There
  is no first-class SwiftUI analog for the vertical-edge card overlap/z-order
  behavior; reproduce it with `.offset`/`.zIndex` driven by each item's index
  distance from the selection.
- **Compose**: Mirror the same per-edge tab list and shared active-id/group-id
  state in a `ViewModel`. Render a horizontal edge with a `Row` of
  `FilterChip`/custom `Surface` pills inside a horizontally-scrolling
  container, and a vertical edge with a `Column` of the same, using
  `Modifier.offset`/`graphicsLayer { translationY = ... }` and `zIndex()` keyed
  on each item's distance from the selected index to reproduce the `-16pt`
  overlap and depth ordering. Compose a `Scaffold`-style frame with `Row`/
  `Column` slots for the up-to-four bars around the content, showing or hiding
  a bar's Composable entirely (not just visually) to mirror `isHidden`.
- **React/Web**: Represent each edge's tabs as an array in component state,
  keyed by id, with a shared `activeGroupId`. Render a top/bottom edge as a
  `<div>` with `display: flex; flex-direction: row` and a left/right edge with
  `flex-direction: column`, each tab a `<button>` styled with the selected/
  unselected background and text-color swap; a `position: relative` wrapper
  with negative `margin` (mirroring the `-16pt` overlap) and `z-index`
  computed from index-distance-from-selection reproduces the vertical card
  stack. Compose the up-to-four bars and the center `<div>` with CSS Grid
  (`grid-template-areas` for top/left/center/right/bottom), toggling a bar's
  `display: none` to mirror `isHidden`.
- **AppKit / UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/`
  across `MultiTabbedViewController.swift` (edge/tab/selection state, layout,
  center mounting), `TabBarView.swift` (bar rendering, `TabButton`,
  `TabItemHostView`, card stacking), `TabItem.swift` (`TabItem`,
  `TabBarHostedItem`, `TabBarStackedItem`), `Edge.swift`, and
  `MultiTabbedViewControllerDelegate.swift`. This is a macOS-only, AppKit
  `NSViewController` component with no UIKit code path in source.
  `loadView()`, `viewDidLoad()`, and `preferredContentSizeDidChange(for:)`
  are declared `open` so a subclass can extend them (`open-for-subclassing`,
  folded in here because it is purely a Swift subclassing detail, not a
  behavior of the concept itself). `MultiTabbedViewController`, `Tab`'s
  storage (`EdgeState`), and `TabBarView` are all `@MainActor`-isolated,
  which is what backs the single-thread confinement described under Edge
  Cases. `contentInsets` is an `NSEdgeInsets` applied as layout-constraint
  constants, with the trailing and bottom insets given as negative constants
  (inward) and the top and leading insets as positive constants. `TabButton`
  sets `accessibilityRole = .button` and `setAccessibilityElement(true)`,
  which stops AppKit from hoisting its subviews into the tree in its place;
  nothing in `MultiTabbedViewController.swift` or `TabBarView.swift` posts an
  `NSAccessibility.post(element:notification:)` call for a programmatic
  active-tab change, and neither `TabButton` nor `TabItemHostView` implements
  `acceptsFirstResponder`/`keyDown`/key-view-loop wiring, so a tab is
  reachable only by a pointer click or an existing VoiceOver cursor's
  `accessibilityPerformPress()`. The close icon is the `xmark.circle.fill` SF
  Symbol. Padding constants are named `TabBarView.outerPadding` (6pt),
  `endPadding` (8pt), `itemSpacing` (4pt), and `cardOverlap` (-16pt); the tab
  button's corner radius is `backgroundView.layer?.cornerRadius` and the
  content area's border is `centerContainer.layer?.borderWidth`. Reusing one
  view controller across two tabs is not guarded by `addTab`/`insertTab`;
  AppKit's own view-controller containment is the only thing that reacts to a
  violation. A UIKit/iPadOS port has no direct analog to four independently
  toggleable, sibling-linked edge bars around one content area; it would most
  likely be a hand-built container using `UIStackView`s for each edge
  (mirroring this file's own `NSStackView`-per-edge structure) and a custom
  container view controller for the center, rather than `UITabBarController`,
  which supports only one bottom bar and no cross-edge group selection.
  Internally (private, not part of the conformance contract above — cited
  here rather than in the test vectors): `tabBars: [Edge: TabBarView]` holds
  each edge's bar view; `centerContainer` is the shared content wrapper and
  `mountedCenterController` tracks the controller currently mounted in it;
  each bar keeps its thickness in `thicknessConstraint` and lays items out in
  an `NSStackView` (`stack`) whose `edgeInsets` hold the per-side padding;
  `TabButton` draws selection through `backgroundView.layer` and a
  `titleLabel` role swap.
- **WinUI 3**: There is no single WinUI 3
  control that docks tab bars on all four sides with cross-edge sibling
  selection, so build the frame as a `Grid` with `Auto`-sized
  `RowDefinition`s/`ColumnDefinition`s for the top/bottom/left/right bar slots
  around a `Star`-sized center `ContentPresenter`, collapsing a disabled
  edge's row/column to `0` (`Visibility="Collapsed"` on that bar) to mirror
  `isHidden`/`rebuildEdgeConstraints()`. WinUI 3's native `TabView` only
  supports a single top-docked strip and has no notion of a tab linked across
  several instances, so represent each edge's bar as a `ListView` (or
  `ItemsRepeater`) of `ToggleButton`-based pill items inside a horizontal or
  vertical `StackPanel`/`ItemsStackPanel` (chosen by `Edge.isVertical`),
  driving each item's checked visual state with a `VisualStateManager`
  `Selected`/`Unselected` state group that swaps `Background`/`Foreground`
  brushes the way `TabButton.updateAppearance()` swaps palette roles. Persist
  a `groupID`-style key alongside each `ListView`'s items and, on any one
  edge's `SelectionChanged`, programmatically set the matching item selected
  on every other edge's `ListView` to reproduce
  `group-siblings-share-selection-across-edges`. Bind each bar's
  `MinWidth`/`MinHeight` (top/bottom vs. left/right) to the hosted content's
  measured `DesiredSize` plus `6epx`, clamped to the `28epx`/`140epx` floor, to
  mirror `tab-bar-thickness-floor-and-growth`. Reproduce the vertical-edge
  card overlap with a negative `Margin` on each item plus `Canvas.ZIndex` set
  from each item's index-distance from the selected one, mirroring
  `applyStackOrder()`; a close glyph can use the Segoe Fluent Icons
  `` ("Cancel") glyph sized to match the `14×14pt` hit area.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/MultiTabbedViewController.swift` |

## Design Decisions

**Decision**: A tab's `groupID` defaults to its own `id` rather than requiring
every caller to supply one.
**Rationale**: Per `Tab.init`'s doc comment, this "makes a tab its own group of
one — the behaviour every host had before groups existed," so a caller with
only one edge needs no change to keep working. (AppKit/UIKit.)
**Approved**: pending

**Decision**: `activateFallbackTab()` looks for a same-group sibling on any
enabled edge before falling back to the first tab of the first enabled edge.
**Rationale**: Per the method's doc comment, turning an edge off "is a decision
about where tabs are drawn," and jumping instead to an unrelated tab on the
first enabled edge "dropped [the user] onto an unrelated checkout" — the
group-first fallback keeps the user's actual selection stable across edge
visibility changes. (AppKit/UIKit.)
**Approved**: pending

**Decision**: `contentInsets` is applied by `MultiTabbedViewController` around
the mounted content, rather than left to the content itself.
**Rationale**: Per the property's doc comment, the tab bars "have to stay flush
against the window," so the gap belongs between the bars and what they
frame, and "this controller is the only thing that owns both." (AppKit/UIKit.)
**Approved**: pending

**Decision**: `activeTabDidChange` fires on every activation — including
transitions to `nil` — while `didSelectTab` fires only for a user-driven
pick (a click, or the neighbor/fallback a close hands the user).
**Rationale**: Per the delegate's doc comments, a host that only needs "which
pane is in front now" should not have to separately filter fallback and
clearing transitions out of genuine user picks; the two callbacks
deliberately separate "what changed" from "the user chose this." (AppKit/UIKit.)
**Approved**: pending

**Decision**: `TabBarView.rebuildButtons()`'s reconciliation tears down a hosted
controller only if that controller's view still sits in *this* bar's own
wrapper.
**Rationale**: Per the method's doc comment, a cross-edge move reparents the
controller's view onto the new bar's wrapper before the old bar notices the
id is gone from its own items; tearing it down there too "would rip the
view out of the new bar's display." (AppKit/UIKit.)
**Approved**: pending

**Decision** (documented quirk, not a deliberate design choice): the
front-to-back z-reordering and `stackDepth` reporting in
`TabBarView.applyStackOrder()` only cover `.viewController` items (via
`hostViews`/`hostedControllers`). A `.title` `TabButton` on a vertical
(`.left`/`.right`) edge still receives the same `-16pt` overlapping
`stack.spacing` as hosted items, but is never reordered by distance from the
selected item — its z-order, and therefore which overlapping title tab
draws and hit-tests on top, is left at whatever order
`NSStackView.addArrangedSubview` produced (list order), regardless of which
tab is selected.
**Rationale**: `hostViews`/`hostedControllers` are populated only for
`.viewController` items, so `applyStackOrder()`'s reordering loops have
nothing to reorder for title tabs; nothing in source suggests this was a
deliberate choice for the title-tab case rather than an oversight. Recorded
here, per source fidelity, rather than smoothed over. (AppKit/UIKit.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | failed | Accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

Keyboard-navigable is failed because `TabButton`/`TabItemHostView` have no
key-view-loop or `keyDown` wiring (see Accessibility).
Screen-reader-support is partial: it holds for `.title` tabs, where
`TabButton` sets a real accessibility role, title, value, and a republished
close-button child, but no accessibility notification is posted for a
programmatic active-tab change — a fallback activation, or the sibling-selection
update across an edge's other tabs (see Accessibility). String-externalization
is failed because the close button's "Close Tab" accessibility description is
a hardcoded English literal (see Localization). `@MainActor` confinement, the
single-active-tab invariant, and the color-only selection cue are true of the
source (see Behavioral Requirements and Accessibility Options) but are not
compliance-catalog checks, so they are not listed here.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: at-most-one-active-tab summary/overview wording, observable (not private-internal) conformance test vector assertions, corrected edge-toggle-updates-bar-visibility and preferred-content-size-change-refreshes-every-bar wording, added Change History initial row, cleaned up and re-scoped Compliance to catalog checks, subject-only requirement renames, bold-form Design Decisions, AppKit / UIKit and WinUI 3 Platform Notes fixes, insertTab API-name correction, expanded and corrected conformance test vector coverage; states controller reuse across tabs as an unguarded caller precondition. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/. |
