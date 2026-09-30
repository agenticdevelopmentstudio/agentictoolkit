<!-- leaf: implement-general-view-2/number-field-view--part-2 · source: number-field-view.md -->

# NumberFieldView — continued (part 2)

**Rules** (cite as `implement-general-view-2/number-field-view--part-2#<slug>`):

- `label-requirements` MUST — Component MUST call textField.setAccessibilityTitleUIElement(label) — the same row pattern CheckboxView and its …

## Appearance

- **Corner radius**: Not applicable — the component adds no custom layer or
  drawing code; it composes stock `NSTextField` instances into a row.
- **Padding**: `ComposableSettings.makeRow([label, textField])` inserts a
  flexible spacer between them, sets the `NSStackView`'s `spacing` to
  `SettingsLayout.default[.rowSpacing]` = 8pt (applied to the label→spacer
  gap), and zeroes the spacer→`textField` gap
  (`setCustomSpacing(0, after: spacer)`) — the same row shape and spacing
  math `CheckboxView` and `CaptionedSliderView` use. `pinToEdges` (or the
  content-width variant used when `labelWidth` is set) adds 0pt of outer
  padding of its own beyond that internal 8pt/0pt spacing.
- **Font**: `label` uses `makeRowLabel`'s `textRole: .button`, resolving to
  `ThemeTypography.defaultStyle(.button)`: 13pt, medium weight, proportional
  system font, scaled by the active theme's `sizeScale`. `textField` uses
  `palette.font(.code)`, resolving to `ThemeTypography.defaultStyle(.code)`:
  12pt, regular weight, the system monospaced font, also scaled by
  `sizeScale` — chosen so a changing value doesn't reflow the field.
- **Background**: `label` — none (transparent); `ThemedLabel.init` sets
  `drawsBackground = false`, `isBordered = false`, `isBezeled = false`.
  `textField` — source never overrides `isBordered`, `isBezeled`, or
  `drawsBackground` on it; it stays a plain, default-initialized
  `NSTextField()`, which keeps AppKit's standard bezeled, opaque text-field
  background rather than being transparent like the label.
- **Foreground/Text**: `label` (`role: .primaryText`) resolves to the active
  theme's foreground color at full strength (`SemanticPalette.derive
  (.primaryText)` returns `theme.foreground` unchanged), repainted live via
  `ThemePaletteObserver`. `textField.textColor` is set directly to
  `palette.primaryTextColor` — the same `.primaryText` role, applied through
  `observeTheme` rather than through a `ThemedLabel` — also repainted live
  on every theme change.
- **Border**: `label` — none (`ThemedLabel` sets `isBordered = false`).
  `textField` — no border property is set in source, so it keeps
  `NSTextField()`'s default bezel (`bezelStyle` defaults to `.squareBezel`),
  drawn by AppKit rather than by this component.
- **Shadow**: Not applicable — no shadow is drawn or configured anywhere in
  `NumberFieldView.swift`.
- **Min/Max size**: `textField.widthAnchor` is fixed to the constant
  `fieldWidth` (default `72`pt). `label.widthAnchor` is fixed only when
  `labelWidth` is supplied. No height constraint is set on either view;
  height comes from each control's intrinsic content size within the row.

## Accessibility

- **Role/trait**: Not set explicitly anywhere in source. `textField` keeps
  `NSTextField`'s default editable-text-field accessibility role; `label`
  keeps AppKit's default for a non-editable field (`ThemedLabel` sets
  `isEditable = false`) — a static-text element.
- **Label requirements**: Component MUST call
  `textField.setAccessibilityTitleUIElement(label)` — the same row pattern
  `CheckboxView` and its siblings use — so the field's accessible name comes
  from its adjacent visible label rather than a separate
  `accessibilityLabel` string.
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  there is no loading state, and disabling is left entirely to a caller (see
  States); a committed clamp or revert updates `textField.stringValue`
  directly, which `NSTextField`'s own accessibility value reporting picks up
  automatically, with no explicit announcement call in source.
- **Minimum tap target**: Not applicable — this is a macOS,
  pointer/keyboard-driven `NSView`/`NSControl` composition with no touch
  input path in source; the 44×44pt guidance is iOS/touch-specific. No
  `controlSize` is set on `textField`, so it keeps `NSTextField`'s regular
  system metrics; its clickable width is the fixed `fieldWidth` (72pt
  default) set by **fixes-field-width**.
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. `label` and `textField` text colors resolve from the active theme's `.primaryText` role against the hosting background at runtime, and the component performs no contrast check, so whether a given theme's resolved pair meets 4.5:1 cannot be determined from this file; settling it needs a theme-level contrast audit of `.primaryText` against the settings-row backgrounds it sits on.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<Value>` | — (required) | Supplies the row's title and current value; receives committed field changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `minimum` | `Value?` | `nil` | The lowest value the field will store. `nil` clamps nothing at the bottom. |
| `maximum` | `Value?` | `nil` | The highest value the field will store. `nil` clamps nothing at the top. |
| `fieldWidth` | `CGFloat` | `72` | Width of the number field, in points. |
| `labelWidth` | `CGFloat?` | `nil` | When set, pins `label` to a fixed, right-aligned width so a column of rows lines up; when `nil`, the row spans the container's full width. |

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in the file; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: the file sets no custom `NSColor` outside the theme's `.primaryText` role; `NSTextField`'s own default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator in source. |

## Privacy

- **Data collected**: Not applicable — the component collects no data of its
  own; it only displays a value supplied by `viewModel` and reports
  committed edits back through `viewModel.settingObserver`.
- **Storage**: Not applicable — `NumberFieldView.swift` never reads or
  writes `UserDefaults`, the keychain, or any other store directly.
  Persistence is owned by `ViewModel`/`UserSettingObserver`/`UserSetting`,
  which are not part of this file.
- **Transmission**: Not applicable — no networking call appears anywhere in
  source.
- **Retention**: Not applicable — the view retains only its own subviews
  (`label`, `textField`) and its reference to `viewModel` for its own
  lifetime; it persists nothing itself beyond that.

