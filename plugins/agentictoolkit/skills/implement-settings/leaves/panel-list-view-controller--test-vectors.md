<!-- leaf: implement-settings/panel-list-view-controller--test-vectors · source: settings-panel-list-view-controller.md -->

# PanelListViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| cts-panel-list-001 | panel-storage | `setPanels([panelA, panelB])` | The sidebar shows exactly two rows, for `panelA` and `panelB`, in that order |
| cts-panel-list-002 | panel-set-rebuild | `setPanels([panelA])`, then `setPanels([panelA, panelB])` | The sidebar shows two rows after the second call, without a separate rebuild call being needed |
| cts-panel-list-003 | unchanged-query-guard | Construct a test subclass overriding `setSections(_:)` to increment a counter; `setPanels([panelA, panelB])`; set `searchQuery = "x"`; record the counter; set `searchQuery = "x"` again (identical) | The counter after the second assignment equals the counter recorded after the first — `setSections(_:)` was not called again |
| cts-panel-list-004 | query-change-rebuild | Same counter subclass as cts-panel-list-003; `setPanels([panelA, panelB])`; set `searchQuery = "a"`; record the counter; set `searchQuery = "b"` | The counter after the second assignment is one greater than after the first — `setSections(_:)` was called again |
| cts-panel-list-005 | empty-query-inclusion | `setPanels([panelA, panelB])`, then `searchQuery = "   "` | Both rows remain visible |
| cts-panel-list-006 | all-terms-match | `setPanels([panelA])` where `panelA.descriptor.title == "General"` and `panelA.descriptor.section == "App"`, then `searchQuery = "app general"` | `panelA`'s row is visible; `searchQuery = "app missing"` then hides it |
| cts-panel-list-007 | panel-order-preservation | `setPanels([panelB, panelA])`, `searchQuery = ""` | Rows appear in the order `panelB`, `panelA` |
| cts-panel-list-008 | contiguous-section-grouping | `setPanels([p1(section: "A"), p2(section: "B"), p3(section: "A")])` | Three sections render, in order A, B, A — not two sections of A merged |
| cts-panel-list-009 | descriptor-row-mapping | `setPanels([panelA])` where `panelA.descriptor` has a specific title, icon, and `isDisabled == true` | The row shows that title and icon and renders in the disabled appearance |
| cts-panel-list-010 | original-index-row-id | Construct via `init(nibName:bundle:)`; `setPanels([panelA, panelB])`, `searchQuery = "panelB-only-term"` (hides `panelA`); select the surviving row through the outline view directly (not via `selectPanel(at:)`) | `visiblePanelIndices() == [1]`, and `onSelectPanel` is invoked with `panelB` — proving the surviving row's id still resolves to index `1`, not re-indexed to `0` |
| cts-panel-list-011 | selection-callback-bridge | Construct via `init(nibName:bundle:)`, `setPanels([panelA])`, click `panelA`'s row | `onSelectPanel` is invoked once with `panelA` |
| cts-panel-list-012 | coder-init-bridge-omission | Construct via `init?(coder:)`, `setPanels([panelA])`, select `panelA`'s row through the outline view directly | `onSelectPanel` is never invoked (it was never wired) |
| cts-panel-list-013 | callback-free-selection | Set `onSelectPanel` to a spy closure, call `selectPanel(at: 0)` | The row at index 0 becomes selected; the spy closure is not called |
| cts-panel-list-014 | out-of-range-select-guard | `setPanels([panelA])`, call `selectPanel(at: 5)` | No row's selection changes; no crash |
| cts-panel-list-015 | panel-visibility-report | `setPanels([panelA, panelB])`, `searchQuery` set to a term matching only `panelB` | `isPanelVisible(at: 0) == false`, `isPanelVisible(at: 1) == true` |
| cts-panel-list-016 | visible-index-report | `setPanels([p0, p1, p2])`, `searchQuery` set to a term matching only `p0` and `p2` | `visiblePanelIndices() == [0, 2]` |
| cts-panel-list-017 | row-id-panel-resolution | Select a row whose underlying id is `"1"` for `setPanels([panelA, panelB])` | `onSelectPanel` receives `panelB`; simulating a stale/malformed id (e.g. `"not-a-number"` or `"9"`) resolves to no panel |
