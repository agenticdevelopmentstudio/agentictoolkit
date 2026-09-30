<!-- leaf: implement-git-client/projects-project-workspace--part-3 · source: git-client-projects-project-workspace.md -->

# ProjectWorkspace — continued (part 3)

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

## Localization

`ProjectWorkspace.swift` contains exactly one user-facing string literal:
`initialTabs()`'s default tab title, hardcoded as English with no
localization mechanism (`ProjectWorkspace.swift`).

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not looked up) | `Tab 1` | Title of the single default tab `initialTabs()` returns for a project that has never persisted any tabs. |

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

