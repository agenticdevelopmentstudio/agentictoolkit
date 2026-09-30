<!-- leaf: implement-general-view-1/captioned-slider-view--edge-cases · source: captioned-slider-view.md -->

# CaptionedSliderView

**Rules** (cite as `implement-general-view-1/captioned-slider-view--edge-cases#<slug>`):

- `earlier-handler-component-not-assumed-coexist-another-onchange` MUST — Overwritten external observer: viewModel.onChange is a single closure property, and the component's initializer …
- `single-line-source-level-note-implementors-caption` SHOULD — Caption can change a second time after release: sliderChanged(_:) sets the caption optimistically from newValue before …

## Edge Cases

- Null/empty input: `viewModel` (`RangeViewModel<Double>`) and `formatter`
  are non-optional constructor parameters — `formatter` is additionally
  `@escaping`, since the initializer stores it on the instance for later
  calls from `sync()` and `sliderChanged(_:)`. Swift's type system rules
  out `nil` for either parameter, so the component needs no nil-handling
  path for its two initializer parameters.
- Boundary values — inverted/zero-width range: source performs no
  `minValue < maxValue` validation before assigning `slider.minValue`/
  `slider.maxValue` from `viewModel` (see **does-not-validate-range**). If
  `viewModel.minValue >= viewModel.maxValue`, the resulting slider
  behavior is whatever `NSSlider` does for an equal-or-inverted range.
- Concurrent access: Not applicable — the class and the `formatter`
  closure are both `@MainActor`-isolated, so Swift's concurrency checker
  serializes all access to the main actor; there is no code path by which
  two threads can mutate the view simultaneously.
- Error states: Not applicable — every operation in this file (the
  slider's target-action, the formatter call, and the
  `settingObserver.value` write) is a synchronous, non-throwing call; no
  `try`, `Result`, or error-producing API appears in source.
- Offline/disconnected: Not applicable — the component performs no
  networking of its own; it only reads from and writes to an in-process
  `RangeViewModel`.
- Overwritten external observer: `viewModel.onChange` is a single closure
  property, and the component's initializer unconditionally overwrites it
  (see **overwrites-view-model-onchange**). Constructing a second
  `CaptionedSliderView` (or any other observer) against the same view
  model silently drops the earlier handler; the component MUST NOT be
  assumed to coexist with another `onChange` observer already registered
  on the same `RangeViewModel` instance.
- Caption can change a second time after release: `sliderChanged(_:)`
  sets the caption optimistically from `newValue` before writing to
  `settingObserver.value`. If that write causes `settingObserver` to
  clamp or otherwise transform the value and re-fire `viewModel.onChange`,
  `sync()` then overwrites the caption with `formatter(viewModel.value)`
  — the view model's actual accepted value, not the optimistic
  `newValue`. This is inferred from the interaction between
  `sliderChanged(_:)` and `sync()` rather than stated as a single line in
  source; it is a SHOULD-level note for implementors: the caption SHOULD
  be expected to update a second time, after slider release, without
  further user action, whenever the view model does not accept a value
  as-given.
