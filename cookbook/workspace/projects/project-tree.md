---
id: 8f0a3e2b-4d61-4a2f-9e4d-6c1a7b3f0d92
title: Project Tree
domain: agentictoolkit://cookbook/workspace/projects/project-tree
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Arranges a flat registry of repository rows into the folder-then-project tree the project chooser displays, home-relative and alphabetically sorted.
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
- agentictoolkit://cookbook/workspace/projects/git-repo
- agentictoolkit://cookbook/workspace/projects/project-filter
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTree.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectBrowserViewController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectTreeTests.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Tree

## Overview

This turns a flat registry of repository rows into the hierarchy the
project chooser draws: folders on the way to a project, and the projects
themselves. A tree node is the row type — a folder when it holds no
repository, a project when it holds one — and the builder is the
operation that builds and sorts a forest of those rows from the registry
and a home directory. Paths inside the caller's home directory are shown
relative to it, "so the top of the list is `Development` and
`Deployments` rather than three levels of `Users/<name>` that are the same
for everything" (source documentation); a path outside home keeps its
leading slash, "the only thing distinguishing `/opt` from a folder of the
user's called `opt`". The one caller in the given sources is the project
browser, which builds the tree from the current registry and exposes the
returned roots and every node's `children` directly to its outline view
as its data source.

## Behavioral Requirements

- **project-tree-node-stored-shape**: a tree node MUST store exactly four
  properties — `name` (string), `repo` (an optional repository
  reference), `path` (string), and `children` (a list of tree nodes), the
  last exposed read-only and defaulting to an empty list — set through
  construction restricted to this component.
- **project-tree-node-is-folder-derivation**: `isFolder` MUST be a
  computed property that returns whether `repo` is absent; a node is a
  folder if and only if it was constructed with no repository.
- **project-tree-node-construction-restricted**: construction and
  child-appending MUST both be restricted to this component; no other
  component MUST be able to construct a tree node or append a child to an
  existing one directly — only the tree-building operation MUST be able
  to shape the tree.
- **repositories-in-display-order-leaf-passthrough**: `repositoriesInDisplayOrder`
  MUST return itself as a single-element list immediately, without
  inspecting `children`, when the node holds a repository.
- **repositories-in-display-order-folder-recursion**: when the node holds
  no repository, `repositoriesInDisplayOrder` MUST return the flattened
  concatenation of every child's own `repositoriesInDisplayOrder`, so the
  flattened result MUST contain only nodes that hold a repository, in the
  same depth-first order `children` is stored in at every level.
- **build-default-home-directory**: the tree-building operation's
  home-directory input MUST default to the current user's home directory,
  evaluated once per call when the caller supplies no explicit value.
- **build-path-standardization**: before computing anything else, building
  the tree MUST reduce both the home directory's path and every
  repository's path through the same path-standardization step, which
  strips exactly one trailing `"/"` when the string is longer than one
  character and leaves every other string unchanged — MUST NOT collapse
  repeated slashes, resolve `".."` or `"~"`, or normalize case.
- **trail-under-home-detection**: computing a path's trail MUST classify a
  path as under home only when its component count is strictly greater
  than home's component count AND its first components equal home's
  components exactly; a path identical to home itself MUST NOT be
  classified as under home.
- **trail-under-home-truncation**: for a path classified as under home,
  computing its trail MUST start the returned trail at the first
  component after home's own components, omitting every component of
  home itself from both the trail's names and its count.
- **trail-outside-home-leading-slash**: for a path NOT classified as under
  home, computing its trail MUST prepend `"/"` to the name of the trail's
  first component only; the name of every other component, at any depth,
  MUST have no leading slash.
- **trail-absolute-path-always-full**: every trail entry's path MUST be
  computed as the full absolute path from the filesystem root through
  that component, regardless of whether that component's displayed name
  was truncated for being under home; two folders with the same displayed
  name under different ancestors MUST therefore be tracked as distinct
  entries because their path values differ.
- **build-ancestor-reuse-by-path**: for each ancestor step in a
  repository's trail (every entry except the last), building the tree
  MUST reuse the existing tree node already registered at that step's
  path, if one exists, as the parent for the next step, and MUST NOT
  create a second node for the same path; this reuse check MUST NOT
  inspect the existing node's folder-or-project state before treating it
  as the parent.
- **build-ancestor-folder-creation**: when no node is yet registered at an
  ancestor step's path, building the tree MUST construct a new folder
  node, register it at that path, and append it to the running parent (or
  to the roots when there is no parent yet) before continuing to the next
  step.
- **build-leaf-name-from-registry**: the tree node building constructs for
  a repository's leaf MUST take its `name` from the repository's own
  name, never from the trail-computed component name that a path-only
  derivation would have produced.
- **build-duplicate-leaf-path-dropped**: when a node is already registered
  at the leaf's path and that node holds a repository, building the tree
  MUST skip constructing a second node for the current repository and
  MUST NOT add it to the tree, because "the registry allows [two rows for
  one path] and this must not duplicate".
- **build-roots-sort-order**: building the tree MUST sort the roots so
  every folder sorts before every project, and MUST NOT consider `name`
  when two roots differ in folder-or-project state.
- **build-roots-name-tiebreak**: within two roots of the same
  folder-or-project state, building the tree MUST order them by a
  locale-aware, case-insensitive comparison of `name`, ascending.
- **build-recursive-sort**: after sorting the roots, building the tree
  MUST recursively apply the same sort so every node's `children`, at
  every depth of the resulting forest, is sorted by the same
  folders-first, case-insensitive-alphabetical rule.
- **main-thread-confinement**: a tree node and the tree-building operation
  MUST both be confined to the UI's main execution context; a caller on
  any other execution context MUST cross through that context to call the
  build operation or to read or mutate a tree node's `children`.
- **build-empty-input-yields-empty-tree**: building the tree from an empty
  registry MUST return an empty array; nothing in the build loop runs
  when the registry is empty, so the roots MUST stay empty.
- **project-tree-leaf-path-collision**: NEEDS REVIEW: Not implemented in
  source. When a repository's leaf path was already registered as a
  folder node (created earlier as another repository's ancestor step),
  the reuse guard does not match, so building the tree falls through and
  constructs a second, project-flavored tree node at that same path,
  overwrites the registration to point at it, and appends it to the
  parent (or roots) without ever removing the earlier folder node, which
  is still present in that same parent's children from when it was
  created; the two sibling nodes (one folder, one project) at the
  identical path are both rendered by the project browser's outline view,
  contradicting the file's own stated intent that a path "must not
  duplicate" — missing is a rule for whether the folder should be
  replaced, merged, or kept alongside the project, and the evidence that
  would settle it is a test exercising a repository whose path equals
  another repository's ancestor folder path, or the authors' intended
  precedence between a folder and a project claiming the same path.
- **project-tree-degenerate-path-dropped**: NEEDS REVIEW: Not implemented
  in source. Computing a path's trail returns an empty list for any path
  whose standardized form splits into zero components (for example the
  root path `/`, which the standardization step leaves unchanged because
  its length is not greater than 1); building the tree then silently
  drops that repository from the tree entirely, appearing in no root, no
  folder, and no count, with no error, no log call, and no signal of any
  kind reaching the caller — missing is whether such a repository should
  be surfaced some other way (an error row, a log line) rather than
  vanishing, and the evidence that would settle it is a test constructing
  a repository with a degenerate path and asserting on the intended
  outcome, or a product decision on how the project chooser should
  represent it.

## Appearance

Not applicable — this is a tree-building data structure and algorithm, not a
visual component.

## States

Not applicable — this is a tree-building data structure and algorithm, not a
visual component. The tree-building operation has no runtime state machine
of its own: it is called anew, synchronously, every time the project
browser needs a fresh tree; nothing in this file remembers a previous
call's result.

## Accessibility

Not applicable — this is a tree-building data structure and algorithm, not a
visual component. The outline view that renders the nodes this file
produces is a separate component (the project browser) with its own
accessibility surface, not given in these sources.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| PT-001 | build-ancestor-folder-creation, trail-under-home-truncation, build-leaf-name-from-registry | Build the tree from two repositories at `/Users/someone/Development/projects/whippet` and `/Users/someone/Development/projects/adh`, with home directory `/Users/someone`. | the roots read `Development`; its children read `projects`; that folder's children read `adh`, `whippet` — ProjectTreeTests.swift › testProjectsAppearUnderTheFoldersThatHoldThem |
| PT-002 | trail-under-home-truncation | Build the tree from one repository at `/Users/someone/dev/alpha`, with home directory `/Users/someone`. | the roots read `dev` — ProjectTreeTests.swift › testTheHomeDirectoryIsNotShownAsFolders |
| PT-003 | trail-outside-home-leading-slash | Build the tree from one repository at `/opt/checkouts/alpha`, with home directory `/Users/someone`. | the roots read `/opt`; its children read `checkouts` — ProjectTreeTests.swift › testAPathOutsideHomeKeepsItsLeadingSlash |
| PT-004 | build-roots-name-tiebreak, build-recursive-sort | Build the tree from three repositories at `/Users/someone/dev/zeta`, `/Users/someone/dev/alpha`, and `/Users/someone/dev/nested/beta`, with home directory `/Users/someone`. | the `dev` folder's children read `nested`, `alpha`, `zeta` — folder before both projects, projects alphabetical — ProjectTreeTests.swift › testFoldersSortBeforeProjectsAndBothSortAlphabetically |
| PT-005 | build-leaf-name-from-registry | Build the tree from one repository at `/Users/someone/dev/alpha` whose registry name is `Alpha (main)`, with home directory `/Users/someone`. | the `dev` folder's children read `Alpha (main)` — ProjectTreeTests.swift › testAProjectRowTakesItsNameFromTheRegistry |
| PT-006 | trail-absolute-path-always-full | Build the tree from two repositories at `/Users/someone/work/src/alpha` and `/Users/someone/play/src/beta`, with home directory `/Users/someone`. | the roots read `play`, `work`; the `play` branch's `src` folder holds `beta`; the `work` branch's `src` folder holds `alpha` — two `src` folders under different parents stay distinct — ProjectTreeTests.swift › testTwoTreesWithSameNamedFoldersDoNotCollapseIntoOne |
| PT-007 | repositories-in-display-order-leaf-passthrough, repositories-in-display-order-folder-recursion | Build the tree from three repositories at `/Users/someone/dev/zeta`, `/Users/someone/dev/nested/beta`, and `/Users/someone/dev/alpha`, with home directory `/Users/someone`, then read every root's repositories in display order. | reads `beta`, `alpha`, `zeta` — ProjectTreeTests.swift › testTheProjectsAreReadableInDisplayOrder |
| PT-008 | build-empty-input-yields-empty-tree | Build the tree from an empty registry, with home directory `/Users/someone`. | the result is empty — ProjectTreeTests.swift › testAnEmptyRegistryBuildsAnEmptyTree |
| PT-009 | build-duplicate-leaf-path-dropped | Build the tree from two repositories that both resolve to the identical path `/Users/someone/dev/alpha`, named `Alpha` and `Alpha Copy` respectively, with home directory `/Users/someone`. | the `dev` folder has exactly one child, named `Alpha` — the second repository at the identical path is dropped (no dedicated test in the given suite) |
| PT-010 | project-tree-leaf-path-collision | Build the tree from two repositories at `/Users/someone/dev/sub/nested` and `/Users/someone/dev/sub`, with home directory `/Users/someone`. | the `dev` folder's children contain two entries named `sub` — one folder (created as the ancestor of `nested`) and one project (the second repository, whose own path equals that ancestor's) — the open question this recipe flags; no test in the given suite exercises this input |

## Edge Cases

- **Null and empty input**: An empty registry MUST yield empty roots
  (MUST, see `build-empty-input-yields-empty-tree`, PT-008). A repository
  path that standardizes to a string with zero `"/"`-separated components
  (for example `"/"`) makes the trail computation return an empty list,
  and building the tree silently omits that repository from the tree (see
  `project-tree-degenerate-path-dropped` — the open question on this
  behavior).
- **Boundary values**: A path exactly equal to home (not longer than it)
  is, by `trail-under-home-detection`, NOT treated as under home, so it is
  shown with its full absolute component list rather than collapsed to
  nothing (MUST). The path-standardization step's trailing-slash strip
  only fires when the path's length is greater than 1, so the
  single-character path `"/"` is left as `"/"` rather than becoming an
  empty string (MUST).
- **Concurrent access**: a tree node and the tree-building operation are
  both confined to a single execution context (MUST, see
  `main-thread-confinement`), and a tree node offers no cross-context
  sharing guarantee of its own (see the concurrency note in Platform
  Notes), so cross-context access must go through that confinement; this
  file defines no lock, no queue, and no other concurrency primitive of
  its own because that confinement is the only synchronization mechanism
  in play.
- **Error states**: No function in this file throws, returns an optional
  the caller must unwrap and handle, or calls anything that can fail
  (conditional-exit statements here select control flow, not error
  propagation); a repository whose path degenerates to an empty trail is
  dropped with no error path at all rather than surfacing a failure (see
  `project-tree-degenerate-path-dropped`).
- **Offline or disconnected state**: Not applicable — this file makes no
  network call and depends on no connectivity; it operates purely on the
  in-memory registry and home-directory reference passed to the build
  operation.
- **Missing file or unreachable directory**: Not applicable to this file
  itself — building the tree, computing a path's trail, and the
  path-standardization step derive every result from path strings alone
  and never check whether a repository's path exists on disk or is
  actually a directory; a path naming a location that no longer exists is
  placed in the tree exactly as if it still did.
- **Cancellation and timeouts**: Not applicable — building the tree and
  every helper it calls (trail computation, path standardization,
  recursive sort) are synchronous, non-asynchronous, in-memory
  computations over a caller-supplied list; none spawns a subprocess or a
  long-running operation that anything could cancel or that could time
  out.
- **Ordering and duplicate paths**: Two repositories whose standardized
  path is byte-for-byte identical produce exactly one tree node (MUST, see
  `build-duplicate-leaf-path-dropped`, PT-009), but a repository whose
  path equals a different repository's ancestor folder path produces two
  sibling nodes at that path — one folder, one project (see
  `project-tree-leaf-path-collision` — the open question on this
  behavior, PT-010). Which of the two repositories in the registry is
  processed first determines which node (folder or project) is created
  at a shared ancestor path first, since building the tree iterates the
  registry in the order given and never reorders it before building.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repos` (build input) | list of repositories | none — required | The flat registry rows to arrange into a tree; order within this list determines which node is created first at a shared ancestor path (see Edge Cases). |
| `homeDirectory` (build input) | directory reference | the current user's home directory | The directory whose own path components are omitted from the display, per `trail-under-home-truncation`. |

This file reads no environment variable, settings key, or injected
dependency beyond these two parameters.

## Deep Linking

Not applicable: this file defines no URL scheme, route, or navigation
destination — it only shapes an in-memory tree that the project browser
later renders and navigates through its own selection mechanism, which is
a separate component.

## Localization

Not applicable: this file produces no hardcoded user-facing string of its
own. Every `name` a tree node displays is either echoed verbatim from the
repository's own name (a value the registry owns) or derived from a path
component string, never a literal sentence or word this file authors
itself — contrast the repository's own summary text, which does build a
hardcoded English sentence.

## Accessibility Options

Not applicable: this file renders nothing, so Reduce Motion, Increase
Contrast, and Differentiate Without Color have nothing to apply to.

## Feature Flags

Not applicable: this file contains no feature-flag or build-configuration
check of any kind.

## Analytics

Not applicable: this file makes no analytics or event-tracking call.

## Privacy

- **Data collected**: Every tree node's path is an absolute filesystem
  path, and on a typical home directory that path embeds the user's
  account name for every node under the home directory; the folder names
  shown to the caller are themselves path components taken from that same
  path.
- **Storage**: None performed by this file — the returned forest is a
  plain in-memory structure with no persistence code of its own; whatever
  holds a reference to it controls its lifetime.
- **Transmission**: None — this file makes no network call.
- **Retention**: Not defined here; a returned forest's lifetime is
  entirely up to its caller, and nothing in this file caches or reuses a
  previous call's result.

## Logging

Not applicable: this file contains no logging call of any kind —
including on the path where a degenerate repository is silently dropped
(see `project-tree-degenerate-path-dropped`).

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTree.swift`,
  tested by
  `Tests/AgenticToolkitMacOSTests/Projects/ProjectTreeTests.swift`; it
  imports only `Foundation` and depends on no AppKit, UIKit, or SwiftUI type,
  so it ports unchanged into a SwiftUI-hosted app. A SwiftUI `List` or
  `OutlineGroup` would bind directly to the returned `[ProjectTreeNode]`
  roots and each node's `children`, exactly as `ProjectBrowserViewController`
  binds its `NSOutlineView` today. `ProjectTreeNode` MUST NOT declare
  `Sendable` conformance; because it is a `public final class` holding
  mutable reference state (`children`) with no such conformance, the
  compiler keeps every value of this type confined to the `@MainActor`
  isolation domain it was created in — no caller in the given sources
  passes a `ProjectTreeNode` across isolation domains (contrast
  `GitRepo`'s `Sendable` conformance in `GitRepo.swift`).
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation; documents the leaf-path collision and degenerate-path open questions. |
