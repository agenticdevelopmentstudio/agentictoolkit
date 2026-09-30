<!-- leaf: implement-window/explorer-view--states · source: window-explorer-view.md -->

# WindowExplorerView

## States

| State | Appearance change |
|-------|------------------|
| Default | Populated: header bar, divider, and a sectioned list of app groups and window rows. |
| Pressed | Not applicable — the view applies no custom pressed styling; toggle and button press feedback is the system `.checkbox`/`.borderless`/`.bordered` chrome. |
| Disabled | Refresh button disabled while `isLoading`; a section's select-all toggle disabled when it has no selectable windows; a row's toggle disabled, and its title colored `theme.secondaryText`, when its window is not selectable. |
| Focused | Not applicable — no `.focused()`/custom focus-ring styling appears in source; standard keyboard focus rendering on each `Toggle`/`Button` applies unmodified. |
| Loading | List content replaced by a centered `ProgressView` (`.scaleEffect(0.8)`) and the caption "Scanning windows...", in a `minHeight: 200` frame. |
| Empty | After a completed scan with no application groups: a centered `macwindow.on.rectangle` icon, "No windows found", and the hint "Make sure Accessibility permission is granted.", in a `minHeight: 200` frame. |
| Accessibility banner shown | `needsAccessibility == true`: a warning-tinted banner is shown above whichever of Default, Loading, or Empty is otherwise active. |
| Section fully selected | Select-all toggle for that section shows checked. |
| Section partially or not selected | Select-all toggle for that section shows unchecked (covers both "some selected" and "none selected"). |
| Row's window owned by the active group | Toggle enabled, no context badge shown (the badge is suppressed when the owning context equals `activeGroupID`). |
| Row's window owned by a different context | Toggle disabled, title dimmed to `theme.secondaryText`, and a colored context-name badge is shown. |
