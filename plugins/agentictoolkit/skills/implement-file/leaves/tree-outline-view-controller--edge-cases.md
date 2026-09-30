<!-- leaf: implement-file/tree-outline-view-controller--edge-cases · source: file-tree-outline-view-controller.md -->

# File Tree Outline View Controller

## Edge Cases

- **Null/empty input**: An empty root (no `rootNode`, or `rootNode.children`
  empty) renders the placeholder row rather than zero rows (see
  `empty-root-placeholder-text`); the placeholder is never selectable and
  never opens anything. `restoreDisclosure()` doing nothing further once
  there is no pending restored selection, and a document event with an
  unparseable URI being silently ignored, are covered as named requirements
  above (see **restore-disclosure-noop-without-pending** and
  **document-event-ignores-unparseable-uri**).
- **Boundary values**: The one-shot auto-expand
  (`lone-root-auto-expands-once`) only applies when there is exactly one root
  manager and `restoration.expandedPaths` is empty; a browser with two or
  more roots always starts fully collapsed unless `restoration` says
  otherwise. Restoring a selection many directory levels deep has no explicit
  maximum-depth cap in source; it is bounded only by how many reload cycles
  the real directory depth requires (`restore-descends-incrementally`).
- **Concurrent access**: This controller, `FileTreeManager`,
  `FileBrowserSelection`, `FileBrowserRestorationState`, and
  `TextDocumentStore` are all `@MainActor`-isolated, and every Combine
  subscription this file installs additionally hops
  `.receive(on: RunLoop.main)`. `FileTreeNode.loadChildrenIfNeeded()` performs
  its filesystem read on a background queue but publishes the result back via
  `DispatchQueue.main.async`, so this controller never observes a children
  update off the main thread. Multiple browser panes can share one
  `FileBrowserSelection`/`FileBrowserRestorationState`; a selection or
  disclosure change made by one pane's outline is observed and mirrored by
  every other pane's own `isSyncingSelection`/`isSyncingExpansion`-guarded
  code path, so cross-pane updates highlight/disclose without looping back
  into a second write.
- **Error states**: A directory whose contents cannot be read (for example,
  permission denied) is rendered identically to a genuinely empty directory —
  the "Empty" placeholder — because `FileTreeNode.loadChildren` swallows a
  `contentsOfDirectory` failure into an empty array before it ever reaches
  this controller; this component surfaces no distinct error state or
  affordance for that case. A context-menu action for a path that no longer
  exists on disk produces no menu items rather than an error dialog (see
  `context-menu-omitted-for-missing-path`). If the row selected before a
  reload can no longer be found by identity or by path, the component treats
  that as "the user's file is gone" and clears the selection
  (`reload-clears-selection-when-row-gone`) rather than treating it as an
  error condition.
- **Offline/disconnected state**: Not applicable. This component reads and
  watches the local filesystem only; it makes no network requests, so there
  is no connectivity-loss behavior to define here.
