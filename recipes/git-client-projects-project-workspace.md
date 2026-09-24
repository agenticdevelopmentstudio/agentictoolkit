---
id: 33086772-2d36-49f5-8e1d-725163d7ce8f
title: ProjectWorkspace
domain: agentictoolkit://recipes/git-client-projects-project-workspace
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The project a window opens: a GitRepo, its persisted tabs, pane state, settings,
  directories, plus weakly-cached per-directory browser and git-status objects.'
platforms:
- swift
- macos
tags:
- git
- projects
- workspace
- tabs
- pane-state
- caching
- macos
- appkit
depends-on: []
related:
- agentictoolkit://recipes/git-client-projects-project-database
- agentictoolkit://recipes/git-client-projects-project-database-layout
- agentictoolkit://recipes/git-client-projects-git-repo
- agentictoolkit://recipes/git-client-projects-project-checkout
- agentictoolkit://recipes/git-client-projects-branch-controller
- agentictoolkit://recipes/git-client-projects-project-controller
- agentictoolkit://recipes/composable-tabs-window-controller
- agentictoolkit://recipes/git-client
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectWorkspaceTabsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase+Layout.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsLayout.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabLayoutSpec.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileBrowserDirectories.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Git/GitStatusProvider.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Editor/ProjectLanguageServices.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/MainThreadWorkspace.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectWorkspace

## Overview

`ProjectWorkspace` (`ProjectWorkspace.swift`) is one open project: the `GitRepo`
it is, the `ProjectDatabase` rows keyed to that repository, and the tab/split
arrangement its window shows. Per its own doc comment, it is "what `NSDocument`
used to be here, minus the document" — there is no file to read, write,
autosave, revert or name, because a project is a `git_repo` row plus the rows
keyed to it, so every edit is already saved and a repository can move on disk
without the project noticing. It owns the project's stored tab tree
(`storedTabs()`, `initialTabs()`, `persistTabs(...)`), an untyped per-pane and
per-project string bag (`paneState`/`setPaneState`, `setting`/`setSetting`),
the project's extra file-browser roots (`fileBrowserDirectories(primary:)`,
`persistProjectDirectories(...)`), and two directory-keyed object caches —
`FileBrowserDirectories` and `GitStatusProvider` — that hold their values
weakly so exactly one instance exists for as long as anything still needs it.
It is `@MainActor` and holds no `Sendable` conformance of its own; every
property and method is confined to the main actor by that declaration alone.

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

## Appearance

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component.

## States

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component. Its only runtime state is the tab tree
`storedTabs()`/`initialTabs()` read and repair and the two weak object caches,
all covered under Behavioral Requirements, not here.

## Accessibility

Not applicable — this is a project's persisted-state and per-directory object
cache, not a visual component. The accessibility of the panes it causes to
exist is the concern of whatever hosts a `TabRecord`'s content
(`BranchController`'s `TabPaneViewController`, the file browser), neither of
which this file renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-workspace-001 | stored-tabs-nil-when-empty-or-absent | Build a fresh `ProjectWorkspace` over an empty database and call `project.storedTabs()` (`testStoredTabsIsNilBeforeAnythingIsPersisted`). | `storedTabs()` returns `nil`. |
| git-client-projects-project-workspace-002 | persist-tabs-swallows-failure, stored-tabs-nil-when-empty-or-absent | Build one `TabRecord` on `project.layout.blueprint()`, call `project.persistTabs([record], activeTabID: record.id, enabledEdges: [.left])`, then call `project.storedTabs()` (`testStoredTabsReturnsWhatWasPersisted`). | `storedTabs()` returns non-nil; `stored.tabs.map(\.id) == [record.id]`; `stored.activeTabID == record.id`; `stored.enabledEdges == [.left]`. |
| git-client-projects-project-workspace-003 | file-browser-directories-cached-per-resolved-primary | Call `project.fileBrowserDirectories(primary: worktreeURL)` twice with the same `worktreeURL` (`testFileBrowserDirectoriesAreCachedPerPrimary`). | Both calls return the identical (`===`) `FileBrowserDirectories`; `first.primary.path == worktreeURL.path`; `project.fileBrowserDirectories` (the project's own directory) is a distinct instance (`!==`) from `first`. |
| git-client-projects-project-workspace-004 | git-status-provider-cached-per-resolved-directory | Call `project.gitStatusProvider(forDirectory: worktreeURL)` twice with the same `worktreeURL`, then once with `tempRoot` (`testGitStatusProvidersAreCachedPerDirectory`). | The two `worktreeURL` calls return the identical (`===`) `GitStatusProvider`; `first.repoRoot.path == worktreeURL.resolvingSymlinksInPath().path`; the `tempRoot` call's provider is distinct (`!==`) from `first`. |
| git-client-projects-project-workspace-005 | file-browser-directories-weakly-held | Take `project.fileBrowserDirectories(primary: worktreeURL)` and `project.gitStatusProvider(forDirectory: worktreeURL)` inside a scope holding only `weak` references, confirm each is reference-identical to a second call made inside that scope, then let the scope end and re-call both accessors (`testADirectoryNothingHoldsAnyMoreIsForgotten`). | Both `weak` references are `nil` once the scope ends; a fresh call afterward mints a working `FileBrowserDirectories` whose `primary.path` still equals `worktreeURL.resolvingSymlinksInPath().path`, and a repeat of that fresh call again returns the identical (`===`) instance. |
| git-client-projects-project-workspace-006 | directory-addition-fans-out-to-every-live-sibling | Take `project.fileBrowserDirectories(primary: tempRoot)` and `project.fileBrowserDirectories(primary: worktreeURL)`; call `mainRoots.add(addedFromMain)`; then call `worktreeRoots.add(addedFromWorktree)` (`testARootAddedInOneBrowserReachesTheOtherAndSurvivesItsNextSave`). | After the first `add`, `worktreeRoots.additional.map(\.path) == [addedFromMain.resolvingSymlinksInPath().path]`. After the second `add`, `project.projectDirectories()` contains both added URLs and `mainRoots.additional.map(\.path) == worktreeRoots.additional.map(\.path)`. |
| git-client-projects-project-workspace-007 | primary-is-re-added-if-stored-but-dropped | Take `mainRoots` and `worktreeRoots` as above; call `worktreeRoots.add(tempRoot)` (adding the main checkout as a root of the worktree browser); then call `mainRoots.add(addedFromMain)` (`testARootThatIsAnotherBrowsersPrimaryIsNotDroppedByThatBrowsersSave`). | Immediately after `worktreeRoots.add(tempRoot)`, `mainRoots.additional.isEmpty == true` (a browser never lists its own primary). After `mainRoots.add(addedFromMain)`, `project.projectDirectories()` still contains both `tempRoot` and `addedFromMain`. |
| git-client-projects-project-workspace-008 | initial-tabs-default-when-nothing-stored | Not present in `ProjectWorkspaceTabsTests.swift`; synthesized from `ProjectWorkspace.swift`. Build a fresh `ProjectWorkspace` with nothing persisted; call `project.initialTabs()`. | The returned `tabs` has exactly one `TabRecord` titled `"Tab 1"` whose `root` equals `project.layout.blueprint()`; `activeTabID` equals that tab's `id`; `enabledEdges == [.top]`. |
| git-client-projects-project-workspace-009 | stored-tab-trees-repaired-against-current-spec, one-arrangement-per-project, stale-focused-node-cleared, active-tab-fallback | Not present in `ProjectWorkspaceTabsTests.swift`; synthesized from `ProjectWorkspace.swift`. Persist two `TabRecord`s built under a spec that later disallows one pane in the second tab's tree, with the second tab's `focusedNodeID` pointing at that now-disallowed pane; call `project.initialTabs()`. | Every returned tab's `root` is a spec-reconciled tree that also matches the shared arrangement `ProjectTabReconciler.arrangement(of:activeTabID:)` computes over the repaired tabs; the second tab's `focusedNodeID` is `nil`; `activeTabID` falls back to the first returned tab's `id` when `stored.activeTabID` names no tab in the result. |
| git-client-projects-project-workspace-010 | update-preserves-identity | Build `project` from `repo`; call `project.update(repo: GitRepo(id: repo.id, path: "/new/path", name: "Renamed"))`, then call `project.update(repo: GitRepo(id: UUID(), path: repo.path, name: repo.name))`. | After the first call, `project.repo.path == "/new/path"` and `project.displayName == "Renamed"`. After the second call, `project.repo` is unchanged from the first call's result — the id mismatch made the second `update` a no-op. |
| git-client-projects-project-workspace-011 | pane-number-allocation-is-monotonic | Call `project.allocatePaneNumber()` three times in a row on the same `ProjectWorkspace`. | The three calls return `1`, `2`, `3`, in that order, and no later call on the same instance ever returns a number already returned. |
| git-client-projects-project-workspace-012 | pane-state-scoped-by-node-and-key, pane-state-failures-swallowed-and-logged-with-full-context | Call `project.setPaneState(nodeID: id, key: "scrollOffset", value: "120")`, then `project.paneState(nodeID: id, key: "scrollOffset")`; separately, call `project.paneState(nodeID: id, key: "scrollOffset")` for a `repo.id` the database has never recorded (an unpersisted `GitRepo`, provoking a foreign-key failure). | The first pair returns `"120"`. The second call returns `nil`, and one `error`-level log line is emitted naming the verb (`"load"`), the `repo.id`, the `nodeID`, and the key. |
| git-client-projects-project-workspace-013 | pane-state-list-json-encoded | Call `project.setPaneStateList(nodeID: id, key: "recentFiles", values: ["/a", "/b"])`, then `project.paneStateList(nodeID: id, key: "recentFiles")`; then call `project.setPaneStateList(nodeID: id, key: "recentFiles", values: [])` and read the key again; separately, read `paneStateList` for a key that was never set. | The first read returns `["/a", "/b"]`. After setting an empty list, `paneState(nodeID:key:)` for that key returns `nil` and `paneStateList` for it returns `[]`. The never-set key's `paneStateList` also returns `[]`. |
| git-client-projects-project-workspace-014 | project-setting-scoped-by-repo, setting-nil-deletes-row | Call `project.setSetting("theme", to: "dark")`, then `project.setting("theme")`; then call `project.setSetting("theme", to: nil)` and read `project.setting("theme")` again. | The first read returns `"dark"`. After setting `nil`, `project.setting("theme")` returns `nil`, and the underlying row for `("theme", repo.id)` no longer exists (matching `"never set"`). |
| git-client-projects-project-workspace-015 | cache-directory-derivation | Build a `project` whose `database.databasePath` is `"/Users/x/Library/.../Test.db"`; read `project.cacheDirectoryURL` without calling anything else, then check the filesystem. | `cacheDirectoryURL.path == "/Users/x/Library/.../caches/<repo.id.uuidString>"`; no directory exists on disk at that path yet, because reading the property performs no filesystem write. |
| git-client-projects-project-workspace-016 | extension-workspace-roots-conformance | Cast `project` to `ExtensionWorkspaceRoots` and read `workspaceDisplayName` and `workspaceRootURLs` after adding one extra directory to the project's own file browser. | `workspaceDisplayName == project.displayName`; `workspaceRootURLs == project.fileBrowserDirectories.all`, with the project's own `directoryURL` first. |
| git-client-projects-project-workspace-017 | git-client-defaults-to-shared-injectable, layout-defaults-through-fallback-chain | Construct `ProjectWorkspace(repo:database:)` with every optional parameter omitted. | `project.gitClient` is reference-identical (`===`, once `GitClient` is compared by its shared-instance identity) to `GitClient.shared`; `project.layout` is `ComposableTabsLayout.current` when a layout has been installed process-wide, or otherwise a placeholder-only layout equal to `ComposableTabsLayout.placeholderOnly()`'s shape. |
| git-client-projects-project-workspace-018 | stored-tabs-load-failure-signal | Not present in `ProjectWorkspaceTabsTests.swift`; demonstrates the open question on stored-tabs-load-failure-signal. Force `database.loadTabs(repoID:)` to throw (e.g. a corrupted database file or a repo id the schema rejects), capture the OS log for the duration, then call `project.storedTabs()`. | `storedTabs()` returns `nil`, exactly as it would for a project that had never saved a tab — and the captured log contains no line attributable to this call, unlike vector -012's pane-state failure, which does log. |

## Edge Cases

- **Null and empty input**: `storedTabs()` treats a `loadTabs` result whose
  `tabs` array is empty the same as a thrown error — both produce `nil`
  (**stored-tabs-nil-when-empty-or-absent**, MUST). `paneStateList` for an
  unset key, or for a key holding a string that is not valid UTF-8 or not
  valid JSON, returns `[]` rather than throwing or crashing
  (**pane-state-list-json-encoded**, MUST). `setPaneStateList` with an empty
  `values` array clears the key instead of writing `"[]"`
  (**pane-state-list-json-encoded**, MUST).
- **Boundary values**: `allocatePaneNumber()`'s counter starts at `1` and has
  no declared upper bound; it is a plain `Int`, so the boundary this file
  defines no behavior for is `Int.max` overflow, which Swift traps on rather
  than wrapping (MUST, by the language's own arithmetic semantics — not a
  case this file guards against itself). `initialTabs()`'s stored-tab path is
  only reached when `stored.tabs` is non-empty, because `storedTabs()` already
  filters the empty case out, so the `shared[0].id` fallback in
  **active-tab-fallback** never indexes an empty array.
- **Concurrent access**: Every property and method here is confined to the
  main actor (**main-actor-isolation**), so no two calls on one
  `ProjectWorkspace` instance can interleave their mutations of `repo`,
  `nextPaneNumber`, or either `WeakCache`. Two separate `ProjectWorkspace`
  instances built over the same `repo.id` (a project opened in two windows)
  can still race at the `ProjectDatabase` layer — `persistTabs`, `setSetting`,
  `setPaneState`, and `persistProjectDirectories` from one instance are not
  serialized against calls from another — but ordering that race, when it
  matters, is `ProjectController`'s job (see
  `agentictoolkit://recipes/git-client-projects-project-controller`), not
  this file's; `ProjectWorkspace` itself makes no ordering claim across
  instances.
- **Error states**: Every database-backed method except `storedTabs()` catches
  its error, logs it through `Self.logger.error` (or `logPaneStateFailure`),
  and returns a safe default — `nil`, `[]`, or nothing — rather than
  propagating it (**persist-tabs-swallows-failure**,
  **pane-state-failures-swallowed-and-logged-with-full-context**,
  **project-setting-scoped-by-repo**,
  **project-directories-load-failure-yields-empty**, all MUST). The one
  exception, `storedTabs()`'s bare `try?`, has no log signal at all — see
  **stored-tabs-load-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense —
  every dependency this file reads or writes (`ProjectDatabase`, the
  filesystem paths it resolves symlinks against) is local. `gitStatusProvider
  (forDirectory:)` hands out an object built on `gitClient`, but the git
  subprocess calls that object goes on to make are that object's own concern,
  not this file's (see `agentictoolkit://recipes/git-client`).
- **Cancellation and timeouts**: No method on `ProjectWorkspace` is `async`;
  every operation here is a synchronous database call, a synchronous cache
  lookup, or a pure computation, so there is no cancellation token, timeout,
  or `Task` for this file to honor or ignore (MUST, by the absence of any
  `async` signature in `ProjectWorkspace.swift`).
- **Missing file or unreachable server**: A `primary`/`directory` argument
  that does not exist on disk is not distinguished from one that does —
  `resolvingSymlinksInPath()` on a nonexistent path returns the path
  unchanged, so `fileBrowserDirectories(primary:)` and `gitStatusProvider
  (forDirectory:)` still mint and cache an object keyed to it
  (**file-browser-directories-cached-per-resolved-primary**,
  **git-status-provider-cached-per-resolved-directory**, MUST, by the absence
  of any existence check in either method).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repo` (parameter to `init`) | `GitRepo` | none — required | The repository this project is; supplies `id`, `displayName`, and `directoryURL`. |
| `database` (parameter to `init`) | `ProjectDatabase` | none — required | The one shared database every persisted read/write in this file goes through, scoped by `repo.id`. |
| `layout` (parameter to `init`) | `ComposableTabsLayout?` | `nil` → `ComposableTabsLayout.current ?? ComposableTabsLayout.placeholderOnly()` | Which views this project may show and which arrangements of them are legal. |
| `languageServices` (parameter to `init`) | `ProjectLanguageServices?` | `nil` | This project's language servers; `nil` disables language-service support for the project. Lifecycle owned by `ProjectWindowManager`, not by this file. |
| `gitClient` (parameter to `init`) | `GitClient` | `GitClient.shared` | The git client `gitStatusProvider(forDirectory:)` builds every `GitStatusProvider` on. |

`ProjectWorkspace.swift` reads no environment variable and no settings key of
its own; the project-scoped `setting`/`setSetting` pair is a caller-defined
key/value bag this file only routes to `ProjectDatabase`, not a source of
configuration for `ProjectWorkspace` itself.

## Deep Linking

Not applicable: `ProjectWorkspace.swift` defines no URL scheme, route, or
navigation destination.

## Localization

`ProjectWorkspace.swift` contains exactly one user-facing string literal:
`initialTabs()`'s default tab title, hardcoded as English with no
localization mechanism (`ProjectWorkspace.swift`).

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not looked up) | `Tab 1` | Title of the single default tab `initialTabs()` returns for a project that has never persisted any tabs. |

## Accessibility Options

Not applicable: `ProjectWorkspace.swift` renders nothing itself. It vends
`TabRecord`s and per-directory model objects (`FileBrowserDirectories`,
`GitStatusProvider`) that other view controllers render; Reduce Motion,
Increase Contrast, and Differentiate Without Color are those rendering
layers' concern.

## Feature Flags

Not applicable: `ProjectWorkspace.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: `ProjectWorkspace.swift` makes no analytics or
event-tracking call.

## Privacy

- **Data collected**: Local filesystem paths (`repo.path`, `directoryURL`,
  every `primary`/`directory` this file is asked to resolve and cache),
  the repository's `id` (a `UUID`), and whatever a pane or the project window
  itself chooses to store under `paneState`/`setPaneState` and
  `setting`/`setSetting` — per the doc comment on `paneStateList`, the lists
  panes remember through this API "are file paths" (`ProjectWorkspace.swift`). No credential, token, or network-identity data passes
  through this file.
- **Storage**: Everything persisted here (tabs, pane state, project settings,
  extra directories) is written to the one `ProjectDatabase` this project was
  constructed with, scoped by `repo.id`; see
  `agentictoolkit://recipes/git-client-projects-project-database` and
  `agentictoolkit://recipes/git-client-projects-project-database-layout` for
  that store's own durability guarantees. `cacheDirectoryURL` names, but does
  not itself populate, a filesystem location beside the database.
- **Transmission**: `ProjectWorkspace.swift` makes no network call and sends
  nothing off the local machine; `gitStatusProvider(forDirectory:)` hands out
  a collaborator that may run local `git` subprocesses, not a network client.
- **Retention**: Data persisted through this file survives until explicitly
  overwritten or deleted through the same accessor (`setSetting(_:to: nil)`
  deletes rather than storing an empty value, per **setting-nil-deletes-row**)
  or until the underlying `git_repo` row itself is deleted, which is outside
  this file's own methods.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `ProjectWorkspace`
(`ProjectWorkspace.swift`, via `Loggable`).

| Event | Level | Message |
|-------|-------|---------|
| `database.saveTabs` threw | error | `Failed to save project tabs: <error description>` |
| `database.paneState` threw (via `logPaneStateFailure("load", ...)`) | error | `Failed to load pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| `database.setPaneState` threw (via `logPaneStateFailure("save", ...)`) | error | `Failed to save pane state (repo <repo id>, node <node id>, key <key>): <error description>` |
| `database.pruneNestedPaneState` threw (via `logPaneStateFailure("prune", ...)`, key `"*"`) | error | `Failed to prune pane state (repo <repo id>, node <node id>, key *): <error description>` |
| `database.setting` threw | error | `Failed to load project setting: <error description>` |
| `database.setSetting` threw | error | `Failed to save project setting: <error description>` |
| `database.loadProjectDirectories` threw | error | `Failed to load project directories: <error description>` |
| `database.saveProjectDirectories` threw | error | `Failed to save project directories: <error description>` |

`database.loadTabs` throwing inside `storedTabs()` produces no log line at
all — see the open question on stored-tabs-load-failure-signal.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift`,
  importing `AppKit`, `AgenticToolkitCore`, `AgenticToolkitCoreUI`,
  `AgenticToolkitCoreMacOS`, and `os`. It calls no AppKit UI API directly —
  it is a plain `@MainActor` model object holding a `GitRepo`, a
  `ProjectDatabase`, a `ComposableTabsLayout`, and two weak object caches. A
  SwiftUI host would still need this exact object feeding a tab-bar view, as
  an `@Observable`/`ObservableObject`-wrapped dependency, not a `View` or
  `Scene` itself.
- **Compose**: Model `ProjectWorkspace` as a plain class confined to a single
  coroutine dispatcher (Compose's main-thread dispatcher, mirroring
  `@MainActor`), holding `repo` and `layout` as `MutableState` so dependent
  composables recompose on `update(repo:)`. Reproduce the two `WeakCache`s
  with a `WeakHashMap`/`java.lang.ref.WeakReference`-backed map keyed by the
  resolved directory path, evicted the same way — lazily, on next lookup,
  rather than by an explicit listener. Route every persisted read/write
  (`storedTabs`, `paneState`, `setting`, `projectDirectories`) through a
  coroutine-based `ProjectDatabase` port that mirrors this file's
  swallow-and-log convention on every path except the one this recipe flags
  as an open question.
- **React/Web**: There is no local filesystem worktree or SQLite file to
  scope this object to on the web; a browser-hosted project workspace would
  keep `repo`/tabs/pane-state/settings as component state populated from and
  persisted through a server-side API standing in for `ProjectDatabase` (see
  `agentictoolkit://recipes/git-client-projects-project-database`), and would
  reproduce the two weak, directory-keyed caches with a JavaScript `WeakMap`
  (optionally paired with `FinalizationRegistry` to detect eviction) keyed by
  a normalized directory identifier, since JavaScript has no
  `resolvingSymlinksInPath()` equivalent of its own.
- **AppKit / UIKit**: The source already is this tier — a plain
  `@MainActor`-confined `NSObject`-free model class with no `NSViewController`
  of its own. A UIKit (iOS) port carries the tab-tree, pane-state, settings,
  and directory-cache logic unchanged; it would still need its own
  `FileBrowserDirectories`/`GitStatusProvider`-equivalent collaborators, and,
  per the multi-checkout note in
  `agentictoolkit://recipes/git-client-projects-project-controller`, iOS
  sandboxing makes exposing more than one linked worktree under one project
  an unusual arrangement to design a browser for.
- **WinUI 3**: Port `ProjectWorkspace` as a plain C# class with no interface
  requiring thread-affinity of its own, touched only from the UI thread
  (`DispatcherQueue`) by convention — the same discipline
  `agentictoolkit://recipes/git-client-projects-branch-controller`'s WinUI
  port assumes for `@MainActor`. Reproduce the two `WeakCache`s with a
  `Dictionary<string, WeakReference<T>>` (or `ConditionalWeakTable`) keyed by
  a normalized, reparse-point-resolved path (`Path.GetFullPath`/
  `FileInfo.FullName`, mirroring `resolvingSymlinksInPath()`), pruning dead
  entries the same way — lazily, on the next lookup for any key, not on a
  timer. Reproduce **directory-addition-fans-out-to-every-live-sibling** by
  iterating every live entry in that table and calling an equivalent
  `ReplaceAdditional` on each, and reproduce
  **pane-state-list-json-encoded** with `System.Text.Json` in place of
  `JSONEncoder`/`JSONDecoder`. Route every persisted accessor
  (`storedTabs`/`saveTabs`, `paneState`/`setPaneState`, `setting`/
  `setSetting`, `loadProjectDirectories`/`saveProjectDirectories`) through
  the same SQLite-backed port `agentictoolkit://recipes/git-client-projects-project-database`
  and `agentictoolkit://recipes/git-client-projects-project-database-layout`
  describe, keeping this file's swallow-and-log convention on every path
  except the one flagged as an open question above.

## Design Decisions

**Decision**: `fileBrowserDirectoriesByPrimary` and `gitStatusProvidersByRoot`
hold their values weakly (`WeakCache`) instead of strongly.
**Rationale**: The doc comment on `WeakCache` states the failure mode this
avoids directly: holding values strongly meant a project "accumulated one
`FileBrowserDirectories` and one `GitStatusProvider` for every directory
anything had *ever* asked about — every worktree visited, every checkout
opened and closed again — for as long as the project stayed open," each one
"still observing a directory with nothing left on screen to show for it."
Weak values end an entry with its last holder without weakening the
invariant the cache exists for (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `gitStatusProvider(forDirectory:)` mints and caches its
`GitStatusProvider`s on `ProjectWorkspace`, not on `BranchController`.
**Rationale**: The doc comment explains the ordering bug this sidesteps: a
pane is built while the window installs its stored tabs, "before the first
`git worktree list` has returned and so before any `BranchController`
exists"; a provider resolved through the branch controllers "therefore
answered `nil` for every pane the window opened with," and because
`FileBrowserViewController` "latches what it is handed at init and never asks
again," those panes ran a private provider of their own for the rest of the
session while the `Refresh Status` command reached a different object.
Minting at the project level removes the ordering question rather than
moving it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` refreshes every other
live `FileBrowserDirectories` before returning, rather than letting each
browser reload lazily on its own next save.
**Rationale**: The doc comment states the bug this closes: each browser used
to write "the *whole* list back on any change," from its own stale snapshot,
so "the second one to save wrote its stale copy over the first one's addition
and the folder vanished from disk with no error." Refreshing every sibling
immediately, before anything else can save, keeps every open browser's copy
of the one project-wide list current (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `projectDirectoriesDidChange(_:from:)` re-adds `primary` to the
merged list when the stored list names it but the browser's own `urls` do
not.
**Rationale**: The doc comment explains why this merge is necessary: "an
object cannot represent its own primary" — a `FileBrowserDirectories` filters
its own primary out of `additional` because it is already shown and not
removable. If a user added a worktree's folder as an extra root of the main
checkout and then opened that worktree in its own tab, the worktree's own
browser would otherwise silently delete that entry on its next save
(`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `cacheDirectoryURL` is a pure computation that never creates the
directory it names.
**Rationale**: The doc comment states the reasoning directly: every caller so
far only names the folder (the file browser excludes it from the tree), and
"a getter that quietly makes a directory on disk … for every project, whether
or not anything ever caches into it … is a side effect nobody reading
`project.cacheDirectoryURL` would expect." Whoever writes there first creates
it (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: The `chrome.` prefix on `paneState`/`setPaneState` keys is
reserved by documentation only; `ProjectWorkspace` adds no runtime check that
a caller's key avoids it.
**Rationale**: The doc comment gives the reasoning: "Nothing checks this: the
prefix is what keeps chrome off content's keys, and this sentence is what
keeps content off chrome's. A check would have to let the one caller that is
*supposed* to write the prefix through, which buys less than the sentence
does." (`ProjectWorkspace.swift`).
**Approved**: pending

**Decision**: `setSetting(_:to:)` treats a `nil` value as a delete rather than
storing an empty or null row.
**Rationale**: The doc comment states this directly: "so 'never set' and 'set
back to the default' are the same state and neither accumulates"
(`ProjectWorkspace.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectWorkspace` owns exactly
the tab tree, the pane-state/setting bag, the extra-directory list, and the
lifecycle of its two per-directory object caches, while delegating every
actual read and write to `ProjectDatabase`, all tab-arithmetic to
`ComposableTabsLayout.spec` and `ProjectTabReconciler`, and all rendering to
whatever hosts a `TabRecord` — it constructs no view of its own. unit-test-
coverage is partial because `ProjectWorkspaceTabsTests.swift` exercises
`storedTabs()`'s nil-before-persist and round-trip paths, both weak caches'
per-key identity and eviction, and the directory-addition fan-out and
primary-re-add merges — but has no test for `initialTabs()`'s spec-repair,
arrangement-reshape, or stale-focus-clearing paths, for `update(repo:)`'s id
guard, for `allocatePaneNumber()`, or for any pane-state/setting failure path
(vectors -008 through -014 and -016 through -018 above are synthesized to
describe what such tests would assert). explicit-error-handling is partial
because every failing database call except `storedTabs()` is caught and
logged; `storedTabs()`'s bare `try?` lets its error vanish with no log line
at all (the open question on stored-tabs-load-failure-signal).
graceful-degradation passes because every failure path here degrades to a
safe, documented default — `nil`, `[]`, or the previous cache value — rather
than crashing or propagating. state-recovery is partial for the same reason
explicit-error-handling is: `initialTabs()` is this project's state-recovery
path after a restart, and a transient `loadTabs` failure on that path is
currently indistinguishable from a project that never saved anything, so
recovery silently resets to one default tab instead of surfacing the
failure. data-integrity is partial because `paneStateList` treats an unset
key and a key holding corrupt JSON identically (both `[]`), so corrupt pane
state is never detected or reported as such, only masked as "unset."

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
