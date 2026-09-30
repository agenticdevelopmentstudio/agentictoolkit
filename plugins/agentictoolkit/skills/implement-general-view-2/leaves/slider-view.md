<!-- leaf: implement-general-view-2/slider-view · source: slider-view.md -->

**Rules** (cite as `implement-general-view-2/slider-view#<slug>`):

- `arranges-row-layout` MUST
- `sets-slider-range` MUST
- `slider-hugs-loosely` MUST
- `initializes-from-view-model` MUST
- `commits-slider-value` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-views` MUST
- `rejects-coder-initialization` MUST
- `rejects-frame-only-initialization` MUST

# SliderView

## Overview

`SliderView` is a macOS `ComposableSettings` row: a title label and an
`NSSlider` in one horizontal row, with no trailing caption (contrast with
the sibling `CaptionedSliderView`, which adds a formatter-derived value
label). The row is driven by a `RangeViewModel<Double>`: the view sets the
slider's range and value from the view model at construction, writes the
user's slider interactions back into the view model's `settingObserver`,
and re-synchronizes the label text and the slider's range and value
whenever the view model reports an external change — including the range,
which the sibling `CaptionedSliderView` does not re-apply after
construction.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  slider in a single horizontal row, and MUST pin that row to the edges of
  the view.
- **sets-slider-range**: Component MUST set the slider's `minValue` and
  `maxValue` from `viewModel.minValue` and `viewModel.maxValue` at
  initialization.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the inter-item spacing, takes the width
  left over after the label.
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and the
  slider's value to `viewModel.value`.
- **commits-slider-value**: Component MUST write the slider's new value
  into `viewModel.settingObserver.value` whenever the slider's action
  fires and the new value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-synchronize the label's
  text and the slider's `minValue`, `maxValue`, and `doubleValue` —
  re-reading `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`,
  and `viewModel.value` — whenever `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and
  `slider` as public, directly-accessible properties.
- **rejects-coder-initialization**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes stock `NSTextField`/`NSSlider`
  instances into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between the label and the slider (`[label, spacer, slider]`) and sets
  the `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` =
  8pt; that 8pt gap applies between label→spacer, while `makeRow`
  explicitly zeroes the spacer→slider gap
  (`setCustomSpacing(0, after: spacer)`) so the spacer's own width is the
  only thing between the label and the slider. `pinToEdges` pins the
  row's top/leading/trailing/bottom directly to `SliderView`'s edges with
  no additional constant, so the component contributes 0pt of its own
  outer padding beyond that internal 8pt / 0pt spacing.
- **Font**: The label (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography`'s `.button` style: 13pt, medium weight, proportional
  system font (`ThemeTypography.swift`: `case .button: return
  FontStyle(size: 13, weight: .medium)`). The size scales with the active
  theme's `sizeScale` and the label repaints automatically on a theme
  change via `ThemePaletteObserver` (`ThemedLabel.applyTheme` re-reads
  `palette.font(textRole)` on every palette update).
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on the label, and neither `SliderView` nor the row `NSStackView` sets
  `wantsLayer` or a background color of its own. The slider is a plain,
  unconfigured `NSSlider()` using AppKit's default rendering.
- **Foreground/Text**: The label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.color(.primaryText)`, exposed as
  `SemanticPalette.primaryText`), recomputed live on a theme change via
  `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `SliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `SliderView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `SliderView.swift`; the slider's width is governed
  entirely by the horizontal content-hugging priority (`1`) set in
  `init`, with no compression-resistance override on either subview.

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSSlider` and `NSTextField` each carry AppKit's
  built-in accessibility role (slider, static text) automatically.
- **Label requirements**: The label and the slider are laid out as
  sibling views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  the slider linking it to the label text — confirmed by comparison with
  sibling row views in the same directory: `CheckboxView.swift`,
  `NumberFieldView.swift`, and `PopupMenuChoiceView.swift` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their
  control, but `SliderView.swift` does not do so for `slider`. Without
  that link, VoiceOver announces the slider on its own with no reference
  to the row's title when focus lands on it.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The label's text color resolves via `SemanticPalette`'s `primaryText` role, whose floor against the background is `minContrast: 3.0` (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`) — below the 4.5:1 small-text threshold — and the component performs no contrast check of its own; settling whether a given theme's resolved pair actually meets 4.5:1 needs a theme-level contrast audit of primaryText against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `RangeViewModel<Double>` | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own re-sync handler (see Edge Cases). |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: Not applicable — `SliderView.swift` sets no
  custom `NSColor` anywhere; whatever coloring the row has comes entirely
  from `ThemedLabel`'s palette-driven text color and `NSSlider`'s default
  AppKit rendering, both of which follow system Increase Contrast
  automatically.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated only through the slider's thumb position; there is no
  caption or other color-coded signal in source to differentiate.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  slider changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `RangeViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  and its reference to `viewModel` for its own lifetime; it persists
  nothing beyond that.

