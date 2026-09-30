<!-- leaf: implement-git-client/projects-project-workspace--part-2 · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-workspace--part-2#<slug>`):

- `main-actor-isolation` MUST
- `repo-identity` MUST
- `repo-mutation-exposed-read-only` MUST
- `update-preserves-identity` MUST
- `pane-number-allocation-is-monotonic` MUST
- `cache-directory-derivation` MUST
- `stored-tabs-nil-when-empty-or-absent` MUST
- `initial-tabs-default-when-nothing-stored` MUST
- `stored-tab-trees-repaired-against-current-spec` MUST
- `one-arrangement-per-project` MUST
- `stale-focused-node-cleared` MUST
- `active-tab-fallback` MUST
- `persist-tabs-swallows-failure` MUST
- `pane-state-scoped-by-node-and-key` MUST
- `chrome-prefix-is-unenforced-convention` MUST
- `pane-state-failures-swallowed-and-logged-with-full-context` MUST
- `pane-state-list-json-encoded` MUST
- `project-setting-scoped-by-repo` MUST
- `setting-nil-deletes-row` MUST
- `project-directories-load-failure-yields-empty` MUST
- `file-browser-directories-cached-per-resolved-primary` MUST
- `file-browser-directories-weakly-held` MUST
- `directory-addition-fans-out-to-every-live-sibling` MUST
- `primary-is-re-added-if-stored-but-dropped` MUST
- `git-status-provider-cached-per-resolved-directory` MUST
- `extension-workspace-roots-conformance` MUST
- `git-client-defaults-to-shared-injectable` MUST
- `layout-defaults-through-fallback-chain` MUST

## Behavioral Requirements

- **main-actor-isolation**: `ProjectWorkspace` MUST be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance, so every stored property and
  method is confined to the main actor by that declaration alone
  (`ProjectWorkspace.swift`).
- **repo-identity**: `id` MUST be computed as `repo.id`, `displayName` MUST be
  computed as `repo.name`, and `directoryURL` MUST be computed as `repo.url`,
  on every access rather than cached separately (`ProjectWorkspace.swift`).
- **repo-mutation-exposed-read-only**: `repo` MUST be exposed as `public
  private(set)`, so only `ProjectWorkspace`'s own `update(repo:)` method may
  change it; every other reader sees it as read-only (`ProjectWorkspace.swift`).
- **update-preserves-identity**: `update(repo:)` MUST replace `self.repo` with
  the argument only when `repo.id == self.repo.id`, and MUST leave `self.repo`
  unchanged and return with no other effect when the ids differ
  (`ProjectWorkspace.swift`).
- **pane-number-allocation-is-monotonic**: `allocatePaneNumber()` MUST return
  the current value of an internal counter that starts at `1` and MUST then
  increment that counter, so no two calls on one `ProjectWorkspace` instance
  ever return the same number and no released number is ever reused
  (`ProjectWorkspace.swift`).
- **cache-directory-derivation**: `cacheDirectoryURL` MUST be computed as
  `<the directory containing database.databasePath>/caches/<repo.id as a UUID
  string>/`, and reading it MUST NOT create that directory or any of its
  parents on disk (`ProjectWorkspace.swift`).
- **stored-tabs-nil-when-empty-or-absent**: `storedTabs()` MUST return `nil`
  both when `database.loadTabs(repoID:)` throws and when it returns a `tabs`
  array that is empty, collapsing "nothing was ever persisted" and "the load
  failed" into the same result (`ProjectWorkspace.swift`).
- **initial-tabs-default-when-nothing-stored**: When `storedTabs()` returns
  `nil`, `initialTabs()` MUST return exactly one `TabRecord` titled `"Tab 1"`
  with `root: layout.blueprint()`, that tab's own `id` as `activeTabID`, and
  `[.top]` as `enabledEdges` (`ProjectWorkspace.swift`).
- **stored-tab-trees-repaired-against-current-spec**: When tabs are stored,
  `initialTabs()` MUST rewrite every tab's `root` with `layout.spec.reconcile
  (record.root)` before doing anything else with it, so a tree built under an
  earlier spec that no longer allows one of its panes is repaired on load
  (`ProjectWorkspace.swift`).
- **one-arrangement-per-project**: After that repair, `initialTabs()` MUST
  compute a shared arrangement via `ProjectTabReconciler.arrangement(of:
  activeTabID:)` over the repaired tabs, and, when that call produces one,
  MUST reshape every tab's `root` to it with `reshaped(toMatch:)`, each tab
  getting its own fresh set of node ids (`ProjectWorkspace.swift`).
- **stale-focused-node-cleared**: For every tab, `initialTabs()` MUST clear
  `focusedNodeID` to `nil` whenever that id is no longer present in the tab's
  (possibly just rewritten) `root.leafIDs`, following either rewrite above
  (`ProjectWorkspace.swift`).
- **active-tab-fallback**: `initialTabs()` MUST return `stored.activeTabID` as
  the active id when it names one of the returned tabs, and MUST otherwise
  fall back to the first returned tab's `id` (`ProjectWorkspace.swift`).
- **persist-tabs-swallows-failure**: `persistTabs(_:activeTabID:enabledEdges:)`
  MUST call `database.saveTabs(tabs:activeTabID:enabledEdges:repoID:)`, and on
  failure MUST log the error through `Self.logger.error` and MUST NOT throw,
  retry, or otherwise signal the failure to its caller
  (`ProjectWorkspace.swift`).
- **pane-state-scoped-by-node-and-key**: `paneState(nodeID:key:)` and
  `setPaneState(nodeID:key:value:)` MUST read and write through
  `database.paneState(repoID:nodeID:key:)` and `database.setPaneState
  (repoID:nodeID:key:value:)`, scoped by this project's own `repo.id`
  together with the given `nodeID` and `key` (`ProjectWorkspace.swift`).
- **chrome-prefix-is-unenforced-convention**: A `key` beginning with
  `chrome.` is reserved for `ProjectPaneStateStore`'s own use; pane content
  reading or writing through `paneState`/`setPaneState` MUST NOT use a key
  with that prefix, but `ProjectWorkspace` performs no runtime check of this
  rule itself (`ProjectWorkspace.swift`).
- **pane-state-failures-swallowed-and-logged-with-full-context**:
  `paneState`, `setPaneState`, and `pruneNestedPaneState` MUST each catch any
  error `database` throws, log it through `logPaneStateFailure(_:nodeID:key:
  error:)` naming the verb, this project's `repo.id`, the `nodeID`, and the
  `key` (`"*"` for `pruneNestedPaneState`), and MUST NOT propagate it;
  `paneState` MUST return `nil` on that path and `setPaneState`/
  `pruneNestedPaneState` MUST simply return (`ProjectWorkspace.swift`).
- **pane-state-list-json-encoded**: `paneStateList(nodeID:key:)` MUST decode
  the stored string as JSON `[String]` and MUST return `[]` when the key is
  unset, the stored string is not valid UTF-8, or JSON decoding fails
  (`ProjectWorkspace.swift`). `setPaneStateList(nodeID:key:
  values:)` MUST call `setPaneState(...,value: nil)` when `values` is empty,
  and MUST otherwise JSON-encode `values` to a UTF-8 string and write it,
  doing nothing when either encoding step fails (`ProjectWorkspace.swift`).
- **project-setting-scoped-by-repo**: `setting(_:)` and `setSetting(_:to:)`
  MUST read and write through `database.setting(repoID:key:)` and
  `database.setSetting(repoID:key:value:)`, scoped to this project's own
  `repo.id`, and MUST log and return `nil` (`setting`) or simply return
  (`setSetting`) on failure rather than propagate it (`ProjectWorkspace.swift`).
- **setting-nil-deletes-row**: `setSetting(_:to:)` called with `value: nil`
  MUST delete the underlying row rather than storing an empty or null value,
  so "never set" and "set back to the default" are the same state
  (`ProjectWorkspace.swift`).
- **project-directories-load-failure-yields-empty**: `projectDirectories()`
  MUST return `[]` and log the failure when `database.loadProjectDirectories
  (repoID:)` throws, rather than propagate the error or return a stale cached
  value (`ProjectWorkspace.swift`).
- **file-browser-directories-cached-per-resolved-primary**:
  `fileBrowserDirectories(primary:)` MUST resolve symlinks in `primary` before
  using it as a cache key, MUST return the cached `FileBrowserDirectories` for
  that resolved key when one is still alive, and MUST otherwise construct a
  new `FileBrowserDirectories(primary:additional:)` seeded with `additional:
  projectDirectories()`, register `projectDirectoriesDidChange` as its
  `onChange` handler, cache it under the resolved key, and return it
  (`ProjectWorkspace.swift`).
- **file-browser-directories-weakly-held**: The cache backing
  `fileBrowserDirectories(primary:)` and `gitStatusProvider(forDirectory:)`
  MUST hold its values weakly and MUST drop a key as soon as nothing outside
  the cache still holds the value stored under it, so a directory nothing is
  showing any more is forgotten rather than accumulated for the life of the
  project (`ProjectWorkspace.swift`).
- **directory-addition-fans-out-to-every-live-sibling**:
  `projectDirectoriesDidChange(_:from:)` MUST persist the merged directory
  list and then call `replaceAdditional(with:)` on every other still-live
  `FileBrowserDirectories` the cache currently holds (every entry in
  `fileBrowserDirectoriesByPrimary.liveEntries` whose key is not `primary`),
  so a `+`/`−` made through one directory's browser reaches every other open
  browser for the same project (`ProjectWorkspace.swift`).
- **primary-is-re-added-if-stored-but-dropped**: Before persisting,
  `projectDirectoriesDidChange(_:from:)` MUST re-add `primary` to the merged
  list when the previously stored list contained it but the incoming `urls`
  do not, and MUST NOT add it otherwise — because a `FileBrowserDirectories`
  never lists its own `primary` among its `additional` roots
  (`ProjectWorkspace.swift`).
- **git-status-provider-cached-per-resolved-directory**:
  `gitStatusProvider(forDirectory:)` MUST resolve symlinks in `directory`
  before using it as a cache key, MUST return the cached `GitStatusProvider`
  for that key when one is still alive, and MUST otherwise construct
  `GitStatusProvider(repoRoot:client:)` with this project's own `gitClient`,
  cache it under the resolved key, and return it (`ProjectWorkspace.swift`).
- **extension-workspace-roots-conformance**: `ProjectWorkspace` MUST conform
  to `ExtensionWorkspaceRoots`, exposing `workspaceDisplayName` as
  `displayName` and `workspaceRootURLs` as `fileBrowserDirectories.all` — this
  project's own directory's roots, primary first (`ProjectWorkspace.swift`).
- **git-client-defaults-to-shared-injectable**: `init(repo:database:layout:
  languageServices:gitClient:)` MUST default `gitClient` to `GitClient
  .shared` when the caller supplies none, and every method that mints a
  per-directory object or vends git access (`fileBrowserDirectories(primary:)`
  by way of caching, `gitStatusProvider(forDirectory:)`) MUST use this
  project's stored `gitClient`, never a client of its own
  (`ProjectWorkspace.swift`).
- **layout-defaults-through-fallback-chain**: `init` MUST resolve a `nil`
  `layout` argument as `ComposableTabsLayout.current ?? ComposableTabsLayout
  .placeholderOnly()` — the app-installed layout when one exists, a
  placeholder-only layout otherwise (`ProjectWorkspace.swift`).
- **stored-tabs-load-failure-signal**: NEEDS REVIEW: Not implemented in source. `storedTabs()` discards whatever error `database.loadTabs(repoID:)` throws via `try?` (`ProjectWorkspace.swift`) with no call to `Self.logger` and no other signal, unlike every other failing database access in this file — `setting`, `setSetting`, `projectDirectories`, `persistProjectDirectories`, `persistTabs`, and the three pane-state methods all log through `Self.logger.error` on their catch path. A database error while loading a project's tabs is therefore indistinguishable from a project that has simply never saved any, with zero diagnostic trail either way. Resolving this needs a decision from whoever owns this file: whether `storedTabs()` should log like its siblings do, and whether `initialTabs()`'s caller needs a way to tell "nothing stored" apart from "the load failed" at all.

