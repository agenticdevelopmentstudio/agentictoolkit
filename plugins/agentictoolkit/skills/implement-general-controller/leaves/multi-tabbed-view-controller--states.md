<!-- leaf: implement-general-controller/multi-tabbed-view-controller--states · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController

## States

| State | Appearance change |
|-------|------------------|
| Default (unselected tab) | `TabButton` background transparent; label role `.secondaryText`; close icon tint `.tertiaryText`. |
| Selected (active tab / group) | `TabButton` background fills with `.selection`; label role `.selectionText`; close icon tint `.selectionText`; `accessibilityValue` reports `true`; a `.viewController` item's `isHighlighted` is set `true`. |
| Stacked (vertical edge, `.viewController` items only) | An item recedes visually behind items nearer the selection: its `stackDepth` (index distance from the selected item) is reported to any hosted `TabBarStackedItem`, and its `-16pt`-overlapping card is drawn and hit-tested beneath nearer items. `.title` items receive the overlap spacing but not the depth reordering — see Design Decisions. |
| Edge hidden | The edge's bar is set `isHidden = true` and dropped from the edge layout constraints entirely; its tabs are preserved but not drawn. |
| Pressed | Not applicable: a click resolves directly to selection or to the close action in the same `mouseDown` handler; there is no separate, visually distinct pressed/mouse-down appearance before that resolution. |
| Disabled | Not applicable: no tab, button, or bar has a disabled appearance in source; a tab that exists is always selectable, and an edge that is off is hidden entirely rather than shown disabled. |
| Focused | Not applicable: `TabButton` and `TabItemHostView` are plain `NSView` subclasses with no first-responder/focus-ring appearance defined in source (see the Accessibility keyboard-navigation gap). |
| Loading | Not applicable: every tab operation (add, remove, move, rename, select) is synchronous; source defines no loading/pending indicator. |
