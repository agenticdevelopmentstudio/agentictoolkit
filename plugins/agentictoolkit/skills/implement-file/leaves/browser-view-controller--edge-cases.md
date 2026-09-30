<!-- leaf: implement-file/browser-view-controller--edge-cases · source: file-browser-view-controller.md -->

# File Browser View Controller

**Rules** (cite as `implement-file/browser-view-controller--edge-cases#<slug>`):

- `null-empty-input` MUST — Calling addDirectory() and confirming the panel with zero URLs selected is not reachable through NSOpenPanel (it …
- `boundary-values` MUST — Selecting many directories at once in the open panel (allowsMultipleSelection: true) MUST add every one not already …
- `concurrent-access` SHOULD — directories.$additional is observed on the main queue (receive(on: DispatchQueue.main)) before triggering …

## Edge Cases

- **Null/empty input**: Calling `addDirectory()` and confirming the panel
  with zero URLs selected is not reachable through `NSOpenPanel` (it requires
  at least one choice to return `.OK`); `directories.all` is unaffected in
  that case. Calling `removeSelectedDirectory()` with no selection (`nil`)
  MUST refuse via `RefusalFeedback.announce()` (see
  `remove-directory-requires-selected-root`).
- **Boundary values**: Selecting many directories at once in the open panel
  (`allowsMultipleSelection: true`) MUST add every one not already present,
  in the order the panel returns them (per
  `add-directory-preserves-panel-order`), and MUST select only the last one
  (per `add-directory-selects-last-added`) even when several are added in a
  single call.
- **Concurrent access**: `directories.$additional` is observed on the main
  queue (`receive(on: DispatchQueue.main)`) before triggering
  `rebuildManagers()`, and `FileBrowserDirectories`/`FileBrowserSelection`
  are `@MainActor`-isolated `ObservableObject`s. Multiple browser panes of
  the same project can share one `FileBrowserDirectories`/
  `FileBrowserSelection`/`FileBrowserRestorationState`; when one pane adds or
  removes a root, every other pane observing the same objects rebuilds its
  own managers and clears any of its own selection state that pointed under
  the removed root (`teardown-clears-orphaned-node-selection`,
  `teardown-clears-orphaned-root-selection`). This is stated as
  `multi-pane-consistency`, a SHOULD-level guarantee for multi-pane hosts:
  the source comments describe it as the reason those two clears exist, but
  no explicit test in the given source exercises two live controllers at
  once.
- **Error states**: The open panel returning anything other than `.OK`
  (Cancel) is treated as a no-op, not an error — no dialog is shown. A
  directory the user already added is likewise treated as a no-op, not an
  error. Removing a non-removable or unselected root produces a
  `RefusalFeedback.announce()` (by default, `NSSound.beep()`), not a modal
  error. If `injectedGitStatusProvider`'s `repoRoot` fails to match a new
  root, the component does not raise an error; it simply omits the provider
  (`git-status-provider-reuse`), leaving whatever the manager does with
  `nil` (constructing its own) out of this component's scope.
- **Offline/disconnected state**: Not applicable. This component reads and
  watches the local filesystem only; it makes no network requests, so there
  is no connectivity-loss behavior to define here. (Git status refreshes are
  the concern of the injected/constructed `GitStatusProvider`, a separate
  component.)
