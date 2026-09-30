<!-- leaf: implement-general-controller/log-view-controller--states · source: log-view-controller.md -->

# Log View Controller

## States

| State | Appearance change |
|-------|------------------|
| Default | Toolbar (leading items, Pause, Clear, status dot, status label) above a 1pt divider above the log view, filling the root view; root view background is `.windowBackground`. |
| Pressed | Not applicable: the pause/clear buttons' pressed-state fill (a swap between the `.elevatedSurface` and `.selection` role colors on `isHighlighted`) is owned by `ThemedSecondaryButton`, a separate themed control; the component applies no pressed-state styling of its own. |
| Disabled | Not applicable: the component never sets `isEnabled = false` on the pause or clear button; both remain enabled regardless of connection, pause, or error state. |
| Focused | Not applicable: the component sets no custom focus-ring appearance on any control; whatever focus ring AppKit draws by default for a standard `NSButton` is unmodified. |
| Loading | Represented by the Connecting state below; there is no separate loading spinner or progress indicator. |
| Connected | `controller.isConnected == true`: status dot fills with the `.success` role color; status label text and tooltip read `Connected`. |
| Connecting | `controller.isConnected == false` and `controller.lastError == nil`: status dot fills with the `.warning` role color; status label text and tooltip read `Connecting…`. |
| Error | `controller.isConnected == false` and `controller.lastError != nil`: status dot fills with the `.danger` role color; status label text and tooltip read the error string verbatim. |
| Paused | `controller.isPaused == true`: pause button title reads `Resume`. `controller.isPaused == false`: pause button title reads `Pause`. |
