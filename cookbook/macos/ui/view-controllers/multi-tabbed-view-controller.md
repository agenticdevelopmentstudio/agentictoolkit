---
id: d1257c76-fb28-47a5-bc2b-d4fb1ef87b53
title: MultiTabbedViewController
domain: agentictoolkit://cookbook/macos/ui/view-controllers/multi-tabbed-view-controller
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: IDE-style AppKit view controller with up to four independently toggleable
  edge-docked tab bars sharing one center content area; at most one tab is active
  at a time.
platforms:
- swift
- macos
tags:
- tabs
- tab-bar
- view-controller
- layout
- appkit
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

# MultiTabbedViewController

## Overview

`MultiTabbedViewController` is an `open`, `@MainActor` `NSViewController` that
hosts up to four edge-docked tab bars — top, right, bottom, left — around a
single shared content area, IDE-style. Each enabled edge owns its own tab
list; edges can be shown or hidden independently and a hidden edge keeps its
tabs so re-enabling it restores them. At most one tab is active across the
whole controller at any time, and that tab's own view controller fills the
center; `mainContentViewController`, if set, fills the center instead while no
tab is active. A `Tab`'s `groupID` ties it to its siblings on other edges — one
thing the user thinks of as "a tab" can have a member on each edge, and
selecting any member selects all of them; a tab given no explicit group is its
own group of one. Tab bar rendering, per-tab click/close handling, and
vertical-edge card stacking are implemented by the internal `TabBarView` and
`TabButton` types in the same directory and are described here as part of this
component, since neither has a recipe of its own.

## Behavioral Requirements

- **top-edge-enabled-by-default**: Component MUST initialize with the `.top`
  edge enabled and the `.right`, `.bottom`, and `.left` edges disabled.
- **edge-toggle-updates-bar-visibility**: When the view is loaded, Component
  MUST set that edge's bar's `isHidden` to `!enabled` and rebuild the edge
  constraints whenever `setEdgeEnabled(_:_:)` changes an edge's enabled state,
  and MUST do nothing (no state change, no constraint rebuild) when the
  requested state already matches the edge's current state.
- **hidden-edge-retains-tabs**: Component MUST NOT discard a disabled edge's
  tab list; its tabs MUST still be returned by `tabs(on:)` and MUST reappear in
  that edge's bar once the edge is re-enabled.
- **edge-state-change-triggers-fallback-activation**: Component MUST run
  fallback activation (`activateFallbackTab()`) when `setEdgeEnabled(_:_:)`
  disables the edge currently holding the active tab, and MUST also run it when
  enabling an edge while no tab is currently active.
- **disabled-edge-excluded-from-layout**: Component MUST pin the shared content
  area directly to the view's own edge, rather than to a hidden bar, for every
  disabled edge, and MUST leave a disabled edge's bar with no layout
  constraints connecting it to the content area.
- **bar-spans-content-perpendicular-dimension**: Component MUST constrain a
  top/bottom bar's leading and trailing edges to the content area's leading and
  trailing edges, and a left/right bar's top and bottom edges to the content
  area's top and bottom edges, so each bar spans the full width or height of
  what it frames.
- **add-tab-appends-to-edge**: `addTab(_:on:)` MUST insert the given tab at the
  end of the specified edge's tab list.
- **insert-tab-clamps-index**: `insertTab(_:at:on:)` MUST clamp a requested
  index into the range `0...tabs(on: edge).count` rather than trapping or
  ignoring an out-of-range value.
- **remove-tab-locates-owning-edge**: `removeTab(id:)` MUST locate the edge
  that owns the given tab id itself (the caller does not name an edge) and
  remove the tab from that edge's list.
- **move-tab-clamps-index-within-edge**: `moveTab(id:to:on:)` MUST clamp the
  requested index into the range `0...(tabs(on: edge).count - 1)` and MUST
  reorder the tab only within the edge given, never across edges.
- **move-tab-no-op-when-index-unchanged**: `moveTab(id:to:on:)` MUST leave the
  tab list unchanged and MUST NOT invoke the delegate's reorder callback when
  the clamped target index equals the tab's current index.
- **rename-tab-title-items-only**: `renameTab(id:title:)` MUST update the
  displayed text of a tab whose item is `.title`, and MUST have no effect at
  all on a tab whose item is `.viewController`.
- **set-tab-item-preserves-mounted-content**: `setTabItem(id:item:)` MUST
  replace only what the tab shows in its bar; it MUST NOT alter, remount, or
  otherwise disturb that tab's own content view controller in the center area.
- **single-active-tab-invariant**: Component MUST have at most one active tab
  (`activeTabID`) across the entire controller, spanning all four edges, at any
  time.
- **tab-defaults-to-own-group**: `Tab.init` MUST default a tab's `groupID` to
  its own `id` when no explicit `groupID` is supplied.
- **group-siblings-share-selection-across-edges**: Component MUST show every
  tab that shares the active tab's `groupID` as selected on its own edge's bar,
  even though only one of them is the tab whose content the center shows.
- **ungrouped-tab-shows-no-selection-on-other-edges**: Component MUST show no
  selection on an edge whose tabs include no member of the active tab's group.
- **first-tab-on-enabled-edge-auto-activates**: `insertTab(_:at:on:)` MUST
  activate the inserted tab when there is currently no active tab and the
  target edge is enabled.
- **active-tab-removal-neighbor**: `removeTab(id:)` MUST
  activate the tab left at the removed tab's clamped index on the same edge
  when the removed tab was active and tabs remain on that edge.
- **removing-last-tab-on-edge-triggers-fallback**: `removeTab(id:)` MUST run
  fallback activation when removing the active tab leaves its edge with no
  tabs left.
- **fallback-prefers-active-group**: `activateFallbackTab()` MUST prefer a tab,
  on any enabled edge, that shares the previously active tab's `groupID`, over
  the first tab of the first enabled edge.
- **fallback-clears-when-nothing-found**: `activateFallbackTab()` MUST set the
  active tab to `nil` when no enabled edge has any tab at all.
- **active-tab-change-notification**: Component MUST invoke
  `multiTabbedViewController(_:activeTabDidChange:on:)` with `nil` id and `nil`
  edge, rather than skipping the callback, whenever the active tab is cleared.
- **select-tab-refuses-non-member-id**: `selectTab(id:on:)` MUST have no effect
  when the given id is not a member of the specified edge's own tab list (it
  MUST NOT search other edges).
- **center-shows-active-tab-view-controller**: Component MUST mount the active
  tab's `viewController` as the sole child filling the shared content area.
- **center-falls-back-to-main-content**: Component MUST mount
  `mainContentViewController` in the shared content area whenever no tab is
  active, and MUST leave the area unmounted when both the active tab and
  `mainContentViewController` are absent.
- **center-mount-skips-redundant-remount**: Component MUST NOT tear down and
  remount the currently mounted controller when `refreshCenterContent()`
  resolves to the controller already mounted (identity match).
- **content-insets-applied-to-mounted-view**: Component MUST offset the
  mounted content view from the shared content area's edges by
  `contentInsets`, applying the trailing and bottom insets as negative
  constants (inward) and the top and leading insets as positive constants.
- **center-outline-reflects-color-override-or-fallback**: Component MUST draw
  a `1pt` border around the shared content area using `centerOutlineColor` when
  it is set, and the resolved theme palette's `.outline` role when it is `nil`.
- **preferred-content-size-change-refreshes-every-bar**: Whenever any hosted
  view controller reports a changed `preferredContentSize`, every edge's
  bar — not only the bar hosting the changed controller — MUST reflect its own
  hosted items' current preferred content size in its thickness.
- **tab-bar-orientation-follows-edge**: `TabBarView` MUST lay out a top or
  bottom bar's items in a horizontal row and a left or right bar's items in a
  vertical column.
- **tab-bar-thickness-floor-and-growth**: `TabBarView` MUST size a bar's
  thickness to at least `28pt` for a top/bottom bar or `140pt` for a left/right
  bar, and MUST grow it to the largest hosted item's `preferredContentSize` on
  that axis plus `6pt` whenever that sum exceeds the floor.
- **tab-item-padding-flush-to-content-side**: `TabBarView` MUST apply `6pt` of
  padding between an item and the bar's outer (window) side, and MUST leave
  the content (workspace) side of the bar flush against its items with no
  padding.
- **tab-button-selection-style**: `TabButton` MUST fill a selected
  tab's background with the `.selection` palette role and leave an unselected
  tab's background transparent, and MUST switch its label between the
  `.selectionText` and `.secondaryText` roles, and its close icon's tint
  between `.selectionText` and `.tertiaryText`, to match.
- **hosted-item-highlight-follows-selection**: Component MUST set a
  `.viewController` tab's `isHighlighted` to match the selection state,
  whenever the item conforms to `TabBarHostedItem`.
- **close-icon-hit-region**: `TabButton` MUST select the
  tab when a pointer-down lands outside the close button's frame, and MUST
  route a pointer-down inside the close button's frame to the close action
  instead of selecting.
- **clicking-hosted-item-selects-its-tab**: `TabItemHostView` MUST select its
  tab when any point inside the hosted content is clicked, without preventing
  an interior control (such as the hosted item's own close control) from
  handling its own click first.
- **vertical-edge-cards-overlap-and-order-by-distance**: On a left or right
  edge, `TabBarView` MUST lay out `.viewController` items with a `-16pt`
  overlap and MUST order them, back to front, by each item's distance (in
  index positions) from the currently selected item, so an item nearer the
  selection draws and is hit-tested above one farther away. (This ordering and
  the `-16pt` overlap spacing itself only apply to `.viewController` items —
  see the Design Decisions entry on `.title` tabs on a vertical edge.)
- **cross-edge-move-preserves-foreign-controller**: When reconciling a bar's
  items, `TabBarView` MUST leave a hosted view controller's parent and mounted
  view untouched if that controller's view has already been reparented onto a
  different bar's wrapper (a cross-edge move in progress), rather than tearing
  it down because its id is no longer present in this bar's own items.
- **new-tab-hook-delegates-without-mutating**: `newTab(_:)` MUST forward to
  `multiTabbedViewControllerNeedsNewTab(_:)` and MUST NOT itself add, remove,
  or otherwise mutate any tab.
- **explicit-group-override**: A caller MAY pass an explicit `groupID` to
  `Tab.init`, differing from `id`, to tie multiple `Tab` instances (typically
  one per edge) together as siblings of one logical tab.
- **open-for-subclassing**: Component MAY be subclassed; `loadView()`,
  `viewDidLoad()`, and `preferredContentSizeDidChange(for:)` are declared
  `open` so a subclass can extend them.

## Appearance

- **Corner radius**: `4pt` on each `TabButton`'s background pill
  (`backgroundView.layer?.cornerRadius`).
- **Padding**: Inside a `TabButton`: `10pt` leading from the background to the
  title label, `4pt` top/bottom between the label and the background, `6pt`
  between the label and the close button, `6pt` from the close button to the
  background's trailing edge, and the background itself is inset `2pt` from
  the button's own top/bottom. Inside `TabBarView`: `6pt` (`outerPadding`)
  between an item and the bar's outer (window) side only — the content
  (workspace) side is flush; `8pt` (`endPadding`) at each end of the bar along
  its length, overridable per edge via `setTabStartInset(_:for:)`; `4pt`
  (`itemSpacing`) between items on a horizontal bar, or `-16pt`
  (`cardOverlap`, a negative gap) between items on a vertical bar.
- **Font**: `.caption` text role (size and weight resolved by the active
  theme's typography, not a fixed point size in source) for a `TabButton`'s
  title label.
- **Background**: `TabBarView` fills with the `.windowBackground` palette
  role. The shared content area (`centerContainer`) fills with
  `centerBackgroundColor` when set, or the `.windowBackground` role when
  `nil`. A `TabButton`'s background is the `.selection` role when selected,
  or transparent (`NSColor.clear`) when not.
- **Foreground/Text**: A `TabButton`'s title label uses the `.selectionText`
  role when selected or `.secondaryText` when not; its close icon tints
  `.selectionText` when selected or `.tertiaryText` when not.
- **Border**: The shared content area draws a `1pt` border
  (`centerContainer.layer?.borderWidth`) in `centerOutlineColor` when set, or
  the resolved palette's `.outline` role when `nil`. No `TabButton` or bar
  itself draws a border.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  source.
- **Min/Max size**: A bar's thickness floor is `28pt` (top/bottom) or `140pt`
  (left/right), and grows to the largest hosted item's `preferredContentSize`
  on that axis plus `6pt` when that is larger. The close button's hit area is
  a fixed `14×14pt`; its glyph (`xmark.circle.fill`) renders at `10pt`,
  `.regular` weight.

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected tab) | `TabButton` background transparent; label role `.secondaryText`; close icon tint `.tertiaryText`. |
| Selected (active tab / group) | `TabButton` background fills with `.selection`; label role `.selectionText`; close icon tint `.selectionText`; `accessibilityValue` reports `true`; a `.viewController` item's `isHighlighted` is set `true`. |
| Stacked (vertical edge, `.viewController` items only) | An item recedes visually behind items nearer the selection: its `stackDepth` (index distance from the selected item) is reported to any hosted `TabBarStackedItem`, and its `-16pt`-overlapping card is drawn and hit-tested beneath nearer items. `.title` items receive the overlap spacing but not the depth reordering — see Design Decisions. |
| Edge hidden | The edge's bar is set `isHidden = true` and dropped from the edge layout constraints entirely; its tabs are preserved but not drawn. |
| Pressed | Not applicable: a click resolves directly to selection or to the close action in the same `mouseDown` handler; there is no separate, visually distinct pressed/mouse-down appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar has a disabled appearance in source; a tab that exists is always selectable, and an edge that is off is hidden entirely rather than shown disabled. |
| Focused | Not applicable: `TabButton` and `TabItemHostView` are plain `NSView` subclasses with no first-responder/focus-ring appearance defined in source (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every tab operation (add, remove, move, rename, select) is synchronous; source defines no loading/pending indicator. |

## Accessibility

- **Role/trait**: `TabButton` sets `accessibilityRole = .button` and
  `setAccessibilityElement(true)`, which stops AppKit from hoisting its
  subviews into the tree in its place (`TabButton.init`, `TabBarView.swift`).
  The controller's own view and `centerContainer` set no accessibility role —
  not applicable, they are plain layout containers, not controls.
- **Label requirements**: A `.title` tab exposes its title text via
  `setAccessibilityTitle(title)`; its close button carries its own identifier
  (`tab-bar.close.<uuid>`, distinct per tab since several bars can be on
  screen at once) and description ("Close Tab"), and is the sole entry
  `TabButton.accessibilityChildren()` republishes once the tab becomes its own
  element. A `.viewController` tab's own accessible content is entirely the
  hosted controller's concern — this component only forwards `isHighlighted`
  and `onClose` through `TabBarHostedItem` when the controller opts in.
- **Announce state changes**: `TabButton.isHighlighted`'s `didSet` updates
  that button's own `accessibilityValue`, so a click-driven selection is
  reflected on the pressed element itself, but nothing in
  `MultiTabbedViewController.swift` or `TabBarView.swift` posts an
  `NSAccessibility.post(element:notification:)` (or any other accessibility
  notification) when the active tab changes programmatically — a fallback
  activation after `removeTab`, `setEdgeEnabled`, or the sibling-selection
  update in `setSelected(_:)` across an edge's other tabs. A VoiceOver user
  tracking a different element is not told the active tab changed when no
  click of their own caused it.
- **Keyboard / assistive-technology navigation**: `TabButton` and
  `TabItemHostView` (`TabBarView.swift`) are plain `NSView` subclasses with no
  `acceptsFirstResponder`, `keyDown`, or key-view-loop wiring; a tab is
  reachable only by a pointer click (`mouseDown`) or an existing VoiceOver
  cursor's `accessibilityPerformPress()`. There is no way for a keyboard-only
  or Full Keyboard Access user to move focus onto a tab and activate it
  without a pointer or VoiceOver already positioned there.
- **Minimum tap target**: The close button's hit area is a fixed `14×14pt`
  (`TabButton.init`); the tab body (background, label, close button) is
  larger than that and is clickable everywhere outside the close button's own
  frame. macOS is a pointer-driven desktop platform; the `44×44pt` (iOS) /
  `48×48dp` (Android) touch-target minimums do not apply directly to this
  source and instead inform the touch-platform translations in Platform
  Notes.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| multi-tabbed-001 | top-edge-enabled-by-default | Construct a new `MultiTabbedViewController` | `isEdgeEnabled(.top) == true`; `isEdgeEnabled(.right/.bottom/.left) == false` |
| multi-tabbed-002 | edge-toggle-updates-bar-visibility | View loaded; call `setEdgeEnabled(.bottom, true)` | The bottom edge's tab bar becomes visible (no longer hidden) in the view hierarchy; the edge layout constraints are rebuilt |
| multi-tabbed-003 | hidden-edge-retains-tabs | Add a tab on `.bottom`; disable `.bottom`; re-enable `.bottom` | `tabs(on: .bottom)` returns the same tab throughout, and its button reappears once re-enabled |
| multi-tabbed-004 | edge-state-change-triggers-fallback-activation | Active tab lives on `.top`; call `setEdgeEnabled(.top, false)` | Fallback activation runs; `activeTabID` changes (to another tab or `nil`) |
| multi-tabbed-005 | disabled-edge-excluded-from-layout | `.left` disabled | The content area's leading edge is pinned directly to the view's own leading edge, not to the left bar (which is hidden and unconstrained) |
| multi-tabbed-006 | bar-spans-content-perpendicular-dimension | `.top` enabled | The top bar spans the full width of the content area: its leading and trailing edges align with the content area's leading and trailing edges |
| multi-tabbed-007 | add-tab-appends-to-edge | Edge already has 2 tabs; call `addTab(newTab, on: edge)` | `tabs(on: edge).last?.id == newTab.id` |
| multi-tabbed-008 | insert-tab-clamps-index | Edge has 2 tabs; call `insertTab(tab, at: 99, on: edge)` | Tab is inserted at index `2` (the end), not out of bounds |
| multi-tabbed-009 | remove-tab-locates-owning-edge | Tab lives on `.right`; call `removeTab(id: tab.id)` with no edge argument | `tabs(on: .right)` no longer contains the tab |
| multi-tabbed-010 | move-tab-clamps-index-within-edge | Edge has 3 tabs; call `moveTab(id: firstID, to: 50, on: edge)` | Tab moves to index `2` (the last valid index) |
| multi-tabbed-011 | move-tab-no-op-when-index-unchanged | Tab already at index `1`; call `moveTab(id:, to: 1, on:)` | Tab list order is unchanged; `didReorderTab` delegate callback is not invoked |
| multi-tabbed-012 | rename-tab-title-items-only | Call `renameTab(id:, title: "New")` on a `.viewController` tab | `tabs(on: edge).first { $0.id == id }?.title` is unchanged |
| multi-tabbed-013 | set-tab-item-preserves-mounted-content | Active tab's item is replaced via `setTabItem(id:, item:)` | The tab's `viewController` (and, if it is the active tab, the mounted center content) is unchanged |
| multi-tabbed-014 | single-active-tab-invariant | Tabs exist on 2 enabled edges with unrelated groups; select a tab on `.top`, then select a different (ungrouped) tab on `.left` | After the second selection, `activeTabID` names only the `.left` tab; the `.top` bar shows no tab as selected |
| multi-tabbed-015 | tab-defaults-to-own-group | Construct `Tab(title:, viewController:)` with no `groupID` | `tab.groupID == tab.id` |
| multi-tabbed-016 | group-siblings-share-selection-across-edges | Top and bottom tabs share a `groupID`; select the bottom one | The top bar shows its own member of the group (`topTab`) as selected, even though the bottom tab is the one whose content is shown |
| multi-tabbed-017 | ungrouped-tab-shows-no-selection-on-other-edges | Top tab has no shared group with any bottom tab; select the top tab | The bottom bar shows no tab as selected |
| multi-tabbed-018 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; call `addTab(tab, on: edge)` | `activeTabID == tab.id` |
| multi-tabbed-019 | active-tab-removal-neighbor | Active tab at index 1 of 3 on its edge is removed | The tab now at index 1 (the old index 2) becomes active |
| multi-tabbed-020 | removing-last-tab-on-edge-triggers-fallback | Active tab is the only tab on its edge; call `removeTab(id:)` | Fallback activation runs |
| multi-tabbed-021 | fallback-prefers-active-group | Active tab's group has a sibling on another enabled edge; a tab unrelated to the group sits first on the first enabled edge | Fallback activates the group sibling, not the unrelated first tab |
| multi-tabbed-022 | fallback-clears-when-nothing-found | No enabled edge has any tab; fallback runs | `activeTabID == nil` |
| multi-tabbed-023 | active-tab-change-notification | Last tab on the last enabled edge is removed | Delegate receives `activeTabDidChange(nil, on: nil)` |
| multi-tabbed-024 | select-tab-refuses-non-member-id | Call `selectTab(id: unrelatedID, on: edge)` where `unrelatedID` is not in `edge`'s tabs | `activeTabID` is unchanged |
| multi-tabbed-025 | center-shows-active-tab-view-controller | A tab is activated | The shared content area mounts the active tab's view controller as its sole child view |
| multi-tabbed-026 | center-falls-back-to-main-content | No tab active; `mainContentViewController` is set | The shared content area mounts `mainContentViewController`'s view |
| multi-tabbed-027 | center-mount-skips-redundant-remount | `refreshCenterContent()` called twice in a row with the same resolved target | The mounted controller's view is not removed and re-added on the second call |
| multi-tabbed-028 | content-insets-applied-to-mounted-view | `contentInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)` | The mounted content sits 4pt in from the content area's top and leading edges, and 4pt in from its bottom and trailing edges (inset inward) |
| multi-tabbed-029 | center-outline-reflects-color-override-or-fallback | `centerOutlineColor = nil` | The content area's visible border renders in the resolved palette's `.outline` color |
| multi-tabbed-030 | preferred-content-size-change-refreshes-every-bar | Hosted controller on `.left` changes `preferredContentSize`; `preferredContentSizeDidChange(for:)` fires | Every edge's bar — not only `.left`'s — recalculates its thickness to reflect its own hosted items' current preferred content size |
| multi-tabbed-031 | tab-bar-orientation-follows-edge | `TabBarView(edge: .right)` built | The right bar lays out its items down a vertical column, not across a row |
| multi-tabbed-032 | tab-bar-thickness-floor-and-growth | `.left` bar hosts an item with `preferredContentSize.width == 200` | The left bar's thickness (frame width) grows to `206pt` (200 + 6pt padding), above its `140pt` floor |
| multi-tabbed-033 | tab-item-padding-flush-to-content-side | `.top` bar built | The top bar's first item sits `6pt` from the bar's outer (top) edge; on the workspace-facing (bottom) edge, items sit flush with a `0pt` gap |
| multi-tabbed-034 | tab-button-selection-style | `TabButton.isHighlighted = true` | The selected tab's background fills with the `.selection` palette color, and its title text switches to the `.selectionText` role |
| multi-tabbed-035 | hosted-item-highlight-follows-selection | A `.viewController` tab conforming to `TabBarHostedItem` is selected | Its `isHighlighted == true` |
| multi-tabbed-036 | close-icon-hit-region | `mouseDown` at a point inside the close button's frame | The close action fires, closing that tab; the click does not also select the tab |
| multi-tabbed-037 | clicking-hosted-item-selects-its-tab | Real `mouseDown` hit-tested onto a hosted item's interior label | The hosted tab becomes selected |
| multi-tabbed-038 | vertical-edge-cards-overlap-and-order-by-distance | `.left` bar has 3 hosted items; the middle one is selected | The middle item's neighbors are drawn and hit-tested behind it: it visually overlaps and receives clicks over both neighbors |
| multi-tabbed-039 | cross-edge-move-preserves-foreign-controller | A hosted controller is moved from `.left`'s bar to `.right`'s bar (insert-then-remove); `.left`'s bar reconciles afterward | The controller's `parent` and mounted view are unaffected by `.left`'s reconciliation |
| multi-tabbed-040 | new-tab-hook-delegates-without-mutating | Call `newTab(nil)` with a delegate installed | `multiTabbedViewControllerNeedsNewTab(_:)` is invoked; no tab is added by this call itself |
| multi-tabbed-041 | explicit-group-override | Construct two `Tab` instances with the same explicit `groupID`, one per edge; select one | The other tab, sharing the same `groupID`, is also shown as selected on its own edge's bar |
| multi-tabbed-042 | Null/empty input (Edge Cases) | Call `tabs(on: edge)` for an edge with no tabs ever added | Returns `[]`, without trapping |
| multi-tabbed-043 | Error states (Edge Cases) | Set `delegate`, then let it deallocate (no strong reference remains); call `removeTab(id:)` for the last tab on an edge | The tab is removed from `tabs(on: edge)` (the mutation completes); no crash occurs even though `delegate` is now `nil` |
| multi-tabbed-044 | first-tab-on-enabled-edge-auto-activates | Edge has no tabs and is enabled; call `insertTab(tab, at: 0, on: edge)` directly (not `addTab`) | `activeTabID == tab.id` |

## Edge Cases

- Null/empty input (MUST): `tabs(on:)` MUST return `[]` for an edge with no
  tabs, never trap. `selectedTab(on:)`/`selectedTabID(on:)` MUST return `nil`
  when the active tab (if any) is not a member of the given edge. With both
  `mainContentViewController == nil` and no active tab, the shared content
  area MUST be left with no mounted controller at all rather than showing a
  blank placeholder controller.
- Boundary values (MUST): `insertTab(_:at:on:)`'s clamp
  (`max(0, min(index, count))`) and `moveTab(id:to:on:)`'s clamp
  (`max(0, min(index, count - 1))`) MUST both handle an index below `0` or
  past the end of the list the same way as one already in range — neither
  traps nor silently ignores the call.
- Concurrent access: Not applicable — `MultiTabbedViewController`, `Tab`'s
  storage (`EdgeState`), and `TabBarView` are all `@MainActor`-isolated; every
  mutating entry point (`addTab`, `removeTab`, `moveTab`, `setEdgeEnabled`,
  `selectTab`, and the internal sync/activation methods) runs on the main
  actor, so source provides no path for two threads to mutate one instance at
  the same time.
- Error states (MUST): `edge(forTabID:)` returning `nil` for an unknown id
  MUST make `removeTab(id:)`, `renameTab(id:title:)`, and `setTabItem(id:item:)`
  silent no-ops rather than trap. `selectTab(id:on:)` MUST be silently ignored
  when `id` is not a member of the given edge's own list — it does not search
  other edges for it. `delegate` is `weak`; a deallocated delegate MUST make
  every `delegate?...` call a no-op without preventing the underlying tab
  mutation from completing.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind; it manages an in-memory set of tab bars and mounts
  caller-supplied view controllers.
- Reusing one view-controller instance across two tabs: unguarded caller
  precondition. Nothing in `addTab`/`insertTab` refuses or dedupes a `Tab`
  whose `viewController` is already parented elsewhere or already mounted as
  another tab's content; callers MUST supply a distinct controller per tab,
  and AppKit's own view-controller containment is the only thing that reacts
  to a violation.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `delegate` | `MultiTabbedViewControllerDelegate?` (weak) | `nil` | Receives tab lifecycle callbacks: new-tab request, select, active-tab change, close request, reorder. |
| `mainContentViewController` | `NSViewController?` | `nil` | Shown in the shared content area while no tab is active. |
| `contentInsets` | `NSEdgeInsets` | `NSEdgeInsetsZero` | Gap held between the mounted content and the tab bars/edges around it. |
| `centerBackgroundColor` | `NSColor?` | `nil` | Overrides the shared content area's fill; `nil` falls back to the `.windowBackground` role. |
| `centerOutlineColor` | `NSColor?` | `nil` | Overrides the shared content area's `1pt` border color; `nil` falls back to the palette's `.outline` role. |
| Tab start inset (`setTabStartInset(_:for:)` / `tabStartInset(for:)`) | `CGFloat` per `Edge` | `8` (`TabBarView.endPadding`) | Where a bar's first tab begins, measured along the bar from its start. |
| Edge enabled state (`setEdgeEnabled(_:_:)` / `isEdgeEnabled(_:)`) | `Bool` per `Edge` | `true` for `.top`; `false` for `.right`/`.bottom`/`.left` | Whether an edge's tab bar and tabs are shown at all. |

## Deep Linking

Not applicable: `MultiTabbedViewController.swift` defines no URL scheme,
`NSUserActivity`, route, or deep-link handler anywhere in source; tabs are
added and removed only by direct, in-process API calls from the host.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — | "Close Tab" | `NSImage(systemSymbolName:accessibilityDescription:)`'s description for a `TabButton`'s close icon (`TabBarView.swift`) |

"Close Tab" is a hardcoded English `String` literal passed directly to
`accessibilityDescription`, not routed through `NSLocalizedString` or any
other localization mechanism used in this file — it is the one non-data-driven,
user/AT-facing string this component itself owns (a tab's own title text is
always supplied by the caller, so it carries no localization concern of this
component's making).

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext`/`animator()` call anywhere in
  `MultiTabbedViewController.swift` or `TabBarView.swift`; every appearance
  change (selection restyle, thickness change, layout rebuild) applies
  immediately.
- **Increase Contrast**: Not applicable — every color this component draws
  (`.selection`, `.selectionText`, `.secondaryText`, `.tertiaryText`,
  `.windowBackground`, `.outline`) is a semantic palette role; Increase
  Contrast handling, if any, belongs entirely to the theme/palette system this
  component defers to, not to this file.
- **Differentiate Without Color**: `TabButton.updateAppearance()`
  distinguishes selected from unselected purely by fill color (`.selection`
  vs. transparent) and a text-role swap (`.selectionText` vs.
  `.secondaryText`); no border, icon, weight, or other non-color cue
  accompanies the change. A `.viewController` item on a vertical edge gets a
  color-independent stacking/overlap cue from its `stackDepth`, but a
  `.title` tab never gets one, on any edge.

## Feature Flags

Not applicable: no feature-flag or config-gating lookup appears anywhere in
source; every edge, once enabled by the host, and every tab, once added,
behaves identically regardless of any external flag.

## Analytics

Not applicable: source contains no analytics or telemetry call anywhere in
`MultiTabbedViewController.swift` or `TabBarView.swift`; the delegate
callbacks are structural notifications for the host, not telemetry events.

## Privacy

- **Data collected**: None by this component itself. It manages an in-memory
  list of tab ids, group ids, display titles, and view-controller references
  describing *how* tabs are arranged — never content the host chooses to
  display inside a hosted view controller.
- **Storage**: In-memory only, for the life of the controller (`edgeStates`,
  `tabBars`, `activeTabID`). Nothing in this source persists tab state to disk;
  any such persistence is entirely the host's own responsibility, outside this
  file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: None beyond the controller's own lifetime; all tab and edge
  state is discarded when the controller is deallocated.

## Logging

Not applicable: source contains no logging call (no `print`, `os_log`, or
`Logger`/`Loggable` reference) anywhere in `MultiTabbedViewController.swift` or
`TabBarView.swift`.

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
  `NSViewController` component with no UIKit code path in source. A UIKit/
  iPadOS port has no direct analog to four independently toggleable,
  sibling-linked edge bars around one content area; it would most likely be a
  hand-built container using `UIStackView`s for each edge (mirroring this
  file's own `NSStackView`-per-edge structure) and a custom container view
  controller for the center, rather than `UITabBarController`, which supports
  only one bottom bar and no cross-edge group selection. Internally (private,
  not part of the conformance contract above — cited here rather than in the
  test vectors): `tabBars: [Edge: TabBarView]` holds each edge's bar view;
  `centerContainer` is the shared content wrapper and `mountedCenterController`
  tracks the controller currently mounted in it; each bar keeps its thickness
  in `thicknessConstraint` and lays items out in an `NSStackView` (`stack`)
  whose `edgeInsets` hold the per-side padding; `TabButton` draws selection
  through `backgroundView.layer` and a `titleLabel` role swap.
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
  `\uE711` ("Cancel") glyph sized to match the `14×14pt` hit area.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/MultiTabbedViewController.swift` |

## Design Decisions

**Decision**: A tab's `groupID` defaults to its own `id` rather than requiring
every caller to supply one.
**Rationale**: Per `Tab.init`'s doc comment, this "makes a tab its own group of
one — the behaviour every host had before groups existed," so a caller with
only one edge needs no change to keep working.
**Approved**: pending

**Decision**: `activateFallbackTab()` looks for a same-group sibling on any
enabled edge before falling back to the first tab of the first enabled edge.
**Rationale**: Per the method's doc comment, turning an edge off "is a decision
about where tabs are drawn," and jumping instead to an unrelated tab on the
first enabled edge "dropped [the user] onto an unrelated checkout" — the
group-first fallback keeps the user's actual selection stable across edge
visibility changes.
**Approved**: pending

**Decision**: `contentInsets` is applied by `MultiTabbedViewController` around
the mounted content, rather than left to the content itself.
**Rationale**: Per the property's doc comment, the tab bars "have to stay flush
against the window," so the gap belongs between the bars and what they
frame, and "this controller is the only thing that owns both."
**Approved**: pending

**Decision**: `activeTabDidChange` fires on every activation — including
transitions to `nil` — while `didSelectTab` fires only for a user-driven
pick (a click, or the neighbor/fallback a close hands the user).
**Rationale**: Per the delegate's doc comments, a host that only needs "which
pane is in front now" should not have to separately filter fallback and
clearing transitions out of genuine user picks; the two callbacks
deliberately separate "what changed" from "the user chose this."
**Approved**: pending

**Decision**: `TabBarView.rebuildButtons()`'s reconciliation tears down a hosted
controller only if that controller's view still sits in *this* bar's own
wrapper.
**Rationale**: Per the method's doc comment, a cross-edge move reparents the
controller's view onto the new bar's wrapper before the old bar notices the
id is gone from its own items; tearing it down there too "would rip the
view out of the new bar's display."
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
here, per source fidelity, rather than smoothed over.
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
