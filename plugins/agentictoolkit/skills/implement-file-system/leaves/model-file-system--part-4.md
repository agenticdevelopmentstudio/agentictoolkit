<!-- leaf: implement-file-system/model-file-system--part-4 · source: file-system-model-file-system.md -->

# File Browser FileSystem Model — continued (part 4)

## Privacy

- **Data collected**: File and directory paths, names, extensions, sizes,
  and modification dates read from the local file system under `rootURL`,
  plus whatever `gitStatus` an external caller assigns
  (`node-git-status-external`). Nothing is collected beyond what already
  exists on the user's own disk.
- **Storage**: None of these four files persists anything itself; the tree
  is held only in memory for the lifetime of the `DirectoryWatchCoordinator`
  and its `FileTreeNode`s. `FileTreeConfig.customMappingsDefaultsKey` names
  a `UserDefaults` key, but reading or writing that key is owned by a
  different component (`CustomFileTypeMappings`), not these four files.
- **Transmission**: None. No file here imports a networking API or makes a
  network call.
- **Retention**: In-memory only, for as long as the coordinator/node objects
  live; nothing is written to disk by these files.
- **Log privacy annotation**: `FileSystemWatcher.start()` logs its root path
  with an explicit `privacy: .public` annotation
  (`logger.info("Started file system watcher for \(self.rootPath, privacy: .public)")`),
  overriding `os.log`'s default private-by-default redaction for
  string-interpolated values — a deliberate choice to keep the watched
  root's path visible in log output rather than redacted (see Design
  Decisions).

## Platform Notes

- **SwiftUI**: None of these four files imports SwiftUI, but
  `DirectoryWatchCoordinator` and `FileTreeNode`'s `ObservableObject` +
  `@Published` conformances are consumable directly by a SwiftUI view via
  `@StateObject`/`@ObservedObject` with no adapter layer. A SwiftUI port
  would keep this model layer unchanged and bind a `List` or `OutlineGroup`
  to `rootNode`'s `children`, calling `loadChildrenIfNeeded()` from
  `.onAppear` or the row's disclosure action, in place of the AppKit
  `NSOutlineView` consumer described in
  File Tree Outline View Controller.
- **Compose**: Model `@Published var children`/`isSyncing` as
  `mutableStateOf`/`StateFlow` fields observed from a `ViewModel`; run
  `fullSync()`/`handleChanges`'s background reads on
  `kotlinx.coroutines.Dispatchers.IO` inside a coroutine scope in place of
  `DispatchQueue.global`; Android has no FSEvents equivalent, so the watcher
  needs either `java.nio.file.WatchService` (JVM-side polling) or a
  platform `FileObserver`, coalesced on a timer to approximate the `0.5`
  second latency; render the tree as a `LazyColumn` with per-row expand
  state driving a lazy child-load call.
- **React/Web**: A browser sandbox has no direct file-system access at all;
  in a Node-hosted (Electron-style) app, use `fs.promises.readdir` as the
  `contentsOfDirectory` analog and `chokidar` or `fs.watch` (debounced to
  match the `0.5` second latency) as the `FSEventStreamCreate` analog; hold
  `children`/`isSyncing` in React state (`useState`/`useReducer`) or a store
  (Zustand/Redux), and render the tree with a virtualized list component
  that calls the lazy-load function on row expansion.
- **AppKit / UIKit**: The source
  (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/`,
  tested by `Tests/AgenticToolkitMacOSTests/FileBrowser/DirectoryWatchCoordinatorTests.swift`
  and `FileTreeNodeTests.swift`) is macOS-only — it imports `CoreServices`
  for `FSEvents`, which has no iOS counterpart, and lives under a
  `macOS`-specific source directory with no `#if os(iOS)` branch. The direct
  AppKit consumer is `FileTreeOutlineViewController`
  (see File Tree Outline View Controller).
  An iOS port needs a different watch mechanism entirely — a
  `DispatchSource` file-descriptor watch or a polling timer — since
  `FSEventStreamCreate` is unavailable there.
- **WinUI 3**: `System.IO.FileSystemWatcher` is the direct analog to
  `FSEventStreamCreate`/`FSEventStreamSetDispatchQueue`, but its
  `Changed`/`Created`/`Deleted`/`Renamed` events fire per-change rather than
  FSEvents' coalesced batches, so a port needs its own `System.Threading.Timer`
  or `Task.Delay` coalescing buffer to reproduce the `0.5` second latency of
  `watcher-stream-configuration`. Use `ObservableCollection<TreeNode>`
  plus `INotifyPropertyChanged` (or a `CommunityToolkit.Mvvm`
  `ObservableObject`/`[ObservableProperty]`) as the `@Published`/
  `ObservableObject` analog for `rootNode`/`children`.
  `Directory.EnumerateFileSystemEntries` or
  `DirectoryInfo.EnumerateFileSystemInfos` is the `contentsOfDirectory`
  analog; run it on `Task.Run` (the `DispatchQueue.global` analog) and marshal
  results back through the captured `SynchronizationContext` or
  `DispatcherQueue.TryEnqueue` (the `DispatchQueue.main.async` analog). .NET
  has no built-in `fnmatch`; reproduce `node-should-ignore-glob-match` with
  `Microsoft.Extensions.FileSystemGlobbing` or a hand-rolled wildcard
  matcher. For the lazy-load-on-expand behavior
  (`node-load-children-if-needed-guard`), use a `TreeView`/
  `TreeViewNode.HasUnrealizedChildren` plus the `Expanding` event — the same
  mapping this component's own consumer recipe's WinUI 3 bullet already
  uses for `expand-loads-children-lazily`.

## Design Decisions

- **Decision**: `fullSync()` merges into the existing `rootNode` (when its
  `url` matches) instead of always replacing it with the freshly-built tree.
  **Rationale**: Stated directly in the source's inline comment: a fresh
  root is a fresh object for every directory beneath it, so replacing it
  outright would orphan whatever the outline view had already read for a
  currently-open folder, and that folder would come back empty on the next
  redraw even though nothing about it actually changed. Re-using the nodes
  keeps identity, and with it everything already read.
  **Approved**: pending
- **Decision**: Filename exclusion is split across two independent
  mechanisms — `excludedPrefixes` (path-prefix filtering inside
  `FileSystemWatcher`'s FSEvents callback) and `ignorePatterns` (glob
  filename filtering inside `FileTreeNode.loadChildren`) — rather than one
  shared list.
  **Rationale**: Not stated in a source comment. The two operate at
  different layers with different costs: `excludedPrefixes` stops FSEvents
  from ever delivering paths under a noisy subtree (`.git`, `node_modules`)
  to `handleChanges` at all, while `ignorePatterns` only decides what a
  directory listing displays. A directory can therefore be excluded from
  live watching yet still be listable once via `loadChildren` (opening
  `.git` manually still shows its contents unless a pattern also hides it),
  and a filename hidden by `ignorePatterns` still generates FS events that
  reach `handleChanges` if its directory isn't separately excluded.
  **Approved**: pending
- **Decision**: A directory read eagerly at construction
  (`init(loadChildren: true)`) keeps `children` as a non-nil empty array
  when it turns out to be empty, while the lazy path
  (`loadChildrenIfNeeded()`) converts that same empty result to `nil`.
  **Rationale**: Not stated in a source comment for the eager path
  specifically; the lazy path's own comment explains only its half: "`nil`,
  not an empty array, for a directory that turned out to have nothing in
  it... keeping it would leave a disclosure triangle that opens onto
  nothing." The eager path has no equivalent conversion, so the two
  construction paths leave a genuinely empty, already-read directory in two
  different observable shapes depending on which path read it.
  **Approved**: pending
- **Decision**: `loadChildrenIfNeeded()` sets `childrenLoaded = true`
  synchronously, before dispatching the background read, rather than after
  the read completes.
  **Rationale**: Stated directly in the source's inline comment: "two rows
  appearing in the same frame must not both start the same enumeration."
  Setting the flag first makes a second near-simultaneous call see
  `childrenLoaded == true` and return early, guaranteeing at most one
  background read per directory per open.
  **Approved**: pending
- **Decision**: The FSEvents callback force-casts `eventPaths` via
  `unsafeBitCast(eventPaths, to: NSArray.self) as! [String]`, with an
  inline `swiftlint:disable:this force_cast` comment.
  **Rationale**: Not stated beyond the disable comment itself; the cast's
  safety depends entirely on `kFSEventStreamCreateFlagUseCFTypes` being
  passed to `FSEventStreamCreate` (`watcher-stream-configuration`), which
  guarantees `eventPaths` really is a `CFArray` of `CFString`s bridgeable to
  `NSArray`/`String`. This is accepted technical debt: if that flag were
  ever removed, the cast would crash rather than fail gracefully.
  **Approved**: pending
- **Decision**: `FileSystemWatcher.start()` logs the watched root path with
  an explicit `privacy: .public` annotation rather than `os.log`'s
  private-by-default redaction for interpolated values.
  **Rationale**: Not stated in a source comment. A locally-mounted project
  path is treated here as safe to surface in log output, which is a
  deliberate choice given `os.log` otherwise redacts interpolated strings by
  default.
  **Approved**: pending
- The open question on `concurrent-sync-reentrancy` (Behavioral
  Requirements) is a source-fidelity gap, not a resolved design decision:
  no rationale for the current last-completion-wins behavior exists in the
  given sources.
