<!-- leaf: implement-general-view-1/captioned-slider-view--test-vectors · source: captioned-slider-view.md -->

# CaptionedSliderView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| captioned-slider-view-001 | arranges-row-layout | Construct `CaptionedSliderView` with any `viewModel`/`formatter` | `label`, `slider`, and `captionLabel` are all subviews of a single row view that is pinned to the component's edges; no other layout container appears |
| captioned-slider-view-002 | sets-slider-range | `viewModel.minValue = 0`, `viewModel.maxValue = 1` | After init, `slider.minValue == 0` and `slider.maxValue == 1` |
| captioned-slider-view-014 | does-not-validate-range | `viewModel.minValue = 10`, `viewModel.maxValue = 5` (inverted) | After init, `slider.minValue == 10` and `slider.maxValue == 5`, unmodified — no validation or correction is applied |
| captioned-slider-view-003 | slider-hugs-loosely | Construct the component | After init, `slider.contentHuggingPriority(for: .horizontal).rawValue == 1` |
| captioned-slider-view-004 | caption-resists-compression | Construct the component | After init, `captionLabel.contentCompressionResistancePriority(for: .horizontal) == .required` |
| captioned-slider-view-005 | caption-uses-monospaced-digits | Construct the component | `captionLabel`'s font descriptor includes the monospaced-digit font-feature trait |
| captioned-slider-view-006 | initializes-from-view-model | `viewModel.title = "Volume"`, `viewModel.value = 42`, `formatter = { "\(Int($0))" }` | After init, `label.stringValue == "Volume"`, `slider.doubleValue == 42`, `captionLabel.stringValue == "42"` |
| captioned-slider-view-007 | updates-caption-live | Set `slider.doubleValue = 75` and invoke `sliderChanged(slider)` (the slider's target-action), with `formatter = { "\(Int($0))%" }` | `captionLabel.stringValue` becomes `"75%"` immediately, without any `viewModel.onChange` firing |
| captioned-slider-view-008 | commits-slider-value | `viewModel.settingObserver.value = 10`; set `slider.doubleValue = 30` and invoke `sliderChanged(slider)` | `viewModel.settingObserver.value == 30` after the call |
| captioned-slider-view-009 | skips-redundant-commits | `viewModel.settingObserver.value = 50`; set `slider.doubleValue = 50` (same value) and invoke `sliderChanged(slider)` | Using a spy/counting `SettingObserver` in place of the real one, the write count recorded before the call equals the write count recorded after — `settingObserver.value`'s setter is not invoked a second time |
| captioned-slider-view-010 | syncs-on-external-change | After construction, externally change `viewModel.title` and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `slider.doubleValue`, and `captionLabel.stringValue` all update to reflect the new `viewModel` state |
| captioned-slider-view-015 | overwrites-view-model-onchange | Register a counting closure on `viewModel.onChange` before constructing `CaptionedSliderView(viewModel:formatter:)`, then invoke `viewModel.onChange(value)` after construction | The pre-registered closure is never invoked; only the component's own `sync()`-calling handler runs |
| captioned-slider-view-011 | exposes-constituent-views | Construct the component, then access `.label`, `.slider`, `.captionLabel` from outside the type | All three properties are accessible and return the same `NSTextField`/`NSSlider`/`NSTextField` instances built during init |
| captioned-slider-view-012 | requires-designated-initializer | Attempt `CaptionedSliderView(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| captioned-slider-view-013 | rejects-frame-only-initialization | Attempt `CaptionedSliderView(frame: .zero)` | The call traps with a fatal error; no instance is returned |
