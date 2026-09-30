<!-- leaf: implement-general-controller/multi-tabbed-view-controller · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController

## Overview

`MultiTabbedViewController` is an `open`, `@MainActor` `NSViewController` that
hosts up to four edge-docked tab bars — top, right, bottom, left — around a
single shared content area, IDE-style. Each enabled edge owns its own tab
list; edges can be shown or hidden independently and a hidden edge keeps its
tabs so re-enabling it restores them. At most one tab is active across the
whole controller at any time, and that tab's own view controller fills the
center; `mainContentViewController`, if set, fills the center instead while no
tab is active. A `Tab`'s `groupID` ties it to its siblings on other edges — one
thing the user thinks of as "a tab" can have a member on each edge, and
selecting any member selects all of them; a tab given no explicit group is its
own group of one. Tab bar rendering, per-tab click/close handling, and
vertical-edge card stacking are implemented by the internal `TabBarView` and
`TabButton` types in the same directory and are described here as part of this
component, since neither has a recipe of its own.

