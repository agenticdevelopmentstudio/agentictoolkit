<!-- leaf: implement-settings/window · source: settings-window.md -->

**Rules** (cite as `implement-settings/window#<slug>`):

- `identifies-window-as-settings` MUST
- `titles-window-settings` MUST
- `hides-window-title-visibility` MUST
- `uses-full-size-content-view-style-mask` MUST
- `suppresses-sidebar-title` MUST
- `shows-sidebar-search` MUST
- `sorts-panels-alphabetically` MUST
- `exposes-setting-panels` MUST
- `activates-app-on-show-by-default` MUST
- `allows-subclass-to-disable-activation` MAY
- `skips-activation-when-disabled` MUST
- `shows-quietly-under-quiet-presentation` MUST
- `activates-and-keys-window-normally` MUST
- `attaches-help-drawer-presenter` MUST
- `installs-unified-toolbar-chrome` MUST
- `fixes-toolbar-item-order` MUST
- `hides-inline-help-button` MUST
- `builds-back-forward-as-one-control` MUST
- `routes-segment-selection-to-navigation` MUST
- `syncs-navigation-control-enablement` MUST
- `shows-current-panel-title` MUST
- `renders-panel-title-as-single-line-heading` MUST
- `shows-outline-glyph-when-drawer-closed` MUST
- `shows-filled-glyph-when-drawer-open` MUST
- `tints-help-button-by-drawer-state` MUST
- `swaps-help-tooltip-by-drawer-state` MUST
- `keeps-help-accessibility-name-stable` MUST
- `updates-help-glyph-on-visibility-change` MUST
- `updates-help-glyph-on-navigation-change` MAY
- `wires-help-only-for-inserted-item` MUST
- `anchors-help-presenter-to-button` MUST
- `tracks-theme-live-on-help-button` MUST
- `toggles-help-on-click` MUST
- `builds-tracking-separator-from-splitview` MUST
- `assigns-high-visibility-to-primary-items` MUST
- `returns-nil-for-unknown-toolbar-identifier` MUST

# SettingsWindow

## Overview

`ComposableSettings.SettingsWindow` (`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsWindow.swift`)
is a reusable AppKit window controller for one app-wide Settings window,
shaped like macOS System Settings: an always-alphabetical topic sidebar with
its own search field on the left, and the selected panel's content on the
right, with the sidebar running the window's full height under a transparent,
unified toolbar. The toolbar carries a two-segment back/forward control, the
name of the panel currently on screen, and a help toggle that discloses a
per-window help drawer. A host subclasses `SettingsWindow` and supplies its
panels through the `settingPanels` property (see Configuration); see Design
Decisions for a source-fidelity note on the class's own doc comment, which
still illustrates configuration a different way.

## Behavioral Requirements

- **identifies-window-as-settings**: The window MUST be registered under the
  fixed window id `"settings"`, so the app tracks one Settings window rather
  than one per instance.
- **titles-window-settings**: The window's `windowTitle` MUST be `"Settings"`.
- **hides-window-title-visibility**: The window's `titleVisibility` MUST be
  set to `.hidden`, deferring to the toolbar's panel-title item to show what
  is on screen.
- **uses-full-size-content-view-style-mask**: The window's style mask MUST be
  `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`,
  so the sidebar can run the full height of the window under the titlebar.
- **suppresses-sidebar-title**: The hosted split's `sidebarTitle` MUST be
  `nil`.
- **shows-sidebar-search**: The hosted split's `showsSidebarSearch` MUST be
  `true`.
- **sorts-panels-alphabetically**: The hosted split's `sortsPanelsByTitle`
  MUST be `true`, so panels always list in alphabetical order regardless of
  registration order.
- **exposes-setting-panels**: The `settingPanels` property MUST get and set
  the hosted split's panel list (`viewController?.panels`,
  `viewController?.setPanels(_:)`), returning an empty array before the split
  has loaded.
- **activates-app-on-show-by-default**: `activatesOnShow` MUST default to
  `true`.
- **allows-subclass-to-disable-activation**: A subclass MAY override
  `activatesOnShow` to return `false` when it does not want `showWindow()` to
  activate the app.
- **skips-activation-when-disabled**: When `activatesOnShow` is `false`,
  `showWindow()` MUST call `super.showWindow()` and then return, without
  calling `NSApp.activate` or making the window key itself.
- **shows-quietly-under-quiet-presentation**: When `activatesOnShow` is
  `true` and `QuietWindowPresentation.isEnabled` is `true`, `showWindow()`
  MUST call `window?.makeKeyAndOrderFrontQuietly()` and MUST NOT call
  `NSApp.activate` or order the window above other applications' windows.
- **activates-and-keys-window-normally**: When `activatesOnShow` is `true`
  and quiet presentation is not enabled, `showWindow()` MUST call
  `NSApp.activate(ignoringOtherApps: true)` followed by
  `window?.makeKeyAndOrderFront(nil)`.
- **attaches-help-drawer-presenter**: `configureWindow(_:)` MUST construct a
  `HelpDrawerController(parentWindow:)` from the window being configured and
  assign it to the hosted split's `helpPresenter`.
- **installs-unified-toolbar-chrome**: `configureWindow(_:)` MUST install an
  `NSToolbar` identified `"ComposableSettings.Toolbar"` with
  `displayMode = .iconOnly` and `allowsUserCustomization = false`, and MUST
  set the window's `toolbarStyle` to `.unified`,
  `titlebarAppearsTransparent` to `true`, and `titlebarSeparatorStyle` to
  `.none`.
- **fixes-toolbar-item-order**: `toolbarDefaultItemIdentifiers` and
  `toolbarAllowedItemIdentifiers` MUST both return the same fixed list, in
  order: the sidebar tracking separator, the back/forward navigation item,
  the panel-title item, a flexible space, and the help item.
- **hides-inline-help-button**: `configureWindow(_:)` MUST set the hosted
  split's `showsInlineHelpButton` to `false`, since the toolbar supplies the
  window's one help control.
- **builds-back-forward-as-one-control**: The back/forward toolbar item's
  view MUST be a single momentary, `.separated`-style `NSSegmentedControl`
  with two segments — `chevron.backward` labeled "Back" and
  `chevron.forward` labeled "Forward" — carrying one combined accessibility
  label, "Back and forward", rather than two independent buttons.
- **routes-segment-selection-to-navigation**: Selecting segment `0` on the
  navigation control MUST call `goBack()`; selecting segment `1` MUST call
  `goForward()`; any other selected-segment value, including no selection
  (`-1`), MUST trigger neither.
- **syncs-navigation-control-enablement**: Whenever `onNavigationChange`
  fires, the navigation control's back segment MUST be enabled to match
  `canGoBack` and its forward segment MUST be enabled to match
  `canGoForward`, each set independently, because a custom-view toolbar item
  receives no AppKit validation pass.
- **shows-current-panel-title**: Whenever `onNavigationChange` fires, the
  panel-title label's text MUST be set to `currentPanelTitle ?? ""`.
- **renders-panel-title-as-single-line-heading**: The panel-title label MUST
  be a non-editable, single-line `ThemedLabel` using the `.heading` text
  role and the `.primaryText` color role, truncating overflow with
  `.byTruncatingTail`, and MUST hug content horizontally at `.defaultHigh`.
- **shows-outline-glyph-when-drawer-closed**: While the help drawer is
  closed, the help button's image MUST be the outline `questionmark.circle`
  SF Symbol.
- **shows-filled-glyph-when-drawer-open**: While the help drawer is open,
  the help button's image MUST be the filled `questionmark.circle.fill` SF
  Symbol.
- **tints-help-button-by-drawer-state**: The help button's
  `contentTintColor` MUST be the resolved theme palette's
  `secondaryTextColor` while the drawer is closed and its `accentColor`
  while the drawer is open.
- **swaps-help-tooltip-by-drawer-state**: The help button's tooltip MUST
  read "Show Help" while the drawer is closed and "Hide Help" while the
  drawer is open.
- **keeps-help-accessibility-name-stable**: The help button image's
  accessibility description MUST remain "Help" across every glyph swap; it
  MUST NOT change to match the tooltip text.
- **updates-help-glyph-on-visibility-change**: Whenever
  `onHelpVisibilityChange` fires, the help button's glyph, tint, and tooltip
  MUST be refreshed to match the drawer's current visibility.
- **updates-help-glyph-on-navigation-change**: Whenever `onNavigationChange`
  fires, the help button's glyph, tint, and tooltip MAY also be refreshed,
  since the current implementation shares one refresh path with navigation
  enablement and the panel title; an implementer is not required to refresh
  the help button on navigation alone (see Platform Notes, AppKit / UIKit,
  for the shared private method this rides on).
- **wires-help-only-for-inserted-item**: The help toolbar item's button
  reference, its live theme observer, and the help-anchor-view assignment
  MUST be attached only when the toolbar factory's
  `willBeInsertedIntoToolbar` flag is `true` — never for the
  customization-palette sample or a rebuild pass — so a discarded copy
  cannot leave the tracked help button pointing at a view that is off
  screen.
- **anchors-help-presenter-to-button**: When the help item is actually
  inserted, its button MUST be assigned to `helpPresenter?.helpAnchorView`.
- **tracks-theme-live-on-help-button**: The inserted help button MUST
  re-apply its glyph/tint/tooltip whenever the resolved theme palette
  changes, via a live `ThemePaletteObserver` on that button, not only once
  at construction.
- **toggles-help-on-click**: Clicking the help button MUST call
  `viewController?.toggleHelp()`.
- **builds-tracking-separator-from-splitview**: The sidebar tracking
  separator toolbar item MUST be an `NSTrackingSeparatorToolbarItem` bound
  to the hosted split's `splitView` at divider index `0`, and MUST be `nil`
  if the split currently has no split view.
- **assigns-high-visibility-to-primary-items**: The navigation item, the
  panel-title item, and the help item MUST each set
  `visibilityPriority = .high`.
- **returns-nil-for-unknown-toolbar-identifier**: The toolbar item factory
  MUST return `nil` for any `NSToolbarItem.Identifier` outside the fixed
  list in **fixes-toolbar-item-order**.

