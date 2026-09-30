<!-- leaf: implement-git-client/projects-project-checkout--edge-cases · source: git-client-projects-project-checkout.md -->

# ProjectCheckout

**Rules** (cite as `implement-git-client/projects-project-checkout--edge-cases#<slug>`):

- `null-and-empty-input` MUST — branch == nil MUST fall back displayName to directory.lastPathComponent rather than producing an empty or placeholder …
- `boundary-values` MUST — A directory whose path is the single-character root / MUST still produce a deterministic, non-empty hexadecimal …
- `concurrent-access` MUST — ProjectCheckout MUST be readable, comparable, and hashable concurrently from multiple threads or actors with no …
- `error-states` MUST — resolvingSymlinksInPath() is a non-throwing API, and init(directory:branch:isMain:) has no throws and no error-handling …
- `duplicate-worktree-entries` MUST — When worktrees passed to checkouts(from:) contains two entries with the same directory, checkouts(from:) MUST produce …

## Edge Cases

- **Null and empty input**: `branch == nil` MUST fall back `displayName` to
  `directory.lastPathComponent` rather than producing an empty or placeholder
  string (`ProjectCheckout.swift`). MUST. An empty `worktrees`
  array passed to `checkouts(from:)` MUST return an empty array, since
  `filter` and `map` over an empty collection produce no elements
  (`ProjectCheckout.swift`). MUST.
- **Boundary values**: A `directory` whose `path` is the single-character
  root `/` MUST still produce a deterministic, non-empty hexadecimal
  `identifier`, since the djb2 loop only iterates over
  `directory.path.utf8` and has no special case for a short path
  (`ProjectCheckout.swift`). MUST.
- **Concurrent access**: `ProjectCheckout` MUST be readable, comparable, and
  hashable concurrently from multiple threads or actors with no
  synchronization, because it is `Sendable`, every stored property is
  immutable, and `identifier`/`displayName` are pure computations with no
  shared mutable state (`ProjectCheckout.swift`). MUST.
  `checkouts(from:)` is a `static func` with no shared state of its own, so
  concurrent calls on different `worktrees` arguments MUST NOT interfere
  with one another (`ProjectCheckout.swift`). MUST.
- **Error states**: `resolvingSymlinksInPath()` is a non-throwing API, and
  `init(directory:branch:isMain:)` has no `throws` and no error-handling
  path at all; when `directory` names a path that does not exist on disk,
  the initializer MUST NOT raise or surface an error — it stores whatever
  `resolvingSymlinksInPath()` returns, which is a best-effort result rather
  than a validated one (`ProjectCheckout.swift`). MUST (this is
  a fact about a non-throwing API, not a swallowed error — there is no
  throwing call here to swallow).
- **Offline or disconnected state**: Not applicable — `ProjectCheckout.swift`
  makes no network call; `directory`, `branch`, and `isMain` are supplied by
  the caller or derived from a `GitWorktree` value already read from local
  disk (`ProjectCheckout.swift`, entire file).
- **Duplicate worktree entries**: When `worktrees` passed to
  `checkouts(from:)` contains two entries with the same `directory`,
  `checkouts(from:)` MUST produce two separate `ProjectCheckout` values
  rather than deduplicating them, since `.map` performs a strict one-to-one
  projection with no `Set` or dedup step (`ProjectCheckout.swift`). MUST.
