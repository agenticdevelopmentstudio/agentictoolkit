<!-- leaf: implement-composable-tabs/view-registry--states · source: composable-tabs-view-registry.md -->

# ComposableTabsViewRegistry

## States

| State | Appearance change |
|-------|------------------|
| Default | Numbered title centered over a container tinted by the pane's chart-series color at 0.15 alpha (or untinted if the series is empty). |
| Pressed | Not applicable: neither the container nor the title is a control; the source attaches no click/press handling to either. |
| Disabled | Not applicable: the source defines no enabled/disabled state for this view. |
| Focused | Not applicable: the title is a non-editable, non-interactive `ThemedLabel`; the source gives the container no focus ring or key-view behavior. |
| Loading | Not applicable: the view has no asynchronous content or loading affordance; it is populated synchronously in `loadView()`. |
