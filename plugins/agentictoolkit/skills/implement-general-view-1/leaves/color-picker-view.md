<!-- leaf: implement-general-view-1/color-picker-view · source: color-picker-view.md -->

**Rules** (cite as `implement-general-view-1/color-picker-view#<slug>`):

- `arranges-row-layout` MUST
- `initializes-from-view-model` MUST
- `commits-color-value` MUST
- `delegates-color-clamping` MUST
- `syncs-on-external-change` MUST
- `owns-on-change` MUST
- `exposes-constituent-views` MUST
- `rejects-coder-initialization` MUST
- `rejects-frame-only-initialization` MUST

# ColorPickerView

## Overview

`ColorPickerView` is an AppKit `NSView` from the ComposableSettingsWindow
system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/ColorPickerView.swift`)
that pairs a title label with an `NSColorWell` as one settings row and
conforms to `SettingsViewProtocol`. Its title and color are driven by a
caller-supplied `ColorViewModel`: the view reflects the view model's
title/color on construction and whenever the view model reports an
external change, and it writes the user's color-well interactions back
into `viewModel.color`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label` and `colorWell`
  into a single horizontal row via `ComposableSettings.makeRow`, and MUST
  pin that row to all four edges of the view via
  `ComposableSettings.pinToEdges` with no additional constant.
- **initializes-from-view-model**: Component MUST, during initialization,
  build `label` from `viewModel.title` (via `createLabel(title:)`, which
  calls `ComposableSettings.makeRowLabel`) and set `colorWell.color` to
  `viewModel.color`.
- **commits-color-value**: Component MUST set `viewModel.color` to
  `sender.color` every time `colorChanged(_:)` — the color well's
  target-action — is invoked, unconditionally, with no comparison against
  the current value.
- **delegates-color-clamping**: Component MUST NOT perform its own
  clamping or validation of `sender.color` before writing it to
  `viewModel.color`; normalizing an out-of-gamut or malformed color is
  `RGBAColor`'s responsibility, one layer below this component.
- **syncs-on-external-change**: Component MUST re-set `label.stringValue`
  to `viewModel.title` and `colorWell.color` to `viewModel.color` whenever
  `viewModel.onChange` fires.
- **owns-on-change**: Component MUST assign its own closure to
  `viewModel.onChange` during initialization, unconditionally replacing
  any handler already registered on that `ColorViewModel` instance;
  callers MUST NOT share a single `ColorViewModel` across more than one
  observer (for example, two `ColorPickerView` instances, or a
  `ColorPickerView` and another registered `onChange` handler), because
  constructing the later observer silently drops whichever handler was
  registered first.
- **exposes-constituent-views**: Component MUST expose `label` and
  `colorWell` as public, directly-accessible, read-only (`let`)
  properties.
- **rejects-coder-initialization**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer
  or drawing code; it only composes a stock `NSTextField`/`ThemedLabel`
  and a stock `NSColorWell` into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between `label` and `colorWell` (`[label, spacer, colorWell]`) and sets
  the `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` =
  8pt, which applies to the label→spacer gap; `makeRow` explicitly zeroes
  the spacer→colorWell gap (`setCustomSpacing(0, after: spacer)`), so the
  spacer's own width is the only thing between the label and the color
  well. `pinToEdges` pins the row's top/leading/trailing/bottom directly
  to `ColorPickerView`'s edges with no additional constant, so the
  component contributes 0pt of its own outer padding beyond that internal
  8pt / 0pt spacing.
- **Font**: `label` (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight,
  proportional system font, scaling with the active theme's `sizeScale`
  and repainting on a theme change via `ThemePaletteObserver`. `colorWell`
  has no text of its own — not applicable.
- **Background**: None (transparent) for `label` —
  `ThemedLabel.init` sets `drawsBackground = false`, `isBordered = false`,
  and `isBezeled = false` — and neither `ColorPickerView` nor the row
  `NSStackView` sets `wantsLayer` or a background color of its own.
  `colorWell`'s swatch chrome is `NSColorWell`'s own default AppKit
  rendering, not customized in source (no `colorWellStyle` is set).
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change. `colorWell` is not a
  text control; the color it displays is the edited value itself, not a
  foreground/text color, so "Foreground/Text" is not applicable to it.
- **Border**: Not applicable — no border is drawn or configured anywhere
  in `ColorPickerView.swift`; `colorWell`'s border is `NSColorWell`'s
  stock chrome, not custom to this file.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere
  in `ColorPickerView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `ColorPickerView.swift`; sizing is governed
  entirely by `label` and `colorWell`'s own intrinsic sizes inside the
  `makeRow` stack view.

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults — no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call
  appears in source. `NSColorWell` and `NSTextField` each carry AppKit's
  built-in accessibility role (color well, static text) automatically.
- **Label requirements**: `label` and `colorWell` are laid out as sibling
  views in the same row, but source sets no
  `accessibilityLabel`/`accessibilityTitleUIElement` (or equivalent) on
  `colorWell` linking it to `label` — confirmed by comparison with sibling
  row views in the same directory: `CheckboxView`, `NumberFieldView`, and
  `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their control,
  but `ColorPickerView` does not do so for `colorWell`. `colorWell` relies
  entirely on `NSColorWell`'s own default AppKit accessibility role, with
  no explicit, programmatic link from the color well to the row's title
  text.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  the component has no loading state and never disables itself (see
  States); there is no state transition to announce.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ColorViewModel` | — (required) | Supplies the row's title and current color; receives committed color-well changes via `viewModel.color`. The initializer also overwrites this view model's `onChange` closure with the component's own sync handler (see **owns-on-change**). |

## Accessibility Options

- **Reduce Motion**: Not applicable — source contains no animation,
  transition, or `NSAnimationContext` call; every state change is an
  instantaneous property assignment.
- **Increase Contrast**: Not applicable — `ColorPickerView.swift` sets no
  custom `NSColor` anywhere; `label`'s coloring comes from the active
  theme's `primaryText` role and `colorWell`'s swatch chrome comes
  entirely from AppKit's default control rendering, both of which follow
  system Increase Contrast automatically.
- **Differentiate Without Color**: Not applicable — the color `colorWell`
  displays is the control's own edited value, not a color-coded status
  signal that needs a redundant non-color cue; no other state in this
  component is communicated through color alone.

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a color value supplied by `viewModel` and
  reports color-well changes back through `viewModel.color`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by
  `ColorViewModel`/`UserSettingObserver`, which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere
  in source.
- **Retention**: Not applicable — the view retains only its own subviews
  and its reference to `viewModel` for its own lifetime; it persists
  nothing beyond that.

