<!-- leaf: implement-composable-tabs/pane-view-controller · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController

## Overview

`ComposableTabsPaneViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsPaneViewController.swift`) is one leaf of a `ComposableTabs` split tree: registry-vended content under a pane title bar, plus — while arrange mode is on — a dimming scrim and a small toolbar that let the user reshape the layout around it.

It is a subclass of `PaneViewController` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/Panes/PaneViewController.swift`), which owns the shared chrome — the title bar, the gear button, the minimize/zoom/close controls, and per-pane spacing — for every kind of pane in the framework, not only `ComposableTabs` leaves. `PaneViewController` is out of this recipe's scope; only the three things this subclass adds are documented here: which registry vends its content, the backdrop that draws the active-pane outline, and what "arrange mode" does over the top of an otherwise ordinary pane. The layout can be rearranged two ways that answer different needs: the gear menu always carries a `Move` submenu for a user who knows exactly which pane goes where, and arrange mode dims the content and puts the same four directions in a central toolbar for a user who is looking at the window deciding. Both read the same `ComposableTabsMoveMenu`, so there is one answer to what `Move` means.

