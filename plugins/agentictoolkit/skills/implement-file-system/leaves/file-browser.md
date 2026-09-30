<!-- leaf: implement-file-system/file-browser · source: file-system-file-browser.md -->

**Rules** (cite as `implement-file-system/file-browser#<slug>`):

- `primary-resolves-symlinks` MUST
- `additional-normalized-on-construction` MUST
- `all-orders-primary-first` MUST
- `replace-additional-silent` MUST
- `replace-additional-skips-unchanged-value` MUST
- `add-appends-resolved-and-reports` MUST
- `add-rejects-existing-root` MUST
- `remove-removes-resolved-and-reports` MUST
- `remove-rejects-non-member` MUST
- `is-removable-reflects-additional-membership` MUST
- `root-containing-longest-match` MUST
- `init-seeds-without-reporting` MUST
- `is-expanded-membership` MUST
- `set-expanded-reports-only-on-change` MUST
- `set-selected-path-reports-only-on-change` MUST
- `on-change-payload-sorted-paths` MUST
- `construction-is-inert` MUST
- `git-status-provider-injectable-or-owned` MUST
- `git-status-observation-retained-for-lifetime` MUST
- `coordinator-excludes-fixed-prefixes` MUST
- `rootnode-and-syncing-mirror-coordinator` MUST
- `update-ignore-patterns-triggers-resync` MUST
- `load-initial-starts-three-independent-operations` MUST
- `start-watching-delegates-to-coordinator` MUST
- `stop-watching-cancels-pending-debounces` MUST
- `fs-change-debounces-git-refresh-500ms` MUST
- `fs-change-debounces-ide-detection-2000ms` MUST
- `refresh-git-status-delegates-to-provider` MUST
- `ide-detection-reentrant-safe` MUST
- `apply-ignores-unavailable-result` MUST
- `apply-requires-root-node` MUST
- `apply-overwrites-entire-tree` MUST
- `apply-keys-by-repo-relative-path` MUST
- `apply-branches-on-node-directory-flag` MUST

# File System File Browser

## Overview

Three `@MainActor` Combine model types that together form the non-visual
contract behind the file browser: `FileBrowserDirectories` (the primary root
plus any additional roots the user has added), `FileBrowserRestorationState`
(which directories were disclosed and which file was selected, for a host to
persist and restore), and `FileTreeManager` (the per-root coordinator that
delegates directory scanning and filesystem watching to a
`DirectoryWatchCoordinator`, overlays git status from a `GitStatusProvider`,
and runs IDE-marker detection through an `IDEDetector`). None of the three
draws anything; they are the state and orchestration a UI layer such as
`FileBrowserViewController`/`FileTreeOutlineViewController` observes and
drives.

## Behavioral Requirements

### FileBrowserDirectories

- **primary-resolves-symlinks**: `init(primary:additional:)` MUST store
  `primary` as `primary.resolvingSymlinksInPath()`, never the URL as given.
- **additional-normalized-on-construction**: `init(primary:additional:)` MUST
  resolve every URL in `additional` via `resolvingSymlinksInPath()`, and MUST
  drop any resolved URL that equals the resolved `primary` or duplicates an
  already-kept resolved URL, keeping the surviving URLs in their original
  order (`normalize(_:primary:)`).
- **all-orders-primary-first**: `all` MUST return `[primary]` followed by
  `additional`, in that order, on every access.
- **replace-additional-silent**: `replaceAdditional(with:)` MUST normalize
  `urls` the same way construction does and MUST assign the result to
  `additional` without invoking `onChange`, regardless of whether the value
  changed.
- **replace-additional-skips-unchanged-value**: `replaceAdditional(with:)`
  MUST NOT reassign `additional` (and therefore MUST NOT republish
  `$additional`) when the normalized replacement already equals the current
  `additional`.
- **add-appends-resolved-and-reports**: `add(_:)` MUST resolve `url`'s
  symlinks, append the resolved URL to `additional`, invoke `onChange` with
  the new `additional`, and return `true`, whenever the resolved URL is not
  already a member of `all`.
- **add-rejects-existing-root**: `add(_:)` MUST make no change to
  `additional`, MUST NOT invoke `onChange`, and MUST return `false` when the
  resolved `url` already equals `primary` or an existing member of
  `additional`.
- **remove-removes-resolved-and-reports**: `remove(_:)` MUST resolve `url`'s
  symlinks, remove the matching entry from `additional`, invoke `onChange`
  with the new `additional`, and return `true`, whenever the resolved URL is
  currently a member of `additional`.
- **remove-rejects-non-member**: `remove(_:)` MUST make no change, MUST NOT
  invoke `onChange`, and MUST return `false` when the resolved `url` is not
  currently a member of `additional` — this is also what happens when `url`
  is `primary`, since `primary` is never stored in `additional`.
- **is-removable-reflects-additional-membership**: `isRemovable(_:)` MUST
  return whether `url`'s resolved form is currently a member of `additional`,
  and therefore MUST always return `false` for `primary`.
- **root-containing-longest-match**: `root(containing:)` MUST return the
  member of `all` whose path equals the resolved `url`'s path, or is a
  path-segment prefix of it (`path == root.path` or
  `path.hasPrefix(root.path + "/")`), choosing the longest matching root's
  path when more than one root matches, and MUST return `nil` when no root
  in `all` matches.

### FileBrowserRestorationState

- **init-seeds-without-reporting**: `init(expandedPaths:selectedPath:)` MUST
  set `expandedPaths` to a `Set` built from the given array and
  `selectedPath` to the given value, and MUST NOT invoke `onChange` as part
  of construction.
- **is-expanded-membership**: `isExpanded(_:)` MUST return whether `path` is
  currently a member of `expandedPaths`.
- **set-expanded-reports-only-on-change**: `setExpanded(_:path:)` MUST insert
  `path` into `expandedPaths` when the argument is `true` and remove it when
  `false`, and MUST invoke `onChange` afterward if and only if that
  insert/remove actually changed `expandedPaths`' membership.
- **set-selected-path-reports-only-on-change**: `setSelectedPath(_:)` MUST
  assign `path` to `selectedPath` and MUST invoke `onChange` afterward if and
  only if `path` differs from the current `selectedPath`.
- **on-change-payload-sorted-paths**: Every `onChange` invocation MUST pass
  `expandedPaths.sorted()` (ascending `String` order) as its first argument,
  never the unsorted `Set`, and the current `selectedPath` as its second.

### FileTreeManager

- **construction-is-inert**: `init(repoRootURL:packageURL:config:ignorePatterns:gitStatusProvider:)`
  MUST NOT perform a directory scan, start filesystem watching, request a git
  status refresh, or run IDE detection; each of those MUST happen only when a
  caller invokes `loadInitial()`, `startWatching()`, `refreshGitStatus()`, or
  `ideDetector.detect()` respectively.
- **git-status-provider-injectable-or-owned**: Construction MUST use the
  `gitStatusProvider` argument as-is when it is non-`nil`, and MUST construct
  a new `GitStatusProvider(repoRoot: repoRootURL)` when it is `nil`.
- **git-status-observation-retained-for-lifetime**: Construction MUST
  register exactly one observer with the manager's `gitStatusProvider` via
  `observe(_:)` and MUST retain the returned `GitStatusObservation` in
  `gitStatusObservation` for the manager's lifetime, so the registration is
  released — and this manager stops receiving broadcasts — only when the
  manager itself is deallocated.
- **coordinator-excludes-fixed-prefixes**: Construction MUST build the
  manager's `DirectoryWatchCoordinator` with `excludedPrefixes` equal to
  exactly `[packageURL.path, repoRootURL.appendingPathComponent(".git").path]`.
- **rootnode-and-syncing-mirror-coordinator**: `rootNode` and `isSyncing` MUST
  always equal the coordinator's own `$rootNode`/`$isSyncing` values, applied
  on the main run loop (`.receive(on: DispatchQueue.main)`).
- **update-ignore-patterns-triggers-resync**: `updateIgnorePatterns(_:)` MUST
  replace the coordinator's `ignorePatterns` with the given value and MUST
  then call `coordinator.fullSync()`.
- **load-initial-starts-three-independent-operations**: `loadInitial()` MUST
  call `coordinator.fullSync()`, `refreshGitStatus()`, and
  `ideDetector.detect()`; none of the three MUST wait for another to
  complete before starting.
- **start-watching-delegates-to-coordinator**: `startWatching()` MUST call
  `coordinator.startWatching(onChange:)` with a callback that invokes this
  manager's own `onCoordinatorChanged()`.
- **stop-watching-cancels-pending-debounces**: `stopWatching()` MUST call
  `coordinator.stopWatching()` and MUST cancel and discard both
  `pendingGitRefresh` and `pendingIDEDetection`, whichever of the two is
  currently scheduled.
- **fs-change-debounces-git-refresh-500ms**: Each time `onCoordinatorChanged()`
  runs, it MUST cancel any previously scheduled git-status refresh and
  schedule a new one for exactly 0.5 seconds later on the main queue.
- **fs-change-debounces-ide-detection-2000ms**: The same
  `onCoordinatorChanged()` call MUST also cancel any previously scheduled IDE
  re-detection and schedule a new one for exactly 2.0 seconds later on the
  main queue, independently of the git-refresh scheduling in the previous
  requirement.
- **refresh-git-status-delegates-to-provider**: `refreshGitStatus()` MUST call
  `gitStatusProvider.refresh()` and MUST NOT itself track whether a refresh is
  already in flight.
- **ide-detection-reentrant-safe**: A call to `ideDetector.detect()` made while
  a previously started detection scan has not yet finished MUST be a no-op
  (`IDEDetector.detect()`'s own `guard !isDetecting else { return }`), so the
  debounced re-detection this manager schedules can never pile up concurrent
  scans against one `IDEDetector`.
- **apply-ignores-unavailable-result**: When the observed
  `GitStatusRefreshResult` is `.unavailable`, `apply(_:)` MUST leave every
  node's `gitStatus` unchanged.
- **apply-requires-root-node**: When the observed result is `.status(_:)` but
  `rootNode` is `nil`, `apply(_:)` MUST leave every node's `gitStatus`
  unchanged, since there is no tree to walk.
- **apply-overwrites-entire-tree**: When the observed result is `.status(_:)`
  and `rootNode` is non-`nil`, `apply(_:)` MUST recursively set `gitStatus` on
  every node currently in the tree — including assigning `nil` to a node
  whose repo-relative path has no entry in the result's `files`/`directories`
  maps, not only adding entries for paths that changed.
- **apply-keys-by-repo-relative-path**: Each node's lookup key MUST be its
  `url.path` with the manager's `repoRootURL.path + "/"` prefix stripped, or
  the empty string when the node's path does not begin with that prefix
  (which is the case for the repo root node itself).
- **apply-branches-on-node-directory-flag**: A node's status MUST be looked
  up in the result's `directories` map when `node.isDirectory` is `true`, and
  in its `files` map otherwise.

