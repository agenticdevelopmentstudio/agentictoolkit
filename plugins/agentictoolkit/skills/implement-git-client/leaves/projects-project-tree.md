<!-- leaf: implement-git-client/projects-project-tree · source: git-client-projects-project-tree.md -->

**Rules** (cite as `implement-git-client/projects-project-tree#<slug>`):

- `project-tree-node-stored-shape` MUST
- `project-tree-node-is-folder-derivation` MUST
- `project-tree-node-construction-restricted` MUST
- `repositories-in-display-order-leaf-passthrough` MUST
- `repositories-in-display-order-folder-recursion` MUST
- `build-default-home-directory` MUST
- `build-path-standardization` MUST
- `trail-under-home-detection` MUST
- `trail-under-home-truncation` MUST
- `trail-outside-home-leading-slash` MUST
- `trail-absolute-path-always-full` MUST
- `build-ancestor-reuse-by-path` MUST
- `build-ancestor-folder-creation` MUST
- `build-leaf-name-from-registry` MUST
- `build-duplicate-leaf-path-dropped` MUST
- `build-roots-sort-order` MUST
- `build-roots-name-tiebreak` MUST
- `build-recursive-sort` MUST
- `project-tree-main-actor-isolation` MUST
- `project-tree-node-non-sendable` MUST
- `build-empty-input-yields-empty-tree` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repos` (`ProjectTree.build`) | `[GitRepo]` | none — required | The flat registry rows to arrange into a tree; order within this array determines which node is created first at a shared ancestor path (see Edge Cases). |
| `homeDirectory` (`ProjectTree.build`) | `URL` | `FileManager.default.homeDirectoryForCurrentUser` | The directory whose own path components are omitted from the display, per `trail-under-home-truncation`. |

`ProjectTree.swift` reads no environment variable, settings key, or injected
dependency beyond these two parameters.

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

