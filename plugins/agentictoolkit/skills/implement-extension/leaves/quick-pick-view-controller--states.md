<!-- leaf: implement-extension/quick-pick-view-controller--states · source: extension-quick-pick-view-controller.md -->

# ExtensionQuickPickViewController

## States

| State | Appearance change |
|-------|------------------|
| Default | Title label (if any) shown; search field shows `model.request.placeHolder` (or empty); table lists `model.visibleIndices`; the highlighted row, if any, is selected via `syncSelection()`. |
| Pressed | Single-select: clicking a row highlights it, syncs selection, and immediately calls `onAccept` (accept-on-click). Multi-select: clicking a row or its checkbox toggles that row's check and reloads only that row; the panel stays open. Either mode: a click on a separator or out-of-range row is a no-op. |
| Disabled | Not applicable: `isEnabled` is never set on any control in `ExtensionQuickPickViewController.swift`; every view is always enabled. |
| Focused | The search field holds first responder from the moment `focusSearchField()` is called (invoked externally by `ExtensionPickerWindowController.takeInitialFocus()`) — see **search-field-focus**; the table refuses first responder (`refusesFirstResponder = true`) and is never itself focused — the highlighted row is instead shown through table selection plus `ThemedTableRowView`'s own rounded selection fill (`.selection` role, 4pt corner radius, inset 2pt/1pt), not a native focus ring. |
| Loading | Not applicable: no asynchronous operation, spinner, or loading flag appears anywhere in `ExtensionQuickPickViewController.swift`; the model is built synchronously from the request in `init`. |
