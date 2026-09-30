<!-- leaf: implement-git-client/scripting--part-2 · source: git-client-scripting.md -->

# GitClientScripting — continued (part 2)

**Rules** (cite as `implement-git-client/scripting--part-2#<slug>`):

- `window-enumeration-order` MUST
- `window-enumeration-recomputed` MUST
- `window-lookup-short-circuits` MUST
- `window-lookup-miss-returns-nil` MUST
- `tab-enumeration-nests-by-window` MUST
- `tab-branch-resolver-wiring` MUST
- `tab-branch-nil-for-adopted-windows` MUST
- `tab-lookup-short-circuits` MUST
- `tab-lookup-miss-returns-nil` MUST
- `pane-enumeration-tags-source-window` MUST
- `pane-lookup-short-circuits` MUST
- `pane-lookup-miss-returns-nil` MUST
- `main-actor-confinement` MUST
- `window-id-is-project-id` MUST
- `window-degrades-when-controller-is-gone` MUST
- `window-help-visible-round-trips` MUST
- `window-drawer-tab-read-only` MUST
- `window-search-query-round-trips` MUST
- `window-selected-tab-round-trips` MUST
- `window-object-specifier-key` MUST
- `tab-value-rebuilt-per-read` MUST
- `tab-id-is-the-group-id` MUST
- `tab-edges-may-be-empty` MUST
- `tab-branch-empty-when-unresolved` MUST
- `tab-object-specifier-key` MUST
- `pane-requires-its-enumerating-window` MUST
- `pane-view-controller-held-strongly-window-held-weakly` MUST
- `pane-project-and-tab-derived-live` MUST
- `pane-selection-empty-when-nothing-selected` MUST
- `pane-minimized-is-edge-name-or-no` MUST

## Behavioral Requirements

- **window-enumeration-order**: `scriptableProjectWindows` MUST map every
  controller in `openWindowControllers`, in that array's order, to one
  `ScriptableProjectWindow(controller:)` (`ProjectWindowManager+Scripting.swift`). `openWindowControllers` itself is `openOrder.compactMap {
  controllers[$0] }` — the order projects were opened in, not dictionary
  order (`ProjectWindowManager.swift` and its preceding comment).
- **window-enumeration-recomputed**: `scriptableProjectWindows` MUST be
  recomputed from `openWindowControllers` on every access; it is a computed
  property with no backing cache, so a window opened or closed between two
  reads MUST be reflected in the very next read (`ProjectWindowManager+Scripting.swift`).
- **window-lookup-short-circuits**: `scriptableProjectWindow(uniqueID:)` MUST
  search `openWindowControllers.lazy.map(ScriptableProjectWindow.init(controller:))`
  and stop at the first wrapper whose `uniqueID` equals the argument, so a
  match at position *n* MUST NOT cause a `ScriptableProjectWindow` to be
  constructed for any controller after it (`ProjectWindowManager+Scripting.swift`).
- **window-lookup-miss-returns-nil**: `scriptableProjectWindow(uniqueID:)`
  MUST return `nil` when no open window's `uniqueID` equals the argument,
  including when the argument is not a well-formed UUID string — the search
  is a plain string comparison, not a UUID parse, so it MUST NOT throw or
  crash on a malformed argument (`ProjectWindowManager+Scripting.swift`).
- **tab-enumeration-nests-by-window**: `scriptableProjectTabs` MUST flat-map
  `openWindowControllers` through `scriptingTabs(of:)`, so the result is
  every window's tabs, windows in `openWindowControllers` order and, within
  one window, in that window's own tab-group order
  (`ProjectWindowManager+Scripting.swift`).
- **tab-branch-resolver-wiring**: `scriptingTabs(of:)` MUST look up
  `self.projectController(for: controller.project.id)` once per window, and
  MUST pass `scriptingTabs(branch:)` a closure that, for a tab's working
  directory `directory`, evaluates `projectController?.branchController(forDirectory:
  directory)?.currentBranch` (`ProjectWindowManager+Scripting.swift`).
- **tab-branch-nil-for-adopted-windows**: Because `projectController(for:)`
  returns `nil` for a window `adoptForScripting(_:)` registered rather than a
  window this manager opened (`ProjectWindowManager.swift` and
  their preceding comment), every tab belonging to an adopted-only window
  MUST resolve its branch closure to `nil`, which `ComposableTabsWindowController.scriptingTabs(branch:)`
  then reports as the empty string (see **tab-branch-empty-when-unresolved**).
- **tab-lookup-short-circuits**: `scriptableProjectTab(uniqueID:)` MUST walk
  `openWindowControllers.lazy.flatMap { self.scriptingTabs(of: $0) }` and stop
  at the first tab whose `uniqueID` equals the argument, so tabs in windows
  after the match MUST NOT be built (`ProjectWindowManager+Scripting.swift`).
- **tab-lookup-miss-returns-nil**: `scriptableProjectTab(uniqueID:)` MUST
  return `nil` when no open tab's `uniqueID` equals the argument
  (`ProjectWindowManager+Scripting.swift`).
- **pane-enumeration-tags-source-window**: `scriptablePanes` MUST flat-map
  `openWindowControllers`, and for each window MUST map every pane in that
  window's `allPanes()` to `ScriptablePane(pane:in: window)`, tagging each
  wrapper with the exact window it was enumerated from rather than leaving the
  wrapper to discover its own window (`ProjectWindowManager+Scripting.swift`).
- **pane-lookup-short-circuits**: `scriptablePane(uniqueID:)` MUST walk
  `openWindowControllers.lazy.flatMap { window in window.allPanes().lazy.map
  { ScriptablePane(pane: $0, in: window) } }` and stop at the first pane
  whose `uniqueID` equals the argument (`ProjectWindowManager+Scripting.swift`).
- **pane-lookup-miss-returns-nil**: `scriptablePane(uniqueID:)` MUST return
  `nil` when no open pane's `uniqueID` equals the argument
  (`ProjectWindowManager+Scripting.swift`).
- **main-actor-confinement**: Every member of this extension, and every
  member of `ScriptableProjectWindow`, `ScriptableProjectTab` and
  `ScriptablePane`, MUST run on the main actor: `ProjectWindowManager` is
  declared `@MainActor` (`ProjectWindowManager.swift`) with no
  `Sendable` conformance, and each of the three wrapper classes independently
  repeats the `@MainActor` declaration on itself (`ScriptableProjectWindow.swift`, `ScriptableProjectTab.swift`, `ScriptablePane.swift`). None of the four types MUST be called from a non-main-actor context.
- **window-id-is-project-id**: `ScriptableProjectWindow.uniqueID` MUST return
  `self.controller?.project.id.uuidString`, falling back to `""` when
  `controller` is `nil` — the persisted `git_repo.id`, so one window's id is
  always its project's id (`ScriptableProjectWindow.swift`).
- **window-degrades-when-controller-is-gone**: Because `controller` is held
  `weak`, every `ScriptableProjectWindow` property (`uniqueID`, `name`,
  `helpVisible`, `drawerTab`, `searchQuery`, `selectedTab`) MUST fall back to
  `""` (or `false` for `helpVisible`) rather than force-unwrap or crash once
  the underlying `ComposableTabsWindowController` has been deallocated
  (`ScriptableProjectWindow.swift`).
- **window-help-visible-round-trips**: `ScriptableProjectWindow.helpVisible`
  MUST get `controller.isHelpVisible` and MUST set through
  `controller.setHelpVisible(newValue)`, defaulting to `false` when
  `controller` is `nil` (`ScriptableProjectWindow.swift`).
- **window-drawer-tab-read-only**: `ScriptableProjectWindow.drawerTab` MUST
  expose `controller.helpDrawerTabID` as a read-only `String`, defaulting to
  `""`, and MUST NOT declare a setter — Help is documented as the only legal
  tab, so a setter would have exactly one legal value it could accept
  (`ScriptableProjectWindow.swift`).
- **window-search-query-round-trips**: `ScriptableProjectWindow.searchQuery`
  MUST get and set `controller.searchQuery` directly, so setting it MUST
  route through whatever `searchQuery`'s own setter on `ComposableTabsWindowController`
  does (routing the search), not merely record a string
  (`ScriptableProjectWindow.swift`).
- **window-selected-tab-round-trips**: `ScriptableProjectWindow.selectedTab`
  MUST get and set `controller.selectedTabIdentifier`, defaulting to `""`
  when `controller` is `nil` (`ScriptableProjectWindow.swift`).
- **window-object-specifier-key**: `ScriptableProjectWindow.objectSpecifier`
  MUST build its `NSScriptObjectSpecifier` via `applicationElementSpecifier(key:
  "projectWindows") { self.uniqueID }` (`ScriptableProjectWindow.swift`; see `agentictoolkit://recipes/foundation-scripting` for that
  helper's own contract).
- **tab-value-rebuilt-per-read**: `ScriptableProjectTab` MUST be constructed
  fresh on every `scriptingTabs`/`scriptableProjectTabs`/`scriptableProjectTab(uniqueID:)`
  call, with all six fields (`id`, `title`, `edges`, `project`,
  `workingDirectory`, `branch`) fixed at `init` and never mutated afterward —
  it is a value snapshot, not a cache that a later tab rename would have to
  invalidate (`ScriptableProjectTab.swift`).
- **tab-id-is-the-group-id**: `ScriptableProjectTab.uniqueID` MUST be the tab
  *group's* id (the persisted `project_tabs.group_id`), never a per-edge
  member row's id, because one project-level tab drawn on several edges is
  one tab to a script, not one per edge (`ScriptableProjectTab.swift`).
- **tab-edges-may-be-empty**: `ScriptableProjectTab.tabEdges` MUST report the
  current set of edges that tab group is drawn on, and an empty array MUST be
  a valid result when every edge the group could draw on has been disabled
  (`ScriptableProjectTab.swift`).
- **tab-branch-empty-when-unresolved**: `ComposableTabsWindowController.scriptingTabs(branch:)`
  (the direct caller of the closure this extension supplies) MUST fold a
  `nil` branch result to the empty string `""` on the `ScriptableProjectTab`
  it builds (`ComposableTabsWindowController.swift`'s `branch(directory)
  ?? ""`), so a directory that resolves to no `ProjectController`, no
  `BranchController` for that directory, or a `BranchController` whose
  checkout is on a detached HEAD (`currentBranch == nil`, see
  `agentictoolkit://recipes/git-client-projects-branch-controller`) all
  collapse to the same observable value: an empty string, never `nil`
  stringified and never a thrown error.
- **tab-object-specifier-key**: `ScriptableProjectTab.objectSpecifier` MUST
  build its `NSScriptObjectSpecifier` via `applicationElementSpecifier(key:
  "projectTabs") { self.uniqueID }` (`ScriptableProjectTab.swift`).
- **pane-requires-its-enumerating-window**: `ScriptablePane.init(pane:in:)`
  MUST take the `ComposableTabsWindowController` the pane was found in as a
  required, non-optional parameter — a pane behind a background tab has
  never been in a view hierarchy, so a wrapper left to discover its own
  window through the view would report an empty project and tab for most
  panes in a real window (`ScriptablePane.swift`).
- **pane-view-controller-held-strongly-window-held-weakly**: `ScriptablePane`
  MUST hold its wrapped `ComposableTabsPaneViewController` (`pane`) strongly
  and its enumerating `window` weakly — the opposite asymmetry from
  `ScriptableProjectWindow`, which holds its controller weakly
  (`ScriptablePane.swift`).
- **pane-project-and-tab-derived-live**: `ScriptablePane.paneProject` MUST
  return `self.window?.project.displayName ?? ""`, and `ScriptablePane.paneTab`
  MUST return `self.window?.tabGroup(containing: self.pane)?.title ?? ""`,
  both computed fresh from the tagged window on every access rather than
  captured once at enumeration time (`ScriptablePane.swift`).
- **pane-selection-empty-when-nothing-selected**: `ScriptablePane.paneSelection`
  MUST return `self.pane.selectionDescription ?? ""`, treating "nothing
  selected" as the empty string rather than a missing value
  (`ScriptablePane.swift`).
- **pane-minimized-is-edge-name-or-no**: `ScriptablePane.paneMinimized` MUST
  return `self.pane.minimizedEdge?.rawValue ?? "no"` — one string, not a
  boolean plus an edge, because "minimized" and "minimized where" are one
  fact that two separate properties could disagree about
  (`ScriptablePane.swift`).
