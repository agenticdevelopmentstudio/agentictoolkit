<!-- leaf: implement-general-view-1/checkbox-view · source: checkbox-view.md -->

**Rules** (cite as `implement-general-view-1/checkbox-view#<slug>`):

- `arranges-row-layout` MUST
- `links-toggle-accessibility-title` MUST
- `initializes-from-view-model` MUST
- `commits-toggle-value` MUST
- `skips-redundant-commits` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST
- `claims-sole-onchange-observer` MUST
- `inherits-native-keyboard-focus` MUST
- `label-requirements` MUST — Component MUST set toggle.setAccessibilityTitleUIElement(self.label) — per the source's own comment, AppKit gives a …

# CheckboxView

## Overview

`CheckboxView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/CheckboxView.swift`):
a title label leading and an `NSSwitch` trailing, in the same row shape System
Settings uses for a boolean setting. Despite the file and type name
`CheckboxView`, the control it draws is an `NSSwitch`, not a checkbox button —
the source's own doc comment explains the switch replaced a
checkbox-with-title button because a checkbox puts its control on the left,
the one row shape that cannot line up with the popups, steppers, and sliders
beside it in the same settings card. The row is driven by a
`ComposableSettings.ViewModel<Bool>`: the view reflects the view model's
title/value on construction and whenever the view model reports an external
change, and it writes the user's switch interactions back into the view
model's `settingObserver`.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange the title label and the
  toggle in a single horizontal row (`label`, then `toggle`), MUST place the
  toggle at the row's trailing edge with a flexible spacer absorbing the
  leftover width between `label` and `toggle`, and MUST pin that row to the
  edges of the view.
- **links-toggle-accessibility-title**: Component MUST set the toggle's
  accessibility title UI element to the label
  (`toggle.setAccessibilityTitleUIElement(label)`).
- **initializes-from-view-model**: Component MUST, at the end of
  initialization, set the label's text to `viewModel.title` and the toggle's
  state to `.on` when `viewModel.value` is `true` and `.off` when it is
  `false`.
- **commits-toggle-value**: Component MUST write the toggle's new boolean
  value (`sender.state == .on`) into `viewModel.settingObserver.value`
  whenever the toggle's action fires and the new value differs from the
  current `settingObserver.value`.
- **skips-redundant-commits**: Component MUST NOT write to
  `viewModel.settingObserver.value` when the toggle's new value equals the
  current `settingObserver.value`.
- **syncs-on-external-change**: Component MUST re-set the label's text to
  `viewModel.title` and the toggle's state to reflect `viewModel.value`
  whenever `viewModel.onChange` fires.
- **exposes-constituent-views**: Component MUST expose `label` and `toggle`
  as public, directly-accessible properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **claims-sole-onchange-observer**: Component MUST assign its own handler
  to `viewModel.onChange` during initialization
  (`viewModel.onChange = { [weak self] _ in self?.update() }`), superseding
  any handler already registered on that view model instance (see
  **overwritten external observer** in Edge Cases).
- **inherits-native-keyboard-focus**: Component MUST NOT override `toggle`'s
  or `label`'s default `NSControl` focus, tabbing, or key-handling behavior;
  no `acceptsFirstResponder`, `keyDown`, or focus-ring override appears in
  source, so keyboard operability follows `NSSwitch`'s native behavior
  unchanged.

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it only composes a stock `NSTextField` label and a stock
  `NSSwitch` into a row.
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer between
  `label` and `toggle` (`[label, spacer, toggle]`) and sets the
  `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt,
  which applies to the label→spacer gap; `makeRow` explicitly zeroes the
  spacer→toggle gap (`setCustomSpacing(0, after: spacer)`), so the spacer's
  own width is the only thing between the label and the toggle. `toggle`
  keeps `NSSwitch`'s own default content-hugging priority (higher than the
  spacer's `defaultLow`-minus-one), so the spacer, not the toggle, absorbs
  the row's leftover width. `pinToEdges` pins the row's top/leading/trailing/
  bottom directly to `CheckboxView`'s edges with no additional constant, so
  the component contributes 0pt of its own outer padding beyond that
  internal 8pt / 0pt spacing.
- **Font**: The label (`ComposableSettings.makeRowLabel`, `textRole:
  .button`) resolves to `ThemeTypography.defaultStyle(.button)`: 13pt,
  medium weight, proportional system font. The size scales with the active
  theme's `sizeScale` (`1.0` by default) and the label repaints
  automatically on a theme change via `ThemePaletteObserver`. `NSSwitch`
  draws no text of its own.
- **Background**: None (transparent) — `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false`
  on the label, and neither `CheckboxView` nor the row `NSStackView` sets
  `wantsLayer` or a background color of its own.
- **Foreground/Text**: The label (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change via `ThemePaletteObserver`.
  `NSSwitch`'s on/off track and thumb colors are AppKit's own system
  rendering; `CheckboxView` sets no color on `toggle`.
- **Border**: Not applicable — no border is drawn or configured anywhere in
  `CheckboxView.swift`.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `CheckboxView.swift`.
- **Min/Max size**: Not applicable — no explicit min/max width or height
  constraint is set in `CheckboxView.swift`; sizing is governed entirely by
  the label's and `NSSwitch`'s own intrinsic content sizes, the row's 8pt
  spacing, and `pinToEdges`.

## Accessibility

- **Role/trait**: Not customized beyond the title-element link below — no
  `setAccessibilityRole` call appears in source; `NSSwitch` carries AppKit's
  own built-in accessibility role for a switch/toggle control.
- **Label requirements**: Component MUST set
  `toggle.setAccessibilityTitleUIElement(self.label)` — per the source's own
  comment, AppKit gives a bare switch no name, so VoiceOver would otherwise
  announce it as an unlabelled control; the visible label supplies the
  accessible name instead of a separate `accessibilityLabel` string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable — the
  component has no loading state and never disables itself in source (see
  States); on/off is announced by `NSSwitch`'s own native accessibility
  value reporting when `state` changes, which `CheckboxView` does not
  override.
- **Minimum tap target**: Not applicable — this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44×44pt minimum is iOS/touch guidance, not a macOS
  pointer-interface requirement. `CheckboxView` sets no `controlSize` on
  `toggle`, so it keeps `NSSwitch`'s regular system click-target metrics.
- **Keyboard operability**: `CheckboxView` sets no `acceptsFirstResponder`,
  key-handling, or focus-ring override on `toggle` or `label` in source, so
  `toggle` keeps `NSSwitch`'s inherited `NSControl` tab order and its native
  Space/Return activation (see **inherits-native-keyboard-focus**).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<Bool>` | — (required) | Supplies the row's title and current boolean value; receives committed toggle changes via `settingObserver.value`. The initializer also overwrites this view model's `onChange` closure with the component's own `update` handler (see **claims-sole-onchange-observer**). `viewModel.explanation` (inherited from `AbstractViewModel`) is accepted by the initializer chain but never read or rendered anywhere in `CheckboxView.swift`. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: source contains no animation, transition, or `NSAnimationContext` call; every state change is an instantaneous property assignment (`label.stringValue`, `toggle.state`). |
| Increase Contrast | Not verified for the label: `CheckboxView.swift` sets no custom `NSColor` of its own on `toggle`, and the label's color comes from the theme's `.primaryText` role via `SemanticPalette.derive`, but nothing in this source, or in the theme code searched, shows that role responding to the system Increase Contrast setting. `NSSwitch`'s own track/thumb colors are unmodified system rendering, which does track Increase Contrast automatically. |
| Differentiate Without Color | Not applicable: the on/off state is communicated through `NSSwitch`'s own track position and system iconography, not through a color-only signal introduced by this component. |

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  toggle changes back through `viewModel.settingObserver`.
- **Storage**: Not applicable — source performs no read/write to disk,
  `UserDefaults`, or any other store; persistence, if any, is owned by the
  `ComposableSettings.ViewModel<Bool>`/`settingObserver`, which are not part
  of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `toggle`) and its reference to `viewModel` for its own
  lifetime; it persists nothing beyond that.

