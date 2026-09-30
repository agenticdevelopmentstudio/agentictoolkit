<!-- leaf: implement-composable-tabs/window-controller--states · source: composable-tabs-window-controller.md -->

# ComposableTabsWindowController

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet loaded (`window == nil`): no toolbar or titlebar accessories exist until the first `showWindow(_:)`. |
| Pressed | Not applicable — the window controller itself renders no pressable surface; per-press visuals belong to the `NSButton`/`NSToolbarItem` instances it hosts. |
| Disabled | Search field is disabled and grayed whenever the search target's `isSearchable` is `false` (see **search-availability**, **search-target**). |
| Focused | The active tab's last-focused leaf pane holds first responder, restored on tab activation and on `showWindow(_:)`. |
| Loading | Not applicable — tab and pane installation is synchronous; no loading/spinner state exists in source. |
| Arrange mode enabled | Arrange titlebar button shows accent tint and `.state = .on` (pressed-looking bezel); the bound menu item shows a checkmark. |
| Arrange mode disabled | Arrange titlebar button shows no tint and `.state = .off`; the menu item shows no checkmark. |
| Help drawer open | Help toolbar button shows the filled `questionmark.circle.fill` glyph, accent tint, and tooltip "Hide Help". |
| Help drawer closed | Help toolbar button shows the outlined `questionmark.circle` glyph, secondary-text tint, and tooltip "Show Help". |
| Single remaining tab group | The tab-close affordance for that group's members MUST have no effect (see **last-group-guard**). |
| Last enabled edge | The settings toggle for that edge MUST have no effect (see **last-edge-guard**). |
