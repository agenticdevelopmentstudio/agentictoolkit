<!-- leaf: implement-general-controller/topic-list-view-controller--test-vectors · source: topic-list-view-controller.md -->

# TopicListViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| topic-list-001 | group-items-by-section | `setSections` with two sections, each holding two items, in a given order | The outline's rows, top to bottom, are exactly those items in the given section/item order |
| topic-list-002 | header-row-for-titled-section | A section with `title: "Recents"` and one item | A group header row reading "Recents" appears above that item's row |
| topic-list-003 | omit-header-for-untitled-section | A section with `title: nil` and two items | No group header row appears; only the two item rows are shown |
| topic-list-004 | flat-row-hierarchy, hide-disclosure-controls | Any populated outline | `isItemExpandable` returns `false` for every node and `shouldShowOutlineCellForItem` returns `false` for every item, so no row shows a disclosure triangle |
| topic-list-005 | hide-outline-column-header | Inspect `outlineView` after `loadView` | `outlineView.headerView == nil` |
| topic-list-006 | header-rows-not-selectable | Click, or send `AXPress` to, a group header row | `shouldSelectItem` returns `false`; the row does not become selected |
| topic-list-007 | disabled-item-selectability | An item with `isDisabled == true`; select it by click | The row becomes selected and `onSelect` is invoked with that item, identically to an enabled item |
| topic-list-008 | mute-disabled-item-appearance | Two items, one `isDisabled == true`, one `isDisabled == false` | The disabled row's label/icon use `tertiaryTextColor`; the enabled row's use `primaryTextColor`/`accentColor` |
| topic-list-009 | render-item-without-icon-when-nil | An item constructed with `icon: nil` | Its row's `imageView.image == nil`; no placeholder or broken image appears |
| topic-list-010 | user-selection-callback | User clicks an unselected item row | `onSelect` is invoked exactly once with that item |
| topic-list-011 | suppress-onselect-on-programmatic-selection | Call `selectItem(withId:)` for an unselected, present id | The row becomes selected but `onSelect` is NOT invoked |
| topic-list-012 | select-item-by-id, missing-id-selection | Two items with ids "a" and "b"; call `selectItem(withId: "b")`, then `selectItem(withId: "z")` | First call selects "b"'s row; second call leaves "b" selected (no change, no crash) |
| topic-list-013 | noop-select-already-selected-id | Row for id "b" is already selected; call `selectItem(withId: "b")` again | `selectRowIndexes` is not called again; selection and `onSelect` are unaffected |
| topic-list-014 | restore-selection-by-id-after-resection | Item "b" selected; call `setSections` with a new section list that still contains an item with id "b" | After reload, the row for id "b" is selected again, with no `onSelect` firing for the transient deselection |
| topic-list-015 | restore-selection-across-theme-change | A row is selected; the active theme changes | After `applyTheme(_:)` runs, the same row is still selected, with no spurious `onSelect(nil)` |
| topic-list-016 | stable-row-node-identity | Call `setSections` once, then call `selectItem(withId:)` for an item present since that call | `outlineView.row(forItem:)` resolves to a valid (non -1) row for that item |
| topic-list-017 | hide-header-when-title-and-accessory-empty | `setTitle(nil)` and no header accessory view set | `headerView.isHidden == true` |
| topic-list-018 | hide-footer-when-unset | `setFooterView(nil)` | `footerContainer.isHidden == true` |
| topic-list-019 | header-accessory-below-title | `setTitle("Panels")` and `setHeaderAccessoryView(searchField)` | The header shows the title label above `searchField`, both spanning the header's width |
| topic-list-020 | footer-spans-sidebar-width | `setFooterView(actionsBar)` | `actionsBar`'s leading/trailing anchors equal `footerContainer`'s; it visually spans the sidebar |
| topic-list-021 | content-below-titlebar-safe-area | Host the controller's view in a window whose content extends under the titlebar | `contentStack`'s top sits at the safe-area inset, not the raw top of the view, so the titlebar does not overlap the list |
| topic-list-022 | preferred-width | One item titled "A very long item title" and no title/footer/accessory | `preferredWidth()` returns exactly `itemChromeWidth + renderedWidth("A very long item title", itemFont) + outlineChromePadding (64)` |
| topic-list-023 | item-accessibility-id-from-title | An item with `id: "row-7"`, `title: "Appearance"` | The row label's accessibility identifier is `"topic-list.item.appearance"`, not `"topic-list.item.row-7"` |
| topic-list-024 | ax-press-selection | Send `accessibilityPerformPress()` to an item row's label | The press selects the row and returns `true` |
| topic-list-024b | ax-press-selection | Install a delegate override where `shouldSelectItem` returns `false`; send `accessibilityPerformPress()` to an item row's label | `accessibilityPerformPress()` returns `false`; the row does not become selected |
| topic-list-025 | repaint-on-theme-change | Active theme changes from light to dark | Root view, `contentStack`, `headerView`, `footerContainer` backgrounds, title label font/color, and outline/scroll backgrounds all update to the new palette's values |
| topic-list-026 | single-column-fills-width | Enclosing split view widens the sidebar by 40pt | The outline's single column widens by the same amount on the next layout pass; no row clips its label |
| topic-list-027 | overlay-autohide-scroller | Inspect `scrollView` after `loadView` | `scrollView.scrollerStyle == .overlay` and `scrollView.autohidesScrollers == true` |
| topic-list-028 | automatic-outline-style | Inspect `outlineView.style` after `loadView` | `outlineView.style == .automatic` |
