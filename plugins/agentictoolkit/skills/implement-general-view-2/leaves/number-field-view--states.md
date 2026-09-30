<!-- leaf: implement-general-view-2/number-field-view--states · source: number-field-view.md -->

# NumberFieldView

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `textField` shows the current value's `settingsFieldString`, right-aligned, in the code-role monospaced font. |
| Editing | The user's typed text is shown verbatim in `textField.stringValue` while focused; no `NSFormatter` is attached (deliberate — see Design Decisions), so intermediate/partial text (e.g. a leading `-`) is not rejected mid-edit. |
| Committed — valid | On Return/Tab/click-away (`controlTextDidEndEditing`) or on the field's own action firing, a parseable value is clamped (unless bounds are contradictory) and written back to `textField.stringValue` and `viewModel.settingObserver.value`. |
| Committed — invalid | An unparseable string reverts `textField.stringValue` and `label.stringValue` to the view model's current value/title; `viewModel.settingObserver.value` is left unchanged. |
| Pressed | Not applicable: the component renders no button; there is no press/highlight state to define. |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public `textField` property, at which point `NSTextField`'s native disabled dimming applies. |
| Focused | Not styled by this component; any focus ring shown when the field becomes first responder is `NSTextField`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |
