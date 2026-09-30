<!-- leaf: implement-general-view-2/text-area-edit-view--states · source: text-area-edit-view.md -->

# TextAreaEditView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textView.string` equals `viewModel.value`, rendered in the theme's body/code font and colors described in Appearance. |
| Focused | Not styled by source — no focus-ring customization appears anywhere in `TextAreaEditView.swift`; AppKit's own default `NSTextView`/`NSScrollView` focus ring applies when `textView` becomes first responder. |
| Committed | After `commit()` runs (per end-editing-commit, window-detachment-commit, or teardown-notification-observers) and `textView.string` differs from `settingObserver.value`, the new value is written through (see commit-echo-guard). |
| External value adopted | When `viewModel.onChange` fires with a value the component did not itself just write, `textView.string` is replaced with the new value (see external-value-adoption), and the caret jumps to its end if the editor currently has focus (see caret-position-on-external-change). |
| Disabled | Not implemented in source: `textView.isEditable` and `isSelectable` are never set (both default `true`, so the field is always editable). A caller may set either directly through the public `textView` property; because `NSTextView` is not an `NSControl`, doing so produces no automatic visual dimming the way disabling an `NSControl` would. |
| Pressed | Not applicable: a text editor has no discrete pressed state distinct from becoming first responder and placing the caret; no such state is drawn in source. |
| Loading | Not applicable: the component performs no asynchronous operation and shows no loading indicator in source. |
