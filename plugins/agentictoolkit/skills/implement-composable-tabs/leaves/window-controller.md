<!-- leaf: implement-composable-tabs/window-controller · source: composable-tabs-window-controller.md -->

**Rules** (cite as `implement-composable-tabs/window-controller#<slug>`):

- `window-id` MUST
- `default-geometry` MUST
- `minimum-size` MUST
- `frame-persistence` MUST
- `standard-window-controls` MUST
- `window-title` MUST
- `unified-toolbar` MUST
- `tab-group-creation` MUST
- `group-close-scope` MUST
- `last-group-guard` MUST
- `last-edge-guard` MUST
- `edge-top-up` MUST
- `title-tab-fallback` MUST
- `arrangement-mirroring` MUST
- `structural-change-persistence` MUST
- `focused-leaf-debounce` MUST
- `arrange-titlebar-button` MUST
- `settings-titlebar-button` MUST
- `arrange-menu-state` MUST
- `search-target` MUST
- `search-routing` MUST
- `search-availability` MUST
- `search-target-clearing` MUST
- `status-footer-content` MUST
- `help-drawer-toggle` MUST
- `help-visibility-persistence` MUST
- `help-tab-width-persistence` MUST
- `help-glyph-state` MUST
- `tab-activation-focus` MUST
- `pane-teardown-on-close` MUST
- `divider-flush-on-close` MUST
- `reload-persist-suppression` MUST
- `pane-enumeration-order` MUST
- `scripting-tab-selection` MUST
- `redundant-tab-selection-guard` MUST
- `edge-set-assignment-order` MUST

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

