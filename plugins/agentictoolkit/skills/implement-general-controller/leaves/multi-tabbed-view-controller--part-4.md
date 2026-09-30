<!-- leaf: implement-general-controller/multi-tabbed-view-controller--part-4 · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController — continued (part 4)

## Platform Notes

- **SwiftUI**: Model each edge's tab list as an `@State`/`@Observable` array
  keyed by a stable id, and the active tab as a single shared id (or a
  `groupID`, to reproduce cross-edge sibling selection). Render each enabled
  edge's bar as an `HStack`/`VStack` (chosen by `Edge.isVertical`) of pill
  buttons inside a `ScrollView`, each with a `.background` capsule that swaps
  fill/foreground on selection the way `TabButton.updateAppearance()` does,
  and a trailing close `Button`. Compose the four bars and the center content
  with nested `VStack`/`HStack`s mirroring `rebuildEdgeConstraints()`'s
  top/bottom-row, left/right-column arrangement, hiding a disabled edge's bar
  with `if isEdgeEnabled(edge) { ... }` rather than an `isHidden` flag. There
  is no first-class SwiftUI analog for the vertical-edge card overlap/z-order
  behavior; reproduce it with `.offset`/`.zIndex` driven by each item's index
  distance from the selection.
- **Compose**: Mirror the same per-edge tab list and shared active-id/group-id
  state in a `ViewModel`. Render a horizontal edge with a `Row` of
  `FilterChip`/custom `Surface` pills inside a horizontally-scrolling
  container, and a vertical edge with a `Column` of the same, using
  `Modifier.offset`/`graphicsLayer { translationY = ... }` and `zIndex()` keyed
  on each item's distance from the selected index to reproduce the `-16pt`
  overlap and depth ordering. Compose a `Scaffold`-style frame with `Row`/
  `Column` slots for the up-to-four bars around the content, showing or hiding
  a bar's Composable entirely (not just visually) to mirror `isHidden`.
- **React/Web**: Represent each edge's tabs as an array in component state,
  keyed by id, with a shared `activeGroupId`. Render a top/bottom edge as a
  `<div>` with `display: flex; flex-direction: row` and a left/right edge with
  `flex-direction: column`, each tab a `<button>` styled with the selected/
  unselected background and text-color swap; a `position: relative` wrapper
  with negative `margin` (mirroring the `-16pt` overlap) and `z-index`
  computed from index-distance-from-selection reproduces the vertical card
  stack. Compose the up-to-four bars and the center `<div>` with CSS Grid
  (`grid-template-areas` for top/left/center/right/bottom), toggling a bar's
  `display: none` to mirror `isHidden`.
- **AppKit / UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/`
  across `MultiTabbedViewController.swift` (edge/tab/selection state, layout,
  center mounting), `TabBarView.swift` (bar rendering, `TabButton`,
  `TabItemHostView`, card stacking), `TabItem.swift` (`TabItem`,
  `TabBarHostedItem`, `TabBarStackedItem`), `Edge.swift`, and
  `MultiTabbedViewControllerDelegate.swift`. This is a macOS-only, AppKit
  `NSViewController` component with no UIKit code path in source. A UIKit/
  iPadOS port has no direct analog to four independently toggleable,
  sibling-linked edge bars around one content area; it would most likely be a
  hand-built container using `UIStackView`s for each edge (mirroring this
  file's own `NSStackView`-per-edge structure) and a custom container view
  controller for the center, rather than `UITabBarController`, which supports
  only one bottom bar and no cross-edge group selection. Internally (private,
  not part of the conformance contract above — cited here rather than in the
  test vectors): `tabBars: [Edge: TabBarView]` holds each edge's bar view;
  `centerContainer` is the shared content wrapper and `mountedCenterController`
  tracks the controller currently mounted in it; each bar keeps its thickness
  in `thicknessConstraint` and lays items out in an `NSStackView` (`stack`)
  whose `edgeInsets` hold the per-side padding; `TabButton` draws selection
  through `backgroundView.layer` and a `titleLabel` role swap.
- **WinUI 3**: There is no single WinUI 3
  control that docks tab bars on all four sides with cross-edge sibling
  selection, so build the frame as a `Grid` with `Auto`-sized
  `RowDefinition`s/`ColumnDefinition`s for the top/bottom/left/right bar slots
  around a `Star`-sized center `ContentPresenter`, collapsing a disabled
  edge's row/column to `0` (`Visibility="Collapsed"` on that bar) to mirror
  `isHidden`/`rebuildEdgeConstraints()`. WinUI 3's native `TabView` only
  supports a single top-docked strip and has no notion of a tab linked across
  several instances, so represent each edge's bar as a `ListView` (or
  `ItemsRepeater`) of `ToggleButton`-based pill items inside a horizontal or
  vertical `StackPanel`/`ItemsStackPanel` (chosen by `Edge.isVertical`),
  driving each item's checked visual state with a `VisualStateManager`
  `Selected`/`Unselected` state group that swaps `Background`/`Foreground`
  brushes the way `TabButton.updateAppearance()` swaps palette roles. Persist
  a `groupID`-style key alongside each `ListView`'s items and, on any one
  edge's `SelectionChanged`, programmatically set the matching item selected
  on every other edge's `ListView` to reproduce
  `group-siblings-share-selection-across-edges`. Bind each bar's
  `MinWidth`/`MinHeight` (top/bottom vs. left/right) to the hosted content's
  measured `DesiredSize` plus `6epx`, clamped to the `28epx`/`140epx` floor, to
  mirror `tab-bar-thickness-floor-and-growth`. Reproduce the vertical-edge
  card overlap with a negative `Margin` on each item plus `Canvas.ZIndex` set
  from each item's index-distance from the selected one, mirroring
  `applyStackOrder()`; a close glyph can use the Segoe Fluent Icons
  `\uE711` ("Cancel") glyph sized to match the `14×14pt` hit area.

## Design Decisions

**Decision**: A tab's `groupID` defaults to its own `id` rather than requiring
every caller to supply one.
**Rationale**: Per `Tab.init`'s doc comment, this "makes a tab its own group of
one — the behaviour every host had before groups existed," so a caller with
only one edge needs no change to keep working.
**Approved**: pending

**Decision**: `activateFallbackTab()` looks for a same-group sibling on any
enabled edge before falling back to the first tab of the first enabled edge.
**Rationale**: Per the method's doc comment, turning an edge off "is a decision
about where tabs are drawn," and jumping instead to an unrelated tab on the
first enabled edge "dropped [the user] onto an unrelated checkout" — the
group-first fallback keeps the user's actual selection stable across edge
visibility changes.
**Approved**: pending

**Decision**: `contentInsets` is applied by `MultiTabbedViewController` around
the mounted content, rather than left to the content itself.
**Rationale**: Per the property's doc comment, the tab bars "have to stay flush
against the window," so the gap belongs between the bars and what they
frame, and "this controller is the only thing that owns both."
**Approved**: pending

**Decision**: `activeTabDidChange` fires on every activation — including
transitions to `nil` — while `didSelectTab` fires only for a user-driven
pick (a click, or the neighbor/fallback a close hands the user).
**Rationale**: Per the delegate's doc comments, a host that only needs "which
pane is in front now" should not have to separately filter fallback and
clearing transitions out of genuine user picks; the two callbacks
deliberately separate "what changed" from "the user chose this."
**Approved**: pending

**Decision**: `TabBarView.rebuildButtons()`'s reconciliation tears down a hosted
controller only if that controller's view still sits in *this* bar's own
wrapper.
**Rationale**: Per the method's doc comment, a cross-edge move reparents the
controller's view onto the new bar's wrapper before the old bar notices the
id is gone from its own items; tearing it down there too "would rip the
view out of the new bar's display."
**Approved**: pending

**Decision** (documented quirk, not a deliberate design choice): the
front-to-back z-reordering and `stackDepth` reporting in
`TabBarView.applyStackOrder()` only cover `.viewController` items (via
`hostViews`/`hostedControllers`). A `.title` `TabButton` on a vertical
(`.left`/`.right`) edge still receives the same `-16pt` overlapping
`stack.spacing` as hosted items, but is never reordered by distance from the
selected item — its z-order, and therefore which overlapping title tab
draws and hit-tests on top, is left at whatever order
`NSStackView.addArrangedSubview` produced (list order), regardless of which
tab is selected.
**Rationale**: `hostViews`/`hostedControllers` are populated only for
`.viewController` items, so `applyStackOrder()`'s reordering loops have
nothing to reorder for title tabs; nothing in source suggests this was a
deliberate choice for the title-tab case rather than an oversight. Recorded
here, per source fidelity, rather than smoothed over.
**Approved**: pending
