<!-- leaf: implement-git-client/projects-git-repo--edge-cases · source: git-client-projects-git-repo.md -->

# GitRepo

**Rules** (cite as `implement-git-client/projects-git-repo--edge-cases#<slug>`):

- `null-and-empty-input` MUST — path = "" is accepted unchanged by every initializer that takes it and is forwarded verbatim into url, …
- `boundary-values` MUST — A ProjectScanSummary with only removed set above zero reports found == 0 while summaryText still lists the removals, so …
- `concurrent-access` MUST — All three types are Sendable value types with no shared mutable reference state, no lock, and no actor isolation; every …
- `error-states` MUST — No initializer, and no computed property (url, defaultName(forPath:), leafName, found, summaryText), can throw or …
- `missing-file-or-unreachable-directory` MUST — A path naming a directory that no longer exists on disk, or that never held a .git directory, is not detected by …

## Edge Cases

- **Null and empty input**: `path = ""` is accepted unchanged by every
  initializer that takes it and is forwarded verbatim
  into `url`, `defaultName(forPath:)`, and `leafName`,
  each of which builds `URL(fileURLWithPath:)` from it; Foundation resolves
  an empty or relative string relative to the process's current working
  directory rather than throwing or returning `nil`, so an empty `path`
  never fails construction but the resulting `url`/name describe wherever
  the process happens to be running, not a repository (MUST — see
  `git-repo-path-absoluteness`).
  `remote = ""` is a distinct `Optional.some("")` value from `remote = nil`;
  neither type normalizes the two together (MUST).
- **Boundary values**: A `ProjectScanSummary` with only `removed` set above
  zero reports `found == 0` while `summaryText` still lists the removals, so
  a project count of zero can appear alongside a non-empty list of changes
  (MUST, see `scan-summary-found-excludes-removed`,
  git-client-projects-git-repo-006). `summaryText`'s singular/plural boundary
  is exactly `found == 1`; both `0` and every value `2` and above pluralize
  to "projects" (MUST, `scan-summary-text-headline-pluralization`).
- **Concurrent access**: All three types are `Sendable` value types with no
  shared mutable reference state, no lock, and no actor isolation; every read or write operates on the caller's own copy, so
  concurrent access to independently-held instances from multiple threads
  cannot race (MUST, see `sendable-value-semantics`). This file defines no
  singleton, static `var`, or other ambiently-shared instance for concurrent
  callers to contend over.
- **Error states**: No initializer, and no computed property (`url`,
  `defaultName(forPath:)`, `leafName`, `found`, `summaryText`), can throw or
  signal failure through an `Optional`; this file calls no network,
  database, or file-system API of its own, so it has no error path to
  define (MUST NOT be conflated with `GitClient`'s or `ProjectDatabase`'s
  error handling, which are separate components with their own sources).
- **Offline or disconnected state**: Not applicable — no type in this file
  makes a network call or depends on connectivity; `remote` only stores a
  URL string another component already read out of `.git/config`.
- **Missing file or unreachable directory**: A `path` naming a directory
  that no longer exists on disk, or that never held a `.git` directory, is
  not detected by anything in this file — `url`, `defaultName(forPath:)`,
  and `leafName` derive their result from the string alone, and none calls
  `FileManager` to check existence (MUST).
- **Cancellation and timeouts**: Not applicable — every operation in this
  file (`init`, `url`, `defaultName(forPath:)`, `leafName`, `found`,
  `summaryText`) is a synchronous, non-blocking computation over in-memory
  values; none is `async`, none spawns a subprocess, and none has anything
  to cancel or time out.
