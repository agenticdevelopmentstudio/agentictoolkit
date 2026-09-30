<!-- leaf: implement-general-view-2/log-view--states · source: log-view.md -->

# Log View

## States

| State | Appearance change |
|-------|------------------|
| Default | Rows render per `provider.lines`, styled as described in Appearance. |
| Pressed | Not applicable: no distinct pressed-state styling is defined; whatever mouse-down feedback `NSTableView` supplies for an unselected row before a click resolves is unmodified here. |
| Disabled | Not applicable: the component exposes no enabled/disabled toggle and defines no disabled appearance. |
| Focused | Not applicable: no custom focus-ring appearance is set on the table view or its cells; the system default focus ring is unmodified. |
| Loading | Not applicable: the component has no loading indicator or in-flight state; a provider push is reflected synchronously from the view's perspective. |
| Selected | Row is filled with a 4pt-corner-radius rounded rectangle, inset 2pt/1pt, in the theme's `selection` role color (see `selected-row-uses-theme-selection-color`). |
| Empty | When `provider.lines` is empty, the table shows zero rows; the scroll-to-end operation is a no-op; and, per `empty-table-counts-as-at-bottom`, a subsequent append on a previously empty log follows the tail. |
