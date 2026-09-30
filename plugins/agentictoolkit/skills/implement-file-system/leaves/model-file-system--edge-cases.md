<!-- leaf: implement-file-system/model-file-system--edge-cases · source: file-system-model-file-system.md -->

# File Browser FileSystem Model

**Rules** (cite as `implement-file-system/model-file-system--edge-cases#<slug>`):

- `empty-or-default-exclusion-ignore-lists` MUST — excludedPrefixes: [] and ignorePatterns: [] MUST leave the watcher watching everything under the root and the tree …
- `genuinely-empty-readable-directory` MUST — A directory with zero visible entries MUST read as [] from loadChildren, and the caller-visible children MUST then be …
- `directory-with-a-very-large-number-of-entries` MUST — loadChildren MUST read and materialize an entire directory level in one contentsOfDirectory call, with no pagination, …
- `very-deep-fully-loaded-tree` MUST — maximumDisplayWidth's recursion has no explicit depth cap; it MUST complete via one stack frame per already- loaded …
- `concurrent-expansion-requests-on-the-same-node` MUST — Two near-simultaneous calls to loadChildrenIfNeeded() on the same directory node MUST result in exactly one background …
- `overlapping-syncs-or-change-batches` MUST — fullSync() and handleChanges(_:) MUST NOT be assumed serialized against themselves or each other — see the open …
- `fs-events-coalesced-within-the-watcher-s-latency-window` MUST — Multiple filesystem changes occurring within FSEventStreamCreate's configured 0.5-second latency MUST be delivered to …
- `fseventstreamcreate-failure` MUST — start() MUST log an error and leave the coordinator with no live watcher rather than crashing; the root directory …
- `permission-denied-directory` MUST — A directory whose contents cannot be read (for example, permission denied) MUST be rendered identically to a genuinely …
- `file-deleted-between-listing-and-attribute-read` MUST — attributesOfItem failing on a since-deleted file MUST result in fileSize == nil and modificationDate == nil for that …
- `change-reported-for-a-directory-deleted-before-its-reload-runs` MUST — When handleChanges(_:)'s background reload targets a directory that has since been deleted, loadChildren MUST return [] …
- `no-cancellation-or-timeout` MUST — None of fullSync()'s, handleChanges(_:)'s, or loadChildrenIfNeeded()'s dispatched background work exposes a …

## Edge Cases

- **Empty or default exclusion/ignore lists.** `excludedPrefixes: []` and
  `ignorePatterns: []` MUST leave the watcher watching everything under the
  root and the tree hiding nothing beyond the hardcoded `.DS_Store`
  exclusion (`watcher-exclusion-prefix-match`, `node-load-children-ds-store-exclusion`).
- **Genuinely empty, readable directory.** A directory with zero visible
  entries MUST read as `[]` from `loadChildren`, and the caller-visible
  `children` MUST then be `nil` when read lazily via
  `loadChildrenIfNeeded()` but MUST remain a non-nil `[]` when read eagerly
  through `init(loadChildren: true)` — the two paths intentionally diverge
  (`node-load-children-if-needed-empty-collapse`,
  `node-children-shape-eager-directory`).
- **Directory with a very large number of entries.** `loadChildren` MUST
  read and materialize an entire directory level in one
  `contentsOfDirectory` call, with no pagination, batching, or entry-count
  limit; a directory with tens of thousands of entries is read in full on
  first expansion.
- **Very deep, fully-loaded tree.** `maximumDisplayWidth`'s recursion has no
  explicit depth cap; it MUST complete via one stack frame per already-
  loaded tree level, so its safety against stack growth depends entirely on
  how many levels a caller has actually opened, not on any limit the source
  imposes (`node-max-display-width-recursion`).
- **Concurrent expansion requests on the same node.** Two near-simultaneous
  calls to `loadChildrenIfNeeded()` on the same directory node MUST result
  in exactly one background read, because `childrenLoaded` is set to `true`
  synchronously before the first call ever dispatches
  (`node-load-children-if-needed-flag-before-read`).
- **Overlapping syncs or change batches.** `fullSync()` and
  `handleChanges(_:)` MUST NOT be assumed serialized against themselves or
  each other — see the open question on `concurrent-sync-reentrancy` in
  Behavioral Requirements.
- **FS events coalesced within the watcher's latency window.** Multiple
  filesystem changes occurring within `FSEventStreamCreate`'s configured
  `0.5`-second latency MUST be delivered to the coordinator as a single
  batch of `changedPaths`, not as separate callbacks
  (`watcher-stream-configuration`).
- **`FSEventStreamCreate` failure.** `start()` MUST log an error and leave
  the coordinator with no live watcher rather than crashing; the root
  directory continues to be sync-able via `fullSync()`, and a later
  `start()` call MUST retry creation (`watcher-create-failure-retryable`).
- **Permission-denied directory.** A directory whose contents cannot be
  read (for example, permission denied) MUST be rendered identically to a
  genuinely empty directory, because `loadChildren` swallows a
  `contentsOfDirectory` failure into an empty array before it is visible to
  any caller — the same swallowing this model's own consumer, the file tree
  outline, already treats as a fact rather than a distinct error state
  (`node-load-children-read-failure-empty`).
- **File deleted between listing and attribute read.** `attributesOfItem`
  failing on a since-deleted file MUST result in `fileSize == nil` and
  `modificationDate == nil` for that node, with no error raised
  (`node-attribute-read-tolerant`).
- **Change reported for a directory deleted before its reload runs.** When
  `handleChanges(_:)`'s background reload targets a directory that has
  since been deleted, `loadChildren` MUST return `[]` for it (the same
  swallowed-failure path above), and the subsequent `merge(children: [])`
  MUST drop every one of that node's previously-tracked children — the node
  itself is not removed from its own parent until that parent's own next
  reload notices it is gone.
- **No cancellation or timeout.** None of `fullSync()`'s,
  `handleChanges(_:)`'s, or `loadChildrenIfNeeded()`'s dispatched background
  work exposes a cancellation token or timeout; once
  `DispatchQueue.global(...).async` has been called, that read MUST run to
  completion.
- **Offline or disconnected state.** Not applicable: every one of these
  four files operates on the local file system through `FileManager` and
  local `FSEvents` only; none imports a networking API or makes a network
  call, so there is no connectivity-loss behavior to define.
