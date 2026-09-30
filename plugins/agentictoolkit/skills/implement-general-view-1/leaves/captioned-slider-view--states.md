<!-- leaf: implement-general-view-1/captioned-slider-view--states · source: captioned-slider-view.md -->

# CaptionedSliderView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; slider is at `viewModel.value`; caption shows `formatter(viewModel.value)`. |
| Dragging | Caption updates live to `formatter(newValue)` as the slider's action fires, ahead of any view-model round trip (see updates-caption-live). |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are NSSlider's default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
