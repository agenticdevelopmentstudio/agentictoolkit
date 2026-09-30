<!-- leaf: implement-general-view-2/slider-view--edge-cases · source: slider-view.md -->

# SliderView

**Rules** (cite as `implement-general-view-2/slider-view--edge-cases#<slug>`):

- `triggering-slider-action-level-implementor-note-range` SHOULD — Asynchronous re-sync timing: viewModel.onChange is driven through ComposableSettings.UserSettingObserver …

## Edge Cases

- Null/empty input: `viewModel` (`RangeViewModel<Double>`) is a
  non-optional, non-escaping-typed constructor parameter, so Swift's type
  system rules out `nil` at the call site — this is a property of the
  parameter's type, not a behavior the component implements, so the
  component provides, and needs, no nil-handling path of its own for its
  one initializer parameter.
- Boundary values — inverted/zero-width range: source performs no
  `minValue < maxValue` validation before assigning `slider.minValue`/
  `slider.maxValue` from `viewModel`, either at init or in the `onChange`
  re-sync (see slider-view-012). If `viewModel.minValue >= viewModel.maxValue`,
  `SliderView` adds no guard of its own; the resulting slider behavior is
  whatever `NSSlider` does for an equal-or-inverted range. This is an
  absence rather than an enforced rule: nothing in source validates or
  corrects `viewModel`'s bounds.
- Concurrent access: Not applicable — the class and its `onChange` closure
  are both `@MainActor`-isolated, so Swift's concurrency checker
  serializes all access to the main actor; there is no code path by which
  two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this file (the
  slider's target-action and the `settingObserver.value` write) is a
  synchronous, non-throwing call; no `try`, `Result`, or error-producing
  API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property, and `SliderView`'s initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in ... }`. See the one-observer-
  per-view-model Design Decision for the resulting contract and its
  rationale.
- Asynchronous re-sync timing: `viewModel.onChange` is driven through
  `ComposableSettings.UserSettingObserver`
  (`packages/apple/AgenticToolkit/Core/SettingStorage/UserSetting.swift`),
  whose `onChange` is delivered from a Combine pipeline that does
  `.dropFirst().receive(on: DispatchQueue.main).sink { ... }` on the
  setting's `$currentValue` publisher. A commit made inside
  `sliderChanged(_:)` therefore does not call this view's `onChange`
  re-sync back synchronously within the same call; the label/range/value
  re-sync in syncs-on-external-change happens on a later turn of the main
  dispatch queue, not inline with the triggering slider action. This is a
  SHOULD-level implementor note: the range and value re-sync SHOULD be
  expected to lag one dispatch-queue turn behind a commit made by this
  same view.
