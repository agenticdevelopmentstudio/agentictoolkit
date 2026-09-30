<!-- leaf: implement-git-client/projects-project-controller--part-3 · source: git-client-projects-project-controller.md -->

# ProjectController — continued (part 3)

- **branch-refresh-close-race**: `serializedReconcile()`'s `for controller in self.branchControllers.values { await controller.refresh() }` (`ProjectController.swift`) does not re-check `isClosed` between iterations, so a `markClosed()` call landing between two of those awaits lets the loop keep running `BranchController.refresh()` — and its git subprocess — for a controller whose commands were already unregistered; the extra refresh has no remaining observer.
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

## Privacy

The only data this file touches is a set of local filesystem paths
(`checkout.directory`, `workspace.directoryURL`) and git branch names, both
already visible to the user in the project window and its tabs. It reads,
stores, or transmits no credential, token, or personal data; it makes no
network call of its own (see Offline or disconnected state above).

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
  already assumes (see `agentictoolkit://recipes/git-client-projects-branch-controller`).
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
  `agentictoolkit://recipes/git-client-projects-branch-controller` describes,
  and reproduce the main-first-then-git-order partition
  (**checkouts-ordered-main-first-then-git-order**) with `Where`/`Concat`
  rather than `OrderBy`, since LINQ's `OrderBy` is stable but a hand-rolled
  comparator equivalent to a two-way `sorted(by:)` would not be.

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
