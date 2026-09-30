<!-- leaf: implement-file/browser-view-controller--states · source: file-browser-view-controller.md -->

# File Browser View Controller

## States

| State | Appearance change |
|-------|------------------|
| Default | Tree, separator, and footer laid out; add button enabled; remove button's enabled state follows `selection.selectedRoot` (see Disabled). |
| Pressed | Not applicable: the add/remove buttons are stock `NSButton`s with `bezelStyle: .accessoryBar` and no custom pressed-state styling in source — AppKit supplies the default bezel press feedback. |
| Disabled | Remove button is disabled (`isEnabled = false`) whenever `selection.selectedRoot` is `nil` or is not a removable (user-added) root; its tooltip reads "Select an added directory to remove it". |
| Focused | Not applicable: this file sets no custom focus-ring appearance on the tree, the buttons, or the container; whatever focus ring AppKit draws for a standard `NSButton`/hosted `NSOutlineView` is unmodified here. |
| Loading | Before the view's first `viewWillAppear`, `hasLoaded` is `false` and no manager has been asked to scan (`loadInitial()` not yet called); after the first appearance, `hasLoaded` becomes `true` and every current manager has had `loadInitial()` called once. |
| Watching | While the view is on screen — started at `viewWillAppear`, stopped at whichever of `viewDidDisappear` or `paneContentWillBeDiscarded` comes first — every current manager has `startWatching()` active; once stopped, every manager has `stopWatching()` called. |
