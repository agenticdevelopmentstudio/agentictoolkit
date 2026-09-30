<!-- leaf: implement-file-system/file-browser--part-2 · source: file-system-file-browser.md -->

# File System File Browser — continued (part 2)

**Rules** (cite as `implement-file-system/file-browser--part-2#<slug>`):

- `main-actor-isolation-across-all-three-types` MUST

### Concurrency and isolation

- **main-actor-isolation-across-all-three-types**: `FileBrowserDirectories`,
  `FileBrowserRestorationState`, and `FileTreeManager` are each declared
  `@MainActor` and `public`, with no `Sendable` conformance of their own; per
  Swift's actor-isolation rules this means every property read, mutation, and
  method call on any of the three MUST occur on the main actor, and none of
  the three MAY be passed across an isolation boundary without first hopping
  to the main actor.
- **git-status-may-be-dropped-before-first-sync**: NEEDS REVIEW: Not implemented in source. `loadInitial()` starts `coordinator.fullSync()` and `refreshGitStatus()` independently, and `apply(_:)` silently discards a `.status(_:)` result that arrives while `rootNode` is still `nil` (`apply-requires-root-node`); nothing caches that discarded result or re-applies it once `rootNode` is later set, so if the git status broadcast resolves before the coordinator's first full sync publishes a tree, the freshly drawn tree shows no git-status badges until the next FS-triggered debounce or an explicit `refreshGitStatus()` call. This would be settled by caching the most recent `GitStatusRefreshResult` and re-applying it whenever `rootNode` changes from `nil` to non-`nil`, or by confirming with the author that some other ordering guarantee makes this unreachable in practice.
- **overlapping-directory-syncs-race**: NEEDS REVIEW: Not implemented in source. `DirectoryWatchCoordinator.fullSync()` has no reentrancy guard (unlike `IDEDetector.detect()`'s `guard !isDetecting`), so calling `updateIgnorePatterns(_:)` — or a second `loadInitial()` — while an earlier `fullSync()` is still reading the directory in the background starts a second, overlapping read; each read captures its own `ignorePatterns` snapshot at call time and merges its result into `rootNode` on completion, so whichever call's background read finishes last wins, with no signal to the caller when that is not the most recently requested one. This would be settled by giving each `fullSync()`/`handleChanges()` run a sequence number and discarding a stale run's merge, or by confirming with the author that these two methods are never called close enough together in practice for the order to matter.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `primary` | `URL` | required (no default) | `FileBrowserDirectories`' always-shown root; resolved via `resolvingSymlinksInPath()`. |
| `additional` | `[URL]` | `[]` | `FileBrowserDirectories`' extra roots the user has added, normalized on construction. |
| `FileBrowserDirectories.onChange` | `(([URL]) -> Void)?` | `nil` | Closure a host supplies to persist `additional` whenever `add`/`remove` change it. |
| `expandedPaths` | `[String]` | `[]` | `FileBrowserRestorationState`'s initial set of disclosed directory paths. |
| `selectedPath` | `String?` | `nil` | `FileBrowserRestorationState`'s initial selected file path. |
| `FileBrowserRestorationState.onChange` | `((_ expandedPaths: [String], _ selectedPath: String?) -> Void)?` | `nil` | Closure a host supplies to persist expanded/selected state whenever either changes. |
| `repoRootURL` | `URL` | required (no default) | `FileTreeManager`'s root directory to scan and watch. |
| `packageURL` | `URL` | required (no default) | Path excluded from filesystem watching alongside `.git` (e.g. a build output directory). |
| `config` | `FileTreeConfig` | required (no default) | Package-extension/display-name/`UserDefaults`-key configuration passed through to the scan. |
| `ignorePatterns` | `[String]` | `[]` | Wildcard filename patterns excluded from the scan; also settable later via `updateIgnorePatterns(_:)`. |
| `gitStatusProvider` | `GitStatusProvider?` | `nil` | Injected provider to share across managers/panes of the same checkout; a manager scoped to `repoRootURL` is built when omitted. |

## Platform Notes

- **SwiftUI**: All three types are already Combine `ObservableObject`s with
  `@Published` properties — the same reactive primitive SwiftUI's own state
  containers use — so a SwiftUI host can drive any of them directly with
  `@StateObject`/`@ObservedObject` and no adaptation layer; nothing in these
  three files is AppKit-specific despite currently being consumed only by
  AppKit view controllers (see `file-browser-view-controller`,
  `file-tree-outline-view-controller`).
- **Compose**: Model each type as a Kotlin `ViewModel` exposing
  `StateFlow`/`MutableStateFlow` in place of `@Published` — `additional`,
  `expandedPaths`/`selectedPath`, and `rootNode`/`isSyncing` respectively —
  and replace each `onChange` closure with a `SharedFlow<T>` a host collects,
  or a repository interface the `ViewModel` calls directly instead of
  invoking a closure.
- **React/Web**: Port `FileBrowserDirectories`' add/remove/normalize logic as
  a small store (a Zustand/Redux slice or a hand-rolled event emitter) rather
  than a class with mutable fields; back `FileBrowserRestorationState` with
  the same store pattern, writing to `localStorage`/IndexedDB from the same
  "only report when it actually changed" callback this recipe requires;
  `FileTreeManager`'s two debounces map directly onto `setTimeout`/
  `clearTimeout` with the same 500ms/2000ms delays.
- **AppKit / UIKit**: This is the source platform (the `AgenticToolkitMacOS`
  module), but that placement is a module-organization fact, not a technical
  one: none of `FileBrowserDirectories.swift`, `FileBrowserRestorationState.swift`,
  or `FileTreeManager.swift` imports AppKit. Porting these three types to
  iOS/UIKit needs no logic change to them directly; what would need
  replacing lives one layer down, in `DirectoryWatchCoordinator`'s
  `FileSystemWatcher` (FSEvents is macOS-only) and in `IDEDetector`'s static
  `open(project:rootURL:)` helper (which calls `NSWorkspace`, an AppKit-only
  API not used by any of the three types this recipe specifies).
- **WinUI 3**: Model `FileBrowserDirectories` and `FileBrowserRestorationState`
  as `ObservableObject`/`INotifyPropertyChanged` classes (via
  `CommunityToolkit.Mvvm`'s `ObservableObject` base), with `additional` as an
  `ObservableCollection<Uri>` rebuilt through the same
  normalize-then-assign step; there is no direct .NET equivalent of
  `URL.resolvingSymlinksInPath()`, so use `Path.GetFullPath` together with
  `Directory.ResolveLinkTarget` (.NET 6+, `returnFinalTarget: true`) to reach
  the same "compare by resolved location" behavior `add-rejects-existing-root`
  and `root-containing-longest-match` depend on. Persist
  `FileBrowserRestorationState`'s expanded paths and selection through
  `ApplicationData.Current.LocalSettings` or a JSON file under
  `Windows.Storage`, written from the same onChange-only-when-different
  guard. Model `FileTreeManager` as a class composing a `DirectoryWatchCoordinator`
  equivalent built on `System.IO.FileSystemWatcher`, a git-status poller
  invoked from a background `Task`, and the two debounces
  (`fs-change-debounces-git-refresh-500ms`,
  `fs-change-debounces-ide-detection-2000ms`) as two independent
  `DispatcherTimer`s (or `Task.Delay`-based debouncers) restarted on every
  filesystem-watcher callback, mirroring `pendingGitRefresh`/
  `pendingIDEDetection` exactly rather than collapsing them into one timer.

## Design Decisions

**Decision**: Resolve every root's symlinks (`resolvingSymlinksInPath()`)
before storing or comparing it, in `FileBrowserDirectories`, rather than
comparing paths as given.
**Rationale**: the source's own header comment explains that the same folder
can reach this object twice under two different literal paths — once as a
checkout directory git has already resolved, once as a path the user picked
that nothing resolved — and a lexical comparison would treat those as two
different roots.
**Approved**: pending.

**Decision**: `replaceAdditional(with:)` never invokes `onChange`, unlike
`add(_:)`/`remove(_:)`.
**Rationale**: this method exists for a host to tell the object "the roots
changed somewhere else" — a project window mirroring another pane's edit to
the same shared list — and re-raising `onChange` here would send that
update back to the host that just made it, which would persist and fan it
out a second time.
**Approved**: pending.

**Decision**: `FileTreeManager.apply(_:)` overwrites `gitStatus` on every node
in the tree on every applied result, including clearing nodes with no
current entry, rather than only patching the paths a diff says changed.
**Rationale**: `GitStatus` itself carries no "what changed since last time"
information — only the full current map of file/directory statuses — so a
full re-apply is the only way to correctly clear a status for a file that
was modified and is now clean again.
**Approved**: pending.

**Decision**: `apply(_:)` treats `GitStatusRefreshResult.unavailable` as "do
nothing" rather than "clear every badge."
**Rationale**: an empty status and a failed git invocation are
indistinguishable once badges are cleared from them, and clearing on failure
would repaint an entire dirty tree as clean whenever git is misconfigured,
times out, or a request is cancelled — the source's own comment on
`GitStatusRefreshResult` calls this out directly.
**Approved**: pending.
