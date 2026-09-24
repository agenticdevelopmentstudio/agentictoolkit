---
id: acd561ca-90a4-4303-a411-cfe23410b42a
title: NumberFieldView
domain: agentictoolkit://recipes/number-field-view
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-23'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A macOS ComposableSettings row generic over SettingsNumberValue — a title
  label paired with an optionally bounded, locale-aware number field.
platforms:
- swift
- macos
tags:
- settings
- form-control
- range
- numeric
- appkit
depends-on: []
related:
- agentictoolkit://recipes/integer-field-view
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `textField` shows the current value's `settingsFieldString`, right-aligned, in the code-role monospaced font. |
| Editing | The user's typed text is shown verbatim in `textField.stringValue` while focused; no `NSFormatter` is attached (deliberate — see Design Decisions), so intermediate/partial text (e.g. a leading `-`) is not rejected mid-edit. |
| Committed — valid | On Return/Tab/click-away (`controlTextDidEndEditing`) or on the field's own action firing, a parseable value is clamped (unless bounds are contradictory) and written back to `textField.stringValue` and `viewModel.settingObserver.value`. |
| Committed — invalid | An unparseable string reverts `textField.stringValue` and `label.stringValue` to the view model's current value/title; `viewModel.settingObserver.value` is left unchanged. |
| Pressed | Not applicable: the component renders no button; there is no press/highlight state to define. |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public `textField` property, at which point `NSTextField`'s native disabled dimming applies. |
| Focused | Not styled by this component; any focus ring shown when the field becomes first responder is `NSTextField`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |

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
- **Minimum contrast ratio**: NEEDS REVIEW: Not implemented in source. The
  `label` and `textField` text colors resolve from the active theme's
  `.primaryText` role against the hosting background at runtime; the
  component performs no contrast check, so whether a given theme's resolved
  pair meets 4.5:1 cannot be determined from this file. This would be
  settled by a theme-level contrast audit of `.primaryText` against the
  settings-row backgrounds it sits on.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| number-field-view-001 | builds-label-from-view-model-title | `viewModel.title = "Left Margin"` | `label.stringValue == "Left Margin"` after construction |
| number-field-view-002 | right-aligns-field-text | Construct `NumberFieldView<Int>` with any view model | `textField.alignment == .right` |
| number-field-view-003 | omits-input-formatter | Construct the component | `textField.formatter == nil` |
| number-field-view-004 | wires-field-target-action | Any initialized field | `textField.target === field`; `textField.action == Selector("fieldChanged:")` |
| number-field-view-005 | delegates-field-to-self | Any initialized field | `textField.delegate === field` |
| number-field-view-006 | links-field-accessibility-title | Construct the component | `textField`'s accessibility title UI element is `label` |
| number-field-view-007 | themes-field-live | Construct the field, then call `ThemeManager.shared.selectTheme(id:)` (or post `ThemeManager.didChangeNotification` directly) to switch to a theme whose palette has a distinct `.code` font/`.primaryText` color | `textField.font` and `textField.textColor` update to match the new palette both immediately at construction and again after the change |
| number-field-view-008 | fixes-field-width | Construct with `fieldWidth: 90` | `textField.widthAnchor`'s constant is 90 |
| number-field-view-009 | aligns-label-when-width-fixed | Construct with `labelWidth: 100` | `label.alignment == .right` and `label.widthAnchor`'s constant is 100 |
| number-field-view-010 | lays-out-content-width-row-when-label-fixed | Construct with `labelWidth: 100` | The row's top/leading/bottom are pinned to the container; its trailing constraint is `lessThanOrEqualTo` the container's trailing edge |
| number-field-view-011 | lays-out-full-width-row-by-default | Construct with `labelWidth: nil` | The row is pinned to all four edges of the container |
| number-field-view-012 | initializes-display-from-view-model | `viewModel.title = "Left Margin"`, `viewModel.value = 12` | After init, `label.stringValue == "Left Margin"` and `textField.stringValue == "12"` |
| number-field-view-013 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `textField.stringValue` both update to reflect the new view-model state |
| number-field-view-014 | exposes-constituent-properties | Construct the component with `minimum: 0, maximum: 10` | `.label`, `.textField`, `.minimum == 0`, and `.maximum == 10` are all accessible from outside the type |
| number-field-view-015 | requires-designated-initializer | Attempt `NumberFieldView<Int>(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| number-field-view-016 | rejects-frame-only-initialization | Attempt `NumberFieldView<Int>(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| number-field-view-017 | confines-to-main-actor | Attempt to construct or mutate a `NumberFieldView` from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
| number-field-view-018 | commits-on-field-action | Type `"7"` into `textField` and invoke `fieldChanged(textField)` directly | `viewModel.settingObserver.value == 7` after the call |
| number-field-view-019 | commits-on-editing-end | Type `"7"` into `textField` and invoke `controlTextDidEndEditing` | `viewModel.settingObserver.value == 7` after the call |
| number-field-view-020 | parses-committed-text-via-value-type | `textField.stringValue = "42"`, then commit | `viewModel.settingObserver.value == 42` |
| number-field-view-021 | reverts-on-unparseable-text | `viewModel.settingObserver.value = 5`; set `textField.stringValue = "abc"` and commit | `viewModel.settingObserver.value` remains `5`; `textField.stringValue` is reset to `"5"` |
| number-field-view-022 | clamps-to-bounds | `minimum = 0`, `maximum = 10`; set `textField.stringValue = "99"` and commit | `viewModel.settingObserver.value == 10`; `textField.stringValue == "10"` |
| number-field-view-023 | skips-clamp-on-contradictory-bounds | `minimum = 10`, `maximum = 1`; set `textField.stringValue = "37"` and commit | `viewModel.settingObserver.value == 37` (stored unclamped) |
| number-field-view-024 | redisplays-committed-text | `minimum = 0`, `maximum = 10`; set `textField.stringValue = "99"` and commit | `textField.stringValue` changes from `"99"` to `"10"` |
| number-field-view-025 | skips-redundant-commits | `viewModel.settingObserver.value = 5`; set `textField.stringValue = "5"` (same value) and commit | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| number-field-view-026 | defines-number-parsing-contract | Declare a type conforming to `SettingsNumberValue` that omits `settingsAllowsFloats` or the failable locale initializer | The declaration fails to compile |
| number-field-view-027 | provides-current-locale-parse | With the process locale set to `de_DE`, call `Int(settingsFieldString: "1.234")` with no locale argument | Returns `1234` — a result only produced under a German (thousands-grouped) locale reading, showing the omitted-locale form used the current locale rather than, say, `en_US` (under which the same call returns `nil`) |
| number-field-view-028 | requires-whole-string-locale-parse | With locale `en_US` and `Int.settingsAllowsFloats == false`, call `Int(settingsFieldString: "12abc")` | Returns `nil` (the formatter consumes only `"12"`, leaving the range short of the whole string) |
| number-field-view-029 | trims-whitespace-before-parsing-int | Call `Int(settingsFieldString: " 12 ")` | Returns `12` |
| number-field-view-030 | parses-posix-integer-first | Call `Int(settingsFieldString: "12", locale: Locale(identifier: "de_DE"))` | Returns `12` |
| number-field-view-031 | falls-back-to-locale-decimal-for-int | With locale `de_DE`, call `Int(settingsFieldString: "1.234")` | The POSIX parse of `"1.234"` fails (not representable as a plain `Int` literal with a `.`), the locale-aware branch reads it as German thousands-grouped `1234`, and the call returns `1234` |
| number-field-view-032 | disallows-fractional-values-for-int | Call `Int(settingsFieldString: "1.0")` and `Int(settingsFieldString: "1,5")` with locale `de_DE` | Both return `nil` |
| number-field-view-033 | rejects-inexact-magnitude-for-int | Call `Int(settingsFieldString: "99999999999999999999999999")` | Returns `nil` rather than a saturated `Int.max` |
| number-field-view-034 | writes-plain-integer-text | `Int(1234).settingsFieldString` | Returns `"1234"`, with no grouping separators |
| number-field-view-035 | trims-whitespace-before-parsing-double | Call `Double(settingsFieldString: " 1.5 ")` | Returns `1.5` |
| number-field-view-036 | parses-posix-double-first | Call `Double(settingsFieldString: "nan")` | The POSIX parse succeeds syntactically but the result is not finite, so the call returns `nil` rather than a NaN `Double` |
| number-field-view-037 | falls-back-to-locale-decimal-for-double | With locale `de_DE`, call `Double(settingsFieldString: "1,5")` | The POSIX parse of `"1,5"` fails, the locale-aware branch reads it as `1.5`, and the call returns `1.5` |
| number-field-view-038 | allows-fractional-values-for-double | Call `Double(settingsFieldString: "1.5")` | Returns `1.5` |
| number-field-view-039 | writes-whole-doubles-without-fraction | `Double(20.0).settingsFieldString` and `Double(20.5).settingsFieldString` | Return `"20"` and `"20.5"` respectively |

## Edge Cases

- **Null/empty input**: `viewModel` (`ViewModel<Value>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`. An empty
  `textField.stringValue` fails `Value(settingsFieldString:)` for both `Int`
  and `Double` (a trimmed empty string fails both the POSIX and the
  locale-aware parse), so `commit()` takes the revert path
  (**reverts-on-unparseable-text**) rather than storing `0`.
- **Boundary values**: A typed value exactly equal to `minimum` or `maximum`
  commits unclamped (the clamp is a no-op at the boundary). A value one
  below `minimum` clamps up to `minimum`; one above `maximum` clamps down to
  `maximum`. When `minimum` and `maximum` are both set and `minimum >
  maximum`, clamping is skipped entirely and the raw typed value is stored
  (**skips-clamp-on-contradictory-bounds**) — a caller configuration error,
  not a range this component enforces.
- **Out-of-range magnitude (Int)**: A typed value whose magnitude exceeds
  what `Int` can hold exactly — per `Int.settingsExactInt(from:)`'s
  `Decimal`-based check, which catches the case `NSNumber.int64Value` would
  otherwise silently saturate — is treated as unparseable and reverts rather
  than storing a clamped `Int.max`/`Int.min`.
- **Non-finite values (Double)**: `"nan"`, `"inf"`, and `"-inf"` all parse
  syntactically under `Double(_:)`, but `Double.init(settingsFieldString:
  locale:)` explicitly rejects a non-finite POSIX result and a non-finite
  locale-aware result, returning `nil` rather than storing a NaN or
  infinite value that would make every bounds comparison in `commit()`
  false.
- **Fractional and locale-formatted text (Int)**: A fractional string
  (`"1.5"`, or `"1,5"` in a comma-decimal locale) is rejected outright —
  `Int.settingsAllowsFloats` is `false`, so the locale `NumberFormatter`
  refuses it, and the whole-string-consumed check refuses a partial parse
  like the leading `"1"` of `"1,5"`. An integral-valued fractional spelling
  (`"1.0"`) is refused for the same reason.
- **Whole-number round-trip stability (Double)**: A stored `20.0` renders as
  `"20"` (**writes-whole-doubles-without-fraction**) rather than `"20.0"`,
  so a field showing a value the caller never edited does not visibly
  rewrite it into a longer, decorated form.
- **Concurrent access**: Not applicable — `SettingsNumberValue`'s extension
  methods and the `Int`/`Double` conformances are `nonisolated`, synchronous,
  pure value-type code (the protocol itself requires only `Sendable`); only
  `NumberFieldView` is `@MainActor` (see **confines-to-main-actor**), so all
  construction and mutation of the view is serialized to the main actor even
  though the parsing/formatting code they call is not itself isolated.
- **Error states**: Not applicable — every operation in this file (parsing,
  clamping, the `settingObserver.value` write) is synchronous and
  non-throwing; the one `try` in the file (`formatter.getObjectValue`) is
  caught locally and converted to a `nil` return, never propagated. No
  error reaches the caller.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking; it only reads from and writes to an in-process view model.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property. The initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that view model —
  the same closure-overwrite behavior `CheckboxView` and
  `CaptionedSliderView` document. The component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `viewModel` | `ComposableSettings.ViewModel<Value>` | — (required) | Supplies the row's title and current value; receives committed field changes via `settingObserver.value`. The initializer overwrites this view model's `onChange` closure with the component's own sync handler (see Edge Cases). |
| `minimum` | `Value?` | `nil` | The lowest value the field will store. `nil` clamps nothing at the bottom. |
| `maximum` | `Value?` | `nil` | The highest value the field will store. `nil` clamps nothing at the top. |
| `fieldWidth` | `CGFloat` | `72` | Width of the number field, in points. |
| `labelWidth` | `CGFloat?` | `nil` | When set, pins `label` to a fixed, right-aligned width so a column of rows lines up; when `nil`, the row spans the container's full width. |

## Deep Linking

Not applicable: `NumberFieldView` is a row inside a composable settings
window, not a navigable screen; no URL scheme, route, or deep-link handler
appears anywhere in `NumberFieldView.swift`.

## Localization

Not applicable: the file contains no user-facing string literals of its own.
The row's title comes entirely from `viewModel.title`, a value the caller
provides, so there is nothing for this component to localize itself.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `NSAnimationContext` call appears anywhere in the file; every state change (init, sync, commit) is an instantaneous property assignment. |
| Increase Contrast | Not applicable: the file sets no custom `NSColor` outside the theme's `.primaryText` role; `NSTextField`'s own default border/bezel rendering already tracks the system's Increase Contrast setting automatically. |
| Differentiate Without Color | Not applicable: the component conveys no state through color alone — valid, invalid, and clamped values are communicated entirely through the displayed digits; an invalid entry reverts silently with no color-only error indicator in source. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in `NumberFieldView.swift`; the row always renders once constructed.

## Analytics

Not applicable: `NumberFieldView.swift` contains no analytics or telemetry
call.

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

## Logging

Not applicable: `NumberFieldView.swift` contains no logging call (no
`print`, `os_log`, or logger reference anywhere in source).

## Platform Notes

- **SwiftUI**: `TextField("", value: $numericValue, format: .number)` (or a
  `String`-backed `TextField` with a manual parse/format pair, to reproduce
  the POSIX-write/locale-read asymmetry) inside an `HStack` with a leading
  `Text(viewModel.title)`, giving the field a fixed `.frame(width:)`
  matching `fieldWidth` and `.font(.system(.body, design: .monospaced))` for
  the code-role font. Commit and clamp from the `Binding`'s setter (or
  `.onSubmit`) rather than on every keystroke, mirroring
  commits-on-editing-end and reverts-on-unparseable-text; SwiftUI's own
  `FocusState` change is the analog of `controlTextDidEndEditing`.
- **Compose**: `OutlinedTextField`/`BasicTextField` with
  `keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)`, a
  leading `Text(title)`, and a `Modifier.width(...)` matching `fieldWidth`.
  Keep `onValueChange` parsing against a `String` buffer only (coercing to
  the numeric type on every keystroke would fight a user mid-edit, the same
  problem the source's no-formatter comment describes), and commit/clamp
  when focus is lost (`Modifier.onFocusChanged`), mirroring
  commits-on-editing-end.
- **React/Web**: `<input type="text" inputMode="decimal">` (not
  `type="number"`, whose native spinner and silent-empty-on-invalid behavior
  diverges from the source's explicit revert-on-invalid path, and no `pattern`
  attribute, which cannot express the source's locale-aware grammar — a
  POSIX-only pattern like `-?[0-9]*\.?[0-9]*` would reject comma-decimal
  locales and would also accept a fraction for the `Int` case) paired with a
  `<label>` wired via `aria-labelledby`/`htmlFor`, the web analog of
  `setAccessibilityTitleUIElement`. Parse and clamp on `blur`/`Enter`
  (mirroring commits-on-editing-end and commits-on-field-action), reverting
  the displayed text on a parse failure rather than accepting it, using the
  same two thin parse/format functions per type (rather than the `pattern`
  attribute) to police what each type accepts — the same generalization
  `SettingsNumberValue` gives the Swift source.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/NumberFieldView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: SettingsNumberValue`, inside the `ComposableSettings`
  namespace, conforming to `SettingsViewProtocol` and
  `NSTextFieldDelegate`. The same file declares the `SettingsNumberValue`
  protocol and its `Int`/`Double` conformances, each supplying a
  POSIX-first, then locale-`NumberFormatter`-based parse and a canonical
  `settingsFieldString`. There is no UIKit code path in source; a UIKit
  port would replace `NSTextField` with `UITextField`
  (`keyboardType = .numbersAndPunctuation` to allow a leading `-` and a
  decimal separator), replace target/action with
  `.addTarget(_:action:for: .editingDidEnd)`, and reimplement the generic
  `SettingsNumberValue`-driven parse/clamp/revert logic against
  `UITextField.text` — UIKit has no `NSCoder`-vs-frame initializer split to
  fatal-error on the way requires-designated-initializer and
  rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*` — a `TextBlock` for the title in column
  0, and a `NumberBox` — WinUI's purpose-built numeric field — in column 1,
  in place of a raw `TextBox`. Because `NumberBox.Value` is always a
  `double`, an `Int`-typed field (mirroring this recipe's `Int`
  conformance) MUST convert at the boundary with the same exactness check
  `Int.settingsExactInt(from:)` performs, rejecting (via
  `NumberBox.ValidationMode`/a `NumberBoxNumberFormatter` override) any
  value the round trip through `double` would not reproduce exactly; a
  `Double`-typed field maps directly. `NumberBox` already exposes
  `Minimum`/`Maximum` properties that map directly to this component's
  `minimum`/`maximum` when non-nil; their own unset defaults are
  `double.MinValue`/`double.MaxValue` (not `NaN`), which already mirrors
  `nil`'s no-clamp-at-that-end behavior with no extra sentinel needed.
  `NumberBox` has no equivalent of **skips-clamp-on-contradictory-bounds**,
  though: it documents no escape hatch for a caller-supplied `Minimum >
  Maximum`, so a port either validates that bounds are non-contradictory
  before setting them or accepts that `NumberBox`'s own (unspecified)
  behavior governs that case instead of this source's unclamped fallback —
  the two diverge there. `NumberBox` also parses its displayed text in the
  current culture only, with no POSIX-first fallback, so the round-trip
  guarantee behind this source's POSIX-first Design Decision (text this
  component itself wrote is guaranteed to read back correctly regardless of
  a later locale change) does not carry over automatically; a port that
  needs it must format and re-parse `NumberBox.Text` itself with the same
  POSIX-first-then-current-culture ordering rather than relying on
  `NumberBox`'s own culture-aware parsing. Setting
  `SpinButtonPlacementMode="Collapsed"` keeps it visually a bare field
  rather than a stepper. Set `NumberBox.ValidationMode=
  "InvalidInputOverwritten"` to reproduce reverts-on-unparseable-text
  (WinUI overwrites the box with the last valid value on an invalid commit,
  the same behavior as this source's `sync()` revert), and handle the
  `ValueChanged` event to write the already-clamped, committed value into
  the bound setting with an equality guard before writing, mirroring
  skips-redundant-commits. Set `AutomationProperties.LabeledBy` on the
  `NumberBox` to the `TextBlock`, the WinUI analog of
  `setAccessibilityTitleUIElement`. Give `NumberBox` a fixed `Width`
  matching `fieldWidth` (72 by default here) rather than letting it stretch
  to fill its column, the WinUI analog of fixes-field-width.

## Design Decisions

- **Decision**: Attach no `NSFormatter` to `textField`.
  **Rationale**: Per the source's own comment, a formatter with a minimum
  would reject valid intermediate text on the way to a valid number (e.g.
  typing "-" before "-5", or the "1" of "12" against a minimum of 10);
  parsing happens only on commit instead.
  **Approved**: pending
- **Decision**: Parse POSIX-first, falling back to a locale-aware parse only
  when the POSIX parse fails (or, for `Double`, produces a non-finite
  result).
  **Rationale**: Per the source's own comment on `SettingsNumberValue`, the
  field's own writer (`settingsFieldString`) is POSIX; a locale-first parse
  risks misreading the POSIX text `sync()` itself just wrote as a
  locale-formatted number instead. The source itself notes this ordering is
  unobservable and deliberately untested for `Int` (`settingsFieldString`
  emits no separators for `Int`, so neither parse branch can see a string
  the other reads differently), while `Double`'s ordering is pinned by a
  dedicated test, because a `Double`'s POSIX writer can emit a decimal point
  a locale parse could misread.
  **Approved**: pending
- **Decision**: Skip clamping entirely when `minimum` and `maximum` are both
  set and `minimum > maximum`, rather than clamping to one of them.
  **Rationale**: Per the source's own comment, "a contradictory pair comes
  from a caller's own mistake, and the field's job then is to stay usable,
  not to enforce an empty range" — whichever bound clamping would apply
  first is an arbitrary artifact of the code's line order, so the source
  instead leaves the field unbounded in that case.
  **Approved**: pending
- **Decision**: Revert silently to the last committed value on unparseable
  text, rather than storing a coerced or default value.
  **Rationale**: Per the source's own comment, "text that is not a number of
  this type is not a zero; it is a typo," and a silently-stored zero (or a
  rounded fraction) would be a value the user never typed.
  **Approved**: pending
- **Decision**: Reject a parsed `Int` whose magnitude `Int64` would otherwise
  silently clamp, via a `Decimal`-based exactness check
  (`Int.settingsExactInt(from:)`), rather than accepting the clamped
  result.
  **Rationale**: Per the source's own comment, `NSNumber.int64Value`
  saturates rather than failing on overflow, and `Double(Int64.max)` rounds
  up to exactly 2^63 — indistinguishable from a true 2^63 input as a
  `Double` — so only the `Decimal` comparison can tell a genuinely-typed
  `Int.max` apart from an overflow that would otherwise be silently stored
  as `Int.max`.
  **Approved**: pending
- **Decision**: Render a whole `Double` without a trailing fraction
  (`20.0` → `"20"`) via `Int(exactly:)`, rather than always using
  `String(self)`.
  **Rationale**: Per the source's own comment, `String(20.0)` is `"20.0"`,
  and a field that turns the `20` an extension author wrote into `20.0` the
  moment it is shown has edited a setting nobody touched.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |
| [platform-design-language](agenticdevelopercookbook://compliance/platform-compliance#platform-design-language) | passed | platform-compliance |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | reliability |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |

`native-controls-preference`, `platform-design-language`, `keyboard-navigable`,
`idempotent-operations`, and `separation-of-concerns` rest on the source's use
of a stock `NSTextField`'s own keyboard-and-focus behavior, its
skips-redundant-commits guard, and its single-responsibility split between the
generic view and the `SettingsNumberValue` parsing contract; `screen-reader-support`
is `partial` because `setAccessibilityTitleUIElement` gives the field a
spoken name, but an unparseable-text revert (**reverts-on-unparseable-text**)
changes `textField.stringValue` with no explicit `NSAccessibility` announcement
in source, so whether VoiceOver notices the reverted value while the field is
focused is left to AppKit's own, unverified-in-source, default behavior.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: cites IntegerFieldView by domain URL instead of file path and drops the out-of-scope, duplicative Design Decision about this recipe's requirement count; reformats Design Decisions to the three-line form and corrects an inaccurate parsing example in the POSIX-first decision; trims tags to five; rewords clamps-to-bounds' guard as a positive cross-reference; drops dangling trailing MUST keywords from Edge Cases; corrects the Concurrent Access edge case's actor-isolation claim; strengthens three test vectors (007, 020, 027, 030) to name a real trigger API or assert only observable outcomes; corrects WinUI 3's NumberBox.Minimum/Maximum defaults and documents its contradictory-bounds and locale-first-parsing divergence from this source; drops the web input's locale-hostile pattern attribute; marks screen-reader-support partial and documents why; backfills the missing 1.0.0 history row; remaps Compliance citations to the catalog; records the unverified theme-token contrast as an open question. |
