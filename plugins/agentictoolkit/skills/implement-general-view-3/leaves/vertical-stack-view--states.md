<!-- leaf: implement-general-view-3/vertical-stack-view--states · source: vertical-stack-view.md -->

# Vertical Stack View

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders as an invisible layout container, arranging its arranged subviews vertically with the spacing set from `SettingsLayout.default[.groupSpacing]` (see **sets-arranged-subview-spacing-from-group-spacing-token**); there is no other state. |
| Pressed | Not applicable: `VerticalStackView` sets no target/action, gesture recognizer, or tracking area on itself — it cannot receive or respond to a press. (An arranged subview may itself be pressable; that is the subview's own concern, not this wrapper's.) |
| Disabled | Not applicable: the source never reads or sets `isEnabled` or any dimmed appearance — `VerticalStackView` has no enabled/disabled concept. |
| Focused | Not applicable: `VerticalStackView` never overrides `acceptsFirstResponder` and participates in no key view loop — it cannot become focused or show a focus ring. |
| Loading | Not applicable: `VerticalStackView` performs no asynchronous work and defines no loading indicator. |
