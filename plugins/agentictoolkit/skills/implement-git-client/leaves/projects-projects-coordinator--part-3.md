<!-- leaf: implement-git-client/projects-projects-coordinator--part-3 · source: git-client-projects-projects-coordinator.md -->

# ProjectsCoordinator — continued (part 3)

- **finish-scan-updates-no-decrement-on-failure**: For each repo in `plan.updates`, `finishScan` calls `database.update(repo)` and on failure logs the error with `repo.path` at `privacy: .public`, as the insert and delete loops do, but unlike those loops it does not decrement any `summary` count. A failed update therefore leaves `summary.moved`/`summary.unchanged` (whichever `ProjectReconciler.plan` attributed the row to) overstated, despite the function's own comment that "the summary and what the user was told disagree" is the bug its per-row error handling fixes; the failure is visible only in the log.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `database` (parameter to `init`) | `ProjectDatabase` | none — required | The store `repos` is loaded from and that `finishScan`/`rename`/`openProject` write to. |
| `scanner` (parameter to `init`) | `GitRepoScanner?` | `nil` | Injected scanner for a test or a caller wanting a particular walk; when `nil`, `scan(...)` builds its own scanner from the current setting on every call. |
| `opener` (parameter to `init`) | `ProjectOpening?` | `nil` | Weakly held window-opening delegate; also settable afterward through `setOpener(_:)`. |
| `commandRegistry` (parameter to `init`, labeled `registry`) | `CommandRegistry` | none — required, no default | Where `CommandID.openProject`/`CommandID.scanForProjects` are registered at `init` time (see **command-registry-required**). |
| `UserSettings.projectScanSkipPatterns` | `UserSetting<[String]>` | `GitRepoScanner.defaultRootSkipPatterns` | Read fresh at the start of every `scan(...)` call that has no injected scanner, so an edited skip list takes effect on the next scan without relaunching. |
| `showingProgress` (parameter to `scan`) | `Bool` | `true` | Whether `scan(...)` presents a `ProjectScanProgressWindow` for the duration of the walk. |

## Localization

`ProjectsCoordinator.swift` contains four hardcoded English string
literals: the command titles `"Open Project…"` and `"Scan for Projects"`
(also reused as the two menu-item titles), and the shared category
`"Projects"` used by both `AppCommand` registrations. None is routed
through `NSLocalizedString`, a String Catalog, or any other localization
mechanism in this file.

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
  `agentictoolkit://recipes/git-client-projects-project-database`'s WinUI
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
