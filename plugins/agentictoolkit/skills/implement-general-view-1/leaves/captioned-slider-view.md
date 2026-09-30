<!-- leaf: implement-general-view-1/captioned-slider-view · source: captioned-slider-view.md -->

**Rules** (cite as `implement-general-view-1/captioned-slider-view#<slug>`):

- `arranges-row-layout` MUST
- `sets-slider-range` MUST
- `does-not-validate-range` MUST
- `slider-hugs-loosely` MUST
- `caption-resists-compression` MUST
- `caption-uses-monospaced-digits` MUST
- `initializes-from-view-model` MUST
- `updates-caption-live` MUST
- `commits-slider-value` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `overwrites-view-model-onchange` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST

# CaptionedSliderView

## Overview

`CaptionedSliderView` is a macOS `ComposableSettings` row: a title label, an
`NSSlider`, and a trailing caption label in one horizontal row. The caption
shows the slider's current value rendered through a caller-supplied
formatter (e.g. `{ "\(Int($0 * 100))%" }` or `{ "\(Int($0))s" }`), for use
when the slider's handle position alone doesn't identify the current value.
The row is driven by a `RangeViewModel<Double>`: the view reflects the view
model's title/min/max/value on construction and whenever the view model
reports an external change, and it writes the user's slider interactions
back into the view model's `settingObserver`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the caption label in a single horizontal row, and MUST pin
  that row to the edges of the view.
- **sets-slider-range**: Component MUST set the slider's `minValue` and
  `maxValue` from `viewModel.minValue` and `viewModel.maxValue` at
  initialization.
- **does-not-validate-range**: Component MUST NOT validate or correct
  `viewModel.minValue`/`viewModel.maxValue` before assigning them to the
  slider's `minValue`/`maxValue`; an inverted or zero-width range is passed
  through unmodified.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the inter-item spacing, takes the width
  left over after the label and caption are laid out.
- **caption-resists-compression**: Component MUST set the caption label's
  horizontal compression-resistance priority to `.required` so the caption
  is never compressed.
- **caption-uses-monospaced-digits**: Component MUST render the caption
  label with monospaced digit glyphs (built via
  `ComposableSettings.makeValueLabel(monospacedDigits: true)`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to `viewModel.title`, the
  slider's value to `viewModel.value`, and the caption label's text to
  `formatter(viewModel.value)`.
- **updates-caption-live**: Component MUST update the caption label's text
  to `formatter(newValue)` immediately whenever the slider's action fires
  with a new value, independent of any round trip through the view model.
- **commits-slider-value**: Component MUST write the slider's new value
  into `viewModel.settingObserver.value` whenever the slider's action
  fires and the new value differs from the current
  `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-synchronize the title
  label's text, the slider's value, and the caption label's text —
  re-reading `viewModel.title` and `viewModel.value` — whenever
  `viewModel.onChange` fires.
- **overwrites-view-model-onchange**: Component MUST overwrite
  `viewModel.onChange` with its own sync handler
  (`{ [weak self] _ in self?.sync() }`) during initialization, replacing
  whatever handler, if any, was previously registered on that view model.
- **exposes-constituent-views**: Component MUST expose `label`, `slider`,
  and `captionLabel` as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
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
  between the label and the remaining views (`[label, spacer, slider,
  captionLabel]`) and sets the `NSStackView`'s `spacing` to the
  `SettingsLayout.rowSpacing` token — owned and currently set to 8pt by
  `ComposableSettings.SettingsLayout.default` in
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/ViewLayout.swift`,
  not by `CaptionedSliderView.swift`. That gap applies between
  label→spacer and slider→captionLabel, while `makeRow` explicitly zeroes
  the spacer→slider gap (`setCustomSpacing(0, after: spacer)`) so the
  spacer's own width is the only thing between the label and the slider.
  `pinToEdges` pins the row's top/leading/trailing/bottom directly to
  `CaptionedSliderView`'s edges with no additional constant, so the
  component contributes 0pt of its own outer padding beyond that internal
  token-driven / 0pt / token-driven spacing.
- **Font**: Title label (`ComposableSettings.makeRowLabel`) uses text role
  `.button`; caption label (`ComposableSettings.makeValueLabel
  (monospacedDigits: true)`) uses text role `.code`. Neither role's size
  or weight is set in `CaptionedSliderView.swift`: `SettingsLabels.swift`
  (same directory as the source file) only picks the role, and
  `ThemeTypography.defaultStyle(_:)` in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/ThemeTypography.swift`
  owns the resolved point size and weight per role — currently 13pt
  medium, proportional system font for `.button`, and 12pt regular,
  monospaced for `.code`. Both sizes scale with the active theme's
  `sizeScale` (`1.0` by default) and both labels repaint automatically on
  a theme change via `ThemePaletteObserver`.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled =
  false` on both the title and caption labels, and neither
  `CaptionedSliderView` nor the row `NSStackView` sets `wantsLayer` or a
  background color of its own.
- **Foreground/Text**: Title label uses `SemanticPalette` role
  `.primaryText`; caption label uses role `.secondaryText`. Neither
  color is computed in `CaptionedSliderView.swift`:
  `SemanticPalette.derive(_:)` in
  `external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/SemanticPalette.swift`
  owns both — `.primaryText` currently resolves to the active theme's
  foreground color at full strength, and `.secondaryText` currently
  resolves to that same foreground dimmed 32% toward the background
  color with a minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast:
  3.0)`). Both recompute live on a theme change via
  `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `CaptionedSliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `CaptionedSliderView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `CaptionedSliderView.swift`; sizing is governed
  entirely by the content-hugging (`1`, slider) and
  compression-resistance (`.required`, caption) priorities set on the
  row's constituent views.

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSSlider` and `NSTextField` each carry AppKit's
  built-in accessibility role (slider, static text) automatically.
- **Label requirements**: The title label (`label`) and the slider are
  laid out as sibling views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  the slider linking it to the title text — confirmed by comparison with
  sibling row views in the same directory: `CheckboxView`,
  `NumberFieldView`, and `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their
  control, but neither `CaptionedSliderView` nor the plain `SliderView`
  it's modeled on does so for `slider`. Without that link, VoiceOver
  announces the slider on its own when focus lands on it, with no
  route to the row's title text, unlike the sibling control-with-label
  rows.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path
  in source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `RangeViewModel<Double>` | — (required) | Supplies the row's title and min/max/current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `formatter` | `@MainActor (Double) -> String` | — (required) | Maps the current or in-progress slider value to the caption text shown at the trailing edge of the row (e.g. a percentage or seconds string). |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: `CaptionedSliderView.swift` itself sets no custom
  `NSColor`; both labels get their color from `SemanticPalette` roles
  (`.primaryText` for the title, `.secondaryText` for the caption) via
  `ThemedLabel`, not from AppKit's unstyled control defaults (see
  Appearance → Foreground/Text). `SemanticPalette.derive(_:)`
  (`external/agenticdevelopertoolkit/packages/apple/AgenticDeveloperToolkit/Sources/Theme/SemanticPalette.swift`)
  does not read `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`
  or any other system Increase Contrast signal, so the row's contrast
  does not change when a user turns that system setting on; whatever the
  active theme's colors resolve to is what both labels show either way.
- **Differentiate Without Color**: Not applicable — the current value is
  communicated through the slider's thumb position and the caption's
  text, not through any color-only signal; no color-coded state exists in
  source.

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
  and its reference to `viewModel`/`formatter` for its own lifetime; it
  persists nothing beyond that.

