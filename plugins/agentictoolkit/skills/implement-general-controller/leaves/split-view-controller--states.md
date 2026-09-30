<!-- leaf: implement-general-controller/split-view-controller--states · source: split-view-controller.md -->

# SplitViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | Sidebar and detail `NSSplitViewItem`s added; sidebar non-collapsible; window/detail background painted from the active theme; first panel auto-selected once panels exist. |
| Pressed | Not applicable — this file defines no `NSControl` of its own; the search field is a stock `NSSearchField`, and the divider/rows it hosts belong to `NSSplitView`/`PanelListViewController`. |
| Disabled | Not applicable in this file — a disabled panel row is `PanelListViewController`'s concern (`descriptor.isDisabled`); this file reads no disabled state. |
| Focused | While the sidebar search field holds first responder, Down/Up move the sidebar selection instead of the text caret (**redirects-arrow-keys-to-selection**); every other command types normally. |
| Loading | Not applicable — every operation in this file is synchronous; there is no asynchronous load state. |
| Content-sized sidebar (`contentSizedSidebar == true`) | Sidebar `minimumThickness == maximumThickness`, non-draggable, no autosave name set. |
| Draggable sidebar (`contentSizedSidebar == false`, default) | Sidebar thickness ranges `160`–`360`pt, draggable, `splitView.autosaveName` set to `sidebarAutosaveName`. |
| Sidebar search shown (`showsSidebarSearch == true`) | Search field installed as the sidebar's header accessory during `viewDidLoad`; typing narrows the sidebar and Down/Up steer the highlight. |
| Sidebar search hidden (`showsSidebarSearch == false`, default) | Search field never built; no header accessory installed. |
| Nested split present (≥2 hosted panels are themselves `SplitViewController`s) | Every nested sibling's sidebar is pinned to one shared width; this instance's own detail floor is raised to accommodate the widest nested sibling's sidebar plus its own `detailMinimumThickness`. |
