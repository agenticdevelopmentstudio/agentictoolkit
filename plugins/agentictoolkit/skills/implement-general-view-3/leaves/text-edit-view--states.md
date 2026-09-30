<!-- leaf: implement-general-view-3/text-edit-view--states · source: text-edit-view.md -->

# TextEditView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textField`'s value equals `viewModel.value`, rendered as plain typed characters. |
| Editing | Not styled by source — no focus-ring customization anywhere in `TextEditView.swift`; AppKit's own default `NSControl`/`NSTextField` focus ring applies when the field becomes first responder. |
| Committed | After `textField`'s target/action fires (per `NSTextField`'s own default target/action semantics — on Return and on the field resigning first responder) and the new value differs from `settingObserver.value`, `textFieldChanged(_:)` writes it into `settingObserver.value`. |
| Placeholder shown | Not applicable unless a caller sets `textField.placeholderString` directly through the public `textField` property — `viewModel` carries no placeholder value of its own. When one is set and a later theme change fires, its attributed string is restyled per restyles-existing-placeholder (see Design Decisions for why the very first, construction-time apply never restyles it). |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `label` or `textField`. A caller may set `textField.isEnabled` directly through the public property, at which point `NSTextField`'s native disabled dimming applies. |
| Pressed | Not applicable: a text field has no discrete pressed state distinct from becoming first responder and placing the caret; no such state is drawn in source. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
