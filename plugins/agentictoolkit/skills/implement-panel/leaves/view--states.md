<!-- leaf: implement-panel/view--states · source: panel-view.md -->

# PanelView

## States

| State | Appearance change |
|-------|------------------|
| Default | `stackView` is empty and pinned inside the panel; the background is already painted from the current theme at construction. |
| Group added | A `GroupView` is appended as the next arranged subview, separated from the previous arranged subview (if any) by the default 20pt `groupSpacing`. |
| Heading added, stack previously non-empty | A `PanelHeadingView` is appended; the gap between it and the arranged subview before it is widened to 30pt; its width is matched to `stackView`. |
| Heading added, stack previously empty | A `PanelHeadingView` is appended as the first arranged subview; no spacing adjustment is made because there is no predecessor. |
| Theme changed | `layer?.backgroundColor` is reassigned to the new theme's `.windowBackground` role; no other visual property changes. |
| Pressed | Not applicable: `PanelView.swift` defines no target/action or gesture recognizer of its own; it is a passive layout host. |
| Disabled | Not implemented in `PanelView.swift`; `isEnabled` is never read or set anywhere in source. |
| Focused | Not applicable: the view never becomes key/first responder; `PanelView.swift` overrides no responder-chain behavior. |
| Loading | Not applicable: `PanelView.swift` performs no asynchronous operation and defines no loading indicator. |
