---
id: faf4ec69-7b5c-44c2-a8c2-d7e81dc94ea8
title: PanelHostView
domain: agentictoolkit://cookbook/macos/system-integration/composable-settings-window/views/panel-host-view
type: ingredient
version: 1.1.2
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AppKit macOS view that hosts a settings panel's swapped content plus a persistent
  top-right help button wired to a shared help presenter.
platforms:
- swift
- macos
tags:
- settings
- help
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/split-view-controller
- agentictoolkit://cookbook/macos/system-integration/composable-settings-window/settings-window
references: []
approved-by: ''
approved-date: ''
---

# PanelHostView

## Overview

`ComposableSettings.PanelHostView`, at
`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift`,
is the detail pane's chrome inside a `ComposableSettings.SplitViewController`:
a plain `NSView` that hosts whichever panel is currently selected, plus a
help button pinned to the panel's top-right corner. Per the source's own
doc comment, one instance lives for the whole life of the split and only
its content is swapped — the button is a property of the split's chrome,
not of any one panel, so it never flickers or moves as the selection
changes. Help itself is disclosed elsewhere: this view forwards to a
`SettingsHelpPresenting` presenter (a window drawer or a sheet's popover,
depending on how the owning window is presented) rather than rendering help
content itself. `SplitViewController` owns one `PanelHostView` for its
detail pane and forwards its own `helpPresenter`/`showsHelpButton`/
`toggleHelp()`/`isHelpVisible` directly to it; the settings window assigns
a presenter only to its root split, which is what keeps a nested split (a
panel that is itself a `SplitViewController`) from showing a second help
button or opening a second drawer.

## Behavioral Requirements

- **replaces-content-on-set**: `setContent(_:)`, called with a non-`nil`
  view, MUST remove every existing subview of the content container before
  installing the given view.
- **clears-content-on-nil**: `setContent(nil)` MUST remove every existing
  subview of the content container and MUST NOT install a replacement,
  leaving the content area empty.
- **content-pinned-to-container-edges**: An installed content view MUST be
  pinned to its content container's top, leading, trailing, and bottom
  edges with zero inset.
- **content-container-pinned-to-view-edges**: The content container itself
  MUST be pinned to `PanelHostView`'s own top, leading, trailing, and
  bottom edges with zero inset.
- **help-button-inset-from-content-container**: The help button's top edge
  MUST sit 12pt below the content container's top edge, and its trailing
  edge MUST sit 12pt inside the content container's trailing edge.
- **help-button-above-content**: The help button MUST be added as a
  subview of `PanelHostView` itself, after the content container, so
  swapping the hosted content via `setContent(_:)` never removes,
  reorders, or redraws the button.
- **help-button-visibility**: The help button MUST be hidden whenever
  `showsHelpButton` is `false`, or whenever `helpPresenter` is `nil`, or
  both, and MUST be visible whenever `showsHelpButton` is `true` and
  `helpPresenter` is non-`nil`.
- **help-button-icon-reflects-visibility**: The help button MUST display
  the filled `questionmark.circle.fill` symbol while
  `helpPresenter?.isHelpVisible` is `true`, and the outlined
  `questionmark.circle` symbol otherwise (including when `helpPresenter`
  is `nil`).
- **help-button-symbol-configuration**: The help button's symbol image
  MUST be rendered at 15pt point size with regular weight
  (`NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)`).
- **help-button-tint-reflects-visibility**: The help button's
  `contentTintColor` MUST be the active theme palette's `accentColor`
  while help is visible, and the palette's `secondaryTextColor` while help
  is not visible.
- **help-button-tooltip-reflects-visibility**: The help button's `toolTip`
  MUST read `"Hide Help"` while help is visible, and `"Show Help"` while
  it is not.
- **help-button-accessibility-label-fixed**: The help button's
  accessibility label MUST be the literal string `"Help"`, set once at
  construction, regardless of visibility state.
- **help-button-keyboard-focusable**: `PanelHostView` MUST NOT remove the
  help button from the keyboard/assistive-technology focus order, and
  MUST NOT override its default activation behavior, while the button is
  visible (AppKit: no override of `acceptsFirstResponder`, `keyDown`, or
  `performClick`, so `NSButton`'s stock key-view-loop and Space/Return
  activation apply unmodified).
- **help-button-borderless-image-only**: The help button MUST render with
  no bezel/border (`isBordered = false`) and MUST show only its image
  (`imagePosition = .imageOnly`).
- **help-button-momentary-type**: The help button MUST behave as a
  momentary push control — firing its action once per click and holding
  no on/off state of its own — rather than as a persistent toggle
  (AppKit: `setButtonType(.momentaryChange)`).
- **toggle-help-delegates-to-presenter**: `toggleHelp()` MUST forward to
  `helpPresenter?.toggleHelp()` and MUST have no effect when
  `helpPresenter` is `nil`.
- **help-anchor-claimed-when-button-shown**: Whenever `showsHelpButton` is
  `true`, `PanelHostView` MUST set `helpPresenter?.helpAnchorView` to its
  own help button, both when `helpPresenter` is assigned and when
  `showsHelpButton` changes.
- **help-anchor-untouched-when-button-hidden**: Whenever `showsHelpButton`
  is `false`, `PanelHostView` MUST NOT modify `helpPresenter?.helpAnchorView`.
- **help-visibility-change-refreshes-button**: Whenever the current
  presenter invokes its `onVisibilityChange` callback, `PanelHostView`
  MUST re-evaluate and reapply the help button's icon, tint, and tooltip.
- **help-visibility-change-notifies-external-observer**: Whenever the
  current presenter invokes its `onVisibilityChange` callback,
  `PanelHostView` MUST, after refreshing its own button, invoke its own
  `onHelpVisibilityChange` callback if one is set.
- **presenter-reassignment**: Assigning a new
  value to `helpPresenter` MUST install this view's own closure as that
  new presenter's `onVisibilityChange`, MUST re-run the help-anchor claim,
  MUST hand the new presenter the view's currently stored help content via
  `setHelp(_:)`, and MUST refresh the help button.
- **set-help-forwards-to-presenter**: `setHelp(_:)` MUST store the given
  `PanelHelp?` (including `nil`), MUST forward that same value to
  `helpPresenter?.setHelp(_:)`, and MUST refresh the help button
  afterward.
- **is-help-visible-reflects-presenter-or-false**: `isHelpVisible` MUST
  report `helpPresenter!.isHelpVisible` when a presenter is set, and MUST
  report `false` when `helpPresenter` is `nil`.
- **shows-help-button-toggle**: Assigning a
  new value to `showsHelpButton` MUST re-run the help-anchor claim and
  MUST refresh the help button.
- **theme-change-refreshes-button-tint**: `PanelHostView` MUST re-run the
  help button refresh (icon, tint, tooltip) immediately whenever the
  active `SemanticPalette` changes, via its `ThemePaletteObserver`.
- **rejects-coder-initialization**: `PanelHostView` MUST NOT support
  construction via `init(coder:)`; that initializer is marked
  `@available(*, unavailable)` and MUST trigger a fatal error.
- **constraint-based-layout-only**: `PanelHostView` MUST position itself,
  its content container, and its help button entirely through the
  platform's layout-constraint system, never by assigning frames manually
  (AppKit: `translatesAutoresizingMaskIntoConstraints = false` on all
  three, positioned only via Auto Layout constraints).

## Appearance

- **Corner radius**: None. Neither `PanelHostView` nor its content
  container sets a `cornerRadius` anywhere in source.
- **Padding**: The content container is pinned to `PanelHostView`'s edges
  with 0pt inset on all four sides. Installed content is pinned to the
  content container's edges with 0pt inset on all four sides. The help
  button sits 12pt (`buttonInset`) inside the content container's top and
  trailing edges.
- **Font**: Not applicable — `PanelHostView.swift` draws no text of its
  own; its only visual element besides hosted content is an image-only
  help button, which carries no font.
- **Background**: None set. Neither `PanelHostView` nor its content
  container configures a layer background color or `wantsLayer` in
  source; whatever shows through is the hosted content's own background
  or the window's.
- **Foreground/Text**: The help button's `contentTintColor` is
  `palette.accentColor` while help is visible, `palette.secondaryTextColor`
  while it is not (see **help-button-tint-reflects-visibility**).
- **Border**: None — the help button is explicitly borderless
  (`isBordered = false`); nothing else in `PanelHostView.swift` draws a
  border.
- **Shadow**: None — no shadow is drawn or configured anywhere in
  `PanelHostView.swift`.
- **Min/Max size**: None declared on `PanelHostView` itself — no explicit
  width or height constraint appears in source. It fills whatever frame
  its container (the split's detail pane) gives it.

## States

| State | Appearance change |
|-------|------------------|
| Help hidden (default) | Help button, if shown, displays the outlined `questionmark.circle` symbol tinted `secondaryTextColor`, tooltip `"Show Help"`. |
| Help visible | Help button displays the filled `questionmark.circle.fill` symbol tinted `accentColor`, tooltip `"Hide Help"`. |
| No presenter / button disabled | Help button is hidden entirely (`isHidden = true`) — see **help-button-visibility**. |
| Pressed | Not applicable: `PanelHostView.swift` defines no custom pressed-state styling for the help button; `NSButton` with `.momentaryChange` supplies AppKit's own built-in momentary highlight, which this source does not override. |
| Disabled | Not applicable: the source never sets `isEnabled` on the help button or on `PanelHostView` itself; there is no disabled-state path in this file. |
| Focused | Not applicable: the source configures no custom focus ring or focused-state appearance; `NSButton`'s default AppKit focus ring applies unmodified. |
| Loading | Not applicable: every operation in `PanelHostView.swift` (content swap, help toggling, theme repaint) is synchronous; the source defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: `PanelHostView` itself sets no accessibility role — it
  is a plain container `NSView` with default view semantics. The help
  button is a stock `NSButton`, exposed to assistive technology with
  AppKit's default push-button role; `PanelHostView.swift` does not
  override it.
- **Keyboard / assistive technology navigation**: Satisfied — see
  **help-button-keyboard-focusable**. `PanelHostView.swift` neither
  removes the help button from the key-view loop nor overrides
  `acceptsFirstResponder`, `keyDown`, or `performClick`, so Tab/Shift-Tab
  focus traversal and Space/Return activation remain exactly `NSButton`'s
  unmodified default behavior.
- **Label requirements**: Satisfied for the help button — its
  accessibility label is always the literal string `"Help"`
  (**help-button-accessibility-label-fixed**), and both symbol variants
  are constructed with `accessibilityDescription: "Help"`.
  `PanelHostView` sets no label on the content container; whatever
  content is installed via `setContent(_:)` is responsible for its own
  labeling.
- **Announce state changes (e.g., loading, disabled)**: Not satisfied.
  `updateHelpButton()` changes the button's image, `contentTintColor`, and
  `toolTip` when help is disclosed or dismissed, but the accessibility
  label stays the fixed string `"Help"` for both states, and no
  `NSAccessibility.post(element:notification:)` call appears anywhere in
  `PanelHostView.swift` — VoiceOver is told nothing beyond whatever
  AppKit's default image-change handling surfaces on its own.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `contentTintColor` is set from `palette.accentColor` or `palette.secondaryTextColor` with neither color's contrast against whatever the button is drawn over computed or enforced in `PanelHostView.swift`; whether either color reaches WCAG AA's 3:1 non-text contrast minimum for every theme this component ships with depends on each theme's concrete color values and needs auditing per theme.
- **Minimum tap target**: Not applicable in the iOS 44×44pt sense —
  `PanelHostView` targets macOS only, where controls are pointer-operated,
  and Apple's Human Interface Guidelines do not set a single numeric
  minimum hit-target size for a pointer-driven AppKit control the way
  they do for an iOS touch target. The help button's actual click area is
  not set explicitly in source; it takes its size from `NSButton`'s
  default cell sizing for a borderless, image-only, momentary-change
  button showing a 15pt symbol, which `PanelHostView.swift` neither
  overrides nor measures.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-host-view-001 | replaces-content-on-set | Call `setContent(viewA)`, then `setContent(viewB)` | After the second call, `viewA` is no longer a subview of the content container; only `viewB` is |
| panel-host-view-002 | clears-content-on-nil | Call `setContent(viewA)`, then `setContent(nil)` | The content container has zero subviews after the second call |
| panel-host-view-003 | content-pinned-to-container-edges | Call `setContent(viewA)` | `viewA`'s top/leading/trailing/bottom anchors are each constrained equal to the content container's corresponding anchor with 0 constant |
| panel-host-view-004 | content-container-pinned-to-view-edges | Construct `PanelHostView()` | The content container's top/leading/trailing/bottom anchors are each constrained equal to `PanelHostView`'s corresponding anchor with 0 constant |
| panel-host-view-005 | help-button-inset-from-content-container | Construct `PanelHostView()` | The help button's top anchor equals the content container's top anchor + 12; its trailing anchor equals the content container's trailing anchor − 12 |
| panel-host-view-006 | help-button-above-content | Construct `PanelHostView()`, then call `setContent(viewA)` | The help button remains a subview of `PanelHostView` (not of the content container) both before and after the call, and is not removed or reordered by it |
| panel-host-view-007 | help-button-visibility | Set `showsHelpButton = false` with `helpPresenter` non-`nil` | `helpButton.isHidden == true` |
| panel-host-view-008 | help-button-visibility | Set `helpPresenter = nil` with `showsHelpButton == true` | `helpButton.isHidden == true` |
| panel-host-view-009 | help-button-visibility | Set `showsHelpButton = true` and assign a non-`nil` `helpPresenter` | `helpButton.isHidden == false` |
| panel-host-view-010 | help-button-icon-reflects-visibility | Set `helpPresenter` to a presenter stub whose `isHelpVisible` returns `true` | The help button's image is `questionmark.circle.fill` |
| panel-host-view-011 | help-button-icon-reflects-visibility | Assign a presenter whose `isHelpVisible == false` | The help button's image is `questionmark.circle` |
| panel-host-view-012 | help-button-symbol-configuration | Construct `PanelHostView()` | The image's symbol configuration reports point size 15 and weight `.regular` |
| panel-host-view-013 | help-button-tint-reflects-visibility | Presenter reports `isHelpVisible == true` while the active theme is "Solarized Dark" | `helpButton.contentTintColor` equals Solarized Dark's `SemanticPalette.accentColor` |
| panel-host-view-014 | help-button-tint-reflects-visibility | Presenter reports `isHelpVisible == false` while the active theme is "Solarized Dark" | `helpButton.contentTintColor` equals Solarized Dark's `SemanticPalette.secondaryTextColor` |
| panel-host-view-015 | help-button-tooltip-reflects-visibility | Presenter reports `isHelpVisible == true` | `helpButton.toolTip == "Hide Help"` |
| panel-host-view-016 | help-button-tooltip-reflects-visibility | Presenter reports `isHelpVisible == false` | `helpButton.toolTip == "Show Help"` |
| panel-host-view-017 | help-button-accessibility-label-fixed | Toggle help visible, then hidden | `helpButton`'s accessibility label reads `"Help"` in both states |
| panel-host-view-018 | help-button-borderless-image-only | Construct `PanelHostView()` | `helpButton.isBordered == false`; `helpButton.imagePosition == .imageOnly` |
| panel-host-view-019 | help-button-momentary-type | Construct `PanelHostView()` | `helpButton`'s button type is `.momentaryChange` |
| panel-host-view-020 | toggle-help-delegates-to-presenter | Assign a presenter, then call `toggleHelp()` | The presenter's `toggleHelp()` is invoked exactly once |
| panel-host-view-021 | toggle-help-delegates-to-presenter | With `helpPresenter == nil`, call `toggleHelp()` | No presenter method is invoked and no error occurs |
| panel-host-view-022 | help-anchor-claimed-when-button-shown | With `showsHelpButton == true`, assign a presenter | `presenter.helpAnchorView === helpButton` |
| panel-host-view-023 | help-anchor-untouched-when-button-hidden | With `showsHelpButton == false`, assign a presenter whose `helpAnchorView` was previously set to some other view | `presenter.helpAnchorView` is unchanged by the assignment |
| panel-host-view-024 | help-visibility-change-refreshes-button | With a presenter assigned, invoke the presenter's stored `onVisibilityChange` closure | The help button's icon/tint/tooltip are re-evaluated against the presenter's current `isHelpVisible` |
| panel-host-view-025 | help-visibility-change-notifies-external-observer | With `onHelpVisibilityChange` set, invoke the presenter's `onVisibilityChange` closure | `onHelpVisibilityChange` is invoked exactly once, after the button refresh |
| panel-host-view-026 | presenter-reassignment | Call `setHelp(contentA)`, then assign a new `helpPresenter` | The new presenter receives `setHelp(contentA)`, its `helpAnchorView` is claimed (if shown), and its `onVisibilityChange` is this view's closure |
| panel-host-view-027 | set-help-forwards-to-presenter | With a presenter assigned, call `setHelp(nil)` | The presenter receives `setHelp(nil)` and the help button is refreshed |
| panel-host-view-028 | is-help-visible-reflects-presenter-or-false | Query `isHelpVisible` with `helpPresenter == nil` | Returns `false` |
| panel-host-view-029 | is-help-visible-reflects-presenter-or-false | Query `isHelpVisible` with a presenter whose `isHelpVisible == true` | Returns `true` |
| panel-host-view-030 | shows-help-button-toggle | Toggle `showsHelpButton` from `false` to `true` with a presenter assigned | The presenter's `helpAnchorView` is claimed and the help button's hidden/icon/tint state is refreshed |
| panel-host-view-031 | theme-change-refreshes-button-tint | With help visible while the active theme is "Solarized Dark", call `ThemeManager.selectTheme(id:)` with Solarized Light's id | `helpButton.contentTintColor` updates to Solarized Light's `SemanticPalette.accentColor` without reconstructing the view |
| panel-host-view-032 | rejects-coder-initialization | Attempt `PanelHostView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| panel-host-view-033 | constraint-based-layout-only | Inspect `PanelHostView`, its content container, and its help button after construction | `translatesAutoresizingMaskIntoConstraints == false` for all three |
| panel-host-view-034 | help-button-keyboard-focusable | Construct `PanelHostView()`, Tab focus to the visible help button, then press Space | The help button receives key-view focus via Tab/Shift-Tab and its action fires on Space/Return, using `NSButton`'s unmodified default first-responder and key-equivalent handling |

## Edge Cases

- **Null/empty input**: `setContent(nil)` MUST empty the content container
  rather than error (**clears-content-on-nil**). `setHelp(nil)` MUST be
  forwarded to the presenter exactly like any other value
  (**set-help-forwards-to-presenter**); `PanelHostView.swift` performs no
  special-casing between `nil` and a populated `PanelHelp` beyond passing
  the value through.
- **Boundary values**: Not applicable in the numeric-input sense — the
  only fixed numeric value in source is the `buttonInset` constant (12pt),
  which is not client-supplied and has no minimum/maximum to test.
- **Concurrent access**: Not applicable — `PanelHostView` is a
  `@MainActor` class; the Swift compiler rejects construction or mutation
  of it from off the main actor, so there is no concurrent-access surface
  to define behavior for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or fallible operation; every
  method is a synchronous view/property update with no failure path.
- **Offline/disconnected state**: Not applicable — `PanelHostView.swift`
  performs no networking of any kind.
- **Rapid, repeated `setContent(_:)` calls**: Each call independently
  tears down and rebuilds the content container's subviews
  (**replaces-content-on-set**); the source contains no debouncing or
  in-flight guard, so N calls in quick succession perform N full teardown
  cycles.
- **`helpPresenter` reassigned to a different, non-`nil` instance while
  the previous presenter is still retained elsewhere**: The source's
  `didSet` only ever touches `self.helpPresenter` — the *new* value — and
  never clears the previously assigned presenter's own
  `onVisibilityChange`. If a caller keeps a reference to the old presenter
  and it later fires `onVisibilityChange` on its own, this view's closure
  still runs and repaints the help button as if that stale presenter were
  still current. This is what the `didSet` implementation does, not an
  intentional safeguard.
- **`showsHelpButton` toggled while help is currently visible**: Setting
  it to `false` hides the button (**help-button-visibility**)
  but does not itself close help — `helpPresenter.isHelpVisible` and any
  window drawer/popover the presenter owns are unaffected; only this
  view's own button disappears.
- **Anchor left stale when the button hides**: Per
  **help-anchor-untouched-when-button-hidden**, `PanelHostView` does not
  clear `helpPresenter?.helpAnchorView` when `showsHelpButton` becomes
  `false` — the presenter is left pointing at a now-hidden view. What a
  presenter does with a hidden anchor (for example guarding before
  presenting) is that presenter's own contract, not `PanelHostView`'s.

## Configuration

`PanelHostView`
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `helpPresenter` | `(any SettingsHelpPresenting)?` | `nil` | Where this view's help button opens and closes help, and reports visibility changes back. `nil` hides the help button entirely. |
| `showsHelpButton` | `Bool` | `true` | Whether this view draws its own `?` button. Set `false` for a window whose toolbar supplies help instead. |
| `onHelpVisibilityChange` | `(() -> Void)?` | `nil` | Callback fired after help is disclosed or dismissed, for chrome outside this view (e.g. a toolbar button) that needs to mirror the same state. |

```swift
public init()
public func setContent(_ view: NSView?)
public func setHelp(_ help: PanelHelp?)
public func toggleHelp()
public var isHelpVisible: Bool { get }
```

## Deep Linking

Not applicable: `PanelHostView` is chrome inside a settings window, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in `PanelHostView.swift`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | `Help` | Help button's accessibility label, set once in `configureHelpButton()` via `setAccessibilityLabel("Help")` |
| — (hardcoded literal, no key) | `Help` | Passed as `accessibilityDescription` to `NSImage(systemSymbolName:accessibilityDescription:)` for both help-button glyph variants |
| — (hardcoded literal, no key) | `Show Help` | Help button's `toolTip` while help is not visible |
| — (hardcoded literal, no key) | `Hide Help` | Help button's `toolTip` while help is visible |

All four strings above are set as plain `String` literals through AppKit
APIs (`setAccessibilityLabel`, `NSImage`'s `accessibilityDescription:`
parameter, and `toolTip`) — none of these is a SwiftUI
`Text`/`LocalizedStringKey` position, so a literal here is not
automatically localizable the way SwiftUI's is. No `NSLocalizedString`
call or string-catalog reference appears anywhere in `PanelHostView.swift`.

## Accessibility Options

- **Reduce Motion**: Not applicable — `PanelHostView.swift` contains no
  animation, transition, or `NSAnimationContext`/`CATransaction` call.
  Content swapping and help-button refresh are both synchronous property
  and subview assignments, not a motion effect.
- **Increase Contrast**: Not applicable in this file — the help button's
  colors come entirely from the active `SemanticPalette`
  (`accentColor`/`secondaryTextColor`); if Increase Contrast should raise
  either color's contrast, that is the palette/theme system's
  responsibility, not `PanelHostView`'s. Whether these colors reach an
  adequate ratio is the open question on minimum-contrast-ratio, tracked
  once under Accessibility above.
- **Differentiate Without Color**: Supported — the help-visible and
  help-hidden states are distinguished by both the button's symbol shape
  (`questionmark.circle.fill` vs. `questionmark.circle`) and its tint
  color (**help-button-icon-reflects-visibility**,
  **help-button-tint-reflects-visibility**), so color is never the sole
  signal.

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; `PanelHostView` is constructed and behaves unconditionally whenever
its owning split creates one.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — `PanelHostView` holds only the `PanelHelp?`
  content and the presenter/content-view references handed to it by its
  caller; it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind. (Whether help-visibility is remembered across launches is decided
  by the assigned `helpPresenter`, e.g. `HelpDrawerController`'s
  `UserSettings`-backed preference — outside `PanelHostView.swift`.)
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The currently installed content view and the most
  recently set `help` value are held in memory as private stored
  properties for the view's own lifetime, and are replaced (not appended
  to) on every subsequent `setContent(_:)`/`setHelp(_:)` call; nothing
  persists past deallocation.

## Logging

Not applicable: the source contains no logging call (no `print`,
`os_log`, or logger reference anywhere in `PanelHostView.swift`).

## Platform Notes

- **SwiftUI**: Compose a `ZStack(alignment: .topTrailing)` with the
  swapped panel content as the base layer and a borderless `Button` as the
  overlay, offset `.padding(.top, 12).padding(.trailing, 12)`. Drive the
  button's `Image(systemName:)` between `"questionmark.circle.fill"` and
  `"questionmark.circle"`, and its `.foregroundStyle` between `.tint` and
  `.secondary`, from an observed `isHelpVisible` on whatever object plays
  the presenter's role; gate the button's presence on
  `showsHelpButton && helpPresenter != nil` the same way this view does.
  Content swap becomes whatever view a `@ViewBuilder`/enum-driven switch
  renders, since SwiftUI needs no manual subview teardown.
- **Compose**: A `Box` with the panel content filling it and an
  `IconButton` aligned `Alignment.TopEnd` with
  `Modifier.padding(top = 12.dp, end = 12.dp)`; swap between a filled and
  an outline "help" icon (e.g. `Icons.Filled.Help` /
  `Icons.Outlined.HelpOutline`) and between `MaterialTheme.colorScheme.primary`
  and `.onSurfaceVariant` tint from a `helpVisible: Boolean` state, and
  gate the button's presence on the same `showsHelpButton && helpPresenter
  != null` condition.
- **React/Web**: A relatively-positioned container `<div>` with the panel
  content as children and an absolutely positioned `<button>`
  (`position: absolute; top: 12px; right: 12px`) rendering an inline
  SVG/icon-font glyph that swaps between an outline and a filled variant;
  the button's `aria-label="Help"` stays fixed while a `title` attribute
  (or a tooltip component) swaps between "Show Help"/"Hide Help", mirroring
  the fixed-label/changing-tooltip split in source. CSS custom properties
  (or a theme context) supply the accent/secondary colors that swap with a
  `visible` boolean class or data attribute.
- **AppKit / UIKit** (source platform): Source at
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift`
  (this recipe's source): a macOS-only (`import AppKit`), `@MainActor`
  `NSView` subclass. Specific to it: the manual subview teardown in
  `setContent(_:)` (`contentContainer.subviews.forEach { $0.removeFromSuperview() }`);
  the help button being added as a sibling of, and after, the content
  container so it always draws above swapped panels regardless of what
  they contain; the shared `NSView.pinToEdges(_:of:)` static helper
  (`ViewLayout.swift`) used for both the container's and the content
  view's edge constraints; the `buttonInset` constant (12pt) driving
  the button's own two constraints; and
  `translatesAutoresizingMaskIntoConstraints = false` set on
  `PanelHostView` itself, the content container, and the help button, per
  **constraint-based-layout-only**. A UIKit port would use a `UIView`
  overlaying a `UIButton(configuration: .plain())` pinned with
  `NSLayoutConstraint`s the same way, but no analogue currently exists
  elsewhere in this codebase's `ComposableSettingsWindow/` tree — the rest
  of it is AppKit-only.
- **WinUI 3**: Build this as a single-cell
  `Grid`: the swapped panel content (a `ContentControl` or `Frame` whose
  `Content` is reassigned the way `setContent(_:)` swaps subviews) fills
  the cell, and a borderless `Button` (`BorderThickness="0"`,
  `Background="Transparent"`, no `Style` resource applying a bezel) shares
  the same cell with `HorizontalAlignment="Right" VerticalAlignment="Top"
  Margin="0,12,12,0"` to match the 12px inset. The button's `Content` is a
  `FontIcon` bound to a Segoe Fluent Icons glyph; Segoe Fluent Icons has no
  built-in filled/outline question-mark pair the way SF Symbols does, so
  matching the source's filled-vs-outline distinction needs either two
  custom icon glyphs or a single glyph plus a `Fill`/`Stroke` visual-state
  swap — call this out as a deviation rather than a drop-in equivalent.
  Drive the two visual states with a `VisualStateManager`
  (`HelpHidden`/`HelpVisible`, swapping `Foreground` between
  `{ThemeResource AccentTextFillColorPrimaryBrush}` and
  `{ThemeResource TextFillColorSecondaryBrush}`) rather than imperative
  color assignment. Set `AutomationProperties.Name="Help"` (fixed, mirroring
  the source's static accessibility label) and bind `ToolTipService.ToolTip`
  to a string that swaps "Show Help"/"Hide Help" — WinUI's
  `AutomationProperties.Name` and `ToolTipService.ToolTip` are two separate
  properties, just as AppKit's accessibility label and `toolTip` are here,
  so the fixed-label/changing-tooltip split translates directly. Gate the
  button's `Visibility` on the same `showsHelpButton`-and-presenter
  condition used in source.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/PanelHostView.swift` |

## Design Decisions

**Decision**: The help button is shown for every panel a split hosts, based
solely on `showsHelpButton` and whether a `helpPresenter` is assigned —
never on whether the panel currently on screen has any help content.
**Rationale**: per the source's own comment on `updateHelpButton()`, it used
to come and go with `help != nil`, which "put a control in the corner of
some panels and not others and made the drawer look like a property of
the panel rather than of the window."
**Approved**: pending

**Decision**: `claimHelpAnchorIfShown()` re-runs unconditionally on every
`helpPresenter` assignment and every `showsHelpButton` change, rather than
claiming the anchor once at construction.
**Rationale**: per the source's own comment on `claimHelpAnchorIfShown()`,
claiming the anchor only once meant a later `helpPresenter` reassignment
"silently took it back" from whoever held it, "and handed a popover
presenter a hidden, zero-size view to hang off."
**Approved**: pending

**Decision**: Route chrome outside this view (e.g. a toolbar help button)
through a dedicated `onHelpVisibilityChange` callback rather than sharing
`helpPresenter.onVisibilityChange` directly.
**Rationale**: per the source's own comment on `onHelpVisibilityChange`,
`onVisibilityChange` "has exactly one slot" on the presenter and this view
claims it for its own inline button; anything else that needs the same
notification has to be told by whoever holds that slot rather than
overwriting it.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | internationalization |
| [platform-theming](agenticdevelopercookbook://compliance/platform-compliance#platform-theming) | passed | platform-compliance |

Statuses rest on: every color coming from `SemanticPalette`, with the
help-visible/hidden distinction carried by both icon shape and tint, never
color alone (platform-theming); the help button being a stock `NSButton`
with no override that removes it from the key-view loop or blocks its
default activation (keyboard-navigable); the fixed accessibility label
never reflecting the toggled visibility state, with no
`NSAccessibility.post` call anywhere in source (screen-reader-support —
see Accessibility); `accentColor`/`secondaryTextColor` carrying no
enforced minimum-contrast floor evaluated in this file (contrast-ratio —
see Accessibility); and the four accessibility-label/tooltip strings being
set as plain AppKit string literals with no `NSLocalizedString` or
string-catalog reference anywhere in `PanelHostView.swift`
(no-hardcoded-strings, string-externalization — see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved private source identifiers (`buttonInset`, `NSView.pinToEdges`) and AppKit-specific mechanics (`constraint-based-layout-only`, `help-button-momentary-type`) out of requirement bodies and into Platform Notes; merged and renamed condition-laden requirement names to subject-only form (`help-button-visibility`, `presenter-reassignment`, `shows-help-button-toggle`); promoted the implicit keyboard-focus guarantee to a named requirement (`help-button-keyboard-focusable`) with a conformance vector; moved the stale-presenter-callback observation out of Design Decisions (it was a bug, not an approved choice) and left it as the single Edge Case description; trimmed the popover edge case to what this component guarantees; reformatted Design Decisions to the bold three-line form; fixed Compliance statuses and pruned Compliance rows to checks that exist in the catalog; named concrete conformance-vector fixtures (Solarized Dark/Light, `ThemeManager.selectTheme(id:)`) and precise call sequences; removed the unsupported WinUI 3 parenthetical; and listed related ingredients in frontmatter. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
