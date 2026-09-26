---
id: 7cac2263-94fe-47ec-ab1d-6cf5a12baf14
title: SettingsWindow
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-window
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "AppKit window controller for the app's Settings window: alphabetical sidebar panels, a unified toolbar with back/forward and help, and quiet-presentation-aware activation."
platforms:
- swift
- macos
tags:
- composable-settings
- window-controller
- settings
- split-view
- appkit
depends-on:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/split-view-controller
- agentictoolkit://cookbook/macos/system-integration/window-manager/windows/single-window-controller
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-panel/settings-panel-view-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

- **Corner radius**: Not applicable — a standard `NSWindow`; this file draws
  no custom-cornered chrome.
- **Padding**: Not decided in this file — toolbar item spacing is AppKit's
  standard `NSToolbar` layout, and a panel's own content padding is decided
  by that `SettingsPanelViewController` subclass, a separate ingredient.
- **Font**: The panel-title label's font is the active theme palette's
  `.heading` text-role font (`ThemedLabel` reads it from
  `SemanticPalette.font(_:)`), not a literal point size chosen in this file.
  The help button's SF Symbol is rendered at 15pt, `.regular` weight
  (`NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)`, applied
  in `WindowToolbarBuilder.applyDisclosureAppearance`).
- **Background**: The window's background color is set once, at window
  creation, by the inherited `SingleWindowController.loadWindow()` to
  `ThemePaletteObserver.currentPalette.windowBackgroundColor` — not by this
  file. With `titlebarAppearsTransparent = true` and no titlebar separator,
  the sidebar's and detail pane's own fills read as one continuous color
  under the toolbar band rather than a strip of system chrome laid across
  both.
- **Foreground/Text**: The panel-title label's text color is the theme
  palette's `.primaryText` color role, re-applied live on theme change; the
  help button's tint switches between the palette's `secondaryTextColor`
  and `accentColor` as described above.
- **Border**: `titlebarSeparatorStyle` is explicitly set to `.none`, so no
  separator line is drawn between the toolbar and the sidebar/detail panes.
- **Shadow**: Not applicable — standard system window shadow; this file
  configures no custom shadow.
- **Min/Max size**: Not decided in this file — no `minSize`/`maxSize`
  override is set here. Window sizing comes entirely from the inherited
  `SingleWindowController`/`WindowManager` machinery (a default of 600×480pt
  absent a registered `WindowSpec` for the `"settings"` id), not from any
  value in `SettingsWindow.swift` itself.

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet loaded (`window == nil`): no toolbar, navigation control, panel-title label, or help button exist until the first `showWindow()` call builds the window. |
| Pressed | Not applicable at this layer — per-press bezel visuals belong to `NSSegmentedControl`/`NSButton`, not to this controller. |
| Disabled | The navigation control's back segment is disabled when `canGoBack == false`; its forward segment is disabled when `canGoForward == false`, each independently. |
| Focused | Not applicable — this file assigns no first-responder or focus-restoration behavior of its own; a panel's own focus handling belongs to that panel, a separate ingredient. |
| Loading | Not applicable — panel and toolbar installation are synchronous; no loading/spinner state exists in this file. |
| Help drawer open | Help button shows the filled `questionmark.circle.fill` glyph, accent tint, and tooltip "Hide Help". |
| Help drawer closed | Help button shows the outline `questionmark.circle` glyph, secondary-text tint, and tooltip "Show Help". |
| Activation disabled (`activatesOnShow == false`) | `showWindow()` calls `super.showWindow()` and returns; this override itself neither calls `NSApp.activate` nor makes the window key — whatever key/visible state results comes entirely from the inherited base behavior. |
| Quiet presentation enabled | `showWindow()` makes the window key without activating the app or ordering it above other applications' windows. |

## Accessibility

- Role/traits: a standard `NSWindow` with title-bar close/miniaturize/zoom
  buttons; the toolbar's navigation and help controls are plain
  `NSSegmentedControl`/`NSButton` instances hosted in custom-view toolbar
  items (`NSToolbarItem` itself is not accessible), and the panel-title
  item hosts a plain `ThemedLabel` (`NSTextField` subclass).
- Accessibility identifiers: the help button's identifier is the toolbar
  item identifier's raw value, `"ComposableSettings.help"`, set by
  `WindowToolbarBuilder.iconButtonItem`. Neither the navigation control nor
  the panel-title label is given an explicit accessibility identifier in
  this file.
- Label requirements: the navigation control's combined accessibility label
  is "Back and forward"; its two segment images carry the accessibility
  descriptions "Back" and "Forward" from their `NSImage` construction. The
  help button's accessibility description is fixed at "Help" for its whole
  lifetime (see **keeps-help-accessibility-name-stable**).
- Announce state changes: the help toggle communicates open/closed through
  symbol shape (outline vs. filled) and tooltip text, not tint alone (see
  **swaps-help-tooltip-by-drawer-state** and
  **shows-filled-glyph-when-drawer-open**).
- Minimum control size: macOS is a pointer-driven platform with no mandated
  minimum touch-target size; this file sets no explicit frame for the
  navigation control or help button, so both size themselves per AppKit's
  standard icon-only toolbar sizing, consistent with this codebase's other
  toolbar controls rather than a value this file decides on its own.
- Keyboard/focus: the navigation control and help button are ordinary
  keyboard-focusable AppKit controls (Tab to focus, Space/Return to
  activate); `NSSegmentedControl` provides its own arrow-key segment
  navigation. This file customizes neither the key-view loop nor any
  keyboard shortcut for these controls.
- Color/contrast: toolbar and label colors are read from the shared theme
  palette (`ThemePaletteObserver`); contrast is a design-system-level
  concern this file does not decide, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The panel-title label draws its text in the `.primaryText` role and the help button tints itself with `secondaryTextColor`/`accentColor`, each against whichever theme surface renders behind it under the transparent, unified toolbar (see Appearance, Background); no contrast ratio between those roles and their background is computed or asserted anywhere in this file. Settling this needs a theme-level contrast audit of `SemanticPalette`'s roles against the surfaces they are drawn over, not a change to `SettingsWindow.swift` itself.

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

## Edge Cases

- **Null/empty input**: `currentPanelTitle == nil` MUST result in the
  panel-title label showing the empty string, not a placeholder (MUST, see
  **shows-current-panel-title**). A `selectedSegment` value of `-1` (no
  selection) on the navigation control MUST trigger neither `goBack()` nor
  `goForward()` (MUST, see **routes-segment-selection-to-navigation**). A
  toolbar request for the sidebar tracking separator when
  `viewController?.splitView` is `nil` MUST return `nil` rather than a
  partially-configured item (MUST, see
  **builds-tracking-separator-from-splitview**).
- **Boundary values**: Not applicable — this file has no numeric,
  countable, or ranged input of its own (two fixed navigation directions and
  one fixed, five-item toolbar list); it defines no minimum/maximum to test
  against.
- **Concurrent access**: The class and its methods are `@MainActor`-isolated
  (as is its `WindowController` superclass), so all mutation runs on the
  main actor; there is no defined behavior for access from another thread,
  and none is needed for an AppKit window controller. Unlike some sibling
  window controllers in this codebase, this file installs no explicit
  reentrancy guard (no in-flight-operation flag) — none is needed because
  every entry point here (`showWindow()`, the toolbar delegate methods, the
  two button actions) runs to completion synchronously before AppKit can
  call back in.
- **Error states**: This file performs no fallible operation of its own — no
  network call, no throwing initializer, no optional force-unwrap outside
  the `guard`-protected `viewController`/`window` accesses already covered
  by the requirements above. It therefore produces no error state to
  communicate to the user; this is what the source does, not an idealized
  claim of error handling that isn't there.
- **Offline/disconnected state**: Not applicable — this file makes no
  network requests.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `settingPanels` | `[any ComposableSettingsPanel]` | `[]` | Panels shown in the sidebar; assigning replaces the hosted split's full panel set. Each panel is a separate `ComposableSettingsPanel`/`SettingsPanelViewController` ingredient. |
| `activatesOnShow` | `Bool` (open, overridable) | `true` | Whether `showWindow()` activates the app and makes the window key; a subclass overrides it to `false` to avoid stealing focus from an `LSUIElement`/menubar host. |

## Deep Linking

Not applicable: no URL-scheme or `NSUserActivity` handling appears anywhere
in `SettingsWindow.swift`. The window is opened only by direct method calls
(`showWindow()`) from other in-process code.

## Localization

Every user-facing string in this file is a hardcoded English literal passed
directly to AppKit APIs, not a localization key: `"Settings"` (window
title), `"Back"` / `"Forward"` (segment image accessibility descriptions),
`"Back and forward"` (navigation control accessibility label),
`"Back/Forward"` / `"Panel"` (toolbar item labels), `"Help"` (toolbar item
label and the help button's stable accessibility name), and `"Show Help"` /
`"Hide Help"` (tooltip text). None of these pass through
`NSLocalizedString` or a String Catalog lookup anywhere in this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this file performs no animation of any kind (not even an opacity fade) — the help glyph swap is an instantaneous image/tint/tooltip change with no transition to reduce. |
| Increase Contrast | Not applicable: every color used here is read from the shared theme palette (`ThemePaletteObserver`); contrast handling is a design-system-level concern this file defers to that shared, separately-recipe'd system. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by symbol shape (outline vs. filled `questionmark.circle`) and by tooltip text, not by tint alone (see **shows-filled-glyph-when-drawer-open** and **swaps-help-tooltip-by-drawer-state**). |

## Feature Flags

Not applicable: no flag-gated behavior (`FeatureFlag`, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging call appears in this file.

## Privacy

- **Data collected**: This file collects no data directly. It constructs a
  `HelpDrawerController` and assigns it as the hosted split's help
  presenter; that controller independently persists whether the settings
  help drawer is visible — that persistence belongs to `HelpDrawerController`,
  a separate ingredient, not to this file. This file's own state
  (`activatesOnShow`, the assigned `settingPanels`) is held in memory only.
- **Storage**: Not decided in this file. Window-frame geometry for the
  `"settings"` window id is persisted locally by the inherited
  `SingleWindowController`/`WindowManager` machinery; this file contains no
  storage call of its own.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not decided in this file; see Storage and Data collected
  above for which components own the data this window causes to be
  persisted.

## Logging

Not applicable: no `Logger`/`os_log`/print-based logging call appears
anywhere in `SettingsWindow.swift`.

## Platform Notes

- **SwiftUI**: build the two-pane shape as a `NavigationSplitView` with a
  `List(selection:)` sidebar (sorted alphabetically to match
  `sortsPanelsByTitle`) and a `.searchable` modifier for the sidebar search.
  `NavigationSplitView`'s selection model has no back/forward concept, so
  that has to be rebuilt explicitly: a small observable object exposing
  `canGoBack`/`canGoForward` and a small history stack, driving two
  `.toolbar` `Button`s. The panel-title toolbar item becomes a
  `.principal`-placement `Text` (or the detail column's `.navigationTitle`
  read back into the toolbar), and the help toggle is a `.toolbar` button
  bound to `@State private var isHelpVisible`, swapping
  `Image(systemName:)` between `"questionmark.circle"` and
  `"questionmark.circle.fill"`.
- **Compose (Desktop/Android)**: model the window as one top-level
  composable with a `Row` of a `LazyColumn` sidebar (Material 3
  `NavigationRail`/`PermanentDrawerSheet`, alphabetically sorted, with a
  search `TextField` at its top) and a detail pane. Compose Navigation's
  back stack does not map directly to a two-pane split's back/forward, so
  mirror it with a small view-model exposing `canGoBack`/`canGoForward`
  booleans backing two `IconButton`s in the top app bar. The help toggle
  maps to an `IconToggleButton` swapping between an outlined and a filled
  help icon, tinted via `MaterialTheme.colorScheme.secondary`/`primary`.
- **React/Web**: a two-pane layout (`<nav>` sidebar + `<main>` detail);
  because browser back/forward already exists at the tab level, the
  in-window back/forward here maps to two `<button>` elements bound to
  `disabled={!canGoBack}` / `disabled={!canGoForward}` state, not to
  `history.back()`. The help toggle is a `<button aria-pressed={isOpen}>`
  swapping an inline SVG icon and its `title` attribute, opening the help
  drawer as a `role="complementary"` panel or a `<dialog>`.
- **AppKit / UIKit**: this is the source platform, and it is AppKit-only —
  no UIKit counterpart exists in source. Files: this file
  (`SettingsWindow.swift`), `SplitViewController.swift` (sidebar/detail
  split, search, navigation history — a separate ingredient),
  `ComposableSettingsPanel.swift` / `SettingsPanelViewController.swift`
  (the per-panel contract — a separate ingredient), `Help/HelpDrawerController.swift`
  (the deprecated `NSDrawer`-backed help presenter),
  `WindowToolbarBuilder.swift` (icon-button construction and the
  disclosure-glyph helper), `SingleWindowController.swift` /
  `WindowController.swift` (window lifecycle and frame persistence),
  `ThemedViews.swift` (`ThemedLabel`), and `QuietWindowPresentation.swift`
  (test/automation activation suppression). The private `updateToolbarState()`
  method is what couples the help button's refresh to navigation changes: it
  is the shared refresh path behind both `syncs-navigation-control-enablement`
  and **updates-help-glyph-on-navigation-change**, called from the
  `onNavigationChange` closure installed in `installToolbar(on:)`.
- **WinUI 3**: the closest native shape is a single `Window` hosting a
  `NavigationView` in `Left` or `LeftCompact` `PaneDisplayMode` as the
  sidebar, with `NavigationView.MenuItems` sorted alphabetically to match
  `sortsPanelsByTitle` and `NavigationView.AutoSuggestBox` set to reproduce
  `showsSidebarSearch`, and a `Frame` in the content area navigating between
  per-panel `Page`s. `NavigationView` supplies its own back button
  (`IsBackButtonVisible`) but nothing for forward, so forward needs two
  custom `AppBarButton`s in the window's `TitleBar`/`CommandBar`, bound to a
  small navigation-history view-model exposing `CanGoBack`/`CanGoForward` to
  mirror `canGoBack`/`canGoForward`. Put the panel-title `TextBlock` in that
  same `CommandBar`, bound to `Frame.CurrentSourcePageType`'s title.
  `Window.ExtendsContentIntoTitleBar = true` plus
  `Window.SetTitleBar(commandBar)` reproduces
  `.fullSizeContentView` + `titlebarAppearsTransparent` +
  `titleVisibility = .hidden` together. The help toggle is an
  `AppBarToggleButton` swapping a `FontIcon`/`SymbolIcon` between an
  outline and filled help glyph via its `IsChecked` state, driving a
  `SplitView` (`DisplayMode="Inline"` or `"CompactOverlay"`) pinned to the
  window's trailing edge as the WinUI substitute for the AppKit help
  drawer — WinUI has no drawer primitive of its own, so `SplitView` is the
  standard stand-in, matching the pattern
  `agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller` already uses
  for its own drawer translation.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SettingsWindow.swift` |

## Design Decisions

**Decision**: Give the sidebar's own top slot to the search field and remove
the sidebar title entirely, rather than showing a titled sidebar with search
below it.
**Rationale**: this matches System Settings' shape (source comment); the
name of what is on screen is shown once, in the toolbar's panel-title item
beside the back/forward control, exactly where a reader is already looking
to change it — a separate sidebar title would be a second answer to the same
question.
**Approved**: pending

**Decision**: Sort panels alphabetically, always, with no host-supplied
ordering option.
**Rationale**: the panels in a settings window are unrelated destinations,
and the only thing a reader hunting for one of them knows is its name;
whatever order a host happened to register panels in is an order only the
host can see (source comment on `sortsPanelsByTitle`).
**Approved**: pending

**Decision**: Represent back/forward as one two-segment `NSSegmentedControl`
rather than two independent `NSButton`s.
**Rationale**: it is one control with one meaning — where in the navigation
trail the reader is — and a single shared bezel is how System Settings
expresses that (source comment on `navigationControl`).
**Approved**: pending

**Decision**: `activatesOnShow` defaults to `true`, with an open override
point for hosts that don't want it.
**Rationale**: a settings window is normally opened to be used immediately,
and shown from an `LSUIElement`/menubar host the base `showWindow()` still
leaves the window visible but non-key, so its sidebar selection and text
fields don't respond until the user clicks it first; defaulting to
activation avoids that dead first click for the common case, while the
override keeps the behavior optional rather than forcing it on every
consumer (source comment on `activatesOnShow`).
**Approved**: pending

**Decision**: Under `QuietWindowPresentation`, make the window key without
activating the app or ordering it above other applications' windows.
**Rationale**: an automated session driving the app still needs the sidebar
selection and text fields to respond, which requires the window to be key,
but must not steal focus or draw over whatever the person at the keyboard is
doing — that is the entire distinction this file draws between a settings
window "opened to be used" and one "opened to be driven" (source comment on
`showWindow()`).
**Approved**: pending

**Decision**: Wire the help button reference, its theme observer, and the
help-anchor view only when `willBeInsertedIntoToolbar` is `true`.
**Rationale**: AppKit calls the toolbar item factory again to build a
customization-palette sample and on every toolbar rebuild; adopting one of
those non-live copies would point all three at a button that is never on
screen, leaving the real, visible help button unthemed and unreported
(source comment on the `.settingsHelp` case).
**Approved**: pending

**Decision**: Whether to update the class doc comment (which still shows
`override func makeSettingsPanels() -> [ComposableSettings.SettingsPanelViewController]`)
to describe `settingPanels`, or to restore a `makeSettingsPanels()` override
point, is not yet settled.
**Rationale**: `SettingsWindow.swift` illustrates subclassing
through a `makeSettingsPanels()` override that does not exist anywhere in
the class — the only subclass-facing configuration surface this version
actually exposes is the `settingPanels` property (see Overview and
Configuration). This is a documentation/implementation mismatch in the
source, not a behavior this recipe can decide on its own; it belongs to
whoever maintains `SettingsWindow.swift`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | passed | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |

`screen-reader-support` and `keyboard-navigable` rest on the Accessibility
section's Label requirements and Keyboard/focus bullets (explicit
accessibility labels/descriptions on the navigation control and help button;
ordinary keyboard-focusable AppKit controls). `dynamic-type-support` and
`contrast-ratio` are `partial` because the source reads fonts and colors
from the shared theme palette but this file neither asserts nor decides
scaling or contrast itself (see the open question on
minimum-contrast-ratio).
`no-hardcoded-strings` and `string-externalization` are `failed` because
every user-facing string this file passes to AppKit is a literal, not a
localization key (see Localization).

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: replaced the fabricated recipe-quality Compliance rows with real accessibility/internationalization checks and their grounded statuses, cleaned up by `compliance_fix.py`; flagged the theme-token colors this file reads with a Minimum contrast ratio open question; downgraded `updates-help-glyph-on-navigation-change` from MUST to MAY and moved its private-method coupling into Platform Notes; recorded the stale `makeSettingsPanels()` doc comment as a pending Design Decision instead of prose; reformatted Design Decisions to the bold three-line form; trimmed `tags` to five entries and populated `depends-on`/`related`; removed leftover template instruction text from Accessibility Options; resolved the WinUI cross-reference to a full domain URL; and corrected three inaccurate conformance test vectors (settings-window-011, -015, -023, -024) and the "Activation disabled" States row. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `SettingsWindow.swift`. |
