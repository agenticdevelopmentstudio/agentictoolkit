<!-- leaf: implement-general-view-3/text-edit-view--test-vectors · source: text-edit-view.md -->

# TextEditView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| text-edit-view-001 | constructs-plain-text-field | Construct `TextEditView` with any `viewModel` | `textField` is an instance of `NSTextField` whose `stringValue` equals `viewModel.value` |
| text-edit-view-002 | supports-text-field-substitution | Declare a subclass of `TextEditView` overriding `makeTextField(initialValue:)` to return an `NSSecureTextField` | The subclass compiles and constructing it produces a `textField` of the overridden type, with the row layout, theming, and commit wiring unchanged |
| text-edit-view-003 | arranges-row-layout | Construct `TextEditView` with any `viewModel` | `label` and `textField` are both subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| text-edit-view-004 | expands-text-field-to-fill-row | Inspect `textField`'s horizontal content-hugging priority relative to the row spacer's after construction | `textField`'s priority is lower than the row spacer's hugging priority, so the field absorbs the row's leftover width (see Design Decisions for the exact value) |
| text-edit-view-005 | wires-text-field-action | Any initialized `TextEditView` | `textField.target` is the view itself; invoking `textField`'s registered commit action reaches the view's edit-commit handler, which can write to `settingObserver` (see Platform Notes for the specific selector name) |
| text-edit-view-006 | initializes-from-view-model | `viewModel.title = "Server Name"`, `viewModel.value = "prod-1"` | After init, `label.stringValue == "Server Name"` and `textField.stringValue == "prod-1"` |
| text-edit-view-007 | commits-value-on-change | `viewModel.settingObserver.value = "old"`; set `textField.stringValue = "new"` and invoke `textFieldChanged(textField)` | `viewModel.settingObserver.value == "new"` after the call |
| text-edit-view-008 | skips-redundant-commits | `viewModel.settingObserver.value = "same"`; set `textField.stringValue = "same"` and invoke `textFieldChanged(textField)`, observing writes via a recording spy or observer registered on `settingObserver` | The spy/observer records zero additional writes to `settingObserver.value` after the call |
| text-edit-view-009 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue` and `textField.stringValue` both update to reflect the new `viewModel` state |
| text-edit-view-010 | applies-theme-styling | Construct the view, then trigger a theme change | `textField.font` equals the theme's `.body`-role font and `textField.textColor` equals the theme's `primaryText` color, both immediately after construction and again after the theme change |
| text-edit-view-011 | restyles-existing-placeholder | After construction, set `textField.placeholderString = "Enter value"`, then trigger a theme change | `textField.placeholderAttributedString`'s color attribute equals the theme's `placeholderText` color and its font equals the theme's `.body`-role font |
| text-edit-view-012 | exposes-constituent-views | Construct the component, then access `.label` and `.textField` from outside the type | Both properties are accessible and return the same `NSTextField` instances built during init |
| text-edit-view-013 | requires-designated-initializer | Attempt `TextEditView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| text-edit-view-014 | rejects-frame-only-initialization | Attempt `TextEditView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| text-edit-view-015 | confines-to-main-actor | (Static/compile-time check, not a runtime assertion) Attempt to construct or mutate a `TextEditView` from off the main actor | The call fails to compile under Swift's `@MainActor` isolation checking; there is no runtime behavior to observe |
| text-edit-view-016 | conforms-to-settings-view-protocol | Any `TextEditView` instance | `view is SettingsViewProtocol` evaluates `true` |
| text-edit-view-017 | claims-sole-onchange-observer | Register an observer closure on `viewModel.onChange`, then construct a `TextEditView` against that same `viewModel` | `viewModel.onChange` now points at `TextEditView`'s own handler; invoking it no longer calls the previously registered closure |
