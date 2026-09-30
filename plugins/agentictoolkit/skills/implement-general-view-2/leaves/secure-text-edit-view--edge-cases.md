<!-- leaf: implement-general-view-2/secure-text-edit-view--edge-cases · source: secure-text-edit-view.md -->

# SecureTextEditView

## Edge Cases

All edge-case behavior — the non-optional `viewModel` parameter ruling out
`nil`, unbounded `String` length, main-actor-serialized concurrent access,
the absence of any throwing or error-producing API, no networking, and the
`viewModel.onChange` overwrite when a second observer is constructed against
the same view model — is inherited unmodified from `TextEditView`, whose
initializer `SecureTextEditView` reuses without change; see
`agentictoolkit://recipes/text-edit-view#edge-cases`.
`SecureTextEditView.swift` contributes no code beyond the
`makeTextField(initialValue:)` override, so it introduces no edge case of
its own.
