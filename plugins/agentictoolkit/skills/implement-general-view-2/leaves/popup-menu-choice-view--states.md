<!-- leaf: implement-general-view-2/popup-menu-choice-view--states · source: popup-menu-choice-view.md -->

# PopupMenuChoiceView

## States

| State | Appearance change |
|-------|------------------|
| Default | Label shows `viewModel.title`; `popUpButton`'s selected item matches the choice whose `value` equals `viewModel.value`, if one exists. |
| Menu Open | Not styled by this file; `NSPopUpButton`'s own native menu presentation (item list, chevron pair) when clicked — not custom in source. |
| Item Selected | The item the user clicks becomes `popUpButton.selectedItem`; `popupChanged(_:)` then commits its `representedObject` (cast to `Value`) to `viewModel.settingObserver.value` per **commits-selection-value**, **ignores-unresolvable-selection**, and **skips-redundant-commits**. |
| Pressed | Not applicable: the component renders no button of its own; the popup's own press/active bezel-less appearance while its menu is open is `NSPopUpButton`'s default AppKit rendering, not custom to this file. |
| Disabled | Not implemented in `PopupMenuChoiceView`; `isEnabled` is never read or set on `label` or `popUpButton` in source. A caller may set `popUpButton.isEnabled` directly through the public `popUpButton` property, at which point `NSPopUpButton`'s native disabled dimming applies. |
| Focused | Not styled by `PopupMenuChoiceView`; any focus ring when the popup is tabbed to is `NSPopUpButton`'s own native `NSControl` focus appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
