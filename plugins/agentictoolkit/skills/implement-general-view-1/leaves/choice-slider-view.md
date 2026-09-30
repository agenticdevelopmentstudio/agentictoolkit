<!-- leaf: implement-general-view-1/choice-slider-view · source: choice-slider-view.md -->

**Rules** (cite as `implement-general-view-1/choice-slider-view#<slug>`):

- `arranges-row-layout` MUST
- `builds-tick-marks-from-choices` MUST
- `flanking-labels-hug-tightly` MUST
- `slider-hugs-loosely` MUST
- `fixes-value-label-width` MUST
- `initializes-from-view-model` MUST
- `claims-onchange-observer` MUST
- `commits-slider-value` MUST
- `ignores-out-of-range-tick` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `leaves-display-unchanged-for-unmatched-value` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `stretches-to-superview-width` MUST
- `confines-to-main-actor` MUST

# ChoiceSliderView

## Overview

`ChoiceSliderView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ChoiceSliderView.swift`):
a title label, a discrete `NSSlider` whose ticks each correspond to one entry
in a `ChoiceViewModel<Value>`'s `choices` array, and a trailing label showing
the current choice's `label` text. Per the source's own doc comment, the
slider "snaps to ticks only" — it never represents a value between two
choices. The row is driven by `ChoiceViewModel<Value>`: the view reflects the
view model's title/value on construction and whenever the view model reports
an external change, and it writes the user's slider interactions back into
the view model's `settingObserver`. `ChoiceViewModel.Choice` also carries an
optional `imageSystemName`, but `ChoiceSliderView` never reads that field —
only `PopupMenuChoiceView`, a sibling row over the same view model, renders
it.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label, the
  slider, and the value label in a single horizontal row, and MUST pin that
  row to the edges of the view.
- **builds-tick-marks-from-choices**: Component MUST, at initialization, set
  the slider's `minValue` to `0`, its `maxValue` to
  `Double(max(viewModel.choices.count - 1, 0))`, its `numberOfTickMarks` to
  `viewModel.choices.count`, and its `allowsTickMarkValuesOnly` to `true`.
- **flanking-labels-hug-tightly**: Component MUST set both the title label's
  and the value label's horizontal content-hugging priority to `.required`.
- **slider-hugs-loosely**: Component MUST set the slider's horizontal
  content-hugging priority to `1` — below the row spacer's `defaultLow`
  priority — so the slider, not the title label or the value label, takes
  the width left over after the row is laid out.
- **fixes-value-label-width**: Component MUST size the value label's width to
  a fixed constant equal to the ceiling of the widest rendered width, among
  `viewModel.choices`' `label` strings, measured in the value label's own
  font (falling back to the current theme palette's caption font when the
  value label's font is `nil`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the title label's text to `viewModel.title`, and —
  when `viewModel.value` matches a choice's `value` — set the slider's
  `doubleValue` to that choice's index and the value label's text to that
  choice's `label`.
- **claims-onchange-observer**: Component MUST assign its own handler to
  `viewModel.onChange` during initialization, replacing any handler already
  registered there.
- **commits-slider-value**: Component MUST write the matching choice's
  `value` into `viewModel.settingObserver.value` when the slider's action
  fires (see ignores-out-of-range-tick and skips-redundant-commits for the
  guard conditions).
- **ignores-out-of-range-tick**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the slider action's rounded index
  falls outside `viewModel.choices.indices`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the resolved choice's value equals
  the current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the title label's text
  from `viewModel.title`, and — when `viewModel.value` matches a choice —
  re-set the slider's `doubleValue` and the value label's text, whenever
  `viewModel.onChange` fires.
- **leaves-display-unchanged-for-unmatched-value**: Component MUST NOT alter
  the slider's `doubleValue` or the value label's text when
  `viewModel.value` does not match any choice's `value`, whether at
  initialization or on a later `viewModel.onChange` call.
- **exposes-constituent-views**: Component MUST expose `label`, `slider`, and
  `valueLabel` as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **stretches-to-superview-width**: Component MUST, once it is added to a
  superview, activate a width constraint pinning itself to that superview's
  full width, at a priority one step below `.required`.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes stock `NSTextField`/`NSSlider` instances
  into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer between
  the title label and the remaining views (`[label, spacer, slider,
  valueLabel]`) and sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt, which applies to the
  label→spacer and slider→valueLabel gaps; `makeRow` explicitly zeroes the
  spacer→slider gap (`setCustomSpacing(0, after: spacer)`), so the spacer's
  own width is the only thing between the title label and the slider.
  `pinToEdges` pins the row's top/leading/trailing/bottom directly to
  `ChoiceSliderView`'s edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal spacing.
- **Font**: Title label (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font. Value label (`makeValueLabel()`, `textRole: .caption` — the
  default, since `ChoiceSliderView` passes no `monospacedDigits: true`)
  resolves to `ThemeTypography.defaultStyle(.caption)`: 11pt, regular
  weight, proportional system font. Both sizes scale with the active
  theme's `sizeScale` (`1.0` by default) and both labels repaint
  automatically on a theme change via `ThemePaletteObserver`.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on both labels, and neither `ChoiceSliderView` nor the row `NSStackView`
  sets `wantsLayer` or a background color of its own.
- **Foreground/Text**: Title label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength. Value label (`role:
  .secondaryText`) resolves to that same foreground dimmed 32% toward the
  background color, with a minimum contrast ratio of 3.0 enforced
  (`foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)`).
  Both recompute live on a theme change via `ThemePaletteObserver`.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `ChoiceSliderView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `ChoiceSliderView.swift`.
- **Min/Max size**: The value label carries a fixed `widthAnchor` constraint
  equal to `ceil(longestLabelWidth)`, computed once at initialization from
  `viewModel.choices.map(\.label)` (see fixes-value-label-width); no other
  view in the row has an explicit min/max constraint. Separately, once the
  component is added to a superview, it activates a width constraint equal
  to that superview's full width, at priority `.required - 1` (see
  stretches-to-superview-width).

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call appears
  in source. `NSSlider` and `NSTextField` each carry AppKit's built-in
  accessibility role (slider, static text) automatically.
- **Label requirements**: The title label (`label`) and the slider are laid
  out as sibling views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on the
  slider linking it to the title text — unlike `PopupMenuChoiceView`, the
  sibling row over the same `ChoiceViewModel<Value>`, which calls
  `self.popUpButton.setAccessibilityTitleUIElement(self.label)` on its
  control. VoiceOver focus on the slider is therefore not programmatically
  tied to the row's title text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself (see States);
  there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ChoiceViewModel<Value>` | — (required) | Supplies the row's title, the ordered `choices` list, and the current value; receives committed slider changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `syncSelection` handler (see Edge Cases). `Choice.imageSystemName` is accepted by the type but never read by `ChoiceSliderView` (see Overview). |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable — source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment. |
| Increase Contrast | Partial — the title label uses the theme's foreground color at full strength, which tracks system Increase Contrast normally, but the value label's color is theme-computed as `foreground.dimmed(towards: background, by: 0.32, minContrast: 3.0)` (see Foreground/Text): it enforces its own fixed 3.0 minimum contrast ratio rather than responding to the system's Increase Contrast setting. |
| Differentiate Without Color | Not applicable — the current choice is communicated through the slider's tick position and the value label's text, not through any color-only signal; no color-coded state exists in source. |

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports slider
  changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ChoiceViewModel`/`settingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews and
  its reference to `viewModel` for its own lifetime; it persists nothing
  beyond that.

