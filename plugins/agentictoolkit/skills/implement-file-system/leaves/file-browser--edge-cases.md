<!-- leaf: implement-file-system/file-browser--edge-cases · source: file-system-file-browser.md -->

# File System File Browser

**Rules** (cite as `implement-file-system/file-browser--edge-cases#<slug>`):

- `null-and-empty-input` MUST — FileBrowserDirectories(primary:) with no additional argument (the default []) MUST leave all equal to [primary]. …
- `boundary-values` MUST — A URL passed to add(_:) or remove(_:) that is byte-for-byte identical to an existing root, and one that only resolves …
- `concurrent-access` MAY — All three types are @MainActor-isolated (main-actor-isolation-across-all-three-types), so no two calls into any one of …
- `error-states` MUST — A GitStatusRefreshResult.unavailable (git missing, the process failing, or a cancelled request, per GitStatusProvider's …

## Edge Cases

- **Null and empty input**: `FileBrowserDirectories(primary:)` with no
  `additional` argument (the default `[]`) MUST leave `all` equal to
  `[primary]`. `FileBrowserRestorationState()` with no arguments (defaults
  `[]`/`nil`) MUST leave `isExpanded(_:)` `false` for every path and
  `selectedPath` `nil`, with no crash. `FileTreeManager` with the default
  `ignorePatterns: []` excludes nothing of its own beyond whatever the
  delegated `FileTreeNode.loadChildren` already hardcodes (skipping
  `.DS_Store`) — this MUST hold.
- **Boundary values**: A URL passed to `add(_:)` or `remove(_:)` that is
  byte-for-byte identical to an existing root, and one that only resolves to
  the same location after `resolvingSymlinksInPath()`, MUST be treated
  identically (both are "the same root") because both go through the same
  resolve-then-compare step. A root added *inside* another root (nested
  under `primary` or another `additional` entry) MUST resolve
  `root(containing:)` to the more specific (deepest-path) root, per
  **root-containing-longest-match**, not the outer one.
- **Concurrent access**: All three types are `@MainActor`-isolated
  (**main-actor-isolation-across-all-three-types**), so no two calls into any
  one of them can race against each other from different threads. Two
  genuine ordering gaps remain even under that isolation — a delayed git
  status broadcast racing the tree's first sync, and two overlapping
  directory syncs racing each other — both left open above (see the open question on `git-status-may-be-dropped-before-first-sync`
  and the open question on `overlapping-directory-syncs-race`). A single
  `GitStatusProvider` MAY be shared across multiple `FileTreeManager`
  instances (confirmed by `FileTreeManagerInjectedProviderTests`); each
  manager's own `GitStatusObservation` is independent, so one manager being
  deallocated does not affect another sharing the same provider.
- **Error states**: A `GitStatusRefreshResult.unavailable` (git missing, the
  process failing, or a cancelled request, per `GitStatusProvider`'s own
  documentation) MUST leave existing git-status badges exactly as they were
  — this component draws no distinction between "nothing has changed" and
  "we could not find out," beyond simply not touching the data it already
  has. A filesystem read failure inside the delegated
  `DirectoryWatchCoordinator`/`FileTreeNode` layer is swallowed to an empty
  result before it ever reaches `FileTreeManager` (documented in the sibling
  `file-tree-outline-view-controller` recipe's Edge Cases); none of the three
  types in this recipe surfaces a distinct error state for that case either.
- **Offline/disconnected state**: Not applicable. None of the three types
  makes a network request; `GitStatusProvider` runs a local `git` subprocess
  through `GitClient`, and all filesystem access is local to the machine, so
  there is no connectivity-loss behavior to define here.
