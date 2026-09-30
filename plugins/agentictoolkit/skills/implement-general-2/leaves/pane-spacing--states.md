<!-- leaf: implement-general-2/pane-spacing--states · source: pane-spacing.md -->

# PaneSpacing

## States

| State | Appearance change |
|-------|------------------|
| Default — hairline gutter (`dividerThickness` ≤ 1pt) | AppKit's own `.thin`-style divider paint via `super.drawDivider(in:)`. |
| Default — wide gutter (`dividerThickness` > 1pt) | Divider rect filled with `currentPalette.projectPaneBackdrop`. |
| Pressed | Not applicable: dragging a divider is `NSSplitView`'s own built-in behavior; this file paints no pressed/highlighted state of its own. |
| Disabled | Not applicable: neither `PaneSpacing` nor `PaneSplitView` expose a disabled state; a `0`-point gutter is a valid, still-draggable style choice (see `minimumDividerGrab`), not a disabled divider. |
| Focused | Not applicable: no focus ring or focus-driven appearance change appears in this source. |
| Loading | Not applicable: all six settings are read synchronously from local storage; this source has no async operation and no loading state. |
