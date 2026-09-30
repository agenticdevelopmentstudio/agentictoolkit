<!-- leaf: implement-general-view-3/typing-indicator-view--states · source: typing-indicator-view.md -->

# TypingIndicatorView

## States

| State | Appearance change |
|-------|------------------|
| Default | Constructed but `startAnimating()` not yet called: every dot sits at `NSView`'s default `alphaValue` of 1.0, since alpha is only ever set inside `startAnimating()`/`tick()`. |
| Pressed | Not applicable: the view has no target-action, tracking area, or button subview — nothing in the source responds to a press. |
| Disabled | Not applicable: the source has no `isEnabled`-driven appearance change; nothing disables the indicator. |
| Focused | Not applicable: the source gives the view no focus ring, key-view-loop participation, or focus-driven appearance change. |
| Loading | This is the component's entire purpose: after `startAnimating()`, the dots pulse in the left-to-right chase pattern (see **single-dot-highlighted-per-tick**) until the view is removed from its superview (see **timer-invalidated-on-removal**). |
