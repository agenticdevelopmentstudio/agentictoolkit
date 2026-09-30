<!-- leaf: implement-general-view-2/horizontal-stack-view--states · source: horizontal-stack-view.md -->

# Horizontal Stack View

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged subviews horizontally with `SettingsLayout.default[.groupSpacing]` spacing between them (see **group-spacing**); there is no other state. |
| Pressed | Not applicable: `HorizontalStackView` sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged subview may itself be pressable; that is the subview's own concern, not this wrapper's.) |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `HorizontalStackView` has no enabled/disabled concept. |
| Focused | Not applicable: `HorizontalStackView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `HorizontalStackView` performs no asynchronous work and defines no loading indicator. |
