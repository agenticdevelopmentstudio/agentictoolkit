<!-- leaf: implement-git-client/projects-project-chooser-window--edge-cases · source: git-client-projects-project-chooser-window.md -->

# ProjectChooserWindow

**Rules** (cite as `implement-git-client/projects-project-chooser-window--edge-cases#<slug>`):

- `null-and-empty-input` MUST — A ProjectsCoordinator whose repos is empty at construction leaves the browser's selection nil, so openButton.isEnabled …
- `boundary-values` MUST — window.minSize fixes the one numeric boundary this file defines: AppKit MUST prevent the window from being resized …

## Edge Cases

- **Null and empty input**: A `ProjectsCoordinator` whose `repos` is empty
  at construction leaves the browser's selection `nil`, so
  `openButton.isEnabled` MUST stay `false` through `loadView()` (see
  **open-button-enablement-tracks-selection**); Cancel MUST remain fully
  functional regardless (see **cancel-button-forwards-nil**). `runModal()`'s
  `guard let window else { return nil }` MUST return `nil` if
  `window` were ever `nil`, but in practice `init(coordinator:)` always
  calls `super.init(window:)` with a concrete, non-optional window and no other initializer path exists (`init?(coder:)` is
  unavailable), so this guard is a defensive check on a case the file's own
  contract never actually produces.
- **Boundary values**: `window.minSize` fixes the one numeric boundary this
  file defines: AppKit MUST prevent the window from being resized below
  360×300 even though it opens at 460×480 (see
  **window-identity-fixed-at-init**). The number of projects in
  `coordinator.repos` — zero, one, or many — imposes no boundary of its own
  on this file; scale limits on the project list belong to
  `ProjectBrowserViewController`, not to this window.
- **Concurrent access**: Every mutation of `chosen` and every access to
  `content`/`browser`/`openButton` is confined to the main actor by
  `@MainActor` (see **main-actor-isolation**), so no interleaving on this
  file's own state can be observed torn. Neither `ProjectChooserWindow.choose(from:onChoose:)`
  nor `ProjectsCoordinator.showProjectChooser()` guards against being
  invoked a second time before the first session ends — unlike
  `ProjectsCoordinator.scan()`'s `guard !isScanning` — so two rapid
  invocations (for example, the "Open Project…" command fired twice before
  the first window paints) construct two independent `ProjectChooserWindow`
  instances and stack two nested `NSApp.runModal` sessions; AppKit resolves
  this deterministically (last-opened is topmost and must be dismissed
  before the previous session resumes — see
  **window-close-ignored-when-not-active-modal-session**), but the two
  windows and their buttons carry identical, non-instance-scoped
  accessibility identifiers (see **accessibility-identifiers-fixed**), so
  automation driven by those identifiers alone cannot distinguish the two
  simultaneously open chooser windows.
- **Error states**: `ProjectChooserWindow.swift` makes no call that can
  throw and defines no error type of its own; it reads `coordinator.repos`
  only indirectly, through the `ProjectBrowserViewController` it hosts, and
  that property is a non-throwing, already-materialized array — any failure
  in producing it (a scan error, a database read error) happens upstream in
  `ProjectsCoordinator` and `ProjectDatabase`, entirely out of this file's
  view.
- **Offline or disconnected state**: Not applicable — this file makes no
  network request. It only reads local, in-memory state
  (`ProjectsCoordinator.repos`) through the browser it hosts and has no
  notion of connectivity of its own.
