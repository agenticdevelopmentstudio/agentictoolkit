<!-- leaf: implement-general-controller/tab-pane-view-controller--states · source: tab-pane-view-controller.md -->

# TabPaneViewController

## States

| State | Appearance change |
|-------|------------------|
| Default (behind, depth ≥ 1) | Bar's window-background fill, border-tone outline, dimmer text roles, receded inward on every side by `4`–`12` pt depending on edge and depth. |
| Front (selected, depth 0) | Workspace backdrop fill, workspace outline color, accent-colored agent label, background overhangs the workspace edge by `1` pt, open border seam disappears into the workspace's own line. |
| Pressed | Not applicable: the card itself has no pressed appearance of its own; the only clickable subview drawn here is the close button, and it defines no pressed/highlighted image state beyond AppKit's default button feedback. |
| Disabled | Not applicable: the source defines no disabled state for the card, its labels, or its close button - `isEnabled` is never set to `false` anywhere in `TabPaneView.swift` or `TabPaneViewController.swift`. |
| Focused | Not applicable to the card as a whole, which draws no focus ring of its own. The close button is a standard `NSButton` and so participates in AppKit's default keyboard-focus-ring appearance; no custom focus appearance is defined in source. |
| Loading | Not applicable: the component has no asynchronous fetch of its own - `reload()` reads already-available data-source values synchronously and has no in-flight state to represent. |
| Branch/summary hidden | Branch and summary rows are removed from visible layout (`isHidden = true`) whenever the data source reports `nil` for that field. |
| Depth mid-transition | While `animatesDepthChanges` is `true`, moving between two depths is a `0.16` s ease-out animation of the paint and text insets, not an instantaneous state. |
