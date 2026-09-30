<!-- leaf: implement-general-view-2/slider-view--test-vectors · source: slider-view.md -->

# SliderView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| slider-view-001 | arranges-row-layout | Construct `SliderView` with any `viewModel` | The row `NSStackView`'s arranged subviews are exactly `[label, <row-spacer inserted by makeRow>, slider]` in that order; that stack view is `SliderView`'s only subview and is pinned to its edges; no other layout container appears |
| slider-view-002 | sets-slider-range | `viewModel.minValue = 0`, `viewModel.maxValue = 1` | After init, `slider.minValue == 0` and `slider.maxValue == 1` |
| slider-view-003 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| slider-view-004 | initializes-from-view-model | `viewModel.title = "Volume"`, `viewModel.value = 42` | After init, `label.stringValue == "Volume"` and `slider.doubleValue == 42` |
| slider-view-005 | commits-slider-value | `viewModel.settingObserver.value = 10`; set `slider.doubleValue = 30` and invoke `sliderChanged(slider)` (the slider's target-action) | `viewModel.settingObserver.value == 30` after the call |
| slider-view-006 | skips-redundant-commits | Substitute a counting `settingObserver` test double whose `value` setter increments a write counter; set its `value = 50`, reset the counter to 0, then set `slider.doubleValue = 50` (same value) and invoke `sliderChanged(slider)` | The counting `settingObserver`'s write counter stays at 0 after the call |
| slider-view-007 | syncs-on-external-change | After construction, externally change `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`, and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.minValue`, `slider.maxValue`, and `slider.doubleValue` all update to reflect the new `viewModel` state |
| slider-view-008 | exposes-constituent-views | Construct the component, then access `.label` and `.slider` from outside the type | Both properties are accessible and return the same `NSTextField`/`NSSlider` instances built during init |
| slider-view-009 | rejects-coder-initialization | Attempt `SliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| slider-view-010 | rejects-frame-only-initialization | Attempt `SliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| slider-view-011 | syncs-on-external-change | Change the value on the backing `UserSetting` that `viewModel.settingObserver` observes (not by calling `viewModel.onChange` directly), then await one main-queue turn (the `.dropFirst().receive(on: DispatchQueue.main)` Combine hop in `UserSettingObserver`) | `label.stringValue`, `slider.minValue`, `slider.maxValue`, and `slider.doubleValue` are unchanged immediately after the setting write, and only update to reflect the new state after that main-queue turn elapses |
| slider-view-012 | sets-slider-range | Construct `SliderView` with `viewModel.minValue = 10`, `viewModel.maxValue = 0` (an inverted range; a zero-width case such as `minValue = maxValue = 5` is equivalent) | `slider.minValue == 10` and `slider.maxValue == 0` — assigned unchanged from `viewModel`, with no clamping, swapping, or correction |
