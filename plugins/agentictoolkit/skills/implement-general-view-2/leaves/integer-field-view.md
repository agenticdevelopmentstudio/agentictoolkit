<!-- leaf: implement-general-view-2/integer-field-view · source: integer-field-view.md -->

**Rules** (cite as `implement-general-view-2/integer-field-view#<slug>`):

- `wraps-number-field-view` MUST
- `exposes-constituent-views` MUST
- `arranges-single-child` MUST
- `forwards-editing-end-to-wrapped-field` MUST
- `default-field-width` MUST
- `forwards-label-width` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST
- `label-requirements` MUST — Component MUST call textField.setAccessibilityTitleUIElement(label) — the same row pattern CheckboxView and its …

# IntegerFieldView

## Overview

`IntegerFieldView` is a macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/IntegerFieldView.swift`):
a title label leading and a narrow, right-aligned integer text field trailing,
clamped to a `RangeViewModel<Int>`'s bounds. Per the source's own doc comment,
it exists because "a slider is the wrong control for a number the user
already knows" — "12 points on the left" is typed, not dragged — and a
`StepperView` "makes you click twelve times to say it." The type is kept as a
thin, forwarding wrapper around a private `NumberFieldView<Int>`
(`.../Views/NumberFieldView.swift`), which does the actual work: it builds
the label and field, wires theming and accessibility, and owns the
locale-aware parse/clamp/commit logic. `IntegerFieldView` stays as public API
"because it is public API of a framework other repos link: a bounded integer
field is still exactly this call" (source comment).

The wrapped `NumberFieldView<Int>`'s own behavior — theming, target/action and
delegate wiring, layout when `labelWidth` is set, locale-aware parsing,
clamping, revert-on-invalid, and external-change sync — is documented in full
at `agentictoolkit://recipes/number-field-view`, which this recipe depends on.
This recipe documents only what `IntegerFieldView` itself contributes:
constructing and forwarding to that wrapped view, exposing its constituent
views, and the initializer/actor requirements `IntegerFieldView` does not
inherit from it.

## Behavioral Requirements

The wrapped `NumberFieldView<Int>`'s own requirements — label/field
construction, theming, target/action and delegate wiring, `labelWidth`
layout, locale-aware parsing, clamping, revert-on-invalid, and
external-change sync — are documented at
`agentictoolkit://recipes/number-field-view#requirements`. The requirements
below are `IntegerFieldView`'s own: what it does to construct, forward to,
and expose that wrapped view.

- **wraps-number-field-view**: Component MUST construct a private
  `NumberFieldView<Int>`, passing the supplied `RangeViewModel<Int>` as its
  view model and `viewModel.minValue`/`viewModel.maxValue` as its
  `minimum`/`maximum` bounds.
- **exposes-constituent-views**: Component MUST expose `label` and
  `textField` as public properties, set to the wrapped `NumberFieldView`'s
  own `label` and `textField` instances.
- **arranges-single-child**: Component MUST add the wrapped
  `NumberFieldView` as its only subview and pin it to its own top, leading,
  trailing, and bottom edges, contributing no additional outer padding of
  its own.
- **forwards-editing-end-to-wrapped-field**: Component's
  `controlTextDidEndEditing(_:)` MUST call `commit()` on the wrapped
  `NumberFieldView`.
- **default-field-width**: Component's initializer MUST default
  `fieldWidth` to 52 points when the caller supplies none — narrower than
  the wrapped `NumberFieldView`'s own uncalled default of 72 points (see
  Design Decisions) — and MUST pass that value through to the wrapped
  `NumberFieldView`'s own `fieldWidth` parameter.
- **forwards-label-width**: Component's initializer MUST pass its own
  `labelWidth` parameter (default `nil`) through unchanged to the wrapped
  `NumberFieldView`.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.

## Appearance

- **Corner radius**: Not applicable — neither `IntegerFieldView` nor
  `NumberFieldView` sets a layer or draws a custom shape; both are plain
  `NSView` subclasses composing stock `NSTextField`s.
- **Padding**: `NumberFieldView`'s `makeRow([label, textField])` inserts a
  flexible spacer between them, sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt (applied to the
  label→spacer gap), and zeroes the spacer→`textField` gap
  (`setCustomSpacing(0, after: spacer)`) — the same row shape and spacing
  math `CheckboxView` and `CaptionedSliderView` use.
  `IntegerFieldView.pinToEdges(field, of: self)` adds 0pt of outer padding
  of its own; `NumberFieldView`'s own edge-pinning (`pinToEdges`, or the
  content-width variant when `labelWidth` is set) likewise adds nothing
  beyond that internal 8pt/0pt spacing.
- **Font**: `label` uses `ComposableSettings.makeRowLabel`'s `textRole:
  .button`, resolving to `ThemeTypography.defaultStyle(.button)`: 13pt,
  medium weight, proportional system font, scaled by the active theme's
  `sizeScale`. `textField` uses `palette.font(.code)`, resolving to
  `ThemeTypography.defaultStyle(.code)`: 12pt, regular weight, the system
  monospaced font, also scaled by `sizeScale` — chosen so a changing value
  doesn't reflow the field.
- **Background**: `label` — none (transparent); `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, `isBezeled = false`.
  `textField` — source never overrides `isBordered`, `isBezeled`, or
  `drawsBackground` on it; it stays a plain, default-initialized
  `NSTextField()`, which keeps AppKit's standard bezeled, opaque text-field
  background rather than being transparent like the label.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the
  active theme's foreground color at full strength, repainted live via
  `ThemePaletteObserver`. `textField.textColor` is set directly to
  `palette.primaryTextColor` (the same `.primaryText` role, applied through
  `observeTheme` rather than through a `ThemedLabel`), also repainted live
  on every theme change.
- **Border**: `label` — none (`ThemedLabel` sets `isBordered = false`).
  `textField` — no border property is set in source, so it keeps
  `NSTextField()`'s default bezel (`bezelStyle` defaults to
  `.squareBezel`), drawn by AppKit rather than by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `IntegerFieldView.swift` or `NumberFieldView.swift`.
- **Min/Max size**: `textField.widthAnchor` is fixed to the constant
  `fieldWidth` (52pt via `IntegerFieldView`'s own default; `NumberFieldView`'s
  own uncalled default is 72pt — see Design Decisions). No height
  constraint is set on either `label` or `textField`; height comes from
  each control's intrinsic content size within the row.

## Accessibility

- **Role/trait**: Not set explicitly anywhere in source. `textField` keeps
  `NSTextField`'s default editable-text-field accessibility role; `label`
  keeps AppKit's default for a non-editable field (`ThemedLabel` sets
  `isEditable = false`) — a static-text element.
- **Label requirements**: Component MUST call
  `textField.setAccessibilityTitleUIElement(label)` — the same row pattern
  `CheckboxView` and its siblings use — so the field's accessible name
  comes from its adjacent visible label rather than a separate
  `accessibilityLabel` string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller
  (see States); a committed clamp or revert updates `textField.stringValue`
  directly, which `NSTextField`'s own accessibility value reporting picks
  up automatically, with no explicit announcement call in source.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/keyboard-driven `NSView`/`NSControl` composition with no touch
  input path in source; the 44×44pt guidance is iOS/touch-specific. No
  `controlSize` is set on `textField`, so it keeps `NSTextField`'s regular
  system metrics; its clickable width is the fixed `fieldWidth` (52pt
  default here, per **default-field-width**), constrained onto the wrapped
  field's `textField.widthAnchor` by the wrapped `NumberFieldView`'s own
  `fixes-field-width` requirement (see
  `agentictoolkit://recipes/number-field-view#requirements/fixes-field-width`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.RangeViewModel<Int>` | — (required) | Supplies the row's title and min/max/current integer value; receives committed field changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the wrapped field's own sync handler (see Edge Cases). |
| `fieldWidth` | `CGFloat` | `52` | Width of the number field, in points. Differs from `NumberFieldView`'s own uncalled default of `72` — see Design Decisions. |
| `labelWidth` | `CGFloat?` | `nil` | When set, pins `label` to a fixed, right-aligned width so a column of rows lines up; when `nil`, the row spans the container's full width. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears in either file; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: neither file sets a custom `NSColor` outside the theme's `.primaryText` role; `NSTextField`'s own default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator in source. |

## Privacy

- **Data collected**: Not applicable — the component collects no data of
  its own; it only displays a value supplied by `viewModel` and reports
  committed edits back through `viewModel.settingObserver`.
- **Storage**: Not applicable — neither `IntegerFieldView.swift` nor
  `NumberFieldView.swift` reads or writes `UserDefaults`, the keychain, or
  any other store directly. Persistence is owned by
  `RangeViewModel<Int>`/`UserSettingObserver`/`UserSetting`, which are not
  part of these files; by default that chain routes through
  `UserDefaultsSettingsStorageProvider`, so a committed value survives an
  app restart, but that guarantee lives outside this component.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `textField`, the wrapped `field`) and its reference to
  `viewModel` for its own lifetime; it persists nothing itself beyond
  that.

