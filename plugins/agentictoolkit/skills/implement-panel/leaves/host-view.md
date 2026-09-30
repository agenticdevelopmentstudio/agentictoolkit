<!-- leaf: implement-panel/host-view · source: panel-host-view.md -->

**Rules** (cite as `implement-panel/host-view#<slug>`):

- `replaces-content-on-set` MUST
- `clears-content-on-nil` MUST
- `content-pinned-to-container-edges` MUST
- `content-container-pinned-to-view-edges` MUST
- `help-button-inset-from-content-container` MUST
- `help-button-above-content` MUST
- `help-button-visibility` MUST
- `help-button-icon-reflects-visibility` MUST
- `help-button-symbol-configuration` MUST
- `help-button-tint-reflects-visibility` MUST
- `help-button-tooltip-reflects-visibility` MUST
- `help-button-accessibility-label-fixed` MUST
- `help-button-keyboard-focusable` MUST
- `help-button-borderless-image-only` MUST
- `help-button-momentary-type` MUST
- `toggle-help-delegates-to-presenter` MUST
- `help-anchor-claimed-when-button-shown` MUST
- `help-anchor-untouched-when-button-hidden` MUST
- `help-visibility-change-refreshes-button` MUST
- `help-visibility-change-notifies-external-observer` MUST
- `presenter-reassignment` MUST
- `set-help-forwards-to-presenter` MUST
- `is-help-visible-reflects-presenter-or-false` MUST
- `shows-help-button-toggle` MUST
- `theme-change-refreshes-button-tint` MUST
- `rejects-coder-initialization` MUST
- `constraint-based-layout-only` MUST

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

