<!-- leaf: implement-general-view-2/tab-bar-view--states · source: tab-bar-view.md -->

# TabBarView

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected) | `TabButton` background transparent; label role `.secondaryText`; close icon tint `.tertiaryText`. |
| Selected | `TabButton` background fills with `.selection`; label role `.selectionText`; close icon tint `.selectionText`; `accessibilityValue` reports `true`; a hosted `TabBarHostedItem`'s `isHighlighted` is set `true`. |
| Stacked (vertical bar, `.viewController` items only) | An item recedes behind items nearer the selection: its `stackDepth` (index distance from the selected item) is reported to any hosted `TabBarStackedItem`, and its `-16pt`-overlapping wrapper view is drawn and hit-tested beneath nearer items (see the Edge Cases entry on title tabs not being depth-reordered). |
| Pressed | Not applicable: a mouse-down resolves directly to selection or to the close action inside the same `mouseDown` handler; there is no separate, visually distinct pressed appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar exposes a disabled appearance in `TabBarView.swift`; any item present in `items` is always selectable. |
| Focused | Not applicable: `TabButton` and `TabItemHostView` are plain `NSView` subclasses with no first-responder or focus-ring appearance defined in source (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every operation (`setItems`, `setSelected`, `renameItem`, `rebuildButtons`, `applyStackOrder`, `updateThickness`) is synchronous; source defines no loading/pending indicator. |
