<!-- leaf: implement-settings/window--states · source: settings-window.md -->

# SettingsWindow

## States

| State | Appearance change |
|-------|------------------|
| Default | Window not yet loaded (`window == nil`): no toolbar, navigation control, panel-title label, or help button exist until the first `showWindow()` call builds the window. |
| Pressed | Not applicable at this layer — per-press bezel visuals belong to `NSSegmentedControl`/`NSButton`, not to this controller. |
| Disabled | The navigation control's back segment is disabled when `canGoBack == false`; its forward segment is disabled when `canGoForward == false`, each independently. |
| Focused | Not applicable — this file assigns no first-responder or focus-restoration behavior of its own; a panel's own focus handling belongs to that panel, a separate ingredient. |
| Loading | Not applicable — panel and toolbar installation are synchronous; no loading/spinner state exists in this file. |
| Help drawer open | Help button shows the filled `questionmark.circle.fill` glyph, accent tint, and tooltip "Hide Help". |
| Help drawer closed | Help button shows the outline `questionmark.circle` glyph, secondary-text tint, and tooltip "Show Help". |
| Activation disabled (`activatesOnShow == false`) | `showWindow()` calls `super.showWindow()` and returns; this override itself neither calls `NSApp.activate` nor makes the window key — whatever key/visible state results comes entirely from the inherited base behavior. |
| Quiet presentation enabled | `showWindow()` makes the window key without activating the app or ordering it above other applications' windows. |
