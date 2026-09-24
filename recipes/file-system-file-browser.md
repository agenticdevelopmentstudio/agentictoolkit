---
id: fa6a7094-40c2-4302-8cf3-742a072f5bb3
title: File System File Browser
domain: agentictoolkit://recipes/file-system-file-browser
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The file-browser model layer: root-set management, expand/select restoration, and per-root scan/watch/git-status/IDE-detection orchestration."
platforms:
- swift
- macos
tags:
- file-browser
- macos
- git-status
- restoration
depends-on: []
related:
- agentictoolkit://recipes/file-browser-view-controller
- agentictoolkit://recipes/file-tree-outline-view-controller
references:
- https://developer.apple.com/documentation/combine/observableobject
- https://developer.apple.com/documentation/foundation/url/resolvingsymlinksinpath()
- https://developer.apple.com/documentation/swift/mainactor
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a set of Combine model/manager types
(`FileBrowserDirectories`, `FileBrowserRestorationState`, `FileTreeManager`),
not a visual component.

## States

Not applicable — this is a set of Combine model/manager types, not a visual
component; the runtime states these types occupy (syncing, watching,
detecting, awaiting a git-status broadcast) are covered under Behavioral
Requirements above, not in a visual-state table.

## Accessibility

Not applicable — this is a set of Combine model/manager types, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-system-file-browser-001 | primary-resolves-symlinks | Construct `FileBrowserDirectories(primary: symlinkURL)` where `symlinkURL` is a symlink to `targetURL`. | `directories.primary` equals `targetURL.resolvingSymlinksInPath()`, not `symlinkURL` as given. |
| file-system-file-browser-002 | additional-normalized-on-construction | Construct with `primary: A` and `additional: [A, B, B]` (a symlink to `B` appears twice, one of which resolves to `A`). | `additional` equals `[B]`; the entry resolving to `A` and the duplicate `B` are both dropped. |
| file-system-file-browser-003 | all-orders-primary-first | Construct with `primary: A`, `additional: [B, C]`. | `all` equals `[A, B, C]`. |
| file-system-file-browser-004 | replace-additional-silent | Call `replaceAdditional(with: [D])` on an instance with an `onChange` closure installed. | `additional` becomes `[D]`; the `onChange` closure is not invoked. |
| file-system-file-browser-005 | replace-additional-skips-unchanged-value | Call `replaceAdditional(with:)` with the same URLs `additional` already holds (in the same order). | `$additional` does not publish a new value as a result of the call. |
| file-system-file-browser-006 | add-appends-resolved-and-reports | Call `add(E)` where `E` is not `primary` and not already in `additional`, with `onChange` installed. | Returns `true`; `additional` gains `E.resolvingSymlinksInPath()` at the end; `onChange` is called once with the new `additional`. |
| file-system-file-browser-007 | add-rejects-existing-root | Call `add(primary)`. | Returns `false`; `additional` and `onChange` are both unaffected. |
| file-system-file-browser-008 | remove-removes-resolved-and-reports | Call `remove(B)` where `B` is a current member of `additional`, with `onChange` installed. | Returns `true`; `B` is removed from `additional`; `onChange` is called once with the new `additional`. |
| file-system-file-browser-009 | remove-rejects-non-member | Call `remove(primary)`. | Returns `false`; `additional` and `onChange` are both unaffected. |
| file-system-file-browser-010 | is-removable-reflects-additional-membership | Call `isRemovable(primary)` and `isRemovable(B)` where `B` is in `additional`. | Returns `false` for `primary`, `true` for `B`. |
| file-system-file-browser-011 | root-containing-longest-match | Construct with `primary: /repo` and `additional: [/repo/vendor/lib]` (a root nested inside `primary`), then call `root(containing: /repo/vendor/lib/x.swift)`. | Returns `/repo/vendor/lib`, not `/repo`. |
| file-system-file-browser-012 | init-seeds-without-reporting | Construct `FileBrowserRestorationState(expandedPaths: ["/tmp/a"], selectedPath: "/tmp/a/b")` with `onChange` installed immediately after. | `isExpanded("/tmp/a")` is `true`; `selectedPath` equals `"/tmp/a/b"`; `onChange` has not been called. |
| file-system-file-browser-013 | is-expanded-membership | Call `isExpanded("/tmp/never-added")` on a fresh instance. | Returns `false`. |
| file-system-file-browser-014 | set-expanded-reports-only-on-change | Call `setExpanded(true, path: "/tmp/a")` twice in a row, with `onChange` installed. | `onChange` is called exactly once, after the first call; the second call (no membership change) does not invoke it. |
| file-system-file-browser-015 | set-selected-path-reports-only-on-change | Call `setSelectedPath("/tmp/a/x.swift")` then call it again with the same path, with `onChange` installed. | `onChange` is called exactly once, after the first call. |
| file-system-file-browser-016 | on-change-payload-sorted-paths | Call `setExpanded(true, path: "/tmp/b")` then `setExpanded(true, path: "/tmp/a")`. | The second `onChange` call's first argument is `["/tmp/a", "/tmp/b"]`, sorted, not `["/tmp/b", "/tmp/a"]` in call order. |
| file-system-file-browser-017 | construction-is-inert | Construct a `FileTreeManager` and, before calling any method on it, inspect `rootNode`, `isSyncing`, and `ideDetector.detectedIDEs`. | `rootNode` is `nil`; `isSyncing` is `false`; `detectedIDEs` is empty — no scan, watch, refresh, or detection has started. |
| file-system-file-browser-018 | git-status-provider-injectable-or-owned | Construct one manager passing an explicit `GitStatusProvider` instance `P`, and a second passing none. | The first manager's `gitStatusProvider` is `P` (`===`); the second manager's `gitStatusProvider` is a distinct instance whose `repoRoot` equals the manager's `repoRootURL`. |
| file-system-file-browser-019 | git-status-observation-retained-for-lifetime | Construct a manager sharing an injected `GitStatusProvider` with another manager, then let the first manager be deallocated. | After deallocation, a subsequent `provider.refresh()` broadcast is delivered only to the surviving manager's observer, not to the deallocated one's. |
| file-system-file-browser-020 | coordinator-excludes-fixed-prefixes | Construct a manager with `repoRootURL: /repo`, `packageURL: /repo/.build`. | The coordinator's `excludedPrefixes` equals `["/repo/.build", "/repo/.git"]`. |
| file-system-file-browser-021 | rootnode-and-syncing-mirror-coordinator | Call `loadInitial()` and observe `manager.rootNode`/`manager.isSyncing` while the underlying coordinator's `fullSync()` runs. | `manager.isSyncing` becomes `true` when the coordinator's does, and `manager.rootNode`/`manager.isSyncing` settle to the coordinator's final published values once the sync completes. |
| file-system-file-browser-022 | update-ignore-patterns-triggers-resync | Call `updateIgnorePatterns(["*.log"])` on a manager whose tree already contains a `debug.log` file. | The coordinator's `ignorePatterns` becomes `["*.log"]` and a full resync runs; the resulting tree omits `debug.log`. |
| file-system-file-browser-023 | load-initial-starts-three-independent-operations | Call `loadInitial()` and record the order in which `coordinator.fullSync()`, `refreshGitStatus()`, and `ideDetector.detect()` are invoked. | All three are invoked once, in that order, with no invocation waiting on another's completion before starting. |
| file-system-file-browser-024 | start-watching-delegates-to-coordinator | Call `startWatching()`, then mutate a file under `repoRootURL`. | `coordinator.startWatching` was called with a non-`nil` callback; the mutation eventually triggers `onCoordinatorChanged()` on the manager. |
| file-system-file-browser-025 | stop-watching-cancels-pending-debounces | Trigger a filesystem change (scheduling both debounced work items), then immediately call `stopWatching()` before either fires. | `coordinator.stopWatching()` is called; neither the debounced git refresh nor the debounced IDE re-detection runs afterward. |
| file-system-file-browser-026 | fs-change-debounces-git-refresh-500ms | Trigger `onCoordinatorChanged()` twice, 0.1 seconds apart. | `refreshGitStatus()`'s underlying `gitStatusProvider.refresh()` is invoked once, approximately 0.5 seconds after the *second* trigger, not once per trigger. |
| file-system-file-browser-027 | fs-change-debounces-ide-detection-2000ms | Trigger `onCoordinatorChanged()` twice, 0.5 seconds apart. | `ideDetector.detect()` is invoked once, approximately 2.0 seconds after the *second* trigger, not once per trigger. |
| file-system-file-browser-028 | refresh-git-status-delegates-to-provider | Call `refreshGitStatus()` twice in immediate succession. | `gitStatusProvider.refresh()` is called twice; the manager itself performs no in-flight check (any coalescing observed comes from `GitStatusProvider`, not from `FileTreeManager`). |
| file-system-file-browser-029 | ide-detection-reentrant-safe | Call `ideDetector.detect()` twice in immediate succession, before the first scan's background work completes. | Only one background scan runs; the second call is a no-op (`isDetecting` was already `true`). |
| file-system-file-browser-030 | apply-ignores-unavailable-result | With a tree already showing `gitStatus == .modified` on a node, deliver `GitStatusRefreshResult.unavailable` to the manager's observer callback. | That node's `gitStatus` remains `.modified`; nothing is cleared. |
| file-system-file-browser-031 | apply-requires-root-node | With `rootNode == nil`, deliver `GitStatusRefreshResult.status(someStatus)`. | No crash occurs and no node's `gitStatus` is set, since there is no tree. |
| file-system-file-browser-032 | apply-overwrites-entire-tree | With a tree where node `a.swift` has `gitStatus == .modified`, deliver a `GitStatusRefreshResult.status(_:)` whose `files` map no longer contains `a.swift` but does contain `b.swift: .added`. | `a.swift`'s `gitStatus` becomes `nil`; `b.swift`'s `gitStatus` becomes `.added`. |
| file-system-file-browser-033 | apply-keys-by-repo-relative-path | With `repoRootURL: /repo`, deliver a status whose `files` map contains `"src/a.swift": .modified`. | The node at `/repo/src/a.swift` receives `gitStatus == .modified`; the root node itself (relative path `""`) is looked up in `directories[""]`, which is never populated by `GitStatus.parse`, so it receives `nil`. |
| file-system-file-browser-034 | apply-branches-on-node-directory-flag | Deliver a status whose `directories` map contains `"src": .modified` and whose `files` map contains `"src": .added` (a contrived collision). | The directory node at repo-relative path `"src"` receives `.modified` (looked up in `directories`), not `.added`. |
| file-system-file-browser-035 | main-actor-isolation-across-all-three-types | Inspect the type declarations of `FileBrowserDirectories`, `FileBrowserRestorationState`, and `FileTreeManager`. | All three are `@MainActor public final class`, none conforms to `Sendable`, matching the requirement. |
| file-system-file-browser-036 | git-status-may-be-dropped-before-first-sync | Call `loadInitial()` on a manager whose `gitStatusProvider.refresh()` resolves before `coordinator.fullSync()` publishes `rootNode`. | The git-status result is dropped (per `apply-requires-root-node`); once `rootNode` is later published, no node shows a git-status badge until the next debounced or explicit refresh — the open question this marker records. |
| file-system-file-browser-037 | overlapping-directory-syncs-race | Call `updateIgnorePatterns(["*.a"])` immediately followed by `updateIgnorePatterns(["*.b"])`, arranging for the first call's background read to finish after the second's. | The final `rootNode` reflects the first call's `*.a` pattern rather than the more recently requested `*.b` pattern — the open question this marker records. |

## Edge Cases

- **Null and empty input**: `FileBrowserDirectories(primary:)` with no
  `additional` argument (the default `[]`) MUST leave `all` equal to
  `[primary]`. `FileBrowserRestorationState()` with no arguments (defaults
  `[]`/`nil`) MUST leave `isExpanded(_:)` `false` for every path and
  `selectedPath` `nil`, with no crash. `FileTreeManager` with the default
  `ignorePatterns: []` excludes nothing of its own beyond whatever the
  delegated `FileTreeNode.loadChildren` already hardcodes (skipping
  `.DS_Store`) — this MUST hold.
- **Boundary values**: A URL passed to `add(_:)` or `remove(_:)` that is
  byte-for-byte identical to an existing root, and one that only resolves to
  the same location after `resolvingSymlinksInPath()`, MUST be treated
  identically (both are "the same root") because both go through the same
  resolve-then-compare step. A root added *inside* another root (nested
  under `primary` or another `additional` entry) MUST resolve
  `root(containing:)` to the more specific (deepest-path) root, per
  **root-containing-longest-match**, not the outer one.
- **Concurrent access**: All three types are `@MainActor`-isolated
  (**main-actor-isolation-across-all-three-types**), so no two calls into any
  one of them can race against each other from different threads. Two
  genuine ordering gaps remain even under that isolation — a delayed git
  status broadcast racing the tree's first sync, and two overlapping
  directory syncs racing each other — both left open above (see the open question on `git-status-may-be-dropped-before-first-sync`
  and the open question on `overlapping-directory-syncs-race`). A single
  `GitStatusProvider` MAY be shared across multiple `FileTreeManager`
  instances (confirmed by `FileTreeManagerInjectedProviderTests`); each
  manager's own `GitStatusObservation` is independent, so one manager being
  deallocated does not affect another sharing the same provider.
- **Error states**: A `GitStatusRefreshResult.unavailable` (git missing, the
  process failing, or a cancelled request, per `GitStatusProvider`'s own
  documentation) MUST leave existing git-status badges exactly as they were
  — this component draws no distinction between "nothing has changed" and
  "we could not find out," beyond simply not touching the data it already
  has. A filesystem read failure inside the delegated
  `DirectoryWatchCoordinator`/`FileTreeNode` layer is swallowed to an empty
  result before it ever reaches `FileTreeManager` (documented in the sibling
  `file-tree-outline-view-controller` recipe's Edge Cases); none of the three
  types in this recipe surfaces a distinct error state for that case either.
- **Offline/disconnected state**: Not applicable. None of the three types
  makes a network request; `GitStatusProvider` runs a local `git` subprocess
  through `GitClient`, and all filesystem access is local to the machine, so
  there is no connectivity-loss behavior to define here.

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

## Deep Linking

Not applicable: none of `FileBrowserDirectories.swift`,
`FileBrowserRestorationState.swift`, or `FileTreeManager.swift` contains any
URL-scheme or route handling.

## Localization

Not applicable: none of the three files constructs a user-facing string of
any kind; every value they hold or emit is a `URL`, a `String` file path, a
`Bool`, or a model/enum value, none of it chrome text.

## Accessibility Options

Not applicable: these are non-visual model/manager types with no rendering
of their own, so Reduce Motion, Increase Contrast, and Differentiate Without
Color have nothing in these three files to apply to.

## Feature Flags

Not applicable: none of the three files reads a feature flag or build
configuration switch.

## Analytics

Not applicable: none of the three files calls an analytics or
event-tracking API.

## Privacy

Not applicable: none of the three files reads, stores, or transmits a token,
credential, or other secret. The only data they hold is local filesystem
paths (`FileBrowserDirectories`, `FileBrowserRestorationState`) and git/IDE
metadata about those same paths (`FileTreeManager`), all of it already
visible to the user in their own checkout, and none of the three files makes
a network call.

## Logging

Not applicable: none of `FileBrowserDirectories.swift`,
`FileBrowserRestorationState.swift`, or `FileTreeManager.swift` calls
`os.Logger`, `print`, or any other logging API directly. Logging for this
subsystem is performed entirely by the delegated `DirectoryWatchCoordinator`,
`GitStatusProvider`, and `IDEDetector` helpers, each of which conforms to
`Loggable` on its own — not by the three types this recipe specifies.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`separation-of-concerns` passes: `FileTreeManager` only orchestrates,
delegating directory scanning/watching to `DirectoryWatchCoordinator`, git
overlay to `GitStatusProvider`, and IDE detection to `IDEDetector`, while
`FileBrowserDirectories` and `FileBrowserRestorationState` are each a single,
independent model. `unit-test-coverage` is partial: `FileBrowserRestorationStateTests`
covers `FileBrowserRestorationState` directly and `FileTreeManagerInjectedProviderTests`
covers `FileTreeManager`'s dependency-injection behavior, but no test file
exercises `FileBrowserDirectories`' `add`/`remove`/`normalize`/
`root(containing:)` methods directly, nor `FileTreeManager`'s debounce or
`apply(_:)` behavior. `explicit-error-handling` is partial: `GitStatusRefreshResult.unavailable`
is an explicit, named failure case, but the two races recorded as `NEEDS
REVIEW` above show that a dropped or superseded result currently produces no
signal of any kind. `state-recovery` passes: `FileBrowserRestorationState`
exists specifically so a host can persist and restore disclosure/selection
across a relaunch. `idempotent-operations` passes: `FileBrowserRestorationState.setExpanded`/
`setSelectedPath` and `FileBrowserDirectories.normalize`/`replaceAdditional`
all guard against reporting or reassigning when nothing actually changed.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
