---
id: 7cac2263-94fe-47ec-ab1d-6cf5a12baf14
title: Settings Window
domain: agentictoolkit://cookbook/ui/settings/settings-window
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "A reusable window for an app's Settings surface: an alphabetically sorted topic sidebar with search, a unified header bar with back/forward navigation and help, and quiet-presentation-aware activation."
platforms:
- swift
- macos
tags:
- composable-settings
- window-controller
- settings
- split-view
depends-on:
- agentictoolkit://cookbook/ui/settings/settings-split-view
- agentictoolkit://cookbook/ui/windows/single-window-controller
related:
- agentictoolkit://cookbook/ui/settings/settings-panel
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
references: []
approved-by: ''
approved-date: ''
---

# Settings Window

## Overview

A reusable window for a single, app-wide Settings surface, in the style of a
system's built-in settings app: an always-alphabetical topic sidebar with its
own search field on one side, and the selected panel's content on the other,
with the sidebar running the window's full height under a transparent,
unified header bar. The header bar carries a two-part back/forward control,
the name of the panel currently on screen, and a help toggle that discloses a
per-window help panel. A host supplies its panels through configuration (see
Configuration); see Design Decisions for a source-fidelity note about
implementation documentation that still describes configuration a different
way.

## Behavioral Requirements

- **identifies-window-as-settings**: The window MUST be registered under the
  fixed window id `"settings"`, so the app tracks one Settings window rather
  than one per instance.
- **titles-window-settings**: The window's title text MUST be `"Settings"`.
- **hides-window-title-visibility**: The window MUST hide its title text from
  the title bar, deferring to the header bar's panel-title item to show what
  is on screen.
- **extends-content-under-title-bar**: The window MUST remain titled,
  closable, miniaturizable, and resizable, and MUST extend its content area
  under the title bar so the sidebar can run the full height of the window
  (see Platform Notes for the exact style mask).
- **suppresses-sidebar-title**: The hosted split view MUST show no sidebar
  title.
- **shows-sidebar-search**: The hosted split view MUST show a search field in
  the sidebar.
- **sorts-panels-alphabetically**: The hosted split view MUST sort its panels
  alphabetically by title, so panels always list in alphabetical order
  regardless of registration order.
- **exposes-setting-panels**: Setting the panel list MUST replace the hosted
  split view's full panel set; reading it before the split view has loaded
  MUST return an empty list.
- **activates-app-on-show-by-default**: The window's activate-on-show
  behavior MUST default to enabled.
- **allows-subclass-to-disable-activation**: A host MAY disable activate-on-
  show so that showing the window does not activate the app.
- **skips-activation-when-disabled**: When activate-on-show is disabled,
  showing the window MUST perform only the base show behavior — it MUST NOT
  activate the app or make the window key on top of that.
- **shows-quietly-under-quiet-presentation**: When activate-on-show is
  enabled and quiet presentation is enabled, showing the window MUST make the
  window key without activating the app or ordering it above other
  applications' windows.
- **activates-and-keys-window-normally**: When activate-on-show is enabled
  and quiet presentation is not enabled, showing the window MUST activate the
  app and then make the window key and frontmost.
- **attaches-help-drawer-presenter**: Configuring the window MUST construct a
  help panel presenter for that window and assign it as the hosted split
  view's help presenter.
- **installs-unified-toolbar-chrome**: Configuring the window MUST install a
  unified, icon-only header bar that the user cannot customize, with a
  transparent title bar and no separator line between the title bar and the
  content below it.
- **fixes-toolbar-item-order**: The header bar's item order MUST be fixed,
  for both the default set and the allowed set, in this order: the sidebar
  tracking separator, the back/forward navigation control, the panel-title
  item, a flexible space, and the help control.
- **hides-inline-help-button**: Configuring the window MUST hide the hosted
  split view's own inline help control, since the header bar supplies the
  window's one help control.
- **builds-back-forward-as-one-control**: The back/forward control MUST be a
  single control with two segments — a back-facing chevron labeled "Back"
  and a forward-facing chevron labeled "Forward" — carrying one combined
  accessibility label, "Back and forward", rather than two independent
  buttons.
- **routes-segment-selection-to-navigation**: Choosing the back segment MUST
  navigate back; choosing the forward segment MUST navigate forward; no
  selection MUST trigger neither.
- **syncs-navigation-control-enablement**: Whenever the navigation state
  changes, the back segment MUST be enabled only when moving back is
  possible and the forward segment enabled only when moving forward is
  possible, each set independently, because a custom-view header-bar item
  receives no automatic validation pass.
- **shows-current-panel-title**: Whenever the navigation state changes, the
  panel-title item's text MUST be set to the current panel's title, or the
  empty string when there is none.
- **renders-panel-title-as-single-line-heading**: The panel-title item MUST
  show its text as a non-editable, single-line heading using the heading
  text role and the primary-text color role, truncating overflow at the end,
  and MUST hug its content horizontally rather than stretching.
- **shows-outline-glyph-when-drawer-closed**: While the help panel is closed,
  the help control's icon MUST be an outline question-mark icon.
- **shows-filled-glyph-when-drawer-open**: While the help panel is open, the
  help control's icon MUST be a filled question-mark icon.
- **tints-help-button-by-drawer-state**: The help control's tint MUST be the
  resolved theme palette's secondary-text color role while the panel is
  closed and its accent color role while the panel is open.
- **swaps-help-tooltip-by-drawer-state**: The help control's tooltip MUST
  read "Show Help" while the panel is closed and "Hide Help" while the panel
  is open.
- **keeps-help-accessibility-name-stable**: The help control's accessibility
  description MUST remain "Help" across every icon swap; it MUST NOT change
  to match the tooltip text.
- **updates-help-glyph-on-visibility-change**: Whenever the help panel's
  visibility changes, the help control's icon, tint, and tooltip MUST be
  refreshed to match the panel's current visibility.
- **updates-help-glyph-on-navigation-change**: Whenever the navigation state
  changes, the help control's icon, tint, and tooltip MAY also be refreshed,
  since one implementation may share a single refresh path across
  navigation and help state; an implementer is not required to refresh the
  help control on navigation alone (see Platform Notes for
  the shared private method this rides on).
- **wires-help-only-for-inserted-item**: The help control's live reference,
  its live theme tracking, and its help-anchor assignment MUST be attached
  only when the control being built is actually the one being inserted into
  the header bar — never for a customization-palette sample or a rebuild
  pass — so a discarded copy cannot leave the tracked help control pointing
  at a view that is off screen.
- **anchors-help-presenter-to-button**: When the help control is actually
  inserted, it MUST be assigned as the help presenter's help-anchor view.
- **tracks-theme-live-on-help-button**: The inserted help control MUST
  re-apply its icon/tint/tooltip whenever the resolved theme palette
  changes, tracked live, not only once at construction.
- **toggles-help-on-click**: Activating the help control MUST toggle the
  help panel's visibility.
- **builds-tracking-separator-from-splitview**: The sidebar tracking
  separator item MUST be bound to the hosted split view's divider nearest
  the sidebar, and MUST be absent if the split view does not currently
  exist.
- **assigns-high-visibility-to-primary-items**: The navigation control, the
  panel-title item, and the help control MUST each be given high visibility
  priority.
- **returns-nil-for-unknown-toolbar-identifier**: Requesting an item for any
  identifier outside the fixed list in **fixes-toolbar-item-order** MUST
  return nothing.

## Appearance

- **Corner radius**: Not applicable — a standard system window; this file
  draws no custom-cornered chrome.
- **Padding**: Not decided in this file — header-bar item spacing follows
  the platform's standard header-bar layout, and a panel's own content
  padding is decided by that panel's own ingredient, a separate concept.
- **Font**: The panel-title item's font is the active theme palette's
  heading text-role font, not a literal point size chosen in this file. The
  help control's icon is rendered at 15pt, regular weight.
- **Background**: The window's background color is set once, at window
  creation, by an inherited window-lifecycle component, to the resolved
  theme palette's window background color — not by this file. With the
  title bar transparent and no title-bar separator, the sidebar's and detail
  pane's own fills read as one continuous color under the header-bar band
  rather than a strip of system chrome laid across both.
- **Foreground/Text**: The panel-title item's text color is the theme
  palette's primary-text color role, re-applied live on theme change; the
  help control's tint switches between the palette's secondary-text and
  accent color roles as described above.
- **Border**: The title-bar separator is explicitly turned off, so no
  separator line is drawn between the header bar and the sidebar/detail
  panes.
- **Shadow**: Not applicable — standard system window shadow; this file
  configures no custom shadow.
- **Min/Max size**: Not decided in this file — no minimum/maximum size
  override is set here. Window sizing comes entirely from inherited
  window-lifecycle and window-management machinery (a default of 600×480pt
  absent a registered window spec for the `"settings"` id), not from any
  value in this file itself.

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet loaded: no header bar, navigation control, panel-title item, or help control exist until the window is first shown. |
| Pressed | Not applicable at this layer — per-press visual feedback belongs to the underlying control widgets, not to this window. |
| Disabled | The navigation control's back segment is disabled when moving back is not possible; its forward segment is disabled when moving forward is not possible, each independently. |
| Focused | Not applicable — this file assigns no focus-management or focus-restoration behavior of its own; a panel's own focus handling belongs to that panel, a separate ingredient. |
| Loading | Not applicable — panel and header-bar installation are synchronous; no loading/spinner state exists in this file. |
| Help panel open | Help control shows the filled question-mark icon, accent tint, and tooltip "Hide Help". |
| Help panel closed | Help control shows the outline question-mark icon, secondary-text tint, and tooltip "Show Help". |
| Activation disabled | Showing the window performs only the base show behavior; this override itself neither activates the app nor makes the window key — whatever key/visible state results comes entirely from the inherited base behavior. |
| Quiet presentation enabled | Showing the window makes it key without activating the app or ordering it above other applications' windows. |

## Accessibility

- Role/traits: a standard system window with title-bar close/minimize/zoom
  controls; the header bar's navigation and help controls are plain
  segmented-control and button widgets hosted in custom-view header-bar
  items, and the panel-title item hosts a plain text label.
- Accessibility identifiers: the help control's accessibility identifier is
  fixed at `"ComposableSettings.help"`. Neither the navigation control nor
  the panel-title item is given an explicit accessibility identifier in
  this file.
- Label requirements: the navigation control's combined accessibility label
  is "Back and forward"; its two segment icons carry the accessibility
  descriptions "Back" and "Forward". The help control's accessibility
  description is fixed at "Help" for its whole lifetime (see
  **keeps-help-accessibility-name-stable**).
- Announce state changes: the help toggle communicates open/closed through
  icon shape (outline vs. filled) and tooltip text, not tint alone (see
  **swaps-help-tooltip-by-drawer-state** and
  **shows-filled-glyph-when-drawer-open**).
- Minimum control size: this file sets no explicit frame for the navigation
  control or help control, so both size themselves per the platform's
  standard icon-only header-bar sizing, consistent with this codebase's
  other header-bar controls rather than a value this file decides on its
  own; on a pointer-driven platform there is no mandated minimum
  touch-target size to meet (see Platform Notes for touch-platform sizing
  considerations).
- Keyboard/focus: the navigation control and help control are ordinary
  keyboard-focusable controls (Tab to focus, Space/Return to activate); the
  segmented control provides its own arrow-key segment navigation. This
  file customizes neither the focus order nor any keyboard shortcut for
  these controls.
- Color/contrast: header-bar and label colors are read from the shared
  theme palette; contrast is a design-system-level concern this file does
  not decide, per
  `agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages`.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The panel-title item draws its text in the primary-text role and the help control tints itself with the secondary-text/accent roles, each against whichever theme surface renders behind it under the transparent, unified header bar (see Appearance, Background); no contrast ratio between those roles and their background is computed or asserted anywhere in this file. Settling this needs a theme-level contrast audit of the palette's roles against the surfaces they are drawn over, not a change to this file itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| settings-window-001 | identifies-window-as-settings | Construct the window | Its window id is `"settings"`. |
| settings-window-002 | titles-window-settings | Construct the window | Its window title is `"Settings"`. |
| settings-window-003 | hides-window-title-visibility | Show the window | The window's title text is hidden. |
| settings-window-004 | extends-content-under-title-bar | Inspect the window after construction | It remains titled, closable, miniaturizable, and resizable, with its content extended under the title bar. |
| settings-window-005 | suppresses-sidebar-title | Construct the window | The hosted split view has no sidebar title. |
| settings-window-006 | shows-sidebar-search | Construct the window | The hosted split view shows a sidebar search field. |
| settings-window-007 | sorts-panels-alphabetically | Construct the window | The hosted split view sorts panels alphabetically by title. |
| settings-window-008 | exposes-setting-panels | Assign the panel list to `[panelB, panelA]` | The hosted split view's panel list reflects the assignment. |
| settings-window-009 | activates-app-on-show-by-default | Construct the window with no override | Activate-on-show is enabled. |
| settings-window-010 | allows-subclass-to-disable-activation | Override activate-on-show to disabled | The override value is honored (activate-on-show is disabled). |
| settings-window-011 | skips-activation-when-disabled | Activate-on-show is disabled; show the window | The app is not activated, and only the base show behavior runs, with no further window operation of its own. |
| settings-window-012 | shows-quietly-under-quiet-presentation | Activate-on-show is enabled; quiet presentation is enabled; show the window | The window is made key without activating the app. |
| settings-window-013 | activates-and-keys-window-normally | Activate-on-show is enabled; quiet presentation is disabled; show the window | The app is activated, then the window is made key and frontmost, in that order. |
| settings-window-014 | attaches-help-drawer-presenter | Trigger window configuration (first show) | The hosted split view's help presenter is a help panel presenter built with that window. |
| settings-window-015 | installs-unified-toolbar-chrome | Trigger window configuration | The window has a unified, icon-only header bar the user cannot customize, a transparent title bar, and no title-bar separator. |
| settings-window-016 | fixes-toolbar-item-order | Read the header bar's default and allowed item lists | Both equal: the sidebar tracking separator, the navigation control, the panel-title item, a flexible space, and the help control, in that order. |
| settings-window-017 | hides-inline-help-button | Trigger window configuration | The hosted split view's inline help control is hidden. |
| settings-window-018 | builds-back-forward-as-one-control | Inspect the navigation control | One segmented control, momentary tracking, separated style, 2 segments, accessibility label "Back and forward". |
| settings-window-019 | routes-segment-selection-to-navigation | Choose the back segment, then the forward segment, then simulate no selection | Navigate back is triggered once, navigate forward is triggered once, no call on the third case. |
| settings-window-020 | syncs-navigation-control-enablement | Moving back is not possible, moving forward is possible; navigation state changes | Back segment disabled, forward segment enabled. |
| settings-window-021 | shows-current-panel-title | Current panel title is `"General"`; navigation state changes | Panel-title item's text is `"General"`. |
| settings-window-022 | renders-panel-title-as-single-line-heading | Inspect the panel-title item | Non-editable, truncates overflow at the end, hugs content horizontally, primary-text color role, heading text role. |
| settings-window-023 | shows-outline-glyph-when-drawer-closed | Help panel is not visible; help visibility changes | Help control's icon is the outline question-mark icon. |
| settings-window-024 | shows-filled-glyph-when-drawer-open | Help panel is visible; help visibility changes | Help control's icon is the filled question-mark icon. |
| settings-window-025 | tints-help-button-by-drawer-state | Toggle help visibility off then on | Tint is secondary-text color then accent color. |
| settings-window-026 | swaps-help-tooltip-by-drawer-state | Toggle help visibility off then on | Tooltip reads "Show Help" then "Hide Help". |
| settings-window-027 | keeps-help-accessibility-name-stable | Toggle help visibility through several open/close cycles | The help icon's accessibility description is "Help" after every cycle. |
| settings-window-028 | updates-help-glyph-on-visibility-change | Help visibility changes after the panel opens | Help control's icon/tint/tooltip refresh to the open state. |
| settings-window-029 | updates-help-glyph-on-navigation-change | Navigation state changes while the help panel is open | Help control's icon/tint/tooltip reflect the open state. |
| settings-window-030 | wires-help-only-for-inserted-item | The help control is built as a non-live copy, not the one being inserted | The help control reference, its theme tracking, and its help-anchor view are left unset. |
| settings-window-031 | anchors-help-presenter-to-button | The help control is actually inserted | The help presenter's help-anchor view equals the returned control. |
| settings-window-032 | tracks-theme-live-on-help-button | Change the resolved theme palette after the help control is inserted | Help control icon/tint refresh without any other event firing. |
| settings-window-033 | toggles-help-on-click | Activate the inserted help control | The help panel's visibility toggles. |
| settings-window-034 | builds-tracking-separator-from-splitview | The hosted split view exists; request the sidebar tracking separator | Returns a separator item bound to that split view's first divider. |
| settings-window-035 | builds-tracking-separator-from-splitview | The hosted split view does not exist; request the sidebar tracking separator | Returns nothing. |
| settings-window-036 | assigns-high-visibility-to-primary-items | Inspect the navigation, panel-title, and help items | Each has high visibility priority. |
| settings-window-037 | returns-nil-for-unknown-toolbar-identifier | Request an item for an identifier outside the fixed list | Returns nothing. |

## Edge Cases

- **Null/empty input**: No current panel title MUST result in the
  panel-title item showing the empty string, not a placeholder (MUST, see
  **shows-current-panel-title**). No selection on the navigation control
  MUST trigger neither navigate-back nor navigate-forward (MUST, see
  **routes-segment-selection-to-navigation**). A request for the sidebar
  tracking separator when the hosted split view does not exist MUST return
  nothing rather than a partially-configured item (MUST, see
  **builds-tracking-separator-from-splitview**).
- **Boundary values**: Not applicable — this file has no numeric,
  countable, or ranged input of its own (two fixed navigation directions and
  one fixed, five-item header-bar list); it defines no minimum/maximum to
  test against.
- **Concurrent access**: All mutation is confined to a single designated
  thread (this file and its base window-lifecycle type are both isolated to
  it), so there is no defined behavior for access from another thread, and
  none is needed for a window controller of this kind. Unlike some sibling
  window controllers in this codebase, this file installs no explicit
  reentrancy guard (no in-flight-operation flag) — none is needed because
  every entry point here (showing the window, the header-bar item factory,
  and the two control actions) runs to completion synchronously before the
  platform can call back in.
- **Error states**: This file performs no fallible operation of its own — no
  network call, no throwing construction, no unchecked access outside the
  safely-guarded accesses already covered by the requirements above. It
  therefore produces no error state to communicate to the user; this is
  what the source does, not an idealized claim of error handling that isn't
  there.
- **Offline/disconnected state**: Not applicable — this file makes no
  network requests.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Panel list | List of settings panels | Empty | Panels shown in the sidebar; assigning replaces the hosted split view's full panel set. Each panel is a separate settings-panel ingredient. |
| Activate on show | Boolean (open, overridable) | Enabled | Whether showing the window activates the app and makes the window key; a host overrides it to disabled to avoid stealing focus from a background/menu-bar-only host. |

## Deep Linking

Not applicable: no URL-scheme or system-activity handling appears anywhere
in this file. The window is opened only by direct calls from other
in-process code.

## Localization

Every user-facing string in this file is a hardcoded English literal, not a
localization key: `"Settings"` (window title), `"Back"` / `"Forward"`
(segment icon accessibility descriptions), `"Back and forward"` (navigation
control accessibility label), `"Back/Forward"` / `"Panel"` (header-bar item
labels), `"Help"` (header-bar item label and the help control's stable
accessibility name), and `"Show Help"` / `"Hide Help"` (tooltip text). None
of these pass through a localization lookup anywhere in this file.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: this file performs no animation of any kind (not even an opacity fade) — the help icon swap is an instantaneous image/tint/tooltip change with no transition to reduce. |
| Increase Contrast | Not applicable: every color used here is read from the shared theme palette; contrast handling is a design-system-level concern this file defers to that shared, separately-recipe'd system. |
| Differentiate Without Color | Handled: the help toggle differentiates open/closed by icon shape (outline vs. filled question-mark icon) and by tooltip text, not by tint alone (see **shows-filled-glyph-when-drawer-open** and **swaps-help-tooltip-by-drawer-state**). |

## Feature Flags

Not applicable: no flag-gated behavior (feature flag, remote config, or
similar) appears in this file.

## Analytics

Not applicable: no analytics or event-logging call appears in this file.

## Privacy

- **Data collected**: This file collects no data directly. It constructs a
  help panel presenter and assigns it as the hosted split view's help
  presenter; that presenter independently persists whether the settings
  help panel is visible — that persistence belongs to the help presenter, a
  separate ingredient, not to this file. This file's own state (activate-on-
  show, the assigned panel list) is held in memory only.
- **Storage**: Not decided in this file. Window-frame geometry for the
  `"settings"` window id is persisted locally by inherited
  window-lifecycle/window-management machinery; this file contains no
  storage call of its own.
- **Transmission**: None — no networking import or call appears in this
  file.
- **Retention**: Not decided in this file; see Storage and Data collected
  above for which components own the data this window causes to be
  persisted.

## Logging

Not applicable: no logging call appears anywhere in this file.

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
  no UIKit counterpart exists in source. The window is an `NSWindow`; its
  title text (`windowTitle`, mapped to AppKit's `title`) is hidden via
  `titleVisibility = .hidden`. The full-height-sidebar style mask is
  `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`.
  The hosted split view's neutral properties map to `sidebarTitle = nil`,
  `showsSidebarSearch = true`, `sortsPanelsByTitle = true`; the panel-list
  property (`settingPanels`) forwards to `viewController?.panels` /
  `viewController?.setPanels(_:)`, returning `[]` before the split loads.
  `activatesOnShow` is the open, overridable `Bool` (default `true`); when
  `false`, `showWindow()` calls `super.showWindow()` and returns without
  calling `NSApp.activate` or making the window key. A host commonly
  overrides it to `false` for an `LSUIElement`/menu-bar-only host. Under
  `QuietWindowPresentation.isEnabled`, `showWindow()` calls
  `window?.makeKeyAndOrderFrontQuietly()`; otherwise it calls
  `NSApp.activate(ignoringOtherApps: true)` then
  `window?.makeKeyAndOrderFront(nil)`. `configureWindow(_:)` builds a
  `HelpDrawerController(parentWindow:)` as the split's `helpPresenter`,
  installs an `NSToolbar` identified `"ComposableSettings.Toolbar"`
  (`displayMode = .iconOnly`, `allowsUserCustomization = false`), sets
  `toolbarStyle = .unified`, `titlebarAppearsTransparent = true`,
  `titlebarSeparatorStyle = .none`, and sets `showsInlineHelpButton = false`.
  `toolbarDefaultItemIdentifiers`/`toolbarAllowedItemIdentifiers` both
  return `[.sidebarTrackingSeparator, .settingsNavigation,
  .settingsPanelTitle, .flexibleSpace, .settingsHelp]`. The navigation
  control is one momentary, `.separated`-style `NSSegmentedControl` with two
  segments — `chevron.backward` labeled "Back" and `chevron.forward`
  labeled "Forward" — wired so segment `0` calls `goBack()`, segment `1`
  calls `goForward()`, and any other value including `-1` calls neither;
  enablement syncs from `canGoBack`/`canGoForward` on every
  `onNavigationChange`, because a custom-view toolbar item receives no
  AppKit validation pass. The panel-title item is a `ThemedLabel`
  (`NSTextField` subclass) reading `currentPanelTitle ?? ""`, non-editable,
  `.heading` text role, `.primaryText` color role,
  `lineBreakMode = .byTruncatingTail`, horizontal content-hugging
  `.defaultHigh` — its font comes from `SemanticPalette.font(_:)`. The help
  control swaps `questionmark.circle`/`questionmark.circle.fill` SF Symbols
  (`NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)`, applied
  in `WindowToolbarBuilder.applyDisclosureAppearance`), tints via
  `contentTintColor` between `secondaryTextColor`/`accentColor`, and keeps
  its image's `accessibilityDescription` fixed at `"Help"` (identifier
  `"ComposableSettings.help"`, set by `WindowToolbarBuilder.iconButtonItem`)
  across tooltip swaps ("Show Help"/"Hide Help"). Its live reference,
  `ThemePaletteObserver` theme tracking, and
  `helpPresenter?.helpAnchorView` assignment are wired only when the
  toolbar factory's `willBeInsertedIntoToolbar` flag is `true`, never for
  the customization-palette sample or a rebuild pass. Clicking it calls
  `viewController?.toggleHelp()`. The sidebar tracking separator is an
  `NSTrackingSeparatorToolbarItem` bound to `viewController?.splitView` at
  divider index `0`, `nil` if there is no split view. The navigation,
  panel-title, and help items each set `visibilityPriority = .high`; the
  toolbar item factory returns `nil` for any `NSToolbarItem.Identifier`
  outside that fixed list. The private `updateToolbarState()` method is
  what couples the help button's refresh to navigation changes: it is the
  shared refresh path behind both **syncs-navigation-control-enablement**
  and **updates-help-glyph-on-navigation-change**, called from the
  `onNavigationChange` closure installed in `installToolbar(on:)`. The
  class and its methods are `@MainActor`-isolated (as is its
  `WindowController` superclass); no explicit reentrancy guard is installed
  because every entry point (`showWindow()`, the toolbar delegate methods,
  the two button actions) runs to completion synchronously. The window's
  background color is set once, at window creation, by the inherited
  `SingleWindowController.loadWindow()`, to
  `ThemePaletteObserver.currentPalette.windowBackgroundColor`. Window
  sizing comes from the inherited `SingleWindowController`/`WindowManager`
  machinery (default 600×480pt absent a registered `WindowSpec` for the
  `"settings"` id). None of this file's user-facing string literals pass
  through `NSLocalizedString` or a String Catalog lookup; no
  `Logger`/`os_log`/print-based logging call appears anywhere in the file;
  no `NSUserActivity`/URL-scheme handling exists — the window opens only
  via direct `showWindow()` calls. Files: this file (`SettingsWindow.swift`),
  `SplitViewController.swift` (sidebar/detail split, search, navigation
  history — a separate ingredient), `ComposableSettingsPanel.swift` /
  `SettingsPanelViewController.swift` (the per-panel contract — a separate
  ingredient), `Help/HelpDrawerController.swift` (the deprecated
  `NSDrawer`-backed help presenter), `WindowToolbarBuilder.swift`
  (icon-button construction and the disclosure-glyph helper),
  `SingleWindowController.swift` / `WindowController.swift` (window
  lifecycle and frame persistence), `ThemedViews.swift` (`ThemedLabel`), and
  `QuietWindowPresentation.swift` (test/automation activation suppression).
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
  `agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window` already uses
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
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: replaced the fabricated recipe-quality Compliance rows with real accessibility/internationalization checks and their grounded statuses, cleaned up by `compliance_fix.py`; flagged the theme-token colors this file reads with a Minimum contrast ratio open question; downgraded `updates-help-glyph-on-navigation-change` from MUST to MAY and moved its private-method coupling into Platform Notes; recorded the stale `makeSettingsPanels()` doc comment as a pending Design Decision instead of prose; reformatted Design Decisions to the bold three-line form; trimmed `tags` to five entries and populated `depends-on`/`related`; removed leftover template instruction text from Accessibility Options; resolved the WinUI cross-reference to a full domain URL; and corrected three inaccurate conformance test vectors (settings-window-011, -015, -023, -024) and the "Activation disabled" States row. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial extraction from `SettingsWindow.swift`. |
