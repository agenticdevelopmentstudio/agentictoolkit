<!-- leaf: implement-git-client/projects-project-window-manager--part-2 · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-window-manager--part-2#<slug>`):

- `project-opening-conformance` MUST
- `main-actor-isolation` MUST
- `shared-singleton` MUST
- `open-window-setting-key` MUST
- `injectable-collaborators` MUST
- `attach-registers-opener` MUST
- `front-window-controller-fallback-chain` MUST
- `open-workspaces-derived` MUST
- `refresh-publishes-then-notifies` MUST
- `every-mutation-site-refreshes` MUST
- `adopt-for-scripting-idempotent` MUST
- `adopt-for-scripting-registers-without-persisting` MUST
- `forget-for-scripting-guarded` MUST
- `project-controller-lookup-nil-for-adopted` MUST
- `open-project-raises-existing-window` MUST
- `open-project-tolerates-missing-language-factory` MUST
- `open-project-starts-language-services` MUST
- `project-controller-precedes-window` MUST
- `callback-wiring-checks-current-controller` MUST
- `will-change-cancels-pending-persist` MUST
- `open-project-registration-order` MUST
- `open-fires-changed-notification-after-window-is-frontmost` MUST
- `initial-key-notification-not-guaranteed` MUST
- `close-project-delegates-and-no-ops-on-unknown-id` MUST
- `shutdown-all-language-services-runs-concurrently` MUST
- `shutdown-all-language-services-drains-pending-teardowns` MUST
- `restore-open-projects-requires-coordinator` MUST
- `restore-plan-is-pure` MUST
- `restore-forgets-missing-folders` MUST
- `restore-reopens-existing-folders` MUST
- `window-open-flag-read-write` MUST
- `window-open-read-failure-defaults-closed` MUST
- `became-key-refreshes-checkouts` MUST
- `close-flag-respects-app-termination` MUST

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
