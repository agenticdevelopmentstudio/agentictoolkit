<!-- leaf: implement-general-view-2/stepper-view--states · source: stepper-view.md -->

# StepperView

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `valueLabel` shows the current integer value as plain digits; `stepper.integerValue` matches. |
| At minimum value | `stepper.integerValue == stepper.minValue`; because `valueWraps == false`, further decrements are absorbed by `NSStepper`'s own bounds enforcement rather than wrapping to `maxValue`. This is `NSStepper`'s native behavior given the `minValue`/`valueWraps` configuration `StepperView` sets (see disables-stepper-wraparound), not custom drawing in this file. |
| At maximum value | Symmetric to the minimum case: `stepper.integerValue == stepper.maxValue`, further increments are absorbed rather than wrapping to `minValue`. |
| Pressed | Not applicable: the component renders no button of its own; `stepper`'s own arrow-press highlight while clicked is `NSStepper`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `StepperView`; `isEnabled` is never read or set on `label`, `valueLabel`, or `stepper` in source. A caller may set `stepper.isEnabled` directly through the public `stepper` property, at which point `NSStepper`'s native disabled dimming applies. |
| Focused | Not styled by `StepperView`; any focus ring when `stepper` is tabbed to is `NSStepper`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
