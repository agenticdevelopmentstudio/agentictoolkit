<!-- leaf: implement-general-view-2/secure-text-edit-view--test-vectors · source: secure-text-edit-view.md -->

# SecureTextEditView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secure-text-edit-view-001 | masks-entry-with-secure-field | Construct `SecureTextEditView` with any `viewModel` | `textField` is an instance of `NSSecureTextField`, not a plain `NSTextField` |
| secure-text-edit-view-002 | forecloses-subclassing | Attempt to declare a subclass of `ComposableSettings.SecureTextEditView` | Compiler rejects the declaration (`final`) |

All other conformance test vectors — row layout, content-hugging, target/
action wiring, view-model sync, theme styling, placeholder restyling,
constituent-view exposure, the initializer traps, and main-actor confinement
— are inherited unmodified from `TextEditView`; see
`agentictoolkit://recipes/text-edit-view#test-vectors`.
