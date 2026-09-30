<!-- leaf: implement-panel/scroll-view--test-vectors · source: panel-scroll-view.md -->

# PanelScrollView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| panel-scroll-view-001 | document-view-flipped | Inspect `documentView.isFlipped` on a newly constructed `PanelScrollView` | `isFlipped` returns `true` |
| panel-scroll-view-002 | content-top-leading-anchored | Inspect the document view's active constraints against `contentView` on a newly constructed `PanelScrollView` | Document view's top and leading anchors are each constrained equal, constant `0`, to `contentView`'s top and leading anchors |
| panel-scroll-view-003 | content-width-matches-viewport | Call `setContent(view)` with `view` whose intrinsic content width is wider than the current viewport, then resize the scroll view's frame | `view`'s width always equals `contentView.frame.width`; it never exceeds or falls short of the viewport width regardless of `view`'s intrinsic width |
| panel-scroll-view-004 | content-min-height-viewport | Call `setContent(view)` with `view` whose intrinsic content height is smaller than the viewport height | `view`'s height is at least `contentView.frame.height`, filling the viewport with no gap below |
| panel-scroll-view-005 | content-fills-document-edges | Call `setContent(view)`, then inspect the edge constraints between `view` and the document view | `view`'s top, leading, trailing, and bottom anchors are each constrained equal, constant `0`, to the document view's corresponding anchors |
| panel-scroll-view-006 | content-replacement-removes-previous | Call `setContent(viewA)`, then call `setContent(viewB)` | After the second call, `viewA` is no longer a subview of the document view; only `viewB` remains |
| panel-scroll-view-007 | content-replacement-resets-scroll-position | Scroll to the bottom of `viewA`'s content, then call `setContent(viewB)` | The scroll position returns to the top (origin) once `setContent` installs `viewB`, as a side effect of removing `viewA`'s constraints rather than an explicit scroll reset |
| panel-scroll-view-008 | vertical-scroller-enabled | Inspect a newly constructed `PanelScrollView` | `hasVerticalScroller == true` |
| panel-scroll-view-009 | horizontal-scroller-enabled | Inspect a newly constructed `PanelScrollView` | `hasHorizontalScroller == true` |
| panel-scroll-view-010 | scrollers-autohide | Inspect a newly constructed `PanelScrollView` | `autohidesScrollers == true` |
| panel-scroll-view-011 | background-transparent | Inspect a newly constructed `PanelScrollView` | `drawsBackground == false` |
| panel-scroll-view-012 | autoresizing-mask-disabled | Inspect a newly constructed `PanelScrollView` and its document view | `translatesAutoresizingMaskIntoConstraints == false` on both the scroll view and the document view |
| panel-scroll-view-013 | main-actor-isolated | Attempt to construct or call `setContent` on a `PanelScrollView` from off the main actor | The compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| panel-scroll-view-014 | programmatic-instantiation-only | Attempt `PanelScrollView(coder: someCoder)` | The compiler rejects the call at compile time (the initializer is marked unavailable); no instance is produced |
| panel-scroll-view-015 | content-width-matches-viewport | Host a `PanelScrollView` as one pane of an `NSSplitView`, record the split view's divider position, then call `setContent(view)` with `view` whose intrinsic width is wider than the pane | The divider's position is unchanged after `setContent` returns; `view`'s width still equals `contentView.frame.width`, never exceeding the pane's allotted width |
