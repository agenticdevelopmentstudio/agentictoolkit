---
id: 5bfadad5-c93b-432a-807e-04be57ff16b4
title: Project Management
domain: agentictoolkit://cookbook/workspace/projects/project-controller
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Owns a project's checkouts and their branch controllers, reconciles them
  against stored tabs, and answers the window's tab-item and command-registration requests.
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
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/branch-controller
- agentictoolkit://cookbook/ui/layout/composable-tabs/tabs-window
- agentictoolkit://cookbook/ui/layout/tabbed-view/tab-pane
- agentictoolkit://cookbook/workspace/files/git-status-provider
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

# Project Management

## Overview

The project controller is the one-per-project-window owner of a project's
checkouts and their branch controllers. It decides which tabs the window
shows by reconciling the checkouts git reports against the tabs the
project's stored workspace state holds, and it answers the window's
tab-item requests as the project's tab-item data source. Per its own design
rationale, it "knows nothing about views beyond vending what a branch
controller makes." It serializes its own two entry points (opening, and
refreshing checkouts) onto one chained operation so two overlapping callers
cannot let a slower, earlier git read overwrite a faster, later one, and it
keeps a project's branch-scoped commands registered with the app's command
registry in step with which checkouts currently exist.

## Behavioral Requirements

- **state-surface**: The project controller MUST expose its live state as a
  `checkouts` list and a `branchControllers` map from checkout to branch
  controller, both read-only from outside, as the only project-owned
  collections it maintains.
- **tab-item-data-source-conformance**: The project controller MUST be the
  one that answers every tab-item request itself, rather than delegating
  that responsibility to the workspace or to a branch controller.
- **required-workspace-optional-registry**: Constructing a project
  controller MUST accept a workspace as a required parameter with no
  default value, and a command registry as a required parameter (also with
  no default) whose value MAY be absent.
- **derived-git-client**: The git client MUST be computed from the
  workspace on every access rather than stored or constructed
  independently, so this controller and every branch controller it creates
  read git through the one client the workspace was given.
- **open-runs-serialized-reconcile**: Opening the project MUST run the
  serialized reconcile operation and MUST NOT itself perform any git read,
  checkout assignment, or tab persistence.
- **refresh-checkouts-runs-serialized-reconcile**: Refreshing checkouts
  MUST run the serialized reconcile operation, the same entry point opening
  uses.
- **reconcile-calls-chain-in-order**: The serialized reconcile operation
  MUST capture whatever reconcile is currently in flight, start a new one
  that awaits the in-flight one's completion before doing any work of its
  own, record itself as the new in-flight reconcile, and await its own
  completion — so two overlapping calls to opening or refreshing checkouts
  always run their reconciles in the order they were called, never in the
  order their own git reads happen to finish.
- **close-guard-brackets-reconcile-and-refresh**: The serialized reconcile
  operation MUST check the closed flag immediately before reconciling and
  again immediately after it returns, skipping reconciling entirely on the
  first check's failure and skipping the branch-controller refresh loop
  entirely on the second's.
- **branch-controllers-refreshed-after-reconcile**: When both close checks
  pass, the serialized reconcile operation MUST refresh every branch
  controller currently held.
- **mark-closed-is-synchronous-and-final**: Marking the project closed MUST
  take effect immediately, within the same step as the call that reaches
  it — not deferred to a later asynchronous continuation — setting the
  closed flag and unregistering every current branch controller's commands.
- **shutdown-closes-then-stops-language-services**: Shutting down MUST
  mark the project closed and then stop the workspace's language services,
  in that order.
- **reregister-commands-guard**: Reregistering commands MUST return
  immediately, registering nothing, when the project is closed or when
  there is no command registry.
- **reregister-commands-fills-only-gaps**: When that guard passes,
  reregistering commands MUST register, with the command registry, every
  command of every current branch controller whose id is not already
  registered, and MUST leave every already-registered id untouched.
- **branch-controller-lookup-resolves-symlinks**: Looking up a branch
  controller by directory MUST resolve symlinks in the given directory
  before comparing it against the branch controllers' key directories, and
  MUST return the first match by directory equality.
- **reconcile-aborts-after-a-late-close**: Reconciling MUST read the
  current checkouts and then, before mutating the checkout list, the
  branch-controller map, or persisting tabs, MUST return immediately if the
  project has become closed during that read.
- **reconcile-commits-fresh-checkouts**: Once past that guard, reconciling
  MUST assign the freshly read checkouts to the checkout list and MUST
  synchronize the branch controllers before computing a tab plan.
- **tab-plan-via-reconciler**: Reconciling MUST compute its plan from the
  stored tabs (or an empty list when none are stored), the just-assigned
  checkouts, and the project's directory.
- **unchanged-plan-writes-nothing**: When tabs were already stored and the
  plan is unchanged, reconciling MUST NOT persist tabs, MUST NOT signal
  that tabs are about to change, and MUST NOT signal that tabs changed.
- **unchanged-plan-still-signals-checkout-change**: On that same
  unchanged-plan path, reconciling MUST signal that tab items need
  refreshing if and only if the checkout list actually changed from
  before, and MUST NOT signal it otherwise.
- **changed-plan-writes-and-signals-in-order**: When no tabs were stored,
  or the plan is not unchanged, reconciling MUST signal that tabs are
  about to change, then persist the new tabs, then signal that tabs
  changed, in that order.
- **default-enabled-edge**: Reconciling MUST use the previously stored
  enabled edges, or the single top edge when nothing was stored, as the
  enabled-edges list for any newly built tab record.
- **new-checkout-tabs-copy-arrangement-or-blueprint**: For every checkout
  being added, reconciling MUST build its tab records from a blueprint that
  reuses the existing tab arrangement (with fresh identifiers) when one can
  be derived from the tabs being kept, and MUST otherwise fall back to the
  project's default layout blueprint.
- **active-tab-falls-back-to-first**: Reconciling MUST set the active tab
  to the tab whose id equals the previously stored active tab id, and MUST
  fall back to the first tab in the list when no tab matches.
- **checkouts-from-worktrees**: On a successful read of the repository's
  worktrees, reading checkouts MUST convert the result into checkout
  values — which excludes every bare worktree entry — and MUST return a
  single synthetic checkout for the project's own directory, with no
  branch and marked as main, when that conversion yields zero checkouts.
- **checkouts-ordered-main-first-then-git-order**: Reading checkouts MUST
  order a non-empty result as every main checkout followed by every
  non-main checkout, each half preserving the order the worktree read
  returned it in, and MUST use a stability-preserving partition rather
  than a general-purpose sort to do so, since a general sort is not
  guaranteed to preserve the original relative order of equal elements.
- **worktree-read-failure-keeps-last-known**: When reading the
  repository's worktrees fails, reading checkouts MUST log the failure —
  naming the directory but never the git output — and MUST return the
  previous checkout list unchanged when it is non-empty, or the single
  synthetic checkout described in **checkouts-from-worktrees** when it is
  empty.
- **branch-controllers-reused-by-directory**: Synchronizing branch
  controllers MUST reuse an existing branch controller for any checkout
  whose directory matches an existing entry's key directory, even when the
  checkout's branch differs from that key.
- **branch-controllers-created-with-injected-collaborators**: For a
  checkout with no existing controller, synchronizing branch controllers
  MUST construct a new branch controller with this controller's own git
  client and with the workspace's status provider for that checkout's
  directory, and MUST register every one of that new controller's commands
  with the command registry.
- **branch-controllers-dropped-with-their-commands**: Synchronizing branch
  controllers MUST unregister the commands of every existing branch
  controller whose checkout directory is absent from the new checkout set,
  before replacing the branch-controller map with the newly built one.
- **unregister-mirrors-register**: Unregistering a branch controller's
  commands MUST unregister exactly the ids in that controller's current
  command set, no more and no fewer.
- **tab-item-resolves-directory-then-branch-controller**: Answering a
  tab-item request MUST resolve the tab record's working directory
  (falling back to the project's own directory when the record has none)
  with symlinks resolved, MUST return a plain title when no branch
  controller is found for it, and MUST otherwise return a hosted pane from
  that branch controller.
- **persist-failure-signal**: Persisting tabs catches a save failure, logs
  it, and returns nothing; reconciling signals that tabs changed
  unconditionally right after that call, so the window is told a new tab
  set was written even when the underlying write failed — the failure
  reaches only the log.
- **branch-refresh-close-race**: The serialized reconcile operation's
  per-branch-controller refresh loop does not re-check the closed flag
  between iterations, so marking the project closed partway through that
  loop lets it keep running a branch controller's refresh — and its git
  subprocess — for a controller whose commands were already unregistered;
  the extra refresh has no remaining observer.

## Appearance

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component.

## States

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component. Its runtime state machines — the
current checkout list and branch-controller map snapshot and the
closed-lifecycle flag — are covered under Behavioral Requirements
(**reconcile-commits-fresh-checkouts**,
**mark-closed-is-synchronous-and-final**), not here.

## Accessibility

Not applicable — this is a project window's checkout-and-tab-reconciling
controller, not a visual component. The accessibility of the panes and menu
items it causes to exist is the concern of the branch controller's tab
pane and the window's own tab bar, neither of which this file renders
itself.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-controller-001 | state-surface, required-workspace-optional-registry, checkouts-ordered-main-first-then-git-order, changed-plan-writes-and-signals-in-order, new-checkout-tabs-copy-arrangement-or-blueprint, branch-controllers-created-with-injected-collaborators, default-enabled-edge, active-tab-falls-back-to-first | Build a project controller with no command registry over a fixture with a `main` checkout and a `feature` worktree; open the project. | The checkout list's display names are `["main", "feature"]`; their main flags are `[true, false]`; two branch controllers exist; the stored tabs have 2 distinct group ids, titles `["main", "feature"]`, and working directories `[repoRoot, worktreeRoot]`. |
| git-client-projects-project-controller-002 | unchanged-plan-writes-nothing | Open a first project controller, then build a second one over the same workspace and open it too. | The stored tabs' ids after the second open equal the ids recorded after the first. |
| git-client-projects-project-controller-003 | unchanged-plan-writes-nothing, unchanged-plan-still-signals-checkout-change, branch-controllers-reused-by-directory | Open a project controller; record its main checkout's branch controller; set a listener for the tabs-changed signal; refresh checkouts with nothing changed on disk. | Stored tab ids are unchanged; the tabs-changed signal fires zero times; the main checkout's branch controller after the refresh is the identical instance recorded before it. |
| git-client-projects-project-controller-004 | changed-plan-writes-and-signals-in-order, branch-controllers-dropped-with-their-commands, tab-plan-via-reconciler | Open a project controller, set a listener for the tabs-changed signal, remove the `feature` worktree on disk (`git worktree remove --force`), then refresh checkouts. | The checkout list's display names are `["main"]`; the stored tabs' titles equal `["main"]`; the tabs-changed signal fires once. Whether the about-to-change signal fired is not asserted by this test, but persisting the new tabs is observably complete (the new stored tabs are readable) before the tabs-changed signal fires, consistent with the documented call order. |
| git-client-projects-project-controller-005 | tab-item-data-source-conformance, tab-item-resolves-directory-then-branch-controller | After opening, request a tab item for the left edge for the stored `main` tab record, and again for a stray tab record whose working directory is an unrelated path. | The `main` request returns a hosted pane titled "main"; the stray-record request returns a plain title of "notes". |
| git-client-projects-project-controller-006 | branch-controllers-created-with-injected-collaborators, required-workspace-optional-registry | Build a project controller with a real command registry and open it on the two-checkout fixture. | Exactly 6 branch-action commands are registered (2 checkouts times 3 commands each). |
| git-client-projects-project-controller-007 | branch-controllers-dropped-with-their-commands, unregister-mirrors-register | With a registry-backed project controller open, remove the `feature` worktree on disk and refresh checkouts. | No registered command id is suffixed by the removed checkout's identifier; the remaining branch-action command count is 3. |
| git-client-projects-project-controller-008 | mark-closed-is-synchronous-and-final | Open a registry-backed project controller, then mark it closed. | No branch-action commands remain registered. |
| git-client-projects-project-controller-009 | reregister-commands-fills-only-gaps, mark-closed-is-synchronous-and-final | Two project controllers share one command registry over the same repository; both open; the first is marked closed; then the second reregisters its commands. | After both open, 6 branch-action commands are registered; after the first is marked closed, 0 remain; after the second reregisters, 6 are registered again. |
| git-client-projects-project-controller-010 | reregister-commands-guard | Open a registry-backed project controller, mark it closed, then reregister its commands. | No branch-action commands are registered. |
| git-client-projects-project-controller-011 | branch-controllers-created-with-injected-collaborators | Request the workspace's status provider for the repository's root directory before opening the project controller, then open it, then look up the branch controller for that same directory and read its status provider. | The `main` and `feature` status providers are distinct; the provider requested before opening is the identical instance the resulting branch controller holds. |
| git-client-projects-project-controller-012 | branch-controller-lookup-resolves-symlinks | After opening, look up the branch controller for the repository's root directory, and again for a symlink pointing at that same directory. | Both lookups return the identical branch controller instance. |
| git-client-projects-project-controller-013 | worktree-read-failure-keeps-last-known, derived-git-client | Open a project controller whose git client reads its configuration from a flippable source; flip that configuration to a nonexistent executable path; refresh checkouts. | The checkout list's display names are still `["main", "feature"]`; two branch controllers still exist; the stored tab ids are unchanged from before the flip — proving the injected git client, reached only through the workspace, is what actually governs the read. |
| git-client-projects-project-controller-014 | reconcile-calls-chain-in-order, close-guard-brackets-reconcile-and-refresh | Using a fake git executable whose first worktree-listing call answers slowly with a stale single-checkout result and every later call answers immediately with the fresh two-checkout result: start opening, wait for proof its git call began, then start refreshing checkouts concurrently, and await both. | The checkout list's display names are `["main", "feature"]` and the stored tabs' titles equal `["main", "feature"]` — the later, fresher call's write is the one left standing, regardless of which git process happened to finish first. |
| git-client-projects-project-controller-016 | reconcile-aborts-after-a-late-close, close-guard-brackets-reconcile-and-refresh | Not present in the test suite; synthesized from the implementation. Start opening the project; while its checkout-read is still pending, mark the project closed; let the open complete. | The checkout list, branch-controller map, and the workspace's stored tabs are left exactly as they were before opening; neither the about-to-change nor the tabs-changed signal fires. |
| git-client-projects-project-controller-017 | branch-controllers-refreshed-after-reconcile | Not present in the test suite; synthesized from the implementation (compare the branch controller's own refresh test, which exercises that refresh in isolation). Rename the `feature` worktree's branch on disk (`git checkout -b renamed`), then refresh checkouts. | Looking up the branch controller for the worktree's directory and reading its current branch returns "renamed", proving the per-branch-controller refresh loop ran even though the checkout list's shape did not change. |
| git-client-projects-project-controller-018 | shutdown-closes-then-stops-language-services | Not present in the test suite; synthesized from the implementation. Build a workspace whose language services are a test double recording shutdown calls; build a project controller over it; shut it down. | The project reports itself closed; the branch commands are unregistered exactly as marking it closed alone would leave them; the language-services double records exactly one shutdown call. |
| git-client-projects-project-controller-019 | unchanged-plan-still-signals-checkout-change | Not present in the test suite; synthesized from the implementation. After opening, set a listener for the tab-items-need-refresh signal; rename the `feature` worktree's branch on disk without adding or removing a worktree; refresh checkouts. | The stored tab set is unchanged (so the tabs-changed signal does not fire), but the tab-items-need-refresh signal fires exactly once because the checkout list actually changed. |
| git-client-projects-project-controller-020 | new-checkout-tabs-copy-arrangement-or-blueprint, active-tab-falls-back-to-first | Not present in the test suite; synthesized from the implementation. After opening, add a third worktree on disk, then refresh checkouts. | The new worktree's tab record reuses the existing tab arrangement with fresh identifiers, not the project's default layout blueprint; the active tab still names whichever tab was active before the refresh. |
| git-client-projects-project-controller-021 | checkouts-from-worktrees | Not present in the test suite; synthesized from the implementation. Build a workspace whose directory is a plain directory that has never been a git repository (so listing its worktrees succeeds with empty output); open the project controller. | The checkout list holds exactly one synthetic checkout for the workspace's own directory, with no branch and marked as main; exactly one branch controller is created, for that synthetic checkout. |

## Edge Cases

- **Null and empty input**: A successful worktree read that reports zero
  non-bare worktrees MUST fall back to the single synthetic main checkout
  at the project's own directory (**checkouts-from-worktrees**; see vector
  -021). A project with no stored tabs at all MUST always take the
  "changed" persistence path, because having no stored tabs short-circuits
  the unchanged-plan guard regardless of what the plan itself says (MUST).
- **Boundary values**: The checkout list may hold exactly one entry (a
  repository with no linked worktrees) or many; the loops over checkouts
  being added and over held branch controllers run zero, one, or many
  times with no special case for either end (MUST). The enabled edges
  default to the single top edge (**default-enabled-edge**) when nothing
  was stored, so a project's very first reconcile always creates exactly
  one tab per checkout rather than one per available edge.
- **Concurrent access**: Opening and refreshing checkouts MUST be safe to
  call concurrently because the serialized reconcile operation chains each
  call onto whatever reconcile is already running, so two overlapping
  calls' git reads and database writes land in call order rather than
  completion order (**reconcile-calls-chain-in-order**; see vector -014).
  Every mutation of the checkout list, the branch-controller map, and the
  closed flag is confined to a single execution context (see Platform
  Notes), so no interleaving can observe a torn write. The one place
  serialization does not fully cover is **branch-refresh-close-race**: the
  per-branch-controller refresh loop inside the serialized reconcile
  operation does not re-check the closed flag between iterations.
- **Error states**: A worktree-read failure (whether from a missing
  executable, a launch failure, a timeout, or a failed command) is not
  distinguished by reading checkouts — every case is caught by one
  unqualified handler, logged once without the git output, and answered
  with the last known checkouts or the synthetic fallback
  (**worktree-read-failure-keeps-last-known**, MUST). A failure inside
  persisting tabs is logged there and not detected by this file; see
  **persist-failure-signal**.
- **Offline or disconnected state**: Not applicable in the network sense —
  reading worktrees runs `git worktree list --porcelain` against the local
  working tree only; it makes no request to a remote. An unreadable or
  removed project directory is handled identically to any other
  worktree-read failure above.
- **Cancellation and timeouts**: The serialized reconcile operation awaits
  its internal operation to completion rather than racing it against a
  timeout of its own; a timeout failure reaches reading checkouts through
  the same generic handling as every other error (see Error states above).
  Neither opening nor refreshing checkouts checks for cooperative
  cancellation on its own; the calling context's own cancellation is the
  only cancellation path that reaches this controller (MUST, by absence).
- **Missing file or unreachable server**: A checkout directory removed out
  from under the project (a worktree removal racing a pending reconcile)
  is not distinguished from any other git failure inside reading
  checkouts; synchronizing branch controllers drops that checkout's branch
  controller and unregisters its commands on the *next* successful
  reconcile, not immediately (**branch-controllers-dropped-with-their-commands**;
  see vectors -004, -007).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` (construction parameter) | workspace reference | none — required | The project this controller reconciles; supplies the git client, the project directory, stored/persisted tabs, the default layout blueprint, and a per-directory status provider. |
| `commandRegistry` (construction parameter) | command-registry reference, optional | none — required parameter; may be absent | Where branch commands are registered and unregistered. Absent disables command-palette integration for this project: every register/unregister call becomes a no-op. |
| `onTabsDidChange` | callback, optional | absent | Caller-set callback fired after a reconcile persists a changed tab set. |
| `onWillChangeTabs` | callback, optional | absent | Caller-set callback fired immediately before persisting tabs, in the same execution step. |
| `onTabItemsNeedRefresh` | callback, optional | absent | Caller-set callback fired when the checkouts changed but the tab plan itself did not. |

This controller reads no environment variable and no settings key
directly; the git executable path, timeout, and submodule handling are the
git client's own configuration concern, reached only indirectly through
the workspace.

## Deep Linking

Not applicable: this controller defines no URL scheme, route, or
navigation destination.

## Localization

Not applicable: this controller contains no user-facing string literal of
its own. Every title it hands to a tab item or reads from a stored tab
record (a checkout's display name, a record's title) is data produced
elsewhere, not a string this file composes.

## Accessibility Options

Not applicable: this controller renders nothing itself — it vends
tab-item values (plain titles or hosted panes) that the window and the
branch controller's own pane rendering render. Reduce Motion, Increase
Contrast, and Differentiate Without Color are those rendering layers'
concern.

## Feature Flags

Not applicable: this controller contains no feature-flag or
build-configuration check.

## Analytics

Not applicable: this controller makes no analytics or event-tracking call.

## Privacy

The only data this file touches is a set of local filesystem paths (a
checkout's directory, the project's own directory) and git branch names,
both already visible to the user in the project window and its tabs. It
reads, stores, or transmits no credential, token, or personal data; it
makes no network call of its own (see Offline or disconnected state
above).

## Logging

This controller makes one logging call of its own: reading checkouts'
failure handler, on a failed worktree read. The logging category is the
project controller's own name.

| Event | Level | Message |
|-------|-------|---------|
| Worktree read failed | error | `Failed to read worktrees for <directory>; keeping last checkouts` |

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift`,
  built on `AppKit` (indirectly, through `ComposableTabsTabItemDataSource`'s
  `NSViewController`-hosting `TabItem`) and `AgenticToolkitCore`
  (`ProjectWorkspace`, `ProjectCheckout`, `ProjectTabReconciler`, `GitClient`,
  `CommandRegistry`, `Edge`, `TabRecord`, `Loggable`). It uses no SwiftUI API
  of its own; a SwiftUI-hosted window would still need this controller as a
  plain `@MainActor` observable object feeding a tab-bar view, not a
  `View`/`Scene` itself. Conformance to `ComposableTabsTabItemDataSource` is
  how **tab-item-data-source-conformance** is implemented: this type
  answers `composableTabsWindowController(_:tabItemFor:on:)` directly
  rather than delegating it, and that protocol's `TabItem` return type is
  what makes **tab-item-resolves-directory-then-branch-controller**'s
  `.title`/`.viewController` cases concrete. `ProjectController` is
  declared `@MainActor` and holds no `Sendable` conformance of its own —
  every property and method is confined to the main actor by that
  declaration alone. A `SWIFT_STRICT_CONCURRENCY: complete` build enforces
  this at compile time: attempting to call `open()` or read `checkouts`
  from a `nonisolated` context with no `await` and no `@MainActor` hop
  fails to compile, so there is no runtime path that reaches this type off
  the main actor — the guarantee is verified at build time, not by a
  runtime test.
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
  already assumes (see `agentictoolkit://cookbook/workspace/projects/branch-controller`).
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
  `agentictoolkit://cookbook/workspace/projects/branch-controller` describes,
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
