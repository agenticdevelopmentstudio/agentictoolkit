<!-- leaf: implement-git-client/projects-project-controller--edge-cases · source: git-client-projects-project-controller.md -->

# ProjectController

**Rules** (cite as `implement-git-client/projects-project-controller--edge-cases#<slug>`):

- `null-and-empty-input` MUST — A successful gitClient.worktrees(in:) call that reports zero non-bare worktrees MUST fall back to the single synthetic …
- `boundary-values` MUST — checkouts may hold exactly one entry (a repository with no linked worktrees) or many; the loops over plan.add and …
- `concurrent-access` MUST — open() and refreshCheckouts() MUST be safe to call concurrently because serializedReconcile() chains each call onto …
- `error-states` MUST — A GitClientError thrown by gitClient.worktrees(in:) (.executableNotFound, .launchFailed, .timedOut, .commandFailed) is …
- `cancellation-and-timeouts` MUST — serializedReconcile() awaits its internal Task to completion (await task.value, ProjectController.swift) rather than …

## Edge Cases

- **Null and empty input**: A successful `gitClient.worktrees(in:)` call that
  reports zero non-bare worktrees MUST fall back to the single synthetic main
  checkout at `workspace.directoryURL` (**checkouts-from-worktrees**; see
  vector -021). A project with no stored tabs at all (`workspace.storedTabs()
  == nil`) MUST always take the "changed" persistence path, because
  `stored == nil` short-circuits the `plan.isUnchanged` guard regardless of
  what the plan itself says (`ProjectController.swift`, MUST).
- **Boundary values**: `checkouts` may hold exactly one entry (a repository
  with no linked worktrees) or many; the loops over `plan.add` and
  `branchControllers.values` run zero, one, or many times with no special
  case for either end (MUST). `enabledEdges` defaults to the single edge
  `[.top]` (**default-enabled-edge**) when nothing was stored, so a project's
  very first reconcile always creates exactly one tab per checkout rather
  than one per available edge.
- **Concurrent access**: `open()` and `refreshCheckouts()` MUST be safe to
  call concurrently because `serializedReconcile()` chains each call onto
  whatever `inFlightReconcile` `Task` is already running, so two overlapping
  calls' git reads and database writes land in call order rather than
  completion order (**reconcile-calls-chain-in-order**; see vector -014).
  Every mutation of `checkouts`, `branchControllers`, and `isClosed` is
  confined to the main actor (**main-actor-isolation**), so no interleaving
  can observe a torn write. The one place serialization does not fully cover
  is **branch-refresh-close-race**: the per-branch-controller
  refresh loop inside `serializedReconcile()`'s `Task` does not re-check
  `isClosed` between iterations.
- **Error states**: A `GitClientError` thrown by `gitClient.worktrees(in:)`
  (`.executableNotFound`, `.launchFailed`, `.timedOut`, `.commandFailed`) is
  not distinguished by `readCheckouts()` — every case is caught by one
  unqualified `catch`, logged once without the git output, and answered with
  the last known `checkouts` or the synthetic fallback
  (**worktree-read-failure-keeps-last-known**, MUST). A failure inside
  `workspace.persistTabs` is logged there and not detected by this file; see
  **persist-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense —
  `gitClient.worktrees(in:)` runs `git worktree list --porcelain` against the
  local working tree only, per `GitClient.swift`'s `worktrees(in:)`; it makes
  no request to a remote. An unreadable or removed `workspace.directoryURL`
  is handled identically to any other `GitClientError` above.
- **Cancellation and timeouts**: `serializedReconcile()` awaits its internal
  `Task` to completion (`await task.value`, `ProjectController.swift`) rather than racing it against a timeout of its own; `GitClientError
  .timedOut` reaches `readCheckouts()` through the same generic catch as
  every other error (see Error states above). Neither `open()` nor
  `refreshCheckouts()` checks `Task.isCancelled`; Swift's cooperative
  cancellation of the calling context is the only cancellation path that
  reaches this controller (MUST, by absence).
- **Missing file or unreachable server**: A checkout directory removed out
  from under the project (`git worktree remove` racing a pending reconcile)
  is not distinguished from any other git failure inside `readCheckouts()`;
  `syncBranchControllers()` drops that checkout's `BranchController` and
  unregisters its commands on the *next* successful reconcile, not
  immediately (**branch-controllers-dropped-with-their-commands**; see
  vectors -004, -007).
