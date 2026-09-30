<!-- leaf: implement-general-view-2/number-field-view--test-vectors · source: number-field-view.md -->

# NumberFieldView

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
