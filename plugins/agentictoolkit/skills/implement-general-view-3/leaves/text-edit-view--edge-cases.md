<!-- leaf: implement-general-view-3/text-edit-view--edge-cases · source: text-edit-view.md -->

# TextEditView

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ViewModel<String>`) is
  a non-optional, typed constructor parameter, so Swift's type system rules
  out `nil` entirely; the component needs no nil-handling path for its one
  initializer parameter. An empty `viewModel.title` or `viewModel.value`
  produces an empty label or field with no crash.
- Boundary values: Not applicable — the bound value is `String` with no
  minimum or maximum length enforced anywhere in `TextEditView.swift`; any
  length is accepted and displayed as-is.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see confines-to-main-actor).
- Error states: Not applicable — every operation in this file (the
  field's target-action commit and the `settingObserver.value` write) is
  a synchronous, non-throwing call; no `try`, `Result`, or error-producing
  API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<String>`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `TextEditView.init` unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`, replacing whatever
  handler (if any) was previously registered on that `viewModel` (see
  **claims-sole-onchange-observer**). Constructing a second `TextEditView`
  (or `SecureTextEditView`, or any other observer) against the same view
  model silently drops the earlier handler.
