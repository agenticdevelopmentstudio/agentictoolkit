<!-- leaf: implement-general-view-1/font-picker-view--states · source: font-picker-view.md -->

# FontPickerView

## States

| State | Appearance change |
|-------|------------------|
| Default | `label` shows `viewModel.title`; `button` shows `viewModel.font`'s sample, titled with `describe(viewModel.font, installed: viewModel.isInstalled)`. |
| Pressed | Not applicable / inherited: clicking `button` opens the system font panel through `FontChooserButton`'s own default interaction; no custom presentation code exists in `FontPickerView.swift`. |
| Disabled | `button.isEnabled == false` and `label.alphaValue == 0.4` (see **dims-and-disables-the-row**). |
| Focused | Not applicable / inherited: no custom focus-ring styling is set in source; `button` uses `NSButton`'s default focus-ring behavior when tabbed to. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
