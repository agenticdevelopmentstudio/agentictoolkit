<!-- leaf: implement-general-view-1/color-picker-view--states · source: color-picker-view.md -->

# ColorPickerView

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `colorWell` shows `viewModel.color`. |
| Pressed | Not applicable / inherited: clicking `colorWell` opens the system color panel through `NSColorWell`'s own default AppKit interaction; no custom presentation code exists in `ColorPickerView.swift`. |
| Disabled | Not applicable: `isEnabled` is never set on `colorWell` or `label` in source; the row is always enabled. |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; `colorWell` uses AppKit's default `NSControl` focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
