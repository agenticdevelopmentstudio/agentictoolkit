<!-- leaf: implement-general-controller/topic-list-view-controller--part-3 · source: topic-list-view-controller.md -->

# TopicListViewController — continued (part 3)

## Platform Notes

- **SwiftUI**: Use a `List(selection: $selectedID)` built from the same
  `TopicListSection`/`TopicListItem` model, with `Section(header: Text(title))`
  wherever a section's title is non-nil (mirroring
  **header-row-for-titled-section** / **omit-header-for-untitled-section**),
  and a plain, unsectioned `ForEach` when it is nil. Render a disabled row's
  label and `Label` icon with `.foregroundStyle(.tertiary)` while still
  leaving the row tappable/selectable (mirroring
  **disabled-item-selectability** — do not use SwiftUI's `.disabled()`
  modifier, since that would also block selection, unlike the source
  behavior). Compose the optional title/accessory/footer as sibling views
  above and below the `List` in a `VStack`, collapsing each with
  `if let` rather than SwiftUI's `.hidden()` (which still reserves layout
  space), mirroring the zero-height collapse behavior of `isHidden` on a
  `NSStackView` arranged subview. Read the row's rendered text width with
  `(text as NSString).size(withAttributes:)` if a content-driven sidebar
  width equivalent to `preferredWidth()` is needed.
- **Compose**: Build the outline as a `LazyColumn` with `stickyHeader` items
  for each section whose title is non-nil, and plain items otherwise. Style
  a disabled item's `Text`/`Icon` with `MaterialTheme.colorScheme.onSurfaceVariant`
  (or `LocalContentColor.current.copy(alpha = …)`) while leaving its
  `Modifier.clickable` active, mirroring **disabled-item-selectability**
  (Compose's built-in `enabled = false` on `clickable` would, like SwiftUI's
  `.disabled()`, block the click entirely — do not use it here; `contentColorFor`
  is also the wrong tool, since it returns the content color paired with a
  given background, not a muted tone). Wrap the whole sidebar
  column in a `Surface` whose `color` is read from the active
  `MaterialTheme.colorScheme` so it repaints on theme change, mirroring
  **repaint-on-theme-change**. Compose an optional title/accessory header
  and footer as sibling composables that emit nothing (`if (condition) { … }`)
  when unset, rather than an `AnimatedVisibility` that would animate a
  collapse this component never animates.
- **React/Web**: Render the sidebar as a `<nav>` containing a single
  `<ul role="listbox">` for the whole list, mirroring **flat-row-hierarchy**'s
  single-outline model — never one `listbox` per section, which would split
  keyboard navigation and single selection across sections. Wrap each titled
  section's rows in an `<li role="group" aria-labelledby="section-id">`
  containing an `<h3 id="section-id">` for the title followed by that
  section's `<li role="option" aria-selected>` rows; an untitled section's
  rows sit directly in the listbox with no wrapping `group`. Style a disabled item with a muted text/icon color
  class while still attaching its `onClick`/keyboard handlers, mirroring
  **disabled-item-selectability** (do not set the native `disabled`
  attribute, which — like SwiftUI's `.disabled()` — would remove it from the
  tab order and block activation). Give each item's element an `id` or
  `data-testid` derived from a slugified title, mirroring
  **item-accessibility-id-from-title**, and drive CSS custom properties
  (`--surface-bg`, `--text-primary`, etc.) from the active theme so a theme
  switch repaints them, mirroring **repaint-on-theme-change**. Collapse an
  unset header/footer with `display: none` (which removes layout space, like
  AppKit's `isHidden` on a stack view's arranged subview) rather than
  `visibility: hidden`.
- **AppKit/UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/TopicListViewController.swift`
  as a `@MainActor`, `open` `NSViewController` that builds its entire view
  hierarchy by hand in `loadView()` — a single-column `NSOutlineView`
  (`ColumnFillingOutlineView`) inside an `NSScrollView`, stacked with an
  optional title/accessory header and an optional client footer in a
  vertical `NSStackView`. It is its own `NSOutlineViewDataSource`/
  `NSOutlineViewDelegate`, with row appearance and theming driven by
  `SemanticPalette` via `ThemePaletteObserver` and `ThemedTableRowView`
  (both defined in the vendored `AgenticDeveloperToolkitUI` framework this
  target re-exports). There is no UIKit code path in source; a UIKit port
  would replace `NSOutlineView`/`NSScrollView` with a `UITableView` (a flat
  list needs no `UICollectionView` compositional layout), use
  `tableView(_:titleForHeaderInSection:)` for group headers, and would need
  to grow the AppKit `.default` row height — well under 44pt — to at least a
  44pt touch target, since UIKit has no keyboard-first,
  `NSOutlineView`-style default row navigation to fall back on for
  pointer-free selection.
- **WinUI 3**: Build the sidebar as a
  `NavigationView` in `Left`/`LeftCompact` display mode, or — if
  `NavigationView`'s chrome (back button, pane toggle) is unwanted — a plain
  `ListView` bound to a flattened collection of `TopicListSection`/
  `TopicListItem` view models, grouped with `CollectionViewSource.IsSourceGrouped
  = true` and a `GroupStyle` whose `HeaderTemplate` renders the section
  title only when it is non-empty (mirroring
  **header-row-for-titled-section**/**omit-header-for-untitled-section** —
  WinUI's `CollectionViewSource` grouping is the direct analog of
  `buildRootNodes(from:)`'s header/item interleaving). Bind each
  `ListViewItem`'s `IsEnabled` to nothing (leave it `true`) and instead bind
  its `Foreground`/icon `Fill` to a converter that returns a muted
  `SolidColorBrush` when the item's `IsDisabled` is set, mirroring
  **disabled-item-selectability** — WinUI's `IsEnabled = false`
  would, like SwiftUI's `.disabled()` and Compose's `enabled = false`,
  also block selection, which source does not do. Use
  `ListView.SelectionMode="Single"` with `SelectedItem`/`SelectionChanged`
  as the analog of `onSelect`, and select an item by identity
  (`ListView.SelectedItem = viewModels.First(vm => vm.Id == id)`) as the
  analog of `selectItem(withId:)`, no-oping when no match is found
  (mirroring **missing-id-selection**). Give the optional title a
  `TextBlock` and the optional accessory/footer `ContentPresenter`s bound to
  nullable view-model properties, collapsing each to `Visibility.Collapsed`
  (which, like AppKit's `isHidden` on a stack panel child, removes it from
  layout — not `Opacity="0"`) when unset, mirroring
  **hide-header-when-title-and-accessory-empty**/**hide-footer-when-unset**.
  Re-theme the `NavigationView`/`ListView`'s brushes from
  `Application.Current.Resources` `ThemeResource`s (or re-apply them in an
  `ActualThemeChanged` handler) so a theme switch repaints the sidebar,
  mirroring **repaint-on-theme-change**. Set `AutomationProperties.AutomationId`
  on each `ListViewItem` to the slugified title (mirroring
  **item-accessibility-id-from-title**) while `AutomationProperties.Name`
  carries the plain title as the item's accessible name, since WinUI's UI
  Automation tree, like AppKit's, exposes the item's own element rather than
  a synthesized row wrapper as the natural place to attach an identifier and
  a name.

## Design Decisions

- Decision: Cache `TopicListNode` instances in `rootNodesCache` across
  accesses, rebuilding them only inside `setSections(_:)`, instead of
  recomputing `rootNodes` fresh on every access.
  Rationale: Per the property's doc comment, `NSOutlineView` identifies
  items by reference; rebuilding on every access (the prior behavior) made
  `outlineView.row(forItem:)` always return -1, which silently broke
  `selectItem(withId:)`.
  Approved: pending
- Decision: Let `shouldSelectItem` and `TopicListItemLabel.accessibilityPerformPress()`
  gate selection only on node kind (`.item` vs. `.header`), never on
  `TopicListItem.isDisabled`.
  Rationale: Source draws no such distinction — a "coming soon" placeholder
  item stays reachable and selectable by mouse, keyboard, and assistive
  technology alike; only its rendered appearance is muted. A consumer that
  wants a disabled item to be truly inert must check `isDisabled` itself
  inside its `onSelect` handler.
  Approved: pending
- Decision: Track suppression of `onSelect` with an integer nesting counter
  (`selectionSuppressionDepth`), not a boolean flag.
  Rationale: Per the property's doc comment, a single suppression scope must
  absorb both the notification `reloadData()` posts when it drops the
  selection and the one the following re-selection posts — AppKit delivers
  both synchronously within the scope — so the counter, not a one-shot
  flag, is what keeps a single scope correct.
  Approved: pending
- Decision: Override `layout()` on `ColumnFillingOutlineView` to call
  `sizeLastColumnToFit()` after `super.layout()`, rather than setting the
  column's `width` directly.
  Rationale: Per the class's doc comment, setting `column.width` directly
  from `layout()` re-enters `NSTableView.tile`/`setFrameSize` and throws;
  `sizeLastColumnToFit()` after `super.layout()` is the safe primitive.
  Approved: pending
- Decision: Set `outlineView.style = .automatic` rather than the more
  visually apt `.sourceList`.
  Rationale: Per the source comment, `.sourceList` forces an internal
  `NSVisualEffectView` dark material regardless of `NSApp.appearance`;
  `.automatic` lets the outline's background follow this component's own
  theme instead.
  Approved: pending
- Decision: Pin `contentStack`'s top anchor to the root view's
  `safeAreaLayoutGuide.topAnchor` instead of its plain `topAnchor`.
  Rationale: Per the source comment, in a window whose content runs the
  full height (so the sidebar's fill reaches up behind the window buttons)
  the titlebar overlaps this view, and the list must begin below it;
  everywhere else that inset is zero and nothing moves.
  Approved: pending
- Decision: Put the accessibility identifier and `AXPress` handling on the
  item's `NSTextField` label (`TopicListItemLabel`), not on
  `NSTableCellView` or `NSTableRowView`.
  Rationale: Per the source comment, AppKit synthesizes a table's `AXRow`
  and `AXCell` elements itself; an identifier or action attached to
  `NSTableRowView`/`NSTableCellView` never reaches the accessibility tree,
  so the label is the row's one real element in it.
  Approved: pending
- Decision: Derive an item row's accessibility identifier from its `title`
  (slugified), not from its `id`.
  Rationale: Per the source comment, `id` is the caller's private key — in
  the settings window it is a panel's index in an array — so it names
  whichever row a given index currently holds and renames itself whenever a
  row is inserted above it. The title is what the row is called on screen,
  which is what someone driving the list actually knows about it.
  Approved: pending
