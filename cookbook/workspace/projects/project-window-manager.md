---
id: 7f1b8bef-e78e-4cac-be55-c948fe9062e5
title: Project Window Manager
domain: agentictoolkit://cookbook/workspace/projects/project-window-manager
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owns one window per open project, pairs each with the project's controller,
  restores windows open at last quit, and drains quit-time teardowns.
platforms:
- swift
- macos
tags:
- git
- projects
- window-controller
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/project-controller
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
- agentictoolkit://cookbook/workspace/projects/git-repo
- agentictoolkit://cookbook/workspace/projects/project-database
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWindowManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectsCoordinator.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/SystemIntegration/WindowManager/WindowManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Concurrency/PendingTeardowns.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsWindowController.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectWindowManagerControllerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Window Manager

## Overview

This keeps one window per open project, keyed by a repository's id rather
than by its path, so opening "the same project" twice after it has moved
or been renamed still raises the same window. For every project it opens
it builds a matched pair — a project controller that owns the
checkout/tab reconciliation, and a window controller that hosts it — and
tears both down together when the window closes. It conforms to the
project-opening interface so a coordinator can hand it project-open/close
requests, and it publishes changes so a browser can watch which projects
are currently open. Beyond the windows it opens itself, it can also adopt
a window a host built by some other means, so scripting can see it too,
and it restores whichever projects were flagged open when the app last
quit. It is confined to the UI's main execution context, and every
property and method is confined there by that declaration alone.

## Behavioral Requirements

- **project-opening-conformance**: The manager MUST conform to the
  project-opening interface — supplying an open-project operation and a
  close-project operation, each keyed by a repository id — and MUST
  publish its state so another component can observe it.
- **main-thread-confinement**: The manager MUST be confined to the UI's
  main execution context, with no thread-safety guarantee of its own;
  every stored property and every method MUST be reached only from that
  context.
- **shared-singleton**: The manager MUST expose one process-wide shared
  instance.
- **open-window-setting-key**: The manager MUST record whether a
  project's window was open at quit as a row in the project-settings
  store, keyed by the setting key `"window.open"`, scoped per repository
  id rather than kept in an app-wide preference, so the flag is deleted
  along with the project row it belongs to rather than surviving it.
- **injectable-collaborators**: The git client, the command registry, and
  the language-services factory MUST each be a public, externally
  settable property — defaulting to the shared git client, absent, and
  absent respectively — so a test or an alternate host can substitute a
  throwaway git client, decline command-palette integration, or decline
  language services without subclassing.
- **attach-registers-opener**: Attaching to a coordinator MUST store the
  given coordinator by a weak reference and MUST register the manager as
  that coordinator's project-opening implementation.
- **front-window-controller-fallback-chain**: The frontmost-window-controller
  lookup MUST return, in order: the window controller of whichever window
  currently has key status; failing that, the first of this manager's
  window controllers found among the app's currently ordered windows;
  failing that, the controller for the most recently opened project —
  returning the first of the three that resolves to a value.
- **open-workspaces-derived**: The open-workspaces list and the
  open-window-controllers list MUST both be computed by mapping the
  open-order list through the open-controllers table, filtering out any
  id no longer present, rather than maintained as separately stored
  lists.
- **refresh-publishes-then-notifies**: Refreshing the open-workspace-ids
  list MUST assign it from the open-order list filtered by membership in
  the open-controllers table, and MUST invoke the open-projects-changed
  callback only after that assignment completes.
- **every-mutation-site-refreshes**: Every operation that adds to or
  removes from the open-controllers table — adopting a window for
  scripting, forgetting an adopted window, opening a project, and the
  window-close handling a close observer installs — MUST refresh the
  open-workspace-ids list after the mutation.
- **adopt-for-scripting-idempotent**: Adopting a window for scripting
  MUST return immediately, registering nothing again, when the
  open-controllers table already holds an entry for that controller's
  project id.
- **adopt-for-scripting-registers-without-persisting**: On the
  non-idempotent path, adopting a window for scripting MUST insert the
  controller into the open-controllers table and the open-order list, add
  its id to the adopted-for-scripting set, and install a close observer
  that does not record open state, and MUST NOT write the window-open
  flag in either direction.
- **forget-for-scripting-guarded**: Forgetting an adopted window MUST
  remove the controller from the open-controllers table, the open-order
  list, and the adopted-for-scripting set, and MUST remove its close
  observer, only when the table's current entry for that id is that exact
  controller and that id is present in the adopted-for-scripting set;
  otherwise it MUST do nothing.
- **project-controller-lookup-nil-for-adopted**: Looking up a project's
  controller MUST return absent for a repository id whose window was
  registered by adopting it for scripting rather than built by opening a
  project, because adopting a window for scripting never inserts into the
  project-controllers table.
- **open-project-raises-existing-window**: When the open-controllers table
  already has an entry for the repository, opening a project MUST update
  that existing project's stored data, show its window, order it to the
  front, and offer the app the foreground, and MUST return without
  building a new workspace or controller.
- **no-database-open-failure-signal**: Opening a project MUST have no
  return value and MUST NOT throw or await; when no database is attached,
  its only response MUST be one error-level log call — no return value,
  thrown error, or callback tells the caller (a menu action or a
  double-click in the project browser) that nothing happened, so the user
  sees no window and no explanation. The failure MUST be logged, not
  surfaced.
- **open-project-tolerates-missing-language-factory**: When the
  language-services factory is absent, or returns nothing, opening a
  project MUST log that fact at info level and MUST continue building the
  workspace and window with no language services.
- **open-project-starts-language-services**: When the language-services
  factory returns a value for the project's directory, opening a project
  MUST start those language services before constructing the project
  controller.
- **project-controller-precedes-window**: Opening a project MUST construct
  the project controller and store it in the project-controllers table
  before constructing the window controller, and MUST pass that same
  project controller as the window's tab-item data source at construction
  rather than assigning it afterward.
- **callback-wiring-checks-current-controller**: The tabs-changed callback
  and the tab-items-need-refresh callback that opening a project assigns
  to the new project controller MUST each hold the manager, the window
  controller, and the project controller by weak reference, and MUST call
  through to the window only when the open-controllers table's current
  entry for that repository is still reference-identical to the captured
  project controller.
- **will-change-cancels-pending-persist**: The will-change-tabs callback
  that opening a project assigns MUST cancel that project controller's
  pending tab persistence.
- **open-project-registration-order**: On the new-project path, opening a
  project MUST, in this order: register the controller in the
  open-controllers table and append its id to the open-order list; show
  the window, order it to the front, and offer the app the foreground;
  refresh the open-workspace-ids list; install the close observer
  (recording open state) and the became-key observer; start the project
  controller's own opening work as an independent, concurrently running
  unit of work; write the window-open flag as open.
- **open-fires-changed-notification-after-window-is-frontmost**: Opening a
  project MUST refresh the open-workspace-ids list — and therefore invoke
  the open-projects-changed callback — only after the window has been
  registered, ordered to the front, and offered the foreground, and MUST
  NOT do so at the point the controller is first registered.
- **initial-key-notification-not-guaranteed**: Because the window is
  ordered to the front and given key status before the became-key
  observer is installed, a newly opened window's own first became-key
  notification MAY or MAY NOT be seen by that observer, and opening a
  project MUST NOT add any synchronization to force either outcome.
- **close-project-delegates-and-no-ops-on-unknown-id**: Closing a project
  MUST close the window belonging to the open-controllers table's entry
  for that repository id when one exists, and MUST do nothing when it
  does not.
- **shutdown-all-language-services-runs-concurrently**: Shutting down all
  language services MUST collect every currently open project's language
  services and MUST shut them all down concurrently, as a single group of
  concurrent operations, never sequentially.
- **shutdown-all-language-services-drains-pending-teardowns**: After that
  group of concurrent operations completes, shutting down all language
  services MUST also wait for the pending-teardowns registry to drain, so
  a language service whose shutdown was started by an earlier window
  close — one already removed from the open-controllers table — is still
  waited for.
- **restore-open-projects-requires-coordinator**: Restoring open projects
  MUST return immediately, reopening nothing, when no coordinator has
  been attached.
- **restore-plan-is-pure**: Computing the restore plan MUST be a pure
  computation with no side effect, given a list of repositories, a
  was-open predicate, and an exists-on-disk predicate, and MUST compute a
  set to reopen — every repository for which both predicates are true —
  and a set to forget — every repository for which the was-open predicate
  is true and the exists-on-disk predicate is false.
- **restore-forgets-missing-folders**: For every repository in the
  restore plan's forget set, restoring open projects MUST log at info
  level and MUST write the window-open flag as closed, clearing the
  persisted flag instead of reopening a window onto a missing folder.
- **restore-reopens-existing-folders**: For every repository in the
  restore plan's reopen set, restoring open projects MUST open that
  project.
- **window-open-flag-read-write**: Reading the window-open flag MUST read
  the `"window.open"` setting through the database's per-repository
  setting lookup and MUST treat exactly the string `"1"` as open; writing
  the window-open flag MUST write `"1"` for open and remove the row
  (rather than writing any other value) for closed.
- **window-open-read-failure-defaults-closed**: When the database's
  setting lookup fails, reading the window-open flag MUST log the failure
  at error level and MUST return closed — the same value it returns for a
  project whose window was genuinely never marked open.
- **became-key-refreshes-checkouts**: The became-key observer MUST, on
  firing, look up the project controller for that repository id and, when
  found, start that controller's checkout refresh as an independent,
  concurrently running unit of work.
- **close-flag-respects-app-termination**: In the window-close handling,
  when that close observer records open state, writing the window-open
  flag as closed MUST happen only when the app is not in the middle of
  terminating, so a window the platform closes on its way out of a
  quitting app is not recorded as the user having closed it.
- **close-drops-controller-and-reregisters-survivors**: The close
  handling MUST remove the closing project's entry from the
  project-controllers table and mark that controller closed
  synchronously, then MUST re-register commands on every remaining value
  in the project-controllers table, so a branch-command id that collided
  across two windows over the same repository is handed back to the
  surviving window.
- **close-captures-teardown-target-before-removing-it**: The close
  handling MUST capture both the project-controllers table's removed
  entry for that id and the open-controllers table's entry's language
  services before removing that id from the open-controllers table, the
  open-order list, and the adopted-for-scripting set, and MUST route the
  teardown it schedules through the captured project controller's own
  shutdown when one exists, or through the captured language services'
  shutdown only when it does not — never both.
- **close-observer-uses-nil-queue**: The close observer MUST be installed
  so its handler runs synchronously, on the same thread and in the same
  run-loop turn as the close, rather than deferred through an enqueued
  delivery.
- **close-fires-on-project-closed-before-removal**: The close handling
  MUST invoke the project-closed callback while the open-controllers
  table still holds the closing project — i.e. before removing that
  entry.
- **close-teardown-added-to-shared-registry**: The close handling MUST
  hand its teardown to the pending-teardowns registry rather than
  starting an unmanaged, unheld unit of concurrent work, so shutting down
  all language services can find and wait for it even after this
  project's controller and window have already left every other
  collection.

## Appearance

Not applicable — this is a window-lifecycle manager, not a visual component.

## States

Not applicable — this is a window-lifecycle manager, not a visual component.
Its runtime state — which project ids currently have an open window, and
whether each was opened by this manager or merely adopted for scripting — is
covered under Behavioral Requirements (**open-workspaces-derived**,
**project-controller-lookup-nil-for-adopted**), not here.

## Accessibility

Not applicable — this is a window-lifecycle manager, not a visual component.
The accessibility of the window it raises and the panes it hosts is the
concern of the window controller and the view controllers it hosts, neither
of which this file renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-window-manager-001 | project-controller-precedes-window, callback-wiring-checks-current-controller, open-project-registration-order | Build a fresh manager (not the shared instance), attach it to a coordinator over a one-repository fixture, supply a git client, open the fixture's project, then wait for its stored tabs to become non-empty. | the project's controller is found by lookup and its workspace directory (resolved) equals the fixture's root; the stored tabs' titles equal `["main"]`; the window controller found by lookup has that same controller as its tab-item data source; once the pending reload lands, every top-edge tab item is a view-controller-backed item, never a bare title; closing the project by id leaves the lookup returning nothing for it — ProjectWindowManagerControllerTests.swift › testOpeningAProjectBuildsAControllerAndClosingDropsIt |
| git-client-projects-project-window-manager-002 | open-project-raises-existing-window | Open a project, wait for its tabs to persist, then open the same repository a second time with the app-activation call replaced by a counting stand-in. | the count is 1 after the first open and 2 after the second — the already-open branch still offers the app the foreground — ProjectWindowManagerControllerTests.swift › testOpeningAProjectAsksForTheForeground |
| git-client-projects-project-window-manager-003 | became-key-refreshes-checkouts, callback-wiring-checks-current-controller | Open a project on a repository with one checkout, add a second worktree on disk, then post the platform's became-key notification against the open window. | the checkouts' display names become `["main", "feature"]`; the window's top-edge tab-item count becomes 2, proving the tabs-changed callback reached the reload — ProjectWindowManagerControllerTests.swift › testTheWindowBecomingKeyRefreshesCheckouts |
| git-client-projects-project-window-manager-004 | project-controller-lookup-nil-for-adopted, close-captures-teardown-target-before-removing-it | Open one project normally; separately build a window controller over its own workspace and register it by adopting it for scripting; close the adopted window. | the project-controller lookup returns nothing for the adopted project both before and after its close; the window-controller lookup returns nothing for it after close; the opened project's own controller is untouched throughout — ProjectWindowManagerControllerTests.swift › testAnAdoptedWindowHasNoControllerAndClosesThroughTheFallback |
| git-client-projects-project-window-manager-005 | close-drops-controller-and-reregisters-survivors, close-observer-uses-nil-queue | Open a project with a counting stand-in for the git client, wait for its tabs to persist, note the window, close the project, then reopen the same repository and post the became-key notification against the now-closed (stale) window. | the manager has no key observer for that repository immediately after the close; posting the notification against the stale window makes no additional call to the stand-in git client once the reopened project's own reconcile has gone quiet — ProjectWindowManagerControllerTests.swift › testClosingRemovesTheKeyObserverSoAStaleWindowCannotTriggerARefresh |
| git-client-projects-project-window-manager-006 | close-captures-teardown-target-before-removing-it, close-teardown-added-to-shared-registry | Open two windows — one by opening a project, with an injected counting stand-in for language services; one by adopting a window for scripting, with a different counting stand-in — then close each independently. | closing the adopted window shuts down only its own services exactly once and leaves the opened window's services untouched; closing the opened window then shuts down its own services exactly once, never twice — ProjectWindowManagerControllerTests.swift › testClosingShutsDownExactlyOneLanguageServicesPerWindow |
| git-client-projects-project-window-manager-007 | close-drops-controller-and-reregisters-survivors, close-observer-uses-nil-queue | Open a project against a stand-in git client that marks a file as started and then pauses, wait for that marker to appear, and close the project by id while the project controller's own opening work is still in flight. | the project-controller lookup returns nothing immediately after closing; once the slow stand-in git call finally returns, the stored tabs are still empty and the checkouts are still empty — the in-flight opening work's reconcile never lands — ProjectWindowManagerControllerTests.swift › testClosingWhileTheOpenTaskIsInFlightPersistsNothingAndReloadsNothing |
| git-client-projects-project-window-manager-008 | will-change-cancels-pending-persist | Open a project against a stand-in git client that answers a worktree listing at once with two checkouts and pauses on every revision lookup; move keyboard focus into the window's first pane immediately after opening, before the reconcile's write lands. | after the reconcile lands, the stored tabs' titles are `{"main", "feature"}`, not the window's single-pane placeholder — the will-change-tabs callback's cancellation stopped the window's own debounced write from overwriting the reconcile's write — ProjectWindowManagerControllerTests.swift › testAFirstOpenKeepsTheReconciledTabsAgainstTheWindowsDebouncedWrite |
| git-client-projects-project-window-manager-009 | project-controller-precedes-window, open-project-registration-order | Open a project, wait for it to persist, close it, then open the same repository again and read the window's panes at the moment the open call returns and again roughly 800 ms later. | the pane count and the panes' own identities are unchanged across that interval, and every top-edge tab item is view-controller-backed once the scan lands — a reopen that finds nothing changed never discards and rebuilds panes it already has — ProjectWindowManagerControllerTests.swift › testReopeningAnUnchangedProjectKeepsThePanesItsWindowBuilt |
| git-client-projects-project-window-manager-010 | close-drops-controller-and-reregisters-survivors | Open a project, then close it by id and check whether its controller reports itself closed with no intervening suspension. | the controller reports open immediately before the close and closed immediately after it, in the same synchronous call — proving the close is marked synchronously from the close handling, not from separately scheduled work — ProjectWindowManagerControllerTests.swift › testClosingMarksTheControllerClosedInTheSameTurn |
| git-client-projects-project-window-manager-011 | restore-plan-is-pure, restore-forgets-missing-folders, restore-reopens-existing-folders | Not present in the given test suite; synthesized from the source. Compute the restore plan for three repositories a, b, c, where a and b were open at last quit and only a and c still exist on disk. | the reopen set is `{a}` and the forget set is `{b}`; c (never flagged open) appears in neither set — synthesized, no dedicated test in the given suite |
| git-client-projects-project-window-manager-012 | shutdown-all-language-services-runs-concurrently, shutdown-all-language-services-drains-pending-teardowns | Not present in the given test suite; synthesized from the source together with the pending-teardowns registry's own drain guarantee. Open two projects with distinct counting stand-ins for language services, close one of them (starting its teardown through the pending-teardowns registry), then immediately shut down all language services before that teardown would otherwise finish on its own. | both counting stand-ins report exactly one shutdown call once shutting down all language services returns — the closed project's already-detached teardown is still waited for, not just the still-open project's — synthesized, no dedicated test in the given suite |

## Edge Cases

- **Null and empty input**: The language-services factory and the command
  registry being absent are documented, supported configurations, not
  gaps — opening a project logs and continues with no language services
  (**open-project-tolerates-missing-language-factory**), and every
  command-registry call elsewhere becomes a no-op. The coordinator being
  absent (never attached) makes restoring open projects a no-op
  (**restore-open-projects-requires-coordinator**); it also leaves
  opening a project unable to pass its database guard — see
  **no-database-open-failure-signal** (MUST/SHOULD as annotated on each
  cited requirement).
- **Boundary values**: The open-order list and the open-controllers table
  may hold zero, one, or many project ids; every value derived from them
  (the open-workspaces list, the open-window-controllers list, the
  frontmost-window-controller lookup's final fallback) MUST handle zero
  entries by producing an empty list or nothing, with no special case in
  the source for either end (MUST, by the absence of any guard).
- **Concurrent access**: Every mutation of the open-controllers table,
  the open-order list, the project-controllers table, the
  adopted-for-scripting set, and the key-observer table is confined to
  the manager's main execution context (**main-thread-confinement**), so
  no interleaving between opening a project, closing a project, adopting
  a window for scripting, and the notification-driven handlers can
  observe a torn collection (MUST). One race the source does guard
  explicitly: opening a project's own completion work and a later close
  of the same project both reach the same project controller, and
  **callback-wiring-checks-current-controller**'s identity check is what
  stops a stale controller's callback from reaching a window that has
  moved on to a different controller (see vector -007).
- **Error states**: A failed setting read or write is logged and answered
  with a default (closed, for a read; the write simply does not happen)
  rather than propagated to any caller (**window-open-read-failure-defaults-closed**,
  **window-open-flag-read-write** — both MUST, by their failure
  handling). Opening a project's own database-missing guard is the one
  error path in this file with no signal at all beyond the log line; see
  **no-database-open-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense
  — every operation this file performs is local: the database, the
  filesystem check the restore plan's exists-on-disk predicate performs,
  and git through the project controller (documented in
  `agentictoolkit://cookbook/workspace/projects/project-controller`).
  None of it reaches a remote host.
- **Cancellation and timeouts**: Opening a project's own opening work is
  not cancelled by a subsequent close of that project; the in-flight work
  keeps running to completion, and it is the project controller's own
  closed-state guard — not anything in this file — that stops it from
  persisting stale data or reloading a dead window (see
  `agentictoolkit://cookbook/workspace/projects/project-controller`'s
  reconcile-aborts-after-a-late-close requirement, and vector -007
  above). Shutting down all language services waits for its group of
  concurrent operations and then for the pending-teardowns registry to
  drain, unconditionally, with no timeout of its own; the roughly
  2.5-second-per-server ceiling belongs to the subprocess channel's own
  termination step, documented on the pending-teardowns registry.
- **Missing file or unreachable server**: A repository whose folder was
  deleted or renamed since the app last quit is not distinguished from
  any other flagged-open project until the restore plan checks whether
  it still exists on disk; it is moved to the forget set and its
  persisted flag is cleared rather than reopened onto an empty tree
  (**restore-forgets-missing-folders**, see vector -011). A repository
  opened directly (not via restore) whose folder is already missing is
  not checked here at all — the workspace and controller are built
  regardless, and the resulting git failure is the project controller's
  to degrade gracefully from, not this file's.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| git client | a git client reference | the shared git client | The git client every project controller this manager builds is given, through the workspace. |
| command registry | a command registry reference (optional) | absent | Passed to every project controller this manager builds; absent disables command-palette integration for every project. |
| language-services factory | a function from a project's directory to language services (optional) | absent | Called with a project's directory each time opening a project builds a new workspace; absent, or a factory returning nothing, opens the project with no language services. |
| project-closed callback | a callback (optional) | absent | Fired once, synchronously, from the window-close handling, before the closing project's workspace is dropped from the open-controllers table. |
| open-projects-changed callback | a callback (optional) | absent | Fired after every mutation of the open-project set, from refreshing the open-workspace-ids list. |
| coordinator | a coordinator reference, held weakly (optional) | absent until attached | Supplies the database (required for opening a project to proceed) and the repository list (read by restoring open projects); set by attaching to a coordinator, which also registers the manager as that coordinator's opener. |
| app-activation call (internal, test-only seam) | a function with no arguments | asks the app to come forward, unless already active | How a newly or already-open project window asks the app to come forward; overridable so a test can count activations instead of driving real app state. |

This file reads no environment variable and no settings key of its own
beyond the single per-project setting row it reads and writes, keyed by
the setting key `"window.open"`.

## Deep Linking

Not applicable: this file defines no URL scheme, route, or navigation
destination of its own.

## Localization

Not applicable: the five string literals in this file are log messages,
read only from the system console, never displayed to the app's user.
The file produces no user-facing string of its own.

## Accessibility Options

Not applicable: this file renders no view of its own. Reduce Motion,
Increase Contrast, and Differentiate Without Color are the concern of the
window controller and the panes it hosts, not this manager.

## Feature Flags

Not applicable: this file contains no feature-flag or build-configuration
check.

## Analytics

Not applicable: this file makes no analytics or event-tracking call.

## Privacy

- **Data collected**: None beyond what the project browser already shows
  — a repository's id, name, and local filesystem path — and whether its
  window is currently open.
- **Storage**: The open/closed flag is durable, in the project-settings
  store (local disk only). The live-session bookkeeping (the
  open-controllers table, the open-order list, the project-controllers
  table, the adopted-for-scripting set, the key-observer table, the
  close-observer table) is in-memory only and does not survive a
  relaunch.
- **Transmission**: None; every call this file makes is local (the
  database, the filesystem, and the platform's window/notification
  system).
- **Retention**: The `"window.open"` row for a project lives with that
  project's row and is deleted along with it, per the persisted key's own
  documentation — it is not retained independently of the project it
  describes.
- Every log call in this file explicitly marks the repository name or id
  it logs as public, non-sensitive data; both are already visible to the
  user in the project browser and the window's own title, and no
  credential or token is logged anywhere in this file.

## Logging

This file makes five logging calls. Subsystem defaults to the app's own
bundle identifier; category is this component's name.

| Event | Level | Message |
|-------|-------|---------|
| The database is absent when opening a project | error | `Cannot open <repo.name>: no project database attached` |
| The language-services factory is absent, or returns nothing | info | `No language services for <repo.name>: no factory wired` |
| A flagged-open repository's folder is missing at restore | info | `Not reopening <repo.name>: its folder is gone` |
| Reading the window-open flag fails | error | `Could not read window state for <repoID>: <error>` |
| Writing the window-open flag fails | error | `Could not record window state for <repoID>: <error>` |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWindowManager.swift`,
  built on `AppKit` (`NSApp`, `NSWindow`, `NSNotification`), `Combine`
  (`ObservableObject`/`@Published`), `os` (its `Logger`, via `Loggable`), and
  `AgenticToolkitCore` (`GitRepo`, `GitClient`, `ProjectWorkspace`,
  `ProjectController`, `ProjectsCoordinator`, `ProjectOpening`,
  `CommandRegistry`, `ComposableTabsWindowController`, `ProjectLanguageServices`,
  `PendingTeardowns`). It uses no SwiftUI API; a SwiftUI-hosted project
  browser would still need this type as a plain `@MainActor` `ObservableObject`
  feeding a `WindowGroup`/`NSHostingController`, not a `Scene` itself.
  `ProjectWindowManager` is declared `@MainActor` and declares no `Sendable`
  conformance of its own, so every stored property and method is confined to
  the main actor by that declaration alone.
- **Compose**: Model `ProjectWindowManager` as a plain `@MainActor`-confined
  class (or dispatched onto Compose's main-thread dispatcher) holding a
  `Map<UUID, WindowController>`, a `List<UUID>` for open order, and a
  `StateFlow<List<UUID>>` in place of `@Published var openWorkspaceIDs`.
  Replace the `NSWindow.willCloseNotification`/`didBecomeKeyNotification`
  observers with the host platform's own window lifecycle callbacks, keeping
  the same ordering rule — deregister first, then run the teardown a
  coroutine scope can outlive its window's own scope (mirroring
  **close-teardown-added-to-shared-registry**'s detached-teardown registry).
- **React/Web**: There is no per-project native window on the web; the
  closest analogue is a browser tab or a workspace panel keyed by project id
  in client state, with `restorePlan`'s pure reopen/forget split reproduced as
  a plain function over persisted "was this project open" flags read from
  `localStorage` or a user-settings endpoint, and the language-server
  teardown concern replaced by whatever cancels in-flight requests for a
  closed panel's editor sessions.
- **AppKit / UIKit**: The source already is AppKit; a UIKit (iOS) port would
  replace `NSWindow`/`NSWindowController` lifecycle notifications with
  `UIWindowScene`/`UIScene` lifecycle delegate callbacks, and would need its
  own multi-window story since iOS treats "one window per project" as a
  multi-scene arrangement rather than AppKit's independent `NSWindow`s; the
  controller-pairing, restore-plan, and teardown-draining logic ports
  unchanged.
- **WinUI 3**: Port `ProjectWindowManager` as a plain C# class holding
  `Dictionary<Guid, Window>` (`controllers`), `List<Guid>` (`openOrder`), and
  an `ObservableCollection<Guid>` or `event Action?`-backed property in place
  of `openWorkspaceIDs`/`onOpenProjectsChanged`, with no interface requiring
  thread-affinity of its own — mirror `@MainActor` confinement by only ever
  touching this object from the UI thread (`DispatcherQueue`), the same
  discipline `ProjectController`'s WinUI port already assumes (see
  `agentictoolkit://cookbook/workspace/projects/project-controller`). Reproduce
  `NSWindow.willCloseNotification`'s `queue: nil` synchronous delivery
  (**close-observer-uses-nil-queue**) with `Window.Closed`, handled inline on
  the UI thread rather than through a dispatcher post, so a scan that closes a
  window and deletes its row in the same call stack still runs its cleanup
  before that row is gone. Reproduce **close-teardown-added-to-shared-registry**
  with a small `PendingTeardowns`-equivalent — a `Dictionary<int, Task>` that a
  window-close `Task.Run`-free async method adds itself to and that quit's
  own async shutdown drains in a loop — rather than firing a bare
  `Task.Run(async () => ...)` that a process exit can orphan. Read and write
  the persisted "window open" flag through the same `System.Data.Sqlite`-backed
  settings store `agentictoolkit://cookbook/workspace/projects/project-database`
  describes, using `HttpClient`/`System.Text.Json`/`Task`/`async` and
  `Windows.Storage` only where a networked or file-based collaborator this
  manager delegates to (git, language servers) needs them — this type itself
  makes no HTTP call and reads no `Windows.Storage` file directly.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWindowManager.swift` |

## Design Decisions

**Decision**: `openProject(_:)` calls `refreshOpenWorkspaceIDs()` — and
therefore `onOpenProjectsChanged?()` — only after the window has been
registered, ordered to the front, and offered app activation, not at the
point the controller is first added to `controllers`.
**Rationale**: The doc comment explains the bug this fixes directly: firing
earlier "published 'the open set changed' while `NSApp` still described the
previous window," so `frontWindowController`-derived seams like the extension
hosts' `workspaceRoots` ran "against the *old* project's roots, or against
none at all on the first project of the session, and never ran again"
(`ProjectWindowManager.swift`).
**Approved**: pending

**Decision**: The per-controller callbacks `openProject(_:)` assigns
(`onTabsDidChange`, `onTabItemsNeedRefresh`) capture `self`, `controller`, and
`projectController` weakly and re-check `self.projectControllers[repo.id]
=== projectController` before touching the window.
**Rationale**: Labeled "Ruling Q" in the source: the guard exists so "a
controller that was closed and replaced — or one whose window is already gone
— can never drive a window that is no longer its own".
**Approved**: pending

**Decision**: `observeClose(of:repoID:recordsOpenState:)` registers its
`NSWindow.willCloseNotification` observer with `queue: nil` rather than
`.main`.
**Rationale**: The inline comment states the failure mode a `.main`-queued
(enqueued) delivery would allow: "the scan closes a deleted project's window
and then deletes its row in the same turn, and a block that lands after that
deletes-then-writes — a foreign key that no longer resolves." `queue: nil`
keeps the handler on the poster's thread, in the same run-loop turn as the
close.
**Approved**: pending

**Decision**: The close handler skips `setWindowOpen(false, repoID:)` when
`WindowManager.shared.isTerminating` is `true`.
**Rationale**: The inline comment states the reason directly: "AppKit closes
still-open windows on the way out of the app. Recording that as 'the user
closed it' would stop every open project from reopening next launch, which is
the opposite of what quitting with windows open means".
**Approved**: pending

**Decision**: The close handler captures the outgoing `ProjectController`
and/or `languageServices` before removing the project from `controllers`, and
routes the scheduled teardown through the captured `ProjectController
.shutdown()` when one exists, falling back to the captured `languageServices
.shutdown()` only when it does not — never both.
**Rationale**: `ProjectController.shutdown()` and the inline
`languageServices.shutdown()` path both end at the same
`languageServices.shutdown()` call; running both "would shut the same
services down twice." The inline fallback exists only for a window
`adoptForScripting(_:)` registered, which has no project controller of its
own to route through.
**Approved**: pending

**Decision**: `shutdownAllLanguageServices()` hands every started-but-not-yet-
finished teardown to `PendingTeardowns` rather than starting a bare, unheld
`Task` at each window close.
**Rationale**: `PendingTeardowns`' own doc comment names the two independent
near-misses this extraction fixes — this type's window-close observer and
`LanguageServerRegistry.reconcile` both started detached teardown work and
"the app-level quit path... enumerated a collection the work had already
left, found nothing to wait for, and returned," orphaning a subprocess when
the process then exited inside `SubprocessChannel.terminate()`'s roughly
2.5-second budget (`PendingTeardowns.swift`, class doc comment;
`ProjectWindowManager.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |

Notes: separation-of-concerns passes because `ProjectWindowManager` owns
exactly window/controller lifecycle bookkeeping — the `controllers`/
`openOrder`/`projectControllers`/`keyObservers`/`closeObservers` tables — and
delegates every git read and tab-reconciliation decision to
`ProjectController`, every persistence read/write to `ProjectDatabase` through
`ProjectWorkspace`, and every pane/tab render decision to
`ComposableTabsWindowController`; it never reads git output or a tab record
itself. unit-test-coverage is partial because
`ProjectWindowManagerControllerTests.swift` exercises opening, reopening,
activation, key-observer refresh, adoption/fallback teardown routing, closing
mid-open-task, the two-writer debounce race, and synchronous `markClosed()`
timing — but `restorePlan`, `restoreOpenProjects`, and
`shutdownAllLanguageServices` have no test anywhere in the repository
(vectors -011 and -012 above are synthesized to describe what such tests
would assert). explicit-error-handling is partial: the two
`ProjectDatabase`-setting paths and the missing-language-factory path all log
their failure, but `openProject(_:)`'s missing-database guard gives the
caller no signal beyond that log — see
**no-database-open-failure-signal**. graceful-degradation passes because a
missing database, a missing language-service factory, and a missing-on-disk
folder at restore each fall back to a documented, reduced behavior (no
window, no completions, no reopen) rather than crashing or reopening a broken
window. state-recovery is partial because `restoreOpenProjects()` correctly
separates "never opened" from "flagged open, folder gone," but
`isWindowOpen(repoID:)` maps a genuine database read failure to the identical
`false` result as "was never open," so a transient read error at launch
silently drops a window from the restore set with only a log line to show for
it. main-thread-freedom passes because every subprocess- or database-bound
wait this file starts (`ProjectController.open()`/`refreshCheckouts()`, each
service's `shutdown()` inside the task group, `PendingTeardowns.drain()`) is
reached through `await`, releasing the main actor for the suspension.
secure-log-output passes because every log call names only a repo's UUID,
name, or path — already visible to the user in the project browser and the
window's own title — and no credential, token, or other secret is logged
anywhere in this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
