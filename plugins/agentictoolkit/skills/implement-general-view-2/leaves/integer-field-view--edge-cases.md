<!-- leaf: implement-general-view-2/integer-field-view--edge-cases · source: integer-field-view.md -->

# IntegerFieldView

## Edge Cases

- **Null/empty input**: `viewModel` (`RangeViewModel<Int>`) is a
  non-optional, typed constructor parameter; Swift's type system rules out
  `nil`. The wrapped field's own revert-on-empty-text behavior — an empty
  `textField.stringValue` fails the parse the same as any other unparseable
  text — is documented at
  `agentictoolkit://recipes/number-field-view#edge-cases`.
- **Boundary values**: Clamping at `minimum`/`maximum`, and skipping the
  clamp when `minimum > maximum`, is entirely the wrapped
  `NumberFieldView<Int>`'s behavior; see
  `agentictoolkit://recipes/number-field-view#edge-cases`. `IntegerFieldView`
  only supplies those bounds, via `viewModel.minValue`/`viewModel.maxValue`
  (**wraps-number-field-view**).
- **Out-of-range magnitude and fractional/locale-formatted text**: Parsing
  — POSIX-first with a locale-aware fallback, magnitude-exactness rejection,
  and fractional rejection — is entirely the wrapped `NumberFieldView<Int>`'s
  behavior; see `agentictoolkit://recipes/number-field-view#edge-cases`.
- **Concurrent access**: Not applicable — `IntegerFieldView` is declared
  `@MainActor` (**confines-to-main-actor**), so all construction and
  mutation is serialized to the main actor by the compiler. The wrapped
  `NumberFieldView<Int>` carries the same isolation independently; see
  `agentictoolkit://recipes/number-field-view#edge-cases`.
- **Error states**: Not applicable — every operation in
  `IntegerFieldView.swift` (construction, forwarding, and
  `controlTextDidEndEditing`) is synchronous and non-throwing; no `try`,
  `Result`, or error-producing API appears in this file.
- **Offline/disconnected state**: Not applicable — the component performs
  no networking; it only forwards to the wrapped `NumberFieldView<Int>`,
  which itself only reads from and writes to an in-process view model.
- **Overwritten external observer**: This is entirely the wrapped
  `NumberFieldView<Int>`'s behavior — its initializer, not
  `IntegerFieldView`'s, unconditionally assigns `viewModel.onChange`; see
  `agentictoolkit://recipes/number-field-view#edge-cases`.
- **Delegate reassignment**: Because `textField.delegate` is set to the
  `NumberFieldView` instance, not `IntegerFieldView`, a caller that
  reassigns `textField.delegate` to something else silently disables
  `commit()`-on-editing-end; `IntegerFieldView.controlTextDidEndEditing(_:)`
  only fires if a caller explicitly re-points `textField.delegate` back at
  the outer `IntegerFieldView` (see Design Decisions).
