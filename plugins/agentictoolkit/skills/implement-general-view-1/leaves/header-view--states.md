<!-- leaf: implement-general-view-1/header-view--states · source: header-view.md -->

# Header View

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `titleLabel`'s text in the `secondaryText` role at the `.caption` font, filling `HeaderView`'s bounds exactly; there is no other state. |
| Pressed | Not applicable: `HeaderView` sets no target/action, gesture recognizer, or tracking area, and `ThemedLabel` sets `isEditable = false` — neither can receive or respond to a press. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance on either `HeaderView` or `titleLabel` — there is no enabled/disabled concept here. |
| Focused | Not applicable: `HeaderView` never overrides `acceptsFirstResponder` and participates in no key view loop; `titleLabel` is a non-editable, non-selectable text field with no focus ring behavior coded. |
| Loading | Not applicable: `HeaderView` performs no asynchronous work of any kind and defines no loading indicator. |
