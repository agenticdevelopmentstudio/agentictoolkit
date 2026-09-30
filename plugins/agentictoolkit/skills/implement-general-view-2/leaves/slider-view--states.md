<!-- leaf: implement-general-view-2/slider-view--states · source: slider-view.md -->

# SliderView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; slider is at `viewModel.value` with its range set to `viewModel.minValue`/`viewModel.maxValue`. |
| Dragging | No custom dragging visual: the slider's `NSSlider` default `isContinuous` behavior is left unmodified in source, so the action fires on every drag tick (not only on release), each tick invoking commits-slider-value/skips-redundant-commits; there is no caption or other view state to update, so the only visible motion is the slider's own native thumb tracking. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are `NSSlider`'s default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text field in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and label use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
