<!-- leaf: implement-composable-tabs/arrange-overlay-view--states · source: composable-tabs-arrange-overlay-view.md -->

# ComposableTabsArrangeOverlayView

## States

| State | Appearance change |
|-------|------------------|
| Default | Scrim dims the content; toolbar and pane name are centered, with each control's enabled state reflecting the last `refreshAvailability()` call. |
| Add disabled (`canAdd()` is `false`) | The Add button is rendered in AppKit's standard disabled (dimmed) style and does not send its action. |
| Remove disabled (`canRemove()` is `false`) | The Remove button is rendered disabled the same way. |
| Move disabled (no directions in `availableDirections()`) | All four Move menu items are disabled and the Move button itself is disabled. |
| Pressed | Not applicable: no custom pressed-state styling exists in source; AppKit's default `.rounded` bezel press highlight applies unmodified to every button. |
| Focused | Not applicable: no custom focus-ring styling exists in source; AppKit's default keyboard-focus ring applies unmodified. |
| Loading | Not applicable: no asynchronous operation or loading indicator exists anywhere in this file. |
