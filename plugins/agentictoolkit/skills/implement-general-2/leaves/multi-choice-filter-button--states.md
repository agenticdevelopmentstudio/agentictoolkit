<!-- leaf: implement-general-2/multi-choice-filter-button--states · source: multi-choice-filter-button.md -->

# MultiChoiceFilterButton

## States

| State | Appearance change |
|-------|------------------|
| Default | Title reads `"<label>: Any"`; no choice menu item is checked. |
| Choice selected | The corresponding menu item's `state` is `.on` (system checkmark glyph); the title updates per **formats-title-few-selected** / **formats-title-many-selected**. |
| Choice deselected / "Any" chosen | The corresponding menu item's `state` is `.off`; once no items remain checked, the title reverts to `"<label>: Any"`. |
| Pressed | Not styled by source: opening the pull-down and highlighting a hovered/pressed menu item is `NSPopUpButton`'s and `NSMenu`'s own native rendering, not custom to this file. |
| Disabled | Not implemented in source; `isEnabled` is never read or set on `self` in `MultiChoiceFilterButton.swift`. A caller may set the inherited `NSControl.isEnabled` directly, at which point `NSPopUpButton`'s native disabled dimming applies. |
| Focused | Not styled by source; any focus ring shown when the button is tabbed to is `NSPopUpButton`'s own native `NSControl` focus-ring appearance. |
| Loading | Not applicable: the component has no asynchronous operation and no loading indicator in source. |
