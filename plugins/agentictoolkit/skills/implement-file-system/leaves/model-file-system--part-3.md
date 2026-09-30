<!-- leaf: implement-file-system/model-file-system--part-3 · source: file-system-model-file-system.md -->

# File Browser FileSystem Model — continued (part 3)

**Rules** (cite as `implement-file-system/model-file-system--part-3#<slug>`):

- `node-max-display-width-formula` MUST
- `node-max-display-width-recursion` MUST
- `node-max-display-width-unmaterialized-children` MUST
- `watcher-unchecked-sendable-declaration` MUST
- `watcher-exclusion-prefix-match` MUST
- `watcher-start-idempotent` MUST
- `watcher-create-failure-retryable` MUST
- `watcher-callback-path-filtering` MUST
- `watcher-callback-main-thread-dispatch` MUST
- `watcher-stream-configuration` MUST
- `watcher-stop-teardown` MUST
- `watcher-deinit-safety-net` MUST
- `coordinator-mainactor-declaration` MUST
- `coordinator-ignore-patterns-mutable` MUST
- `coordinator-full-sync-one-level` MUST
- `coordinator-full-sync-background-io` MUST
- `coordinator-full-sync-merge-vs-replace` MUST
- `coordinator-full-sync-completion-signal` MUST
- `coordinator-start-watching-registration` MUST
- `coordinator-stop-watching-teardown` MUST
- `coordinator-handle-changes-pre-sync-guard` MUST
- `coordinator-handle-changes-affected-directories` MUST
- `coordinator-handle-changes-index-scope` MUST
- `coordinator-handle-changes-per-directory-reload` MUST
- `coordinator-handle-changes-completion-signal` MUST

- **node-max-display-width-formula**:
  `maximumDisplayWidth(depth:characterWidth:indentPerLevel:baseWidth:)` MUST
  compute a node's own width as `baseWidth + (CGFloat(depth) *
  indentPerLevel) + (CGFloat(name.count) * characterWidth)`, using the
  defaults `characterWidth: 7.5`, `indentPerLevel: 20.0`, `baseWidth: 70.0`
  when the caller supplies none.
- **node-max-display-width-recursion**: `maximumDisplayWidth(...)` MUST
  return its own width unchanged when `children` is `nil`, and otherwise
  MUST return the greater of its own width and the maximum width returned
  by recursing into each child at `depth + 1`.
- **node-max-display-width-unmaterialized-children**:
  `maximumDisplayWidth(...)` MUST compute its result only from nodes already
  materialized in memory; an unopened directory (`children == []`) MUST
  contribute no width from its own on-disk descendants, since none has been
  read yet.
- **watcher-unchecked-sendable-declaration**: `FileSystemWatcher` MUST be
  declared `final class FileSystemWatcher: @unchecked Sendable`, so the
  compiler MUST NOT independently verify its internal thread safety; callers
  are trusted to serialize their own access to `start()`/`stop()`.
- **watcher-exclusion-prefix-match**: `FileSystemWatcher.isExcluded(_:by:)`
  MUST return `true` for a path if and only if the path equals a prefix in
  `prefixes` exactly, or starts with that prefix followed by `"/"`; it MUST
  NOT use a bare `hasPrefix` match without that separator.
- **watcher-start-idempotent**: `start()` MUST do nothing — create no new
  stream, install no new callback — when `streamRef` is already non-`nil`.
- **watcher-create-failure-retryable**: `start()` MUST log an error and
  return, leaving `streamRef` as `nil`, when `FSEventStreamCreate` returns
  `nil`; because `streamRef` stays `nil`, a later call to `start()` MUST
  attempt creation again.
- **watcher-callback-path-filtering**: The FSEvents callback MUST filter
  `eventPaths` through `isExcluded(_:by:)` against `excludedPrefixes` before
  invoking `handler`, and MUST NOT invoke `handler` at all when every
  reported path is excluded.
- **watcher-callback-main-thread-dispatch**: The FSEvents callback MUST
  invoke `handler` via `DispatchQueue.main.async`, regardless of which
  thread or queue FSEvents itself delivered the event on.
- **watcher-stream-configuration**: `start()` MUST create the FSEvents
  stream with `kFSEventStreamEventIdSinceNow` (future events only, no
  historical replay), a latency of `0.5` seconds, and the flags
  `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes`.
- **watcher-stop-teardown**: `stop()` MUST call `FSEventStreamStop`,
  `FSEventStreamInvalidate`, and `FSEventStreamRelease` on the current
  stream, then set `streamRef` to `nil`; it MUST do nothing when `streamRef`
  is already `nil`.
- **watcher-deinit-safety-net**: `FileSystemWatcher.deinit` MUST call
  `stop()`, so a watcher deallocated without an explicit `stop()` call MUST
  still tear down its FSEvents stream.
- **coordinator-mainactor-declaration**: `DirectoryWatchCoordinator` MUST be
  declared `@MainActor`, and its `rootURL`, `excludedPrefixes`, and `config`
  MUST be set once at `init` and MUST NOT change afterward.
- **coordinator-ignore-patterns-mutable**: `ignorePatterns` MUST be a
  public, mutable property that a caller MAY change at any time after
  construction, independently of `rootURL`, `excludedPrefixes`, or `config`.
- **coordinator-full-sync-one-level**: `fullSync()` MUST read only the root
  directory's own immediate entries (via `FileTreeNode(loadChildren: true,
  ...)`); it MUST NOT recursively read any directory below the root.
- **coordinator-full-sync-background-io**: `fullSync()` MUST perform its
  directory read on `DispatchQueue.global(qos: .userInitiated)`, and MUST
  set `isSyncing = true` before dispatching that read and `isSyncing =
  false` only after the result has been applied on the main queue.
- **coordinator-full-sync-merge-vs-replace**: `fullSync()` MUST call
  `existing.merge(children:)` on the current `rootNode` — keeping that
  `rootNode` instance and reusing already-read descendant node instances —
  when a `rootNode` already exists and its `url` equals `rootURL`; it MUST
  replace `rootNode` outright with the freshly-built tree only when no
  `rootNode` exists yet, or the existing one's `url` differs from `rootURL`.
- **coordinator-full-sync-completion-signal**: `fullSync()` MUST invoke
  `onChangeCallback` and log an info message naming
  `rootURL.lastPathComponent`, on the main queue, only after `isSyncing` has
  been set back to `false`.
- **coordinator-start-watching-registration**: `startWatching(onChange:)`
  MUST store the supplied closure as `onChangeCallback`, construct a
  `FileSystemWatcher` for `rootURL.path` and `excludedPrefixes`, and call
  `start()` on it; its change-handling closure MUST re-enter `@MainActor`
  isolation via `Task { @MainActor in ... }` before calling
  `handleChanges(_:)`.
- **coordinator-stop-watching-teardown**: `stopWatching()` MUST call
  `stop()` on the current watcher and set the coordinator's stored watcher
  reference to `nil`.
- **coordinator-handle-changes-pre-sync-guard**: `handleChanges(_:)` MUST
  return immediately, without touching `isSyncing`, when `rootNode` is
  still `nil` — a change delivered before the first `fullSync()` has
  published a tree is already covered by that pending sync.
- **coordinator-handle-changes-affected-directories**: `handleChanges(_:)`
  MUST compute the set of affected directories as the distinct results of
  `(path as NSString).deletingLastPathComponent` applied to every changed
  path.
- **coordinator-handle-changes-index-scope**: `handleChanges(_:)` MUST build
  its path-to-node index (`buildIndex`) by walking only nodes already
  materialized under `rootNode` — recursing solely through non-`nil`
  `children` arrays — and MUST drop an affected directory from the update
  set entirely when no directory node for it exists in that index; a change
  reported for a directory that has never been materialized in the tree
  MUST produce no update and no error.
- **coordinator-handle-changes-per-directory-reload**: For each affected
  directory that does have a matching node, `handleChanges(_:)` MUST
  re-read that one directory level via
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` on
  `DispatchQueue.global(qos: .userInitiated)`, then apply the result with
  `merge(children:)` on the main queue.
- **coordinator-handle-changes-completion-signal**: `handleChanges(_:)`
  MUST set `isSyncing = false` and invoke `onChangeCallback` on the main
  queue only after every affected directory's `merge(children:)` call has
  been applied.
- **concurrent-sync-reentrancy**: NEEDS REVIEW: Not implemented in source. Neither `fullSync()` nor `handleChanges(_:)` guards against being invoked again while a previous invocation's background read is still in flight — both set `isSyncing = true` unconditionally rather than checking it first, unlike `loadChildrenIfNeeded()`'s explicit `childrenLoaded`-set-before-dispatch guard for the analogous per-node race — so two overlapping calls each independently dispatch their own background read and later apply `merge(children:)` on the main actor in whichever order their background work happens to finish, not the order the calls (or the underlying FS events) occurred in; this would be settled by either a source change that coalesces or serializes overlapping syncs, or a test demonstrating the current last-completion-wins ordering is acceptable, and neither exists in the given sources.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | `URL` | required (`DirectoryWatchCoordinator.init`) | The directory this coordinator syncs and watches. |
| `config` | `FileTreeConfig` | required; caller may pass `.default` | Opaque-package extensions/display names and the `UserDefaults` key for custom file-type mappings — threaded through but not read by these four files beyond `packageExtensions`. |
| `excludedPrefixes` | `[String]` | required (`DirectoryWatchCoordinator.init`, `FileSystemWatcher.init`) | Absolute path prefixes; FS events at or under any of them are dropped by `FileSystemWatcher.isExcluded` before `handleChanges` ever runs. |
| `ignorePatterns` | `[String]` | `[]` | Wildcard filename patterns filtered out of every directory listing via `fnmatch`; settable at any time through the coordinator's public `var`. |
| `packageExtensions` | `Set<String>` | `[]` (via `FileTreeConfig`) | Extensions whose matching directories are treated as opaque, single-item packages. |
| `packageDisplayNames` | `[String: String]` | `[:]` (via `FileTreeConfig`) | Passed through `FileTreeConfig`; not read by any of these four files itself. |
| `customMappingsDefaultsKey` | `String` | `"AgenticFileBrowser.customMappings"` (via `FileTreeConfig`) | `UserDefaults` key naming; not read by any of these four files itself — owned by `CustomFileTypeMappings`. |
| `onChange` (`startWatching(onChange:)`) | `(() -> Void)?` | `nil` | Closure `DirectoryWatchCoordinator` invokes after every applied sync or watched change. |
| `url` / `isDirectory` / `loadChildren` (`FileTreeNode.init`) | `URL` / `Bool` / `Bool` | `loadChildren` defaults to `false` | Per-node construction arguments the coordinator and `loadChildren(for:)` supply. |

