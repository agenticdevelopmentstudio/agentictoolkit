<!-- leaf: implement-general-view-1/choice-slider-view--test-vectors · source: choice-slider-view.md -->

# ChoiceSliderView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| choice-slider-view-001 | arranges-row-layout | Construct `ChoiceSliderView` with any `viewModel` | `label`, `slider`, and `valueLabel` are all subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| choice-slider-view-002 | builds-tick-marks-from-choices | `viewModel.choices` has 4 entries | After init, `slider.minValue == 0`, `slider.maxValue == 3`, `slider.numberOfTickMarks == 4`, `slider.allowsTickMarkValuesOnly == true` |
| choice-slider-view-003 | flanking-labels-hug-tightly | Construct the component | After init, `label.contentHuggingPriority(for: .horizontal) == .required` and `valueLabel.contentHuggingPriority(for: .horizontal) == .required` |
| choice-slider-view-004 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| choice-slider-view-005 | fixes-value-label-width | `viewModel.choices` labels are `"Small"` and `"Extra Small"` | After init, `valueLabel`'s width constraint constant equals `ceil("Extra Small".renderedWidth(usingFont: valueLabel.font))`, the widest of the two |
| choice-slider-view-006 | initializes-from-view-model | `viewModel.title = "Size"`, `viewModel.choices = [(label: "Small", value: .small), (label: "Large", value: .large)]`, `viewModel.value = .large` | After init, `label.stringValue == "Size"`, `slider.doubleValue == 1`, `valueLabel.stringValue == "Large"` |
| choice-slider-view-007 | commits-slider-value | `viewModel.settingObserver.value == choices[0].value`; set `slider.doubleValue = 1` and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value == choices[1].value` after the call |
| choice-slider-view-008 | ignores-out-of-range-tick | Invoke `sliderChanged(_:)` directly with a stub `NSSlider` (or subclass override) whose `doubleValue` reports a rounded index of `viewModel.choices.count` (outside bounds) — a real, bound `NSSlider` with `allowsTickMarkValuesOnly` clamps `doubleValue` into `[minValue, maxValue]` and can never report an out-of-range value | `viewModel.settingObserver.value` is unchanged; no crash occurs |
| choice-slider-view-009 | skips-redundant-commits | `viewModel.settingObserver.value == choices[0].value`; set `slider.doubleValue = 0` (same index) and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| choice-slider-view-010 | syncs-on-external-change | After construction, externally change `viewModel.title` and set `viewModel.value` to a value present in `choices`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.doubleValue`, and `valueLabel.stringValue` all update to reflect the new `viewModel` state |
| choice-slider-view-011 | leaves-display-unchanged-for-unmatched-value | After construction, invoke `viewModel.onChange(newValue)` where `newValue` matches no `choices[].value` | `slider.doubleValue` and `valueLabel.stringValue` remain at whatever they were before the call |
| choice-slider-view-012 | exposes-constituent-views | Construct the component, then access `.label`, `.slider`, `.valueLabel` from outside the type | All three properties are accessible and return the same `NSTextField`/`NSSlider`/`NSTextField` instances built during init |
| choice-slider-view-013 | requires-designated-initializer | Attempt `ChoiceSliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| choice-slider-view-014 | rejects-frame-only-initialization | Attempt `ChoiceSliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
| choice-slider-view-015 | stretches-to-superview-width | Add an initialized `ChoiceSliderView` as a subview of a parent `NSView` | After `viewDidMoveToSuperview` runs, a width constraint equal to the parent's `widthAnchor`, at priority `.required - 1`, is active on the component |
| choice-slider-view-016 | confines-to-main-actor | Attempt to construct or mutate a `ChoiceSliderView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| choice-slider-view-017 | claims-onchange-observer | Register a closure on `viewModel.onChange`, then construct `ChoiceSliderView(viewModel:)` | Invoking `viewModel.onChange(newValue)` afterward no longer calls the previously registered closure; only the component's own handler runs |
