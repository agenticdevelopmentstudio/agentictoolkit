<!-- leaf: implement-general-view-2/secure-text-edit-view--states · source: secure-text-edit-view.md -->

# SecureTextEditView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `textField`'s underlying value equals `viewModel.value`, rendered as one dot-mask glyph per character — `NSSecureTextField`'s own built-in masked rendering, per the source's doc comment ("so the entry is dot-masked") — see **masks-entry-with-secure-field**. |
| All other states | Editing, Committed, Placeholder shown, Disabled, Pressed, and Loading are inherited unmodified from `TextEditView`; see `agentictoolkit://recipes/text-edit-view#states`. |
