<!-- leaf: implement-general-view-2/radio-button-choice-view · source: radio-button-choice-view.md -->

**Rules** (cite as `implement-general-view-2/radio-button-choice-view#<slug>`):

- `arranges-heading-above-controls-stack` MUST
- `builds-one-radio-button-per-choice` MUST
- `lays-out-controls-along-axis` MUST
- `aligns-controls-stack-by-axis` MUST
- `spaces-stacks-by-row-spacing` MUST
- `initializes-from-view-model` MUST
- `commits-radio-selection` MUST
- `skips-redundant-commits` MUST
- `ignores-unmatched-sender` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST

# RadioButtonChoiceView

## Overview

`RadioButtonChoiceView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/RadioButtonChoiceView.swift`):
a title label sitting above a stack of native `NSButton` radio buttons, one
per entry in a `ChoiceViewModel<Value>`'s `choices` array, each button's own
title text set to that choice's `label`. Unlike its sibling row views over the
same `ChoiceViewModel` (`ChoiceSliderView`, `PopupMenuChoiceView`),
`RadioButtonChoiceView` does not use `ComposableSettings.makeRow`'s single
horizontal `[label, spacer, control]` layout; it composes two nested
`NSStackView`s instead — an outer vertical stack of `[label, controlsStack]`,
and an inner `controlsStack` holding the radio buttons themselves, oriented by
the constructor's `axis` parameter (`.vertical` by default). The row is driven
by `ChoiceViewModel<Value>`: the view reflects the view model's title/value on
construction and whenever the view model reports an external change, and it
writes the user's radio-button selection back into the view model's
`settingObserver`. `ChoiceViewModel.Choice` also carries an optional
`imageSystemName`, but `RadioButtonChoiceView` never reads that field — only
`PopupMenuChoiceView`, a sibling row over the same view model, renders it.

## Behavioral Requirements

- **arranges-heading-above-controls-stack**: Component MUST arrange the title
  label above a group of choice controls in a single outer, vertical
  container (`[label, controls group]`), and MUST pin that outer container to
  the edges of the view.
- **builds-one-radio-button-per-choice**: Component MUST create one
  radio-type choice control for each entry in `viewModel.choices`, in the
  same order, using that choice's `label` as the control's own visible text.
- **lays-out-controls-along-axis**: Component MUST arrange the created
  choice controls, in order, inside a single controls group whose layout
  orientation is set to the constructor's `axis` parameter (default
  `.vertical`).
- **aligns-controls-stack-by-axis**: Component MUST align the controls group
  along its leading edge when `axis` is `.vertical`, and along a shared first
  baseline when `axis` is not `.vertical`.
- **spaces-stacks-by-row-spacing**: Component MUST set both the spacing
  between the label and the controls group, and the spacing between each
  control within the group, to `SettingsLayout.default[.rowSpacing]`.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title`, and select the
  choice control whose associated choice `value` equals `viewModel.value`
  while deselecting every other choice control.
- **commits-radio-selection**: Component MUST write the value paired with the
  choice control that fired the selection action into
  `viewModel.settingObserver.value` whenever that value differs from the
  current `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the firing control's paired value
  equals the current `settingObserver.value`.
- **ignores-unmatched-sender**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the control that fired the
  selection action is not present in the component's recorded
  control-value pairs.
- **syncs-on-external-change**: Component MUST re-set the label's text from
  `viewModel.title`, and re-select the choice control matching
  `viewModel.value` while deselecting the rest, whenever `viewModel.onChange`
  fires.
- **exposes-constituent-views**: Component MUST expose the heading label and
  the ordered list of choice controls as public, directly-accessible
  properties; the choice-controls list MUST NOT be publicly replaceable as a
  whole (readable from outside the type, but not externally settable).
- **requires-designated-initializer**: Component MUST NOT support
  construction through a serialization/coder-based initializer; that
  construction path MUST trigger a fatal error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction through a frame/bounds-only initializer that bypasses the
  required view-model parameter; that construction path MUST trigger a fatal
  error.
- **confines-to-main-actor**: Component MUST be usable only on the UI (main)
  thread of execution.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock `NSTextField` label and stock
  `NSButton` radio buttons into two nested stacks.
- **Padding**: Component does not use `ComposableSettings.makeRow` (no
  spacer, no forced content-hugging priorities). The outer `NSStackView`
  (`[label, controlsStack]`) is vertical, `alignment = .leading`, `spacing =
  SettingsLayout.default[.rowSpacing]` = 8pt. `controlsStack` itself uses the
  same 8pt `spacing`, applied between each radio button along whichever axis
  it is laid out on. `pinToEdges` pins the outer stack's
  top/leading/trailing/bottom directly to `RadioButtonChoiceView`'s edges
  with no additional constant, so the component contributes 0pt of its own
  outer padding beyond that internal 8pt spacing.
- **Font**: The heading label (`ComposableSettings.makeRowLabel`, via
  `Self.createLabel(title:)`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font, scaling with the active theme's `sizeScale` and repainting
  automatically on a theme change (`ThemePaletteObserver`). Each radio
  button's own title text, by contrast, comes from AppKit's stock
  `NSButton(radioButtonWithTitle:)` factory, not from `ThemedLabel` — it
  renders in AppKit's native control font and does not participate in the
  app's theme `sizeScale` or repaint-on-theme-change path the heading label
  uses.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, `isBezeled = false` on the
  heading label; neither `RadioButtonChoiceView` nor either `NSStackView`
  sets `wantsLayer` or a background color of its own. Each radio button's
  background is AppKit's native, unthemed `NSButton` rendering.
- **Foreground/Text**: The heading label (`role: .primaryText`) resolves to
  the active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change. Each radio button's title
  text color is AppKit's own system rendering; `RadioButtonChoiceView` sets
  no color on any `radioButtons` element.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `RadioButtonChoiceView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `RadioButtonChoiceView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `RadioButtonChoiceView.swift`; sizing is governed
  entirely by the label's and each `NSButton`'s own intrinsic content size,
  the two stacks' 8pt spacing, and `pinToEdges`.

## Accessibility

- **Role/trait**: Not customized beyond AppKit's own defaults — no
  `setAccessibilityRole` call appears anywhere in source. Each `NSButton`
  produced by `radioButtonWithTitle:target:action:` carries AppKit's built-in
  radio-button accessibility role and reports its own visible title text
  (the choice's `label`) as its accessible name automatically — unlike a
  bare, title-less control, each button here is already individually named.
- **Label requirements**: Not implemented in source. Source sets no
  accessibility API at all on `label`, `controlsStack`, or any
  `radioButtons` element — no `setAccessibilityTitleUIElement`, no
  accessibility group role, no `accessibilityChildren` linkage tying the
  heading `label` (e.g. "Theme") to the set of radio buttons beneath it as
  one named group. This is confirmed by comparison with `CheckboxView`, a
  sibling row, which does call
  `toggle.setAccessibilityTitleUIElement(self.label)` for its single
  control; VoiceOver has no source-declared link between the heading's
  text and the radio-button group, so each button's own visible title is
  the only accessible name it reports.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself in source (see
  States); a selection change is announced by `NSButton`'s own native
  accessibility value reporting when `state` changes, which
  `RadioButtonChoiceView` does not override.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. `RadioButtonChoiceView` sets no
  `controlSize` on any `radioButtons` element, so each keeps `NSButton`'s
  regular system click-target metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The heading `label` text color resolves from the active theme's `.primaryText` role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file, which would be settled by a theme-level contrast audit of `.primaryText` against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ChoiceViewModel<Value>` | — (required) | Supplies the row's title, the ordered `choices` list, and the current value; receives committed radio-button changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases). `Choice.imageSystemName` is accepted by the type but never read by `RadioButtonChoiceView` (see Overview). |
| `axis` | `NSUserInterfaceLayoutOrientation` | `.vertical` | Sets `controlsStack.orientation` and, through the `(axis == .vertical) ? .leading : .firstBaseline` ternary, `controlsStack.alignment`. Has no effect on the outer `[label, controlsStack]` stack, which is always vertical. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `button.state`). |
| Increase Contrast | Not applicable — `RadioButtonChoiceView.swift` sets no custom `NSColor` on any `radioButtons` element; the heading label's color comes from the theme's `.primaryText` role, and `NSButton`'s radio-dot/track colors follow AppKit's default rendering, which tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable — the selected choice is communicated through `NSButton`'s own filled-vs-empty radio-dot iconography and each button's own visible title text, not through a color-only signal introduced by this component. |

