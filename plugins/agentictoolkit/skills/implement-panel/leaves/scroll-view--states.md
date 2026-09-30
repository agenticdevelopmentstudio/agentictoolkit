<!-- leaf: implement-panel/scroll-view--states · source: panel-scroll-view.md -->

# PanelScrollView

## States

| State | Appearance change |
|-------|------------------|
| Default | Scroll view is active; scrollers autohide until scrolling or hovering (`autohidesScrollers = true`). |
| Pressed | Not applicable |
| Disabled | Not applicable |
| Focused | Not applicable |
| Loading | Not applicable |

Not applicable (Pressed/Disabled/Focused/Loading): `NSScrollView` is not an
`NSControl`, so `PanelScrollView` has no pressed or enabled/disabled state in
source; `init` does not override `acceptsFirstResponder`, so focus belongs to
whatever content is installed via `setContent`, not to the panel itself; and
the component has no loading or progress state anywhere in
`PanelScrollView.swift`.
