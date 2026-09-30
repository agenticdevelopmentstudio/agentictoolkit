<!-- leaf: implement-general-view-1/explanation-view--states · source: explanation-view.md -->

# ExplanationView

## States

| State | Appearance change |
|-------|------------------|
| Default | Displays `text` from `init(withText:)`, wrapped across as many lines as the container's width requires. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `ExplanationView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
