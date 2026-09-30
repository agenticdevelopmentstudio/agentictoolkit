<!-- leaf: implement-general-controller/split-view-controller--edge-cases · source: split-view-controller.md -->

# SplitViewController

**Rules** (cite as `implement-general-controller/split-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — setPanels([]) and clear() both leave panels empty, the sidebar empty, and the detail pane empty (MUST). Constructing …
- `boundary-values` MUST — selectPanel(at:) and navigate(to:) both guard panels.indices.contains(index) and are silent no-ops out of range (MUST). …
- `sidebarautosavename-nil-while-contentsizedsidebar-false` MAY — A subclass MAY override sidebarAutosaveName to return nil. In that case splitView.autosaveName is set to nil, which …

## Edge Cases

- **Null/empty input**: `setPanels([])` and `clear()` both leave `panels`
  empty, the sidebar empty, and the detail pane empty (MUST). Constructing
  with `init(listViewController:)`'s default argument uses a stock
  `PanelListViewController()` rather than requiring a caller-supplied one
  (MUST).
- **Boundary values**: `selectPanel(at:)` and `navigate(to:)` both guard
  `panels.indices.contains(index)` and are silent no-ops out of range
  (MUST). `moveSelection(by:)` stops at the first or last *visible* row
  rather than wrapping, and is a no-op when no rows are visible (MUST, see
  **steps-through-visible-rows-only**). A content-sized sidebar's width is
  capped at `480`pt regardless of how wide `preferredWidth()` reports (MUST,
  see **caps-content-sized-sidebar-width**).
- **Concurrent access**: Not applicable — the class is `@MainActor`, so the
  Swift compiler rejects construction or mutation from off the main actor;
  there is no concurrent-access surface for this file to define behavior
  for.
- **Error states**: Not applicable — every member in this file is
  synchronous and non-throwing; there is no dependency, network call, or
  fallible operation in this file.
- **Offline/disconnected state**: Not applicable — this file performs no
  networking and has no dependency on connectivity.
- **`removePanel(_:)` on a panel not in `panels`**: `removeAll(where:)`
  removes nothing, but the method still unconditionally resets navigation
  history, re-sets the sidebar's panel list, and invokes
  `notifyNavigationChange()` — the same side effects as a real removal.
  This is a documented observation of the file's actual behavior, not a
  deliberate contract (see split-view-controller-053).
- **`sidebarAutosaveName == nil` while `contentSizedSidebar == false`**: A
  subclass MAY override `sidebarAutosaveName` to return `nil`. In that case
  `splitView.autosaveName` is set to `nil`, which silently disables
  `NSSplitView`'s width-persistence for that instance — no fallback name is
  substituted and nothing fails (see split-view-controller-024b).
- **Stale nested-detail floor after a nested split is removed**:
  `unifyNestedSidebars()` only recomputes `nestedDetailFloor` when at least
  two nested `SplitViewController` panels remain (`guard nested.count > 1
  else { return }`); when a `removePanel`/`setPanels` call drops the nested
  count from two-or-more to one or zero, this early return leaves
  `nestedDetailFloor` at its previous, now-stale value rather than
  resetting it toward `0`. The detail pane's floor can therefore stay wider
  than the current panel set requires until a later state again has two or
  more nested siblings. This is the file's actual, undocumented behavior —
  see Design Decisions and split-view-controller-054.
- **Toggling `showsSidebarSearch` or `sortsPanelsByTitle` after their
  first effect has already run**: Neither property has a property observer.
  `showsSidebarSearch` is read only once, in `viewDidLoad`, to decide
  whether to install the header accessory view — flipping it afterward has
  no further effect on an already-loaded view. `sortsPanelsByTitle` is
  read only inside `setPanels(_:)`/`addPanel(_:)` — flipping it does not
  retroactively reorder a panel list already installed; it only changes the
  outcome of the next mutating call.
