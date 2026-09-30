<!-- leaf: implement-git-client/projects-project-tree--edge-cases · source: git-client-projects-project-tree.md -->

# ProjectTree

**Rules** (cite as `implement-git-client/projects-project-tree--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty repos array MUST yield roots == [] (MUST, see build-empty-input-yields-empty-tree, PT-008). A repo.path that …
- `boundary-values` MUST — A path exactly equal to home (not longer than it) is, by trail-under-home-detection, NOT treated as under home, so it …
- `concurrent-access` MUST — ProjectTreeNode and ProjectTree.build are both @MainActor-isolated (MUST, see project-tree-main-actor-isolation), and …
- `ordering-and-duplicate-paths` MUST — Two GitRepo values whose standardized path is byte-for-byte identical produce exactly one ProjectTreeNode (MUST, see …

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
