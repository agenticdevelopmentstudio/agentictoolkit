<!-- leaf: implement-general-view-1/checkbox-view--states · source: checkbox-view.md -->

# CheckboxView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; toggle state reflects `viewModel.value`. |
| On | `toggle.state == .on`, drawn as `NSSwitch`'s system on-track appearance; set on init when `viewModel.value == true`, and on any user or external change that sets the value `true`. |
| Off | `toggle.state == .off`, drawn as `NSSwitch`'s system off-track appearance; set on init when `viewModel.value == false`, and on any user or external change that sets the value `false`. |
| Pressed | Not applicable: the component renders no button; the toggle's own drag/press animation while switching on or off is `NSSwitch`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `CheckboxView`; `isEnabled` is never read or set on `label` or `toggle` in source. A caller may set `toggle.isEnabled` directly through the public `toggle` property, at which point `NSSwitch`'s native disabled dimming applies. |
| Focused | Not styled by `CheckboxView`; any focus ring when the toggle is tabbed to is `NSSwitch`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
