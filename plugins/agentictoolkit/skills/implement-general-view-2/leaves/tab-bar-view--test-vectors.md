<!-- leaf: implement-general-view-2/tab-bar-view--test-vectors · source: tab-bar-view.md -->

# TabBarView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| tab-bar-view-001 | thickness-floor-by-edge | `TabBarView.preferredThickness(for: .top)` / `.left` | Returns `28`; `.left` returns `140` |
| tab-bar-view-002 | orientation-follows-edge | `TabBarView(edge: .right)` constructed | Its arranged content lays out vertically (top-to-bottom) |
| tab-bar-view-003 | alignment-favors-workspace-side | `TabBarView(edge: .top)` constructed | Items align to the bar's bottom edge |
| tab-bar-view-004 | item-spacing-by-orientation | `TabBarView(edge: .left)` constructed | The gap between adjacent items is `-16pt` (items overlap) |
| tab-bar-view-005 | start-inset-defaults-to-end-padding | New `TabBarView` | `startInset == 8`; the first item begins `8pt` from the bar's start |
| tab-bar-view-006 | host-may-override-start-inset | `bar.startInset = 20` | The first item now begins `20pt` from the bar's start |
| tab-bar-view-007 | outer-padding-on-window-side-only | `TabBarView(edge: .bottom)` | Items sit `6pt` from the bar's outer (window) edge, flush (`0pt`) against the workspace edge, and `8pt` from each end along the bar's length |
| tab-bar-view-008 | bar-fills-perpendicular-and-pins-length | `TabBarView(edge: .top)` laid out in a 300pt-wide superview | The bar's arranged content spans the bar's own leading/trailing edges; the bar's height constraint constant `== 28` at rest |
| tab-bar-view-009 | vertical-bar-packs-from-top | `TabBarView(edge: .left)` with 2 short items in a tall superview | The bar's arranged content is shorter than the bar's own height; the gap below is empty, not stretched |
| tab-bar-view-010 | bar-fills-window-background | Palette changes from theme A to theme B | `layer?.backgroundColor` updates to theme B's `.windowBackground` color |
| tab-bar-view-011 | set-items-triggers-rebuild | `setItems([item], selectedID: item.id)` | The bar renders exactly one item, matching the new item |
| tab-bar-view-012 | set-selected-restyles-and-reorders | Two `.title` items; call `setSelected(itemB.id)` | The tab for `itemB` is highlighted; the tab for `itemA` is not |
| tab-bar-view-013 | stack-depth-by-distance-from-selection | 3 `.viewController` items at indices 0,1,2; select index 0 | Depths reported to `TabBarStackedItem` are `0, 1, 2` |
| tab-bar-view-014 | stack-depth-by-distance-from-selection | Same 3 items; `selectedID == nil` | Every item's reported depth is `1` |
| tab-bar-view-015 | vertical-edge-cards-overlap-and-order-by-distance | `.left` bar, 3 hosted items, middle one selected | The middle item's wrapper view is above both neighbors in `subviews` (frontmost, topmost hit-tested) |
| tab-bar-view-016 | rename-title-item | `renameItem(id: tab.id, title: "New")` on an existing `.title` tab | `items` entry's payload is `.title("New")`; `buttons[tab.id]?.title == "New"` |
| tab-bar-view-017 | rename-title-item | `renameItem(id: unknownID, title: "X")` | No crash; `items` and `buttons` are unchanged |
| tab-bar-view-018 | rebuild-clears-and-repopulates | `setItems([a, b], ...)` then `setItems([c], ...)` | The bar renders exactly one item, `c`'s; no rendered element for `a` or `b` remains |
| tab-bar-view-019 | cross-edge-move-preserves-foreign-controller | A hosted controller's view is reparented onto a different bar's wrapper, then this bar is given new items | The controller's `parent` and view are unaffected by this bar's reconciliation |
| tab-bar-view-020 | rebuild-drops-stale-hosted-controllers | A `.viewController` item is removed from `items` and the bar re-renders | The removed item's controller no longer receives highlight or stack-depth updates from the bar |
| tab-bar-view-021 | title-item-becomes-button | `.title` item on a `.left` bar | The created `TabButton` has active constraints pinning its leading/trailing edges to the bar's interior |
| tab-bar-view-022 | title-item-becomes-button | `.title` item on a `.top` bar | The created `TabButton` has no cross-axis pin installed by `TabBarView` (relies on the bar's own alignment) |
| tab-bar-view-023 | viewcontroller-item-becomes-hosted-view | `.viewController` item on a `.top` bar | The wrapping `TabItemHostView` has active top/bottom constraints pinning it to the bar's interior |
| tab-bar-view-024 | thickness-grows-with-hosted-content | `.left` bar hosts an item with `preferredContentSize.width == 200` | The bar's thickness (width) is `206` (`200 + 6`, above the `140` floor) |
| tab-bar-view-025 | thickness-grows-with-hosted-content | `.left` bar with no hosted items | The bar's thickness (width) is `140` (the floor) |
| tab-bar-view-026 | host-view-fills-hosted-content | `TabItemHostView(id:, content:)` constructed | `content`'s top/leading/trailing/bottom equal the wrapper's own edges |
| tab-bar-view-027 | host-view-click-selects | `mouseDown` on a point inside the wrapper but outside any interior control | `onSelect(id)` is invoked |
| tab-bar-view-028 | close-icon-hit-routes-to-close | `mouseDown` at a point inside `closeButton.frame` | `onClose(id)` fires; `onSelect` is not invoked by this `mouseDown` |
| tab-bar-view-029 | close-icon-hit-routes-to-close | `mouseDown` at a point outside `closeButton.frame` | `onSelect(id)` is invoked; close is not triggered |
| tab-bar-view-030 | accessibility-press-always-selects | `accessibilityPerformPress()` invoked while a VoiceOver cursor is conceptually "over" the close child | `onSelect(id)` is invoked (never the close action); returns `true` |
| tab-bar-view-031 | tab-button-is-accessible-element | `TabButton(id:, title: "Notes")` constructed, `isHighlighted` left at its default `false` | `accessibilityElement == true`; `accessibilityRole == .button`; `accessibilityTitle == "Notes"`; `accessibilityValue == false` |
| tab-bar-view-032 | tab-button-title-updates-accessibility | `button.title = "Renamed"` | `titleLabel.stringValue == "Renamed"`; `accessibilityTitle == "Renamed"` |
| tab-bar-view-033 | tab-button-highlight-updates-accessibility-value | `button.isHighlighted = true` | `accessibilityValue == true`; the tab restyles to its selected appearance (see vectors 036-037) |
| tab-bar-view-034 | close-button-republished-as-sole-child | `button.accessibilityChildren()` called | Returns an array containing exactly `closeButton` |
| tab-bar-view-035 | close-button-carries-per-tab-identifier | `TabButton(id: uuid, title:)` constructed | `button.accessibilityIdentifier() == "tab-bar.select.\(uuid)"`; `closeButton.accessibilityIdentifier() == "tab-bar.close.\(uuid)"` |
| tab-bar-view-036 | selecting-a-tab-restyles-its-button | `button.isHighlighted = true` | The tab's background fills with the `.selection` color; its title's color role becomes `.selectionText`; its close icon's tint becomes `.selectionText` |
| tab-bar-view-037 | selecting-a-tab-restyles-its-button | `button.isHighlighted = false` | The tab's background becomes clear; its title's color role becomes `.secondaryText`; its close icon's tint becomes `.tertiaryText` |
| tab-bar-view-038 | declares-reorder-callback | `let bar = TabBarView(edge: .top)` | `bar.onReorder` is a settable, externally accessible property (compiles and assigns) |
| tab-bar-view-039 | rejects-coder-initializer | Construct `TabBarView(coder:)` with any `NSCoder` | Execution traps via `fatalError` with message `init(coder:) has not been implemented` |
| tab-bar-view-040 | confines-to-main-actor | Attempt to construct or mutate a `TabBarView` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| tab-bar-view-041 | vertical-edge-cards-overlap-and-order-by-distance | `.left` bar, 3 hosted items at indices 0,1,2; index 1 selected | Between the tied depth-1 neighbors (indices 0 and 2), index 0's wrapper view ends up more frontmost than index 2's, per the descending-index tie-break; index 1 (depth 0, selected) is frontmost of all three |
