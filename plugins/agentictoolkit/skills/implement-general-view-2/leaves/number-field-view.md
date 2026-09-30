<!-- leaf: implement-general-view-2/number-field-view · source: number-field-view.md -->

**Rules** (cite as `implement-general-view-2/number-field-view#<slug>`):

- `builds-label-from-view-model-title` MUST
- `right-aligns-field-text` MUST
- `omits-input-formatter` MUST
- `wires-field-target-action` MUST
- `delegates-field-to-self` MUST
- `links-field-accessibility-title` MUST
- `themes-field-live` MUST
- `fixes-field-width` MUST
- `aligns-label-when-width-fixed` MUST
- `lays-out-content-width-row-when-label-fixed` MUST
- `lays-out-full-width-row-by-default` MUST
- `initializes-display-from-view-model` MUST
- `syncs-on-external-change` MUST
- `exposes-constituent-properties` MUST
- `requires-designated-initializer` MUST
- `rejects-frame-only-initialization` MUST
- `confines-to-main-actor` MUST
- `commits-on-field-action` MUST
- `commits-on-editing-end` MUST
- `parses-committed-text-via-value-type` MUST
- `reverts-on-unparseable-text` MUST
- `clamps-to-bounds` MUST
- `skips-clamp-on-contradictory-bounds` MUST
- `redisplays-committed-text` MUST
- `skips-redundant-commits` MUST
- `defines-number-parsing-contract` MUST
- `provides-current-locale-parse` MUST
- `requires-whole-string-locale-parse` MUST
- `trims-whitespace-before-parsing-int` MUST
- `parses-posix-integer-first` MUST
- `falls-back-to-locale-decimal-for-int` MUST
- `disallows-fractional-values-for-int` MUST
- `rejects-inexact-magnitude-for-int` MUST
- `writes-plain-integer-text` MUST
- `trims-whitespace-before-parsing-double` MUST
- `parses-posix-double-first` MUST
- `falls-back-to-locale-decimal-for-double` MUST
- `allows-fractional-values-for-double` MUST
- `writes-whole-doubles-without-fraction` MUST

# NumberFieldView

## Overview

`NumberFieldView<Value>` is the generic macOS `ComposableSettings` row
(`packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/NumberFieldView.swift`)
underlying every numeric text field in the framework: a title label leading
and a narrow, right-aligned text field trailing, parsed and clamped through a
`SettingsNumberValue` conformance rather than being tied to one numeric type.
Per the source's own doc comment, optional (rather than required) bounds are
"the whole reason this exists: every other numeric row here is built on
`RangeViewModel`, which requires both, and three quarters of the numeric
settings a VS Code extension declares name neither. A number with no ceiling
is still a number, not a text box." The same file also declares
`SettingsNumberValue` — the protocol a number type conforms to so a field can
show it, read it back, and compare it — plus the framework's two
conformances, `Int` and `Double`, each supplying its own locale-aware parse
and canonical text form. `IntegerFieldView`
(`agentictoolkit://recipes/integer-field-view`) is a thin, forwarding wrapper
around `NumberFieldView<Int>`; this recipe documents the field itself,
including the parsing contract that wrapper delegates to.

## Behavioral Requirements

- **builds-label-from-view-model-title**: Component MUST build `label` via
  `ComposableSettings.makeRowLabel(viewModel.title)`.
- **right-aligns-field-text**: Component MUST set `textField.alignment =
  .right`.
- **omits-input-formatter**: Component MUST NOT attach an `NSFormatter` to
  `textField`.
- **wires-field-target-action**: Component MUST set `textField.target` to
  itself and `textField.action` to its `fieldChanged(_:)` selector.
- **delegates-field-to-self**: Component MUST set `textField.delegate` to
  itself.
- **links-field-accessibility-title**: Component MUST call
  `textField.setAccessibilityTitleUIElement(self.label)`.
- **themes-field-live**: Component MUST set `textField.font` to
  `palette.font(.code)` and `textField.textColor` to
  `palette.primaryTextColor`, both immediately on construction and again
  every time the active theme changes (via `observeTheme`).
- **fixes-field-width**: Component MUST constrain `textField.widthAnchor` to
  the constant `fieldWidth` supplied at construction (default `72`).
- **aligns-label-when-width-fixed**: WHEN `labelWidth` is non-nil, Component
  MUST right-align `label` and pin its width to that constant.
- **lays-out-content-width-row-when-label-fixed**: WHEN `labelWidth` is
  non-nil, Component MUST pin the row's top, leading, and bottom edges to the
  container and constrain the row's trailing edge `lessThanOrEqualTo` the
  container's trailing edge.
- **lays-out-full-width-row-by-default**: WHEN `labelWidth` is `nil`,
  Component MUST pin the row to all four edges of the container instead of
  the content-width layout.
- **initializes-display-from-view-model**: At the end of initialization,
  Component MUST set `label.stringValue` to `viewModel.title` and
  `textField.stringValue` to `viewModel.value.settingsFieldString`.
- **syncs-on-external-change**: Component's initializer MUST assign
  `viewModel.onChange` to a closure that re-sets `label.stringValue` and
  `textField.stringValue` from the view model, and that closure MUST fire
  whenever `viewModel.onChange` is invoked.
- **exposes-constituent-properties**: Component MUST expose `label`,
  `textField`, `minimum`, and `maximum` as public, directly-accessible
  properties.
- **requires-designated-initializer**: Component MUST NOT support
  construction via `init(coder:)`; that initializer MUST trigger a fatal
  error.
- **rejects-frame-only-initialization**: Component MUST NOT support
  construction via the frame-only `init(frame:)`; that initializer MUST
  trigger a fatal error.
- **confines-to-main-actor**: Component MUST be usable only on the main
  actor; the class is declared `@MainActor`.
- **commits-on-field-action**: Component MUST call `commit()` whenever
  `textField`'s target-action fires (`fieldChanged(_:)`).
- **commits-on-editing-end**: Component MUST call `commit()` whenever its
  `controlTextDidEndEditing(_:)` delegate callback fires.
- **parses-committed-text-via-value-type**: `commit()` MUST parse
  `textField.stringValue` by calling `Value(settingsFieldString:)` — the
  current-locale initializer the `SettingsNumberValue` conformance supplies.
- **reverts-on-unparseable-text**: WHEN `commit()` cannot parse
  `textField.stringValue`, it MUST leave `viewModel.settingObserver.value`
  unchanged and MUST reset both `label.stringValue` and
  `textField.stringValue` from the view model's current title/value (via
  `sync()`).
- **clamps-to-bounds**: Unless **skips-clamp-on-contradictory-bounds**
  applies, `commit()` MUST clamp a successfully parsed value up to `minimum`
  (if the value is lower) and then down to `maximum` (if the value is higher)
  before storing it.
- **skips-clamp-on-contradictory-bounds**: WHEN both `minimum` and `maximum`
  are set and `minimum` is greater than `maximum`, `commit()` MUST store the
  parsed value unclamped.
- **redisplays-committed-text**: After computing the value to store,
  `commit()` MUST set `textField.stringValue` to that value's
  `settingsFieldString` whenever it differs from the field's current text.
- **skips-redundant-commits**: `commit()` MUST NOT write to
  `viewModel.settingObserver.value` when the computed value equals its
  current value.
- **defines-number-parsing-contract**: `SettingsNumberValue` MUST declare a
  failable, locale-parameterized initializer (`init?(settingsFieldString:
  locale:)`), a `settingsFieldString` string representation, and a static
  `settingsAllowsFloats` flag, and MUST itself be `Codable`, `Sendable`, and
  `Comparable`.
- **provides-current-locale-parse**: The `SettingsNumberValue` extension
  MUST provide `init?(settingsFieldString:)`, parsing with `Locale.current`.
- **requires-whole-string-locale-parse**: The shared locale-aware parse
  (`settingsLocaleNumber(from:locale:)`) MUST configure a `.decimal`-style
  `NumberFormatter` with `allowsFloats = settingsAllowsFloats`, and MUST
  reject the input unless the formatter's consumed range covers the entire
  string.
- **trims-whitespace-before-parsing-int**: `Int.init(settingsFieldString:
  locale:)` MUST trim leading and trailing whitespace from the input before
  parsing.
- **parses-posix-integer-first**: `Int.init(settingsFieldString:locale:)`
  MUST accept a POSIX-parseable integer (`Int(trimmed)`) before attempting a
  locale-aware parse.
- **falls-back-to-locale-decimal-for-int**: WHEN the POSIX parse fails for an
  `Int`, the initializer MUST attempt the locale-aware, whole-string decimal
  parse via `settingsLocaleNumber`.
- **disallows-fractional-values-for-int**: `Int.settingsAllowsFloats` MUST be
  `false`, so both the POSIX and locale-aware parse paths MUST reject any
  fractional spelling, including an integral-valued fractional spelling
  (e.g. `"1.0"`, `"1,0"`).
- **rejects-inexact-magnitude-for-int**: The locale-aware `Int` parse MUST
  reject a parsed number whose magnitude is not exactly representable as
  `Int` — per `Int.settingsExactInt(from:)`'s finite, whole-number, and
  `Decimal`-equality checks — rather than accepting a value `Int64.init`
  would silently saturate.
- **writes-plain-integer-text**: `Int.settingsFieldString` MUST return
  `String(self)`, with no locale-specific grouping or decoration.
- **trims-whitespace-before-parsing-double**: `Double.init(
  settingsFieldString:locale:)` MUST trim leading and trailing whitespace
  from the input before parsing.
- **parses-posix-double-first**: `Double.init(settingsFieldString:locale:)`
  MUST accept a POSIX-parseable double (`Double(trimmed)`) before attempting
  a locale-aware parse, but MUST reject a POSIX-parsed result that is not
  finite.
- **falls-back-to-locale-decimal-for-double**: WHEN the POSIX parse fails or
  is rejected for a `Double`, the initializer MUST attempt the locale-aware,
  whole-string decimal parse, and MUST reject a locale-aware result that is
  not finite.
- **allows-fractional-values-for-double**: `Double.settingsAllowsFloats`
  MUST be `true`.
- **writes-whole-doubles-without-fraction**: `Double.settingsFieldString`
  MUST render a value equal to its own rounded value as an integer-looking
  string with no trailing fractional digits (via `Int(exactly:)`), and MUST
  fall back to `String(self)` for any other value.

