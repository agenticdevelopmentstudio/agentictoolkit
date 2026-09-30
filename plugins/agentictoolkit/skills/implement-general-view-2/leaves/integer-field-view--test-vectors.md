<!-- leaf: implement-general-view-2/integer-field-view--test-vectors · source: integer-field-view.md -->

# IntegerFieldView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| integer-field-view-001 | wraps-number-field-view | Construct `IntegerFieldView(viewModel:)` with `viewModel.minValue = 0`, `viewModel.maxValue = 10`; set `textField.stringValue = "99"`, then trigger the field's target-action (`NSApplication.shared.sendAction(textField.action!, to: textField.target, from: textField)`) | `textField.stringValue` becomes `"10"` — the clamp visible on the public `textField` shows `viewModel.minValue`/`viewModel.maxValue` reached the wrapped field's `minimum`/`maximum` bounds |
| integer-field-view-002 | exposes-constituent-views | Construct `IntegerFieldView` with any `viewModel` | `.label` and `.textField` are accessible from outside the type and are the same instances the wrapped `NumberFieldView` built |
| integer-field-view-003 | arranges-single-child | Construct `IntegerFieldView` with any `viewModel`, add it to a laid-out view hierarchy of a known size | The public `label` and `textField` together occupy the full bounds of `IntegerFieldView` with no additional outer inset: `label`'s frame `minX` equals `IntegerFieldView`'s `minX`, and `textField`'s frame `maxX` equals `IntegerFieldView`'s `maxX` |
| integer-field-view-004 | forwards-editing-end-to-wrapped-field | Set `textField.delegate` to the `IntegerFieldView` instance itself, type a valid number, then trigger `controlTextDidEndEditing` | The wrapped `NumberFieldView.commit()` runs and the new value is stored |
| integer-field-view-005 | default-field-width | Construct `IntegerFieldView(viewModel:)` with no `fieldWidth` argument | `textField.widthAnchor`'s constant is 52 |
| integer-field-view-006 | forwards-label-width | Construct `IntegerFieldView(viewModel:, labelWidth: 80)` | The wrapped field's `label.widthAnchor` constant is 80 and `label.alignment == .right` |
| integer-field-view-007 | requires-designated-initializer | Attempt `IntegerFieldView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-008 | rejects-frame-only-initialization | Attempt `IntegerFieldView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| integer-field-view-009 | confines-to-main-actor | Attempt to construct or mutate an `IntegerFieldView` from off the main actor | Compiler rejects the call at compile time under `@MainActor` isolation checking |
