<!-- leaf: implement-settings/panel-list-view-controller--states · source: settings-panel-list-view-controller.md -->

# PanelListViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | Row shows `descriptor.title`/`descriptor.icon` with `primaryTextColor`/`accentColor`, unselected. |
| Selected | Row highlight comes entirely from `NSOutlineView`'s native selection rendering (`ThemedTableRowView`, inherited); this file restyles nothing further on selection. |
| Disabled (panel) | `descriptor.isDisabled == true`: text and icon tint switch to `tertiaryTextColor` (inherited from `TopicListViewController`); the row remains selectable — `outlineView(_:shouldSelectItem:)` does not gate on `isDisabled`, so this file (and its ancestor) let a disabled row be clicked and selected like any other. |
| Filtered out | A panel `searchQuery` excludes contributes no row at all — it is absent from the sidebar entirely, not shown greyed out or struck through. |
| Pressed | Not applicable: an outline row has no separate pressed/hover visual distinct from selection; this file adds no press styling of its own. |
| Focused | Not customized: standard `NSOutlineView` keyboard-focus ring, unchanged by this file or its ancestor. |
| Loading | Not applicable: `setPanels(_:)` and every rebuild it triggers are synchronous; no asynchronous load or spinner exists anywhere in this file. |
