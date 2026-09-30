<!-- leaf: implement-git-client/projects-project-controller--part-2 · source: git-client-projects-project-controller.md -->

# ProjectController — continued (part 2)

**Rules** (cite as `implement-git-client/projects-project-controller--part-2#<slug>`):

- `state-surface` MUST
- `tab-item-data-source-conformance` MUST
- `main-actor-isolation` MUST
- `required-workspace-optional-registry` MUST
- `derived-git-client` MUST
- `open-runs-serialized-reconcile` MUST
- `refresh-checkouts-runs-serialized-reconcile` MUST
- `reconcile-calls-chain-in-order` MUST
- `close-guard-brackets-reconcile-and-refresh` MUST
- `branch-controllers-refreshed-after-reconcile` MUST
- `mark-closed-is-synchronous-and-final` MUST
- `shutdown-closes-then-stops-language-services` MUST
- `reregister-commands-guard` MUST
- `reregister-commands-fills-only-gaps` MUST
- `branch-controller-lookup-resolves-symlinks` MUST
- `reconcile-aborts-after-a-late-close` MUST
- `reconcile-commits-fresh-checkouts` MUST
- `tab-plan-via-reconciler` MUST
- `unchanged-plan-writes-nothing` MUST
- `unchanged-plan-still-signals-checkout-change` MUST
- `changed-plan-writes-and-signals-in-order` MUST
- `default-enabled-edge` MUST
- `new-checkout-tabs-copy-arrangement-or-blueprint` MUST
- `active-tab-falls-back-to-first` MUST
- `checkouts-from-worktrees` MUST
- `checkouts-ordered-main-first-then-git-order` MUST
- `worktree-read-failure-keeps-last-known` MUST
- `branch-controllers-reused-by-directory` MUST
- `branch-controllers-created-with-injected-collaborators` MUST
- `branch-controllers-dropped-with-their-commands` MUST
- `unregister-mirrors-register` MUST
- `tab-item-resolves-directory-then-branch-controller` MUST

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
