<!-- leaf: implement-composable-tabs/pane-view-controller--states · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: the pane container itself has no pressed state; its individual controls (the gear button, the overlay's Add/Remove/Move/Done buttons) have their own, and those belong to the components that draw them. |
| Disabled | Not applicable: a pane is never disabled as a whole. Individual actions (Add, Remove, each move direction, the gear's Move item) are independently enabled or disabled — see Behavioral Requirements. |
| Focused | Not applicable as a visual state of this view; the closest analog is "Active pane" below, which is a pane-level concept driven by `ComposableTabsActivePane`, not first-responder focus ring drawing. |
| Loading | Not applicable: any loading state belongs to the hosted content view controller, which has its own recipe; this class has no loading indicator of its own. |
| Active pane | 2pt border in the theme's active-pane accent color (`projectActivePaneOutline`), shown when the window is key (or an attached sheet is key) and this pane is that window's active pane. |
| Inactive pane | 2pt border in the theme's hairline outline color (`projectPaneOutline`). |
| Arranging | Content is dimmed behind a 72%-alpha scrim with a centered toolbar (pane name, Add, Remove, Move, Done); a local arrow-key monitor is installed. Exiting via Return, Enter, Escape, or Done removes the scrim and the monitor. |
