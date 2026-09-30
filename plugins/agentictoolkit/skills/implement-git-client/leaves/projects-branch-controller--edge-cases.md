<!-- leaf: implement-git-client/projects-branch-controller--edge-cases · source: git-client-projects-branch-controller.md -->

# BranchController

**Rules** (cite as `implement-git-client/projects-branch-controller--edge-cases#<slug>`):

- `null-and-empty-input` MUST — A checkout constructed with branch: nil (a detached-HEAD or newly discovered worktree) leaves currentBranch nil until …
- `boundary-values` MUST — commands always returns exactly three entries, never zero or a variable count — there is no configuration that adds or …
- `concurrent-access` MUST — Every mutation of currentBranch and panes is confined to the main actor by @MainActor, so no interleaving can observe a …
- `error-states` MUST — GitClientError.executableNotFound, .launchFailed, .timedOut, and .commandFailed are not distinguished from one another …
- `cancellation-and-timeouts` MUST — The Task { [weak self] in await self?.refresh() } started by the Refresh Status command is unstructured; its handle is …
- `missing-file-or-unreachable-server` MUST — A checkout.directory that has been deleted (for example by git worktree remove running concurrently with a pending …

## Edge Cases

- **Null and empty input**: A checkout constructed with `branch: nil` (a
  detached-HEAD or newly discovered worktree) leaves `currentBranch` `nil`
  until the first successful `refresh()`; `displayName` falls back to
  `checkout.directory.lastPathComponent` for exactly that period (MUST, see
  **initial-branch-from-checkout**, **display-name-derivation**).
  `makeTabPane(edge:tabID:)` called before any pane exists always takes the
  "create" branch — there is no null/empty case to special-case, since
  `panes.allObjects` starts empty and the `first(where:)` scan simply finds
  nothing (MUST, see **pane-created-once-per-tab-per-edge**).
- **Boundary values**: `commands` always returns exactly three entries, never
  zero or a variable count — there is no configuration that adds or removes
  a command (MUST, see **commands-computed-per-access**). `panes` may hold
  zero entries (a checkout with no open tab yet); `refresh()`'s
  `for pane in panes.allObjects` loop over zero entries is not an error, it
  simply reloads nothing (MUST, see **refresh-always-reloads-panes**).
- **Concurrent access**: Every mutation of `currentBranch` and `panes` is
  confined to the main actor by `@MainActor`, so no interleaving can observe
  a torn write (MUST, see **main-actor-isolation**). `BranchController.refresh()`
  itself has no coalescing, generation counter, or in-flight guard of any
  kind — unlike its sibling `GitStatusProvider.refresh()` (see
  `agentictoolkit://recipes/file-system-git`), which explicitly coalesces
  overlapping calls into at most one queued follow-up and discards a stale
  response with a generation check. Two overlapping
  `BranchController.refresh()` calls (for example, two rapid Refresh Status
  invocations) each independently `await gitClient.currentBranch(in:)` and
  each independently assign `currentBranch` and reload every pane on
  completion; whichever call's git subprocess returns last wins, with no
  rule preferring the call that was *started* last over one that merely
  finished last; see the open question on refresh-ordering.
- **refresh-ordering**: NEEDS REVIEW: Not implemented in source. There is no ordering or coalescing rule for overlapping `refresh()` calls on one `BranchController`: whichever call's `gitClient.currentBranch(in:)` returns last sets `currentBranch` and reloads the panes, even if it was started first. `BranchControllerTests.swift` exercises only a single `refresh()` call; the app's worktree-scan and command-dispatch call sites, or a stress test issuing overlapping `refresh()` calls, would settle whether this is reachable in practice.
- **Error states**: `GitClientError.executableNotFound`, `.launchFailed`,
  `.timedOut`, and `.commandFailed` are not distinguished from one another
  by `refresh()`; every one is caught by the same unqualified `catch` and
  produces the same outcome — `currentBranch` unchanged, every pane still
  reloaded (MUST, see **refresh-preserves-branch-on-failure**,
  **refresh-always-reloads-panes**). The caller of the Refresh Status
  command has no way to learn that the branch read specifically failed,
  as distinct from succeeding with an unchanged value; the failure's only
  record is `GitCommandLog`, written by `GitClient.execute` (a collaborator,
  not this file — see `agentictoolkit://recipes/file-system-git`'s sibling
  `GitClient.swift`).
- **Offline or disconnected state**: Not applicable in the network sense —
  `gitClient.currentBranch(in:)` runs `git rev-parse --abbrev-ref HEAD`
  against the local working tree only; it makes no request to a remote and
  has no notion of connectivity. An unreadable or removed local `checkout.directory`
  is handled identically to any other `GitClientError` above.
- **Cancellation and timeouts**: The `Task { [weak self] in await
  self?.refresh() }` started by the Refresh Status command is unstructured;
  its handle is discarded, so nothing can cancel it once started
  (`BranchController.swift`). If `self` has already been
  deallocated by the time that task runs, `self?.refresh()` is a no-op; if
  `self` is still alive, the weak-to-strong promotion inside the `await`
  expression keeps the controller alive for the duration of that one call
  (MUST, see **refresh-status-command-effect**). `GitClientError.timedOut`
  reaches `refresh()` through the same generic catch as every other error
  (see Error states above); `BranchController` applies no timeout of its
  own.
- **Missing file or unreachable server**: A `checkout.directory` that has
  been deleted (for example by `git worktree remove` running concurrently
  with a pending refresh) surfaces only as whatever `GitClientError`
  `gitClient.currentBranch(in:)` produces for a missing directory, handled
  identically to Error states above (MUST). Neither
  **reveal-in-finder-command-effect** nor **copy-path-command-effect**
  checks that `directory` still exists before acting on it; a stale Reveal
  in Finder or Copy Path invocation is forwarded to AppKit/the pasteboard
  unchanged (MUST, see **captured-directory-outlives-controller**) — it is
  `ProjectController`'s job, not this file's, to unregister a checkout's
  commands once its directory is gone (`ProjectController.swift`'s
  `syncBranchControllers()`).
