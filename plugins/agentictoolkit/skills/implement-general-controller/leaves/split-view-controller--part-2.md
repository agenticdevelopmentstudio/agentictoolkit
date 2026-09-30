<!-- leaf: implement-general-controller/split-view-controller--part-2 · source: split-view-controller.md -->

# SplitViewController — continued (part 2)

**Rules** (cite as `implement-general-controller/split-view-controller--part-2#<slug>`):

- `exposes-hosted-panels-read-only` MUST
- `default-detail-minimum-thickness` MUST
- `overridable-detail-minimum-thickness` MAY
- `default-sidebar-autosave-name` MUST
- `default-content-sized-sidebar` MUST
- `injectable-list-view-controller` MUST
- `reaches-list-controller-title` MUST
- `reports-innermost-panel-title` MUST
- `rejects-coder-initialization` MUST
- `runs-on-main-actor` MUST
- `forwards-help-presenter-to-detail-chrome` MUST
- `forwards-inline-help-button-visibility` MUST
- `wires-help-visibility-callback-once` MUST
- `toggles-help-through-detail-chrome` MUST
- `reports-help-visibility-from-detail-chrome` MUST
- `builds-search-field-lazily` MUST
- `installs-search-field-only-when-enabled` MUST
- `filters-list-as-user-types` MUST
- `redirects-arrow-keys-to-selection` MUST
- `builds-non-collapsible-sidebar-item` MUST
- `prioritizes-detail-pane-on-resize` MUST
- `fixes-content-sized-sidebar-thickness` MUST
- `constrains-draggable-sidebar-range` MUST
- `persists-draggable-sidebar-width` MUST
- `omits-autosave-for-content-sized-sidebar` MUST
- `caps-content-sized-sidebar-width` MUST
- `unifies-nested-sidebar-widths` MUST
- `raises-detail-floor-for-nested-siblings` MUST
- `floors-detail-pane-thickness` MUST
- `selects-first-panel-on-first-appearance` MUST
- `repaints-theme-on-appearance-and-change` MUST
- `replaces-panel-list-atomically` MUST
- `appends-without-unnecessary-history-reset` MUST
- `removes-and-renumbers-selection` MUST
- `sorts-panels-when-configured` MUST
- `clears-search-when-restored-selection-is-hidden` MUST
- `clears-all-panels` MUST
- `records-explicit-selection` MUST
- `steps-through-visible-rows-only` MUST
- `preserves-search-during-arrow-navigation` MUST
- `navigates-back-through-history` MUST
- `navigates-forward-through-history` MUST
- `resolves-arrows-to-innermost-active-split` MUST

## Behavioral Requirements

- **exposes-hosted-panels-read-only**: The component MUST expose `panels`
  as read-only to callers outside the type — mutable only through
  `setPanels(_:)`, `addPanel(_:)`, `removePanel(_:)`, or `clear()`.
- **default-detail-minimum-thickness**: The component MUST default
  `detailMinimumThickness` to `400` points when not overridden.
- **overridable-detail-minimum-thickness**: A subclass MAY override
  `detailMinimumThickness`, since the property is declared `open`, to raise
  or lower the floor `NSSplitViewItem.minimumThickness` applies to the
  detail pane — appropriate when a subclass's own content needs a
  different minimum than the window-level default (`SettingsPanelSplitViewController`
  lowers it to `200` for nested content; see that recipe).
- **default-sidebar-autosave-name**: The component MUST default
  `sidebarAutosaveName` to `"ComposableSettings.RootSidebar"` when not
  overridden.
- **default-content-sized-sidebar**: The component MUST default
  `contentSizedSidebar` to `false`.
- **injectable-list-view-controller**: The component MUST accept a
  `PanelListViewController` (or subclass) via `init(listViewController:)`,
  defaulting to a stock `PanelListViewController()` when the caller supplies
  none.
- **reaches-list-controller-title**: Whatever value `sidebarTitle` holds
  MUST reach `listViewController.setTitle(_:)` — immediately, if
  `sidebarTitle` is set after the view has loaded, or once, during
  `viewDidLoad`, if it was set (or left at its default) beforehand.
- **reports-innermost-panel-title**: `currentPanelTitle` MUST return the
  innermost selected panel's own title — recursing into a selected panel
  that is itself a `SplitViewController` and using its `currentPanelTitle`
  — whenever that inner title is non-`nil`, rather than this instance's own
  selected panel's `descriptor.title`.
- **rejects-coder-initialization**: Attempting to construct the component
  via `init(coder:)` MUST fail with a fatal error rather than returning an
  instance.
- **runs-on-main-actor**: The component MUST be `@MainActor`-isolated;
  construction and every property access MUST occur on the main actor.
- **forwards-help-presenter-to-detail-chrome**: Whenever `helpPresenter` is
  set, the component MUST forward the new value to `panelHost.helpPresenter`.
- **forwards-inline-help-button-visibility**: Whenever
  `showsInlineHelpButton` is set, the component MUST forward the new value
  to `panelHost.showsHelpButton`.
- **wires-help-visibility-callback-once**: The component MUST wire
  `panelHost.onHelpVisibilityChange` to invoke its own
  `onHelpVisibilityChange` exactly once, during `init`, rather than
  re-wiring it each time `onHelpVisibilityChange` is assigned.
- **toggles-help-through-detail-chrome**: `toggleHelp()` MUST delegate to
  `panelHost.toggleHelp()`.
- **reports-help-visibility-from-detail-chrome**: `isHelpVisible` MUST
  return `panelHost.isHelpVisible`.
- **builds-search-field-lazily**: The sidebar search field MUST be built
  lazily, on first access, so a split with `showsSidebarSearch == false`
  never allocates it.
- **installs-search-field-only-when-enabled**: During `viewDidLoad`, the
  component MUST install the search field as the sidebar's header accessory
  view if and only if `showsSidebarSearch` is `true` at that moment.
- **filters-list-as-user-types**: The search field MUST report every
  keystroke immediately (`sendsSearchStringImmediately == true`, not only on
  Return, `sendsWholeSearchString == false`), and each report MUST set
  `listViewController.searchQuery` to the field's current text.
- **redirects-arrow-keys-to-selection**: While the search field holds
  focus, pressing Down or Up MUST move the sidebar selection via
  `moveSelection(by:)` instead of moving the text caret; every other
  editing command MUST fall through to the field's default handling.
- **builds-non-collapsible-sidebar-item**: During `viewDidLoad`, the
  component MUST add a sidebar `NSSplitViewItem` (built with
  `listViewController`) whose `canCollapse` is `false`.
- **prioritizes-detail-pane-on-resize**: The sidebar item's resize-holding
  priority MUST be higher than the detail item's, so a window resize
  resizes the detail pane rather than the sidebar (see the source values in
  Platform Notes).
- **fixes-content-sized-sidebar-thickness**: Whenever `contentSizedSidebar`
  is `true`, the component MUST set the sidebar item's `minimumThickness`
  and `maximumThickness` to the same value (see
  **caps-content-sized-sidebar-width**), making the sidebar non-draggable.
- **constrains-draggable-sidebar-range**: Whenever `contentSizedSidebar` is
  `false`, the component MUST constrain the sidebar item's thickness between
  `160` and `360` points.
- **persists-draggable-sidebar-width**: Whenever `contentSizedSidebar` is
  `false`, the component MUST set `splitView.autosaveName` to
  `sidebarAutosaveName`, so a user's dragged sidebar width survives across
  app launches.
- **omits-autosave-for-content-sized-sidebar**: Whenever
  `contentSizedSidebar` is `true`, the component MUST NOT set
  `splitView.autosaveName`.
- **caps-content-sized-sidebar-width**: A content-sized sidebar's thickness
  MUST equal `min(minimumSidebarWidthOverride ?? listViewController.preferredWidth(), 480)`
  points.
- **unifies-nested-sidebar-widths**: Whenever two or more of this
  instance's hosted panels are themselves `SplitViewController`s, the
  component MUST set every one of their `minimumSidebarWidthOverride`
  properties to the same value: the widest of their own
  `preferredWidth()`s, capped at `480` points.
- **raises-detail-floor-for-nested-siblings**: Whenever
  **unifies-nested-sidebar-widths** applies, the component MUST raise its
  own nested-detail floor to the largest of `widest + nested.detailMinimumThickness`
  across those nested siblings.
- **floors-detail-pane-thickness**: The detail item's `minimumThickness`
  MUST always equal `max(detailMinimumThickness, nestedDetailFloor)`.
- **selects-first-panel-on-first-appearance**: During `viewWillAppear`, if
  no panel is yet selected and `panels` is non-empty, the component MUST
  select `panels.first`.
- **repaints-theme-on-appearance-and-change**: The component MUST repaint
  the window's `backgroundColor` and the detail container's layer
  `backgroundColor` from the active `SemanticPalette`'s
  `windowBackgroundColor` on every `viewWillAppear` and on every theme
  change its `ThemePaletteObserver` reports.
- **replaces-panel-list-atomically**: `setPanels(_:)` MUST replace `panels`
  (ordered per **sorts-panels-when-configured**), reset navigation history,
  rebuild the sidebar, and re-run sidebar-layout unification, in that call.
- **appends-without-unnecessary-history-reset**: `addPanel(_:)` MUST
  append the given panel to `panels` (reordering if
  **sorts-panels-when-configured** applies) and rebuild the sidebar without
  resetting navigation history, except that when `sortsPanelsByTitle` is
  `true` it MUST reset history and restore the selection, because sorting
  may have renumbered existing rows.
- **removes-and-renumbers-selection**: `removePanel(_:)` MUST remove the
  given panel by identity (`===`), reset navigation history, rebuild the
  sidebar, and restore the sidebar's highlight to whichever panel remains
  selected at its new index — or clear the detail pane if the removed panel
  was the one on screen.
- **sorts-panels-when-configured**: Whenever `sortsPanelsByTitle` is
  `true`, `setPanels(_:)` and `addPanel(_:)` MUST order the full panel list
  by section (ranked in first-encountered order) and, within equal rank, by
  `localizedStandardCompare` of `descriptor.title`; whenever it is `false`,
  panels MUST keep exactly the order supplied.
- **clears-search-when-restored-selection-is-hidden**: When a rebuild's
  restored selection is not among the sidebar's currently visible
  (search-filtered) rows, the component MUST clear the sidebar search query
  before re-selecting it.
- **clears-all-panels**: `clear()` MUST empty `panels`, reset navigation
  history, empty the sidebar, empty the detail pane, and invoke navigation
  change notification.
- **records-explicit-selection**: `selectPanel(_:)` and `selectPanel(at:)`
  MUST record the target index in navigation history before showing it.
- **steps-through-visible-rows-only**: `moveSelection(by:)` MUST move the
  selection only among the sidebar's currently visible (search-filtered)
  rows, and MUST stop at the first or last visible row rather than
  wrapping.
- **preserves-search-during-arrow-navigation**: `moveSelection(by:)` MUST
  leave the search field's text and `listViewController.searchQuery`
  unchanged.
- **navigates-back-through-history**: `goBack()` MUST, when a back step
  exists on the innermost split still able to go back, show that split's
  previous panel without recording a new history entry.
- **navigates-forward-through-history**: `goForward()` MUST, symmetrically
  with **navigates-back-through-history**, show the next panel in the trail
  without recording a new history entry.
- **resolves-arrows-to-innermost-active-split**: `goBack()` and
  `goForward()` MUST act on the innermost nested split whose own history
  can still move in the requested direction, falling back to this instance
  when no nested split can.
