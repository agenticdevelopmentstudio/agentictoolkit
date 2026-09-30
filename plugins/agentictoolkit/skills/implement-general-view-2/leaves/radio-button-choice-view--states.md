<!-- leaf: implement-general-view-2/radio-button-choice-view--states · source: radio-button-choice-view.md -->

# RadioButtonChoiceView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; each radio button's `state` reflects whether its paired choice value equals `viewModel.value`. |
| Selected (per button) | `state == .on`, drawn as `NSButton`'s system filled-radio-dot appearance; set on init, on a user click that changes the value, and on any external `viewModel.onChange` that resolves to that choice. |
| Unselected (per button) | `state == .off`, drawn as `NSButton`'s system empty-radio-circle appearance; set on init and re-synced by `syncSelection()` for every button whose paired value does not equal `viewModel.value`. |
| Pressed | Not styled by this file; `NSButton`'s own mouse-down/press visual for a radio-type button is AppKit's default rendering, not custom to this file. |
| Disabled | Not implemented in `RadioButtonChoiceView`; `isEnabled` is never read or set on `label` or any element of `radioButtons` in source. A caller may set an individual `radioButtons[i].isEnabled` directly (the array elements are mutable `NSButton` references even though the array property itself is `private(set)`), at which point `NSButton`'s native disabled dimming applies to that one button. |
| Focused | Not styled by `RadioButtonChoiceView`; any focus ring when a button is tabbed to is `NSButton`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
