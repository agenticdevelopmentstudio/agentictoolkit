<!-- leaf: implement-window/explorer-view--edge-cases · source: window-explorer-view.md -->

# WindowExplorerView

**Rules** (cite as `implement-window/explorer-view--edge-cases#<slug>`):

- `null-empty-input` MUST — excludeWindowIDs defaults to an empty set (no windows excluded by id). selectedWindowIDs may start empty (no rows …
- `boundary-values` MUST — a window exactly 50 points wide or exactly 50 points tall MUST be excluded, because the filter uses strict > 50 on both …

## Edge Cases

- **Null/empty input**: `excludeWindowIDs` defaults to an empty set (no
  windows excluded by id). `selectedWindowIDs` may start empty (no rows
  checked). A window whose `title` is the empty string MUST render
  "(untitled)" (`window-row`). An `appGroups` result of `[]` MUST
  show the empty state (`empty-state`).
- **Boundary values**: a window exactly 50 points wide or exactly 50 points
  tall MUST be excluded, because the filter uses strict `> 50` on both axes
  (`scan-window-filter`). An AX-to-CG frame difference of exactly 3
  points on any one of x, y, width, or height MUST NOT count as a match,
  because the tolerance check uses strict `< 3`
  (`accessibility-title-match`).
- **Concurrent access**: `refreshAsync()` has no guard against being invoked
  again while a previous scan is still running — it can be triggered
  independently by `.onAppear`, app activation, an external
  `refreshNotification`, and the manual refresh button. Each invocation
  spawns its own `Task.detached` and unconditionally overwrites `appGroups`,
  `needsAccessibility`, and `isLoading` on the main actor when it finishes;
  the source neither cancels an in-flight scan nor coalesces overlapping
  ones, so the last scan to complete determines the final state. No
  debounce or cancellation exists to change this — this is observed
  behavior of the current implementation, not a documented requirement, and
  overlapping scans racing to determine the final state is a likely source
  of surprising results rather than an intended contract.
- **Error states**: `AXUIElementCopyAttributeValue` failing for a given
  process is handled by silently `continue`-ing past that process (no error
  is surfaced to the caller or user). Whether the Accessibility banner
  appears at all depends on `axSucceeded`, which is set `true` if *any*
  process's AX query succeeded during the scan — so if some processes
  succeed and others fail, the banner is never shown even though the
  windows belonging to the failed processes keep their unenriched
  CoreGraphics titles. This is a per-scan flag, not a per-app one, and is
  the current implementation's behavior rather than a designed requirement:
  a user with some processes failing AX queries sees no indication that any
  titles are unenriched.
- **Offline/disconnected state**: Not applicable — the view performs no
  network requests; window enumeration and Accessibility queries are local
  system calls only.
