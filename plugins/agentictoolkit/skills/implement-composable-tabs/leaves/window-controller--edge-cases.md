<!-- leaf: implement-composable-tabs/window-controller--edge-cases · source: composable-tabs-window-controller.md -->

# ComposableTabsWindowController

**Rules** (cite as `implement-composable-tabs/window-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — selectTab(id:) and the selectedTabIdentifier setter with an id that names no group in this window MUST be ignored …
- `boundary-values` MUST — exactly one remaining tab group MUST refuse to close (MUST); exactly one remaining enabled edge MUST refuse to disable …
- `concurrent-access` MUST — the controller is @MainActor-isolated; every mutation (tab add/remove/select, edge toggle, persistence) runs on the …

## Edge Cases

- **Null/empty input**: `selectTab(id:)` and the `selectedTabIdentifier`
  setter with an id that names no group in this window MUST be ignored
  (MUST) rather than clearing the current selection. `panes(inTab:)` with an
  unparsable or unknown identifier MUST return an empty array (MUST). An
  `enabledTabEdgeNames` assignment MUST NOT trip the last-enabled-edge
  refusal partway through, because enables are applied before disables
  (MUST) — see **edge-set-assignment-order**.
- **Boundary values**: exactly one remaining tab group MUST refuse to close
  (MUST); exactly one remaining enabled edge MUST refuse to disable (MUST).
  These are the only two lower-bound guards in the source; no upper bound on
  tab or edge count exists.
- **Concurrent access**: the controller is `@MainActor`-isolated; every
  mutation (tab add/remove/select, edge toggle, persistence) runs on the
  main actor, so there is no defined behavior for access from another
  thread — none is needed, because AppKit view controllers are inherently
  single-threaded. Within the main actor, reentrancy during a single
  operation is guarded explicitly: `isReloadingTabs` suppresses side effects
  while `reloadTabs()` removes tabs, `isMirroringArrangement` stops the
  arrangement mirror from recursing into itself, and `isClosing` stops a
  closing window's own teardown from re-persisting a stale tab set (MUST for
  each guard, as implemented).
- **Error states**: `project.setSetting(_:to:)` and `project.persistTabs(...)`
  are called without checking a return value or catching an error anywhere
  in this file; per the source's own comments, `setSetting` "swallows its
  errors." A persistence failure therefore produces no user-facing error, no
  retry, and no logged diagnostic — this is what the source does, not an
  idealized error-handling requirement. This is recorded as accepted debt in
  Design Decisions above, not treated as an unresolved gap.
- **Offline/disconnected state**: Not applicable — the controller performs
  no network requests; all persistence (window frame, tab layout, drawer
  prefs) is local.
