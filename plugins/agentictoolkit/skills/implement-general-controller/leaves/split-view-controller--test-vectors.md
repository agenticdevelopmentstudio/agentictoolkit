<!-- leaf: implement-general-controller/split-view-controller--test-vectors · source: split-view-controller.md -->

# SplitViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| split-view-controller-001 | exposes-hosted-panels-read-only | Attempt to assign `panels` directly from outside the type | Compile error; only `setPanels`/`addPanel`/`removePanel`/`clear` compile |
| split-view-controller-002 | default-detail-minimum-thickness | Construct a plain instance | `detailMinimumThickness == 400` |
| split-view-controller-003 | overridable-detail-minimum-thickness | Subclass and override `detailMinimumThickness` to `200` | The overridden value, not `400`, governs the detail item's `minimumThickness` |
| split-view-controller-004 | default-sidebar-autosave-name | Construct a plain instance | `sidebarAutosaveName == "ComposableSettings.RootSidebar"` |
| split-view-controller-005 | default-content-sized-sidebar | Construct a plain instance | `contentSizedSidebar == false` |
| split-view-controller-006 | injectable-list-view-controller | Construct with `init(listViewController: customSubclass)` | `listViewController === customSubclass` |
| split-view-controller-007 | reaches-list-controller-title | Set `sidebarTitle = "Advanced"` after `viewDidLoad` has run | `listViewController`'s title becomes `"Advanced"` |
| split-view-controller-007b | reaches-list-controller-title | Set `sidebarTitle = "Advanced"` before the view loads, then trigger `viewDidLoad` | `listViewController`'s title is `"Advanced"` after load |
| split-view-controller-008 | reports-innermost-panel-title | Select a nested `SplitViewController` panel whose own `currentPanelTitle` is `"Accent Color"` | This instance's `currentPanelTitle == "Accent Color"` |
| split-view-controller-009 | rejects-coder-initialization | Attempt `init?(coder:)` | Traps with a fatal error; no instance is returned |
| split-view-controller-010 | runs-on-main-actor | Attempt to construct or mutate an instance from a non-main-actor context | Rejected at compile time by Swift's actor isolation checking |
| split-view-controller-011 | forwards-help-presenter-to-detail-chrome | Set `helpPresenter = drawer` | `panelHost.helpPresenter === drawer` |
| split-view-controller-012 | forwards-inline-help-button-visibility | Set `showsInlineHelpButton = false` | `panelHost.showsHelpButton == false` |
| split-view-controller-013 | wires-help-visibility-callback-once | Assign `onHelpVisibilityChange` twice, then have `panelHost` fire its own callback | The most recently assigned closure fires; no double invocation and no re-wiring occurs on assignment |
| split-view-controller-014 | toggles-help-through-detail-chrome | Call `toggleHelp()` | `panelHost.toggleHelp()` is invoked |
| split-view-controller-015 | reports-help-visibility-from-detail-chrome | Set `panelHost`'s help to visible | `isHelpVisible == true` |
| split-view-controller-016 | builds-search-field-lazily | Construct an instance with `showsSidebarSearch == false` and never read the search field | No `ThemedSearchField` is ever allocated |
| split-view-controller-017 | installs-search-field-only-when-enabled | Set `showsSidebarSearch = true` before `viewDidLoad`, then load | `listViewController`'s header accessory view is the search field |
| split-view-controller-017b | installs-search-field-only-when-enabled | Leave `showsSidebarSearch == false`, then load | `listViewController`'s header accessory view is unset |
| split-view-controller-018 | filters-list-as-user-types | Type `"a"` into the search field without pressing Return | `listViewController.searchQuery == "a"` immediately |
| split-view-controller-019 | redirects-arrow-keys-to-selection | With the search field focused and `"Advanced"` typed, press Down | Sidebar selection moves to the next visible row; search text remains `"Advanced"` |
| split-view-controller-020 | builds-non-collapsible-sidebar-item | Load the view, then attempt to collapse the sidebar item | Collapse is refused; `canCollapse == false` |
| split-view-controller-021 | prioritizes-detail-pane-on-resize | Read the sidebar item's and detail item's `holdingPriority` after `viewDidLoad` | Sidebar item's `holdingPriority == .defaultLow + 1`; detail item's `holdingPriority == .defaultLow` |
| split-view-controller-022 | fixes-content-sized-sidebar-thickness | Set `contentSizedSidebar` to return `true`, then load | Sidebar item's `minimumThickness == maximumThickness` |
| split-view-controller-023 | constrains-draggable-sidebar-range | Load with `contentSizedSidebar == false` (default) | Sidebar item's `minimumThickness == 160`, `maximumThickness == 360` |
| split-view-controller-024 | persists-draggable-sidebar-width | Load with `contentSizedSidebar == false` | `splitView.autosaveName == sidebarAutosaveName` |
| split-view-controller-024b | persists-draggable-sidebar-width | Subclass overrides `sidebarAutosaveName` to return `nil`; load with `contentSizedSidebar == false` | `splitView.autosaveName == nil`; width persistence is silently disabled, no fallback name is used |
| split-view-controller-025 | omits-autosave-for-content-sized-sidebar | Load with `contentSizedSidebar == true` | `splitView.autosaveName` is left unset |
| split-view-controller-026 | caps-content-sized-sidebar-width | `listViewController.preferredWidth()` returns `900`, `minimumSidebarWidthOverride == nil` | Sidebar item's fixed width is `480`, not `900` |
| split-view-controller-027 | unifies-nested-sidebar-widths | Host two nested `SplitViewController` panels whose own `preferredWidth()`s are `180` and `220` | Both nested panels' `minimumSidebarWidthOverride == 220` |
| split-view-controller-028 | raises-detail-floor-for-nested-siblings | Nested siblings as above, each with `detailMinimumThickness == 200` | This instance's `nestedDetailFloor == 420` (`220 + 200`) |
| split-view-controller-029 | floors-detail-pane-thickness | `detailMinimumThickness == 400`, `nestedDetailFloor == 420` | Detail item's `minimumThickness == 420` |
| split-view-controller-030 | selects-first-panel-on-first-appearance | Set two panels via `setPanels(_:)`, then trigger `viewWillAppear` with no prior selection | `panels.first` is shown and selected |
| split-view-controller-031 | repaints-theme-on-appearance-and-change | Switch the active theme after the view has appeared | Window and detail-container backgrounds update to the new theme's `windowBackgroundColor` |
| split-view-controller-032 | replaces-panel-list-atomically | Call `setPanels([a, b])` | `panels == [a, b]`; history is empty; sidebar shows exactly `a` and `b` |
| split-view-controller-033 | appends-without-unnecessary-history-reset | With `sortsPanelsByTitle == false`, navigate to panel `a`, then call `addPanel(c)` | History still shows `a` as current; `c` appended at the end |
| split-view-controller-033b | appends-without-unnecessary-history-reset | With `sortsPanelsByTitle == true`, navigate to panel `a`, then call `addPanel(c)` where `c` sorts before `a` | History is reset; the sidebar re-selects `a` at its new (shifted) index |
| split-view-controller-034 | removes-and-renumbers-selection | Panels `[a, b, c]`, `b` selected, call `removePanel(a)` | `panels == [b, c]`; `b` remains selected at its new index `0` |
| split-view-controller-034b | removes-and-renumbers-selection | Panels `[a, b]`, `b` selected, call `removePanel(b)` | Detail pane is cleared; nothing is selected |
| split-view-controller-035 | sorts-panels-when-configured | `sortsPanelsByTitle == true`; add panels titled `"Zebra"`, `"Apple"` with no section | `panels` order is `["Apple", "Zebra"]` |
| split-view-controller-036 | clears-search-when-restored-selection-is-hidden | Search query hides the currently selected panel, then `removePanel` triggers a restore of that same panel | Search query is cleared before the panel is re-selected |
| split-view-controller-037 | clears-all-panels | Call `clear()` | `panels == []`; detail pane empty; `onNavigationChange` invoked |
| split-view-controller-038 | records-explicit-selection | Call `selectPanel(at: 1)` | History's `current == 1` |
| split-view-controller-039 | steps-through-visible-rows-only | Visible rows are `[0, 2]` (row `1` filtered out), current is `0`, call `moveSelection(by: 1)` | Selection moves to row `2`, not row `1` |
| split-view-controller-039b | steps-through-visible-rows-only | Current selection is the last visible row, call `moveSelection(by: 1)` | No change; selection does not wrap to the first row |
| split-view-controller-040 | preserves-search-during-arrow-navigation | Search query is `"a"`, call `moveSelection(by: 1)` | `listViewController.searchQuery` remains `"a"` |
| split-view-controller-041 | navigates-back-through-history | History has one prior entry, call `goBack()` | The previous panel is shown; history is not appended |
| split-view-controller-042 | navigates-forward-through-history | After a `goBack()`, call `goForward()` | The panel that was current before `goBack()` is shown again |
| split-view-controller-043 | resolves-arrows-to-innermost-active-split | A nested split's own history can go back but the outer split's cannot, call `goBack()` on the outer split | The nested split's `goBack()` behavior runs, not the outer split's |
| split-view-controller-044 | clears-search-on-programmatic-navigation | Search query is `"a"`, call `goBack()` | Search field and `searchQuery` are cleared before the panel is shown |
