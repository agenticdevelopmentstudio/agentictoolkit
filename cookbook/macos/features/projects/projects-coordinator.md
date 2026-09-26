---
id: 2469d716-84aa-4984-9e71-4cfe49d05854
title: ProjectsCoordinator
domain: agentictoolkit://cookbook/macos/features/projects/projects-coordinator
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The project registry feature — owns the database-backed list of known
  git repositories, drives the background scan that reconciles it against disk,
  and registers the app-level open/scan commands and menu items.
platforms:
- swift
- macos
tags:
- git
- projects
- coordinator
- scanning
- command-palette
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/projects/git-repo
- agentictoolkit://cookbook/macos/features/projects/project-database
- agentictoolkit://cookbook/macos/features/projects/project-reconciler
- agentictoolkit://cookbook/macos/features/projects/git-repo-scanner
- agentictoolkit://cookbook/macos/features/projects/project-chooser-window
- agentictoolkit://cookbook/macos/features/projects/project-scan-progress-window
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectChooserWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectScanProgressWindow.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWindowManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppFeature.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/MenuContribution.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsWindowController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectsCoordinator

## Overview

`ProjectsCoordinator` is the project registry feature: one `ProjectDatabase`,
the in-memory list of known git repositories (`repos`), and the background
scan that keeps that list true to disk. Its own doc comment states the
model directly — "a 'project' here is a row, not a file," so a repository
can be renamed or moved on disk without losing its settings or window
layout (`ProjectsCoordinator.swift`). It is an `AppFeature`
(`AppFeature.swift`): the host constructs it once during launch, and it
registers two `AppCommand`s and two `MenuContribution`s on the caller's
`CommandRegistry` at `init` time so a palette, a shortcut, or an extension
can reach "Open Project…" and "Scan for Projects" by id. It owns none of
the scanning, reconciling, persisting, or window-presenting logic itself —
those are `GitRepoScanner`, `ProjectReconciler`, `ProjectDatabase`, and
`ProjectOpening`/`ProjectChooserWindow`/`ProjectScanProgressWindow`,
respectively (see their own recipes) — `ProjectsCoordinator` only sequences
calls to them and republishes the result through `repos` and
`didChangeNotification`.

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
- **finish-scan-updates-no-decrement-on-failure**: For each repo in `plan.updates`, `finishScan` calls `database.update(repo)` and on failure logs the error with `repo.path` at `privacy: .public`, as the insert and delete loops do, but unlike those loops it does not decrement any `summary` count. A failed update therefore leaves `summary.moved`/`summary.unchanged` (whichever `ProjectReconciler.plan` attributed the row to) overstated, despite the function's own comment that "the summary and what the user was told disagree" is the bug its per-row error handling fixes; the failure is visible only in the log.

## Appearance

Not applicable — this is a non-UI feature coordinator, not a visual
component.

## States

Not applicable — this is a non-UI feature coordinator, not a visual
component. Its `isScanning`/`lastScanSummary` are plain state properties,
not view states.

## Accessibility

Not applicable — this is a non-UI feature coordinator, not a visual
component.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `database` (parameter to `init`) | `ProjectDatabase` | none — required | The store `repos` is loaded from and that `finishScan`/`rename`/`openProject` write to. |
| `scanner` (parameter to `init`) | `GitRepoScanner?` | `nil` | Injected scanner for a test or a caller wanting a particular walk; when `nil`, `scan(...)` builds its own scanner from the current setting on every call. |
| `opener` (parameter to `init`) | `ProjectOpening?` | `nil` | Weakly held window-opening delegate; also settable afterward through `setOpener(_:)`. |
| `commandRegistry` (parameter to `init`, labeled `registry`) | `CommandRegistry` | none — required, no default | Where `CommandID.openProject`/`CommandID.scanForProjects` are registered at `init` time (see **command-registry-required**). |
| `UserSettings.projectScanSkipPatterns` | `UserSetting<[String]>` | `GitRepoScanner.defaultRootSkipPatterns` | Read fresh at the start of every `scan(...)` call that has no injected scanner, so an edited skip list takes effect on the next scan without relaunching. |
| `showingProgress` (parameter to `scan`) | `Bool` | `true` | Whether `scan(...)` presents a `ProjectScanProgressWindow` for the duration of the walk. |

## Deep Linking

Not applicable — `ProjectsCoordinator.swift` defines no URL scheme, route,
or navigation destination.

## Localization

`ProjectsCoordinator.swift` contains four hardcoded English string
literals: the command titles `"Open Project…"` and `"Scan for Projects"`
(also reused as the two menu-item titles), and the shared category
`"Projects"` used by both `AppCommand` registrations. None is routed
through `NSLocalizedString`, a String Catalog, or any other localization
mechanism in this file.

## Accessibility Options

Not applicable — `ProjectsCoordinator` renders no UI of its own; the
windows it presents (`ProjectChooserWindow`, `ProjectScanProgressWindow`)
and opens (through `ProjectOpening`) are the rendering layers, and Reduce
Motion, Increase Contrast, and Differentiate Without Color are their
concern, not this coordinator's.

## Feature Flags

Not applicable — `ProjectsCoordinator.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable — `ProjectsCoordinator.swift` makes no analytics or
event-tracking call.

## Privacy

The only data this file logs is a set of local filesystem paths
(`repo.path`, at `privacy: .public`, in the three `finishScan` error
messages) and a repository identifier (`repoID.uuidString`, at `privacy:
.public`, in `rename`'s error message) — both already visible to the user
in the project list and its window titles. `openProject`'s error message is
the one exception: it logs no path or id at all, only the caught `error`
value with no explicit `privacy` annotation (`ProjectsCoordinator.swift`). This file reads, stores, or transmits no credential, token, or
other personal data, and makes no network call of its own (see Offline or
disconnected state above).

## Logging

`ProjectsCoordinator` conforms to `Loggable` (`ProjectsCoordinator.swift`); subsystem defaults to `Bundle.main.bundleIdentifier`,
category is `ProjectsCoordinator`.

| Event | Level | Message |
|-------|-------|---------|
| `rename`'s `database.update` failed | error | `Rename failed for <repoID.uuidString>: <error>` |
| `openProject`'s `database.markOpened` failed | error | `Could not record open time: <error>` |
| `finishScan` insert failed | error | `Could not add <repo.path>: <error>` |
| `finishScan` update failed | error | `Could not update <repo.path>: <error>` |
| `finishScan` delete failed | error | `Could not remove <repo.path>: <error>` |
| `finishScan` completed | info | `Scan complete: <summary.summaryText>` |

`init`'s and `reload()`'s failed `database.allRepos()` reads, and `stop()`'s
failed `database.checkpoint()`, make no log call at all — see
**database-read-failure-unsignaled** and
**stop-checkpoint-failure-unsignaled**.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift`,
  built on `AppKit` (indirectly, through the `ProjectOpening`/
  `ProjectWindowManager` seam and the `ComposableTabsWindowController`/
  `WindowManager` frame cleanup) and `AgenticToolkitCore` (`GitRepo`,
  `ProjectDatabase`, `ProjectReconciler`, `GitRepoScanner`, `AppFeature`,
  `AppCommand`, `MenuContribution`, `CommandRegistry`, `Loggable`). It uses
  no SwiftUI API of its own; a SwiftUI host would still construct this same
  `@MainActor` class as a plain observable feature object, feeding a
  project-list view from `repos` and `isScanning` rather than modeling
  either as a `View`/`Scene`.
- **Compose**: Model `ProjectsCoordinator` as a plain `@MainActor`-confined
  (or main-dispatcher-confined) class holding `repos:
  List<GitRepo>`/`isScanning: Boolean`/`lastScanSummary:
  ProjectScanSummary?` as `MutableState`/`StateFlow` so a project-list
  composable recomposes on change. Represent `didChangeNotification` as a
  `SharedFlow<Unit>` emission rather than an OS-level notification.
  Reproduce **scan-runs-detached-then-hops-main** with a coroutine launched
  on a background dispatcher that switches back to the main dispatcher
  before mutating state — and, to close **scan-task-not-tracked**, store
  the launched `Job` so a Compose port's lifecycle teardown can cancel it.
- **React/Web**: A browser-hosted equivalent has no local git-repository
  filesystem to scan, so this component has no direct one-to-one web port;
  a server-backed project registry would model `repos`/`isScanning` as
  component state populated from an API call standing in for the scan,
  represent `didChangeNotification` as an ordinary event-emitter event, and
  serialize the re-entrancy guard (**scan-guards-reentrancy**) as a request
  flag checked before issuing a new "scan" API call.
- **AppKit / UIKit**: The source already is AppKit-adjacent (through
  `ProjectOpening`, `ProjectChooserWindow`, and `ProjectScanProgressWindow`);
  a UIKit (iOS) port would replace the `NSMenuItem`-backed
  `MenuContribution`s with whatever the iOS host uses for its equivalent
  command surface (a command palette, an action sheet), replace
  `ProjectWindowManager`'s language-server-shutdown seam with an iOS
  equivalent lifecycle hook, and would need its own answer for
  `WindowManager.shared.frames` (multi-window state restoration), since
  iOS's per-scene state restoration model differs from AppKit's; the
  scan/reconcile/persist sequence in `finishScan` ports unchanged.
- **WinUI 3**: Port `ProjectsCoordinator` as a plain C# class implementing
  the app's `IAppFeature` equivalent (mirroring `AppFeature`'s
  `Start()`/`Stop()`/`TerminateAsync()` hooks), holding `ObservableCollection<GitRepo>
  Repos`, `bool IsScanning`, and `ProjectScanSummary? LastScanSummary`, all
  touched only from the UI thread (`DispatcherQueue`) to mirror
  `@MainActor` confinement. Register the two commands
  (`CommandID.OpenProject`/`CommandID.ScanForProjects`) on the host's
  command-registry equivalent and add two `MenuFlyoutItem`s under the File
  menu, matching **menu-contributions-two-file-items**'s slot/order/key
  layout (`Ctrl+Alt+P` for Open Project, mirroring the macOS
  `[.command, .option]` combination). Back `database` with the same
  SQLite file through `Microsoft.Data.Sqlite` (see
  `agentictoolkit://cookbook/macos/features/projects/project-database`'s WinUI
  bullet for the schema/migration port) and call its `Checkpoint()`
  equivalent from `Stop()`, logging any exception there explicitly to
  close **stop-checkpoint-failure-unsignaled** rather than reproducing the
  silent `try?`. Run the scan on `Task.Run` (mirroring
  `Task.detached(priority: .utility)`) and marshal the result back with
  `DispatcherQueue.TryEnqueue` (mirroring `MainActor.run`); store that
  `Task` on the class so `Stop()`/`TerminateAsync()` can `await` or cancel
  it, closing **scan-task-not-tracked** rather than reproducing the gap.
  Reproduce **finish-scan-inserts-decrement-on-failure** and
  **finish-scan-deletes-decrement-and-clear-frames** exactly, including
  their `continue`/no-`continue` asymmetry, and reproduce
  **finish-scan-updates-no-decrement-on-failure**'s gap only if intentionally
  carrying the bug forward — otherwise decrement the matching summary count
  on a caught update failure, which is the fix this recipe's marker
  recommends. Represent `WindowManager.shared.frames`'s clear calls with
  whatever this host's window-frame-persistence store exposes for clearing
  a saved bounds/visibility record by window id.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift` |

## Design Decisions

**Decision**: `commandRegistry` is a required, non-defaulted `init`
parameter rather than an optional with an internal fallback registry.
**Rationale**: The doc comment states the reason directly: a defaulted
private registry would let a caller omit the argument and still get "a
working menu — while the palette silently lost this entire feature's
commands, with no log, no crash and nothing a test could observe." Requiring
the parameter moves that failure to compile time (`ProjectsCoordinator.swift`).
**Approved**: pending

**Decision**: A `scan()` call arriving while one is already in flight is
dropped, not queued or coalesced.
**Rationale**: The inline comment states the reasoning: "two scans of the
same disk produce the same answer, so the second is waste." No caller of
`scan()` is left waiting for a result it would receive anyway from the
scan already running (`ProjectsCoordinator.swift`).
**Approved**: pending

**Decision**: `finishScan` closes every project window slated for deletion
in one pass, completed before any row in `plan.deletes` is actually deleted.
**Rationale**: The inline comment gives the ordering constraint: a window
still open against a row after that row is deleted "is a foreign key that
no longer resolves." Closing first avoids a write from a still-open window
landing on a row that database-level cascading has already removed
(`ProjectsCoordinator.swift`).
**Approved**: pending

**Decision**: `terminate()` reaches the language-server shutdown through a
runtime cast (`opener as? ProjectWindowManager`) rather than widening
`ProjectOpening` to declare a shutdown method.
**Rationale**: The doc comment states the seam is deliberate: `ProjectOpening`
"says nothing about language servers, and widening it for this one call
would push an LSP concern into the protocol the registry is tested
against." A host that supplies a different `ProjectOpening` implementation
simply skips the shutdown call rather than being forced to implement it
(`ProjectsCoordinator.swift`).
**Approved**: pending

**Decision**: `scan(...)` reads `UserSettings.projectScanSkipPatterns` fresh
inside every call rather than caching the scanner (or the setting) at
`init` time, whenever no scanner was injected.
**Rationale**: The doc comment on `injectedScanner` states the intent:
leaving the field `nil` in the ordinary case means "editing the skip list
takes effect on the next scan rather than the next launch"
(`ProjectsCoordinator.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectsCoordinator` owns
exactly the `repos` list, the scan/reconcile/persist sequencing in
`finishScan`, and command/menu registration, while delegating every
directory walk to `GitRepoScanner`, all match/insert/update/delete
arithmetic to `ProjectReconciler`, all persistence to `ProjectDatabase`,
and all window presentation to `ProjectOpening`/`ProjectChooserWindow`/
`ProjectScanProgressWindow` — its own doc comment states it knows a
project only as "a row, not a file." unit-test-coverage fails because no
test file exists anywhere in the repository for this type (no
`ProjectsCoordinatorTests.swift`), so every behavior documented above,
including the open questions and gaps above, is currently unverified by any
automated test. explicit-error-handling is partial because four of the six
database-touching call sites (`rename`, `openProject`, and `finishScan`'s
insert/update/delete loops) catch and log their failure, but two — the
`database.allRepos()` reads in `init`/`reload()` and `database.checkpoint()`
in `stop()` — swallow through `try?` with no log call at all (see
**database-read-failure-unsignaled**, **stop-checkpoint-failure-unsignaled**).
state-recovery is partial because `init`'s load and `reload()`'s refresh
from `database.allRepos()` are this feature's whole recovery mechanism
after a process restart, but a failed read on either path is
indistinguishable from a database that is genuinely empty — there is no
signal a caller or a future launch could use to tell the two apart.
data-integrity is partial because `finishScan`'s insert and delete loops
keep `summary`'s counts truthful to what was actually written on a caught
failure, but the update loop does not (see
**finish-scan-updates-no-decrement-on-failure**), so `lastScanSummary` can
overstate how many rows were actually updated whenever one `database.update`
call in a scan fails.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
