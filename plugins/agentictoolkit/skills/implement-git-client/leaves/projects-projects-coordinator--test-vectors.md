<!-- leaf: implement-git-client/projects-projects-coordinator--test-vectors · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator

## Conformance Test Vectors

No test file exists for `ProjectsCoordinator` (no
`ProjectsCoordinatorTests.swift` anywhere in the repository), so every
vector below is derived directly from source behavior rather than from an
existing test.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-projects-coordinator-001 | repos-initial-load | `init(database:scanner:opener:commandRegistry:)` where `database.allRepos()` throws. | `repos` is `[]`; `init` does not throw; no log call is made (see **database-read-failure-unsignaled**). |
| git-client-projects-projects-coordinator-002 | command-registry-required, menu-contributions-two-file-items | `init(database:scanner:opener:commandRegistry:)` with a fresh `CommandRegistry`. | `registry.isEnabled(id: CommandID.openProject)` and `registry.isEnabled(id: CommandID.scanForProjects)` both answer `true`; `menuContributions.count == 2`, both `.file` slot. |
| git-client-projects-projects-coordinator-003 | rename-trims-and-guards-no-op | `rename(repoID: unknownID, to: "New Name")` where `unknownID` matches no row in `repos`. | `repos` unchanged; `database.update` is never called; no notification posted. |
| git-client-projects-projects-coordinator-004 | rename-trims-and-guards-no-op | `rename(repoID: existingID, to: "  ")` (all whitespace). | `repos` unchanged; `database.update` is never called. |
| git-client-projects-projects-coordinator-005 | rename-persists-then-reloads-or-logs | `rename(repoID: existingID, to: "  New Name  ")` where `database.update` succeeds. | The row's `name` becomes `"New Name"` (trimmed); `reload()` runs, posting `didChangeNotification`. |
| git-client-projects-projects-coordinator-006 | rename-persists-then-reloads-or-logs | Same call, but `database.update` throws. | `Self.logger.error` is called with `repoID.uuidString`; `reload()` does not run; no notification is posted for this call. |
| git-client-projects-projects-coordinator-007 | open-project-marks-reloads-then-opens | `openProject(repo)` where `database.markOpened` throws. | `Self.logger.error` is called; `reload()` still runs; `opener?.openProject(repo)` still runs, in that order. |
| git-client-projects-projects-coordinator-008 | scan-guards-reentrancy | `scan()` called a second time while `isScanning == true` from a first, still-running call. | The second call returns immediately; `isScanning` stays exactly as the first call left it; no second `Task.detached` is started. |
| git-client-projects-projects-coordinator-009 | scan-progress-window-conditional | `scan(showingProgress: false)`. | `progressWindow` remains `nil` throughout the scan; no `ProjectScanProgressWindow.present()` call is made. |
| git-client-projects-projects-coordinator-010 | scan-uses-injected-or-fresh-scanner | `scan()` on a coordinator constructed with a non-`nil` `scanner:` argument. | That injected scanner's `scan()` runs; `UserSettings.projectScanSkipPatterns` is never read. |
| git-client-projects-projects-coordinator-011 | finish-scan-inserts-decrement-on-failure | `finishScan(found:)` where `ProjectReconciler.plan` yields one insert and `database.insert` throws for it. | `summary.added` is one less than `plan.summary.added`; `Self.logger.error` is called with that repo's `path`; `finishScan` continues to the deletes loop rather than stopping. |
| git-client-projects-projects-coordinator-012 | finish-scan-updates-no-decrement-on-failure | `finishScan(found:)` where `ProjectReconciler.plan` yields one update and `database.update` throws for it. | `Self.logger.error` is called with that repo's `path`; `summary`'s count for that row (`moved` or `unchanged`, per `ProjectReconciler.plan`'s attribution) is left exactly as `plan.summary` set it — not decremented (see **finish-scan-updates-no-decrement-on-failure**). |
| git-client-projects-projects-coordinator-013 | finish-scan-closes-windows-before-deleting, finish-scan-deletes-decrement-and-clear-frames | `finishScan(found:)` where `ProjectReconciler.plan` yields one delete and `database.delete` succeeds. | `opener?.closeProject(repoID:)` is called for that repo before `database.delete` runs; on success, `WindowManager.shared.frames.clearSavedState`/`clearVisibility` are both called for `ComposableTabsWindowController.windowID(for: repo.id)`. |
| git-client-projects-projects-coordinator-014 | finish-scan-deletes-decrement-and-clear-frames | Same setup, but `database.delete` throws. | `summary.removed` is one less than `plan.summary.removed`; `Self.logger.error` is called; the frame-clearing calls for that repo are skipped (the `continue`). |
| git-client-projects-projects-coordinator-015 | finish-scan-final-state-order, finish-scan-logs-completion-and-dismisses-progress | `finishScan(found:)` completes with a mix of successful inserts/updates/deletes. | `lastScanSummary` is set to the (possibly decremented) `summary`; `isScanning` is `false`; `reload()` has run; `Self.logger.info` logs `summary.summaryText`; `progressWindow` is `nil` after `finish()` was called on it. |
| git-client-projects-projects-coordinator-016 | terminate-casts-opener-for-language-services | `terminate()` on a coordinator whose `opener` is a `ProjectWindowManager`. | `shutdownAllLanguageServices()` is awaited on that instance. |
| git-client-projects-projects-coordinator-017 | terminate-casts-opener-for-language-services | `terminate()` on a coordinator whose `opener` is `nil`, or a `ProjectOpening` mock that is not a `ProjectWindowManager`. | The method returns immediately; no shutdown call is made anywhere. |
| git-client-projects-projects-coordinator-018 | stop-checkpoint-failure-unsignaled | `stop()` where `database.checkpoint()` throws. | No log call is made; `stop()` returns normally (see **stop-checkpoint-failure-unsignaled**). |
