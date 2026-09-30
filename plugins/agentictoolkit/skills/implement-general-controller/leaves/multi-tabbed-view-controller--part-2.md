<!-- leaf: implement-general-controller/multi-tabbed-view-controller--part-2 · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController — continued (part 2)

**Rules** (cite as `implement-general-controller/multi-tabbed-view-controller--part-2#<slug>`):

- `top-edge-enabled-by-default` MUST
- `edge-toggle-updates-bar-visibility` MUST
- `hidden-edge-retains-tabs` MUST
- `edge-state-change-triggers-fallback-activation` MUST
- `disabled-edge-excluded-from-layout` MUST
- `bar-spans-content-perpendicular-dimension` MUST
- `add-tab-appends-to-edge` MUST
- `insert-tab-clamps-index` MUST
- `remove-tab-locates-owning-edge` MUST
- `move-tab-clamps-index-within-edge` MUST
- `move-tab-no-op-when-index-unchanged` MUST
- `rename-tab-title-items-only` MUST
- `set-tab-item-preserves-mounted-content` MUST
- `single-active-tab-invariant` MUST
- `tab-defaults-to-own-group` MUST
- `group-siblings-share-selection-across-edges` MUST
- `ungrouped-tab-shows-no-selection-on-other-edges` MUST
- `first-tab-on-enabled-edge-auto-activates` MUST
- `active-tab-removal-neighbor` MUST
- `removing-last-tab-on-edge-triggers-fallback` MUST
- `fallback-prefers-active-group` MUST
- `fallback-clears-when-nothing-found` MUST
- `active-tab-change-notification` MUST
- `select-tab-refuses-non-member-id` MUST
- `center-shows-active-tab-view-controller` MUST
- `center-falls-back-to-main-content` MUST
- `center-mount-skips-redundant-remount` MUST
- `content-insets-applied-to-mounted-view` MUST
- `center-outline-reflects-color-override-or-fallback` MUST
- `preferred-content-size-change-refreshes-every-bar` MUST
- `tab-bar-orientation-follows-edge` MUST
- `tab-bar-thickness-floor-and-growth` MUST
- `tab-item-padding-flush-to-content-side` MUST
- `tab-button-selection-style` MUST
- `hosted-item-highlight-follows-selection` MUST
- `close-icon-hit-region` MUST
- `clicking-hosted-item-selects-its-tab` MUST
- `vertical-edge-cards-overlap-and-order-by-distance` MUST
- `cross-edge-move-preserves-foreign-controller` MUST
- `new-tab-hook-delegates-without-mutating` MUST
- `explicit-group-override` MAY
- `open-for-subclassing` MAY

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

