<!-- leaf: implement-composable-tabs/view-controller · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController

## Overview

`ComposableTabsViewController` is a `@MainActor`, `final` `NSSplitViewController`
subclass (of `ThemedSplitViewController`) that is the recursive building block
of a project tab's pane layout. Each instance is either the tab's root or one
node of a binary tree nested beneath it: it holds at most two children —
`ComposableTabsPaneViewController` leaves, or further nested
`ComposableTabsViewController` splits — laid out along a `ComposableTabsAxis`
(`.horizontal` or `.vertical`). The tree's shape and each node's share of its
split (`thicknessFraction`) are captured to and rebuilt from a value-type
`LayoutNode`, so a project's stored layout can be persisted, restored, and
mirrored across tabs. On top of the tree itself, the type also conforms to
`PaneHost` (in `ComposableTabsPaneHost.swift`, the other half of this same
class): it is the object a pane calls to close, minimize/restore, or zoom
itself, and the one that resolves those requests against the layout spec and
the live `NSSplitViewItem`s.

## Behavioral Requirements
