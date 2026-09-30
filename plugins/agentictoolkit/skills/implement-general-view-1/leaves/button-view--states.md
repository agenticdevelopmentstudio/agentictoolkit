<!-- leaf: implement-general-view-1/button-view--states · source: button-view.md -->

# Button View

## States

| State | Appearance change |
|-------|------------------|
| Default | `button` displays `viewModel.title` in `NSButton`'s default bezel style; no custom styling from `ButtonView`. |
| Pressed | Not styled by `ButtonView`; any pressed visual is `NSButton`'s own native bezel press feedback. |
| Disabled | Not implemented in `ButtonView`; the source never reads or sets `button.isEnabled`. A caller may set it directly through the public `button` property, at which point `NSButton`'s native disabled dimming applies. |
| Focused | Not styled by `ButtonView`; any focus ring is `NSButton`'s own native focus appearance. |
| Loading | Not applicable: `ButtonView` performs no asynchronous work of its own and defines no loading state. |
