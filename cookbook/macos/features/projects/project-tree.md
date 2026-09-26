---
id: 8f0a3e2b-4d61-4a2f-9e4d-6c1a7b3f0d92
title: ProjectTree
domain: agentictoolkit://cookbook/macos/features/projects/project-tree
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Arranges a flat registry of GitRepo rows into the folder-then-project tree the project chooser displays, home-relative and alphabetically sorted.
platforms:
- swift
- macos
tags:
- git
- projects
- tree
- value-type
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/projects/git-repo
- agentictoolkit://cookbook/macos/features/projects/project-filter
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTree.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectBrowserViewController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectTreeTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectTree

## Overview

`ProjectTree.swift` turns a flat `[GitRepo]` registry into the hierarchy the
project chooser draws: folders on the way to a project, and the projects
themselves. `ProjectTreeNode` is the row type — a folder when its `repo` is
`nil`, a project when it holds one — and `ProjectTree` is the namespace that
builds and sorts a forest of those rows from `ProjectTree.build(from:
homeDirectory:)`. Paths inside the caller's home directory are shown relative
to it, "so the top of the list is `Development` and `Deployments` rather than
three levels of `Users/<name>` that are the same for everything" (source doc
comment); a path outside home keeps its leading slash, "the
only thing distinguishing `/opt` from a folder of the user's called `opt`"
. The one caller in the given sources is
`ProjectBrowserViewController`, which calls `ProjectTree.build(from:
matching)` and exposes the returned roots and every node's
`children` directly to an `NSOutlineView` as its data source.

## Behavioral Requirements

- **project-tree-node-stored-shape**: `ProjectTreeNode` MUST store exactly
  four properties — `name: String`, `repo: GitRepo?`, `path: String`, and
  `children: [ProjectTreeNode]`, the last `private(set)` and defaulting to an
  empty array — set through a `fileprivate init`.
- **project-tree-node-is-folder-derivation**: `isFolder` MUST be a computed
  property that returns `repo == nil`; a node is a folder if and only if it
  was constructed with no `GitRepo`.
- **project-tree-node-construction-restricted**: `init` and `add(_:)` MUST
  both be declared `fileprivate`; no type outside `ProjectTree.swift` MUST be
  able to construct a `ProjectTreeNode` or append a child to an existing one
  directly — only `ProjectTree.build` MUST be able to shape the tree.
- **repositories-in-display-order-leaf-passthrough**: `repositoriesInDisplayOrder`
  MUST return `[self]` immediately, without inspecting `children`, when
  `repo != nil`.
- **repositories-in-display-order-folder-recursion**: When `repo == nil`,
  `repositoriesInDisplayOrder` MUST return `children.flatMap { $0.repositoriesInDisplayOrder }`,
  so the flattened result MUST contain only nodes whose `repo != nil`, in the
  same depth-first order `children` is stored in at every level.
- **build-default-home-directory**: `ProjectTree.build(from:homeDirectory:)`'s
  `homeDirectory` parameter MUST default to
  `FileManager.default.homeDirectoryForCurrentUser`, evaluated once per call
  when the caller supplies no explicit value.
- **build-path-standardization**: Before computing anything else, `build`
  MUST reduce both `homeDirectory.path` and every `repo.path` through
  `standardized(_:)`, which strips exactly one trailing `"/"` when the string
  is longer than one character and leaves every other string unchanged —
  MUST NOT collapse repeated slashes, resolve `".."` or `"~"`, or normalize
  case.
- **trail-under-home-detection**: `trail(for:home:)` MUST classify a path as
  under `home` only when its component count is strictly greater than
  `home`'s component count AND its first `homeParts.count` components equal
  `home`'s components exactly; a path identical to `home` itself MUST NOT be
  classified as under home.
- **trail-under-home-truncation**: For a path classified as under `home`,
  `trail(for:home:)` MUST start the returned trail at the first component
  after `home`'s own components, omitting every component of `home` itself
  from both the trail's names and its count.
- **trail-outside-home-leading-slash**: For a path NOT classified as under
  `home`, `trail(for:home:)` MUST prepend `"/"` to the `name` of the trail's
  first component only; the `name` of every other component, at any depth,
  MUST have no leading slash.
- **trail-absolute-path-always-full**: Every trail entry's `path` MUST be
  computed as `"/" + parts[0...index].joined(separator: "/")` — the full
  absolute path from the filesystem root through that component — regardless
  of whether that component's displayed `name` was truncated for being under
  `home`; two folders with the same displayed `name` under different
  ancestors MUST therefore be tracked as distinct entries because their
  `path` values differ.
- **build-ancestor-reuse-by-path**: For each ancestor step in a repo's trail
  (every entry except the last), `build` MUST reuse the existing
  `ProjectTreeNode` already registered in `byPath` at that step's `path`, if
  one exists, as the parent for the next step, and MUST NOT create a second
  node for the same `path`; this reuse check MUST NOT inspect the existing
  node's `isFolder` or `repo` before treating it as the parent.
- **build-ancestor-folder-creation**: When no node is yet registered at an
  ancestor step's `path`, `build` MUST construct a new `ProjectTreeNode` with
  `repo: nil`, register it in `byPath` under that `path`, and append it to
  the running `parent` (or to `roots` when there is no parent yet) before
  continuing to the next step.
- **build-leaf-name-from-registry**: The `ProjectTreeNode` `build` constructs
  for a `GitRepo`'s leaf MUST take its `name` from `repo.name`, never from
  the trail-computed component name that a path-only derivation would have
  produced.
- **build-duplicate-leaf-path-dropped**: When `byPath` already holds a node
  at the leaf's `path` whose `repo != nil`, `build` MUST skip constructing a
  second node for the current `GitRepo` and MUST NOT add it to the tree,
  because "the registry allows [two rows for one path] and this must not
  duplicate".
- **build-roots-sort-order**: `build` MUST sort `roots` so every node with
  `isFolder == true` sorts before every node with `isFolder == false`, and
  MUST NOT consider `name` when two roots differ in `isFolder`.
- **build-roots-name-tiebreak**: Within two roots of the same `isFolder`
  value, `build` MUST order them by `name.localizedCaseInsensitiveCompare`,
  ascending.
- **build-recursive-sort**: After sorting `roots`, `build` MUST call
  `sortRecursively()` on each root so every node's `children`, at every
  depth of the resulting forest, is sorted by the same folders-first,
  case-insensitive-alphabetical rule.
- **project-tree-main-actor-isolation**: `ProjectTreeNode` and
  `ProjectTree.build` MUST both be `@MainActor`-isolated; a
  caller on any other isolation domain MUST cross through the main actor to
  call `build` or to read or mutate a `ProjectTreeNode`'s `children`.
- **project-tree-node-non-sendable**: `ProjectTreeNode` MUST NOT declare
  `Sendable` conformance; because it is a `public final class` holding
  mutable reference state (`children`) with no such conformance, the
  compiler MUST keep every value of this type confined to the `@MainActor`
  isolation domain it was created in — no caller in the given sources passes
  a `ProjectTreeNode` across isolation domains (contrast `GitRepo`'s
  `Sendable` conformance in `GitRepo.swift`).
- **build-empty-input-yields-empty-tree**: `build(from: [], homeDirectory:)`
  MUST return an empty array; nothing in `build`'s loop runs when `repos` is
  empty, so `roots` MUST stay `[]`.
- **project-tree-leaf-path-collision**: NEEDS REVIEW: Not implemented in source. When a `GitRepo`'s leaf `path` was already registered in `byPath` as a folder node (`existing.repo == nil`, created earlier as another repo's ancestor step), the guard (`existing.repo != nil`) does not match, so `build` falls through and constructs a second, project-flavored `ProjectTreeNode` at that same `path`, overwrites the `byPath` entry to point at it, and appends it to `parent`/`roots` without ever removing the earlier folder node, which is still present in that same parent's `children` array from when it was created; the two sibling nodes (one folder, one project) at the identical `path` are both rendered by `ProjectBrowserViewController`'s `NSOutlineView`, contradicting the file's own stated intent that a path "must not duplicate" — missing is a rule for whether the folder should be replaced, merged, or kept alongside the project, and the evidence that would settle it is a test exercising a `GitRepo` whose path equals another repo's ancestor folder path, or the authors' intended precedence between a folder and a project claiming the same path.
- **project-tree-degenerate-path-dropped**: NEEDS REVIEW: Not implemented in source. `trail(for:home:)` returns `[]` for any path whose `standardized(_:)` form splits into zero components (for example `path == "/"`, which `standardized(_:)` leaves unchanged because its `count` is not greater than 1); `build`'s `guard let leaf = trail.last else { continue }` then silently drops that `GitRepo` from the tree entirely, appearing in no root, no folder, and no count, with no error, no log call, and no signal of any kind reaching the caller — missing is whether such a repository should be surfaced some other way (an error row, a log line) rather than vanishing, and the evidence that would settle it is a test constructing a `GitRepo` with a degenerate `path` and asserting on the intended outcome, or a product decision on how the project chooser should represent it.

## Appearance

Not applicable — this is a tree-building data structure and algorithm, not a
visual component.

## States

Not applicable — this is a tree-building data structure and algorithm, not a
visual component. `ProjectTree.build` has no runtime state machine of its
own: it is called anew, synchronously, every time `ProjectBrowserViewController`
needs a fresh tree; nothing in this file remembers a previous
call's result.

## Accessibility

Not applicable — this is a tree-building data structure and algorithm, not a
visual component. The `NSOutlineView` that renders the nodes this file
produces is a separate component (`ProjectBrowserViewController`) with its
own accessibility surface, not given in these sources.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| PT-001 | build-ancestor-folder-creation, trail-under-home-truncation, build-leaf-name-from-registry | `ProjectTree.build(from: [repo("/Users/someone/Development/projects/whippet"), repo("/Users/someone/Development/projects/adh")], homeDirectory: "/Users/someone")` | `roots.map(\.name) == ["Development"]`; `roots[0].children.map(\.name) == ["projects"]`; `roots[0].children[0].children.map(\.name) == ["adh", "whippet"]` — `ProjectTreeTests.testProjectsAppearUnderTheFoldersThatHoldThem` |
| PT-002 | trail-under-home-truncation | `ProjectTree.build(from: [repo("/Users/someone/dev/alpha")], homeDirectory: "/Users/someone")` | `roots.map(\.name) == ["dev"]` — `ProjectTreeTests.testTheHomeDirectoryIsNotShownAsFolders` |
| PT-003 | trail-outside-home-leading-slash | `ProjectTree.build(from: [repo("/opt/checkouts/alpha")], homeDirectory: "/Users/someone")` | `roots.map(\.name) == ["/opt"]`; `roots[0].children.map(\.name) == ["checkouts"]` — `ProjectTreeTests.testAPathOutsideHomeKeepsItsLeadingSlash` |
| PT-004 | build-roots-name-tiebreak, build-recursive-sort | `ProjectTree.build(from: [repo("/Users/someone/dev/zeta"), repo("/Users/someone/dev/alpha"), repo("/Users/someone/dev/nested/beta")], homeDirectory: "/Users/someone")` | `roots[0].children.map(\.name) == ["nested", "alpha", "zeta"]` — folder before both projects, projects alphabetical — `ProjectTreeTests.testFoldersSortBeforeProjectsAndBothSortAlphabetically` |
| PT-005 | build-leaf-name-from-registry | `ProjectTree.build(from: [repo("/Users/someone/dev/alpha", name: "Alpha (main)")], homeDirectory: "/Users/someone")` | `roots[0].children.map(\.name) == ["Alpha (main)"]` — `ProjectTreeTests.testAProjectRowTakesItsNameFromTheRegistry` |
| PT-006 | trail-absolute-path-always-full | `ProjectTree.build(from: [repo("/Users/someone/work/src/alpha"), repo("/Users/someone/play/src/beta")], homeDirectory: "/Users/someone")` | `roots.map(\.name) == ["play", "work"]`; `roots[0].children[0].children.map(\.name) == ["beta"]`; `roots[1].children[0].children.map(\.name) == ["alpha"]` — two `"src"` folders under different parents stay distinct — `ProjectTreeTests.testTwoTreesWithSameNamedFoldersDoNotCollapseIntoOne` |
| PT-007 | repositories-in-display-order-leaf-passthrough, repositories-in-display-order-folder-recursion | `ProjectTree.build(from: [repo("/Users/someone/dev/zeta"), repo("/Users/someone/dev/nested/beta"), repo("/Users/someone/dev/alpha")], homeDirectory: "/Users/someone").flatMap { $0.repositoriesInDisplayOrder }` | `.map(\.name) == ["beta", "alpha", "zeta"]` — `ProjectTreeTests.testTheProjectsAreReadableInDisplayOrder` |
| PT-008 | build-empty-input-yields-empty-tree | `ProjectTree.build(from: [], homeDirectory: "/Users/someone")` | `.isEmpty == true` — `ProjectTreeTests.testAnEmptyRegistryBuildsAnEmptyTree` |
| PT-009 | build-duplicate-leaf-path-dropped | `ProjectTree.build(from: [repo("/Users/someone/dev/alpha", name: "Alpha"), repo("/Users/someone/dev/alpha", name: "Alpha Copy")], homeDirectory: "/Users/someone")` | `roots[0].children.count == 1` and `roots[0].children[0].name == "Alpha"` — the second `GitRepo` at the identical path is dropped (no dedicated test in the given suite) |
| PT-010 | project-tree-leaf-path-collision | `ProjectTree.build(from: [repo("/Users/someone/dev/sub/nested"), repo("/Users/someone/dev/sub")], homeDirectory: "/Users/someone")` | `roots[0].children` contains two entries named `"sub"` — one folder (created as the ancestor of `"nested"`) and one project (the second `GitRepo`, whose own path equals that ancestor's) — the open question this recipe flags; no test in the given suite exercises this input |

## Edge Cases

- **Null and empty input**: An empty `repos` array MUST yield `roots == []`
  (MUST, see `build-empty-input-yields-empty-tree`, PT-008). A `repo.path`
  that standardizes to a string with zero `"/"`-separated components (for
  example `"/"`) makes `trail(for:home:)` return `[]`, and `build` silently
  omits that `GitRepo` from the tree (see `project-tree-degenerate-path-dropped`
  — the open question on this behavior).
- **Boundary values**: A path exactly equal to `home` (not longer than it)
  is, by `trail-under-home-detection`, NOT treated as under home, so it is
  shown with its full absolute component list rather than collapsed to
  nothing (MUST). `standardized(_:)`'s trailing-slash strip
  only fires when `path.count > 1`, so the single-character path `"/"` is
  left as `"/"` rather than becoming `""` (MUST).
- **Concurrent access**: `ProjectTreeNode` and `ProjectTree.build` are both
  `@MainActor`-isolated (MUST, see `project-tree-main-actor-isolation`), and
  `ProjectTreeNode` declares no `Sendable` conformance (MUST, see
  `project-tree-node-non-sendable`), so the Swift compiler confines every
  node and every call to `build` to the main actor; this file defines no
  lock, no queue, and no other concurrency primitive of its own because the
  actor isolation is the only synchronization mechanism in play.
- **Error states**: No function in this file throws, returns an `Optional`
  the caller must unwrap and handle, or calls anything that can fail
  ("guard" statements here select control flow, not error propagation); a
  `GitRepo` whose path degenerates to an empty trail is dropped with no
  error path at all rather than surfacing a failure (see
  `project-tree-degenerate-path-dropped`).
- **Offline or disconnected state**: Not applicable — `ProjectTree.swift`
  makes no network call and depends on no connectivity; it operates purely
  on the in-memory `[GitRepo]` array and `URL` passed to `build`.
- **Missing file or unreachable directory**: Not applicable to this file
  itself — `build`, `trail(for:home:)`, and `standardized(_:)` derive every
  result from path strings alone and never call `FileManager` to check
  whether a `repo.path` exists on disk or is actually a directory; a `path`
  naming a location that no longer exists is placed in the tree exactly as
  if it still did.
- **Cancellation and timeouts**: Not applicable — `build` and every helper
  it calls (`trail(for:home:)`, `standardized(_:)`, `sortRecursively()`) are
  synchronous, non-`async`, in-memory computations over a caller-supplied
  array; none spawns a subprocess or a long-running operation that anything
  could cancel or that could time out.
- **Ordering and duplicate paths**: Two `GitRepo` values whose standardized
  `path` is byte-for-byte identical produce exactly one `ProjectTreeNode`
  (MUST, see `build-duplicate-leaf-path-dropped`, PT-009), but a `GitRepo`
  whose path equals a different `GitRepo`'s ancestor folder path produces
  two sibling nodes at that path — one folder, one project (see
  `project-tree-leaf-path-collision` — the open question on this behavior,
  PT-010). Which of the two repos in `repos` is processed first determines
  which node (folder or project) is created at a shared ancestor path first,
  since `build` iterates `repos` in the order given and never reorders it
  before building.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repos` (`ProjectTree.build`) | `[GitRepo]` | none — required | The flat registry rows to arrange into a tree; order within this array determines which node is created first at a shared ancestor path (see Edge Cases). |
| `homeDirectory` (`ProjectTree.build`) | `URL` | `FileManager.default.homeDirectoryForCurrentUser` | The directory whose own path components are omitted from the display, per `trail-under-home-truncation`. |

`ProjectTree.swift` reads no environment variable, settings key, or injected
dependency beyond these two parameters.

## Deep Linking

Not applicable: `ProjectTree.swift` defines no URL scheme, route, or
navigation destination — it only shapes an in-memory tree that
`ProjectBrowserViewController` later renders and navigates through its own
`NSOutlineView` selection, which is a separate component.

## Localization

Not applicable: `ProjectTree.swift` produces no hardcoded user-facing string
of its own. Every `name` a `ProjectTreeNode` displays is either echoed
verbatim from `repo.name` (a value the registry owns) or derived from a path
component string (`trail(for:home:)`'s `name`), never a literal sentence or
word this file authors itself — contrast `GitRepo.swift`'s `summaryText`,
which does build a hardcoded English sentence.

## Accessibility Options

Not applicable: `ProjectTree.swift` renders nothing, so Reduce Motion,
Increase Contrast, and Differentiate Without Color have nothing to apply to.

## Feature Flags

Not applicable: `ProjectTree.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `ProjectTree.swift` makes no analytics or event-tracking
call.

## Privacy

- **Data collected**: Every `ProjectTreeNode.path` is an absolute filesystem
  path, and on a typical macOS home directory that path embeds
  the user's account name for every node under `homeDirectory`; the folder
  names shown to the caller are themselves path components
  taken from that same path.
- **Storage**: None performed by this file — the returned `[ProjectTreeNode]`
  forest is a plain in-memory structure with no persistence code of its own;
  whatever holds a reference to it (`ProjectBrowserViewController`'s `roots`
  property) controls its lifetime.
- **Transmission**: None — `ProjectTree.swift` makes no network call.
- **Retention**: Not defined here; a returned forest's lifetime is entirely
  up to its caller, and nothing in this file caches or reuses a previous
  call's result.

## Logging

Not applicable: `ProjectTree.swift` contains no `Logger`, `os.log`, `print`,
or any other logging call — including on the path where a degenerate
`GitRepo` is silently dropped (see `project-tree-degenerate-path-dropped`).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTree.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [good-test-properties](agenticdevelopercookbook://compliance/best-practices#good-test-properties) | passed | Best Practices |

Notes: separation-of-concerns passes because `ProjectTree.swift` builds and
sorts an in-memory node graph only — no `NSOutlineView`, no `NSView`, and no
persistence or network code — leaving the tree's rendering entirely to
`ProjectBrowserViewController` and the `GitRepo` data shape to `GitRepo.swift`.
unit-test-coverage is partial because `ProjectTreeTests.swift` exercises
home-relative truncation, the outside-home leading slash, folder-before-project
sorting, registry-sourced naming, distinct-path folders, display order, and
the empty-input case (PT-001 through PT-008), but has no test for a duplicate
leaf path (PT-009) or for the folder/project path collision this recipe flags
as `project-tree-leaf-path-collision` (PT-010) — both are traced to the
source's control flow rather than to an assertion in the given suite.
good-test-properties passes because every test in `ProjectTreeTests.swift` is
a synchronous, `@MainActor`-isolated `XCTAssertEqual`/`XCTAssertTrue` call
against a locally constructed `[GitRepo]` array and a fixed `home` URL, with
no shared fixture, no I/O, and no ordering dependency between tests.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation; documents the leaf-path collision and degenerate-path open questions. |
