<!-- leaf: implement-general-view-2/stepper-view · source: stepper-view.md -->

**Rules** (cite as `implement-general-view-2/stepper-view#<slug>`):

- `arranges-row-layout` MUST
- `builds-label-from-view-model-title` MUST
- `builds-value-label-monospaced` MUST
- `resists-value-label-compression` MUST
- `configures-stepper-bounds` MUST
- `fixes-stepper-increment` MUST
- `disables-stepper-wraparound` MUST
- `initializes-stepper-value` MUST
- `wires-stepper-action` MUST
- `initializes-value-label-text` MUST
- `updates-value-label-on-change` MUST
- `commits-stepper-value` MUST
- `skips-redundant-commits` MUST
- `replaces-view-model-onchange` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-views` MUST
- `rejects-coder-initialization` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST

# StepperView

## Overview

`StepperView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/StepperView.swift`):
a title label leading, a monospaced numeric value label, and a trailing
`NSStepper`, bound to a `RangeViewModel<Int>`. Per the source's own doc
comment, it is for "small bounded counts (recents, retry limits, etc.) where
a slider's resolution is wrong but a free text field is too unbounded."
Unlike its sibling row types (`CheckboxView`'s `NSSwitch`, `IntegerFieldView`'s
text field), `NSStepper` draws no visible number of its own — only up/down
arrows — so `StepperView` pairs it with a separate `valueLabel` that the
component keeps in sync with the stepper's value on every change.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label`, `valueLabel`, and
  `stepper` in that order in a single horizontal row and MUST pin that row to
  the edges of the view.
- **builds-label-from-view-model-title**: `label` MUST be built via
  `ComposableSettings.makeRowLabel(viewModel.title)`.
- **builds-value-label-monospaced**: `valueLabel` MUST be built via
  `ComposableSettings.makeValueLabel(monospacedDigits: true)`.
- **resists-value-label-compression**: Component MUST set `valueLabel`'s
  horizontal content compression resistance priority to `.required`.
- **configures-stepper-bounds**: Component MUST set `stepper.minValue` to
  `Double(viewModel.minValue)` and `stepper.maxValue` to
  `Double(viewModel.maxValue)`.
- **fixes-stepper-increment**: Component MUST set `stepper.increment` to `1`,
  independent of the view model's range.
- **disables-stepper-wraparound**: Component MUST set `stepper.valueWraps` to
  `false`.
- **initializes-stepper-value**: Component MUST set `stepper.integerValue` to
  `viewModel.value` on construction.
- **wires-stepper-action**: Component MUST set `stepper.target` to itself and
  `stepper.action` to its `stepperChanged(_:)` selector.
- **initializes-value-label-text**: Component MUST set `valueLabel.stringValue`
  to the string form of `viewModel.value` on construction.
- **updates-value-label-on-change**: Whenever `stepperChanged(_:)` fires,
  component MUST set `valueLabel.stringValue` to the string form of the
  stepper's new `integerValue`, regardless of whether that value is committed.
- **commits-stepper-value**: Whenever `stepperChanged(_:)` fires and the
  stepper's new `integerValue` differs from `viewModel.settingObserver.value`,
  component MUST write the new value into `viewModel.settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the stepper's new value equals the
  current `settingObserver.value`.
- **replaces-view-model-onchange**: Component's initializer MUST assign its
  own closure to `viewModel.onChange`, unconditionally replacing whatever
  handler (if any) was previously registered on that view model instance.
- **syncs-on-external-change**: Whenever `viewModel.onChange` fires, component
  MUST re-set `label.stringValue`, `stepper.minValue`/`stepper.maxValue`,
  `stepper.integerValue`, and `valueLabel.stringValue` from `viewModel`.
- **exposes-constituent-views**: Component MUST expose `label`, `stepper`, and
  `valueLabel` as public, directly-accessible properties.
- **rejects-coder-initialization**: Component MUST NOT support construction
  via `init(coder:)`; that initializer MUST trigger a fatal error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main actor;
  the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes two stock `NSTextField`s and a stock
  `NSStepper` into a row.
- **Padding**: `ComposableSettings.makeRow([label, valueLabel, stepper])`
  passes three views, so `makeRow` inserts its flexible spacer at index 1 —
  between `label` and `valueLabel`, not between `valueLabel` and `stepper`
  (arranged order becomes `[label, spacer, valueLabel, stepper]`). The
  `NSStackView`'s `spacing` is `SettingsLayout.default[.rowSpacing]` = 8pt,
  applied by default between every adjacent pair; `makeRow` then zeroes only
  the spacer→`valueLabel` gap (`setCustomSpacing(0, after: spacer)`), leaving
  the `valueLabel`→`stepper` gap at the unmodified default 8pt. The visible
  effect is `label` pinned to the row's leading edge, all of the row's
  leftover width absorbed in the flexible gap right after it, and
  `valueLabel`/`stepper` sitting together, 8pt apart, at the trailing edge.
  `pinToEdges(row, of: self)` adds 0pt of outer padding beyond that.
- **Font**: `label` (`ComposableSettings.makeRowLabel`, `textRole: .button`)
  resolves to `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight,
  proportional system font, scaled by the active theme's `sizeScale`.
  `valueLabel` (`ComposableSettings.makeValueLabel(monospacedDigits: true)`,
  `textRole: .code`) resolves to `ThemeTypography.defaultStyle(.code)`: 12pt,
  regular weight, the system monospaced font, also scaled by `sizeScale` —
  chosen so a value that changes on every click doesn't reflow the row. Both
  repaint automatically on a theme change via `ThemePaletteObserver`.
  `NSStepper` draws no text of its own.
- **Background**: `label`/`valueLabel` — none (transparent); `ThemedLabel.init`
  sets `drawsBackground = false`, `isBordered = false`, `isBezeled = false`.
  `stepper` — no background is set in source; it keeps `NSStepper`'s default
  AppKit up/down bezel appearance.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the active
  theme's foreground color at full strength. `valueLabel`
  (`role: .secondaryText`) resolves to a lower-emphasis theme color than
  `label`. Both are recomputed live on a theme change. `stepper`'s arrow tint
  is AppKit's own system rendering; the source sets no color on it.
- **Border**: Not applicable — `label`/`valueLabel` have `isBordered = false`
  (`ThemedLabel`); `stepper` keeps `NSStepper`'s default bezel, drawn by
  AppKit rather than configured in `StepperView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `StepperView.swift`.
- **Min/Max size**: Not applicable — no explicit width/height constraint is
  set on `label`, `valueLabel`, or `stepper` beyond `valueLabel`'s
  compression-resistance priority (not a size constraint); sizing follows
  each control's own intrinsic content size, the row's spacing math, and
  `pinToEdges`.

## Accessibility

- **Role/trait**: Not customized in source — no `setAccessibilityRole` call
  appears anywhere in `StepperView.swift`. `stepper` keeps `NSStepper`'s
  built-in AppKit accessibility role for a stepper control; `label` and
  `valueLabel` keep AppKit's default for a non-editable field (`ThemedLabel`
  sets `isEditable = false`) — static-text elements.
- **Label requirements**: Not implemented in source. `stepper` has no
  accessibility title/label linkage — no `setAccessibilityTitleUIElement`,
  `accessibilityLabel`, or `accessibilityTitle` call appears anywhere in
  `StepperView.swift`. Every sibling `ComposableSettings` row that pairs a
  label with an interactive control does link them —
  `CheckboxView.toggle.setAccessibilityTitleUIElement(label)` and
  `IntegerFieldView`'s wrapped `NumberFieldView.textField` do the same — so
  the omission here is a plain gap against the row's own family pattern, not
  a documented design choice. VoiceOver announces `stepper` as an unlabeled
  control, and `valueLabel`'s current number is a separate static text
  element rather than the stepper's own spoken value.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller (see
  States); a value change updates `stepper.integerValue` directly, which
  `NSStepper`'s own native accessibility value reporting picks up, with no
  explicit announcement call in source. `valueLabel`'s parallel text update is
  not itself linked to `stepper`'s accessibility value (see Label
  requirements, above).
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/keyboard-driven `NSView`/`NSControl` composition with no touch input
  path in source; the 44×44pt guidance is iOS/touch-specific. No
  `controlSize` is set on `stepper`, so it keeps `NSStepper`'s regular system
  metrics.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The label and value-label text color resolves from the active theme's primaryText/secondaryText role against the hosting background at runtime; the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file. This would be settled by a theme-level contrast audit of primaryText/secondaryText against the backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.RangeViewModel<Int>` | — (required) | Supplies the row's title, min/max bounds, and current integer value; receives committed stepper changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own `sync` handler (see Edge Cases). |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears in source; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: `StepperView.swift` sets no custom `NSColor` on `stepper`; the labels' colors come from the theme's `.primaryText`/`.secondaryText` roles, and `NSStepper`'s own bezel rendering follows the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — the current value is shown as digits in `valueLabel`. Reaching a bound stops further movement (see disables-stepper-wraparound) rather than wrapping, but nothing in source shows `NSStepper` rendering an arrow as disabled at `minValue`/`maxValue`; it only absorbs the click. `StepperView` introduces no color-only cue of its own either way. |

