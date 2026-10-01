---
id: faf4ec69-7b5c-44c2-a8c2-d7e81dc94ea8
title: Panel Host View
domain: agentictoolkit://cookbook/ui/settings/layout/panel-host-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A view that hosts a settings panel's swapped content plus a
  persistent top-right help button wired to a shared help presenter.
platforms:
- swift
- macos
tags:
- settings
- help
depends-on: []
related:
- agentictoolkit://cookbook/ui/settings/settings-split-view
- agentictoolkit://cookbook/ui/settings/settings-window
references: []
approved-by: ''
approved-date: ''
---

# Panel Host View

## Overview

The Panel Host View is the detail pane's chrome inside a settings split
view: a plain container view that hosts whichever panel is currently
selected, plus a help button pinned to the panel's top-right corner. Per
the source's own doc comment, one instance lives for the whole life of the
split and only its content is swapped — the button is a property of the
split's chrome, not of any one panel, so it never flickers or moves as the
selection changes. Help itself is disclosed elsewhere: this view forwards
to a help-presenting role (a window drawer or a sheet's popover, depending
on how the owning window is presented) rather than rendering help content
itself. The owning split view controller owns one Panel Host View for its
detail pane and forwards its own help-presenter/shows-help-button/
toggle-help/is-help-visible surface directly to it; the settings window
assigns a presenter only to its root split, which is what keeps a nested
split (a panel that is itself a split view) from showing a second help
button or opening a second drawer.

## Behavioral Requirements

- **replaces-content-on-set**: The component's set-content operation,
  called with a present view, MUST remove every existing child of the
  content container before installing the given view.
- **clears-content-on-nil**: The set-content operation, called with no
  view, MUST remove every existing child of the content container and
  MUST NOT install a replacement, leaving the content area empty.
- **content-pinned-to-container-edges**: An installed content view MUST be
  pinned to its content container's top, leading, trailing, and bottom
  edges with zero inset.
- **content-container-pinned-to-view-edges**: The content container itself
  MUST be pinned to the component's own top, leading, trailing, and bottom
  edges with zero inset.
- **help-button-inset-from-content-container**: The help button's top edge
  MUST sit 12pt below the content container's top edge, and its trailing
  edge MUST sit 12pt inside the content container's trailing edge.
- **help-button-above-content**: The help button MUST be added as a
  child of the component itself, after the content container, so
  swapping the hosted content never removes, reorders, or redraws the
  button.
- **help-button-visibility**: The help button MUST be hidden whenever the
  show-help-button setting is off, or whenever no help presenter is
  assigned, or both, and MUST be visible whenever the show-help-button
  setting is on and a help presenter is assigned.
- **help-button-icon-reflects-visibility**: The help button MUST display a
  filled question-mark icon while the assigned help presenter reports help
  as visible, and an outlined question-mark icon otherwise (including when
  no presenter is assigned).
- **help-button-symbol-configuration**: The help button's icon MUST be
  rendered at 15pt point size with regular weight.
- **help-button-tint-reflects-visibility**: The help button's tint color
  MUST be the active theme palette's accent-color role while help is
  visible, and the palette's secondary-text-color role while help is not
  visible.
- **help-button-tooltip-reflects-visibility**: The help button's tooltip
  MUST read "Hide Help" while help is visible, and "Show Help" while it is
  not.
- **help-button-accessibility-label-fixed**: The help button's
  accessibility label MUST be the literal string "Help", set once at
  construction, regardless of visibility state.
- **help-button-keyboard-focusable**: The component MUST NOT remove the
  help button from the keyboard/assistive-technology focus order, and MUST
  NOT override its default activation behavior, while the button is
  visible (see Platform Notes for the source's exact mechanism).
- **help-button-borderless-image-only**: The help button MUST render with
  no border and MUST show only its icon, with no accompanying text label.
- **help-button-momentary-type**: The help button MUST behave as a
  momentary push control — firing its action once per click and holding
  no on/off state of its own — rather than as a persistent toggle.
- **toggle-help-delegates-to-presenter**: The component's toggle-help
  operation MUST forward to the assigned help presenter's own toggle-help
  operation, and MUST have no effect when no presenter is assigned.
- **help-anchor-claimed-when-button-shown**: Whenever the show-help-button
  setting is on, the component MUST set the assigned help presenter's
  anchor view to its own help button, both when a presenter is assigned
  and when the show-help-button setting changes.
- **help-anchor-untouched-when-button-hidden**: Whenever the show-help-button
  setting is off, the component MUST NOT modify the assigned help
  presenter's anchor view.
- **help-visibility-change-refreshes-button**: Whenever the current
  presenter invokes its own visibility-change notification, the component
  MUST re-evaluate and reapply the help button's icon, tint, and tooltip.
- **help-visibility-change-notifies-external-observer**: Whenever the
  current presenter invokes its own visibility-change notification, the
  component MUST, after refreshing its own button, invoke its own external
  visibility-change notification if one is set.
- **presenter-reassignment**: Assigning a new help presenter MUST install
  this component's own callback as that new presenter's visibility-change
  notification, MUST re-run the help-anchor claim, MUST hand the new
  presenter the component's currently stored help content via its
  set-help operation, and MUST refresh the help button.
- **set-help-forwards-to-presenter**: The component's set-help operation
  MUST store the given help content (including no content), MUST forward
  that same value to the assigned help presenter's own set-help operation,
  and MUST refresh the help button afterward.
- **is-help-visible-reflects-presenter-or-false**: The component's
  help-visible query MUST report the assigned help presenter's own
  help-visible value when a presenter is assigned, and MUST report false
  when no presenter is assigned.
- **shows-help-button-toggle**: Changing the show-help-button setting MUST
  re-run the help-anchor claim and MUST refresh the help button.
- **theme-change-refreshes-button-tint**: The component MUST re-run the
  help button refresh (icon, tint, tooltip) immediately whenever the
  active theme palette changes.
- **rejects-deserializing-construction**: The component MUST NOT support
  construction via a deserializing/decoding-based construction path; that
  path MUST trigger a failure rather than produce a usable instance (see
  Platform Notes for the source's exact mechanism).
- **constraint-based-layout-only**: The component MUST position itself,
  its content container, and its help button entirely through the
  platform's layout-constraint system, never by assigning frames manually
  (see Platform Notes for the source's exact mechanism).

## Appearance

- **Corner radius**: None. Neither the component nor its content
  container sets a corner radius anywhere in source.
- **Padding**: The content container is pinned to the component's edges
  with 0pt inset on all four sides. Installed content is pinned to the
  content container's edges with 0pt inset on all four sides. The help
  button sits 12pt inside the content container's top and trailing edges.
- **Font**: Not applicable — the source draws no text of its own; its
  only visual element besides hosted content is an image-only help
  button, which carries no font.
- **Background**: None set. Neither the component nor its content
  container configures a background of its own in source; whatever shows
  through is the hosted content's own background or the window's.
- **Foreground/Text**: The help button's tint color is the theme's
  accent-color role while help is visible, the theme's secondary-text-color
  role while it is not (see **help-button-tint-reflects-visibility**).
- **Border**: None — the help button is explicitly borderless; nothing
  else in the source draws a border.
- **Shadow**: None — no shadow is drawn or configured anywhere in the
  source.
- **Min/Max size**: None declared on the component itself — no explicit
  width or height constraint appears in source. It fills whatever frame
  its container (the split's detail pane) gives it.

## States

| State | Appearance change |
|-------|------------------|
| Help hidden (default) | Help button, if shown, displays the outlined question-mark icon tinted with the secondary-text-color role, tooltip "Show Help". |
| Help visible | Help button displays the filled question-mark icon tinted with the accent-color role, tooltip "Hide Help". |
| No presenter / button disabled | Help button is hidden entirely — see **help-button-visibility**. |
| Pressed | Not applicable: the source defines no custom pressed-state styling for the help button; a momentary-type button supplies the platform's own built-in momentary highlight, which this source does not override. |
| Disabled | Not applicable: the source never sets an enabled/disabled state on the help button or on the component itself; there is no disabled-state path in this file. |
| Focused | Not applicable: the source configures no custom focus ring or focused-state appearance; the platform's default focus ring applies unmodified. |
| Loading | Not applicable: every operation in the source (content swap, help toggling, theme repaint) is synchronous; the source defines no loading flag, spinner, or placeholder state. |

## Accessibility

- **Role/trait**: The component itself sets no accessibility role — it is
  a plain container view with default view semantics. The help button is
  a stock push button, exposed to assistive technology with the
  platform's default push-button role; the source does not override it.
- **Keyboard / assistive technology navigation**: Satisfied — see
  **help-button-keyboard-focusable**. The source neither removes the help
  button from the keyboard focus order nor overrides its default
  activation behavior, so Tab/Shift-Tab focus traversal and Space/Return
  activation remain exactly the platform's unmodified default behavior.
- **Label requirements**: Satisfied for the help button — its
  accessibility label is always the literal string "Help"
  (**help-button-accessibility-label-fixed**), and both icon variants
  carry the same accessible description. The component sets no label on
  the content container; whatever content is installed via the set-content
  operation is responsible for its own labeling.
- **Announce state changes (e.g., loading, disabled)**: Not satisfied.
  The button-refresh operation changes the button's icon, tint, and
  tooltip when help is disclosed or dismissed, but the accessibility label
  stays the fixed string "Help" for both states, and the source issues no
  explicit accessibility-change announcement of its own — a screen reader
  is told nothing beyond whatever the platform's default image-change
  handling surfaces on its own.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The
  tint color is set from the theme's accent-color or secondary-text-color
  role with neither color's contrast against whatever the button is drawn
  over computed or enforced in the source; whether either color reaches
  WCAG AA's 3:1 non-text contrast minimum for every theme this component
  ships with depends on each theme's concrete color values and needs
  auditing per theme.
- **Minimum tap target**: Not applicable in a universal touch-target
  sense — this component targets a pointer-driven desktop environment,
  where a single fixed minimum hit-target size is not established the way
  it is for a touch interface (see Platform Notes for how this plays out
  on the source's platform). The help button's actual click area is not
  set explicitly in source; it takes its size from the platform's default
  sizing for a borderless, image-only, momentary-type button showing a
  15pt icon, which the source neither overrides nor measures.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-host-view-001 | replaces-content-on-set | Call the set-content operation with view A, then with view B | After the second call, view A is no longer a child of the content container; only view B is |
| panel-host-view-002 | clears-content-on-nil | Call the set-content operation with view A, then with no view | The content container has zero children after the second call |
| panel-host-view-003 | content-pinned-to-container-edges | Call the set-content operation with view A | View A's top/leading/trailing/bottom edges are each constrained equal to the content container's corresponding edge with zero constant |
| panel-host-view-004 | content-container-pinned-to-view-edges | Construct the component | The content container's top/leading/trailing/bottom edges are each constrained equal to the component's corresponding edge with zero constant |
| panel-host-view-005 | help-button-inset-from-content-container | Construct the component | The help button's top edge equals the content container's top edge + 12; its trailing edge equals the content container's trailing edge − 12 |
| panel-host-view-006 | help-button-above-content | Construct the component, then call the set-content operation with view A | The help button remains a child of the component (not of the content container) both before and after the call, and is not removed or reordered by it |
| panel-host-view-007 | help-button-visibility | Turn the show-help-button setting off with a help presenter assigned | The help button is hidden |
| panel-host-view-008 | help-button-visibility | Clear the help presenter with the show-help-button setting on | The help button is hidden |
| panel-host-view-009 | help-button-visibility | Turn the show-help-button setting on and assign a help presenter | The help button is visible |
| panel-host-view-010 | help-button-icon-reflects-visibility | Assign a presenter stub whose help-visible value is true | The help button's icon is the filled question-mark variant |
| panel-host-view-011 | help-button-icon-reflects-visibility | Assign a presenter whose help-visible value is false | The help button's icon is the outlined question-mark variant |
| panel-host-view-012 | help-button-symbol-configuration | Construct the component | The icon's rendering configuration reports point size 15 and weight regular |
| panel-host-view-013 | help-button-tint-reflects-visibility | Presenter reports help-visible as true while the active theme is "Solarized Dark" | The help button's tint color equals Solarized Dark's accent-color role |
| panel-host-view-014 | help-button-tint-reflects-visibility | Presenter reports help-visible as false while the active theme is "Solarized Dark" | The help button's tint color equals Solarized Dark's secondary-text-color role |
| panel-host-view-015 | help-button-tooltip-reflects-visibility | Presenter reports help-visible as true | The help button's tooltip reads "Hide Help" |
| panel-host-view-016 | help-button-tooltip-reflects-visibility | Presenter reports help-visible as false | The help button's tooltip reads "Show Help" |
| panel-host-view-017 | help-button-accessibility-label-fixed | Toggle help visible, then hidden | The help button's accessibility label reads "Help" in both states |
| panel-host-view-018 | help-button-borderless-image-only | Construct the component | The help button has no border, and shows only its icon, with no text label |
| panel-host-view-019 | help-button-momentary-type | Construct the component | The help button's activation model is momentary — it fires once per click and holds no on/off state |
| panel-host-view-020 | toggle-help-delegates-to-presenter | Assign a presenter, then invoke the toggle-help operation | The presenter's own toggle-help operation is invoked exactly once |
| panel-host-view-021 | toggle-help-delegates-to-presenter | With no help presenter assigned, invoke the toggle-help operation | No presenter method is invoked and no error occurs |
| panel-host-view-022 | help-anchor-claimed-when-button-shown | With the show-help-button setting on, assign a presenter | The presenter's anchor view is the help button |
| panel-host-view-023 | help-anchor-untouched-when-button-hidden | With the show-help-button setting off, assign a presenter whose anchor view was previously set to some other view | The presenter's anchor view is unchanged by the assignment |
| panel-host-view-024 | help-visibility-change-refreshes-button | With a presenter assigned, invoke the presenter's own visibility-change notification | The help button's icon/tint/tooltip are re-evaluated against the presenter's current help-visible value |
| panel-host-view-025 | help-visibility-change-notifies-external-observer | With an external visibility-change notification set, invoke the presenter's own visibility-change notification | The external notification is invoked exactly once, after the button refresh |
| panel-host-view-026 | presenter-reassignment | Call the set-help operation with content A, then assign a new help presenter | The new presenter receives the set-help operation with content A, its anchor view is claimed (if shown), and its visibility-change notification is this component's own callback |
| panel-host-view-027 | set-help-forwards-to-presenter | With a presenter assigned, call the set-help operation with no content | The presenter receives the set-help operation with no content and the help button is refreshed |
| panel-host-view-028 | is-help-visible-reflects-presenter-or-false | Query the help-visible value with no help presenter assigned | Returns false |
| panel-host-view-029 | is-help-visible-reflects-presenter-or-false | Query the help-visible value with a presenter whose own help-visible value is true | Returns true |
| panel-host-view-030 | shows-help-button-toggle | Toggle the show-help-button setting from off to on with a presenter assigned | The presenter's anchor view is claimed and the help button's hidden/icon/tint state is refreshed |
| panel-host-view-031 | theme-change-refreshes-button-tint | With help visible while the active theme is "Solarized Dark", switch the active theme to "Solarized Light" | The help button's tint color updates to Solarized Light's accent-color role without reconstructing the view |
| panel-host-view-032 | rejects-deserializing-construction | Attempt to construct the component via a deserializing/decoding-based construction path | The call traps or fails; no instance is returned |
| panel-host-view-033 | constraint-based-layout-only | Inspect the component, its content container, and its help button after construction | Each of the three relies solely on the layout-constraint system, with no manual frame assignment |
| panel-host-view-034 | help-button-keyboard-focusable | Construct the component, Tab focus to the visible help button, then press Space | The help button receives keyboard focus via Tab/Shift-Tab and its action fires on Space/Return, using the platform's own unmodified default focus and activation handling |

## Edge Cases

- **Null/empty input**: The set-content operation, given no view, MUST
  empty the content container rather than error (**clears-content-on-nil**).
  The set-help operation, given no content, MUST be forwarded to the
  presenter exactly like any other value (**set-help-forwards-to-presenter**);
  the source performs no special-casing between "no content" and populated
  help content beyond passing the value through.
- **Boundary values**: Not applicable in the numeric-input sense — the
  only fixed numeric value in source is the 12pt button-inset constant,
  which is not client-supplied and has no minimum/maximum to test.
- **Concurrent access**: Not applicable — the component is confined to
  the UI thread; construction or mutation of it from off that thread is
  rejected, so there is no concurrent-access surface to define behavior
  for.
- **Error states (dependency/network failure)**: Not applicable — the
  source performs no I/O, network call, or fallible operation; every
  method is a synchronous view/property update with no failure path.
- **Offline/disconnected state**: Not applicable — the source performs no
  networking of any kind.
- **Rapid, repeated set-content calls**: Each call independently tears
  down and rebuilds the content container's children
  (**replaces-content-on-set**); the source contains no debouncing or
  in-flight guard, so N calls in quick succession perform N full teardown
  cycles.
- **Help presenter reassigned to a different, non-empty instance while the
  previous presenter is still retained elsewhere**: The source's
  reassignment logic only ever touches the newly assigned presenter — it
  never clears the previously assigned presenter's own visibility-change
  notification. If a caller keeps a reference to the old presenter and it
  later fires its visibility-change notification on its own, this
  component's callback still runs and repaints the help button as if that
  stale presenter were still current. This is what the source's
  reassignment logic does, not an intentional safeguard.
- **The show-help-button setting toggled while help is currently
  visible**: Setting it off hides the button (**help-button-visibility**)
  but does not itself close help — the presenter's own help-visible value
  and any window drawer/popover the presenter owns are unaffected; only
  this component's own button disappears.
- **Anchor left stale when the button hides**: Per
  **help-anchor-untouched-when-button-hidden**, the component does not
  clear the assigned help presenter's anchor view when the show-help-button
  setting turns off — the presenter is left pointing at a now-hidden view.
  What a presenter does with a hidden anchor (for example guarding before
  presenting) is that presenter's own contract, not this component's.

## Configuration

The Panel Host View:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Help presenter | help-presenter reference, optional | absent | Where this view's help button opens and closes help, and reports visibility changes back. Absent hides the help button entirely. |
| Show help button | boolean | true | Whether this view draws its own help button. Set false for a window whose toolbar supplies help instead. |
| External visibility-change callback | optional callback | absent | Fired after help is disclosed or dismissed, for chrome outside this view (e.g. a toolbar button) that needs to mirror the same state. |

Its other public operations are: set the hosted content (accepting a
present view or none), set the help content (accepting present content or
none), toggle help, and query whether help is currently visible.

## Deep Linking

Not applicable: the component is chrome inside a settings window, not a
navigable screen; no URL scheme, route, or deep-link handler appears
anywhere in the source.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| — (hardcoded literal, no key) | Help | Help button's accessibility label, set once at construction |
| — (hardcoded literal, no key) | Help | Accessible description carried by both help-button icon variants |
| — (hardcoded literal, no key) | Show Help | Help button's tooltip while help is not visible |
| — (hardcoded literal, no key) | Hide Help | Help button's tooltip while help is visible |

All four strings above are set as plain string literals through the
platform's accessibility APIs (see Platform Notes), not through a
dedicated localizable-text position — a literal set this way is not
automatically localizable the way a framework's dedicated localized-text
mechanism is. No localization-catalog lookup appears anywhere in the
source.

## Accessibility Options

- **Reduce Motion**: Not applicable — the source contains no animation or
  transition of any kind. Content swapping and help-button refresh are
  both synchronous property and child-view assignments, not a motion
  effect.
- **Increase Contrast**: Not applicable in this file — the help button's
  colors come entirely from the active theme palette (accent-color role /
  secondary-text-color role); if Increase Contrast should raise either
  color's contrast, that is the palette/theme system's responsibility, not
  this component's. Whether these colors reach an adequate ratio is the
  open question on minimum-contrast-ratio, tracked once under
  Accessibility above.
- **Differentiate Without Color**: Supported — the help-visible and
  help-hidden states are distinguished by both the button's icon shape
  (filled vs. outlined) and its tint color
  (**help-button-icon-reflects-visibility**,
  **help-button-tint-reflects-visibility**), so color is never the sole
  signal.

## Feature Flags

Not applicable: the source contains no feature-flag lookup or conditional
gate; the component is constructed and behaves unconditionally whenever
its owning split creates one.

## Analytics

Not applicable: the source contains no analytics, tracking, or telemetry
call.

## Privacy

- **Data collected**: None — the component holds only the help content
  and the presenter/content-view references handed to it by its caller;
  it originates no data of its own.
- **Storage**: Not applicable — the source performs no persistence of any
  kind. (Whether help-visibility is remembered across launches is decided
  by the assigned help presenter's own implementation, outside this
  component's source — see Platform Notes for the source's own example.)
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: The currently installed content view and the most
  recently set help content are held in memory as private state for the
  component's own lifetime, and are replaced (not appended to) on every
  subsequent set-content/set-help call; nothing persists past
  deallocation.

## Logging

Not applicable: the source contains no logging call.

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
  `translatesAutoresizingMaskIntoConstraints = false` set on the view
  itself, the content container, and the help button, per
  **constraint-based-layout-only**. The two icon variants are the SF
  Symbols `questionmark.circle.fill`/`questionmark.circle`, rendered via
  `NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)`
  (**help-button-symbol-configuration**); the tint is the button's
  `contentTintColor`, driven from the active `SemanticPalette`'s
  `accentColor`/`secondaryTextColor`, refreshed on change via a
  `ThemePaletteObserver` (**theme-change-refreshes-button-tint**). The
  button is a borderless (`isBordered = false`), image-only
  (`imagePosition = .imageOnly`), momentary-change (`setButtonType(.momentaryChange)`)
  `NSButton`, and `help-button-keyboard-focusable` is satisfied simply by
  never overriding `acceptsFirstResponder`, `keyDown`, or `performClick`,
  so `NSButton`'s stock key-view-loop and Space/Return activation apply
  unmodified. The three accessibility/tooltip strings are set as plain
  `String` literals through `setAccessibilityLabel(_:)`,
  `NSImage(systemSymbolName:accessibilityDescription:)`, and `toolTip` —
  none of these is a SwiftUI `Text`/`LocalizedStringKey` position, and no
  `NSLocalizedString` call or string-catalog reference appears anywhere in
  source. `init?(coder:)` is marked `@available(*, unavailable)` and traps,
  satisfying `rejects-deserializing-construction`. Whether help visibility
  is remembered across launches is decided by whichever presenter is
  assigned — for example `HelpDrawerController`'s own `UserSettings`-backed
  preference — entirely outside this file. On the minimum-tap-target
  question: this component targets macOS only, where controls are
  pointer-operated, and Apple's Human Interface Guidelines do not set a
  single numeric minimum hit-target size for a pointer-driven AppKit
  control the way they do for an iOS touch target (44×44pt); the button's
  actual click area comes from `NSButton`'s default cell sizing for this
  configuration, unmeasured and unoverridden here. A UIKit port would use a
  `UIView` overlaying a `UIButton(configuration: .plain())` pinned with
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
solely on the show-help-button setting and whether a help presenter is
assigned — never on whether the panel currently on screen has any help
content.
**Rationale**: per the source's own comment on `updateHelpButton()`, it used
to come and go with `help != nil`, which "put a control in the corner of
some panels and not others and made the drawer look like a property of
the panel rather than of the window."
**Approved**: pending

**Decision**: The anchor-claiming step re-runs unconditionally on every
help-presenter assignment and every show-help-button change, rather than
claiming the anchor once at construction.
**Rationale**: per the source's own comment on `claimHelpAnchorIfShown()`,
claiming the anchor only once meant a later help-presenter reassignment
"silently took it back" from whoever held it, "and handed a popover
presenter a hidden, zero-size view to hang off."
**Approved**: pending

**Decision**: Route chrome outside this view (e.g. a toolbar help button)
through a dedicated external visibility-change callback rather than
sharing the help presenter's own visibility-change notification directly.
**Rationale**: per the source's own comment on this callback, the
presenter's own visibility-change notification "has exactly one slot" and
this view claims it for its own inline button; anything else that needs
the same notification has to be told by whoever holds that slot rather
than overwriting it.
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

Statuses rest on: every color coming from the theme palette, with the
help-visible/hidden distinction carried by both icon shape and tint, never
color alone (platform-theming); the help button being a stock button
control with no override that removes it from the key-view loop or blocks
its default activation (keyboard-navigable); the fixed accessibility label
never reflecting the toggled visibility state, with no explicit
accessibility-change announcement anywhere in source
(screen-reader-support — see Accessibility); the accent/secondary-text
colors carrying no enforced minimum-contrast floor evaluated in this file
(contrast-ratio — see Accessibility); and the four accessibility-label/tooltip
strings being set as plain platform string literals with no localization-catalog
reference anywhere in source (no-hardcoded-strings,
string-externalization — see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved private source identifiers (`buttonInset`, `NSView.pinToEdges`) and AppKit-specific mechanics (`constraint-based-layout-only`, `help-button-momentary-type`) out of requirement bodies and into Platform Notes; merged and renamed condition-laden requirement names to subject-only form (`help-button-visibility`, `presenter-reassignment`, `shows-help-button-toggle`); promoted the implicit keyboard-focus guarantee to a named requirement (`help-button-keyboard-focusable`) with a conformance vector; moved the stale-presenter-callback observation out of Design Decisions (it was a bug, not an approved choice) and left it as the single Edge Case description; trimmed the popover edge case to what this component guarantees; reformatted Design Decisions to the bold three-line form; fixed Compliance statuses and pruned Compliance rows to checks that exist in the catalog; named concrete conformance-vector fixtures (Solarized Dark/Light, `ThemeManager.selectTheme(id:)`) and precise call sequences; removed the unsupported WinUI 3 parenthetical; and listed related ingredients in frontmatter. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/layout/. |
