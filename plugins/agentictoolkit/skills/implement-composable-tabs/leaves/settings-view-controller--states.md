<!-- leaf: implement-composable-tabs/settings-view-controller--states · source: composable-tabs-settings-view-controller.md -->

# ComposableTabsSettingsViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | Sheet opens with the Tabs panel selected (`selectPanel(at: 0)`); each edge checkbox reflects `isEdgeEnabled(edge)`; Done is enabled. |
| On (edge checkbox) | `checkbox.state == .on`, attributed title drawn in `.primaryText`/`.body`; set on init when `isEdgeEnabled(edge)` is `true`, and after any toggle that `isEdgeEnabled` confirms as enabled. |
| Off (edge checkbox) | `checkbox.state == .off`; set on init when `isEdgeEnabled(edge)` is `false`, and after any toggle — including a refused attempt to disable the last enabled edge, which this file re-reads back to `.on` rather than leaving it `.off` (see **reverts-checkbox-to-authoritative-state**). |
| Pressed | Not applicable: this file sets no custom pressed-state styling; the checkboxes', Done button's, and Spacing controls' click/press feedback is AppKit's own default `NSControl`/`NSButton` rendering. |
| Disabled | Not implemented in source: `isEnabled` is never read or set on any control in this file — the Done button, the four checkboxes, and both `SpacingControl` instances are always interactive whenever the sheet is on screen. |
| Focused | Not styled beyond AppKit's native focus ring, except for the explicit key-view loop this file stitches between the two Spacing controls (**closes-tab-loop-between-spacing-controls**); the Done button and the four checkboxes use AppKit's default key-view-loop placement, which this file does not override. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading indicator appears anywhere in this file. |
