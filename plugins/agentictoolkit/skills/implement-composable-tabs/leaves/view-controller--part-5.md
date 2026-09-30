<!-- leaf: implement-composable-tabs/view-controller--part-5 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — continued (part 5)

## Platform Notes

- **SwiftUI**: Model the tree as a recursive `enum LayoutNode` (already the
  persistence type) driving a recursive `View`: a `.split` node renders a
  custom recursive `HStack`/`VStack` (from the node's axis) around two
  recursive calls, each sized with a `GeometryReader`-driven
  `.frame(width:)`/`.frame(height:)` computed from `thicknessFraction`, with a
  custom `DragGesture` on a thin overlay divider between them — SwiftUI's
  built-in `HSplitView`/`VSplitView` expose no fraction API, so a hand-built
  stack-and-overlay is used instead — to reproduce the clamp-to-minimum
  behavior of **clamp-thickness-to-minimum**. A
  `.leaf` node renders the pane's own view. Persist sizes with a
  `.onChange(of:)` debounced through a `Task` with `Task.sleep(for: .milliseconds(300))`,
  mirroring `scheduleThicknessPersist()`, and skip the write when the rounded
  signature matches the last one sent, mirroring `dedupe-unchanged-persist`.
  Represent zoom as a `@State` "zoomed id" that conditionally renders only the
  zoomed leaf's subtree instead of collapsing sibling views, since SwiftUI has
  no `isCollapsed` flag to toggle.
- **Compose**: Mirror the same recursive `LayoutNode` with a recursive
  `@Composable` function: a split renders a `Row`/`Column` (from the node's
  axis) with each child's `Modifier.weight(fraction)`, and a divider composable
  using `Modifier.pointerInput` to drag-update a `mutableStateOf(Float)`
  fraction, clamped to a minimum-thickness `Dp` the way
  `clamp-thickness-to-minimum` does. Persist via a `snapshotFlow` debounced
  with `.debounce(300)`, mirroring the AppKit debounce exactly. Represent zoom
  by conditionally emitting only the ancestors-and-zoomed-leaf subtree (`if
  (onZoomPath) { ... }`), mirroring `applyZoom(target:)`'s collapse-by-flag
  approach translated to Compose's declarative recomposition model.
- **React/Web**: Render the same recursive tree with nested CSS `flex`
  containers (`flex-direction: row`/`column` from the node's axis), each
  child sized with an inline `flex-basis` percentage derived from
  `thicknessFraction` and a `min-width`/`min-height` from the descriptor's
  `minimumThickness`, using a library such as `react-resizable-panels` (or a
  hand-rolled `pointermove` divider handler) to reproduce drag-to-resize with
  a widened invisible hit area around each divider, mirroring
  `widen-divider-grab-area`. Debounce persistence with `setTimeout(..., 300)`,
  clearing the previous timer on every resize event, mirroring
  `debounce-thickness-persist`, and compare a rounded-fraction signature
  before calling the persistence callback, mirroring `dedupe-unchanged-persist`.
  Implement zoom by conditionally rendering `display: none` on every sibling
  not on the path to the zoomed leaf, the DOM analog of `isCollapsed`.
- **AppKit/UIKit** (source platform): Implemented across
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsViewController.swift`
  (the tree itself: init, layout, arrangement, thickness capture/persist,
  split/remove/move/rebuild, spec-gated mutation, and `LayoutNode`
  construction) and `ComposableTabsPaneHost.swift` (the `PaneHost` conformance
  on the same type: close, minimize/restore, zoom, and the two
  root-only re-apply passes `applyPersistedPaneState()`/`reapplyPaneState()`).
  It is a `final`, `@MainActor` `NSSplitViewController` subclass built as a
  recursive binary tree of itself and `ComposableTabsPaneViewController`
  leaves, with no UIKit code path in source at all — this is a macOS-only,
  pointer-and-window-driven component (draggable dividers, a rail-pinned
  minimize, a zoom that collapses `NSSplitViewItem`s). The requirements and
  test vectors above state everything in observable terms; the private
  symbols that implement them (`applyPreferredThicknessesIfNeeded()`,
  `hasAppliedPersistedPaneState`, `detachSubtree()`, the debounced
  `DispatchWorkItem`/`pendingThicknessPersist`, `lastPersistedThicknesses`,
  and `PaneMinimizeGeometry.resolvedEdge`) are named here because they are
  private to this source file and have no analog for another platform's port
  to match. A UIKit/iPadOS port has
  no direct analog to `NSSplitViewController`'s per-item collapse/pin/minimum
  API; it would most likely use `UISplitViewController` for the fixed
  two-column case, or a hand-built recursive container (mirroring this file's
  own recursive-controller structure) using `UIStackView` plus a custom
  pan-gesture-driven divider for the general N-level tree, and would need to
  invent its own zoom/minimize/pin equivalents from scratch.
- **WinUI 3** (the reason this recipe exists): Represent each `.split` node as
  a `Grid` with exactly two `ColumnDefinition`s (`.horizontal` axis) or two
  `RowDefinition`s (`.vertical` axis), sized `GridLength(fraction,
  GridUnitType.Star)` from each child's `thicknessFraction` (an even 1★/1★
  split, mirroring "the split divides evenly," when neither child has one
  yet), separated by a `GridSplitter` whose `ResizeBehavior="PreviousAndNext"`
  and whose thickness is bound to the between-columns/between-rows gutter
  setting, mirroring `PaneSplitView.dividerThickness`; set `GridSplitter`'s
  hit-test `Width`/`Height` to at least `PaneSpacing.minimumDividerGrab` (6
  device-independent pixels) independent of its drawn thickness, mirroring
  `widen-divider-grab-area`, via a transparent margin rather than a wider
  visible bar. Recurse into a nested `Grid` for a `.split` child and a plain
  content `Frame`/`ContentPresenter` for a `.leaf` child, exactly mirroring
  `buildSplit`/`buildChild`. Debounce a `GridSplitter.DragCompleted` (not
  every intermediate drag delta) through a `DispatcherQueueTimer` set to 300ms
  and reset on every new completion, mirroring
  `scheduleThicknessPersist`/`thicknessPersistDelay`, and skip the write when
  a rounded-fraction signature matches the last one sent, mirroring
  `dedupe-unchanged-persist`. Represent **minimize** by capturing the pane's
  `ColumnDefinition`/`RowDefinition.Width`/`Height` as a fixed pixel
  `GridLength` (not `Auto`, not `*`) sized to the pane's minimized chrome, the
  direct analog of pinning `minimumThickness == maximumThickness`, and
  restore by putting the previously-recorded `Star` value back, mirroring
  `restoreSizing(of:)`'s "ceiling before floor" ordering by clearing any fixed
  cap before reasserting the star weight. Represent **zoom** by collapsing
  (`Visibility="Collapsed"`, `Width`/`Height="0"`) every `Grid`/`GridSplitter`
  off the path from the outermost `Grid` down to the zoomed leaf's container,
  and restoring all of them to their prior `GridLength`s on unzoom — the
  direct analog of toggling `NSSplitViewItem.isCollapsed` down the same path
  in `applyZoom(target:)`. A `VisualStateManager` state group
  (`Default`/`Minimized`/`Zoomed`) on the pane's own container is a reasonable
  way to drive the chrome changes that accompany each transition, mirroring
  the mutual exclusivity in `minimize-clears-zoom-first`/`zoom-toggles-and-excludes-minimize`.

