<!-- leaf: implement-general-view-1/choice-slider-view--states · source: choice-slider-view.md -->

# ChoiceSliderView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; when `viewModel.value` matches a choice, the slider sits at that choice's tick and the value label shows that choice's `label`. |
| Dragging | The slider's on-screen thumb snaps to the nearest tick continuously as it is dragged (`allowsTickMarkValuesOnly`). The value label's text, however, updates only once the committed value round-trips through `viewModel.onChange` — `UserSettingObserver` delivers that callback on a *later* main-queue turn (`.receive(on: DispatchQueue.main)`), not synchronously inside the slider's action — so the value label can lag one main-queue turn behind the slider's visible tick position. |
| Pressed | Not applicable: the component renders no button; the slider's own pressed/thumb-drag visuals are `NSSlider`'s default AppKit rendering, not custom to this file. |
| Disabled | Not applicable: `isEnabled` is never set on the slider or text fields in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; the slider and labels use AppKit's default `NSControl` focus-ring behavior when the row is tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
