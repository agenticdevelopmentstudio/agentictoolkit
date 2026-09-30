<!-- leaf: implement-file/browser-view-controller--test-vectors · source: file-browser-view-controller.md -->

# File Browser View Controller

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-browser-001 | tree-divider-footer-layout | Load the view. | Tree view, then a 1pt separator, then the footer, stacked top to bottom and each pinned leading/trailing to the container. |
| file-browser-002 | window-background-fill | Load the view, inspect the root container's layer background. | Background color equals the current theme's `.windowBackground` role color. |
| file-browser-003 | footer-surface-fill | Load the view, inspect the footer view's layer background. | Background color equals the current theme's `.surface` role color. |
| file-browser-004 | one-manager-per-root | Construct with a primary root and two additional directories. | Exactly one manager backs each of the 3 roots (primary and both additional) — each root loads and can be watched independently (see file-browser-006 and file-browser-009), never sharing a manager with another root or going without one. |
| file-browser-005 | primary-root-always-managed | Read `manager` immediately after construction. | Returns the `FileTreeManager` for `directories.primary`, never `nil` and never a crash. |
| file-browser-006 | start-watching-on-appear | Call `viewWillAppear()` on a controller not currently watching. | Every manager for a current root receives `startWatching()`. |
| file-browser-007 | stop-watching-on-disappear | Call `viewDidDisappear()` while watching. | Every manager receives `stopWatching()`. |
| file-browser-008 | stop-watching-on-pane-teardown | Call `paneContentWillBeDiscarded()` while watching, without a prior `viewDidDisappear()`. | Every manager receives `stopWatching()`. |
| file-browser-009 | load-initial-once | Call `viewWillAppear()` twice in a row. | `loadInitial()` is called on each manager exactly once (only on the first call). |
| file-browser-010 | add-directory-opens-panel | Call `addDirectory()`. | An `NSOpenPanel` is shown with `canChooseDirectories == true`, `canChooseFiles == false`, `allowsMultipleSelection == true`. |
| file-browser-011 | add-directory-cancel-noop | Call `addDirectory()`, dismiss the panel with Cancel. | `directories.additional` is unchanged before and after the call. |
| file-browser-012 | add-directory-skips-duplicates | Call `addDirectory()`, choose a directory already in `directories.all`. | `directories.additional` is unchanged; no error is presented. |
| file-browser-013 | add-directory-selects-last-added | Call `addDirectory()`, choose one new directory and confirm. | `selection.selectedRoot` equals the chosen directory. |
| file-browser-014 | remove-directory-requires-selected-root | Set `selection.selectedRoot = nil`, call `removeSelectedDirectory()`. | `RefusalFeedback.announce()` is invoked; `directories` is unchanged. |
| file-browser-015 | remove-directory-requires-removable-root | Set `selection.selectedRoot` to `directories.primary`, call `removeSelectedDirectory()`. | `RefusalFeedback.announce()` is invoked; `directories` is unchanged. |
| file-browser-016 | remove-directory-clears-selection | Set `selection.selectedRoot` to a user-added root, call `removeSelectedDirectory()`. | The root is removed from `directories.additional`; `selection.selectedRoot` becomes `nil`. |
| file-browser-017 | remove-button-enablement | Set `selection.selectedRoot` to a user-added root, then to `nil`. | Remove button's `isEnabled` is `true`, then `false`. |
| file-browser-018 | remove-button-tooltip | Set `selection.selectedRoot` to a user-added directory named `Notes`. | Remove button's tooltip reads `Remove "Notes" from this project`. |
| file-browser-019 | footer-buttons-identified | Load the view, inspect the footer buttons. | Add button's accessibility identifier is `file-browser.add-directory`; remove button's is `file-browser.remove-directory`. |
| file-browser-020 | teardown-clears-orphaned-node-selection | Select a file under a user-added root, then remove that root from `directories`. | `selection.selectedNode` becomes `nil`. |
| file-browser-021 | teardown-clears-orphaned-root-selection | Set `selection.selectedRoot` to a user-added root, then remove that same root. | `selection.selectedRoot` becomes `nil`. |
| file-browser-022 | late-added-root-loads-if-visible | After the browser has completed its initial load, add a new directory. | The new root's manager has `loadInitial()` called on it. |
| file-browser-023 | late-added-root-watches-if-visible | While the browser is actively watching, add a new directory. | The new root's manager has `startWatching()` called on it. |
| file-browser-024 | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` (symlink-resolved) matches the primary root; construct the browser. | The primary root's manager is built with that provider. |
| file-browser-024b | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` does not match any root. | Every manager is built with `nil` for `gitStatusProvider`. |
| file-browser-025 | open-request-forwarding | Set `controller.onOpenRequest` to a closure that records its arguments, then have the hosted tree fire its own `onOpenRequest` (e.g. by triggering an open from the tree). | The recorded arguments match what the tree fired — `controller.onOpenRequest` reads/writes `tree.onOpenRequest` directly, with no second copy of the closure (see **open-request-forwarding**). |
| file-browser-026 | reveal-forwarding | Call `controller.reveal(someURL)`. | The hosted tree's `reveal(_:)` is invoked with `someURL`. |
| file-browser-027 | pane-selection-change-notification | Install `onPaneSelectionChange`, then set `selection.selectedNode` to a new value, then set it again to the same value. | Callback fires once, for the first change only. Because the forwarding hops through `RunLoop.main`, the test must drain the run loop (or await) after each `selectedNode` assignment before asserting, rather than checking synchronously. |
| file-browser-028 | pane-selection-description | Select a node whose `url` is `/a/b/File.swift`. | `paneSelectionDescription` returns `"File.swift"`, not the full path. |
| file-browser-029 | coder-init-unavailable | Inspect `init(coder:)`'s declaration (a static/API-surface check, not a runtime-executable test). | It is marked `@available(*, unavailable)`, so any call site invoking it fails to compile; a runtime `fatalError` fires only if that unavailability is bypassed. |
| file-browser-030 | reuse-managers-across-rebuild | Add a directory, capture the primary root's manager instance, then add a second directory. | The primary root's manager instance after the second add is the same instance as before (identity-equal). |
| file-browser-031 | single-root-convenience-init | Construct with `init(rootURL:excludedURL:documentStore:)`. | `directories.primary == rootURL` and `directories.additional` is empty. |
| file-browser-032 | add-directory-preserves-panel-order | Call `addDirectory()`, choose three new directories in a specific order (none yet in `directories.all`). | `directories.additional` gains all three, in the same order `NSOpenPanel.urls` returned them. |
| file-browser-033 | multi-pane-consistency | Construct two `FileBrowserViewController`s sharing one `FileBrowserDirectories`/`FileBrowserSelection`; select a node under a user-added root in the first, then remove that root from the second. | The first controller's `selection.selectedNode` (and `selection.selectedRoot`, if it equaled the removed root) become `nil`, since both controllers observe the same shared objects. |
| file-browser-034 | reveal-forwarding | Call `controller.revealNothing()`. | The hosted tree's `revealNothing()` is invoked. |
| file-browser-035 | remove-button-tooltip | Set `selection.selectedRoot` to `nil`. | Remove button's tooltip reads `Select an added directory to remove it`. |
| file-browser-036 | add-directory-selects-last-added | Call `addDirectory()`, choose three new directories in a single panel response and confirm. | `selection.selectedRoot` equals only the last of the three chosen directories, not the first two. |
| file-browser-037 | git-status-provider-reuse | Inject a `GitStatusProvider` whose `repoRoot` (symlink-resolved) matches an *additional* root added via `addDirectory()`, not the primary root. | That additional root's manager is built with that provider, matched through `resolvingSymlinksInPath()` rather than a lexical comparison. |
