<!-- leaf: implement-git-client/scripting--edge-cases · source: git-client-scripting.md -->

# GitClientScripting

**Rules** (cite as `implement-git-client/scripting--edge-cases#<slug>`):

- `null-and-empty-input` MUST — No open project windows leaves scriptableProjectWindows, scriptableProjectTabs and scriptablePanes all empty arrays, …
- `boundary-values` MUST — A tab group MAY be drawn on zero edges (tab-edges-may-be-empty) after every edge is disabled, in which case …
- `concurrent-access` MUST — Every operation in this file, and on all three wrapper types, is confined to the main actor (MUST, see …
- `error-states` MUST — This file defines no throws function and surfaces no Error type of its own. A branch that cannot be resolved — no …
- `a-pane-tab-or-window-that-has-closed-between-enumeration-and-use` MUST — A ScriptableProjectWindow's weak var controller MAY become nil between when a script is handed the wrapper and when it …

## Edge Cases

- **Null and empty input**: No open project windows leaves `scriptableProjectWindows`,
  `scriptableProjectTabs` and `scriptablePanes` all empty arrays, and every
  `*(uniqueID:)` lookup returns `nil` (MUST; the enumerations and lookups are
  plain `map`/`flatMap`/`first` over `openWindowControllers`, which is itself
  `[]` when nothing is open). A `uniqueID` argument that is the empty string
  or any other non-matching string is handled by the same string-equality
  comparison as any other miss — it MUST return `nil`, never throw (MUST, see
  **window-lookup-miss-returns-nil**, **tab-lookup-miss-returns-nil**,
  **pane-lookup-miss-returns-nil**).
- **Boundary values**: A tab group MAY be drawn on zero edges
  (**tab-edges-may-be-empty**) after every edge is disabled, in which case
  `scriptablePanes` for that tab group's window contributes zero panes for
  that tab while `scriptableProjectTabs` still lists the tab itself (MUST).
  There is no maximum enforced on the number of open windows, tabs per
  window, or panes per tab in this file — enumeration is a linear walk with
  no capacity limit.
- **Concurrent access**: Every operation in this file, and on all three
  wrapper types, is confined to the main actor (MUST, see
  **main-actor-confinement**); Cocoa Scripting itself dispatches command
  handlers on the main thread (see `agentictoolkit://recipes/foundation-scripting`),
  so no two enumerations or lookups from this surface can interleave with
  each other or with a window opening or closing. There is no lock, queue, or
  actor state defined in this file itself — main-actor confinement is the
  entire concurrency story.
- **Error states**: This file defines no `throws` function and surfaces no
  `Error` type of its own. A branch that cannot be resolved — no
  `ProjectController` for the window, no `BranchController` for the
  directory, or a detached-HEAD checkout — is not an error condition here;
  it is folded to the empty string before it would ever reach this file's
  callers (MUST, see **tab-branch-empty-when-unresolved**). Any
  `GitClientError` a git subprocess could raise is fully absorbed inside
  `BranchController.refresh()` before `currentBranch` is ever read by this
  extension (see `agentictoolkit://recipes/git-client-projects-branch-controller`);
  none of it is observable through `ScriptableProjectTab.tabBranch`.
- **Offline or disconnected state**: Not applicable in the network sense —
  nothing in `ProjectWindowManager+Scripting.swift` makes a network call.
  Git itself is local-only, and even that local subprocess call happens one
  layer below this file, inside `BranchController`/`GitClient`; this
  extension only reads an already-resolved `currentBranch` snapshot.
- **A pane, tab or window that has closed between enumeration and use**: A
  `ScriptableProjectWindow`'s `weak var controller` MAY become `nil` between
  when a script is handed the wrapper and when it reads a property from it,
  because a script "can keep a reference to a window it then closes"
  (`ScriptableProjectWindow.swift`); every property degrades to its
  documented fallback rather than crashing (MUST, see
  **window-degrades-when-controller-is-gone**). `ScriptablePane.isInWindow`
  exists specifically because `closePane()`'s effect can be silently
  declined by the host, so "the request was delivered" and "the pane is
  gone" are answered by two different questions (MUST, see
  **pane-is-in-window-reasks-live-membership**).
