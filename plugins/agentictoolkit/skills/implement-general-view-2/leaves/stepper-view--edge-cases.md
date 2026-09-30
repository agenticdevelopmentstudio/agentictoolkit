<!-- leaf: implement-general-view-2/stepper-view--edge-cases · source: stepper-view.md -->

# StepperView

**Rules** (cite as `implement-general-view-2/stepper-view--edge-cases#<slug>`):

- `overwritten-external-observer` MUST — viewModel.onChange is a single closure property; per replaces-view-model-onchange, StepperView's initializer …

## Edge Cases

- **Null/empty input**: `viewModel` (`RangeViewModel<Int>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`. An empty
  `viewModel.title` produces a `label` with an empty string and no crash. The
  component provides, and needs, no nil-handling path for its one initializer
  parameter.
- **Boundary values**: At `stepper.integerValue == minValue` or `== maxValue`,
  `NSStepper`'s own bounds enforcement (given `valueWraps == false`) stops
  further movement in that direction rather than wrapping to the opposite
  bound; because `Int` bounds and a fixed `increment` of `1` always land
  exactly on both ends, every value in `[minValue, maxValue]` is reachable.
- **Contradictory bounds (`minValue > maxValue`)**: `StepperView.swift`
  forwards `viewModel.minValue`/`viewModel.maxValue` to
  `stepper.minValue`/`stepper.maxValue` with no validation or reordering — see
  the Design Decision on inverted-bounds handling.
- **Concurrent access**: Not applicable — the class is declared `@MainActor`,
  so all construction and mutation is serialized to the main actor by the
  compiler (see confines-to-main-actor).
- **Error states**: Not applicable — every operation in this file (the
  stepper's target-action, the label/value-label text updates, and the
  `settingObserver.value` write) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel<Int>`.
- **Overwritten external observer**: `viewModel.onChange` is a single closure
  property; per replaces-view-model-onchange, `StepperView`'s initializer
  unconditionally overwrites it, replacing whatever handler (if any) was
  previously registered — the same closure-overwrite behavior `CheckboxView`
  and `IntegerFieldView` document. The component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance.
