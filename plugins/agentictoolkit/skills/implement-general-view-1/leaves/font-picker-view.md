<!-- leaf: implement-general-view-1/font-picker-view · source: font-picker-view.md -->

**Rules** (cite as `implement-general-view-1/font-picker-view#<slug>`):

- `arranges-row-layout` MUST
- `initializes-label-from-view-model-title` MUST
- `initializes-button-without-fixed-width` MUST
- `tags-button-with-a-fixed-accessibility-identifier` MUST
- `commits-picked-font-through-view-model` MUST
- `resyncs-synchronously-after-a-pick` MUST
- `observes-external-view-model-changes` MUST
- `overwrites-existing-view-model-observer` MUST
- `syncs-once-at-construction` MUST
- `redraws-label-text-on-every-sync` MUST
- `updates-button-sample-on-every-sync` MUST
- `describes-font-name-and-rounded-point-size` MUST
- `flags-an-uninstalled-font-in-its-title` MUST
- `delegates-font-resolution-fallback` MUST
- `dims-and-disables-the-row` MUST
- `defaults-to-enabled` MUST
- `exposes-constituent-views` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST

# FontPickerView

## Overview

`FontPickerView` (`ComposableSettings.FontPickerView`) is a macOS `NSView`
from the ComposableSettingsWindow system integration
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/FontPickerView.swift`)
that pairs a title label with a `FontChooserButton` as one settings row and
conforms to `SettingsViewProtocol`. Its title and font are driven by a
caller-supplied `FontViewModel`: the row builds its label from the view
model's title and shows the view model's current font (with an
"installed"/"not installed" qualifier) on the button, keeps both in sync
whenever the view model reports an external change, and writes the font the
user picks in the button's font panel back into `viewModel.setFont(_:)`. Per
the source's own doc comment, the row is "the binding and nothing else" -
the font-panel plumbing lives once, in `FontChooserButton`, so this row and
any other caller of that button cannot drift apart.

## Behavioral Requirements

- **arranges-row-layout**: Component MUST arrange `label` and `button` into
  a single horizontal row via `ComposableSettings.makeRow`, and MUST pin
  that row to all four edges of the view via `ComposableSettings.pinToEdges`
  with no additional constant.
- **initializes-label-from-view-model-title**: Component MUST, during
  initialization, build `label` from `viewModel.title` via
  `ComposableSettings.makeRowLabel`.
- **initializes-button-without-fixed-width**: Component MUST construct
  `button` via the plain `FontChooserButton()` initializer, never
  `FontChooserButton(width:)`, so no width constraint is added on the
  button's behalf.
- **tags-button-with-a-fixed-accessibility-identifier**: Component MUST set
  the button's accessibility identifier to the literal
  `"settings.font-picker.choose"` during initialization.
- **commits-picked-font-through-view-model**: WHEN `button.onChange` fires
  with the font the user picked, the component MUST call
  `viewModel.setFont(_:)` with that font.
- **resyncs-synchronously-after-a-pick**: WHEN `button.onChange` fires, the
  component MUST call its own `sync()` routine synchronously, immediately
  after calling `viewModel.setFont(_:)`, regardless of whether that call
  actually changed the view model's stored name or size.
- **observes-external-view-model-changes**: Component MUST assign
  `viewModel.onChange` to a closure that calls `sync()`; the closure MUST
  discard the font value it receives and let `sync()` re-read state from
  `viewModel` directly.
- **overwrites-existing-view-model-observer**: Component MUST assign that
  closure to `viewModel.onChange` unconditionally in `init`, replacing
  whatever handler (if any) was already registered on that `FontViewModel`
  instance.
- **syncs-once-at-construction**: Component MUST call `sync()` exactly once
  at the end of initialization, after `label`, `button`, the row, and the
  `button.onChange`/`viewModel.onChange` closures are all wired up.
- **redraws-label-text-on-every-sync**: WHEN `sync()` runs, the component
  MUST set `label.stringValue` to `viewModel.title`, unconditionally, even
  though `viewModel.title` cannot change after construction (`title` is a
  `let` on `AbstractViewModel`).
- **updates-button-sample-on-every-sync**: WHEN `sync()` runs, the component
  MUST call `button.show(_:title:)`, passing `viewModel.font` as the font
  and the result of the private `describe(_:installed:)` helper as the
  title.
- **describes-font-name-and-rounded-point-size**: WHEN `sync()` runs,
  `button`'s title MUST read `"<name> — <size> pt"`, where `<name>` is
  `font.displayName ?? font.fontName` and `<size>` is `font.pointSize`
  rounded to the nearest integer (see the `AppKit / UIKit` platform note for
  the private helper that computes this string).
- **flags-an-uninstalled-font-in-its-title**: WHEN `sync()` runs and
  `viewModel.isInstalled == false`, `button`'s title MUST end with the
  literal suffix `" (not installed)"`.
- **delegates-font-resolution-fallback**: Component MUST NOT perform its own
  validation, clamping, or fallback substitution on `viewModel.font`'s
  underlying stored name or size before passing it to `button.show(_:title:)`;
  resolving an uninstalled font name or an out-of-range stored size to a
  fallback font is `FontViewModel.font`'s responsibility, one layer below
  this component.
- **dims-and-disables-the-row**: WHEN `isEnabled` is set to `false`, the
  component MUST set `button.isEnabled` to `false` and `label.alphaValue` to
  `0.4`. WHEN `isEnabled` is set to `true`, the component MUST set
  `button.isEnabled` to `true` and `label.alphaValue` to `1.0`.
- **defaults-to-enabled**: Component MUST initialize `isEnabled` to `true`.
- **exposes-constituent-views**: Component MUST expose `label` and `button`
  as public, directly-accessible, read-only (`let`) properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.

## Appearance

- **Corner radius**: Not applicable - the component adds no custom layer or
  drawing code of its own; it only composes a `ThemedLabel` (via
  `makeRowLabel`) and a `FontChooserButton` into a row (see
  `agentictoolkit://recipes/font-chooser-button` for the button's own
  corner treatment).
- **Padding**: `ComposableSettings.makeRow` inserts a flexible spacer
  between `label` and `button` (`[label, spacer, button]`) and sets the
  `NSStackView`'s `spacing` to `SettingsLayout.default[.rowSpacing]` = 8pt,
  which applies to the label-to-spacer gap; `makeRow` explicitly zeroes the
  spacer-to-button gap (`setCustomSpacing(0, after: spacer)`), so the
  spacer's own width is the only thing between the label and the button.
  `pinToEdges` pins the row's top/leading/trailing/bottom directly to
  `FontPickerView`'s edges with no additional constant, so the component
  contributes 0pt of its own outer padding beyond that internal 8pt / 0pt
  spacing.
- **Font**: `label` (`makeRowLabel`, `textRole: .button`) resolves to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font, scaling with the active theme's `sizeScale` and repainting on
  a theme change via `ThemePaletteObserver`. `button`'s own font is dynamic
  and drawn at a fixed 12pt sample size regardless of the stored font's real
  size - see `draws-sample-at-fixed-size` in
  `agentictoolkit://recipes/font-chooser-button`.
- **Background**: None (transparent) for `label` - `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, and `isBezeled = false` -
  and neither `FontPickerView` nor the row `NSStackView` sets `wantsLayer`
  or a background color of its own. `button`'s bezel chrome is
  `FontChooserButton`'s own concern, not set here.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the active
  theme's foreground color at full strength
  (`SemanticPalette.derive(.primaryText)` returns `theme.foreground`
  unchanged), recomputed live on a theme change, then dimmed to 40% alpha
  when `isEnabled == false` (see **dims-and-disables-the-row**). `button`'s
  title color is not set in this file; it is `FontChooserButton`'s stock
  bezel text color.
- **Border**: Not applicable - no border is drawn or configured anywhere in
  `FontPickerView.swift`.
- **Shadow**: Not applicable - no shadow is drawn or configured anywhere in
  `FontPickerView.swift`.
- **Min/Max size**: Not applicable - no explicit min/max width or height
  constraint is set in `FontPickerView.swift`; sizing is governed entirely
  by `label` and `button`'s own intrinsic sizes inside the `makeRow` stack
  view (`button`'s own compression/hugging behavior when built without a
  fixed width is documented in `agentictoolkit://recipes/font-chooser-button`).

## Accessibility

- **Role/trait**: Not observable beyond AppKit's defaults - no
  `setAccessibilityRole`, `setAccessibilityElement`, or similar call appears
  in `FontPickerView.swift`. `button` carries `NSButton`'s native button
  role (see `agentictoolkit://recipes/font-chooser-button`); `label` is a
  plain static-text control.
- **Label requirements**: `label` and `button` are laid out as sibling views
  in the same row, but `FontPickerView.swift` sets no
  `accessibilityLabel`/`setAccessibilityTitleUIElement` (or equivalent)
  linking `button` to `label` - confirmed by comparison with sibling row
  views in the same directory: `CheckboxView`, `NumberFieldView`, and
  `PopupMenuChoiceView` each call
  `<control>.setAccessibilityTitleUIElement(self.label)` on their control,
  but `FontPickerView` does not do so for `button`. The `accessibilityID`
  call in source (`button.accessibilityID("settings.font-picker.choose")`)
  sets a UI-testing identifier, not an accessible name or label linkage. As
  a result, VoiceOver announces only the button's own title text (e.g.
  "Menlo-Regular — 14 pt") when focus lands on it, not the row's title
  (e.g. "Terminal Font").
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `label.alphaValue` is set to a hardcoded `0.4` when the row is disabled (**dims-and-disables-the-row**), local to `FontPickerView.swift` (no other file in `ComposableSettingsWindow/Views` uses this value or a shared "disabled alpha" constant); whether `label`'s text at 40% alpha against the active theme's surface color still meets a specific contrast ratio (e.g. WCAG 2.1 AA's 4.5:1) cannot be determined from this file alone since it depends on the resolved theme colors, which live outside this source - settled by auditing each shipped theme's resolved `primaryText`/surface pairing at 40% alpha.
- **Announce state changes (e.g., loading, disabled)**: `FontPickerView.swift`
  performs no explicit accessibility notification (no `NSAccessibility.post`
  call) when `isEnabled` changes; `button.isEnabled`'s own state is exposed
  automatically through `NSButton`'s native accessibility, but no proactive
  announcement is posted by this file. There is no loading state to
  announce (see States).
- **Minimum tap target**: Not applicable - this is a macOS, pointer/
  trackpad-driven `NSView`/`NSControl` composition (no touch input path in
  source); the 44x44pt minimum is an iOS/touch guidance, not a macOS
  pointer-interface requirement.

