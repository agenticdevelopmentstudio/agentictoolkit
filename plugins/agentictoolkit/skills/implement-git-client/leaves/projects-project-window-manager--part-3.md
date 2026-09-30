<!-- leaf: implement-git-client/projects-project-window-manager--part-3 · source: git-client-projects-project-window-manager.md -->

# ProjectWindowManager — continued (part 3)

**Rules** (cite as `implement-git-client/projects-project-window-manager--part-3#<slug>`):

- `close-drops-controller-and-reregisters-survivors` MUST
- `close-captures-teardown-target-before-removing-it` MUST
- `close-observer-uses-nil-queue` MUST
- `close-fires-on-project-closed-before-removal` MUST
- `close-teardown-added-to-shared-registry` MUST

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
  `agentictoolkit://recipes/git-client-projects-project-controller`). Reproduce
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
  settings store `agentictoolkit://recipes/git-client-projects-project-database`
  describes, using `HttpClient`/`System.Text.Json`/`Task`/`async` and
  `Windows.Storage` only where a networked or file-based collaborator this
  manager delegates to (git, language servers) needs them — this type itself
  makes no HTTP call and reads no `Windows.Storage` file directly.

