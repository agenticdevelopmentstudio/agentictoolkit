<!-- leaf: implement-general-view-2/radio-button-choice-view--edge-cases · source: radio-button-choice-view.md -->

# RadioButtonChoiceView

## Edge Cases

- Null/empty input: `viewModel` (`ChoiceViewModel<Value>`) is a non-optional,
  typed constructor parameter, so Swift's type system rules out `nil`; the
  component provides, and needs, no nil-handling path for its one required
  initializer parameter.
- Boundary values — empty `choices`: when `viewModel.choices.isEmpty`, the
  `for choice in viewModel.choices` loop never runs, `radioButtons` and
  `buttonValues` stay empty, and `NSStackView(views: [])` produces a
  zero-arranged-subview `controlsStack`. `syncSelection()`'s loop over
  `buttonValues` also never runs. No crash occurs; the row renders only its
  heading label. Source performs no guard against, or special-casing for, an
  empty `choices` array.
- Boundary values — single choice: when `viewModel.choices.count == 1`,
  exactly one radio button is created. Per AppKit's own radio-button
  behavior, once that button is selected (either at init, from
  `syncSelection()`, or by a user click) it cannot be deselected back to "no
  selection" by clicking it again — a `.radio`-type `NSButton` has no
  user-driven path back to `.off` once `.on`, and source never sets `.off`
  from anywhere except a `syncSelection()` pass that finds a *different*
  choice's value equal to `viewModel.value`.
- Boundary values — `viewModel.value` absent from `choices`: `syncSelection()`
  performs the `(value == current) ? .on : .off` comparison independently
  for every button, so a `viewModel.value` matching none of them leaves
  every radio button `.off`; source performs no fallback selection and no
  "at least one must be selected" invariant.
- Concurrent access: Not applicable — the class is `@MainActor` and `Value`
  is constrained to `Sendable`, so all construction and mutation is
  serialized to the main actor (see confines-to-main-actor).
- Error states: Not applicable — every operation in this file (each button's
  target-action and the `settingObserver.value` write) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `ChoiceViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property. `RadioButtonChoiceView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.syncSelection() }`,
  replacing whatever handler (if any) was previously registered on that
  `ChoiceViewModel` instance (see Design Decisions for this as a known
  limitation).
- Native mutual exclusion races the observer round trip: `NSButton(
  radioButtonWithTitle:)` configures each button with AppKit's `.radio`
  button type; multiple such buttons sharing the same immediate superview
  (here, `controlsStack`) natively enforce mutual exclusivity — clicking one
  turns off its siblings in that stack synchronously, as part of the click,
  before `radioChanged(_:)`'s action even fires. `UserSettingObserver`
  delivers `viewModel.onChange` (which drives `syncSelection()`) on a later
  main-queue turn, not synchronously with the write (per its own documented
  `.receive(on: DispatchQueue.main)` behavior). Between the click and that
  later turn, the visually-selected button is the one AppKit toggled
  natively, not one `RadioButtonChoiceView` set directly; `syncSelection()`'s
  later pass is authoritative and will override that native toggle if
  `viewModel.value` does not end up matching it (e.g., another party rejects
  or transforms the write before it reaches `settingObserver.value`).
