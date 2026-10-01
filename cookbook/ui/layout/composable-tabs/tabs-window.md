---
id: 55a394e6-9934-404b-941d-25bebbf71378
title: Composable Tabs Window
domain: agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The top-level window for a project's multi-edge tabbed workspace, owning
  per-edge tab groups, a toolbar search field, a help drawer, and layout persistence.
platforms:
- swift
- macos
tags:
- composable-tabs
- window-controller
- multi-tab
depends-on:
- agentictoolkit://cookbook/ui/layout/tabbed-view
- agentictoolkit://cookbook/ui/layout/composable-tabs
related: []
references: []
approved-by: ''
approved-date: ''
---

# Composable Tabs Window

## Overview

The window is the top-level container for one project's workspace. Its
content hosts up to four docked tab bars — top, right, bottom, left — each
tab wrapping a split-pane tree rooted at a persisted layout. One
project-level "tab" is a *group*: one member tab per currently enabled edge,
all sharing a title and a working directory, so opening, closing, or
renaming a tab acts on the whole group at once rather than on a single
bar's button. The window also owns a unified toolbar (a search field, a
help toggle), two trailing title-bar accessory buttons (arrange mode,
project settings), a bottom status footer, and a per-project help drawer,
and it exposes a scripting-facing surface (a tab handle, pane/tab lookup,
search and tab-selection accessors) that an external automation bridge can
address directly.

## Behavioral Requirements

- **window-id**: The window's identifier MUST be derived from the project's
  repository id, formatted as `"projectWindow.<repo-uuid>"`, so window
  geometry is persisted per project rather than per window type.
- **default-geometry**: With no saved frame for the project, the window MUST
  open at 800×500 points.
- **minimum-size**: The window MUST NOT be resized below 400×300 points.
- **frame-persistence**: The window's frame MUST be saved on move/resize and
  restored the next time a window for the same project id is shown.
- **standard-window-controls**: The window MUST present the close, minimize,
  and zoom title-bar controls and MUST be user-resizable.
- **window-title**: The window title MUST be the project's display name.
- **unified-toolbar**: The window MUST install a unified toolbar containing,
  in order, a flexible space, a search field, and a help button.
- **tab-group-creation**: Creating a project tab MUST create one member tab
  on every currently enabled edge, all sharing one title and one working
  directory, and MUST select the first member created.
- **group-close-scope**: Requesting to close any one member tab MUST remove
  every member of its group from every enabled edge.
- **last-group-guard**: The window MUST NOT close a tab group when it is the
  project's only remaining group.
- **last-edge-guard**: The window MUST NOT disable an edge when doing so
  would leave every edge disabled.
- **edge-top-up**: Enabling an edge MUST create one member tab per existing
  group on that edge if it does not already have one, using the active
  tab's current split arrangement (with fresh node ids) as the starting
  layout, or the project's layout blueprint if no tab exists yet.
- **title-tab-fallback**: A tab whose data source is absent, or whose data
  source declines to supply an item, MUST render as a plain title button
  showing the tab's stored title.
- **arrangement-mirroring**: Whenever the active tab's split tree changes
  shape or a divider moves, the window MUST apply the same shape and
  sizes — never the same node ids — to every other tab in the project.
- **structural-change-persistence**: A split, pane close, tab
  add/remove/reorder/select, or edge toggle MUST synchronously persist every
  tab's current layout tree, the active tab id, and the enabled-edge set to
  the project. A divider-thickness change is the one exception to that
  synchronous path: the tabbed content debounces it 300ms before the
  resulting layout change reaches this persist, and that pending write is
  flushed explicitly when the window closes (see **divider-flush-on-close**).
- **focused-leaf-debounce**: A change to which leaf pane is focused MUST be
  written to the project no sooner than 250ms after the change settles,
  rather than synchronously.
- **arrange-titlebar-button**: The window MUST show a trailing title-bar
  accessory button that toggles arrange mode for the window and is tinted
  with the resolved accent color while arrange mode is enabled.
- **settings-titlebar-button**: The window MUST show a trailing title-bar
  accessory button that presents project settings as a sheet on the window.
- **arrange-menu-state**: A menu item bound to the arrange-mode action MUST
  show a checked state whenever arrange mode is enabled for the window and
  unchecked otherwise.
- **search-target**: The pane the search field targets MUST be whichever
  pane the window last recomputed the field's enabled state and placeholder
  from. That recomputation happens whenever the active pane changes (tab
  activation, an active-pane notification, or the window being shown), so
  the target tracks the active pane at the moment of the last such
  refresh, not necessarily whichever pane is active at the instant of a
  keystroke.
- **search-routing**: Typing into the toolbar search field MUST forward the
  query, live, to the search target (see **search-target**).
- **search-availability**: The search field MUST be disabled whenever the
  search target does not support search, and its placeholder MUST read
  "Search" when the search target supplies none.
- **search-target-clearing**: When the search target changes, the field's
  text MUST be cleared.
- **status-footer-content**: The footer MUST show the project's display
  name, the active tab's title, the active pane's resolved title, and the
  active pane's selection description, omitting any that are empty, joined
  with the separator `" › "`.
- **help-drawer-toggle**: Invoking the help action MUST open the drawer if
  it is closed and close it if it is open.
- **help-visibility-persistence**: Whether the help drawer was left open
  MUST be remembered per project, not globally, and reapplied the next time
  that project's window is shown.
- **help-tab-width-persistence**: The drawer's selected tab and its dragged
  width MUST be remembered per project once help has been disclosed at
  least once in the window's lifetime, and MUST NOT be written before that
  first disclosure.
- **help-glyph-state**: The help button's icon MUST switch between an
  outlined and a filled question-mark glyph depending on whether the drawer
  is disclosed, and its tooltip MUST switch between "Show Help" and "Hide
  Help" to match, while its fixed accessibility name ("Help") MUST NOT
  change.
- **tab-activation-focus**: Activating a project tab MUST restore keyboard
  focus to that tab's last-focused leaf pane, deferred until after the
  tab's view hierarchy is mounted.
- **pane-teardown-on-close**: Closing the window MUST tear down every pane
  in every tab (releasing per-pane resources such as shells or file
  watchers) and MUST stop persisting the tab set from that point on.
- **divider-flush-on-close**: If the project already has stored tabs,
  closing the window MUST flush any pending divider-thickness persist
  before tearing the panes down.
- **reload-persist-suppression**: While a tab-reload operation's removal
  loop is running, the window MUST suppress the persist, focus-restore, and
  chrome-refresh side effects that an intermediate tab-selection change
  would otherwise trigger.
- **pane-enumeration-order**: Enumerating every pane in the window MUST
  order them by tab, then by edge in the fixed order top, right, bottom,
  left, then by each split's own leaf order.
- **scripting-tab-selection**: Setting the active tab by group id MUST
  select that group's member on the first enabled edge that has one, and
  MUST be ignored if the id names no group in this window.
- **redundant-tab-selection-guard**: Selecting a tab that is already active
  MUST NOT re-run tab-activation side effects (focus restore, persist,
  chrome refresh) a second time.
- **edge-set-assignment-order**: Assigning the enabled-edge set MUST enable
  every named edge before disabling any edge that is not named, so that
  reassigning the enabled-edge set never fails the last-enabled-edge
  refusal on an intermediate step.

## Appearance

- **Corner radius**: Not applicable — a standard window; the window draws
  no custom-cornered chrome.
- **Padding**: The tabbed content's insets default to 0pt on all four sides
  (persisted keys `pane_spacing_top` / `_leading` / `_bottom` /
  `_trailing`) and are user-configurable. A side tab bar's own start inset
  on the left and right edges equals the content inset plus the height of
  a pane's own title bar (2pt border inset + 26pt title-bar height = 28pt
  total), so a side tab bar's first tab lines up with a pane's own title
  bar rather than floating above it.
- **Font**: Not applicable — the window renders no text directly; toolbar
  labels, tab titles, and footer text are drawn by the tabbed content view,
  the status footer, and the toolbar/drawer components, each a separate
  ingredient.
- **Background**: The window background is set once, at creation, to the
  active theme's window-background color. The plane behind the split tree
  tracks the live theme palette's pane-backdrop (fill) and pane-outline
  (outline) colors, updating live as the theme changes.
- **Foreground/Text**: Not applicable at this layer — see Font.
- **Border**: Not applicable — standard system window border; no HUD-style
  chrome is configured for this window.
- **Shadow**: Not applicable — standard system window shadow.
- **Min/Max size**: Minimum 400×300pt; no maximum size is set.

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet shown: no toolbar or titlebar accessories exist until the window is first shown. |
| Pressed | Not applicable — the window itself renders no pressable surface; per-press visuals belong to the buttons and toolbar items it hosts. |
| Disabled | Search field is disabled and grayed whenever the search target reports that it does not support search (see **search-availability**, **search-target**). |
| Focused | The active tab's last-focused leaf pane holds keyboard focus, restored on tab activation and when the window is shown. |
| Loading | Not applicable — tab and pane installation is synchronous; no loading/spinner state exists in source. |
| Arrange mode enabled | Arrange titlebar button shows accent tint and a pressed-looking active state; the bound menu item shows a checkmark. |
| Arrange mode disabled | Arrange titlebar button shows no tint and no active state; the menu item shows no checkmark. |
| Help drawer open | Help toolbar button shows the filled question-mark glyph, accent tint, and tooltip "Hide Help". |
| Help drawer closed | Help toolbar button shows the outlined question-mark glyph, secondary-text tint, and tooltip "Show Help". |
| Single remaining tab group | The tab-close affordance for that group's members MUST have no effect (see **last-group-guard**). |
| Last enabled edge | The settings toggle for that edge MUST have no effect (see **last-edge-guard**). |

## Accessibility

- Role/traits: standard window with title-bar close/minimize/zoom controls;
  toolbar and titlebar-accessory controls are plain buttons (custom-view
  toolbar items, since a toolbar item is not itself directly accessible)
  and a system-style search field.
- Accessibility identifiers: the search field and help button carry the
  toolbar identifiers `project.toolbar.search` and `project.toolbar.help`;
  the titlebar accessories carry `project-window.arrange-button` and
  `project-window.project-settings-button`.
- Label requirements: the help button's accessibility description is fixed
  at "Help" and does not change when its glyph/tooltip swap for open vs.
  closed; the arrange and settings buttons carry the accessibility
  descriptions "Arrange Panes" and "Project Settings"; the search field's
  placeholder is the search target's own placeholder text or "Search" when
  none applies.
- Announce state changes: the help toggle communicates its open/closed
  state through symbol shape (outline vs. filled) and tooltip text, not
  tint alone; the arrange toggle communicates its state through the
  button's own pressed/active visual state, in addition to tint.
- Minimum control size: this is a pointer-driven layout with no mandated
  minimum touch-target size; the titlebar accessory buttons are built at
  36×24pt and the toolbar icon buttons follow the platform's standard
  icon-only sizing, consistent with this codebase's other toolbar/titlebar
  controls rather than a value this component decides on its own.
- Keyboard/focus: the titlebar and toolbar buttons are ordinary
  keyboard-focusable controls (Space/Return activate); the search field has
  normal text-field key handling; the arrange action is additionally
  reachable through any menu item bound to the arrange-mode action,
  validated by the platform's own menu-validation mechanism.
- Color/contrast: chrome colors are read from the shared theme palette;
  contrast is a design-system-level concern outside this window's own
  decisions, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-window-controller-001 | window-id | Two windows built for repo ids A and B | Their derived window identifiers are `"projectWindow.A"` and `"projectWindow.B"`; each window's saved frame is independent. |
| composable-tabs-window-controller-002 | default-geometry | Show the window for a project with no prior saved frame | Window frame size is 800×500pt. |
| composable-tabs-window-controller-003 | minimum-size | Attempt to resize the window below 400×300pt | Window stops at 400×300pt. |
| composable-tabs-window-controller-004 | frame-persistence | Move/resize the window, close it, build a new window for the same project id and show it | New window opens at the previously saved frame. |
| composable-tabs-window-controller-005 | standard-window-controls | Inspect the shown window | Close, minimize, and zoom controls are present and enabled; window is resizable by the user. |
| composable-tabs-window-controller-006 | window-title | Project display name is `"Zorkapp"` | Window title reads `"Zorkapp"`. |
| composable-tabs-window-controller-007 | unified-toolbar | Inspect the shown window's toolbar | Toolbar style is unified; item order is flexible space, search, help. |
| composable-tabs-window-controller-008 | tab-group-creation | Top and left edges enabled; create a new project tab | A new group has one member on top and one on left, same title, same working directory; the top member is selected. |
| composable-tabs-window-controller-009 | group-close-scope | Two-member group (top, left); request close on the top member | Both the top and left members are removed. |
| composable-tabs-window-controller-010 | last-group-guard | Exactly one tab group exists; request its close | The group remains; tab count is unchanged. |
| composable-tabs-window-controller-011 | last-edge-guard | Only the top edge is enabled; request disabling it | The top edge remains enabled. |
| composable-tabs-window-controller-012 | edge-top-up | Two groups exist, only the top edge enabled; enable the right edge | The right edge gains one member per existing group, each seeded from the current active tab's arrangement with fresh node ids — none of the new members reuses a node id from the tab they were seeded from. |
| composable-tabs-window-controller-013 | title-tab-fallback | No tab-item data source is supplied; a tab titled `"Tab 2"` is created | The tab renders as a plain title button reading "Tab 2". |
| composable-tabs-window-controller-014 | arrangement-mirroring | Two tabs exist; drag a divider in the active tab | The other tab's split adopts the same shape and sizes, with its own node ids preserved. |
| composable-tabs-window-controller-015 | structural-change-persistence | Reorder a tab | The project's tab layout is persisted synchronously with the new order. |
| composable-tabs-window-controller-016 | focused-leaf-debounce | Change focused leaf twice within 100ms | Only one persist occurs, at least 250ms after the second change. |
| composable-tabs-window-controller-017 | arrange-titlebar-button | Toggle arrange mode on | Arrange button shows accent tint and its active/checked state. |
| composable-tabs-window-controller-018 | settings-titlebar-button | Click the settings titlebar button | The settings view is presented as a sheet. |
| composable-tabs-window-controller-019 | arrange-menu-state | Arrange mode enabled for the window; validate the bound menu item | Menu item shows a checked state. |
| composable-tabs-window-controller-020 | search-routing | Search target is pane P; type `"foo"` | The search target receives the query `"foo"`. |
| composable-tabs-window-controller-021 | search-availability | Search target reports that it does not support search | Search field is disabled. |
| composable-tabs-window-controller-022 | search-target-clearing | Field contains `"foo"`; search target changes to a different searchable pane | Field text becomes `""`. |
| composable-tabs-window-controller-023 | status-footer-content | Project `"Zork"`, tab `"Main"`, pane title `"main.swift"`, no selection description | Footer reads `"Zork › Main › main.swift"`. |
| composable-tabs-window-controller-024 | help-drawer-toggle | Drawer closed; invoke the help action | Drawer opens; invoking again closes it. |
| composable-tabs-window-controller-025 | help-visibility-persistence | Open help, close window, reopen a window for the same project | Drawer reopens automatically. |
| composable-tabs-window-controller-026 | help-tab-width-persistence | Help never opened in this window; close the window | No drawer-tab/drawer-width setting is written. |
| composable-tabs-window-controller-027 | help-glyph-state | Open the help drawer | Help button icon is the filled question-mark glyph, tooltip "Hide Help", accessibility description still "Help". |
| composable-tabs-window-controller-028 | tab-activation-focus | Tab T's last focus was leaf L; activate T | Keyboard focus becomes L's view, after the tab's view hierarchy is mounted. |
| composable-tabs-window-controller-029 | pane-teardown-on-close | Window has a terminal pane with a running shell; close the window | The shell is terminated (every pane's teardown runs). |
| composable-tabs-window-controller-030 | divider-flush-on-close | Project has stored tabs; drag a divider, then close the window within 300ms | The dragged thickness is persisted before teardown. |
| composable-tabs-window-controller-031 | reload-persist-suppression | Trigger a tab-reload operation on a window with 3 tabs | No intermediate persist writes a partial tab set; exactly one persist reflects the final reloaded state. |
| composable-tabs-window-controller-032 | pane-enumeration-order | Two tabs, each split into two panes on the top and left edges | Enumerating every pane returns tab-1's panes (top before left, leaf order), then tab-2's, in the same order on repeated calls. |
| composable-tabs-window-controller-033 | scripting-tab-selection | Set the active tab to an existing group's id, enabled only on the bottom edge | That group's bottom-edge member becomes active. |
| composable-tabs-window-controller-034 | redundant-tab-selection-guard | Tab T is already active; select tab T again | No additional persist, focus-restore, or chrome refresh occurs. |
| composable-tabs-window-controller-035 | edge-set-assignment-order | Only the top edge enabled; assign the enabled-edge set to `["bottom"]` | The bottom edge becomes enabled before the top edge is disabled; final state is the bottom edge only. |
| composable-tabs-window-controller-036 | minimum-size | Inspect the window's configured geometry before the window is ever shown | The configured minimum size is 400×300pt, matching what the window itself enforces. |
| composable-tabs-window-controller-037 | status-footer-content | Project `"Zork"`, active tab's title is `""` (empty), pane title `"main.swift"`, no selection description | Footer reads `"Zork › main.swift"` — the empty tab title contributes no leading `" › "`. |
| composable-tabs-window-controller-038 | search-target | The active pane changes from pane A to pane B, triggering a recomputation of search availability | The search target becomes pane B, matching the field's newly computed enabled state/placeholder. |

## Edge Cases

- **Null/empty input**: selecting a tab, or setting the active tab, by an id
  that names no group in this window MUST be ignored (MUST) rather than
  clearing the current selection. Listing a tab's panes with an unparsable
  or unknown identifier MUST return an empty array (MUST). An assignment to
  the enabled-edge set MUST NOT trip the last-enabled-edge refusal partway
  through, because enables are applied before disables (MUST) — see
  **edge-set-assignment-order**.
- **Boundary values**: exactly one remaining tab group MUST refuse to close
  (MUST); exactly one remaining enabled edge MUST refuse to disable (MUST).
  These are the only two lower-bound guards in the source; no upper bound on
  tab or edge count exists.
- **Concurrent access**: every mutation (tab add/remove/select, edge
  toggle, persistence) is confined to a single thread, so there is no
  defined behavior for access from another thread — none is needed, since
  this kind of window is inherently single-threaded in its host
  environment. Within that single thread, reentrancy during a single
  operation is guarded explicitly: a reload-in-progress guard suppresses
  side effects while tabs are being reloaded, an arrangement-mirroring
  guard stops the mirror from recursing into itself, and a closing guard
  stops a closing window's own teardown from re-persisting a stale tab set
  (MUST for each guard, as implemented).
- **Error states**: the settings-write path and the tab-persistence call
  are invoked without checking a return value or catching an error
  anywhere in this component; per the source's own comments, the
  settings-write path "swallows its errors." A persistence failure
  therefore produces no user-facing error, no retry, and no logged
  diagnostic — this is what the source does, not an idealized
  error-handling requirement. This is recorded as accepted debt in Design
  Decisions above, not treated as an unresolved gap.
- **Offline/disconnected state**: Not applicable — the window performs no
  network requests; all persistence (window frame, tab layout, drawer
  prefs) is local.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `project` | Project workspace object | required | The project workspace this window displays; supplies id, display name, directory, initial tabs, and local settings storage. |
| `tabItemDataSource` | Optional tab-item data source (supplies each tab's edge-bar item) | absent | Supplies each tab's edge-bar item; when absent, falls back to a plain title button (see **title-tab-fallback**). |

## Deep Linking

Not applicable: no URL-scheme or system-activity handoff handling appears
anywhere in this component. The window is opened only by project-management
code constructing it directly.

## Localization

Applicable, and unmet: every user-facing string in this file — `"Search"`,
`"Help"`, `"Show Help"` / `"Hide Help"`, `"Arrange Panes"`, `"Project
Settings"`, `"Panes"`/`"Minimizing"`/`"Zoom"`/etc. help topic bodies, and the
default tab title `"Tab \(n)"` — is a hardcoded English literal. No
localization key lookup exists in source. This is recorded as accepted debt
in Design Decisions above, and is reflected in Compliance below
(`string-externalization`, `no-hardcoded-strings`).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the window performs no animated transitions of its own; tab installation, arrangement mirroring, and drawer open/close are owned by the tabbed content view and the window drawer, each a separate ingredient. |
| Increase Contrast | Not applicable: chrome colors are sourced from the shared theme palette; contrast handling is a design-system-level concern this window does not decide. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by symbol shape (outline vs. filled question-mark glyph) and tooltip text, not by tint alone; the arrange toggle differentiates on/off by the button's own pressed/active visual state, in addition to tint. |

## Feature Flags

Not applicable: no flag-gated behavior (feature flag, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging calls appear in this file.

## Privacy

- **Data collected**: the window's frame (position and size) keyed by
  project id; the project's full tab layout (split tree, titles, working
  directories, focused-leaf id, active-tab id, enabled edges); the help
  drawer's per-project preferences (`drawer.open`, `drawer.tab`,
  `drawer.width`, stored under `project_setting`).
- **Storage**: window frame is stored locally, keyed by the window's
  derived identifier; tab layout and drawer preferences are stored locally
  in the project's own settings/database. No networked store is used
  anywhere in this file.
- **Transmission**: none. No networking import or call appears in this
  file; everything persisted here stays on the local device.
- **Retention**: the window frame persists until the project's saved window
  state is explicitly cleared. Tab layout and drawer preferences persist
  until overwritten or the project is deleted. Drawer tab/width are written
  only after help has been disclosed at least once; a project whose help
  was never opened stores none of that preference.

## Logging

Not applicable: no logging calls appear anywhere in this component.

## Platform Notes

- **SwiftUI**: not the source form. A SwiftUI rebuild would key a
  `WindowGroup`/`Scene` by project id for per-window state, with one
  `TabView`-like construct per enabled edge, all reading the same
  `[TabGroup]` model so a "project tab" still means one logical entry drawn
  on every enabled bar — SwiftUI's `TabView` has no native concept of
  multiple, independently dockable tab bars sharing one selection, so this
  would need a custom container rather than a bare `TabView`.
- **Compose (Android/Desktop)**: model the window as one
  `Activity`/`ComposeWindow`; represent each enabled edge as a `TabRow` (top)
  or a side rail composable (left/right) or a bottom bar, all driven by one
  shared `[TabGroup]`-equivalent state holder in a `ViewModel`; the
  250ms focused-leaf debounce and the persist-on-structural-change split map
  onto `SavedStateHandle` writes gated the same way.
- **React/Web**: the window becomes a page or route; each edge's tab strip
  is a component reading from one shared tab-groups store (Redux/Zustand);
  the toolbar search field maps to an `<input type="search">` wired to
  whichever pane component is currently "the search target," mirroring the
  window's search-target tracking; window-frame persistence has no web
  equivalent (the browser owns window chrome) and would be dropped, keeping
  only the tab-layout and drawer-preference persistence.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists in source. The window is a `@MainActor`
  `NSWindowController` (`ComposableTabsWindowController`); every
  requirement above holds only under main-actor confinement, which is why
  there is no defined cross-thread behavior in Edge Cases: the three
  reentrancy guards named there are the boolean properties
  `isReloadingTabs`, `isMirroringArrangement`, and `isClosing`. The window's
  identifier is derived by `ComposableTabsWindowController.windowID(for:)`;
  its geometry persistence is configured via
  `WindowSpec(persistsFrame: true, minSize: NSSize(width: 400, height: 300), ...)`
  and stored through `WindowManager.shared.frames`
  (`WindowFrameManager.clearSavedState(for:)` clears it). Standard window
  controls are configured via
  `windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]`.
  The toolbar's unified appearance is `toolbarStyle == .unified`. The
  settings titlebar button presents `ComposableTabsSettingsViewController`
  as a sheet on the window's content view controller. Search-target
  tracking (`searchTargetNodeID`) is recomputed by
  `applySearchAvailability(to:)`, called from tab activation, an
  active-pane notification, and `showWindow(_:)`. Tab-activation focus
  restoration is deferred by one run-loop turn so the tab's view hierarchy
  is mounted first. Pane enumeration (`allPanes()`) walks `Edge.allCases`
  order (`top`, `right`, `bottom`, `left`); the enabled-edge setter is
  `enabledTabEdgeNames`; the reload operation is `reloadTabs()`. The help
  glyph is the SF Symbol pair `questionmark.circle` (outlined) /
  `questionmark.circle.fill` (filled); the arrange toggle's pressed-looking
  active state is `NSButton.state` (`.on`/`.off`), rendered by AppKit as a
  pressed bezel on a `.texturedRounded` button, in addition to accent
  tint. Chrome colors track `ThemePaletteObserver.currentPalette` (its
  `windowBackgroundColor`, `projectPaneBackdrop`, `projectPaneOutline`).
  Content insets are `PaneSpacing.contentInsets`
  (`UserSetting<Int>` values `pane_spacing_top`/`_leading`/`_bottom`/
  `_trailing`); the side-bar start-inset arithmetic uses
  `ComposableTabsPaneBackgroundView.borderInset` (2pt) and
  `PaneTitleBarView.height` (26pt). The `project` configuration option is
  typed `ProjectWorkspace`; `tabItemDataSource` is typed
  `ComposableTabsTabItemDataSource?`; persisted tab layout is a
  `TabRecord` list, written via `project.persistTabs(...)` and
  `project.setSetting(_:to:)`, gated by the `hasDisclosedHelp` flag for the
  drawer's tab/width settings. No `NSLocalizedString`/string-catalog lookup
  exists in source for any of this file's literals. Files: this file
  (`ComposableTabsWindowController.swift`), `PaneSpacing.swift`,
  `ComposableTabsPaneViewController.swift` (for `titleBarBottom`),
  `SingleWindowController.swift` / `WindowController.swift` /
  `WindowSpec.swift` (window lifecycle and geometry persistence),
  `WindowToolbarBuilder.swift` (toolbar items and the disclosure-glyph
  helper), `Edge.swift`, `ComposableTabsTabItemDataSource.swift`, and
  `LayoutNode.swift` (`TabRecord`).
- **WinUI 3**: the closest native shape is a single `Window` whose primary
  edge uses `Microsoft.UI.Xaml.Controls.TabView` — WinUI 3's `TabView` only
  docks along the top, so the other three edges (right/bottom/left) have no
  built-in equivalent and need a custom `ItemsRepeater`/`ListView` styled as
  a side or bottom tab strip, all bound to one shared tab-group view-model
  list so a "project tab" still means one logical entry represented on every
  enabled strip. Persisted window geometry maps to `AppWindow.Resize`/`Move`
  saved to `ApplicationData.LocalSettings` keyed by project id, mirroring
  the source's derived window identifier. There is no WinUI drawer primitive
  for the help panel; use a `SplitView` in `Inline` or `CompactOverlay`
  display mode pinned to a window edge, with `IsPaneOpen`/`OpenPaneLength`
  bound to the same per-project `drawer.open`/`drawer.width` settings keys,
  written only after first disclosure exactly as the source's disclosure
  flag gates it. The unified toolbar's search field maps to an
  `AutoSuggestBox` in the window's `TitleBar`/`CommandBar`, toggling
  `IsEnabled` the same way the search field's enabled state is toggled in
  source; the arrange and settings buttons map to two `AppBarButton`s in a
  `CommandBar`, with the arrange toggle using an `AppBarToggleButton`'s
  `IsChecked` visual state in place of the source's tint-plus-button-state
  combination.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsWindowController.swift` |

## Design Decisions

**Decision**: Persist the edge top-up after `installInitialTabs()` restores
the active tab, never before it. (AppKit/UIKit.)
**Rationale**: `persistAllTabs()` writes whichever tab is active at the
moment it runs; writing before the restore would capture the tab that
`insertTab` auto-selected (the first tab of the first enabled edge) instead
of the project's remembered selection, and the next launch would silently
open on the wrong tab even though the current session looked correct.
**Approved**: pending

**Decision**: Suppress `didSelectTab`'s persist, focus-restore, and
chrome-refresh side effects while `reloadTabs()`'s removal loop is running
(`isReloadingTabs`). (AppKit/UIKit.)
**Rationale**: `removeTab` fires `didSelectTab` for whichever member it
activates next; running the full side-effect chain mid-loop would persist a
shrinking, half-removed tab set, schedule first-responder work against a
split about to be discarded, and recompute chrome against tabs that are
half gone.
**Approved**: pending

**Decision**: Debounce the focused-leaf persist by 250ms while persisting
every structural change (split, close, add, remove, reorder, select, edge
toggle) synchronously.
**Rationale**: a divider position is something the user placed by hand and
expects to find again; the focused leaf is a first-responder position the
next launch re-derives on its own, so only it can tolerate — and benefits
from — coalesced writes.
**Approved**: pending

**Decision**: Flush any pending divider-thickness persist during
`windowWillClose` before raising `isClosing`, gated on the project already
having stored tabs. (AppKit/UIKit.)
**Rationale**: a window closed before its project finished opening has a
pending thickness write armed by the very first, placeholder layout pass;
flushing it unconditionally would overwrite a project that has never been
saved with a placeholder arrangement, so the flush only runs when
`storedTabs() != nil`.
**Approved**: pending

**Decision**: Write the help drawer's remembered tab and width only after
`hasDisclosedHelp` becomes true, never on window close alone. (AppKit/UIKit.)
**Rationale**: `setSetting` treats "never set" and "reset to the default"
identically; writing a default row on every window close for a project
whose help was never opened would be indistinguishable from the user having
explicitly chosen that default.
**Approved**: pending

**Decision**: When the enabled-edge set is assigned, enable every named
edge before disabling any edge not named.
**Rationale**: the edge-enable setter (`setEdgeEnabled` in source) refuses
to disable the last enabled edge; processing removals before additions
would make some legal reassignments (for example, moving the only enabled
edge from top to bottom) fail, because the source edge would still read as
"the last one" at the moment its disable is attempted.
**Approved**: pending

**Decision**: Ship every user-facing string in this file — toolbar and
titlebar labels, the help topic bodies, and the default tab title
`"Tab \(n)"` — as a hardcoded English literal rather than routing them
through a localization key now. (The `NSLocalizedString`/string-catalog
mechanism referenced below is AppKit/UIKit-specific; the decision itself
applies regardless of platform.)
**Rationale**: the window predates this project's localization pass, so
none of these strings has a translation to diverge from yet, and routing
them through `NSLocalizedString`/a string catalog today would be
speculative work with nothing to validate it against. `Localization` above
enumerates the literals so the conversion has a ready checklist; the payoff
trigger for doing it is the product actually shipping a non-English build.
**Approved**: pending

**Decision**: Do not add error handling, logging, or retry around
`project.setSetting(_:to:)` or `project.persistTabs(...)` failures in this
window. (AppKit/UIKit.)
**Rationale**: both calls already swallow their own errors one layer down,
in `ProjectWorkspace`; this window has no additional recovery to offer and
no user-facing affordance to retry a settings write from a window
controller. The payoff trigger for revisiting this is a workflow that
depends on a persist actually succeeding (for example cross-device sync),
or a reported case of state loss that traces back to a swallowed write —
neither has occurred yet.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [focus-management](agenticdevelopercookbook://compliance/accessibility#focus-management) | passed | accessibility |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | privacy-and-data |
| [data-retention-policy](agenticdevelopercookbook://compliance/privacy-and-data#data-retention-policy) | passed | privacy-and-data |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |

The accessibility passes rest on the explicit accessibility
descriptions, keyboard-focusable controls, and deliberate focus restoration
documented in Accessibility above. The privacy-and-data passes rest on the
Privacy section's inventory of what is collected, locally stored, and its
defined retention. The internationalization failures rest on the same
hardcoded-literal inventory in Localization.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `ComposableTabsWindowController.swift`. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: renamed all requirements to subject-noun form and updated every cross-reference; added a `search-target` requirement to resolve the circular search-target definition; stated the divider-persist debounce timing in `structural-change-persistence`; added `depends-on` entries for the two composed ingredients that have recipes; reformatted Design Decisions to the bold three-line form and added two entries recording hardcoded strings and swallowed persistence errors as accepted debt; corrected Localization from "Not applicable" to applicable-and-unmet; added accessibility, privacy-and-data, and internationalization checks to Compliance and marked `completeness` partial; removed the incorrect UWP `ApplicationView.PreferredLaunchViewSize` reference from the WinUI 3 Platform Note; and extended the Conformance Test Vectors to cover fresh node ids on edge top-up, arrange-button `.state`, the window spec's minimum size, the empty-tab-title footer separator, and the new `search-target` requirement; removed Compliance rows for checks absent from the cookbook catalog |
| 1.1.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/composable-tabs/. |
