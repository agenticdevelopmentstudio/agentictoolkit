<!-- leaf: implement-extension/tree-view-controller--states · source: extension-tree-view-controller.md -->

# ExtensionTreeViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: this file draws no custom pressed appearance for a row; clicking selects it via `NSOutlineView`'s own default chrome. |
| Disabled | Not applicable: neither pane nor row has a disabled representation in this file; whether an activated item does anything is entirely the extension's command wiring, not this controller's concern. |
| Focused | Not applicable as a visual state drawn by this file: keyboard focus ring and first-responder chrome are inherited, undrawn `NSOutlineView`/`AppKit` behavior. |
| Loading | Not applicable as a whole-pane state: there is no spinner or full-pane loading indicator anywhere in this file; loading is per-branch — see "Branch unloaded" and "Branch timed out" below. |
| Placeholder | Shown until a data source resolves; drawn by `ExtensionViewPlaceholderViewController`, out of this recipe's scope. |
| Tree shown | The placeholder is replaced by the `NSOutlineView`-backed outline once a data source resolves (`first-resolve-shows-outline`). |
| Message banner visible | Shown, wrapped, above the tree whenever `dataSource.message` is non-nil. |
| Message banner hidden | Hidden, tree pinned to the container's top edge, whenever `dataSource.message` is nil. |
| Branch unloaded | Drawn with zero rows while a load is in flight or has not yet been triggered; its own disclosure triangle still shows if `collapsibleState` is not `.none` (`disclosure-driven-by-declared-state`). |
| Branch timed out | Drawn with zero rows after `childrenBudget` elapses with no answer; stays re-askable rather than being recorded as permanently empty. |
| Row selected | Standard `NSOutlineView` selection highlighting, not drawn by this file; reported to `dataSource.selectionDidChange` unless the change was the controller's own redraw sync. |
| Row expanded/collapsed | Standard `NSOutlineView` disclosure, not drawn by this file; reported via `didExpand`/`didCollapse` unless the change was the controller's own auto-expand or redraw sync. |
