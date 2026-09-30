<!-- leaf: implement-composable-tabs/pane-view-controller--edge-cases · source: composable-tabs-pane-view-controller.md -->

# ComposableTabsPaneViewController

**Rules** (cite as `implement-composable-tabs/pane-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — project deallocated before loadView() runs — makeContentViewController() returns nil rather than force-unwrapping …
- `boundary-values` MUST — paneIndex nil is the common, unnumbered case; a non-nil index changes the accessibility identifier's shape (MUST, see …

## Edge Cases

- **Null/empty input**: `project` deallocated before `loadView()` runs — `makeContentViewController()` returns nil rather than force-unwrapping (MUST, see `content-nil-without-project`). `layoutOverride` nil — content and `paneName` fall back to `project.layout`, and `paneName` falls back further to a placeholder-only layout if `project` is also gone. Computed Add choices empty — `presentAddSheet()` refuses rather than presenting an empty picker (MUST, see `add-refused-when-empty`).
- **Boundary values**: `paneIndex` nil is the common, unnumbered case; a non-nil index changes the accessibility identifier's shape (MUST, see `accessibility-id-includes-pane-index`). A tab with exactly one pane makes `canRemoveLeaf` refuse removal of that pane. A pane at the top of a column has no `Up`/`.above` direction available, so the corresponding gear-menu and overlay controls are disabled rather than absent.
- **Concurrent access**: This class is `@MainActor`-isolated, and every piece of mutable state it owns (`paneIndex`, `arrangeOverlay`, `cancellables`, `arrowKeyMonitor`, `stateOwnerNodeID`) is read and written only on the main actor, so there is no concurrent-access hazard by construction. The one boundary crossing is the local `keyDown` monitor's closure, which AppKit invokes `nonisolated`; the source re-enters isolation with `MainActor.assumeIsolated` to run `handleKeyDown(_:)` and only a plain `Bool` crosses back out, because `NSEvent` itself is not `Sendable`.
- **Error states**: When the enclosing split refuses a move, reports Add has no legal choices, or reports Remove is not currently legal, the only surfaced error is `RefusalFeedback.announce()` (default: `NSSound.beep()`) — there is no inline error message, banner, or thrown error anywhere in this file for these cases, and the recipe describes that as-is rather than as an idealized richer error UI.
- **Offline or disconnected state**: Not applicable. This component makes no network requests; its only persistence (pane chrome state, through the inherited `PaneStateStore`) goes through `ProjectPaneStateStore` into the project's local database, and nothing in this file or its immediate collaborators references a network resource.
