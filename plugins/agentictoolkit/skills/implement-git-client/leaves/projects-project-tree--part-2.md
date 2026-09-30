<!-- leaf: implement-git-client/projects-project-tree--part-2 · source: git-client-projects-project-tree.md -->

# ProjectTree — continued (part 2)

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTree.swift`,
  tested by
  `Tests/AgenticToolkitMacOSTests/Projects/ProjectTreeTests.swift`; it
  imports only `Foundation` and depends on no AppKit, UIKit, or SwiftUI type,
  so it ports unchanged into a SwiftUI-hosted app. A SwiftUI `List` or
  `OutlineGroup` would bind directly to the returned `[ProjectTreeNode]`
  roots and each node's `children`, exactly as `ProjectBrowserViewController`
  binds its `NSOutlineView` today.
- **Compose**: Model `ProjectTreeNode` as a Kotlin class (not a `data class`,
  to preserve `fileprivate`-style construction control via an `internal`
  constructor plus a factory) holding `val name: String`, `val repo:
  GitRepo?`, `val path: String`, and a private `MutableList<ProjectTreeNode>`
  exposed as a read-only `List`; `isFolder` ports as `val isFolder get() =
  repo == null`. Reproduce `@MainActor` confinement by requiring `build` to
  run on `Dispatchers.Main` (Kotlin has no compile-time actor-isolation
  check, so this is a convention the port must enforce by review or a
  runtime assertion, not the compiler). `localizedCaseInsensitiveCompare`
  becomes `String.compareTo(other, ignoreCase = true)` combined with the
  platform's current `Locale` for any locale-sensitive difference.
- **React/Web**: A browser has no filesystem, so `homeDirectory`/`path` have
  no direct analogue unless this pattern runs in a Node-hosted process; there
  represent `ProjectTreeNode` as a plain object `{ name, repo, path,
  children }` and `isFolder` as `repo == null`, using `path.sep`-aware string
  splitting in place of `URL`/`String.split(separator: "/")`. JavaScript's
  single-threaded event loop naturally reproduces the source's `@MainActor`
  confinement without extra work, since nothing here is `async` or spawns a
  worker.
- **AppKit / UIKit**: This is the file's actual runtime home today.
  `ProjectBrowserViewController.viewDidLoad`-driven code calls
  `ProjectTree.build(from: matching)` and stores the result in its
  own `roots` property; its `NSOutlineViewDataSource` methods
  (`outlineView(_:child:ofItem:)`, `outlineView(_:isItemExpandable:)`, etc.) read a `ProjectTreeNode`'s `children` and `isFolder`
  directly to drive the outline view. Nothing in `ProjectTree.swift` itself
  is AppKit-specific, so it ports unchanged to UIKit's `UITableView`/
  `UICollectionView` with a diffable, hierarchy-flattening data source.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `ProjectTreeNode` as a plain C# class with `string Name`, `GitRepo? Repo`,
  `string Path`, a `bool IsFolder => Repo is null` computed property, and an
  `IReadOnlyList<ProjectTreeNode> Children` backed by a private
  `List<ProjectTreeNode>` populated only through an internal `Add` method —
  mirroring the source's `fileprivate init`/`add(_:)` restriction with C#
  `internal` visibility rather than a WinUI-specific mechanism. Implement
  `ProjectTree.Build(IReadOnlyList<GitRepo> repos, string? homeDirectory =
  null)` as a static method defaulting `homeDirectory` to
  `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)`, and
  reproduce `trail`/`standardized` with `string.Split('\\', '/')` plus a
  manual home-prefix comparison (Windows paths use `\`, not `/`, so a
  faithful port must decide the separator convention up front rather than
  hardcoding `"/"`). Bind the returned roots to a
  `Microsoft.UI.Xaml.Controls.TreeView`'s `ItemsSource` (or a `TreeViewNode`
  tree built from it), using `IsFolder` to pick between a folder glyph and a
  project glyph in the `TreeView`'s `ItemTemplate`; because `Build` should
  run on the UI thread the way the source's `@MainActor` requires, guard any
  call from a background context with `DispatcherQueue.TryEnqueue` rather
  than relying on a compiler-enforced actor, since C# has no `@MainActor`
  equivalent.

## Design Decisions

**Decision**: `ProjectTreeNode.init` and `add(_:)` are `fileprivate`, and
`children` is `private(set)`, so only `ProjectTree.build` (same file) can
shape the tree.
**Rationale**: The type's own doc comment frames the tree as a display
projection of the registry — "the folders that lead to projects, and the
projects themselves" — not a general-purpose mutable collection a caller
should be free to reshape after the fact; restricting construction to the
file that computes the tree's invariants (sorted order, one node per path)
keeps a caller like `ProjectBrowserViewController` from building a tree that
disagrees with those invariants.
**Approved**: pending

**Decision**: a project's displayed `name` comes from `repo.name`
(`build-leaf-name-from-registry`), never from the trail-computed path
component that a purely path-derived name would have produced.
**Rationale**: `GitRepo.name`'s own doc comment says it is "seeded from the
directory name, then the user's to change" (`GitRepo.swift`) — the
registry, not the filesystem, is the source of truth for what a project is
called once a user has renamed it, and `ProjectTreeTests.testAProjectRowTakesItsNameFromTheRegistry`
exists specifically to pin this choice down.
**Approved**: pending

**Decision**: `build`'s ancestor-reuse step (`build-ancestor-reuse-by-path`)
matches an existing `byPath` entry purely by `path`, without checking whether
that entry `isFolder`.
**Rationale**: The source gives no rationale for this beyond the general
one-node-per-path intent stated for the leaf case ("this must not
duplicate"); because the check is not repeated for the ancestor
case, a path that is simultaneously an ancestor for one repo and the leaf
for another can end up represented inconsistently — see
`project-tree-leaf-path-collision`, the open question this recipe raises
rather than resolves.
**Approved**: pending
