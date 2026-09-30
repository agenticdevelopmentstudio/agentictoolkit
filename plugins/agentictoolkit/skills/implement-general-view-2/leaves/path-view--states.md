<!-- leaf: implement-general-view-2/path-view--states · source: path-view.md -->

# PathView

## States

| State | Appearance change |
|-------|------------------|
| Default | Displays `path` (or `"<caption>: <path>"` when `caption` is supplied), on one line, truncated in the middle if it does not fit. |
| Pressed | Not applicable: the source defines no target/action, gesture recognizer, or tracking area — `PathView` has no pressed interaction to represent. |
| Disabled | Not applicable: the source exposes no enabled/disabled API; it defines no `isEnabled` property or dimmed-appearance logic. |
| Focused | Not applicable: the view never becomes key/first responder; the source overrides no responder-chain behavior, and `NSView`'s own default (`acceptsFirstResponder == false`) applies unmodified. |
| Loading | Not applicable: the source performs no asynchronous operation and defines no loading flag, spinner, or placeholder state. |
