<!-- leaf: implement-git-client/projects-projects-coordinator--edge-cases · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator

**Rules** (cite as `implement-git-client/projects-projects-coordinator--edge-cases#<slug>`):

- `null-and-empty-input` MUST — rename(repoID:to:) called with a repoID not present in repos MUST be a no-op — repo(id:) returns nil and the guard …
- `boundary-values` MUST — This file performs no truncation, pagination, or count-based branching on the size of repos or found at any point — …
- `concurrent-access` MUST — A second scan(showingProgress:) call arriving while isScanning is already true MUST be dropped with no work performed …
- `error-states` MUST — Every database write this file performs directly (database.update in rename, database.markOpened in openProject, and …

## Edge Cases

- **Null and empty input**: `rename(repoID:to:)` called with a `repoID` not
  present in `repos` MUST be a no-op — `repo(id:)` returns `nil` and the
  guard exits before any trim or write (`ProjectsCoordinator.swift`). MUST. A `to:` argument that is empty, all-whitespace, or trims down
  to the unchanged current name MUST also be a no-op, performing no
  database write and no `reload()`. MUST. A `scan()` whose
  scanner reports zero repositories on disk MUST still run `finishScan`
  to completion; `ProjectReconciler.plan` with an empty `found` produces
  deletes for every currently known row `isStillARepository` does not
  excuse, so an empty scan is never distinguished at this layer from "the
  disk root genuinely lost every repository" — that distinction is
  `GitRepoScanner`'s and `ProjectReconciler`'s responsibility, not this
  file's. MUST.
- **Boundary values**: This file performs no truncation, pagination, or
  count-based branching on the size of `repos` or `found` at any point —
  zero, one, or many rows in `plan.inserts`/`plan.updates`/`plan.deletes`
  all take the identical per-row loop in `finishScan`
  (`ProjectsCoordinator.swift`). MUST.
- **Concurrent access**: A second `scan(showingProgress:)` call arriving
  while `isScanning` is already `true` MUST be dropped with no work
  performed and no queuing for a later run — the guard is the
  entire re-entrancy policy, and the inline comment states this is
  deliberate (`ProjectsCoordinator.swift`). MUST. The scan's
  own `Task.detached` continuation is not tracked by any stored handle, so
  `stop()` or `terminate()` racing an in-flight scan is not resolved by
  this file at all (see **scan-task-not-tracked**); every write inside
  `finishScan` is independently caught, so such a race cannot corrupt the
  database, only leave `isScanning` stuck `true` for that run.
- **Error states**: Every database write this file performs directly
  (`database.update` in `rename`, `database.markOpened` in `openProject`,
  and `database.insert`/`database.update`/`database.delete` in
  `finishScan`) is wrapped in its own `do`/`catch` and logs through
  `Self.logger.error` without propagating. MUST. Two read/checkpoint paths
  instead swallow through `try?` with no log call at all —
  `database.allRepos()` in `init`/`reload()`, and `database.checkpoint()`
  in `stop()` — see **database-read-failure-unsignaled** and
  **stop-checkpoint-failure-unsignaled**.
- **Offline or disconnected state**: Not applicable — `ProjectsCoordinator`
  makes no network call of its own. `ProjectDatabase` is a local SQLite
  file and `GitRepoScanner` walks the local filesystem; neither this file
  nor its direct collaborators depend on network reachability.
