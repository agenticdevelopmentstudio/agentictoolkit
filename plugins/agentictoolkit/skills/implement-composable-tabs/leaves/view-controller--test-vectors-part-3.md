<!-- leaf: implement-composable-tabs/view-controller--test-vectors-part-3 · source: composable-tabs-view-controller.md -->

# ComposableTabsViewController — Conformance Test Vectors (part 3)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| composable-tabs-096 | reassign-identifiers-on-root-load | Construct a non-root controller with two panes of the same `paneTypeIdentifier`, load the view | Neither pane's index is assigned by `viewDidLoad()` (no call to `reassignPaneIdentifiers()` on a non-root instance) |
| composable-tabs-097 | persisted-state-applies-once | Leaf X has a persisted minimize edge and lies off the path to leaf Y, the persisted `zoomedLeaf`; `applyPersistedPaneState()` is called | X's split item ends up both pinned (`minimumThickness == maximumThickness`) and collapsed (`isCollapsed == true`) — minimize pinned it before zoom collapsed it, so neither effect is lost |
