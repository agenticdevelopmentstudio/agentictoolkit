<!-- leaf: implement-general-view-1/checkbox-view--edge-cases · source: checkbox-view.md -->

# CheckboxView

## Edge Cases

- Null/empty input: `viewModel` (`ComposableSettings.ViewModel<Bool>`) is a
  non-optional, typed constructor parameter, so Swift's type system rules
  out `nil` entirely; the component needs no nil-handling path for its one
  initializer parameter. `viewModel.title` as an empty string produces a
  label with an empty string and no crash.
- Boundary values: Not applicable — the bound value is `Bool`, a two-value
  type with no minimum/maximum or intermediate range to bound.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see **confines-to-main-actor**).
- Error states: Not applicable — every operation in this file (the toggle's
  target-action and the `settingObserver.value` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ComposableSettings.ViewModel<Bool>`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `CheckboxView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.update() }`, replacing
  whatever handler (if any) was previously registered on that `viewModel`
  (see **claims-sole-onchange-observer**). Constructing a second
  `CheckboxView` (or any other observer) against the same view model
  silently drops the earlier handler.
