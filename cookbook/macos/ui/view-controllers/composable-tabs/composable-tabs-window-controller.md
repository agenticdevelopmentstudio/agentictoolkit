---
id: 55a394e6-9934-404b-941d-25bebbf71378
title: ComposableTabsWindowController
domain: agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'AppKit window controller for a project''s multi-edge tabbed workspace: per-edge
  tab groups, toolbar search, help drawer, and layout persistence.'
platforms:
- swift
- macos
tags:
- composable-tabs
- window-controller
- multi-tab
- macos
- appkit
depends-on:
- agentictoolkit://cookbook/macos/ui/view-controllers/multi-tabbed-view-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-view-controller
related: []
references: []
approved-by: ''
approved-date: ''
---

# ComposableTabsWindowController

## Overview

`ComposableTabsWindowController` (AppKit, macOS) is the top-level window for one
project workspace. Its content is a `MultiTabbedViewController` hosting up to
four docked tab bars — top, right, bottom, left — each tab wrapping a
`ComposableTabsViewController` split-pane tree rooted at a persisted layout.
One project-level "tab" is a *group*: one member tab per currently enabled
edge, all sharing a title and a working directory, so opening, closing, or
renaming a tab acts on the whole group at once rather than on a single bar's
button. The window also owns a unified toolbar (search field, help toggle),
two right-aligned titlebar accessory buttons (arrange mode, project
settings), a bottom status footer, and a per-project help drawer, and it
exposes a scripting-facing surface (`ScriptingTab`, pane/tab lookup, search
and tab-selection accessors) that Cocoa Scripting bridges address directly.

## Behavioral Requirements

- **window-id**: The window id MUST be derived from
  `ComposableTabsWindowController.windowID(for:)`, formatted as
  `"projectWindow.<repo-uuid>"`, so window geometry is persisted per project
  rather than per window class.
- **default-geometry**: With no saved frame for the project, the window MUST
  open at 800×500 points.
- **minimum-size**: The window MUST NOT be resized below 400×300 points.
- **frame-persistence**: The window's frame MUST be saved on move/resize and
  restored the next time a window for the same project id is shown
  (`WindowSpec(persistsFrame: true, ...)`).
- **standard-window-controls**: The window MUST present the close,
  miniaturize, and zoom title-bar buttons and MUST be user-resizable
  (`windowStyleMask = [.titled, .closable, .resizable, .miniaturizable]`).
- **window-title**: The window title MUST be the project's `displayName`.
- **unified-toolbar**: The window MUST install a unified toolbar containing,
  in order, a flexible space, a search field, and a help button.
- **tab-group-creation**: Creating a project tab MUST create one member tab
  on every currently enabled edge, all sharing one title and one working
  directory, and MUST select the first member created.
- **group-close-scope**: Requesting to close any one member tab MUST remove
  every member of its group from every enabled edge.
- **last-group-guard**: The controller MUST NOT close a tab group when it is
  the project's only remaining group.
- **last-edge-guard**: The controller MUST NOT disable an edge when doing so
  would leave every edge disabled.
- **edge-top-up**: Enabling an edge MUST create one member tab per existing
  group on that edge if it does not already have one, using the active
  tab's current split arrangement (with fresh node ids) as the starting
  layout, or the project's layout blueprint if no tab exists yet.
- **title-tab-fallback**: A tab whose data source is `nil`, or whose data
  source declines to supply an item, MUST render as a plain title button
  showing the tab's stored title.
- **arrangement-mirroring**: Whenever the active tab's split tree changes
  shape or a divider moves, the controller MUST apply the same shape and
  sizes — never the same node ids — to every other tab in the project.
- **structural-change-persistence**: A split, pane close, tab
  add/remove/reorder/select, or edge toggle MUST synchronously persist every
  tab's current layout tree, the active tab id, and the enabled-edge set to
  the project. A divider-thickness change is the one exception to that
  synchronous path: `ComposableTabsViewController` debounces it 300ms before
  the resulting layout change reaches this persist, and that pending write is
  flushed explicitly when the window closes (see **divider-flush-on-close**).
- **focused-leaf-debounce**: A change to which leaf pane is focused MUST be
  written to the project no sooner than 250ms after the change settles,
  rather than synchronously.
- **arrange-titlebar-button**: The window MUST show a right-aligned titlebar
  accessory button that toggles arrange mode for the window and is tinted
  with the resolved accent color while arrange mode is enabled.
- **settings-titlebar-button**: The window MUST show a right-aligned
  titlebar accessory button that presents project settings as a sheet on
  the window's content view controller.
- **arrange-menu-state**: A menu item bound to the arrange-mode action MUST
  show a checked state whenever arrange mode is enabled for the window and
  unchecked otherwise.
- **search-target**: The pane the search field targets — the value stored in
  `searchTargetNodeID` — MUST be whichever pane `applySearchAvailability(to:)`
  last computed the field's enabled state and placeholder from. That method
  runs whenever the active pane changes (tab activation, the active-pane
  notification, `showWindow(_:)`), so the target tracks the active pane at
  the moment of the last such refresh, not necessarily whichever pane is
  active at the instant of a keystroke.
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
- **help-glyph-state**: The help button's glyph MUST switch between an
  outlined and a filled `questionmark.circle` symbol depending on whether
  the drawer is disclosed, and its tooltip MUST switch between "Show Help"
  and "Hide Help" to match, while its fixed accessibility name ("Help")
  MUST NOT change.
- **tab-activation-focus**: Activating a project tab MUST restore the first
  responder to that tab's last-focused leaf pane, deferred by one run-loop
  turn so the tab's view hierarchy is mounted first.
- **pane-teardown-on-close**: Closing the window MUST tear down every pane
  in every tab (releasing per-pane resources such as shells or file
  watchers) and MUST stop persisting the tab set from that point on.
- **divider-flush-on-close**: If the project already has stored tabs,
  closing the window MUST flush any pending divider-thickness persist
  before tearing the panes down.
- **reload-persist-suppression**: While `reloadTabs()`'s removal loop is
  running, the controller MUST suppress the persist, focus-restore, and
  chrome-refresh side effects that an intermediate tab-selection change
  would otherwise trigger.
- **pane-enumeration-order**: `allPanes()` MUST return every pane in the
  window ordered by tab, then by edge in `Edge.allCases` order (`top`,
  `right`, `bottom`, `left`), then by each split's own leaf order.
- **scripting-tab-selection**: Setting `selectedTabIdentifier` to a group id
  MUST select that group's member on the first enabled edge that has one,
  and MUST be ignored if the id names no group in this window.
- **redundant-tab-selection-guard**: Selecting a tab that is already active
  MUST NOT re-run tab-activation side effects (focus restore, persist,
  chrome refresh) a second time.
- **edge-set-assignment-order**: Assigning `enabledTabEdgeNames` MUST enable
  every named edge before disabling any edge that is not named, so that
  reassigning the enabled-edge set never fails the last-enabled-edge
  refusal on an intermediate step.

## Appearance

- **Corner radius**: Not applicable — a standard `NSWindow`; the window
  controller draws no custom-cornered chrome.
- **Padding**: The tabbed content's insets are `PaneSpacing.contentInsets`,
  which default to 0pt on all four sides (`pane_spacing_top` /
  `_leading` / `_bottom` / `_trailing`, each `UserSetting<Int>` defaulting to
  `0`) and are user-configurable. The tab bar's own start inset on the left
  and right edges is `insets.top + titleBarBottom`, where `titleBarBottom` =
  2pt (`ComposableTabsPaneBackgroundView.borderInset`) + 26pt
  (`PaneTitleBarView.height`) = 28pt, so a side tab bar's first tab lines up
  with a pane's own title bar rather than floating above it.
- **Font**: Not applicable — the window controller renders no text directly;
  toolbar labels, tab titles, and footer text are drawn by
  `MultiTabbedViewController`, `WindowFooterContentViewController`, and the
  toolbar/drawer components, each a separate ingredient.
- **Background**: The window background is set once, at creation, to
  `ThemePaletteObserver.currentPalette.windowBackgroundColor`. The plane
  behind the split tree tracks the live theme palette's
  `projectPaneBackdrop` (fill) and `projectPaneOutline` (outline) colors via
  a `ThemePaletteObserver` on the tabbed view.
- **Foreground/Text**: Not applicable at this layer — see Font.
- **Border**: Not applicable — standard system window border; no HUD chrome
  is configured for this controller.
- **Shadow**: Not applicable — standard system window shadow.
- **Min/Max size**: Minimum 400×300pt (`minSize`, matching
  `windowSpec.minSize`); no maximum size is set.

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet loaded (`window == nil`): no toolbar or titlebar accessories exist until the first `showWindow(_:)`. |
| Pressed | Not applicable — the window controller itself renders no pressable surface; per-press visuals belong to the `NSButton`/`NSToolbarItem` instances it hosts. |
| Disabled | Search field is disabled and grayed whenever the search target's `isSearchable` is `false` (see **search-availability**, **search-target**). |
| Focused | The active tab's last-focused leaf pane holds first responder, restored on tab activation and on `showWindow(_:)`. |
| Loading | Not applicable — tab and pane installation is synchronous; no loading/spinner state exists in source. |
| Arrange mode enabled | Arrange titlebar button shows accent tint and `.state = .on` (pressed-looking bezel); the bound menu item shows a checkmark. |
| Arrange mode disabled | Arrange titlebar button shows no tint and `.state = .off`; the menu item shows no checkmark. |
| Help drawer open | Help toolbar button shows the filled `questionmark.circle.fill` glyph, accent tint, and tooltip "Hide Help". |
| Help drawer closed | Help toolbar button shows the outlined `questionmark.circle` glyph, secondary-text tint, and tooltip "Show Help". |
| Single remaining tab group | The tab-close affordance for that group's members MUST have no effect (see **last-group-guard**). |
| Last enabled edge | The settings toggle for that edge MUST have no effect (see **last-edge-guard**). |

## Accessibility

- Role/traits: standard `NSWindow` with title-bar close/miniaturize/zoom
  buttons; toolbar and titlebar-accessory controls are plain `NSButton`s
  (custom-view toolbar items, since `NSToolbarItem` is not itself
  accessible) and a system `NSSearchField`.
- Accessibility identifiers: the search field and help button carry the
  toolbar identifiers `project.toolbar.search` and `project.toolbar.help`;
  the titlebar accessories carry `project-window.arrange-button` and
  `project-window.project-settings-button`.
- Label requirements: the help button's accessibility description is fixed
  at "Help" and does not change when its glyph/tooltip swap for open vs.
  closed; the arrange and settings buttons carry the accessibility
  descriptions "Arrange Panes" and "Project Settings"; the search field's
  placeholder is the search target's `searchPlaceholder` or "Search" when
  none applies.
- Announce state changes: the help toggle communicates its open/closed
  state through symbol shape (outline vs. filled) and tooltip text, not
  tint alone; the arrange toggle communicates its state through `NSButton`
  state (`.on`/`.off`, which AppKit renders as a pressed bezel on
  `.texturedRounded`) in addition to tint.
- Minimum control size: macOS is a pointer-driven platform with no mandated
  minimum touch-target size; the titlebar accessory buttons are built at
  36×24pt and the toolbar icon buttons follow `NSToolbar`'s standard
  icon-only sizing, consistent with this codebase's other toolbar/titlebar
  controls rather than a value this component decides on its own.
- Keyboard/focus: the titlebar and toolbar buttons are ordinary
  keyboard-focusable `NSButton`s (Space/Return activate); the search field
  is a standard `NSSearchField` with normal text-field key handling; the
  arrange action is additionally reachable through any menu item bound to
  `toggleArrangeMode(_:)`, validated by `NSMenuItemValidation`.
- Color/contrast: chrome colors are read from the shared theme palette
  (`ThemePaletteObserver`); contrast is a design-system-level concern
  outside this controller's own decisions, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-window-controller-001 | window-id | Two `ComposableTabsWindowController`s built for repo ids A and B | Their `windowID(for:)` values are `"projectWindow.A"` and `"projectWindow.B"`; each window's saved frame is independent. |
| composable-tabs-window-controller-002 | default-geometry | Show the window for a project with no prior saved frame | Window frame size is 800×500pt. |
| composable-tabs-window-controller-003 | minimum-size | Attempt to resize the window below 400×300pt | Window stops at 400×300pt. |
| composable-tabs-window-controller-004 | frame-persistence | Move/resize the window, close it, build a new controller for the same project id and show it | New window opens at the previously saved frame. |
| composable-tabs-window-controller-005 | standard-window-controls | Inspect the shown window | Close, miniaturize, and zoom buttons are present and enabled; window is resizable by the user. |
| composable-tabs-window-controller-006 | window-title | Project `displayName` is `"Zorkapp"` | Window title reads `"Zorkapp"`. |
| composable-tabs-window-controller-007 | unified-toolbar | Inspect the shown window's toolbar | `toolbarStyle == .unified`; item order is flexible space, search, help. |
| composable-tabs-window-controller-008 | tab-group-creation | Top and left edges enabled; call `addTabGroup()` | A new group has one member on top and one on left, same title, same working directory; the top member is selected. |
| composable-tabs-window-controller-009 | group-close-scope | Two-member group (top, left); request close on the top member | Both the top and left members are removed. |
| composable-tabs-window-controller-010 | last-group-guard | Exactly one tab group exists; request its close | The group remains; tab count is unchanged. |
| composable-tabs-window-controller-011 | last-edge-guard | Only `.top` is enabled; call `setEdgeEnabled(.top, false)` | `.top` remains enabled. |
| composable-tabs-window-controller-012 | edge-top-up | Two groups exist, only `.top` enabled; enable `.right` | `.right` gains one member per existing group, each seeded from the current active tab's arrangement with fresh node ids — none of the new members reuses a node id from the tab they were seeded from. |
| composable-tabs-window-controller-013 | title-tab-fallback | `tabItemDataSource` is `nil`; a tab titled `"Tab 2"` is created | The tab renders `.title("Tab 2")`. |
| composable-tabs-window-controller-014 | arrangement-mirroring | Two tabs exist; drag a divider in the active tab | The other tab's split adopts the same shape and sizes, with its own node ids preserved. |
| composable-tabs-window-controller-015 | structural-change-persistence | Reorder a tab | `project.persistTabs` is invoked synchronously with the new order. |
| composable-tabs-window-controller-016 | focused-leaf-debounce | Change focused leaf twice within 100ms | Only one persist occurs, at least 250ms after the second change. |
| composable-tabs-window-controller-017 | arrange-titlebar-button | Toggle arrange mode on | Arrange button shows accent tint and `.state == .on`. |
| composable-tabs-window-controller-018 | settings-titlebar-button | Click the settings titlebar button | `ComposableTabsSettingsViewController` is presented as a sheet. |
| composable-tabs-window-controller-019 | arrange-menu-state | Arrange mode enabled for the window; validate the bound menu item | Menu item state is `.on`. |
| composable-tabs-window-controller-020 | search-routing | Search target is pane P; type `"foo"` | `P.search(for: "foo")` is called. |
| composable-tabs-window-controller-021 | search-availability | Search target's `isSearchable == false` | Search field `isEnabled == false`. |
| composable-tabs-window-controller-022 | search-target-clearing | Field contains `"foo"`; search target changes to a different searchable pane | Field text becomes `""`. |
| composable-tabs-window-controller-023 | status-footer-content | Project `"Zork"`, tab `"Main"`, pane title `"main.swift"`, no selection description | Footer reads `"Zork › Main › main.swift"`. |
| composable-tabs-window-controller-024 | help-drawer-toggle | Drawer closed; invoke `toggleHelp()` | Drawer opens; invoking again closes it. |
| composable-tabs-window-controller-025 | help-visibility-persistence | Open help, close window, reopen a window for the same project | Drawer reopens automatically. |
| composable-tabs-window-controller-026 | help-tab-width-persistence | Help never opened in this window; close the window | No `drawer.tab`/`drawer.width` setting is written. |
| composable-tabs-window-controller-027 | help-glyph-state | Open the help drawer | Help button glyph is `questionmark.circle.fill`, tooltip "Hide Help", accessibility description still "Help". |
| composable-tabs-window-controller-028 | tab-activation-focus | Tab T's last focus was leaf L; activate T | First responder becomes L's view, one run-loop turn after activation. |
| composable-tabs-window-controller-029 | pane-teardown-on-close | Window has a terminal pane with a running shell; close the window | The shell is terminated (`paneWillBeRemoved()`/`tearDownPanes()` runs for every pane). |
| composable-tabs-window-controller-030 | divider-flush-on-close | Project has stored tabs; drag a divider, then close the window within 300ms | The dragged thickness is persisted before teardown. |
| composable-tabs-window-controller-031 | reload-persist-suppression | Call `reloadTabs()` on a window with 3 tabs | No intermediate persist writes a partial tab set; exactly one persist reflects the final reloaded state. |
| composable-tabs-window-controller-032 | pane-enumeration-order | Two tabs, each split into two panes on `.top` and `.left` | `allPanes()` returns tab-1's panes (top before left, leaf order), then tab-2's, in the same order on repeated calls. |
| composable-tabs-window-controller-033 | scripting-tab-selection | Set `selectedTabIdentifier` to an existing group's id enabled only on `.bottom` | That group's `.bottom` member becomes active. |
| composable-tabs-window-controller-034 | redundant-tab-selection-guard | Tab T is already active; call `selectTab(id: T)` again | No additional persist, focus-restore, or chrome refresh occurs. |
| composable-tabs-window-controller-035 | edge-set-assignment-order | Only `.top` enabled; set `enabledTabEdgeNames = ["bottom"]` | `.bottom` becomes enabled before `.top` is disabled; final state is `.bottom` only. |
| composable-tabs-window-controller-036 | minimum-size | Inspect the controller's `windowSpec` before the window is ever shown | `windowSpec.minSize == NSSize(width: 400, height: 300)`, matching `self.minSize`. |
| composable-tabs-window-controller-037 | status-footer-content | Project `"Zork"`, active tab's title is `""` (empty), pane title `"main.swift"`, no selection description | Footer reads `"Zork › main.swift"` — the empty tab title contributes no leading `" › "`. |
| composable-tabs-window-controller-038 | search-target | The active pane changes from pane A to pane B, triggering `applySearchAvailability(to:)` | `searchTargetNodeID` becomes B's `nodeID`, matching the field's newly computed `isEnabled`/placeholder. |

## Edge Cases

- **Null/empty input**: `selectTab(id:)` and the `selectedTabIdentifier`
  setter with an id that names no group in this window MUST be ignored
  (MUST) rather than clearing the current selection. `panes(inTab:)` with an
  unparsable or unknown identifier MUST return an empty array (MUST). An
  `enabledTabEdgeNames` assignment MUST NOT trip the last-enabled-edge
  refusal partway through, because enables are applied before disables
  (MUST) — see **edge-set-assignment-order**.
- **Boundary values**: exactly one remaining tab group MUST refuse to close
  (MUST); exactly one remaining enabled edge MUST refuse to disable (MUST).
  These are the only two lower-bound guards in the source; no upper bound on
  tab or edge count exists.
- **Concurrent access**: the controller is `@MainActor`-isolated; every
  mutation (tab add/remove/select, edge toggle, persistence) runs on the
  main actor, so there is no defined behavior for access from another
  thread — none is needed, because AppKit view controllers are inherently
  single-threaded. Within the main actor, reentrancy during a single
  operation is guarded explicitly: `isReloadingTabs` suppresses side effects
  while `reloadTabs()` removes tabs, `isMirroringArrangement` stops the
  arrangement mirror from recursing into itself, and `isClosing` stops a
  closing window's own teardown from re-persisting a stale tab set (MUST for
  each guard, as implemented).
- **Error states**: `project.setSetting(_:to:)` and `project.persistTabs(...)`
  are called without checking a return value or catching an error anywhere
  in this file; per the source's own comments, `setSetting` "swallows its
  errors." A persistence failure therefore produces no user-facing error, no
  retry, and no logged diagnostic — this is what the source does, not an
  idealized error-handling requirement. This is recorded as accepted debt in
  Design Decisions above, not treated as an unresolved gap.
- **Offline/disconnected state**: Not applicable — the controller performs
  no network requests; all persistence (window frame, tab layout, drawer
  prefs) is local.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `project` | `ProjectWorkspace` | required | The project workspace this window displays; supplies id, display name, directory, initial tabs, and local settings storage. |
| `tabItemDataSource` | `ComposableTabsTabItemDataSource?` | `nil` | Supplies each tab's edge-bar item; `nil` falls back to a plain title button (see **title-tab-fallback**). |

## Deep Linking

Not applicable: no URL-scheme or `NSUserActivity` handling appears anywhere
in `ComposableTabsWindowController.swift`. The window is opened only by
project-management code constructing it directly.

## Localization

Applicable, and unmet: every user-facing string in this file — `"Search"`,
`"Help"`, `"Show Help"` / `"Hide Help"`, `"Arrange Panes"`, `"Project
Settings"`, `"Panes"`/`"Minimizing"`/`"Zoom"`/etc. help topic bodies, and the
default tab title `"Tab \(n)"` — is a hardcoded English literal. The source
contains no localization key lookup (no `NSLocalizedString`, no string
catalog reference). This is recorded as accepted debt in Design Decisions
above, and is reflected in Compliance below (`string-externalization`,
`no-hardcoded-strings`).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the window controller performs no animated transitions of its own; tab installation, arrangement mirroring, and drawer open/close are owned by `MultiTabbedViewController` and `WindowDrawer`, each a separate ingredient. |
| Increase Contrast | Not applicable: chrome colors are sourced from the shared theme palette (`ThemePaletteObserver`); contrast handling is a design-system-level concern this controller does not decide. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by symbol shape (outline vs. filled `questionmark.circle`) and tooltip text, not by tint alone; the arrange toggle differentiates on/off by `NSButton.state` (rendered as a pressed bezel on `.texturedRounded`) in addition to tint. |

## Feature Flags

Not applicable: no flag-gated behavior (`FeatureFlag`, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging calls appear in this file.

## Privacy

- **Data collected**: the window's frame (position and size) keyed by
  project id; the project's full tab layout (`TabRecord` list — split tree,
  titles, working directories, focused leaf id, active tab id, enabled
  edges); the help drawer's per-project preferences (`drawer.open`,
  `drawer.tab`, `drawer.width`, stored under `project_setting`).
- **Storage**: window frame is stored locally via
  `WindowManager.shared.frames`, keyed by `windowID(for:)`; tab layout and
  drawer preferences are stored locally via `project.persistTabs(...)` and
  `project.setSetting(_:to:)` in the project's own settings/database. No
  networked store is used anywhere in this file.
- **Transmission**: none. No networking import or call appears in this file;
  everything persisted here stays on the local device.
- **Retention**: the window frame persists until the project's saved window
  state is cleared (`WindowFrameManager.clearSavedState(for:)`, per the
  comment on `windowID(for:)`). Tab layout and drawer preferences persist
  until overwritten or the project is deleted. Drawer tab/width are written
  only after help has been disclosed at least once
  (`hasDisclosedHelp`); a project whose help was never opened stores none of
  that preference.

## Logging

Not applicable: no `Logger`/`os_log`/print-based logging calls appear
anywhere in `ComposableTabsWindowController.swift`.

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
  whichever pane component is currently "the search target," mirroring
  `searchTargetNodeID`; window-frame persistence has no web equivalent
  (the browser owns window chrome) and would be dropped, keeping only the
  tab-layout and drawer-preference persistence.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists in source. Files: this file
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
  `windowID(for:)`. There is no WinUI drawer primitive for the help panel;
  use a `SplitView` in `Inline` or `CompactOverlay` display mode pinned to a
  window edge, with `IsPaneOpen`/`OpenPaneLength` bound to the same
  per-project `drawer.open`/`drawer.width` settings keys, written only after
  first disclosure exactly as `hasDisclosedHelp` gates it here. The unified
  toolbar's search field maps to an `AutoSuggestBox` in the window's
  `TitleBar`/`CommandBar`, toggling `IsEnabled` the same way
  `NSSearchField.isEnabled` is toggled; the arrange and settings buttons map
  to two `AppBarButton`s in a `CommandBar`, with the arrange toggle using an
  `AppBarToggleButton`'s `IsChecked` visual state in place of AppKit's
  tint-plus-`NSButton.state` combination.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsWindowController.swift` |

## Design Decisions

**Decision**: Persist the edge top-up after `installInitialTabs()` restores
the active tab, never before it.
**Rationale**: `persistAllTabs()` writes whichever tab is active at the
moment it runs; writing before the restore would capture the tab that
`insertTab` auto-selected (the first tab of the first enabled edge) instead
of the project's remembered selection, and the next launch would silently
open on the wrong tab even though the current session looked correct.
**Approved**: pending

**Decision**: Suppress `didSelectTab`'s persist, focus-restore, and
chrome-refresh side effects while `reloadTabs()`'s removal loop is running
(`isReloadingTabs`).
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
having stored tabs.
**Rationale**: a window closed before its project finished opening has a
pending thickness write armed by the very first, placeholder layout pass;
flushing it unconditionally would overwrite a project that has never been
saved with a placeholder arrangement, so the flush only runs when
`storedTabs() != nil`.
**Approved**: pending

**Decision**: Write the help drawer's remembered tab and width only after
`hasDisclosedHelp` becomes true, never on window close alone.
**Rationale**: `setSetting` treats "never set" and "reset to the default"
identically; writing a default row on every window close for a project
whose help was never opened would be indistinguishable from the user having
explicitly chosen that default.
**Approved**: pending

**Decision**: When `enabledTabEdgeNames` is assigned, enable every named
edge before disabling any edge not named.
**Rationale**: `setEdgeEnabled` refuses to disable the last enabled edge;
processing removals before additions would make some legal reassignments
(for example, moving the only enabled edge from top to bottom) fail,
because the source edge would still read as "the last one" at the moment
its disable is attempted.
**Approved**: pending

**Decision**: Ship every user-facing string in this file — toolbar and
titlebar labels, the help topic bodies, and the default tab title
`"Tab \(n)"` — as a hardcoded English literal rather than routing them
through a localization key now.
**Rationale**: the window controller predates this project's localization
pass, so none of these strings has a translation to diverge from yet, and
routing them through `NSLocalizedString`/a string catalog today would be
speculative work with nothing to validate it against. `Localization` above
enumerates the literals so the conversion has a ready checklist; the payoff
trigger for doing it is the product actually shipping a non-English build.
**Approved**: pending

**Decision**: Do not add error handling, logging, or retry around
`project.setSetting(_:to:)` or `project.persistTabs(...)` failures in this
controller.
**Rationale**: both calls already swallow their own errors one layer down,
in `ProjectWorkspace`; this controller has no additional recovery to offer
and no user-facing affordance to retry a settings write from a window
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
