<!-- leaf: implement-git-client/projects-projects-coordinator--part-2 · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator — continued (part 2)

**Rules** (cite as `implement-git-client/projects-projects-coordinator--part-2#<slug>`):

- `did-change-notification-shape` MUST
- `repos-initial-load` MUST
- `command-registry-required` MUST
- `menu-contributions-two-file-items` MUST
- `set-opener-replaces-unconditionally` MUST
- `start-triggers-default-scan` MUST
- `stop-checkpoints-database` MUST
- `terminate-casts-opener-for-language-services` MUST
- `repo-lookup-by-id` MUST
- `rename-trims-and-guards-no-op` MUST
- `rename-persists-then-reloads-or-logs` MUST
- `open-project-marks-reloads-then-opens` MUST
- `show-project-chooser-delegates-to-open` MUST
- `reload-refreshes-then-notifies-unconditionally` MUST
- `scan-guards-reentrancy` MUST
- `scan-progress-window-conditional` MUST
- `scan-uses-injected-or-fresh-scanner` MUST
- `scan-runs-detached-then-hops-main` MUST
- `finish-scan-builds-plan-from-current-repos` MUST
- `finish-scan-inserts-decrement-on-failure` MUST
- `finish-scan-closes-windows-before-deleting` MUST
- `finish-scan-deletes-decrement-and-clear-frames` MUST
- `finish-scan-final-state-order` MUST
- `finish-scan-logs-completion-and-dismisses-progress` MUST
- `loggable-conformance` MUST

## Behavioral Requirements

- **did-change-notification-shape**: `ProjectsCoordinator.didChangeNotification`
  MUST be the `Notification.Name` `"ProjectsCoordinatorDidChange"` and MUST
  carry no payload — the doc comment states readers MUST re-read `repos`
  directly, which is "the one representation of that knowledge"
  (`ProjectsCoordinator.swift`).
- **repos-initial-load**: `init(database:scanner:opener:commandRegistry:)`
  MUST populate `repos` by calling `database.allRepos()` exactly once
  through `try?`, so a thrown error leaves `repos` at its default empty
  array rather than propagating out of `init` (`ProjectsCoordinator.swift`).
- **command-registry-required**: `init` MUST register
  `AppCommand(id: CommandID.openProject, title: "Open Project…", category:
  "Projects", ...)` and `AppCommand(id: CommandID.scanForProjects, title:
  "Scan for Projects", category: "Projects", ...)` on the caller-supplied
  `registry`, and the `commandRegistry` parameter carries no default value —
  the doc comment states this is deliberate so a missing registry fails at
  compile time rather than silently dropping every menu item this feature
  contributes (`ProjectsCoordinator.swift`).
- **menu-contributions-two-file-items**: `init` MUST set `menuContributions`
  to exactly two `MenuContribution` values, both in the `.file` slot: "Open
  Project…" at `order: 0` with key `"p"` and modifiers `[.command, .option]`,
  dispatching through `commandID: CommandID.openProject`; and "Scan for
  Projects" at `order: 10`, dispatching through `commandID:
  CommandID.scanForProjects`, with `isHidden` returning `self.isScanning`
  (`ProjectsCoordinator.swift`).
- **set-opener-replaces-unconditionally**: `setOpener(_:)` MUST replace
  `opener` with the argument regardless of whether one was already set
  (`ProjectsCoordinator.swift`).
- **start-triggers-default-scan**: `start() throws` MUST call `scan()`
  (its default `showingProgress: true`); the method is declared `throws`
  to satisfy `AppFeature`'s override signature but its body contains no
  throwing statement (`ProjectsCoordinator.swift`).
- **stop-checkpoints-database**: `stop()` MUST call `database.checkpoint()`
  (`ProjectsCoordinator.swift`).
- **terminate-casts-opener-for-language-services**: `terminate() async`
  MUST attempt to cast `opener` to `ProjectWindowManager`; when the cast
  succeeds it MUST `await` `shutdownAllLanguageServices()` on it; when the
  cast fails — `opener` is `nil` or a different `ProjectOpening`
  implementation — `terminate()` MUST return immediately having done
  nothing further. The doc comment states the cast is deliberate: widening
  `ProjectOpening` itself to carry an LSP concern "would push an LSP concern
  into the protocol the registry is tested against" (`ProjectsCoordinator.swift`).
- **repo-lookup-by-id**: `repo(id:)` MUST return the first element of
  `repos` whose `id` equals the argument, or `nil` when none matches
  (`ProjectsCoordinator.swift`).
- **rename-trims-and-guards-no-op**: `rename(repoID:to:)` MUST return with
  no effect when `repo(id: repoID)` finds nothing; MUST trim the `to:`
  argument of leading and trailing whitespace and newlines; and MUST return
  with no effect — no database write, no `reload()` — when the trimmed name
  is empty or equal to the repo's current `name` (`ProjectsCoordinator.swift`).
- **rename-persists-then-reloads-or-logs**: When the trimmed name is
  non-empty and differs from the current name, `rename(repoID:to:)` MUST
  set the local copy's `name` to the trimmed value and MUST call
  `database.update(repo)`; on success it MUST call `reload()`; on failure
  it MUST catch the thrown error, log it through `Self.logger.error` with
  `repoID.uuidString` at `privacy: .public`, and MUST NOT call `reload()`
  on that path (`ProjectsCoordinator.swift`).
- **open-project-marks-reloads-then-opens**: `openProject(_:)` MUST call
  `database.markOpened(id: repo.id)`, catching and logging any thrown
  error through `Self.logger.error` without propagating it; MUST then
  unconditionally call `reload()`, regardless of whether `markOpened`
  succeeded; and MUST call `opener?.openProject(repo)` last, after the
  reload (`ProjectsCoordinator.swift`).
- **show-project-chooser-delegates-to-open**: `showProjectChooser()` MUST
  present `ProjectChooserWindow.choose(from: self, onChoose:)`, and the
  `onChoose` closure it supplies MUST call `self.openProject(repo)` for
  whatever repo the chooser passes back (`ProjectsCoordinator.swift`).
- **reload-refreshes-then-notifies-unconditionally**: `reload()` MUST
  reassign `repos` from `try? database.allRepos()`, falling back to the
  existing `repos` value unchanged when that read fails, and MUST then
  post `didChangeNotification` on `NotificationCenter.default`
  unconditionally — even on the path where the read failed and `repos`
  did not actually change (`ProjectsCoordinator.swift`).
- **scan-guards-reentrancy**: `scan(showingProgress:)` MUST return
  immediately, performing no work, when `isScanning` is already `true`;
  otherwise it MUST set `isScanning = true` before doing anything else.
  The inline comment states the policy is deliberate: "two scans of the
  same disk produce the same answer, so the second is waste"
  (`ProjectsCoordinator.swift`).
- **scan-progress-window-conditional**: When `showingProgress` is `true`
  (the default), `scan(...)` MUST construct a `ProjectScanProgressWindow`,
  call `present()` on it, and store it in `progressWindow`; when `false`,
  it MUST leave `progressWindow` untouched (`ProjectsCoordinator.swift`).
- **scan-uses-injected-or-fresh-scanner**: `scan(...)` MUST use
  `injectedScanner` when it is non-`nil`; otherwise it MUST construct a
  fresh `GitRepoScanner` seeded with `UserSettings.projectScanSkipPatterns
  .currentValue` read at the moment `scan(...)` runs, not cached from
  `init` time, so an edited skip list takes effect on the next scan
  (`ProjectsCoordinator.swift`).
- **scan-runs-detached-then-hops-main**: `scan(...)` MUST run the chosen
  scanner's `scan()` inside `Task.detached(priority: .utility)`, off the
  main actor, and MUST hand the result to `finishScan(found:)` through
  `MainActor.run` (`ProjectsCoordinator.swift`).
- **finish-scan-builds-plan-from-current-repos**: `finishScan(found:)` MUST
  compute `plan` via `ProjectReconciler.plan(existing: repos, scanned:
  found)` and MUST seed `summary` as a copy of `plan.summary`
  (`ProjectsCoordinator.swift`).
- **finish-scan-inserts-decrement-on-failure**: For each repo in
  `plan.inserts`, `finishScan` MUST call `database.insert(repo)`; on
  failure it MUST decrement `summary.added` by one and log the error with
  `repo.path` at `privacy: .public`, then MUST continue to the next insert
  rather than aborting the loop (`ProjectsCoordinator.swift`).
- **finish-scan-closes-windows-before-deleting**: `finishScan` MUST call
  `opener?.closeProject(repoID:)` for every repo in `plan.deletes` in a
  pass that completes entirely before the delete pass begins. The inline
  comment states the reason: closing a window writes to the row it
  belongs to, "which after the delete is a foreign key that no longer
  resolves" (`ProjectsCoordinator.swift`).
- **finish-scan-deletes-decrement-and-clear-frames**: For each repo in
  `plan.deletes`, `finishScan` MUST call `database.delete(id: repo.id)`;
  on failure it MUST decrement `summary.removed`, log the error with
  `repo.path` at `privacy: .public`, and `continue` — skipping the frame
  cleanup below — rather than abort the loop; on success it MUST clear
  both the saved state and the visibility of `WindowManager.shared.frames`
  for `ComposableTabsWindowController.windowID(for: repo.id)`
  (`ProjectsCoordinator.swift`).
- **finish-scan-final-state-order**: After all three loops, `finishScan`
  MUST set `lastScanSummary = summary`, MUST set `isScanning = false`, and
  MUST call `reload()`, in that order, before logging completion and
  dismissing the progress window (`ProjectsCoordinator.swift`).
- **finish-scan-logs-completion-and-dismisses-progress**: `finishScan`
  MUST log `summary.summaryText` at `.info` level with `privacy: .public`,
  and MUST call `progressWindow?.finish()` followed by setting
  `progressWindow = nil`, regardless of whether any of the three loops
  above logged an error of its own (`ProjectsCoordinator.swift`).
- **loggable-conformance**: `ProjectsCoordinator` MUST conform to
  `Loggable` with a `nonisolated static let logger` built by
  `makeLogger()` (`ProjectsCoordinator.swift`).
- **database-read-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. Both `init`'s initial load (`try? database.allRepos()`) and `reload()` (the same call) discard any thrown error with no logging call and no way for a caller to distinguish "the registry is genuinely empty" from "the read just failed" — unlike every other database failure path in this file, which each log through `Self.logger.error` (`rename`, `openProject`, and all three `finishScan` loops). What is missing: a log call, or a way for a caller to detect a failed reload versus an empty result. What would settle it: either addition, or a doc comment stating the silence is intentional because a failed read is expected to be transient and self-correcting on the next `reload()`.
- **stop-checkpoint-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. `stop()`'s `try? database.checkpoint()` discards a checkpoint failure with no logging call at all, the only write-adjacent database call in this file that neither logs nor otherwise surfaces its outcome. What is missing: a log call on the caught path, matching the pattern every other database call in this file follows. What would settle it: adding one, or a doc comment stating why a failed checkpoint at shutdown needs no signal.
- **scan-task-not-tracked**: The `Task.detached` scan-and-reconcile continuation started by `scan(...)` is not stored, awaited, or cancellable: `stop()` and `terminate()` can both run while it is in flight, and neither waits for or cancels it. Contrast `terminate()`, whose doc comment describes the language-server shutdown race and which the host's termination sweep awaits. Each write inside `finishScan` is caught independently, so a scan cut off mid-loop does not corrupt the database; it leaves `isScanning` `true` and `lastScanSummary` unset for that run.
