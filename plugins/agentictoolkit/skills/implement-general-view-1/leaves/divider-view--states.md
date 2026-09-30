<!-- leaf: implement-general-view-1/divider-view--states · source: divider-view.md -->

# Divider View

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as a solid-fill layer, 1.0pt tall, colored `resolvedThemeScope.palette.dividerColor`; there is no other state. |
| Pressed | Not applicable: `DividerView` sets no target/action, gesture recognizer, or tracking area — it cannot receive or respond to a press. |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `DividerView` has no enabled/disabled concept. |
| Focused | Not applicable: `DividerView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `DividerView` performs no asynchronous work and defines no loading indicator. |
