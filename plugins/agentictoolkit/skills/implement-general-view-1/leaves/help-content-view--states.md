<!-- leaf: implement-general-view-1/help-content-view--states · source: help-content-view.md -->

# HelpContentView

## States

| State | Appearance change |
|-------|------------------|
| Default | Heading reads "Help"; scroll area shows whatever `setHelp(_:)` was last called with. |
| Empty (`setHelp(nil)` or empty `topics`) | Scroll area shows the single "No Help Yet" group — see **empty-state**. |
| Populated (one or more topics) | Scroll area shows one `GroupView` per topic, in array order — see **topic-groups**. |
| Pressed | Not applicable: `HelpContentView.swift` defines no target/action, gesture recognizer, or tracking area of its own; it is a non-interactive content view. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: `HelpContentView` never becomes key/first responder itself; the source overrides no responder-chain behavior, and any keyboard focus lands on the scroll view's own default targets, not on this view. |
| Loading | Not applicable: `setHelp(_:)` is synchronous; the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
