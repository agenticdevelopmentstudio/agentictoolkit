<!-- leaf: implement-general-view-2/tab-pane-view · source: tab-pane-view.md -->

# TabPaneView

## Overview

`TabPaneView` is a `final`, `@MainActor` `NSView` drawn as one card in an edge
bar of MultiTabbedViewController:
a stacked block, the same arrangement on all four edges, showing a session's
agent/model name, status symbols, session name, working directory, branch, and
an optional summary. It is the `view` of `TabPaneViewController`, which hosts
it as a `TabItem.viewController` and drives its `stackDepth`/`isHighlighted`
through `TabBarStackedItem`. The card in front (`stackDepth == 0`) paints what
the workspace paints, in the workspace's own outline color, and overhangs the
bar by one point to cover the line the workspace draws down that side, so one
unbroken line runs around the active card and the workspace it belongs to. A
card behind stops short of its own edge instead, leaving the workspace's line
whole, and — on a vertical (left/right) edge only — recedes further with every
step of depth, so a column of cards reads as a deck turned to the selected
tab.

