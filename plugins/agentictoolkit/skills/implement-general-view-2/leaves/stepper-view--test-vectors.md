<!-- leaf: implement-general-view-2/stepper-view--test-vectors · source: stepper-view.md -->

# StepperView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| stepper-view-001 | arranges-row-layout | Construct `StepperView` with any `viewModel` | `label`, `valueLabel`, and `stepper` are subviews of a single row view, arranged left-to-right as `[label, spacer, valueLabel, stepper]` (see Appearance/Padding), that is pinned to the component's edges; no other subview sits outside that row |
| stepper-view-002 | builds-label-from-view-model-title | `viewModel.title = "Recent Files"` | `label.stringValue == "Recent Files"` after construction |
| stepper-view-003 | builds-value-label-monospaced | Construct with any `viewModel` | `valueLabel.font` is the system monospaced font (fixed-pitch), matching `ThemeTypography.defaultStyle(.code)` |
| stepper-view-004 | resists-value-label-compression | Construct with any `viewModel` | `valueLabel`'s horizontal content compression resistance priority is `.required` |
| stepper-view-005 | configures-stepper-bounds | `viewModel.minValue = 1`, `viewModel.maxValue = 20` | `stepper.minValue == 1.0` and `stepper.maxValue == 20.0` after construction |
| stepper-view-006 | fixes-stepper-increment | Construct with any `viewModel` | `stepper.increment == 1` |
| stepper-view-007 | disables-stepper-wraparound | Construct with any `viewModel` | `stepper.valueWraps == false` |
| stepper-view-008 | initializes-stepper-value | `viewModel.value = 5` | `stepper.integerValue == 5` after construction |
| stepper-view-009 | wires-stepper-action | Any initialized `StepperView` | `stepper.target === view`; `stepper.action == Selector("stepperChanged:")` |
| stepper-view-010 | initializes-value-label-text | `viewModel.value = 5` | `valueLabel.stringValue == "5"` after construction |
| stepper-view-011 | updates-value-label-on-change | Set `stepper.integerValue = 7` and invoke `stepperChanged(stepper)` | `valueLabel.stringValue == "7"` immediately after the call |
| stepper-view-012 | commits-stepper-value | `viewModel.settingObserver.value = 3`; set `stepper.integerValue = 4` and invoke `stepperChanged(stepper)` | `viewModel.settingObserver.value == 4` after the call |
| stepper-view-013 | skips-redundant-commits | `viewModel.settingObserver.value = 4`; set `stepper.integerValue = 4` (same value) and invoke `stepperChanged(stepper)` | `viewModel.settingObserver.value`'s setter is not invoked a second time (e.g. no additional write/observer notification is recorded) |
| stepper-view-014 | syncs-on-external-change | After construction, externally change `viewModel.title`, `viewModel.minValue`, `viewModel.maxValue`, and `viewModel.value`, then invoke `viewModel.onChange(newValue)` | `label.stringValue`, `stepper.minValue`/`stepper.maxValue`, `stepper.integerValue`, and `valueLabel.stringValue` all update to reflect the new view-model state |
| stepper-view-015 | exposes-constituent-views | Construct the component, then access `.label`, `.stepper`, and `.valueLabel` from outside the type | All three properties are accessible and return the same instances built during init |
| stepper-view-016 | rejects-coder-initialization | Attempt `StepperView(coder: someCoder)` | The call traps with a fatal error; no instance is returned (requires a death/exit test harness, or a compile-time API-surface check that the initializer is unavailable — not a normal in-process XCTest assertion) |
| stepper-view-017 | rejects-frame-only-initialization | Attempt `StepperView(frame: .zero)` | The call traps with a fatal error; no instance is returned (same death/exit-test or API-surface caveat as stepper-view-016) |
| stepper-view-018 | confines-to-main-actor | Attempt to construct or mutate a `StepperView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| stepper-view-019 | replaces-view-model-onchange | Assign a spy closure to `viewModel.onChange`, then construct `StepperView(viewModel:)` | Invoking `viewModel.onChange(_:)` after construction runs `StepperView`'s own sync handler; the spy closure is not invoked |
