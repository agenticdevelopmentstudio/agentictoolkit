---
id: 2469d716-84aa-4984-9e71-4cfe49d05854
title: Projects Coordinator
domain: agentictoolkit://cookbook/workspace/projects/projects-coordinator
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/git-repo
- agentictoolkit://cookbook/workspace/projects/project-database
- agentictoolkit://cookbook/workspace/projects/project-reconciler
- agentictoolkit://cookbook/workspace/projects/git-repo-scanner
- agentictoolkit://cookbook/workspace/projects/project-chooser-window
- agentictoolkit://cookbook/workspace/projects/project-scan-progress-window
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
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

# Projects Coordinator

## Overview

This is the project registry feature: one database, the in-memory list of
known git repositories, and the background scan that keeps that list true
to disk. Its own doc comment states the model directly — "a 'project'
here is a row, not a file," so a repository can be renamed or moved on
disk without losing its settings or window layout. It is a top-level app
feature: the host constructs it once during launch, and it registers two
commands and two menu contributions on the caller's command registry at
construction time so a palette, a shortcut, or an extension can reach
"Open Project…" and "Scan for Projects" by id. It owns none of the
scanning, reconciling, persisting, or window-presenting logic itself —
those are the scanner, the reconciler, the database, and the
project-opening interface and its chooser/progress windows, respectively
(see their own recipes) — this feature only sequences calls to them and
republishes the result through its repository list and its change
notification.

## Behavioral Requirements

- **did-change-notification-shape**: The coordinator's change notification
  MUST be a named notification (`"ProjectsCoordinatorDidChange"`) and
  MUST carry no payload — readers MUST re-read the repository list
  directly, which the doc comment calls "the one representation of that
  knowledge."
- **repos-initial-load**: Construction MUST populate the repository list
  by reading all repositories from the database exactly once, swallowing
  any thrown error, so a failed read leaves the repository list at its
  default empty state rather than propagating out of construction.
- **command-registry-required**: Construction MUST register an "Open
  Project…" command and a "Scan for Projects" command, both in the
  "Projects" category, on the caller-supplied command registry, and the
  command-registry parameter carries no default value — the doc comment
  states this is deliberate so a missing registry fails at build time
  rather than silently dropping every menu item this feature
  contributes.
- **menu-contributions-two-file-items**: Construction MUST set the menu
  contributions to exactly two entries, both in the File-menu slot: "Open
  Project…" ordered first, bound to the primary modifier plus Option and
  the plain key `"p"`, dispatching through the open-project command; and
  "Scan for Projects" ordered after it, dispatching through the
  scan-for-projects command, hidden whenever a scan is already running.
- **set-opener-replaces-unconditionally**: Setting the window-opening
  delegate MUST replace the current one with the argument regardless of
  whether one was already set.
- **start-triggers-default-scan**: Starting the feature MUST trigger a
  scan with progress shown by default; starting is declared able to fail
  by the interface it overrides, but its own body never actually fails.
- **stop-checkpoints-database**: Stopping the feature MUST checkpoint the
  database.
- **terminate-casts-opener-for-language-services**: Terminating the
  feature MUST attempt to recognize the window-opening delegate as a
  project window manager; when it is one, terminating MUST await
  shutting down all language services on it; when it is not — the
  delegate is unset or a different project-opening implementation —
  terminating MUST return immediately having done nothing further. The
  doc comment states the type check is deliberate: widening the
  project-opening interface itself to carry a language-server concern
  "would push an LSP concern into the protocol the registry is tested
  against."
- **repo-lookup-by-id**: Looking up a repository by id MUST return the
  first entry in the repository list whose id equals the argument, or
  nothing when none matches.
- **rename-trims-and-guards-no-op**: Renaming a repository MUST return
  with no effect when looking it up by id finds nothing; MUST trim the
  new name of leading and trailing whitespace and newlines; and MUST
  return with no effect — no database write, no reload — when the
  trimmed name is empty or equal to the repository's current name.
- **rename-persists-then-reloads-or-logs**: When the trimmed name is
  non-empty and differs from the current name, renaming a repository
  MUST set the local copy's name to the trimmed value and MUST write it
  to the database; on success it MUST reload; on failure it MUST catch
  the thrown error, log it at error level naming the repository's id at
  public log-visibility, and MUST NOT reload on that path.
- **open-project-marks-reloads-then-opens**: Opening a project MUST
  record the repository's open time in the database, catching and
  logging any thrown error without propagating it; MUST then
  unconditionally reload, regardless of whether recording the open time
  succeeded; and MUST hand the repository to the window-opening delegate
  last, after the reload.
- **show-project-chooser-delegates-to-open**: Showing the project chooser
  MUST present it against the coordinator, with a callback that opens
  whatever repository the chooser passes back.
- **reload-refreshes-then-notifies-unconditionally**: Reloading MUST
  reread the repository list from the database, falling back to the
  existing list unchanged when that read fails, and MUST then post the
  change notification unconditionally — even on the path where the read
  failed and the list did not actually change.
- **scan-guards-reentrancy**: Scanning MUST return immediately,
  performing no work, when a scan is already running; otherwise it MUST
  mark a scan as running before doing anything else. The inline comment
  states the policy is deliberate: "two scans of the same disk produce
  the same answer, so the second is waste."
- **scan-progress-window-conditional**: When progress is to be shown (the
  default), scanning MUST construct and present a scan-progress window
  and hold onto it; when not, it MUST leave the progress window
  untouched.
- **scan-uses-injected-or-fresh-scanner**: Scanning MUST use an injected
  scanner when one was supplied; otherwise it MUST construct a fresh
  scanner seeded with the current value of the scan-skip-patterns
  setting, read at the moment the scan runs, not cached from
  construction time, so an edited skip list takes effect on the next
  scan.
- **scan-runs-detached-then-hops-main**: Scanning MUST run the chosen
  scanner's walk off the UI's main execution context, and MUST hand the
  result back to the scan-finishing step on that context.
- **finish-scan-builds-plan-from-current-repos**: Finishing a scan MUST
  compute a reconciliation plan from the current repository list and
  what the scan found, and MUST seed the running summary as a copy of
  that plan's own summary.
- **finish-scan-inserts-decrement-on-failure**: For each repository the
  plan calls for inserting, finishing a scan MUST insert it into the
  database; on failure it MUST decrement the summary's added count by
  one and log the error naming the repository's path at public
  log-visibility, then MUST continue to the next insertion rather than
  aborting the loop.
- **finish-scan-closes-windows-before-deleting**: Finishing a scan MUST
  close the project window for every repository the plan calls for
  deleting, in a pass that completes entirely before the delete pass
  begins. The inline comment states the reason: closing a window writes
  to the row it belongs to, "which after the delete is a foreign key
  that no longer resolves."
- **finish-scan-deletes-decrement-and-clear-frames**: For each repository
  the plan calls for deleting, finishing a scan MUST delete it from the
  database; on failure it MUST decrement the summary's removed count,
  log the error naming the repository's path at public log-visibility,
  and skip ahead — bypassing the frame cleanup below — rather than abort
  the loop; on success it MUST clear both the saved state and the
  visibility of that repository's window frame.
- **finish-scan-final-state-order**: After all three loops, finishing a
  scan MUST record the running summary as the last-scan summary, MUST
  mark the scan as no longer running, and MUST reload, in that order,
  before logging completion and dismissing the progress window.
- **finish-scan-logs-completion-and-dismisses-progress**: Finishing a
  scan MUST log the summary's own summary text at info level and public
  visibility, and MUST finish and release the progress window,
  regardless of whether any of the three loops above logged an error of
  its own.
- **loggable-conformance**: The coordinator MUST expose a single shared
  logger for its own log messages, independent of any instance,
  following the same logging convention used across this codebase.
- **database-read-failure-unsignaled**: NEEDS REVIEW: Not implemented in
  source. Both construction's initial load and reloading discard any
  thrown database-read error with no logging call and no way for a
  caller to distinguish "the registry is genuinely empty" from "the read
  just failed" — unlike every other database failure path in this file,
  which each log at error level (renaming, opening a project, and all
  three scan-finishing loops). What is missing: a log call, or a way for
  a caller to detect a failed reload versus an empty result. What would
  settle it: either addition, or a doc comment stating the silence is
  intentional because a failed read is expected to be transient and
  self-correcting on the next reload.
- **stop-checkpoint-failure-unsignaled**: NEEDS REVIEW: Not implemented
  in source. Stopping's checkpoint call discards a checkpoint failure
  with no logging call at all, the only write-adjacent database call in
  this file that neither logs nor otherwise surfaces its outcome. What
  is missing: a log call on the caught path, matching the pattern every
  other database call in this file follows. What would settle it: adding
  one, or a doc comment stating why a failed checkpoint at shutdown
  needs no signal.
- **scan-task-not-tracked**: The background scan-and-reconcile
  continuation started by scanning is not stored, awaited, or
  cancellable: stopping and terminating can both run while it is in
  flight, and neither waits for or cancels it. Contrast terminating,
  whose doc comment describes the language-server shutdown race and
  which the host's termination sweep awaits. Each write inside
  scan-finishing is caught independently, so a scan cut off mid-loop
  does not corrupt the database; it leaves the is-scanning flag set and
  the last-scan summary unset for that run.
- **finish-scan-updates-no-decrement-on-failure**: For each repository
  the plan calls for updating, finishing a scan writes it to the
  database and on failure logs the error naming the repository's path at
  public log-visibility, as the insert and delete loops do, but unlike
  those loops it does not decrement any summary count. A failed update
  therefore leaves the summary's moved/unchanged count (whichever the
  reconciliation plan attributed the row to) overstated, despite the
  scan-finishing step's own comment that "the summary and what the user
  was told disagree" is the bug its per-row error handling fixes; the
  failure is visible only in the log.

## Appearance

Not applicable — this is a non-UI feature coordinator, not a visual
component.

## States

Not applicable — this is a non-UI feature coordinator, not a visual
component. Its is-scanning flag and last-scan summary are plain state
properties, not view states.

## Accessibility

Not applicable — this is a non-UI feature coordinator, not a visual
component.

## Conformance Test Vectors

No dedicated test file exists for this component, so every vector below
is derived directly from source behavior rather than from an existing
test.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-projects-coordinator-001 | repos-initial-load | Construct the coordinator where reading all repositories from the database throws. | the repository list is empty; construction does not throw; no log call is made (see **database-read-failure-unsignaled**). |
| git-client-projects-projects-coordinator-002 | command-registry-required, menu-contributions-two-file-items | Construct the coordinator with a fresh command registry. | the registry reports both the open-project and scan-for-projects commands as enabled; the menu contributions total two entries, both in the File-menu slot. |
| git-client-projects-projects-coordinator-003 | rename-trims-and-guards-no-op | Rename a repository using an id that matches no row in the repository list, with a new name. | the repository list is unchanged; the database is never written; no notification is posted. |
| git-client-projects-projects-coordinator-004 | rename-trims-and-guards-no-op | Rename an existing repository to an all-whitespace name. | the repository list is unchanged; the database is never written. |
| git-client-projects-projects-coordinator-005 | rename-persists-then-reloads-or-logs | Rename an existing repository to a new name with leading and trailing whitespace, where the database write succeeds. | the row's name becomes the trimmed new name; reloading runs, posting the change notification. |
| git-client-projects-projects-coordinator-006 | rename-persists-then-reloads-or-logs | Same call, but the database write throws. | the error is logged naming the repository's id; reloading does not run; no notification is posted for this call. |
| git-client-projects-projects-coordinator-007 | open-project-marks-reloads-then-opens | Open a project where recording its open time in the database throws. | the error is logged; reloading still runs; the window-opening delegate is still handed the project, in that order. |
| git-client-projects-projects-coordinator-008 | scan-guards-reentrancy | Call scan a second time while a scan from a first call is still running. | the second call returns immediately; the is-scanning flag stays exactly as the first call left it; no second background scan is started. |
| git-client-projects-projects-coordinator-009 | scan-progress-window-conditional | Scan with progress not shown. | the progress window remains unset throughout the scan; no scan-progress window is presented. |
| git-client-projects-projects-coordinator-010 | scan-uses-injected-or-fresh-scanner | Scan on a coordinator constructed with a non-empty injected scanner. | that injected scanner's walk runs; the scan-skip-patterns setting is never read. |
| git-client-projects-projects-coordinator-011 | finish-scan-inserts-decrement-on-failure | Finish a scan where the reconciliation plan yields one insertion and writing it to the database throws. | the summary's added count is one less than the plan's own added count; the error is logged naming that repository's path; finishing the scan continues to the deletes loop rather than stopping. |
| git-client-projects-projects-coordinator-012 | finish-scan-updates-no-decrement-on-failure | Finish a scan where the reconciliation plan yields one update and writing it to the database throws. | the error is logged naming that repository's path; the summary's count for that row (moved or unchanged, per the plan's own attribution) is left exactly as the plan set it — not decremented (see **finish-scan-updates-no-decrement-on-failure**). |
| git-client-projects-projects-coordinator-013 | finish-scan-closes-windows-before-deleting, finish-scan-deletes-decrement-and-clear-frames | Finish a scan where the reconciliation plan yields one deletion and the database delete succeeds. | the window-opening delegate is asked to close that project before the database delete runs; on success, that repository's window frame has both its saved state and its visibility cleared. |
| git-client-projects-projects-coordinator-014 | finish-scan-deletes-decrement-and-clear-frames | Same setup, but the database delete throws. | the summary's removed count is one less than the plan's own removed count; the error is logged; the frame-clearing calls for that repository are skipped (the loop continues past them). |
| git-client-projects-projects-coordinator-015 | finish-scan-final-state-order, finish-scan-logs-completion-and-dismisses-progress | Finish a scan that completes with a mix of successful insertions, updates, and deletions. | the last-scan summary is set to the (possibly decremented) running summary; the is-scanning flag is cleared; reloading has run; completion is logged with the summary's own summary text; the progress window is unset after being finished. |
| git-client-projects-projects-coordinator-016 | terminate-casts-opener-for-language-services | Terminate a coordinator whose window-opening delegate is a project window manager. | shutting down all language services is awaited on that instance. |
| git-client-projects-projects-coordinator-017 | terminate-casts-opener-for-language-services | Terminate a coordinator whose window-opening delegate is unset, or a project-opening stand-in that is not a project window manager. | the method returns immediately; no shutdown call is made anywhere. |
| git-client-projects-projects-coordinator-018 | stop-checkpoint-failure-unsignaled | Stop a coordinator where checkpointing the database throws. | no log call is made; stopping returns normally (see **stop-checkpoint-failure-unsignaled**). |

## Edge Cases

- **Null and empty input**: Renaming a repository with an id not present
  in the repository list MUST be a no-op — looking it up by id returns
  nothing and the guard exits before any trim or write. MUST. A new name
  that is empty, all-whitespace, or trims down to the unchanged current
  name MUST also be a no-op, performing no database write and no
  reload. MUST. A scan whose scanner reports zero repositories on disk
  MUST still run the scan-finishing step to completion; the
  reconciliation plan, given an empty found list, produces deletions for
  every currently known row that the scanner's own liveness check does
  not excuse, so an empty scan is never distinguished at this layer from
  "the disk root genuinely lost every repository" — that distinction
  belongs to the scanner and the reconciler, not this feature. MUST.
- **Boundary values**: This feature performs no truncation, pagination,
  or count-based branching on the size of the repository list or the
  found list at any point — zero, one, or many rows in the plan's
  insertions, updates, or deletions all take the identical per-row loop
  when finishing a scan. MUST.
- **Concurrent access**: A second scan call arriving while one is already
  running MUST be dropped with no work performed and no queuing for a
  later run — the guard is the entire re-entrancy policy, and the inline
  comment states this is deliberate. MUST. The scan's own background
  continuation is not tracked by any stored handle, so stopping or
  terminating racing an in-flight scan is not resolved by this feature
  at all (see **scan-task-not-tracked**); every write inside
  scan-finishing is independently caught, so such a race cannot corrupt
  the database, only leave the is-scanning flag stuck set for that run.
- **Error states**: Every database write this feature performs directly
  (the update in renaming, recording the open time in opening a project,
  and the insert/update/delete calls in scan-finishing) is caught
  individually and logged at error level without propagating. MUST. Two
  read/checkpoint paths instead swallow the error with no log call at
  all — reading all repositories in construction and reloading, and
  checkpointing in stopping — see **database-read-failure-unsignaled**
  and **stop-checkpoint-failure-unsignaled**.
- **Offline or disconnected state**: Not applicable — this feature makes
  no network call of its own. The database is a local file and the
  scanner walks the local filesystem; neither this feature nor its
  direct collaborators depend on network reachability.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| database (construction parameter) | a database reference | none — required | The store the repository list is loaded from and that scan-finishing/renaming/opening a project write to. |
| scanner (construction parameter) | a scanner reference (optional) | absent | Injected scanner for a test or a caller wanting a particular walk; when absent, scanning builds its own scanner from the current setting on every call. |
| window-opening delegate (construction parameter) | a project-opening reference (optional) | absent | Weakly held window-opening delegate; also settable afterward. |
| command registry (construction parameter, required) | a command-registry reference | none — required, no default | Where the open-project/scan-for-projects commands are registered at construction time (see **command-registry-required**). |
| scan-skip-patterns setting | a persisted list-of-strings setting | the scanner's own default root-skip patterns | Read fresh at the start of every scan call that has no injected scanner, so an edited skip list takes effect on the next scan without relaunching. |
| show-progress (scan parameter) | a boolean | `true` | Whether scanning presents a scan-progress window for the duration of the walk. |

## Deep Linking

Not applicable — this feature defines no URL scheme, route, or navigation
destination.

## Localization

This feature contains four hardcoded English string literals: the
command titles `"Open Project…"` and `"Scan for Projects"` (also reused
as the two menu-item titles), and the shared category `"Projects"` used
by both command registrations. None is routed through any localization
mechanism in this file.

## Accessibility Options

Not applicable — this feature renders no UI of its own; the windows it
presents (the project chooser, the scan-progress window) and opens
(through the project-opening interface) are the rendering layers, and
Reduce Motion, Increase Contrast, and Differentiate Without Color are
their concern, not this feature's.

## Feature Flags

Not applicable — this feature contains no feature-flag or
build-configuration check.

## Analytics

Not applicable — this feature makes no analytics or event-tracking call.

## Privacy

The only data this feature logs is a set of local filesystem paths (a
repository's path, at public log-visibility, in the three scan-finishing
error messages) and a repository identifier (at public log-visibility,
in renaming's error message) — both already visible to the user in the
project list and its window titles. Opening a project's error message is
the one exception: it logs no path or id at all, only the caught error
value with no explicit visibility annotation. This feature reads,
stores, or transmits no credential, token, or other personal data, and
makes no network call of its own (see Offline or disconnected state
above).

## Logging

This feature exposes a single shared logger for its own messages;
subsystem defaults to the app's own bundle identifier, category is this
feature's name.

| Event | Level | Message |
|-------|-------|---------|
| Renaming's database write failed | error | `Rename failed for <repo id>: <error>` |
| Opening a project's open-time write failed | error | `Could not record open time: <error>` |
| Scan-finishing insert failed | error | `Could not add <repo path>: <error>` |
| Scan-finishing update failed | error | `Could not update <repo path>: <error>` |
| Scan-finishing delete failed | error | `Could not remove <repo path>: <error>` |
| Scan-finishing completed | info | `Scan complete: <summary text>` |

Construction's and reloading's failed reads of all repositories, and
stopping's failed checkpoint, make no log call at all — see
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
  `agentictoolkit://cookbook/workspace/projects/project-database`'s WinUI
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
