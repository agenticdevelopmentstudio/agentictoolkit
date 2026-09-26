---
id: 5bfadad5-c93b-432a-807e-04be57ff16b4
title: ProjectController
domain: agentictoolkit://cookbook/macos/features/projects/project-controller
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owns a project's checkouts and BranchControllers, reconciles them against
  stored tabs, and answers the window's tab-item and command-registration requests.
platforms:
- swift
- macos
tags:
- git
- projects
- tabs
- checkout
- branch
- command-palette
- macos
- appkit
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/projects/branch-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/composable-tabs/composable-tabs-window-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/multi-tabbed-view-controller/tab-pane/tab-pane-view-controller
- agentictoolkit://cookbook/macos/ui/view-controllers/file-browser/model/git
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectWorkspace.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/BranchController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsTabItemDataSource.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/TabItem.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/AppShell/AppCommand.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectControllerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectController

## Overview

`ProjectController` (`ProjectController.swift`) is the one-per-project-window
owner of a project's `ProjectCheckout`s and their `BranchController`s. It
decides which tabs the window shows by reconciling the checkouts git reports
against the tabs `ProjectWorkspace` has stored, and it answers the window
controller's tab-item requests as a `ComposableTabsTabItemDataSource`. Per its
own doc comment, it "knows nothing about views beyond vending what a branch
controller makes." It serializes its own two entry points (`open()`,
`refreshCheckouts()`) onto one chained `Task` so two overlapping callers
cannot let a slower, earlier git read overwrite a faster, later one, and it
keeps a project's branch-scoped `AppCommand`s registered with the app's
`CommandRegistry` in step with which checkouts currently exist. It is
`@MainActor` and holds no `Sendable` conformance of its own — every property
and method is confined to the main actor by that declaration alone.

## Behavioral Requirements

- **state-surface**: `ProjectController` MUST expose its live state as
  `checkouts: [ProjectCheckout]` and `branchControllers: [ProjectCheckout:
  BranchController]`, both `public private(set)`, as the only project-owned
  collections it maintains (`ProjectController.swift`).
- **tab-item-data-source-conformance**: `ProjectController` MUST conform to
  `ComposableTabsTabItemDataSource` and answer every
  `composableTabsWindowController(_:tabItemFor:on:)` call itself, rather than
  delegating conformance to `workspace` or a `BranchController`
  (`ProjectController.swift`).
- **main-actor-isolation**: `ProjectController` MUST be declared `@MainActor`
  and MUST NOT declare `Sendable` conformance; every stored property and
  method is therefore confined to the main actor by that declaration alone
  (`ProjectController.swift`).
- **required-workspace-optional-registry**: `init(workspace:commandRegistry:)`
  MUST accept `workspace: ProjectWorkspace` as a required parameter with no
  default value, and `commandRegistry: CommandRegistry?` as a required
  parameter (also with no default) whose value MAY be `nil`
  (`ProjectController.swift`).
- **derived-git-client**: `gitClient` MUST be computed as `workspace.gitClient`
  on every access rather than stored or constructed independently, so this
  controller and every `BranchController` it creates read git through the one
  client the workspace was given (`ProjectController.swift`).
- **open-runs-serialized-reconcile**: `open()` MUST call
  `serializedReconcile()` and MUST NOT itself perform any git read, checkout
  assignment, or tab persistence (`ProjectController.swift`).
- **refresh-checkouts-runs-serialized-reconcile**: `refreshCheckouts()` MUST
  call `serializedReconcile()`, the same entry point `open()` uses
  (`ProjectController.swift`).
- **reconcile-calls-chain-in-order**: `serializedReconcile()` MUST capture
  whatever `Task` is currently `inFlightReconcile` as `previous`, start a new
  `Task` that awaits `previous?.value` before doing any work of its own, store
  that new `Task` as `inFlightReconcile`, and await it — so two overlapping
  calls to `open()`/`refreshCheckouts()` always run their reconciles in the
  order they were called, never in the order their own git reads happen to
  finish (`ProjectController.swift`).
- **close-guard-brackets-reconcile-and-refresh**: The `Task` built by
  `serializedReconcile()` MUST check `isClosed` immediately before calling
  `reconcile()` and again immediately after it returns, skipping `reconcile()`
  entirely on the first check's failure and skipping the branch-controller
  refresh loop entirely on the second's (`ProjectController.swift`).
- **branch-controllers-refreshed-after-reconcile**: When both close guards
  pass, `serializedReconcile()`'s `Task` MUST call `await controller.refresh()`
  on every value currently in `branchControllers` (`ProjectController.swift`).
- **mark-closed-is-synchronous-and-final**: `markClosed()` MUST be a
  synchronous (non-`async`) method that sets `isClosed = true` and unregisters
  every current branch controller's commands via `unregisterCommands(of:)`, so
  the flag takes effect in the same main-actor turn as the call that reaches
  it (`ProjectController.swift`).
- **shutdown-closes-then-stops-language-services**: `shutdown()` MUST call
  `markClosed()` and then `await workspace.languageServices?.shutdown()`, in
  that order (`ProjectController.swift`).
- **reregister-commands-guard**: `reregisterCommands()` MUST return
  immediately, registering nothing, when `isClosed` is `true` or
  `commandRegistry` is `nil` (`ProjectController.swift`).
- **reregister-commands-fills-only-gaps**: When that guard passes,
  `reregisterCommands()` MUST register, with `commandRegistry`, every command
  of every current branch controller whose id is not already found by
  `commandRegistry.command(id:)`, and MUST leave every already-registered id
  untouched (`ProjectController.swift`).
- **branch-controller-lookup-resolves-symlinks**: `branchController
  (forDirectory:)` MUST call `resolvingSymlinksInPath()` on its `directory`
  argument before comparing it against `branchControllers`' key directories,
  and MUST return the first match by directory equality
  (`ProjectController.swift`).
- **reconcile-aborts-after-a-late-close**: `reconcile()` MUST await
  `readCheckouts()` and then, before mutating `checkouts`, `branchControllers`,
  or calling `workspace.persistTabs`, MUST return immediately if `isClosed`
  has become `true` during that await (`ProjectController.swift`).
- **reconcile-commits-fresh-checkouts**: Once past that guard, `reconcile()`
  MUST assign the freshly read checkouts to `checkouts` and MUST call
  `syncBranchControllers()` before computing a tab plan
  (`ProjectController.swift`).
- **tab-plan-via-reconciler**: `reconcile()` MUST compute its plan by calling
  `ProjectTabReconciler.plan(stored:checkouts:projectDirectory:)` with
  `workspace.storedTabs()?.tabs ?? []`, the just-assigned `checkouts`, and
  `workspace.directoryURL` (`ProjectController.swift`).
- **unchanged-plan-writes-nothing**: When `stored != nil` and
  `plan.isUnchanged` is `true`, `reconcile()` MUST NOT call
  `workspace.persistTabs`, MUST NOT call `onWillChangeTabs`, and MUST NOT call
  `onTabsDidChange` (`ProjectController.swift`).
- **unchanged-plan-still-signals-checkout-change**: On that same
  unchanged-plan path, `reconcile()` MUST call `onTabItemsNeedRefresh?()` if
  and only if `previousCheckouts != checkouts`, and MUST NOT call it otherwise
  (`ProjectController.swift`).
- **changed-plan-writes-and-signals-in-order**: When `stored == nil` or
  `plan.isUnchanged` is `false`, `reconcile()` MUST call `onWillChangeTabs?()`,
  then `workspace.persistTabs(tabs:activeTabID:enabledEdges:)`, then
  `onTabsDidChange?()`, in that order (`ProjectController.swift`).
- **default-enabled-edge**: `reconcile()` MUST use `stored?.enabledEdges ??
  [.top]` as the enabled-edges list for any newly built tab record
  (`ProjectController.swift`).
- **new-checkout-tabs-copy-arrangement-or-blueprint**: For every checkout in
  `plan.add`, `reconcile()` MUST build its tab records with
  `ProjectTabReconciler.makeRecords(for:enabledEdges:blueprint:)`, where the
  blueprint closure MUST return `arrangement?.inFreshIDs()` when
  `ProjectTabReconciler.arrangement(of:activeTabID:)` over `plan.keep`
  produces one, and MUST otherwise return `workspace.layout.blueprint()`
  (`ProjectController.swift`).
- **active-tab-falls-back-to-first**: `reconcile()` MUST set `activeTabID` to
  the tab in `tabs` whose id equals `stored?.activeTabID`, and MUST fall back
  to `tabs.first?.id` when no tab matches (`ProjectController.swift`).
- **checkouts-from-worktrees**: On a successful `gitClient.worktrees(in:)`
  call, `readCheckouts()` MUST convert the result with
  `ProjectCheckout.checkouts(from:)` — which filters out every bare worktree
  entry (`ProjectCheckout.swift`) — and MUST return a single
  synthetic `ProjectCheckout(directory: workspace.directoryURL, branch: nil,
  isMain: true)` when that conversion yields zero checkouts
  (`ProjectController.swift`).
- **checkouts-ordered-main-first-then-git-order**: `readCheckouts()` MUST
  order a non-empty result as every main checkout followed by every non-main
  checkout, each half preserving the order `gitClient.worktrees(in:)` returned
  it in, and MUST NOT use `sorted(by:)` to do so, since Swift documents
  `sorted(by:)` as not guaranteed stable (`ProjectController.swift`).
- **worktree-read-failure-keeps-last-known**: When `gitClient.worktrees(in:)`
  throws, `readCheckouts()` MUST log the failure — naming the directory but
  never the git output — and MUST return the previous `checkouts` unchanged
  when it is non-empty, or the single synthetic checkout described in
  **checkouts-from-worktrees** when it is empty (`ProjectController.swift`).
- **branch-controllers-reused-by-directory**: `syncBranchControllers()` MUST
  reuse an existing `BranchController` for any checkout whose `directory`
  matches an existing entry's key directory, even when the checkout's
  `branch` differs from that key (`ProjectController.swift`).
- **branch-controllers-created-with-injected-collaborators**: For a checkout
  with no existing controller, `syncBranchControllers()` MUST construct
  `BranchController(checkout:gitClient:statusProvider:)` with this
  controller's own `gitClient` and with `workspace.gitStatusProvider
  (forDirectory: checkout.directory)`, and MUST register every one of that
  new controller's `commands` with `commandRegistry`
  (`ProjectController.swift`).
- **branch-controllers-dropped-with-their-commands**: `syncBranchControllers()`
  MUST unregister the commands of every existing branch controller whose
  checkout directory is absent from the new checkout set, via
  `unregisterCommands(of:)`, before replacing `branchControllers` with the
  newly built dictionary (`ProjectController.swift`).
- **unregister-mirrors-register**: `unregisterCommands(of:)` MUST call
  `commandRegistry?.unregister(id:)` for exactly the ids in the controller's
  current `commands`, no more and no fewer (`ProjectController.swift`).
- **tab-item-resolves-directory-then-branch-controller**:
  `composableTabsWindowController(_:tabItemFor:on:)` MUST resolve the
  directory as `(record.workingDirectory ?? workspace.directoryURL)
  .resolvingSymlinksInPath()`, MUST return `.title(record.title)` when
  `branchController(forDirectory:)` finds none for it, and MUST otherwise
  return `.viewController(branch.makeTabPane(edge:tabID: record.id))`
  (`ProjectController.swift`).
- **persist-failure-signal**: `workspace.persistTabs(...)` (`ProjectWorkspace.swift`) catches a save failure, logs it, and returns nothing; `reconcile()` (`ProjectController.swift`) calls `onTabsDidChange?()` unconditionally right after that call, so the window is told a new tab set was written even when the database write failed — the failure reaches only the log.
- **branch-refresh-close-race**: `serializedReconcile()`'s `for controller in self.branchControllers.values { await controller.refresh() }` (`ProjectController.swift`) does not re-check `isClosed` between iterations, so a `markClosed()` call landing between two of those awaits lets the loop keep running `BranchController.refresh()` — and its git subprocess — for a controller whose commands were already unregistered; the extra refresh has no remaining observer.

## Appearance

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component.

## States

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component. Its runtime state machines — the current
`checkouts`/`branchControllers` snapshot and the `isClosed` lifecycle flag —
are covered under Behavioral Requirements (**reconcile-commits-fresh-checkouts**,
**mark-closed-is-synchronous-and-final**), not here.

## Accessibility

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component. The accessibility of the panes and menu
items it causes to exist is the concern of `BranchController`'s
`TabPaneViewController` and the window's own tab bar, neither of which this
file renders itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-controller-001 | state-surface, required-workspace-optional-registry, checkouts-ordered-main-first-then-git-order, changed-plan-writes-and-signals-in-order, new-checkout-tabs-copy-arrangement-or-blueprint, branch-controllers-created-with-injected-collaborators, default-enabled-edge, active-tab-falls-back-to-first | Build a controller with no `commandRegistry` over a fixture with a `main` checkout and a `feature` worktree; call `await controller.open()` (`testOpenCreatesOneTabGroupPerCheckoutAndPersistsIt`). | `checkouts.map(\.displayName) == ["main", "feature"]`; `checkouts.map(\.isMain) == [true, false]`; `branchControllers.count == 2`; the stored tabs have 2 distinct `groupID`s, titles `["main", "feature"]`, and `workingDirectory` `[repoRoot, worktreeRoot]`. |
| git-client-projects-project-controller-002 | unchanged-plan-writes-nothing | Open a first controller, then build a second `ProjectController` over the *same* `workspace` and call `await second.open()` (`testOpeningAgainKeepsTheStoredTabsAcrossASecondOpen`). | The stored tabs' ids after the second `open()` equal the ids recorded after the first. |
| git-client-projects-project-controller-003 | unchanged-plan-writes-nothing, unchanged-plan-still-signals-checkout-change, branch-controllers-reused-by-directory | Open a controller; record its main checkout's `BranchController` instance; set `onTabsDidChange`; call `await controller.refreshCheckouts()` with nothing changed on disk (`testAnUnchangedRefreshFiresNoChangeAndLeavesStoredTabsAlone`). | Stored tab ids are unchanged; the `onTabsDidChange` counter is `0`; the main checkout's `BranchController` after the refresh is reference-identical (`===`) to the one recorded before it. |
| git-client-projects-project-controller-004 | changed-plan-writes-and-signals-in-order, branch-controllers-dropped-with-their-commands, tab-plan-via-reconciler | Open a controller, set `onTabsDidChange`, run `git worktree remove --force` on the `feature` worktree, then call `await controller.refreshCheckouts()` (`testARemovedWorktreeDropsItsTabOnRefresh`). | `checkouts.map(\.displayName) == ["main"]`; the stored tabs' titles equal `["main"]`; the `onTabsDidChange` counter is `1`. `onWillChangeTabs` is not asserted by this test, but `persistTabs` is observably complete (the new stored tabs are readable) before that counter increments, consistent with the documented call order. |
| git-client-projects-project-controller-005 | tab-item-data-source-conformance, tab-item-resolves-directory-then-branch-controller | After `open()`, call `composableTabsWindowController(_:tabItemFor:on: .left)` for the stored `main` tab record, and again for a stray `TabRecord` whose `workingDirectory` is an unrelated path (`testTabItemsForCheckoutsAreHostedPanesAndOthersStayTitles`). | The `main` call returns `.viewController` hosting a `TabPaneViewController` titled `"main"`; the stray-record call returns `.title("notes")`. |
| git-client-projects-project-controller-006 | branch-controllers-created-with-injected-collaborators, required-workspace-optional-registry | Build a controller with a real `CommandRegistry` and call `await controller.open()` on the two-checkout fixture (`testBranchCommandsAreRegistered`). | `registry.allCommands.map(\.id).filter { $0.hasPrefix("branch.action.") }.count == 6` (2 checkouts × 3 commands each). |
| git-client-projects-project-controller-007 | branch-controllers-dropped-with-their-commands, unregister-mirrors-register | With a registry-backed controller open, remove the `feature` worktree on disk and call `await controller.refreshCheckouts()` (`testARemovedWorktreeUnregistersItsBranchCommands`). | No registered command id is suffixed by the removed checkout's `identifier`; the remaining `"branch.action."`-prefixed command count is `3`. |
| git-client-projects-project-controller-008 | mark-closed-is-synchronous-and-final | Open a registry-backed controller, then call `controller.markClosed()` (`testClosingTheProjectLeavesNoBranchCommandsBehind`). | `registry.allCommands.filter { $0.id.hasPrefix("branch.action.") }` is empty. |
| git-client-projects-project-controller-009 | reregister-commands-fills-only-gaps, mark-closed-is-synchronous-and-final | Two controllers share one `CommandRegistry` over the same repository; both `open()`; `first.markClosed()`; then `second.reregisterCommands()` (`testASecondWindowOverTheSameRepoTakesItsCommandsBackWhenTheFirstCloses`). | After both open, `6` `"branch.action."` commands are registered; after `first.markClosed()`, `0` remain; after `second.reregisterCommands()`, `6` are registered again. |
| git-client-projects-project-controller-010 | reregister-commands-guard | Open a registry-backed controller, call `markClosed()`, then call `reregisterCommands()` (`testAClosedControllerReregistersNothing`). | `registry.allCommands.filter { $0.id.hasPrefix("branch.action.") }` is still empty. |
| git-client-projects-project-controller-011 | branch-controllers-created-with-injected-collaborators | Call `workspace.gitStatusProvider(forDirectory: repoRoot)` *before* `controller.open()`, then `await controller.open()`, then read `controller.branchController(forDirectory: repoRoot)?.statusProvider` (`testEachCheckoutGetsItsOwnStatusProvider`, `testAProviderTakenBeforeTheFirstScanIsTheOneTheBranchControllerShares`). | The `main` and `feature` status providers are distinct (`!==`); the provider taken before `open()` is reference-identical (`===`) to the one the resulting `BranchController` holds. |
| git-client-projects-project-controller-012 | branch-controller-lookup-resolves-symlinks | After `open()`, call `branchController(forDirectory: repoRoot)` and `branchController(forDirectory: unresolvedRepoRoot)`, where `unresolvedRepoRoot` is a symlink to `repoRoot` (`testBranchControllerLookupResolvesAnUnresolvedDirectory`). | Both calls return the identical `BranchController` instance (`===`). |
| git-client-projects-project-controller-013 | worktree-read-failure-keeps-last-known, derived-git-client | Open a controller whose `gitClient` reads its configuration from a flippable source; flip that configuration to a nonexistent executable path; call `await controller.refreshCheckouts()` (`testATransientGitFailureKeepsTheLastKnownCheckouts`). | `checkouts.map(\.displayName)` is still `["main", "feature"]`; `branchControllers.count` is still `2`; the stored tab ids are unchanged from before the flip — proving the injected `gitClient` (reached only through `workspace.gitClient`) is what actually governs the read. |
| git-client-projects-project-controller-014 | reconcile-calls-chain-in-order, close-guard-brackets-reconcile-and-refresh | Using a fake `git` executable whose first `worktree list` call answers slowly with a stale single-checkout result and every later call answers immediately with the fresh two-checkout result: start `open()`, wait for proof its git call began, then start `refreshCheckouts()` concurrently, and await both (`testOverlappingOpenAndRefreshCannotLetAStaleWorktreeReadOverwriteAFreshOne`). | `checkouts.map(\.displayName) == ["main", "feature"]` and the stored tabs' titles equal `["main", "feature"]` — the later, fresher call's write is the one left standing, regardless of which git process happened to finish first. |
| git-client-projects-project-controller-015 | main-actor-isolation | Under the project's `SWIFT_STRICT_CONCURRENCY: complete` build setting, attempt to call `controller.open()` or read `controller.checkouts` from a `nonisolated` context with no `await` and no `@MainActor` hop. | Compilation fails; there is no runtime path that reaches `ProjectController` off the main actor, so this MUST is verified at build time rather than by an XCTest assertion. |
| git-client-projects-project-controller-016 | reconcile-aborts-after-a-late-close, close-guard-brackets-reconcile-and-refresh | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. Call `controller.open()`; while its `readCheckouts()` await is still pending, call `controller.markClosed()`; let `open()`'s task resume. | `checkouts`, `branchControllers`, and the workspace's stored tabs are left exactly as they were before `open()` was called; neither `onWillChangeTabs` nor `onTabsDidChange` fires. |
| git-client-projects-project-controller-017 | branch-controllers-refreshed-after-reconcile | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift` (compare `BranchControllerTests.swift`'s `testRefreshReadsTheBranchFromGitAndReloadsPanes`, which exercises `BranchController.refresh()` in isolation). Rename the `feature` worktree's branch on disk (`git checkout -b renamed`), then call `await controller.refreshCheckouts()`. | `controller.branchController(forDirectory: worktreeRoot)?.currentBranch == "renamed"`, proving the per-branch-controller refresh loop ran even though the checkout list's shape did not change. |
| git-client-projects-project-controller-018 | shutdown-closes-then-stops-language-services | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. Build a `ProjectWorkspace` whose `languageServices` is a test double recording `shutdown()` calls; build a controller over it; call `await controller.shutdown()`. | `controller.isClosed == true`; the branch commands are unregistered exactly as `markClosed()` alone would leave them; the `languageServices` double records exactly one `shutdown()` call. |
| git-client-projects-project-controller-019 | unchanged-plan-still-signals-checkout-change | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. After `open()`, set `onTabItemsNeedRefresh`; rename the `feature` worktree's branch on disk without adding or removing a worktree; call `await controller.refreshCheckouts()`. | The stored tab set is unchanged (so `onTabsDidChange` does not fire), but `onTabItemsNeedRefresh` fires exactly once because `previousCheckouts != checkouts`. |
| git-client-projects-project-controller-020 | new-checkout-tabs-copy-arrangement-or-blueprint, active-tab-falls-back-to-first | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. After `open()`, add a third worktree on disk, then call `await controller.refreshCheckouts()`. | The new worktree's tab record's `root` equals the existing arrangement copied with fresh node ids (`arrangement.inFreshIDs()`), not `workspace.layout.blueprint()`; `activeTabID` still names whichever tab was active before the refresh. |
| git-client-projects-project-controller-021 | checkouts-from-worktrees | Not present in `ProjectControllerTests.swift`; synthesized from `ProjectController.swift`. Build a `ProjectWorkspace` whose `directoryURL` is a plain directory that has never been a git repository (so `git worktree list --porcelain` there succeeds with empty output); call `await controller.open()`. | `checkouts == [ProjectCheckout(directory: workspace.directoryURL, branch: nil, isMain: true)]`; exactly one `BranchController` is created, for that synthetic checkout. |

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` (parameter to `init`) | `ProjectWorkspace` | none — required | The project this controller reconciles; supplies `gitClient`, `directoryURL`, `storedTabs()`/`persistTabs(...)`, `layout.blueprint()`, and per-directory `gitStatusProvider(forDirectory:)`. |
| `commandRegistry` (parameter to `init`) | `CommandRegistry?` | none — required parameter; `nil` is a valid value | Where branch commands are registered and unregistered. `nil` disables command-palette integration for this project: every `commandRegistry?.register(...)`/`unregister(...)` call becomes a no-op through optional chaining. |
| `onTabsDidChange` | `(() -> Void)?` | `nil` | Caller-set callback fired after a reconcile persists a changed tab set. |
| `onWillChangeTabs` | `(() -> Void)?` | `nil` | Caller-set callback fired immediately before `persistTabs`, in the same main-actor turn. |
| `onTabItemsNeedRefresh` | `(() -> Void)?` | `nil` | Caller-set callback fired when the checkouts changed but the tab plan itself did not. |

`ProjectController.swift` reads no environment variable and no settings key
directly; git executable path, timeout, and submodule handling are
`GitClientConfiguration` concerns reached only indirectly through
`workspace.gitClient`.

## Deep Linking

Not applicable: `ProjectController.swift` defines no URL scheme, route, or
navigation destination.

## Localization

Not applicable: `ProjectController.swift` contains no user-facing string
literal of its own. Every title it hands to `TabItem` or reads from a
`TabRecord` (`checkout.displayName`, `record.title`) is data produced by
`ProjectCheckout` or an already-stored `TabRecord`, not a string this file
composes.

## Accessibility Options

Not applicable: `ProjectController.swift` renders nothing itself — it vends
`TabItem` values (plain titles or hosted view controllers) that
`ComposableTabsWindowController` and `BranchController`'s
`TabPaneViewController` render. Reduce Motion, Increase Contrast, and
Differentiate Without Color are those rendering layers' concern.

## Feature Flags

Not applicable: `ProjectController.swift` contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: `ProjectController.swift` makes no analytics or
event-tracking call.

## Privacy

The only data this file touches is a set of local filesystem paths
(`checkout.directory`, `workspace.directoryURL`) and git branch names, both
already visible to the user in the project window and its tabs. It reads,
stores, or transmits no credential, token, or personal data; it makes no
network call of its own (see Offline or disconnected state above).

## Logging

`ProjectController.swift` makes one logging call of its own, through its
`Loggable` conformance (`ProjectController.swift`): `readCheckouts()`'s
`catch` block, on a failed `gitClient.worktrees(in:)` call
(`ProjectController.swift`). Subsystem defaults to
`Bundle.main.bundleIdentifier`; category is `ProjectController`.

| Event | Level | Message |
|-------|-------|---------|
| `gitClient.worktrees(in:)` threw | error | `readCheckouts: worktrees(in:) failed for <directory>; keeping last checkouts` |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift`,
  built on `AppKit` (indirectly, through `ComposableTabsTabItemDataSource`'s
  `NSViewController`-hosting `TabItem`) and `AgenticToolkitCore`
  (`ProjectWorkspace`, `ProjectCheckout`, `ProjectTabReconciler`, `GitClient`,
  `CommandRegistry`, `Edge`, `TabRecord`, `Loggable`). It uses no SwiftUI API
  of its own; a SwiftUI-hosted window would still need this controller as a
  plain `@MainActor` observable object feeding a tab-bar view, not a
  `View`/`Scene` itself.
- **Compose**: Model `ProjectController` as a plain `@MainActor`-confined
  class (or a class dispatched onto Compose's main-thread dispatcher) holding
  `checkouts: List<ProjectCheckout>` and a `Map<ProjectCheckout,
  BranchController>`, both as `MutableState`/`StateFlow` so a tab-bar
  composable recomposes on change. Replace the chained-`Task` serialization
  (**reconcile-calls-chain-in-order**) with a single-threaded Kotlin
  `Channel`/`Mutex`-guarded coroutine sequence that awaits the previous
  reconcile's `Deferred` before starting the next, preserving call order over
  completion order. Represent `onTabsDidChange`/`onWillChangeTabs`/
  `onTabItemsNeedRefresh` as `SharedFlow<Unit>` emissions or plain lambda
  properties.
- **React/Web**: There is no filesystem worktree on the web, so this
  component has no direct web port; a browser-hosted project switcher backed
  by a server-side git service would model `checkouts`/`branchControllers` as
  component state populated from an API call standing in for
  `gitClient.worktrees(in:)`, serialize the chained-reconcile ordering
  guarantee as a request queue keyed by project id (so an overlapping
  "refresh" request can never let a stale response overwrite a fresher one),
  and represent the three callbacks as ordinary event-emitter events.
- **AppKit / UIKit**: The source already is effectively AppKit (through the
  `ComposableTabsTabItemDataSource`/`TabItem` contract it implements); a
  UIKit (iOS) port would replace `NSViewController`-hosted `TabItem`s with
  `UIViewController`-hosted ones and would need its own worktree-listing
  affordance in place of `git worktree list`, since iOS sandboxing makes
  multiple linked worktrees of one repository an unusual arrangement to
  expose in a mobile UI; the checkout/branch-controller reconciliation logic
  ports unchanged.
- **WinUI 3**: Port `ProjectController` as a plain C# class holding
  `ObservableCollection<ProjectCheckout> Checkouts` and a
  `Dictionary<ProjectCheckout, BranchController> BranchControllers`, with no
  interface requiring thread-affinity of its own — mirror `@MainActor`
  confinement by only ever touching this object from the UI thread
  (`DispatcherQueue`), the same discipline `BranchController`'s WinUI port
  already assumes (see `agentictoolkit://cookbook/macos/features/projects/branch-controller`).
  Reproduce **reconcile-calls-chain-in-order** with a stored `Task`
  (previous reconcile) that the next call `await`s before starting its own
  work — the same continuation-chaining pattern, not a `SemaphoreSlim`, so
  ordering is decided by *when a call arrived* rather than by whichever task
  wins a lock. Represent `onTabsDidChange`, `onWillChangeTabs`, and
  `onTabItemsNeedRefresh` as C# `event Action?` members (or plain
  `Action?` properties, matching the source's own optional-closure shape
  rather than .NET's multicast-delegate convention). Read worktrees with
  `System.Diagnostics.Process` running `git worktree list --porcelain`
  through the same single-door `GitClient` WinUI port
  `agentictoolkit://cookbook/macos/features/projects/branch-controller` describes,
  and reproduce the main-first-then-git-order partition
  (**checkouts-ordered-main-first-then-git-order**) with `Where`/`Concat`
  rather than `OrderBy`, since LINQ's `OrderBy` is stable but a hand-rolled
  comparator equivalent to a two-way `sorted(by:)` would not be.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift` |

## Design Decisions

**Decision**: Overlapping `open()`/`refreshCheckouts()` calls are serialized
by chaining each call's `Task` onto the previous one's, rather than with a
lock, semaphore, or `AsyncStream`.
**Rationale**: The doc comment on `inFlightReconcile` explains the failure
mode this avoids: without chaining, "whichever's git call happens to finish
last win\[s\], even when that is the earlier of the two calls." Chaining
makes the *later caller's* write the one left standing, regardless of which
git subprocess happens to finish first — call order, not completion order,
is the contract (`ProjectController.swift`, verified by
**reconcile-calls-chain-in-order**, vector -014).
**Approved**: pending

**Decision**: `markClosed()` is synchronous; `shutdown()` is `async` and calls
`markClosed()` as its first step rather than setting `isClosed` itself.
**Rationale**: The doc comment on `isClosed` states the reason directly: an
`async` path to setting the flag "costs a main-actor hop," during which "a
reconcile continuation already enqueued ahead of that hop would resume with
the flag still down, pass the guard, and write a dead window's checkouts
into the database." A synchronous `markClosed()`, called from the window's
close handler in the same main-actor turn that drops the controller, closes
that window (`ProjectController.swift`).
**Approved**: pending

**Decision**: `readCheckouts()` orders a non-empty result with
`found.filter(\.isMain) + found.filter { !$0.isMain }` rather than
`found.sorted(by:)`.
**Rationale**: The inline comment gives the reason: `sorted(by:)` "is
documented as not guaranteed stable, so a comparator that only orders
main-before-non-main would not reliably keep the non-main checkouts in git's
own order." Partitioning instead lets git's own order survive within each
half (`ProjectController.swift`).
**Approved**: pending

**Decision**: `onTabsDidChange` and `onTabItemsNeedRefresh` are mutually
exclusive — a reconcile fires at most one of them, never both.
**Rationale**: The doc comment on `reconcile()` states this is deliberate:
"one fires on the path that writes, the other on the path that does not."
Firing `onTabsDidChange` when nothing was actually written would make the
window "throw away a live pane tree, and every shell and file-system watcher
in it, for no reason at all"; firing `onTabItemsNeedRefresh` on the
write path would be redundant work the write path's own rebuild already
covers (`ProjectController.swift`).
**Approved**: pending

**Decision**: `branchController(forDirectory:)` and the tab-item lookup both
resolve symlinks in the directory they are handed before comparing it to a
checkout's stored (already-resolved) `directory`.
**Rationale**: The inline comment states the two routes a directory reaches
this controller by: `git worktree list` reports a fully resolved path, while
a caller's own `directory` may be "whatever a caller had lying around."
Comparing without resolving both sides would turn a real match into a miss
(`ProjectController.swift`; see
`ProjectCheckout.swift` for the same rule applied to storage).
**Approved**: pending

**Decision**: `syncBranchControllers()` reuses an existing `BranchController`
by matching on the checkout's `directory` alone, not on the whole
`ProjectCheckout` (which also hashes on `branch`).
**Rationale**: The inline comment explains why: "a checkout that switched
branch must still find its controller." Matching on the full value type
would treat a branch switch as a different checkout, discarding and
rebuilding the `BranchController` — and its live `GitStatusProvider`
subscription — on every branch change (`ProjectController.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | partial | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |

Notes: separation-of-concerns passes because `ProjectController` owns exactly
the checkout list, the branch-controller lifecycle, and the tab-reconciliation
call sequence, while delegating every git read to `GitClient` through
`workspace.gitClient`, all tab-plan arithmetic to `ProjectTabReconciler`, all
persistence to `ProjectWorkspace`, and all rendering to `BranchController`'s
panes — per its own doc comment, it "knows nothing about views beyond vending
what a branch controller makes." unit-test-coverage is partial because
`ProjectControllerTests.swift` exercises the open/refresh serialization
ordering under a deliberately racing fake git executable, an unchanged
refresh's no-op path, a removed worktree dropping its tab and commands, tab
vending for both hosted and stray records, single- and multi-window command
registration and teardown, symlink-resolving lookup, and a transient git
failure preserving the last known checkouts — but has no test for a close
landing mid-`readCheckouts()` (**branch-refresh-close-race**
is one instance of this gap), for `shutdown()`'s own effect, for the
onTabItemsNeedRefresh-only path (checkouts changing without the tab plan
changing), or for the arrangement-copying branch of
**new-checkout-tabs-copy-arrangement-or-blueprint** (vectors -016, -018,
-019, and -020 above are synthesized to describe what such tests would
assert). explicit-error-handling is partial because `readCheckouts()`'s
`catch` does log the failure (unlike some sibling collaborators' silent
catches) but still answers with stale data without any signal a caller can
distinguish from a successful read that happened to see no change, and
because `reconcile()` cannot detect a swallowed `persistTabs` failure at all
(**persist-failure-signal**). graceful-degradation passes
because a failed git read keeps the last known checkouts and branch
controllers rather than collapsing the window to a single fallback tab.
error-recovery is partial because `ProjectController` performs no retry or
backoff of its own after a failed git read — recovery depends entirely on
some caller invoking `refreshCheckouts()` again. main-thread-freedom passes
because every git call and every branch-controller refresh reaches this
controller through `await`, an async suspension point that releases the main
actor while the subprocess runs.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
