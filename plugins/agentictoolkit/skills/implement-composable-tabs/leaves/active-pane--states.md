<!-- leaf: implement-composable-tabs/active-pane--states · source: composable-tabs-active-pane.md -->

# ComposableTabsActivePane

## States

| State | Appearance change |
|-------|--------------------|
| No pane has claimed the window yet | No pane's backdrop draws the accent color; every pane reads as "inactive" (hairline outline) until the first `paneDidAppear` claims the spot. |
| Active pane, window focused, highlighting enabled | 2pt border in `projectActivePaneOutline`; backdrop in `projectPaneBackdrop`. |
| Active pane, window not focused (not key and no key attached sheet) | 2pt border in `projectPaneOutline`, same as an inactive pane. |
| Active pane, highlighting disabled (by user setting or theme override) | 2pt border in `projectPaneOutline`, same as an inactive pane. |
| Inactive pane | 2pt border in `projectPaneOutline`; backdrop in `projectPaneBackdrop`. |
| Arrange mode enabled in the window | Pointer movement no longer changes the active pane; clicks still do. |
| Window has an attached sheet | Pointer movement no longer changes the active pane in that window; the sheet itself has the keys. |
