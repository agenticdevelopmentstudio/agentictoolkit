<!-- leaf: implement-git-client/projects-project-window-manager--edge-cases · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager

**Rules** (cite as `implement-git-client/projects-project-window-manager--edge-cases#<slug>`):

- `null-and-empty-input` MUST — languageServicesFactory and commandRegistry being nil are documented, supported configurations, not gaps — …
- `boundary-values` MUST — openOrder and controllers may hold zero, one, or many project ids; every accessor derived from them (openWorkspaces, …
- `concurrent-access` MUST — Every mutation of controllers, openOrder, projectControllers, adoptedForScripting, and keyObservers is confined to the …
- `error-states` MUST — A thrown database.setting/setSetting call is logged and answered with a default (false for a read; the write simply …

## Edge Cases

- **Null and empty input**: `languageServicesFactory` and `commandRegistry`
  being `nil` are documented, supported configurations, not gaps —
  `openProject(_:)` logs and continues with no language services
  (**open-project-tolerates-missing-language-factory**), and every
  `commandRegistry?.register`/`unregister` call elsewhere becomes a no-op
  through optional chaining. `coordinator` being `nil` (never
  `attach`ed) makes `restoreOpenProjects()` a no-op
  (**restore-open-projects-requires-coordinator**); it also leaves
  `openProject(_:)` unable to pass its database guard — see
  **no-database-open-failure-signal** (SHOULD/MUST as annotated on each cited
  requirement).
- **Boundary values**: `openOrder` and `controllers` may hold zero, one, or
  many project ids; every accessor derived from them (`openWorkspaces`,
  `openWindowControllers`, `frontWindowController`'s final fallback) MUST
  handle zero entries by producing an empty array or `nil`, with no special
  case in the source for either end (MUST, by the absence
  of any guard).
- **Concurrent access**: Every mutation of `controllers`, `openOrder`,
  `projectControllers`, `adoptedForScripting`, and `keyObservers` is confined
  to the main actor (**main-actor-isolation**), so no interleaving between
  `openProject(_:)`, `closeProject(repoID:)`, `adoptForScripting(_:)`, and the
  notification-driven handlers can observe a torn collection (MUST). One race
  the source does guard explicitly: `openProject(_:)`'s completion `Task` and a later `closeProject(repoID:)` both reach the same
  `ProjectController`, and **callback-wiring-checks-current-controller**'s
  identity check is what stops a stale controller's callback from reaching a
  window that has moved on to a different controller (see vector -007).
- **Error states**: A thrown `database.setting`/`setSetting` call is logged
  and answered with a default (`false` for a read; the write simply does not
  happen) rather than propagated to any caller
  (**window-open-read-failure-defaults-closed**, **window-open-flag-read-write**
  — both MUST, by their `catch` blocks). `openProject(_:)`'s own
  database-missing guard is the one error path in this file with no signal at
  all beyond the log line; see
  **no-database-open-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense —
  every I/O this file performs is local: SQLite through `ProjectDatabase`, the
  filesystem check in `restorePlan`'s `existsOnDisk`, and git through
  `ProjectController`/`GitClient` (documented in
  `agentictoolkit://recipes/git-client-projects-project-controller`). None of
  it reaches a remote host.
- **Cancellation and timeouts**: `openProject(_:)`'s `Task { await
  projectController.open() }` is not cancelled by a subsequent
  `closeProject(repoID:)`; the in-flight task keeps running to completion, and
  it is `ProjectController`'s own `isClosed` guard — not anything in this file
  — that stops it from persisting stale data or reloading a dead window (see
  `agentictoolkit://recipes/git-client-projects-project-controller`'s
  reconcile-aborts-after-a-late-close requirement, and vector -007 above).
  `shutdownAllLanguageServices()` awaits its task group and then
  `closeTeardowns.drain()` unconditionally, with no timeout of its own; the
  roughly 2.5-second-per-server ceiling belongs to
  `SubprocessChannel.terminate()`, documented on `PendingTeardowns`.
- **Missing file or unreachable server**: A repo whose folder was deleted or
  renamed since the app last quit is not distinguished from any other
  flagged-open project until `restorePlan` checks `existsOnDisk`; it is moved
  to `plan.forget` and its persisted flag is cleared rather than reopened onto
  an empty tree (**restore-forgets-missing-folders**, see vector -011). A repo
  opened directly through `openProject(_:)` (not via restore) whose folder is
  already missing is not checked here at all — the workspace and controller
  are built regardless, and the resulting git failure is
  `ProjectController`'s to degrade gracefully from, not this file's.
