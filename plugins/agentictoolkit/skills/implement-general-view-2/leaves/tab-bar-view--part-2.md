<!-- leaf: implement-general-view-2/tab-bar-view--part-2 · source: tab-bar-view.md -->

# TabBarView — continued (part 2)

**Rules** (cite as `implement-general-view-2/tab-bar-view--part-2#<slug>`):

- `thickness-floor-by-edge` MUST
- `orientation-follows-edge` MUST
- `alignment-favors-workspace-side` MUST
- `item-spacing-by-orientation` MUST
- `start-inset-defaults-to-end-padding` MUST
- `host-may-override-start-inset` MAY
- `outer-padding-on-window-side-only` MUST
- `bar-fills-perpendicular-and-pins-length` MUST
- `vertical-bar-packs-from-top` MUST
- `bar-fills-window-background` MUST
- `set-items-triggers-rebuild` MUST
- `set-selected-restyles-and-reorders` MUST
- `stack-depth-by-distance-from-selection` MUST
- `vertical-edge-cards-overlap-and-order-by-distance` MUST
- `rename-title-item` MUST
- `rebuild-clears-and-repopulates` MUST
- `cross-edge-move-preserves-foreign-controller` MUST
- `rebuild-drops-stale-hosted-controllers` MUST
- `title-item-becomes-button` MUST
- `viewcontroller-item-becomes-hosted-view` MUST
- `thickness-grows-with-hosted-content` MUST
- `host-view-fills-hosted-content` MUST
- `host-view-click-selects` MUST
- `close-icon-hit-routes-to-close` MUST
- `accessibility-press-always-selects` MUST
- `tab-button-is-accessible-element` MUST
- `tab-button-title-updates-accessibility` MUST
- `tab-button-highlight-updates-accessibility-value` MUST
- `close-button-republished-as-sole-child` MUST
- `close-button-carries-per-tab-identifier` MUST
- `selecting-a-tab-restyles-its-button` MUST
- `declares-reorder-callback` MUST
- `rejects-coder-initializer` MUST
- `confines-to-main-actor` MUST

## Behavioral Requirements

- **thickness-floor-by-edge**: `TabBarView.preferredThickness(for:)` MUST
  return `28pt` for `.top`/`.bottom` and `140pt` for `.left`/`.right`. These
  are fixed constants with no stated rationale in source beyond a sensible
  default; a port SHOULD treat them as theme-tunable rather than hardcoding
  them verbatim.
- **orientation-follows-edge**: The component MUST lay out its arranged
  content horizontally for a `.top`/`.bottom` bar and vertically for a
  `.left`/`.right` bar.
- **alignment-favors-workspace-side**: The component MUST align its arranged
  content to the side of the bar adjacent to the workspace/content area it
  frames: the bottom for `.top`, the top for `.bottom`, the trailing edge for
  `.left`, and the leading edge for `.right`.
- **item-spacing-by-orientation**: The component MUST set the gap between
  arranged items to `4pt` (`itemSpacing`) when the bar is horizontal and to
  `-16pt` (`cardOverlap`, a negative gap) when it is vertical; the vertical
  overlap makes the column read as a deck being turned rather than a list,
  while a horizontal bar has room along its length and does not need it.
- **start-inset-defaults-to-end-padding**: `startInset` MUST default to
  `8pt` (`endPadding`) and MUST re-apply the bar's edge insets whenever it
  is changed.
- **host-may-override-start-inset**: A host MAY set `startInset` to a value
  other than the default, to line a bar's first item up with chrome outside
  the bar; the component itself has no opinion on what that chrome is.
- **outer-padding-on-window-side-only**: The component MUST apply `6pt`
  (`outerPadding`) of inset on the bar's outer (window) side and `0pt` on its
  workspace side, with `startInset` at the bar's start (along its length) and
  `8pt` (`endPadding`) at its end.
- **bar-fills-perpendicular-and-pins-length**: For a `.top`/`.bottom` bar, the
  component MUST pin its arranged content's top, leading, trailing, and
  bottom edges to its own corresponding edges and install a height
  constraint; for a `.left`/`.right` bar, MUST pin its arranged content's top,
  leading, and trailing edges to its own, install a width constraint, and
  constrain its arranged content's bottom edge only `lessThanOrEqualTo` its
  own bottom.
- **vertical-bar-packs-from-top**: On a `.left`/`.right` bar, unused column
  height below the arranged content MUST remain empty rather than stretching
  the arranged items, as a direct consequence of the `lessThanOrEqualTo`
  bottom constraint in **bar-fills-perpendicular-and-pins-length**.
- **bar-fills-window-background**: The component MUST paint its own layer
  background with the `.windowBackground` palette role and MUST repaint it
  whenever the resolved theme palette changes.
- **set-items-triggers-rebuild**: `setItems(_:selectedID:)` MUST store the
  given items and selected id on the component and MUST rebuild the bar's
  arranged subviews to match them.
- **set-selected-restyles-and-reorders**: `setSelected(_:)` MUST update
  `selectedID`, MUST set `isHighlighted` to `true` on exactly the `TabButton`
  and any `TabBarHostedItem`-conforming hosted controller whose id equals the
  new selection and to `false` on every other one, and MUST update every
  hosted item's reported stack depth and, on a vertical bar, its front-to-back
  order to match (see **stack-depth-by-distance-from-selection** and
  **vertical-edge-cards-overlap-and-order-by-distance**).
- **stack-depth-by-distance-from-selection**: A selection change MUST
  compute each item's depth as the absolute difference between its index and
  the selected item's index, or `1` for every item when nothing is selected,
  and MUST report that depth to any hosted controller conforming to
  `TabBarStackedItem`.
- **vertical-edge-cards-overlap-and-order-by-distance**: On a `.left`/`.right`
  bar, a selection change MUST reorder each `.viewController` item's wrapper
  view, deepest-first, so the item nearest the selection ends up frontmost in
  both z-order and hit-testing; ties in depth MUST be broken by descending
  index.
- **rename-title-item**: `renameItem(id:title:)` MUST set the matching
  item's payload to `.title(title)` and MUST update that id's `TabButton`
  title when an item with the given id exists in `items`, and MUST be a
  silent no-op when no item has that id.
- **rebuild-clears-and-repopulates**: `setItems(_:selectedID:)` MUST discard
  every previously rendered item's view and any per-item state associated
  with the old items before repopulating the bar from the new `items`.
- **cross-edge-move-preserves-foreign-controller**: When reconciling hosted
  controllers, the component MUST remove a superseded controller's view from
  its superview and remove the controller from its parent only when that
  view is still sitting in a wrapper this bar itself created; it MUST leave
  the view and parent relationship untouched when the view has already been
  reparented onto a different bar.
- **rebuild-drops-stale-hosted-controllers**: Setting new items MUST stop
  tracking a `.viewController` item's hosted controller whenever that id's
  current payload differs by identity from the previously hosted controller
  (including when the id is no longer present in `items` at all), independent
  of whether **cross-edge-move-preserves-foreign-controller** also tore down
  its view.
- **title-item-becomes-button**: For each `.title(title)` item, the
  component MUST create a `TabButton`, set its `isHighlighted` to match
  `selectedID`, wire its `onSelect`/`onClose` to the bar's own
  `onSelect`/`onClose`, add it as an arranged item, and MUST additionally
  pin its cross-axis edges only when the bar's orientation is `.vertical`.
- **viewcontroller-item-becomes-hosted-view**: For each `.viewController`
  item, the component MUST add the controller as a child of `hostController`
  when it is not already its parent, set `isHighlighted` and `onClose` on it
  when it conforms to `TabBarHostedItem`, wrap its view in a
  `TabItemHostView` wired to the bar's `onSelect`, add that wrapper as an
  arranged item, and MUST pin the wrapper's cross-axis edges unconditionally
  (regardless of the bar's orientation).
- **thickness-grows-with-hosted-content**: The component MUST set the bar's
  thickness to the greater of `preferredThickness(for: edge)` and (the
  largest hosted controller's `preferredContentSize` on the bar's thickness
  axis, plus `6pt`/`outerPadding`), and MUST recompute it whenever `items`
  changes.
- **host-view-fills-hosted-content**: `TabItemHostView` MUST pin its wrapped
  content view's top, leading, trailing, and bottom edges to its own
  corresponding edges.
- **host-view-click-selects**: `TabItemHostView.mouseDown(with:)` MUST
  invoke `onSelect(id)` for a click that lands on the wrapper itself, without
  intercepting a click an interior subview (such as a hosted item's own close
  control) already handles as the frontmost hit-tested view.
- **close-icon-hit-routes-to-close**: `TabButton.mouseDown(with:)` MUST route
  a mouse-down that lands within the close icon's own bounds to that icon's
  own native handling (via `super.mouseDown(with:)`) and MUST NOT call
  `onSelect` in that case; it MUST call `onSelect(id)` for a mouse-down
  anywhere else in the view.
- **accessibility-press-always-selects**: `TabButton.accessibilityPerformPress()`
  MUST always call `onSelect(id)` and return `true`, regardless of where an
  assistive-technology press targets the element — unlike a physical click,
  it never routes to the close action.
- **tab-button-is-accessible-element**: `TabButton.init` MUST set
  `accessibilityElement` to `true`, MUST set `accessibilityRole` to
  `.button`, and MUST set the view's initial `accessibilityTitle` and
  `accessibilityValue` from the constructor's `title` and `isHighlighted`.
- **tab-button-title-updates-accessibility**: Setting `TabButton.title` MUST
  update both the visible title text and the view's `accessibilityTitle` to
  the new value.
- **tab-button-highlight-updates-accessibility-value**: Setting
  `TabButton.isHighlighted` MUST update the view's `accessibilityValue` to
  the new value and MUST restyle the button to match (see
  **selecting-a-tab-restyles-its-button**).
- **close-button-republished-as-sole-child**: `TabButton.accessibilityChildren()`
  MUST return exactly `[closeButton]`, so the close control stays reachable
  in the accessibility tree once `TabButton` becomes a single accessibility
  element.
- **close-button-carries-per-tab-identifier**: `TabButton.init` MUST give
  `closeButton` the accessibility identifier `tab-bar.close.<id>` and MUST
  give the tab button itself `tab-bar.select.<id>`, both keyed by the tab's
  own UUID.
- **selecting-a-tab-restyles-its-button**: Selecting a tab MUST fill its
  background with the `.selection` palette role, set its title's color role
  to `.selectionText`, and set its close icon's tint to `.selectionText` when
  `isHighlighted` is `true`; it MUST use `NSColor.clear`, `.secondaryText`,
  and `.tertiaryText` respectively when it is `false`.
- **declares-reorder-callback**: The component MUST expose a public
  `onReorder: ((UUID, Int) -> Void)?` property, in addition to `onSelect` and
  `onClose`, for a caller to observe tab reordering.
- **rejects-coder-initializer**: `TabBarView`, the private `TabItemHostView`,
  and the private `TabButton` MUST each fatal-error if constructed through
  `init?(coder:)`.
- **confines-to-main-actor**: `TabBarView`, `TabItemHostView`, and `TabButton`
  MUST each be usable only on the main actor; all three are declared
  `@MainActor`.
