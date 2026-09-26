---
id: 7f1b8bef-e78e-4cac-be55-c948fe9062e5
title: ProjectWindowManager
domain: agentictoolkit://cookbook/macos/features/projects/project-window-manager
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owns one AppKit window per open project, pairs each with a ProjectController,
  restores windows open at last quit, and drains quit-time teardowns.
platforms:
- swift
- macos
tags:
- git
- projects
- window-controller
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/projects/project-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller
- agentictoolkit://cookbook/macos/features/projects/git-repo
- agentictoolkit://cookbook/macos/features/projects/project-database
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

# ProjectWindowManager

## Overview

`ProjectWindowManager` (`ProjectWindowManager.swift`) keeps one AppKit window
per open project, keyed by `git_repo.id` rather than by path, so opening "the
same project" twice after it has moved or been renamed still raises the same
window. For every project it opens it builds a matched pair — a
`ProjectController` that owns the checkout/tab reconciliation and a
`ComposableTabsWindowController` that hosts it — and tears both down together
when the window closes. It conforms to `ProjectOpening` so a
`ProjectsCoordinator` can hand it project-open/close requests, and to
`ObservableObject` so a browser can watch which projects are currently open.
Beyond the windows it opens itself, it can also adopt a window a host built by
some other means, so scripting can see it too, and it restores whichever
projects were flagged open when the app last quit. It is `@MainActor` and
holds no `Sendable` conformance of its own — every property and method is
confined to the main actor by that declaration alone.

## Behavioral Requirements

- **project-opening-conformance**: `ProjectWindowManager` MUST conform to
  `ProjectOpening` (supplying `openProject(_:)` and `closeProject(repoID:)`)
  and to `ObservableObject` (`ProjectWindowManager.swift`).
- **main-actor-isolation**: `ProjectWindowManager` MUST be declared
  `@MainActor` and MUST NOT declare `Sendable` conformance, so every stored
  property and method is confined to the main actor by that declaration alone.
- **shared-singleton**: `ProjectWindowManager` MUST expose a process-wide
  instance via `public static let shared = ProjectWindowManager()`.
- **open-window-setting-key**: The manager MUST record whether a project's
  window was open at quit as a `project_setting` row keyed by the constant
  `"window.open"` (`openWindowKey`), scoped per `repoID` rather than kept in an
  app-wide preference, so the flag is deleted along with the project row it
  belongs to rather than surviving it.
- **injectable-collaborators**: `gitClient`, `commandRegistry`, and
  `languageServicesFactory` MUST be public, externally settable properties
  defaulting to `GitClient.shared`, `nil`, and `nil` respectively, so a test or
  an alternate host can substitute a throwaway git client, decline
  command-palette integration, or decline language services without
  subclassing.
- **attach-registers-opener**: `attach(to:)` MUST store the given
  `ProjectsCoordinator` weakly as `coordinator` and MUST call
  `coordinator.setOpener(self)`, registering itself as that coordinator's
  `ProjectOpening` implementation.
- **front-window-controller-fallback-chain**: `frontWindowController` MUST
  return, in order, the window controller of `NSApp.keyWindow`, then the first
  `ComposableTabsWindowController` found in `NSApp.orderedWindows`, then
  `controllers[openOrder.last]`, returning the first of the three that
  resolves to a non-nil value.
- **open-workspaces-derived**: `openWorkspaces` and `openWindowControllers`
  MUST be computed by mapping `openOrder` through `controllers`, filtering out
  any id no longer present, rather than maintained as separately stored arrays.
- **refresh-publishes-then-notifies**: `refreshOpenWorkspaceIDs()` MUST assign
  `openWorkspaceIDs` from `openOrder` filtered by membership in `controllers`,
  and MUST call `onOpenProjectsChanged?()` only after that assignment
  completes.
- **every-mutation-site-refreshes**: Every method that adds to or removes from
  `controllers` — `adoptForScripting(_:)`, `forgetForScripting(_:)`,
  `openProject(_:)`, and the window-close handler `observeClose(of:
  repoID:recordsOpenState:)` installs — MUST call `refreshOpenWorkspaceIDs()`
  after the mutation.
- **adopt-for-scripting-idempotent**: `adoptForScripting(_:)` MUST return
  immediately, registering nothing again, when `controllers[controller.project
  .id]` already has an entry.
- **adopt-for-scripting-registers-without-persisting**: On the
  non-idempotent path, `adoptForScripting(_:)` MUST insert the controller into
  `controllers` and `openOrder`, add its id to `adoptedForScripting`, and call
  `observeClose(of:repoID:recordsOpenState: false)`, and MUST NOT call
  `setWindowOpen` in either direction.
- **forget-for-scripting-guarded**: `forgetForScripting(_:)` MUST remove the
  controller from `controllers`, `openOrder`, and `adoptedForScripting`, and
  MUST remove its close observer, only when `controllers[id] === controller`
  and `adoptedForScripting.contains(id)` are both true; otherwise it MUST do
  nothing.
- **project-controller-lookup-nil-for-adopted**: `projectController(for:)`
  MUST return `nil` for a repo id whose window was registered by
  `adoptForScripting(_:)` rather than built by `openProject(_:)`, because
  `adoptForScripting(_:)` never inserts into `projectControllers`.
- **open-project-raises-existing-window**: When `controllers[repo.id]`
  already has an entry, `openProject(_:)` MUST call `existing.project.update
  (repo: repo)`, `existing.showWindow(nil)`, `existing.window?
  .makeKeyAndOrderFront(nil)`, and `activateApp()`, and MUST return without
  building a new workspace or controller.
- **no-database-open-failure-signal**: `openProject(_:)` returns `Void`, is not `async`/`throws`, and its only response to `coordinator?.database` being `nil` is one `error`-level log call; no return value, thrown error, or callback tells the caller — a menu action or a double-click in the project browser — that nothing happened, so the user sees no window and no explanation. The failure is logged, not surfaced.
- **open-project-tolerates-missing-language-factory**: When
  `languageServicesFactory` is `nil` or the closure returns `nil`,
  `openProject(_:)` MUST log that fact at info level and MUST continue
  building the workspace and window with `languageServices` set to `nil`.
- **open-project-starts-language-services**: When
  `languageServicesFactory?(repo.url)` returns a non-nil value,
  `openProject(_:)` MUST call `languageServices?.start()` before constructing
  the `ProjectController`.
- **project-controller-precedes-window**: `openProject(_:)` MUST construct the
  `ProjectController` and store it in `projectControllers[repo.id]` before
  constructing the `ComposableTabsWindowController`, and MUST pass that same
  controller as the window's `tabItemDataSource:` argument to `init` rather
  than assigning it afterward.
- **callback-wiring-checks-current-controller**: The `onTabsDidChange` and
  `onTabItemsNeedRefresh` closures `openProject(_:)` assigns to the new
  `ProjectController` MUST capture `self`, `controller`, and
  `projectController` weakly and MUST call through to the window only when
  `self.projectControllers[repo.id]` is still reference-identical to the
  captured `projectController`.
- **will-change-cancels-pending-persist**: The `onWillChangeTabs` closure
  `openProject(_:)` assigns MUST call `controller?.cancelPendingTabPersist()`.
- **open-project-registration-order**: On the new-project path,
  `openProject(_:)` MUST, in this order: register the controller in
  `controllers` and append its id to `openOrder`; call `showWindow(nil)` and
  `window?.makeKeyAndOrderFront(nil)`; call `activateApp()`; call
  `refreshOpenWorkspaceIDs()`; call `observeClose(of:repoID:
  recordsOpenState: true)` and `observeBecameKey(of:repoID:)`; start `Task {
  await projectController.open() }`; call `setWindowOpen(true, repoID:
  repo.id)`.
- **open-fires-changed-notification-after-window-is-frontmost**:
  `openProject(_:)` MUST call `refreshOpenWorkspaceIDs()` — and therefore
  `onOpenProjectsChanged?()` — only after the window has been registered,
  ordered to the front, and offered app activation, and MUST NOT call it at
  the point the controller is first registered.
- **initial-key-notification-not-guaranteed**: Because
  `makeKeyAndOrderFront(nil)` runs before `observeBecameKey(of:
  repoID:)` installs its observer, a newly opened window's own
  first `didBecomeKeyNotification` MAY or MAY NOT be seen by that observer,
  and `openProject(_:)` MUST NOT add any synchronization to force either
  outcome.
- **close-project-delegates-and-no-ops-on-unknown-id**:
  `closeProject(repoID:)` MUST call `close()` on `controllers[repoID]` when an
  entry exists, and MUST do nothing when it does not.
- **shutdown-all-language-services-runs-concurrently**:
  `shutdownAllLanguageServices()` MUST collect every currently-open project's
  `languageServices` and MUST shut them all down concurrently inside one
  `withTaskGroup`, never sequentially.
- **shutdown-all-language-services-drains-pending-teardowns**: After its task
  group completes, `shutdownAllLanguageServices()` MUST call `await
  closeTeardowns.drain()`, so a language service whose shutdown was started by
  a prior window close — one already removed from `controllers` — is still
  waited for.
- **restore-open-projects-requires-coordinator**: `restoreOpenProjects()`
  MUST return immediately, reopening nothing, when no `coordinator` has been
  attached.
- **restore-plan-is-pure**: `restorePlan(repos:wasOpen:existsOnDisk:)` MUST be
  a `static` function with no side effect, computing `reopen` as every repo
  for which both `wasOpen` and `existsOnDisk` are true, and `forget` as every
  repo for which `wasOpen` is true and `existsOnDisk` is false.
- **restore-forgets-missing-folders**: For every repo in `plan.forget`,
  `restoreOpenProjects()` MUST log at info level and MUST call
  `setWindowOpen(false, repoID:)`, clearing the persisted flag instead of
  reopening a window onto a missing folder.
- **restore-reopens-existing-folders**: For every repo in `plan.reopen`,
  `restoreOpenProjects()` MUST call `openProject(repo)`.
- **window-open-flag-read-write**: `isWindowOpen(repoID:)` MUST read the
  `openWindowKey` setting through `database.setting(repoID:key:)` and MUST
  treat exactly the string `"1"` as open; `setWindowOpen(_:repoID:)` MUST
  write `"1"` for `true` and `nil` (deleting the row) for `false`, through
  `database.setSetting(repoID:key:value:)`.
- **window-open-read-failure-defaults-closed**: When `database.setting(repoID:
  key:)` throws, `isWindowOpen(repoID:)` MUST log the failure at error level
  and MUST return `false` — the same value it returns for a project whose
  window was genuinely never marked open.
- **became-key-refreshes-checkouts**: `observeBecameKey(of:repoID:)` MUST
  install an `NSWindow.didBecomeKeyNotification` observer that, on firing,
  looks up `projectControllers[repoID]` and, when found, starts `Task { await
  projectController.refreshCheckouts() }`.
- **close-flag-respects-app-termination**: In the window-close handler, when
  `recordsOpenState` is `true`, `setWindowOpen(false, repoID:)` MUST be called
  only when `WindowManager.shared.isTerminating` is `false`, so a window
  AppKit closes on its way out of a quitting app is not recorded as the user
  having closed it.
- **close-drops-controller-and-reregisters-survivors**: The close handler
  MUST remove the closing project's entry from `projectControllers` and call
  `markClosed()` on it synchronously, then MUST call `reregisterCommands()`
  on every remaining value in `projectControllers`, so a branch-command id
  that collided across two windows over the same repository is handed back to
  the surviving window.
- **close-captures-teardown-target-before-removing-it**: The close handler
  MUST read `self.projectControllers.removeValue(forKey:)`'s result and
  `self.controllers[repoID]?.project.languageServices` before removing
  `repoID` from `controllers`, `openOrder`, and `adoptedForScripting`, and
  MUST route the teardown it schedules through the captured `ProjectController
  .shutdown()` when one exists, or through the captured `languageServices
  .shutdown()` only when it does not — never both.
- **close-observer-uses-nil-queue**: `observeClose(of:repoID:
  recordsOpenState:)` MUST register its `NSWindow.willCloseNotification`
  observer with `queue: nil`, so the handler runs synchronously on the
  posting thread in the same run-loop turn as the close, never after an
  enqueue delay.
- **close-fires-on-project-closed-before-removal**: The close handler MUST
  call `onProjectClosed?(project)` while `controllers[repoID]` still holds
  the closing project — i.e. before `self.controllers.removeValue(forKey:
  repoID)`.
- **close-teardown-added-to-shared-registry**: The close handler MUST hand
  its teardown closure to `self.closeTeardowns.add(_:)` rather than starting
  an unmanaged `Task`, so `shutdownAllLanguageServices()` can find and await
  it even after this project's controller and window have already left every
  other collection.

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
concern of `ComposableTabsWindowController` and the view controllers it hosts,
neither of which this file renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-window-manager-001 | project-controller-precedes-window, callback-wiring-checks-current-controller, open-project-registration-order | Build a fresh manager (never `.shared`), attach it to a coordinator over a one-repo fixture, set `gitClient`, call `manager.openProject(repo)`, then wait for `controller.workspace.storedTabs()` to become non-nil (`testOpeningAProjectBuildsAControllerAndClosingDropsIt`). | `manager.projectController(for: repo.id)` is non-nil and its `workspace.directoryURL` (resolved) equals the fixture's root; the stored tabs' titles equal `["main"]`; `manager.windowController(for: repo.id)!.tabItemDataSource === controller`; once the pending reload lands, every top-edge tab item is `.viewController`, never `.title`; `manager.closeProject(repoID: repo.id)` leaves `manager.projectController(for: repo.id)` `nil`. |
| git-client-projects-project-window-manager-002 | open-project-raises-existing-window | Open a project, wait for its tabs to persist, then call `manager.openProject(repo)` again on the same repo with `manager.activateApp` replaced by a counting closure (`testOpeningAProjectAsksForTheForeground`). | `activations == 1` after the first open and `activations == 2` after the second — the already-open branch still calls `activateApp()`. |
| git-client-projects-project-window-manager-003 | became-key-refreshes-checkouts, callback-wiring-checks-current-controller | Open a project on a repo with one checkout, add a `feature` worktree on disk, then post `NSWindow.didBecomeKeyNotification` against the open window (`testTheWindowBecomingKeyRefreshesCheckouts`). | `controller.checkouts.map(\.displayName)` becomes `["main", "feature"]`; the window's top-edge tab-item count becomes `2`, proving `onTabsDidChange` reached `reloadTabs()`. |
| git-client-projects-project-window-manager-004 | project-controller-lookup-nil-for-adopted, close-captures-teardown-target-before-removing-it | Open one project normally; separately build a `ComposableTabsWindowController` over its own `ProjectWorkspace` and register it with `manager.adoptForScripting(_:)`; close the adopted window (`testAnAdoptedWindowHasNoControllerAndClosesThroughTheFallback`). | `manager.projectController(for:)` is `nil` for the adopted project both before and after its close; `manager.windowController(for:)` is `nil` for it after close; the opened project's own controller is untouched throughout. |
| git-client-projects-project-window-manager-005 | close-drops-controller-and-reregisters-survivors, close-observer-uses-nil-queue | Open a project with a counting fake `git`, wait for its tabs to persist, note the window, close the project, then reopen the same repo id and post `didBecomeKeyNotification` against the now-closed (stale) window (`testClosingRemovesTheKeyObserverSoAStaleWindowCannotTriggerARefresh`). | `manager.hasKeyObserver(for: repo.id)` is `false` immediately after the close; posting the notification against the stale window makes no additional call to the fake `git` once the reopened project's own reconcile has gone quiet. |
| git-client-projects-project-window-manager-006 | close-captures-teardown-target-before-removing-it, close-teardown-added-to-shared-registry | Open two windows — one via `openProject(_:)` with an injected counting `ProjectLanguageServices`, one via `adoptForScripting(_:)` with a different counting instance — then close each independently (`testClosingShutsDownExactlyOneLanguageServicesPerWindow`). | Closing the adopted window shuts down only its own services exactly once and leaves the opened window's services untouched; closing the opened window then shuts down its own services exactly once, never twice. |
| git-client-projects-project-window-manager-007 | close-drops-controller-and-reregisters-survivors, close-observer-uses-nil-queue | Open a project against a fake `git` that marks a `started` file and then sleeps, wait for that marker to appear, and call `manager.closeProject(repoID:)` while the `Task { await projectController.open() }` started by `openProject(_:)` is still in flight (`testClosingWhileTheOpenTaskIsInFlightPersistsNothingAndReloadsNothing`). | `manager.projectController(for: repo.id)` is `nil` immediately after `closeProject`; once the slow fake `git` call finally returns, `controller.workspace.storedTabs()` is still `nil` and `controller.checkouts` is still empty — the in-flight task's reconcile never lands. |
| git-client-projects-project-window-manager-008 | will-change-cancels-pending-persist | Open a project against a fake `git` that answers `worktree list` at once with two checkouts and sleeps on every `rev-parse`; move first-responder focus into the window's first pane immediately after opening, before the reconcile's write lands (`testAFirstOpenKeepsTheReconciledTabsAgainstTheWindowsDebouncedWrite`). | After the reconcile lands, the stored tabs' titles are `{"main", "feature"}`, not the window's single-pane placeholder — the `onWillChangeTabs`-triggered `cancelPendingTabPersist()` stopped the window's own debounced write from overwriting the reconcile's write. |
| git-client-projects-project-window-manager-009 | project-controller-precedes-window, open-project-registration-order | Open a project, wait for it to persist, close it, then open the same repo again and read the window's panes at the moment `openProject(_:)` returns and again roughly 800 ms later (`testReopeningAnUnchangedProjectKeepsThePanesItsWindowBuilt`). | The pane count and pane identities (`===`) are unchanged across that interval, and every top-edge tab item is `.viewController` after the scan lands — a reopen that finds nothing changed never discards and rebuilds panes it already has. |
| git-client-projects-project-window-manager-010 | close-drops-controller-and-reregisters-survivors | Open a project, then call `manager.closeProject(repoID:)` and check `controller.isClosed` with no intervening `await` (`testClosingMarksTheControllerClosedInTheSameTurn`). | `controller.isClosed` is `false` immediately before the close and `true` immediately after it, in the same synchronous call stack — proving `markClosed()` runs synchronously from the close handler, not from a scheduled `Task`. |
| git-client-projects-project-window-manager-011 | restore-plan-is-pure, restore-forgets-missing-folders, restore-reopens-existing-folders | Not present in `ProjectWindowManagerControllerTests.swift`; synthesized from `ProjectWindowManager.swift`. Call `ProjectWindowManager.restorePlan(repos: [a, b, c], wasOpen: { $0 == a || $0 == b }, existsOnDisk: { $0 != b })`. | `plan.reopen == [a]` and `plan.forget == [b]`; `c` (never flagged open) appears in neither list. |
| git-client-projects-project-window-manager-012 | shutdown-all-language-services-runs-concurrently, shutdown-all-language-services-drains-pending-teardowns | Not present in `ProjectWindowManagerControllerTests.swift`; synthesized from `ProjectWindowManager.swift` together with `PendingTeardowns.swift`'s own drain guarantee. Open two projects with distinct counting `ProjectLanguageServices`, close one of them (starting its teardown through `closeTeardowns`), then immediately call `await manager.shutdownAllLanguageServices()` before that teardown would otherwise finish on its own. | Both counting services report exactly one `shutdown()` call once `shutdownAllLanguageServices()` returns — the closed project's already-detached teardown is still waited for, not just the still-open project's. |

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
  `agentictoolkit://cookbook/macos/features/projects/project-controller`). None of
  it reaches a remote host.
- **Cancellation and timeouts**: `openProject(_:)`'s `Task { await
  projectController.open() }` is not cancelled by a subsequent
  `closeProject(repoID:)`; the in-flight task keeps running to completion, and
  it is `ProjectController`'s own `isClosed` guard — not anything in this file
  — that stops it from persisting stale data or reloading a dead window (see
  `agentictoolkit://cookbook/macos/features/projects/project-controller`'s
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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `gitClient` | `GitClient` | `.shared` | The git client every `ProjectController` this manager builds is given, through `ProjectWorkspace`. |
| `commandRegistry` | `CommandRegistry?` | `nil` | Passed to every `ProjectController` this manager builds; `nil` disables command-palette integration for every project. |
| `languageServicesFactory` | `(@MainActor (URL) -> ProjectLanguageServices)?` | `nil` | Called with a project's directory URL each time `openProject(_:)` builds a new workspace; `nil`, or a closure returning `nil`, opens the project with no language services. |
| `onProjectClosed` | `(@MainActor (ProjectWorkspace) -> Void)?` | `nil` | Fired once, synchronously, from the window-close handler, before the closing project's `ProjectWorkspace` is dropped from `controllers`. |
| `onOpenProjectsChanged` | `(@MainActor () -> Void)?` | `nil` | Fired from `refreshOpenWorkspaceIDs()` after every mutation of the open-project set. |
| `coordinator` (set via `attach(to:)`) | `ProjectsCoordinator?` (held weakly) | `nil` until `attach(to:)` is called | Supplies `database` (required for `openProject(_:)` to proceed) and `repos` (read by `restoreOpenProjects()`); also receives `setOpener(self)`. |
| `activateApp` (internal, test-only seam) | `() -> Void` | `{ NSApp.activateUnlessQuiet() }` | How a newly or already-open project window asks the app to come forward; overridable so a test can count activations instead of driving real `NSApp` state. |

`ProjectWindowManager.swift` reads no environment variable and no settings
key of its own beyond the single per-project `project_setting` row it
reads/writes through `database.setting(repoID:key:)`/`setSetting(repoID:key:
value:)`, keyed by the constant `openWindowKey = "window.open"`.

## Deep Linking

Not applicable: `ProjectWindowManager.swift` defines no URL scheme, route, or
navigation destination of its own.

## Localization

Not applicable: the five string literals in `ProjectWindowManager.swift` are all `Logger` messages, read only from
Console.app / `os_log`, never displayed to the app's user. The file produces
no user-facing string of its own.

## Accessibility Options

Not applicable: `ProjectWindowManager.swift` renders no view of its own.
Reduce Motion, Increase Contrast, and Differentiate Without Color are the
concern of `ComposableTabsWindowController` and the panes it hosts, not this
manager.

## Feature Flags

Not applicable: `ProjectWindowManager.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: `ProjectWindowManager.swift` makes no analytics or
event-tracking call.

## Privacy

- **Data collected**: None beyond what the project browser already shows a
  repo's UUID, name, and local filesystem path (via `GitRepo`/`repo.url`), and
  whether its window is currently open.
- **Storage**: The open/closed flag is durable, in the `project_setting` table
  through `ProjectDatabase` (SQLite, local disk only). The live-session
  bookkeeping (`controllers`, `openOrder`, `projectControllers`,
  `adoptedForScripting`, `keyObservers`, `closeObservers`) is in-memory only
  and does not survive a relaunch.
- **Transmission**: None; every call this file makes is local (SQLite,
  the filesystem, and `NotificationCenter`/AppKit).
- **Retention**: The `window.open` row for a project lives with that
  project's row and is deleted along with it, per the doc comment on
  `openWindowKey` — it is not retained independently of the
  project it describes.
- Every log call in this file explicitly marks the repo name or id it logs as
  `privacy: .public`; both are already visible
  to the user in the project browser and the window's own title, and no
  credential or token is logged anywhere in this file.

## Logging

`ProjectWindowManager.swift` makes five logging calls, through its `Loggable`
conformance. Subsystem defaults to
`Bundle.main.bundleIdentifier`; category is `ProjectWindowManager`.

| Event | Level | Message |
|-------|-------|---------|
| `coordinator?.database` is `nil` in `openProject(_:)` | error | `Cannot open <repo.name>: no project database attached` |
| `languageServicesFactory` is `nil` or returns `nil` | info | `No language services for <repo.name>: no factory wired` |
| A flagged-open repo's folder is missing at restore | info | `Not reopening <repo.name>: its folder is gone` |
| `database.setting(repoID:key:)` throws in `isWindowOpen(repoID:)` | error | `Could not read window state for <repoID>: <error>` |
| `database.setSetting(repoID:key:value:)` throws in `setWindowOpen(_:repoID:)` | error | `Could not record window state for <repoID>: <error>` |

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
  `agentictoolkit://cookbook/macos/features/projects/project-controller`). Reproduce
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
  settings store `agentictoolkit://cookbook/macos/features/projects/project-database`
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
