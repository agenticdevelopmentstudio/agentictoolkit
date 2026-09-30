<!-- leaf: implement-settings/window--edge-cases · source: settings-window.md -->

# SettingsWindow

**Rules** (cite as `implement-settings/window--edge-cases#<slug>`):

- `null-empty-input` MUST — currentPanelTitle == nil MUST result in the panel-title label showing the empty string, not a placeholder (MUST, see …

## Edge Cases

- **Null/empty input**: `currentPanelTitle == nil` MUST result in the
  panel-title label showing the empty string, not a placeholder (MUST, see
  **shows-current-panel-title**). A `selectedSegment` value of `-1` (no
  selection) on the navigation control MUST trigger neither `goBack()` nor
  `goForward()` (MUST, see **routes-segment-selection-to-navigation**). A
  toolbar request for the sidebar tracking separator when
  `viewController?.splitView` is `nil` MUST return `nil` rather than a
  partially-configured item (MUST, see
  **builds-tracking-separator-from-splitview**).
- **Boundary values**: Not applicable — this file has no numeric,
  countable, or ranged input of its own (two fixed navigation directions and
  one fixed, five-item toolbar list); it defines no minimum/maximum to test
  against.
- **Concurrent access**: The class and its methods are `@MainActor`-isolated
  (as is its `WindowController` superclass), so all mutation runs on the
  main actor; there is no defined behavior for access from another thread,
  and none is needed for an AppKit window controller. Unlike some sibling
  window controllers in this codebase, this file installs no explicit
  reentrancy guard (no in-flight-operation flag) — none is needed because
  every entry point here (`showWindow()`, the toolbar delegate methods, the
  two button actions) runs to completion synchronously before AppKit can
  call back in.
- **Error states**: This file performs no fallible operation of its own — no
  network call, no throwing initializer, no optional force-unwrap outside
  the `guard`-protected `viewController`/`window` accesses already covered
  by the requirements above. It therefore produces no error state to
  communicate to the user; this is what the source does, not an idealized
  claim of error handling that isn't there.
- **Offline/disconnected state**: Not applicable — this file makes no
  network requests.
