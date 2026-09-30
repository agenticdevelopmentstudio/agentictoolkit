<!-- leaf: implement-settings/window--test-vectors · source: settings-window.md -->

# SettingsWindow

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-window-001 | identifies-window-as-settings | Construct a `SettingsWindow` | `windowID == "settings"`. |
| settings-window-002 | titles-window-settings | Construct a `SettingsWindow` | `windowTitle == "Settings"`. |
| settings-window-003 | hides-window-title-visibility | Show the window | `window.titleVisibility == .hidden`. |
| settings-window-004 | uses-full-size-content-view-style-mask | Inspect `windowStyleMask` after construction | Equals `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`. |
| settings-window-005 | suppresses-sidebar-title | Construct a `SettingsWindow` | `viewController?.sidebarTitle == nil`. |
| settings-window-006 | shows-sidebar-search | Construct a `SettingsWindow` | `viewController?.showsSidebarSearch == true`. |
| settings-window-007 | sorts-panels-alphabetically | Construct a `SettingsWindow` | `viewController?.sortsPanelsByTitle == true`. |
| settings-window-008 | exposes-setting-panels | Assign `settingPanels = [panelB, panelA]` | `viewController?.panels` reflects the assignment via `setPanels(_:)`. |
| settings-window-009 | activates-app-on-show-by-default | Construct a `SettingsWindow` subclass with no override | `activatesOnShow == true`. |
| settings-window-010 | allows-subclass-to-disable-activation | Subclass overrides `activatesOnShow` to `false` | The override value is honored (`activatesOnShow == false`). |
| settings-window-011 | skips-activation-when-disabled | `activatesOnShow == false`; call `showWindow()` | `NSApp.activate` is not called, and the override returns immediately after `super.showWindow()` without any further window operation of its own. |
| settings-window-012 | shows-quietly-under-quiet-presentation | `activatesOnShow == true`; `QuietWindowPresentation.isEnabled == true`; call `showWindow()` | `window.makeKeyAndOrderFrontQuietly()` is called; `NSApp.activate` is not. |
| settings-window-013 | activates-and-keys-window-normally | `activatesOnShow == true`; quiet presentation disabled; call `showWindow()` | `NSApp.activate(ignoringOtherApps: true)` then `window.makeKeyAndOrderFront(nil)` are called. |
| settings-window-014 | attaches-help-drawer-presenter | Trigger `configureWindow(_:)` (first `showWindow()`) | `viewController?.helpPresenter` is a `HelpDrawerController` built with that window as `parentWindow`. |
| settings-window-015 | installs-unified-toolbar-chrome | Trigger `configureWindow(_:)` | `window.toolbarStyle == .unified`, toolbar identifier `"ComposableSettings.Toolbar"`, `displayMode == .iconOnly`, `allowsUserCustomization == false`, `titlebarAppearsTransparent == true`, `titlebarSeparatorStyle == .none`. |
| settings-window-016 | fixes-toolbar-item-order | Read `toolbarDefaultItemIdentifiers` and `toolbarAllowedItemIdentifiers` | Both equal `[.sidebarTrackingSeparator, .settingsNavigation, .settingsPanelTitle, .flexibleSpace, .settingsHelp]`. |
| settings-window-017 | hides-inline-help-button | Trigger `configureWindow(_:)` | `viewController?.showsInlineHelpButton == false`. |
| settings-window-018 | builds-back-forward-as-one-control | Inspect the navigation toolbar item's view | One `NSSegmentedControl`, `trackingMode == .momentary`, `segmentStyle == .separated`, 2 segments, accessibility label "Back and forward". |
| settings-window-019 | routes-segment-selection-to-navigation | Select segment 0, then segment 1, then simulate `selectedSegment == -1` | `goBack()` called once, `goForward()` called once, no call on the third case. |
| settings-window-020 | syncs-navigation-control-enablement | `canGoBack == false`, `canGoForward == true`; fire `onNavigationChange` | Back segment disabled, forward segment enabled. |
| settings-window-021 | shows-current-panel-title | `currentPanelTitle == "General"`; fire `onNavigationChange` | Panel-title label text is `"General"`. |
| settings-window-022 | renders-panel-title-as-single-line-heading | Inspect the panel-title label | Non-editable, `lineBreakMode == .byTruncatingTail`, horizontal content-hugging `.defaultHigh`, role `.primaryText`, text role `.heading`. |
| settings-window-023 | shows-outline-glyph-when-drawer-closed | `isHelpVisible == false`; fire `onHelpVisibilityChange` | Help button image symbol is `questionmark.circle`. |
| settings-window-024 | shows-filled-glyph-when-drawer-open | `isHelpVisible == true`; fire `onHelpVisibilityChange` | Help button image symbol is `questionmark.circle.fill`. |
| settings-window-025 | tints-help-button-by-drawer-state | Toggle `isHelpVisible` false then true | `contentTintColor` is `secondaryTextColor` then `accentColor`. |
| settings-window-026 | swaps-help-tooltip-by-drawer-state | Toggle `isHelpVisible` false then true | Tooltip reads "Show Help" then "Hide Help". |
| settings-window-027 | keeps-help-accessibility-name-stable | Toggle `isHelpVisible` through several open/close cycles | `button.image?.accessibilityDescription == "Help"` after every cycle. |
| settings-window-028 | updates-help-glyph-on-visibility-change | Fire `onHelpVisibilityChange` after the drawer opens | Help button glyph/tint/tooltip refresh to the open state. |
| settings-window-029 | updates-help-glyph-on-navigation-change | Fire `onNavigationChange` while the drawer is open | Help button glyph/tint/tooltip reflect the open state. |
| settings-window-030 | wires-help-only-for-inserted-item | Toolbar factory called with `willBeInsertedIntoToolbar: false` for `.settingsHelp` | `helpButton`, the theme observer, and `helpAnchorView` are left unset. |
| settings-window-031 | anchors-help-presenter-to-button | Toolbar factory called with `willBeInsertedIntoToolbar: true` for `.settingsHelp` | `viewController?.helpPresenter?.helpAnchorView` equals the returned item's button. |
| settings-window-032 | tracks-theme-live-on-help-button | Change the resolved theme palette after the help item is inserted | Help button glyph/tint refresh without any other event firing. |
| settings-window-033 | toggles-help-on-click | Click the inserted help button | `viewController?.toggleHelp()` is called. |
| settings-window-034 | builds-tracking-separator-from-splitview | `viewController?.splitView` is non-nil; request `.sidebarTrackingSeparator` | Returns an `NSTrackingSeparatorToolbarItem` bound to that split view at divider index 0. |
| settings-window-035 | builds-tracking-separator-from-splitview | `viewController?.splitView` is `nil`; request `.sidebarTrackingSeparator` | Returns `nil`. |
| settings-window-036 | assigns-high-visibility-to-primary-items | Inspect the navigation, panel-title, and help toolbar items | Each has `visibilityPriority == .high`. |
| settings-window-037 | returns-nil-for-unknown-toolbar-identifier | Request an item for an identifier outside the fixed list | Returns `nil`. |
