<!-- leaf: implement-panel/heading-view--states · source: panel-heading-view.md -->

# PanelHeadingView

## States

| State | Appearance change |
|-------|------------------|
| Default | Renders `titleLabel`'s text at the `.primaryText`/`.heading` style; whether a caption follows depends on the `caption` argument given at construction. |
| Caption present | `captionView` is constructed and arranged below `titleLabel`, 6pt apart, its width matched to the stack; `captionLabel` returns its `label`. |
| Caption absent | `captionView` is `nil` and never constructed; only `titleLabel` is an arranged subview; `captionLabel` returns `nil`. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `PanelHeadingView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
