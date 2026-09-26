---
id: a11f34ff-116c-47d6-bffa-edd0799cbcb2
title: SplitViewController
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/split-view-controller
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit base class for a settings window's sidebar/detail split with back/forward
  history and optional search.
platforms:
- swift
- macos
tags:
- settings
- split-view
- view-controller
- navigation
- search
depends-on:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/split-view-controller/settings-panel-list-view-controller
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/panel-host-view
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/panel-scroll-view
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-panel/settings-panel-split-view-controller
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-window
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/split-views
approved-by: ''
approved-date: ''
---

# SplitViewController

## Overview

`ComposableSettings.SplitViewController`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift`,
is the base class for a topic/detail split-pane container used throughout the
settings window: a non-collapsible sidebar of panels on the left, driven by a
`PanelListViewController`, and a themed detail pane on the right that shows
whichever panel is currently selected, hosted inside a `PanelHostView`. It
subclasses `ThemedSplitViewController` (an `AgenticDeveloperToolkit` base
that supplies theme-aware split-view chrome and a divider-hiding safety fix)
and conforms to `NSSearchFieldDelegate` solely to redirect the sidebar
search field's arrow keys to sidebar-row navigation. Per the source's own
doc comments, a client subclasses `SplitViewController` and populates it in
`viewDidLoad` by calling `addPanel(_:)`.

A hosted panel MAY itself be a `SplitViewController` (see
`SettingsPanelSplitViewController`'s own recipe), in which case this class
treats it as a nested split: it unifies every nested sibling's sidebar to
one content width and raises its own detail floor so the nested content is
never squeezed.

**Owns:**
- Panel storage and ordering, including optional alphabetical sorting
- An in-place back/forward navigation trail (`SettingsNavigationHistory`)
- Sidebar sizing — draggable-and-autosaved, or content-sized and pinned
- An optional sidebar search field and its arrow-key-to-selection redirect
- Repainting the window/detail backgrounds from the active theme
- Forwarding help state to a `PanelHostView`

**Delegates to:**
- `PanelListViewController` — sidebar row rendering and search matching
  (its own recipe)
- `PanelHostView` — the detail pane's help-button chrome (its own recipe)
- `PanelScrollView` — the scroll wrapper around non-self-scrolling panel
  content (its own recipe)
- `SettingsWindow` — the window-level toolbar that drives this class's
  `goBack()`/`goForward()`/`helpPresenter` (its own recipe)

This recipe documents only what this file itself declares.

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
- **clears-search-on-programmatic-navigation**: Showing a panel via
  `goBack()`, `goForward()`, `selectPanel(_:)`, or `selectPanel(at:)` MUST
  clear the sidebar search field and query first, so the target row is
  never hidden by a stale filter.
- **propagates-navigation-change-upward**: Whenever this instance's
  selection, history availability, or panel title changes, it MUST invoke
  its own `onNavigationChange` and MUST also invoke the enclosing
  `SplitViewController`'s navigation-change notification, if one exists.
- **reports-current-panel-from-detail-container**: `currentPanel` MUST
  always reflect whichever panel is currently hosted in the detail pane,
  recomputed from the detail pane's actual content rather than from any
  separately tracked selection state (see the source mechanism in Platform
  Notes).
- **reports-effective-help-from-current-panel**: `effectiveHelp` MUST
  return the current panel's own `effectiveHelpContent`.
- **refreshes-help-through-detail-chrome-and-outward**: `refreshHelp()`
  MUST hand `effectiveHelp` to `panelHost.setHelp(_:)` and MUST also call
  the enclosing split's `refreshHelp()`, if one exists.
- **hosts-self-managing-panels-without-wrapper**: `show(_:)` MUST host a
  panel directly in `panelHost` (no wrapping scroll view) when that panel
  is itself a `SplitViewController` or reports `hostsOwnScroll == true`.
- **wraps-other-panels-in-scroll-view**: `show(_:)` MUST wrap every other
  panel's view in a `PanelScrollView` before hosting it in `panelHost`.
- **updates-help-and-floor-on-every-show**: Every call to `show(_:)`,
  including `show(nil)`, MUST refresh the detail chrome's help content and
  MUST re-apply the detail-pane minimum-thickness floor.
- **locates-enclosing-split-by-parent-chain**: `enclosingSettingsSplit`
  MUST always reflect the current view-controller hierarchy — recomputed
  from the live containment relationship each time it is read, not cached
  — returning `nil` when no enclosing split exists (see the source
  mechanism in Platform Notes).

## Appearance

- **Corner radius**: Not applicable — this file draws no chrome of its own;
  any corner radius shown by hosted panel content belongs to that content's
  own recipe.
- **Padding**: The detail pane's content view (`panelHost`) is pinned to
  its container's safe-area top and to the container's leading, trailing,
  and bottom edges with zero additional inset (`viewDidLoad`'s
  `NSLayoutConstraint.activate` block); no other padding constant is set in
  this file.
- **Font**: Not applicable — this file sets no font of its own; the search
  field's font is `ThemedSearchField`'s own responsibility.
- **Background**: `view.window?.backgroundColor` and
  `detailContainer.view.layer?.backgroundColor` are both set to the active
  `SemanticPalette`'s `windowBackgroundColor` role, in `applyTheme(_:)`.
- **Foreground/Text**: Not applicable — this file sets no text color of its
  own.
- **Border**: Not applicable — no border is configured in this file.
- **Shadow**: Not applicable — no shadow is configured in this file.
- **Min/Max size**: `detailMinimumThickness` defaults to `400`pt and floors
  the detail item's `minimumThickness` (raised to `nestedDetailFloor` when
  larger). The sidebar item is either draggable between `160` and `360`pt
  (`contentSizedSidebar == false`) or pinned at
  `min(minimumSidebarWidthOverride ?? listViewController.preferredWidth(), 480)`pt
  (`contentSizedSidebar == true`). No maximum is set on the detail item.

## States

| State | Appearance change |
|-------|------------------|
| Default | Sidebar and detail `NSSplitViewItem`s added; sidebar non-collapsible; window/detail background painted from the active theme; first panel auto-selected once panels exist. |
| Pressed | Not applicable — this file defines no `NSControl` of its own; the search field is a stock `NSSearchField`, and the divider/rows it hosts belong to `NSSplitView`/`PanelListViewController`. |
| Disabled | Not applicable in this file — a disabled panel row is `PanelListViewController`'s concern (`descriptor.isDisabled`); this file reads no disabled state. |
| Focused | While the sidebar search field holds first responder, Down/Up move the sidebar selection instead of the text caret (**redirects-arrow-keys-to-selection**); every other command types normally. |
| Loading | Not applicable — every operation in this file is synchronous; there is no asynchronous load state. |
| Content-sized sidebar (`contentSizedSidebar == true`) | Sidebar `minimumThickness == maximumThickness`, non-draggable, no autosave name set. |
| Draggable sidebar (`contentSizedSidebar == false`, default) | Sidebar thickness ranges `160`–`360`pt, draggable, `splitView.autosaveName` set to `sidebarAutosaveName`. |
| Sidebar search shown (`showsSidebarSearch == true`) | Search field installed as the sidebar's header accessory during `viewDidLoad`; typing narrows the sidebar and Down/Up steer the highlight. |
| Sidebar search hidden (`showsSidebarSearch == false`, default) | Search field never built; no header accessory installed. |
| Nested split present (≥2 hosted panels are themselves `SplitViewController`s) | Every nested sibling's sidebar is pinned to one shared width; this instance's own detail floor is raised to accommodate the widest nested sibling's sidebar plus its own `detailMinimumThickness`. |

## Accessibility

- **Role/trait**: Not applicable — this file assigns no accessibility role
  of its own; the sidebar rows (`PanelListViewController`), the detail
  chrome's help button (`PanelHostView`), and each hosted panel each own
  their own accessibility semantics in their own recipes.
- **Keyboard/assistive technology navigation**: The component MUST redirect
  Down/Up inside the sidebar search field to sidebar-row selection
  (**redirects-arrow-keys-to-selection**), leaving every other command
  (Return, Escape, Left/Right, text editing) to the field's default
  behavior. Beyond that redirect, this file adds no keyboard handling of
  its own; the standard `NSSplitViewController`/`NSOutlineView` tab order
  is unmodified.
- **Label requirements**: Supported for the search field: `NSSearchField`
  exposes its `placeholderString` as the field's accessible description by
  default, and this file sets no additional label of its own. That
  placeholder text is not itself localized (see Localization).
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this file has no loading or disabled state to announce (see States).
- **Minimum tap target**: Not applicable — this is a pointer-driven macOS
  container; no touch-target constant is set anywhere in this file. Hit
  sizing for the search field and split divider is standard AppKit sizing,
  not a value this file chooses.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| split-view-controller-001 | exposes-hosted-panels-read-only | Attempt to assign `panels` directly from outside the type | Compile error; only `setPanels`/`addPanel`/`removePanel`/`clear` compile |
| split-view-controller-002 | default-detail-minimum-thickness | Construct a plain instance | `detailMinimumThickness == 400` |
| split-view-controller-003 | overridable-detail-minimum-thickness | Subclass and override `detailMinimumThickness` to `200` | The overridden value, not `400`, governs the detail item's `minimumThickness` |
| split-view-controller-004 | default-sidebar-autosave-name | Construct a plain instance | `sidebarAutosaveName == "ComposableSettings.RootSidebar"` |
| split-view-controller-005 | default-content-sized-sidebar | Construct a plain instance | `contentSizedSidebar == false` |
| split-view-controller-006 | injectable-list-view-controller | Construct with `init(listViewController: customSubclass)` | `listViewController === customSubclass` |
| split-view-controller-007 | reaches-list-controller-title | Set `sidebarTitle = "Advanced"` after `viewDidLoad` has run | `listViewController`'s title becomes `"Advanced"` |
| split-view-controller-007b | reaches-list-controller-title | Set `sidebarTitle = "Advanced"` before the view loads, then trigger `viewDidLoad` | `listViewController`'s title is `"Advanced"` after load |
| split-view-controller-008 | reports-innermost-panel-title | Select a nested `SplitViewController` panel whose own `currentPanelTitle` is `"Accent Color"` | This instance's `currentPanelTitle == "Accent Color"` |
| split-view-controller-009 | rejects-coder-initialization | Attempt `init?(coder:)` | Traps with a fatal error; no instance is returned |
| split-view-controller-010 | runs-on-main-actor | Attempt to construct or mutate an instance from a non-main-actor context | Rejected at compile time by Swift's actor isolation checking |
| split-view-controller-011 | forwards-help-presenter-to-detail-chrome | Set `helpPresenter = drawer` | `panelHost.helpPresenter === drawer` |
| split-view-controller-012 | forwards-inline-help-button-visibility | Set `showsInlineHelpButton = false` | `panelHost.showsHelpButton == false` |
| split-view-controller-013 | wires-help-visibility-callback-once | Assign `onHelpVisibilityChange` twice, then have `panelHost` fire its own callback | The most recently assigned closure fires; no double invocation and no re-wiring occurs on assignment |
| split-view-controller-014 | toggles-help-through-detail-chrome | Call `toggleHelp()` | `panelHost.toggleHelp()` is invoked |
| split-view-controller-015 | reports-help-visibility-from-detail-chrome | Set `panelHost`'s help to visible | `isHelpVisible == true` |
| split-view-controller-016 | builds-search-field-lazily | Construct an instance with `showsSidebarSearch == false` and never read the search field | No `ThemedSearchField` is ever allocated |
| split-view-controller-017 | installs-search-field-only-when-enabled | Set `showsSidebarSearch = true` before `viewDidLoad`, then load | `listViewController`'s header accessory view is the search field |
| split-view-controller-017b | installs-search-field-only-when-enabled | Leave `showsSidebarSearch == false`, then load | `listViewController`'s header accessory view is unset |
| split-view-controller-018 | filters-list-as-user-types | Type `"a"` into the search field without pressing Return | `listViewController.searchQuery == "a"` immediately |
| split-view-controller-019 | redirects-arrow-keys-to-selection | With the search field focused and `"Advanced"` typed, press Down | Sidebar selection moves to the next visible row; search text remains `"Advanced"` |
| split-view-controller-020 | builds-non-collapsible-sidebar-item | Load the view, then attempt to collapse the sidebar item | Collapse is refused; `canCollapse == false` |
| split-view-controller-021 | prioritizes-detail-pane-on-resize | Read the sidebar item's and detail item's `holdingPriority` after `viewDidLoad` | Sidebar item's `holdingPriority == .defaultLow + 1`; detail item's `holdingPriority == .defaultLow` |
| split-view-controller-022 | fixes-content-sized-sidebar-thickness | Set `contentSizedSidebar` to return `true`, then load | Sidebar item's `minimumThickness == maximumThickness` |
| split-view-controller-023 | constrains-draggable-sidebar-range | Load with `contentSizedSidebar == false` (default) | Sidebar item's `minimumThickness == 160`, `maximumThickness == 360` |
| split-view-controller-024 | persists-draggable-sidebar-width | Load with `contentSizedSidebar == false` | `splitView.autosaveName == sidebarAutosaveName` |
| split-view-controller-024b | persists-draggable-sidebar-width | Subclass overrides `sidebarAutosaveName` to return `nil`; load with `contentSizedSidebar == false` | `splitView.autosaveName == nil`; width persistence is silently disabled, no fallback name is used |
| split-view-controller-025 | omits-autosave-for-content-sized-sidebar | Load with `contentSizedSidebar == true` | `splitView.autosaveName` is left unset |
| split-view-controller-026 | caps-content-sized-sidebar-width | `listViewController.preferredWidth()` returns `900`, `minimumSidebarWidthOverride == nil` | Sidebar item's fixed width is `480`, not `900` |
| split-view-controller-027 | unifies-nested-sidebar-widths | Host two nested `SplitViewController` panels whose own `preferredWidth()`s are `180` and `220` | Both nested panels' `minimumSidebarWidthOverride == 220` |
| split-view-controller-028 | raises-detail-floor-for-nested-siblings | Nested siblings as above, each with `detailMinimumThickness == 200` | This instance's `nestedDetailFloor == 420` (`220 + 200`) |
| split-view-controller-029 | floors-detail-pane-thickness | `detailMinimumThickness == 400`, `nestedDetailFloor == 420` | Detail item's `minimumThickness == 420` |
| split-view-controller-030 | selects-first-panel-on-first-appearance | Set two panels via `setPanels(_:)`, then trigger `viewWillAppear` with no prior selection | `panels.first` is shown and selected |
| split-view-controller-031 | repaints-theme-on-appearance-and-change | Switch the active theme after the view has appeared | Window and detail-container backgrounds update to the new theme's `windowBackgroundColor` |
| split-view-controller-032 | replaces-panel-list-atomically | Call `setPanels([a, b])` | `panels == [a, b]`; history is empty; sidebar shows exactly `a` and `b` |
| split-view-controller-033 | appends-without-unnecessary-history-reset | With `sortsPanelsByTitle == false`, navigate to panel `a`, then call `addPanel(c)` | History still shows `a` as current; `c` appended at the end |
| split-view-controller-033b | appends-without-unnecessary-history-reset | With `sortsPanelsByTitle == true`, navigate to panel `a`, then call `addPanel(c)` where `c` sorts before `a` | History is reset; the sidebar re-selects `a` at its new (shifted) index |
| split-view-controller-034 | removes-and-renumbers-selection | Panels `[a, b, c]`, `b` selected, call `removePanel(a)` | `panels == [b, c]`; `b` remains selected at its new index `0` |
| split-view-controller-034b | removes-and-renumbers-selection | Panels `[a, b]`, `b` selected, call `removePanel(b)` | Detail pane is cleared; nothing is selected |
| split-view-controller-035 | sorts-panels-when-configured | `sortsPanelsByTitle == true`; add panels titled `"Zebra"`, `"Apple"` with no section | `panels` order is `["Apple", "Zebra"]` |
| split-view-controller-036 | clears-search-when-restored-selection-is-hidden | Search query hides the currently selected panel, then `removePanel` triggers a restore of that same panel | Search query is cleared before the panel is re-selected |
| split-view-controller-037 | clears-all-panels | Call `clear()` | `panels == []`; detail pane empty; `onNavigationChange` invoked |
| split-view-controller-038 | records-explicit-selection | Call `selectPanel(at: 1)` | History's `current == 1` |
| split-view-controller-039 | steps-through-visible-rows-only | Visible rows are `[0, 2]` (row `1` filtered out), current is `0`, call `moveSelection(by: 1)` | Selection moves to row `2`, not row `1` |
| split-view-controller-039b | steps-through-visible-rows-only | Current selection is the last visible row, call `moveSelection(by: 1)` | No change; selection does not wrap to the first row |
| split-view-controller-040 | preserves-search-during-arrow-navigation | Search query is `"a"`, call `moveSelection(by: 1)` | `listViewController.searchQuery` remains `"a"` |
| split-view-controller-041 | navigates-back-through-history | History has one prior entry, call `goBack()` | The previous panel is shown; history is not appended |
| split-view-controller-042 | navigates-forward-through-history | After a `goBack()`, call `goForward()` | The panel that was current before `goBack()` is shown again |
| split-view-controller-043 | resolves-arrows-to-innermost-active-split | A nested split's own history can go back but the outer split's cannot, call `goBack()` on the outer split | The nested split's `goBack()` behavior runs, not the outer split's |
| split-view-controller-044 | clears-search-on-programmatic-navigation | Search query is `"a"`, call `goBack()` | Search field and `searchQuery` are cleared before the panel is shown |
| split-view-controller-045 | propagates-navigation-change-upward | This instance is nested inside an outer split, selection changes | Both this instance's `onNavigationChange` and the outer split's navigation-change handling fire |
| split-view-controller-046 | reports-current-panel-from-detail-container | Show panel `a` via `show(_:)` | `currentPanel === a` |
| split-view-controller-047 | reports-effective-help-from-current-panel | `currentPanel.effectiveHelpContent` is non-`nil` | `effectiveHelp` equals that same value |
| split-view-controller-048 | refreshes-help-through-detail-chrome-and-outward | This instance is nested, call `refreshHelp()` | `panelHost.setHelp(_:)` is called with `effectiveHelp`; the outer split's `refreshHelp()` is also called |
| split-view-controller-049 | hosts-self-managing-panels-without-wrapper | Show a panel that is itself a `SplitViewController` | `panelHost`'s content is that panel's view directly, no `PanelScrollView` wrapper |
| split-view-controller-050 | wraps-other-panels-in-scroll-view | Show a plain panel with `hostsOwnScroll == false` | `panelHost`'s content is a `PanelScrollView` wrapping that panel's view |
| split-view-controller-051 | updates-help-and-floor-on-every-show | Call `show(nil)` | `panelHost.setContent(nil)`, `panelHost.setHelp(nil)`, and the detail-floor recompute all run |
| split-view-controller-052 | locates-enclosing-split-by-parent-chain | This instance is added as a child of an outer `SplitViewController` via `addPanel` | `enclosingSettingsSplit` returns that outer instance |
| split-view-controller-053 | (edge case: `removePanel(_:)` on a non-member) | Panels `[a, b]`, call `removePanel(z)` where `z` is not in `panels` | `panels` is unchanged (`[a, b]`); navigation history is still reset, the sidebar's panel list is still re-set, and `onNavigationChange` still fires |
| split-view-controller-054 | (edge case: stale nested-detail floor) | Two nested `SplitViewController` siblings raise `nestedDetailFloor` to `420`; `removePanel` drops the nested count to one | `nestedDetailFloor` remains `420` (not reset toward `0`), because `unifyNestedSidebars()`'s `guard nested.count > 1` returns early before recomputing it |

## Edge Cases

- **Null/empty input**: `setPanels([])` and `clear()` both leave `panels`
  empty, the sidebar empty, and the detail pane empty (MUST). Constructing
  with `init(listViewController:)`'s default argument uses a stock
  `PanelListViewController()` rather than requiring a caller-supplied one
  (MUST).
- **Boundary values**: `selectPanel(at:)` and `navigate(to:)` both guard
  `panels.indices.contains(index)` and are silent no-ops out of range
  (MUST). `moveSelection(by:)` stops at the first or last *visible* row
  rather than wrapping, and is a no-op when no rows are visible (MUST, see
  **steps-through-visible-rows-only**). A content-sized sidebar's width is
  capped at `480`pt regardless of how wide `preferredWidth()` reports (MUST,
  see **caps-content-sized-sidebar-width**).
- **Concurrent access**: Not applicable — the class is `@MainActor`, so the
  Swift compiler rejects construction or mutation from off the main actor;
  there is no concurrent-access surface for this file to define behavior
  for.
- **Error states**: Not applicable — every member in this file is
  synchronous and non-throwing; there is no dependency, network call, or
  fallible operation in this file.
- **Offline/disconnected state**: Not applicable — this file performs no
  networking and has no dependency on connectivity.
- **`removePanel(_:)` on a panel not in `panels`**: `removeAll(where:)`
  removes nothing, but the method still unconditionally resets navigation
  history, re-sets the sidebar's panel list, and invokes
  `notifyNavigationChange()` — the same side effects as a real removal.
  This is a documented observation of the file's actual behavior, not a
  deliberate contract (see split-view-controller-053).
- **`sidebarAutosaveName == nil` while `contentSizedSidebar == false`**: A
  subclass MAY override `sidebarAutosaveName` to return `nil`. In that case
  `splitView.autosaveName` is set to `nil`, which silently disables
  `NSSplitView`'s width-persistence for that instance — no fallback name is
  substituted and nothing fails (see split-view-controller-024b).
- **Stale nested-detail floor after a nested split is removed**:
  `unifyNestedSidebars()` only recomputes `nestedDetailFloor` when at least
  two nested `SplitViewController` panels remain (`guard nested.count > 1
  else { return }`); when a `removePanel`/`setPanels` call drops the nested
  count from two-or-more to one or zero, this early return leaves
  `nestedDetailFloor` at its previous, now-stale value rather than
  resetting it toward `0`. The detail pane's floor can therefore stay wider
  than the current panel set requires until a later state again has two or
  more nested siblings. This is the file's actual, undocumented behavior —
  see Design Decisions and split-view-controller-054.
- **Toggling `showsSidebarSearch` or `sortsPanelsByTitle` after their
  first effect has already run**: Neither property has a property observer.
  `showsSidebarSearch` is read only once, in `viewDidLoad`, to decide
  whether to install the header accessory view — flipping it afterward has
  no further effect on an already-loaded view. `sortsPanelsByTitle` is
  read only inside `setPanels(_:)`/`addPanel(_:)` — flipping it does not
  retroactively reorder a panel list already installed; it only changes the
  outcome of the next mutating call.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `detailMinimumThickness` | `CGFloat` (open, overridable) | `400` | Floor on the detail pane's `NSSplitViewItem.minimumThickness`. |
| `sidebarAutosaveName` | `String?` (open, overridable) | `"ComposableSettings.RootSidebar"` | `NSSplitView.autosaveName` used when `contentSizedSidebar == false`. |
| `contentSizedSidebar` | `Bool` (open, overridable) | `false` | `true` pins the sidebar to its content width and disables dragging/autosave; `false` keeps the draggable, autosaved band. |
| `minimumSidebarWidthOverride` | `CGFloat?` | `nil` | External floor for a content-sized sidebar's width, set by a parent split to unify nested siblings. |
| `sidebarTitle` | `String?` | `nil` | Header title shown above the sidebar's panel list. |
| `showsSidebarSearch` | `Bool` | `false` | Whether the sidebar leads with a search field; read once, in `viewDidLoad`. |
| `sortsPanelsByTitle` | `Bool` | `false` | Whether `setPanels`/`addPanel` alphabetize panels (within section) instead of keeping supplied order. |
| `showsInlineHelpButton` | `Bool` | `true` | Whether the detail pane's own `panelHost` draws its `?` button. |
| `helpPresenter` | `SettingsHelpPresenting?` | `nil` | Where help content and visibility are shown; forwarded to `panelHost.helpPresenter`. |
| `listViewController` | `PanelListViewController` | `PanelListViewController()` | The sidebar controller; injectable via `init(listViewController:)`. |

## Deep Linking

Not applicable: no URL scheme, route, or `NSUserActivity` handling appears
anywhere in `SplitViewController.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `"Search"` | Search | Placeholder text for the sidebar's search field, passed as `ThemedSearchField(placeholder: "Search")` and stored as AppKit's `placeholderString` — a literal `String`, not routed through any localization lookup in this file. |

The `"Search"` placeholder is not localized: `SplitViewController.swift`
passes it as a hardcoded literal to `ThemedSearchField(placeholder:)`,
never routing it through `NSLocalizedString`/`String(localized:)`, both of
which are used elsewhere in this Swift package (outside this file).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this file. |
| Increase Contrast | Not applicable to this file: colors come from `SemanticPalette` via `ThemePaletteObserver`; any Increase Contrast adaptation is that type's responsibility, not something this file computes. |
| Differentiate Without Color | Not applicable: this file has no color-only state indicator; row selection is `PanelListViewController`'s concern. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this file.

## Analytics

Not applicable: this file contains no analytics or telemetry call.

## Privacy

- **Data collected**: None beyond the panels and search text the host
  supplies at runtime; the sidebar search query lives only in memory.
- **Storage**: When `contentSizedSidebar == false` (the default), the
  sidebar's dragged width is persisted locally via `NSSplitView`'s built-in
  `autosaveName` mechanism (backed by `UserDefaults`), keyed by
  `sidebarAutosaveName`. No other state in this file is persisted; the
  search query and navigation history are in-memory only and are discarded
  on `setPanels(_:)`, `clear()`, or app relaunch.
- **Transmission**: Not applicable — no networking call appears anywhere in
  this file.
- **Retention**: The autosaved sidebar width persists under its key
  indefinitely, until the user drags it again or the underlying
  `UserDefaults` entry is cleared by the OS or the app; it is never written
  by this file when `contentSizedSidebar == true`.

## Logging

Not applicable: no logging call (`print`, `os_log`, or logger reference)
appears anywhere in `SplitViewController.swift`.

## Platform Notes

- **SwiftUI**: Use `NavigationSplitView` with a `List` (built from `panels`)
  as the sidebar column and the selected panel's view as the detail column.
  For `contentSizedSidebar == true`, set the sidebar column's
  `.navigationSplitViewColumnWidth(min:ideal:max:)` to the same fixed value
  (min == ideal == max), the nearest SwiftUI analog of a pinned,
  non-draggable width; for the draggable default, use `min: 160, ideal:
  <persisted>, max: 360` and persist the ideal width yourself (SwiftUI has
  no built-in per-split autosave equivalent to `NSSplitView.autosaveName`).
  Use `.searchable(text:)` on the sidebar for `showsSidebarSearch`, and
  drive back/forward with a small custom index stack, since
  `NavigationSplitView` has no built-in in-place trail matching
  `SettingsNavigationHistory`'s discard-forward-on-new-step semantics.
- **Compose**: Compose a two-pane `ListDetailPaneScaffold` (Material 3
  adaptive) or a manual `Row` of a fixed-width `LazyColumn` sidebar plus a
  weighted detail `Box`. Size the sidebar with
  `Modifier.width(IntrinsicSize.Max)` for the content-sized case, or a
  draggable divider whose width is saved to `DataStore`/`SharedPreferences`
  (mirroring the autosave) for the default case. Filter the list with an
  `OutlinedTextField` bound to a `mutableStateOf` query; implement
  back/forward as a small `MutableList<Int>` index trail, since Compose
  Navigation's back stack tracks destinations, not row selections within
  one screen.
- **React/Web**: A CSS Grid two-column layout
  (`grid-template-columns: <sidebar> 1fr`), sidebar `<nav>` of `<button>`s
  or links, detail `<main>`. For the content-sized case, size the sidebar
  column `max-content`; for the draggable default, add a resizer handle
  that persists its width to `localStorage` under a key analogous to
  `sidebarAutosaveName`. Filter with a controlled `<input type="search">`;
  implement back/forward as an in-memory index stack rather than the
  browser History API, since each panel is not necessarily its own route.
- **AppKit / UIKit** (source platform): Source file
  `SplitViewController.swift` (`ComposableSettingsWindow/SplitViewController/`),
  AppKit-only — an `NSSplitViewController` subclass of `ThemedSplitViewController`,
  composing a `PanelListViewController` sidebar item and a `PanelHostView`-hosted
  detail item, wrapping non-self-scrolling panel content in a
  `PanelScrollView`, and tracking navigation with a
  `SettingsNavigationHistory` value type. `panels` is declared
  `private(set)`, enforcing **exposes-hosted-panels-read-only** at compile
  time. `init(coder:)` is `@available(*, unavailable)` and its body is
  `fatalError()`, giving **rejects-coder-initialization** its fatal error.
  The sidebar item's `holdingPriority` is `.defaultLow + 1` against the
  detail item's `.defaultLow`, which is how
  **prioritizes-detail-pane-on-resize** is implemented. `currentPanel` is
  computed by reading `detailContainer.children.first`, and
  `enclosingSettingsSplit` walks `parent` upward looking for the nearest
  `ComposableSettings.SplitViewController` — the mechanisms behind
  **reports-current-panel-from-detail-container** and
  **locates-enclosing-split-by-parent-chain**. No UIKit counterpart exists in
  this codebase (`ComposableSettingsWindow/` is entirely AppKit); a UIKit
  port would reach for `UISplitViewController` with `.doubleColumn` style,
  though it has no analog of `contentSizedSidebar`'s pinned min==max
  thickness or of `NSSplitView`'s dragging-based `autosaveName` persistence.
- **WinUI 3** (the reason this recipe exists): Use a `NavigationView` with
  `PaneDisplayMode="Left"` as the sidebar and its `Content`/`Frame` as the
  detail region. Bind `MenuItems` to the panel list — one
  `NavigationViewItem` per panel, grouped under a `NavigationViewItemHeader`
  per `descriptor.section` run, mirroring `PanelListViewController`'s
  section grouping — and drive selection through `SelectionChanged`
  (analogous to `listViewController.onSelectPanel`). For the draggable
  default (`contentSizedSidebar == false`), set
  `IsPaneToggleButtonVisible="False"` and bind `OpenPaneLength` to a value
  restored from `ApplicationData.LocalSettings` keyed by
  `sidebarAutosaveName`, constrained to a `160`–`360`-equivalent range; for
  `contentSizedSidebar == true`, fix `OpenPaneLength` to the pane's measured
  content width and skip persistence entirely, exactly as this file does.
  There is no WinUI analog of `NSSplitViewItem.minimumThickness` on the
  content side, so approximate `detailMinimumThickness` (and the raised
  nested-sibling floor) with a `MinWidth` on the `Frame`/`ContentPresenter`
  hosting `Content`. For search, add an `AutoSuggestBox` as
  `NavigationView.PaneCustomContent`, wire `TextChanged` to filter
  `MenuItems.Source` the way `searchQueryChanged` filters
  `PanelListViewController`, and forward the list's Up/Down `KeyDown` to
  move `SelectedItem` while the `AutoSuggestBox` keeps focus — mirroring
  `control(_:textView:doCommandBy:)`. Implement back/forward with two
  `Stack<int>`s alongside `NavigationView.BackRequested`, since
  `SettingsNavigationHistory`'s trail semantics (discard-forward-on-new-
  step, no-op on re-selecting the current row) have no built-in WinUI
  equivalent; for a nested `NavigationView` acting as
  `SettingsPanelSplitViewController` does, forward whichever inner item is
  selected up to the outer shell's single help affordance, mirroring
  `effectiveHelp`/`refreshHelp()`'s outward chain.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift` |

## Design Decisions

**Decision**: `detailMinimumThickness` floors the detail pane's
`NSSplitViewItem.minimumThickness` rather than a required-width constraint
on the detail content.
**Rationale**: Per the source's own comment, this "lets the detail grow
freely, unlike a required width constraint on the content, which pins the
window"; it is "the proper lever for the window's minimum width (window
min = sidebar thickness + this)."
**Approved**: pending

**Decision**: `contentSizedSidebar` defaults to `false` for this base class
(the draggable, autosaved band), even though nested splits generally want
`true`.
**Rationale**: Per the source's own comment, "the full-height *root* window
sidebar keeps the draggable behaviour (its outline's column-fill misbehaves
under a fixed width). Nested topic/detail splits opt in — they're the ones
that visibly 'move around' as you switch between them."
**Approved**: pending

**Decision**: `showsSidebarSearch` and `sortsPanelsByTitle` both default to
`false` and are switched on only for the window's root split.
**Rationale**: Per the source's own comments, a nested split's sidebar is
"a table of contents for one panel" written in an intentional order, while
the root window's list is "a set of unrelated destinations" a reader can
only find by name or by search; a second search field inside an outer
split's already-filtered results "is a maze."
**Approved**: pending

**Decision**: `moveSelection(by:)` (arrow-key stepping) leaves the search
field's text and query untouched, unlike `selectPanel`/`goBack`/`goForward`,
which all clear it.
**Rationale**: Per the source's own comment, "the query is the very thing
the reader is steering by when they press Down, so clearing it would throw
away the list they are moving through and jump the highlight somewhere
else."
**Approved**: pending

**Decision**: `SplitViewController` conforms to `NSSearchFieldDelegate`
solely to intercept `moveDown(_:)`/`moveUp(_:)`, returning `false` for
every other command selector.
**Rationale**: Per the source's own comment, this is answered in the
delegate callback "rather than in a `keyDown` override because AppKit has
already turned the key into the reader's intent by this point — and
returning false for every other command leaves the rest of text editing
exactly as it was."
**Approved**: pending

**Decision**: `currentPanelTitle` and `effectiveHelp` both recurse into a
selected panel that is itself a `SplitViewController`, reporting that
inner split's own title/help rather than this instance's.
**Rationale**: Per the source's own comment, "a split whose selected panel
is itself a split answers with the topic selected *inside* it: that is the
panel the reader is looking at," and naming the outer container instead
"left the toolbar stuck on the container's name while the reader moved
down its list."
**Approved**: pending

**Decision**: `unifyNestedSidebars()` leaves `nestedDetailFloor` unchanged
(rather than resetting it toward `0`) whenever the current panel set has
fewer than two nested `SplitViewController` panels.
**Rationale**: Not stated in source. The method's guard clause returns
before recomputing the floor, so a detail-pane floor raised while two or
more nested splits were present can outlive their removal until a later
state again has two or more. Documented here as observed behavior (see
Edge Cases and split-view-controller-054), not as a deliberate design
tradeoff.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |

Statuses rest on: this file delegating row
rendering to `PanelListViewController`, help chrome to `PanelHostView`, and
scroll wrapping to `PanelScrollView` rather than reimplementing any of them
(separation-of-concerns); the search field's arrow-key redirect and the
unmodified standard `NSSplitViewController` tab order (keyboard-navigable);
`native-controls-preference` resting on this file composing only stock
`NSSplitViewController`/`NSSplitViewItem`/`NSSearchField` behavior with no
custom-drawn chrome. `screen-reader-support` is `partial`: the search
field's accessible description is the AppKit-default `placeholderString`,
but that placeholder is the unlocalized `"Search"` literal documented under
Localization, so a non-English VoiceOver user would hear an English word
regardless of the app's language.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restate five implementation-mechanics requirements (private(set), fatalError(), holdingPriority, detail-container read, parent-chain walk) as observable outcomes and move their mechanics into the AppKit Platform Notes bullet; downgrade the removePanel-on-non-member edge case from a MUST-relied-upon contract to a documented observation; add an edge case, a test vector, and Design-Decisions wording for a nil sidebarAutosaveName; add test vectors pinning the removePanel-on-non-member and stale-nested-detail-floor behaviors; tighten test vector 021 to assert holdingPriority directly instead of an unstated width change; reformat Design Decisions to the bold three-line form; split the Overview into a short description plus Owns/Delegates-to lists; move the platform-design-languages reference into related and the three composed-ingredient recipes into depends-on; trim tags to 5 and summary to ~120 characters; and reconcile the Compliance table against the catalog, dropping seven cited checks that have no corresponding category or check in the compliance catalog. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
