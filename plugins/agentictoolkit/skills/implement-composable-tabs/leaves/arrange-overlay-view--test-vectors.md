<!-- leaf: implement-composable-tabs/arrange-overlay-view--test-vectors · source: composable-tabs-arrange-overlay-view.md -->

# ComposableTabsArrangeOverlayView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-arrange-overlay-001 | dims-content-with-scrim | Inspect `layer?.backgroundColor` immediately after construction | Equals `SemanticPalette.nsColor(.windowBackground).withAlphaComponent(0.72).cgColor` for the active palette |
| composable-tabs-arrange-overlay-002 | paints-toolbar-surface | Inspect the toolbar's layer after construction | `cornerRadius == 8`, `borderWidth == 1`, `backgroundColor == elevatedSurface.cgColor`, `borderColor == border.cgColor` |
| composable-tabs-arrange-overlay-003 | applies-theme-immediately-and-on-change | Construct the view under theme A, then switch the active theme to B | Colors match theme A's palette immediately after construction, and update to match theme B's palette after the switch, with no further action taken |
| composable-tabs-arrange-overlay-004 | centers-toolbar-column | Inspect the column's constraints after construction | `centerXAnchor`/`centerYAnchor` are each constrained equal to the view's own center; the label-to-toolbar spacing in the column is 10pt |
| composable-tabs-arrange-overlay-005 | caps-name-label-width | Inspect `nameLabel`'s width constraint after construction | A `lessThanOrEqualTo` constraint against the view's `widthAnchor` with constant `-16` exists |
| composable-tabs-arrange-overlay-006 | truncates-name-label-tail | Set `paneName` to a string wider than the label's constrained width | `nameLabel.lineBreakMode == .byTruncatingTail` and `nameLabel.alignment == .center` |
| composable-tabs-arrange-overlay-007 | toolbar-can-overhang-narrow-pane | Inspect the column's constraints against the view for leading/trailing/top/bottom pins | No such constraint exists; only centerX/centerY constraints tie the column to the view |
| composable-tabs-arrange-overlay-008 | updates-pane-name-on-assignment | Set `paneName = "Editor"` | `nameLabel.stringValue == "Editor"` immediately after the assignment returns |
| composable-tabs-arrange-overlay-009 | exposes-add-button-as-anchor-view | Read `addButtonView` | Returns the same `NSView` instance used as the Add button |
| composable-tabs-arrange-overlay-010 | invokes-add-callback-on-tap | Set `onAdd` to a closure that increments a counter, then click the Add button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-011 | invokes-add-callback-on-tap | Leave `onAdd` as `nil`, then click the (enabled) Add button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-012 | invokes-remove-callback-on-tap | Set `onRemove` to a closure that increments a counter, then click the Remove button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-013 | invokes-remove-callback-on-tap | Leave `onRemove` as `nil`, then click the (enabled) Remove button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-014 | invokes-done-callback-on-tap | Set `onDone` to a closure that increments a counter, then click the Done button | Counter increments by exactly 1 |
| composable-tabs-arrange-overlay-015 | invokes-done-callback-on-tap | Leave `onDone` as `nil`, then click the Done button | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-016 | invokes-move-callback-on-selection | Set `onMove` to a closure capturing its argument; `availableDirections` returns `{.left}`; choose the "Left" Move item | Closure is invoked exactly once with `.left` |
| composable-tabs-arrange-overlay-017 | invokes-move-callback-on-selection | Leave `onMove` as `nil`; choose an enabled Move item | No crash and no observable effect occurs |
| composable-tabs-arrange-overlay-018 | add-button-enablement-tracks-can-add | Set `canAdd = { false }`, then call `refreshAvailability()` | `addButton.isEnabled == false` |
| composable-tabs-arrange-overlay-019 | remove-button-enablement-tracks-can-remove | Set `canRemove = { false }`, then call `refreshAvailability()` | `removeButton.isEnabled == false` |
| composable-tabs-arrange-overlay-020 | move-menu-rebuilt-on-refresh | Call `refreshAvailability()` twice in a row | The Move menu's first item is still its original title item, followed by exactly 4 items, in both cases, in Left/Right/Up/Down order |
| composable-tabs-arrange-overlay-021 | move-item-enablement-tracks-available-directions | Set `availableDirections = { [.left, .above] }`, then call `refreshAvailability()` | The "Left" and "Up" items are enabled; "Right" and "Down" are disabled |
| composable-tabs-arrange-overlay-022 | move-button-enablement-tracks-items | Set `availableDirections = { [] }`, then call `refreshAvailability()` | `moveButton.isEnabled == false` |
| composable-tabs-arrange-overlay-023 | move-button-enablement-tracks-items | Set `availableDirections = { [.right] }`, then call `refreshAvailability()` | `moveButton.isEnabled == true` |
| composable-tabs-arrange-overlay-024 | move-items-icons-match-direction | Inspect the "Up" Move item after `refreshAvailability()` | Its `image` is the `arrow.up` system symbol and its `accessibilityDescription` equals "Up" |
| composable-tabs-arrange-overlay-025 | toolbar-buttons-show-icon-and-label | Inspect the Remove button after construction | `image` is the `minus` system symbol, `accessibilityDescription == "Remove"`, `imagePosition == .imageLeading` |
| composable-tabs-arrange-overlay-026 | refresh-is-caller-driven | Change what `canAdd` returns without calling `refreshAvailability()` | `addButton.isEnabled` remains at its previously computed value |
| composable-tabs-arrange-overlay-027 | computes-initial-availability-at-construction | Construct the view with `canAdd = { false }` and never call `refreshAvailability()` again | `addButton.isEnabled == false` immediately after construction |
| composable-tabs-arrange-overlay-028 | root-and-controls-carry-accessibility-identifiers | Inspect `accessibilityIdentifier()` on the root view and each control after construction | Equal `composable-tabs.arrange.scrim`, `.add`, `.remove`, `.move`, `.done`, and `.pane-name` respectively |
| composable-tabs-arrange-overlay-029 | move-items-carry-prefixed-identifiers | Call `refreshAvailability()` (it takes no parameters) after construction | The "Left" item's identifier is `composable-tabs.arrange.move.left`, produced by `refreshAvailability()`'s internal call to `moveMenu.makeItems(accessibilityPrefix: "composable-tabs.arrange.move")` |
| composable-tabs-arrange-overlay-030 | coder-initialization-unsupported | Attempt `ComposableTabsArrangeOverlayView(coder:)` | The call traps with a fatal error; no instance is returned |
| composable-tabs-arrange-overlay-031 | done-button-has-no-key-equivalent | Inspect `doneButton.keyEquivalent` after construction | Equals `""` |
| composable-tabs-arrange-overlay-032 | scrim-blocks-clicks-to-content | With the overlay installed over a pane's content view, click a point over the scrim but off any button | The content view underneath receives no mouse or key event for that click |
| composable-tabs-arrange-overlay-033 | scrim-click-still-reaches-pane-selection | With the overlay installed over an unselected pane, click a point over the scrim but off any button | The pane becomes the selected pane, via the click reaching `ComposableTabsPaneBackgroundView`'s selection handling through the responder chain |
