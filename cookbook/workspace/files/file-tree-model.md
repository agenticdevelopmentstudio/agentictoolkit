---
id: 1b64553a-ab58-4154-b9d5-30f34eb33caf
title: File Tree Model
domain: agentictoolkit://cookbook/workspace/files/file-tree-model
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A file-tree model layer — lazy, one-level directory reads, identity-preserving
  merges, and a file-system watcher that keeps the tree in sync with on-disk changes.
platforms:
- swift
- macos
tags:
- file-browser
- file-system
- model
- concurrency
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
related:
- agentictoolkit://cookbook/workspace/files/file-tree-view
- agentictoolkit://cookbook/workspace/files/file-browser-view
references:
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/DirectoryWatchCoordinator.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/FileSystemWatcher.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/FileTreeConfig.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/FileTreeNode.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/FileBrowser/DirectoryWatchCoordinatorTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/FileBrowser/FileTreeNodeTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# File Tree Model

## Overview

This is a **logic** component — no visual surface — the file tree's model
layer, made up of four parts: a configuration value (a passive, immutable
set of options), a tree node (representing one file or directory), a
file-system watcher (a thin wrapper around the platform's native
file-change notifications), and a coordinator (the state holder that owns
the tree and drives the watcher). The coordinator's own doc comment states
its purpose directly: it "encapsulates the sync -> watch -> surgical-update
lifecycle. All filesystem I/O runs on background [threads] to avoid
blocking the UI, and a sync reads one level: the root's own entries.
Everything below that is read when it is shown." Concretely: a full sync
reads only the root directory's immediate entries and either replaces or
merges them into whatever tree is already published; starting to watch
opens a change-notification stream scoped to the root and, on every batch
of changes, re-reads just the affected directories and merges the results
in; a node's lazy children-load operation gives any node the same
one-level, read-on-demand behavior when a caller (typically a tree view)
expands it. The merge operation is the mechanism every one of these paths
funnels through to keep already-materialized node objects (and therefore
their own already-read children, and anything a tree view is holding a
reference to) alive across a re-sync rather than being silently replaced by
structurally-equal-but-distinct objects. The direct consumer of this model
is a file tree manager (out of scope for this recipe), which in turn feeds
the file tree view — see
[File Tree View](agentictoolkit://cookbook/workspace/files/file-tree-view)
and
[File Browser](agentictoolkit://cookbook/workspace/files/file-browser-view)
for how this model's `nil`-vs-empty-array `children` distinction and its
swallowed directory-read failures are consumed one layer up.

## Behavioral Requirements

- **config-value-type**: The configuration value MUST be an immutable value
  type safe to share across concurrent contexts, and all three of its
  fields (`packageExtensions`, `packageDisplayNames`,
  `customMappingsDefaultsKey`) MUST be fixed at construction, so a
  configuration value MUST NOT be mutated after construction — a caller
  that needs different values MUST construct a new configuration value.
- **config-package-extensions-default**: Construction MUST default
  `packageExtensions` to an empty set when the caller supplies none.
- **config-package-display-names-default**: Construction MUST default
  `packageDisplayNames` to an empty mapping when the caller supplies none.
- **config-custom-mappings-key-default**: Construction MUST default
  `customMappingsDefaultsKey` to the literal
  `"AgenticFileBrowser.customMappings"` when the caller supplies none.
- **config-default-static-instance**: A well-known default configuration
  value MUST exist, equal to a configuration value constructed with all
  three defaults above.
- **node-identity-by-path**: A node's identity (`id`) MUST be set to its
  full filesystem path — never a generated identifier or any other derived
  value.
- **node-display-name**: A node's display name (`name`) MUST be set to the
  final component of its filesystem path.
- **node-directory-flag-trusted**: Node construction MUST accept the
  `isDirectory` flag exactly as the caller supplies it and MUST NOT verify
  it against the file system at construction time; a caller-supplied
  `isDirectory` value that disagrees with what is actually on disk is not
  detected or corrected.
- **node-package-detection**: A node's `isPackage` MUST be `true` if and
  only if the configured `packageExtensions` contains the node's path
  extension (a case-sensitive set-membership test), regardless of the
  node's `isDirectory` value.
- **node-attribute-read-tolerant**: Node construction MUST read `fileSize`
  and `modificationDate` via a best-effort file-attribute lookup, and MUST
  set both to `nil` — raising no error and logging nothing — when that
  lookup fails (for example a permission-denied or already-deleted file) or
  when the corresponding attribute is absent or not of the expected type.
- **node-file-size-directories-nil**: A node's `fileSize` MUST always be
  `nil` for a node whose `isDirectory` is `true`, independent of whether
  directory size attributes could be read.
- **node-children-shape-file-or-package**: A node's `children` MUST be
  `nil` for any node whose `isDirectory` is `false` or whose `isPackage` is
  `true`.
- **node-children-shape-unopened-directory**: Node construction MUST set
  `children` to an empty array — not `nil` — for a directory node (not a
  package) constructed without eagerly loading its children, so that an
  unopened, expandable directory is distinguishable from a leaf.
- **node-children-shape-eager-directory**: Node construction MUST set
  `children` directly to the result of the one-level directory read
  operation for a directory node (not a package) constructed to eagerly
  load its children, including leaving `children` as an empty array — not
  `nil` — when that directory turns out to have no visible entries; this
  diverges from the lazy children-load operation's empty-to-`nil`
  conversion (see **node-load-children-if-needed-empty-collapse**).
- **node-children-loaded-flag-eager**: A node's `childrenLoaded` MUST be
  `true` immediately when it is constructed with its children eagerly
  loaded, and MUST remain `false` when constructed without eager loading.
- **node-load-children-if-needed-guard**: The lazy children-load operation
  MUST return immediately, performing no file-system access, when
  `isDirectory` is `false`, when `isPackage` is `true`, or when
  `childrenLoaded` is already `true`.
- **node-load-children-if-needed-flag-before-read**: The lazy children-load
  operation MUST set `childrenLoaded = true` before dispatching its
  background read, not after the read completes, so that two calls to it on
  the same node in quick succession MUST result in at most one background
  read of that directory.
- **node-load-children-if-needed-background-queue**: The lazy children-load
  operation MUST perform its directory read, via the one-level directory
  read operation, on a background thread, never on the calling thread (see
  Platform Notes for the mechanism used on Apple platforms).
- **node-load-children-if-needed-empty-collapse**: The lazy children-load
  operation MUST assign the freshly-read result to `children` as `nil` when
  the read returns an empty array, and as the array itself otherwise — it
  MUST NOT leave `children` as a non-nil empty array.
- **node-load-children-if-needed-safe-publish**: The lazy children-load
  operation MUST publish the updated `children` value back on the UI
  thread, and MUST silently skip that assignment if the node has already
  been torn down before the background read completes.
- **node-load-children-if-needed-ui-thread-only**: The lazy children-load
  operation MUST be usable only on the UI thread, so every call to it MUST
  originate there (see Platform Notes for the mechanism used on Apple
  platforms).
- **node-should-ignore-glob-match**: The ignore-pattern check MUST return
  `true` if and only if the filename matches at least one pattern in
  `patterns` via shell-style glob matching, and MUST return `false` when
  `patterns` is empty.
- **node-load-children-ds-store-exclusion**: The one-level directory read
  operation MUST unconditionally exclude any entry named exactly
  `.DS_Store`, independent of `ignorePatterns`.
- **node-load-children-hidden-files-included**: The one-level directory
  read operation MUST NOT exclude hidden entries by default, so dotfiles
  other than `.DS_Store` (for example `.claude`, `.git`, `.gitignore`) MUST
  be included unless a caller-supplied `ignorePatterns` entry matches them.
- **node-load-children-read-failure-empty**: The one-level directory read
  operation MUST return an empty array, raising or logging no error, when
  reading the directory's contents fails.
- **node-load-children-directory-detection-fallback**: The one-level
  directory read operation MUST treat a child whose directory-type resource
  value cannot be read as a file (`isDirectory: false`), never as a
  directory.
- **node-load-children-recursion-depth**: The one-level directory read
  operation MUST construct every child without eagerly loading its own
  children, so one call MUST read exactly one directory level and MUST NOT
  recurse into subdirectories.
- **node-load-children-sort-order**: The one-level directory read operation
  MUST sort its result with every directory node before every file node,
  and MUST sort nodes of the same kind by `name` using a locale-aware,
  case-insensitive comparison in ascending order.
- **node-merge-identity-preservation**: The merge operation MUST, for every
  node in the fresh set whose `id` also appears among the node's current
  `children`, keep the pre-existing node instance (by reference) in the
  result rather than the corresponding instance from the fresh set.
- **node-merge-addition**: The merge operation MUST include, as the fresh
  instance itself, any node in the fresh set whose `id` does not appear in
  the current `children`.
- **node-merge-deletion**: The merge operation MUST drop from the result
  any existing child whose `id` does not appear in the fresh set.
- **node-merge-order-follows-fresh**: The merge operation MUST order its
  result according to the fresh set's order, not the previous `children`'s
  order.
- **node-equality-by-id-only**: Node equality MUST compare only `id` (the
  filesystem path); it MUST NOT consider `children`, `gitStatus`,
  `fileSize`, `modificationDate`, or any other stored property.
- **node-hash-by-id-only**: A node's hash MUST combine only `id` into the
  hash value.
- **node-git-status-external**: A node's `gitStatus` MUST be a public,
  settable property that none of this model's own operations ever assigns;
  it exists purely as a hook a caller outside this model sets.
- **node-icon-package**: A node's icon identifier MUST resolve to the
  package icon whenever `isPackage` is `true`, regardless of `isDirectory`.
- **node-icon-directory-special-names**: A node's icon identifier MUST
  resolve to the AI-assistant-directory icon for a directory named exactly
  `.claude`, the version-control-directory icon for one named exactly
  `.git`, the source-directory icon for one named `Sources`, `Source`, or
  `src`, and the test-directory icon for one named `Tests`, `test`, or
  `tests`.
- **node-icon-directory-dotfile-default**: A node's icon identifier MUST
  resolve to the hidden-configuration-directory icon for any other
  directory whose name starts with `"."`, and to the generic directory icon
  for every remaining directory.
- **node-icon-file-custom-mapping-priority**: A node's icon identifier for
  a file MUST consult the custom file-type mapping table, keyed on the
  lowercased path extension, before any other icon source, and MUST use
  that mapping's own icon identifier when one is found for a non-empty
  extension.
- **node-icon-file-builtin-fallback**: A node's icon identifier for a file
  with no custom mapping MUST use the platform's built-in icon lookup,
  keyed on the lowercased path extension, and MUST fall back to the
  generic document icon when that also returns nothing.
- **node-max-display-width-formula**: The maximum-display-width calculation
  MUST compute a node's own width as `baseWidth + (depth * indentPerLevel) +
  (name.count * characterWidth)`, using the defaults `characterWidth: 7.5`,
  `indentPerLevel: 20.0`, `baseWidth: 70.0` when the caller supplies none.
- **node-max-display-width-recursion**: The maximum-display-width
  calculation MUST return its own width unchanged when `children` is `nil`,
  and otherwise MUST return the greater of its own width and the maximum
  width returned by recursing into each child one level deeper.
- **node-max-display-width-unmaterialized-children**: The
  maximum-display-width calculation MUST compute its result only from
  nodes already materialized in memory; an unopened directory
  (`children == []`) MUST contribute no width from its own on-disk
  descendants, since none has been read yet.
- **watcher-caller-must-serialize-access**: The watcher MUST be safe to
  pass across concurrent contexts without the platform independently
  verifying its internal thread safety; callers are trusted to serialize
  their own access to start/stop.
- **watcher-exclusion-prefix-match**: The exclusion check MUST return
  `true` for a path if and only if the path equals a prefix in `prefixes`
  exactly, or starts with that prefix followed by `"/"`; it MUST NOT use a
  bare prefix match without that separator.
- **watcher-start-idempotent**: Start MUST do nothing — create no new
  stream, install no new callback — when the watcher already has a live
  stream.
- **watcher-create-failure-retryable**: Start MUST log an error and
  return, leaving the watcher with no live stream, when native
  stream creation fails; because no stream is left live, a later call to
  start MUST attempt creation again.
- **watcher-callback-path-filtering**: The change-notification callback
  MUST filter the reported paths through the exclusion check against
  `excludedPrefixes` before invoking the handler, and MUST NOT invoke the
  handler at all when every reported path is excluded.
- **watcher-callback-main-thread-dispatch**: The change-notification
  callback MUST invoke the handler on the UI thread, regardless of which
  thread the underlying notification mechanism itself delivered the event
  on.
- **watcher-stream-configuration**: Start MUST create the change-notification
  stream to report future events only (no historical replay), with a
  latency of `0.5` seconds, configured for per-file-level event granularity
  (see Platform Notes for the exact mechanism used on Apple platforms).
- **watcher-stop-teardown**: Stop MUST tear down the current stream (stop
  it, invalidate it, and release its resources), then clear the watcher's
  stream reference; it MUST do nothing when there is no live stream.
- **watcher-deinit-safety-net**: The watcher MUST tear down its stream when
  it is torn down, so a watcher discarded without an explicit stop call
  MUST still tear down its underlying change-notification stream.
- **coordinator-fixed-construction-config**: The coordinator's `rootURL`,
  `excludedPrefixes`, and `config` MUST be set once at construction and
  MUST NOT change afterward; the coordinator MUST be usable only on the UI
  thread (see Platform Notes for the mechanism used on Apple platforms).
- **coordinator-ignore-patterns-mutable**: `ignorePatterns` MUST be a
  public, mutable property that a caller MAY change at any time after
  construction, independently of `rootURL`, `excludedPrefixes`, or `config`.
- **coordinator-full-sync-one-level**: A full sync MUST read only the root
  directory's own immediate entries (via an eager node construction); it
  MUST NOT recursively read any directory below the root.
- **coordinator-full-sync-background-io**: A full sync MUST perform its
  directory read on a background thread, and MUST set `isSyncing = true`
  before dispatching that read and `isSyncing = false` only after the
  result has been applied on the UI thread.
- **coordinator-full-sync-merge-vs-replace**: A full sync MUST call the
  merge operation on the current root node — keeping that root node
  instance and reusing already-read descendant node instances — when a
  root node already exists and its location equals `rootURL`; it MUST
  replace the root node outright with the freshly-built tree only when no
  root node exists yet, or the existing one's location differs from
  `rootURL`.
- **coordinator-full-sync-completion-signal**: A full sync MUST invoke the
  registered change callback and log an info message naming the root
  directory's own name, on the UI thread, only after `isSyncing` has been
  set back to `false`.
- **coordinator-start-watching-registration**: Start watching MUST store
  the supplied closure as the registered change callback, construct a
  watcher for `rootURL` and `excludedPrefixes`, and start it; its
  change-handling closure MUST re-enter the UI thread before calling the
  change-handling routine.
- **coordinator-stop-watching-teardown**: Stop watching MUST stop the
  current watcher and clear the coordinator's stored watcher reference.
- **coordinator-handle-changes-pre-sync-guard**: The change-handling
  routine MUST return immediately, without touching `isSyncing`, when the
  root node is still `nil` — a change delivered before the first full sync
  has published a tree is already covered by that pending sync.
- **coordinator-handle-changes-affected-directories**: The change-handling
  routine MUST compute the set of affected directories as the distinct
  parent directories of every changed path.
- **coordinator-handle-changes-index-scope**: The change-handling routine
  MUST build its path-to-node index by walking only nodes already
  materialized under the root node — recursing solely through non-`nil`
  `children` arrays — and MUST drop an affected directory from the update
  set entirely when no directory node for it exists in that index; a
  change reported for a directory that has never been materialized in the
  tree MUST produce no update and no error.
- **coordinator-handle-changes-per-directory-reload**: For each affected
  directory that does have a matching node, the change-handling routine
  MUST re-read that one directory level via the one-level directory read
  operation on a background thread, then apply the result with the merge
  operation on the UI thread.
- **coordinator-handle-changes-completion-signal**: The change-handling
  routine MUST set `isSyncing = false` and invoke the registered change
  callback on the UI thread only after every affected directory's merge
  has been applied.
- **concurrent-sync-reentrancy**: NEEDS REVIEW: Not implemented in source.
  Neither a full sync nor the change-handling routine guards against being
  invoked again while a previous invocation's background read is still in
  flight — both set `isSyncing = true` unconditionally rather than
  checking it first, unlike the lazy children-load operation's explicit
  `childrenLoaded`-set-before-dispatch guard for the analogous per-node
  race — so two overlapping calls each independently dispatch their own
  background read and later apply the merge operation on the UI thread in
  whichever order their background work happens to finish, not the order
  the calls (or the underlying file-system events) occurred in; this would
  be settled by either a source change that coalesces or serializes
  overlapping syncs, or a test demonstrating the current
  last-completion-wins ordering is acceptable, and neither exists in the
  given sources.

## Appearance

Not applicable — this is the file browser's logic/model layer, not a
visual component.

## States

Not applicable — this is the file browser's logic/model layer, not a
visual component. Its runtime state (`isSyncing`, `childrenLoaded`, the
sync -> watch -> surgical-update lifecycle) is captured under Behavioral
Requirements above, not as a visual-state table.

## Accessibility

Not applicable — this is the file browser's logic/model layer, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| FSM-001 | config-package-extensions-default, config-package-display-names-default, config-custom-mappings-key-default, config-default-static-instance | Construct the configuration value with no arguments, and separately read the well-known default configuration value | Both produce an empty `packageExtensions`, an empty `packageDisplayNames`, and `customMappingsDefaultsKey == "AgenticFileBrowser.customMappings"` — traced directly to source; not exercised by a given test |
| FSM-002 | config-value-type | Attempt to mutate a configuration value's `packageExtensions` after construction | Fails to compile — `packageExtensions` is fixed at construction on an immutable value type |
| FSM-003 | node-identity-by-path, node-display-name | Construct a node for the file location `/tmp/a/b.txt`, not a directory | `node.id == "/tmp/a/b.txt"`, `node.name == "b.txt"` — traced directly to source; not exercised by a given test |
| FSM-004 | node-directory-flag-trusted | Construct a node for an actual plain file's location, but pass `isDirectory: true` and no eager load | `node.isDirectory == true` and `node.children == []`, exactly as if the location really were a directory — construction performs no on-disk verification |
| FSM-005 | node-package-detection | Construct a node for the location `/tmp/some.catnip-proj`, a directory, no eager load, with an empty `packageExtensions` | `node.isPackage == false` — confirmed by the model's test suite |
| FSM-006 | node-package-detection | Same construction, with `packageExtensions` containing `"catnip-proj"` | `node.isPackage == true` — confirmed by the model's test suite |
| FSM-007 | node-package-detection | Construct a node for the location `/tmp/some.txt`, not a directory, no eager load, with `packageExtensions` containing `"catnip-proj"` | `node.isPackage == false` — confirmed by the model's test suite |
| FSM-008 | node-attribute-read-tolerant, node-file-size-directories-nil | Construct a node for an actual directory, and separately a node for a file location that does not exist | Directory node's `fileSize == nil`; nonexistent-file node's `fileSize == nil` and `modificationDate == nil`, with no thrown error surfaced |
| FSM-009 | node-children-shape-file-or-package | Construct a node for a `.catnip-proj` package directory and a node for a plain file | Both have `children == nil` |
| FSM-010 | node-children-shape-unopened-directory, node-children-loaded-flag-eager | Construct a node for a directory, no eager load | `children == []` and `childrenLoaded == false` |
| FSM-011 | node-children-shape-eager-directory, node-children-loaded-flag-eager | Construct a node for an empty, readable directory, with eager load | `children == []` (not `nil`) and `childrenLoaded == true` — diverges from the lazy path's nil-collapse |
| FSM-012 | node-load-children-if-needed-guard | Run the lazy children-load operation on a file node, on a package node, and again on a directory node whose `childrenLoaded` is already `true` | No background read starts in any of the three cases |
| FSM-013 | node-load-children-if-needed-flag-before-read, node-load-children-if-needed-background-queue, node-load-children-if-needed-ui-thread-only | Run the lazy children-load operation twice, synchronously back-to-back on the UI thread, on the same unopened directory node | `childrenLoaded` is already `true` when the second call is made, so only one background read is issued — the precondition the coordinator's own test suite's folder-opening helper relies on |
| FSM-014 | node-load-children-if-needed-empty-collapse | Run the lazy children-load operation on a directory node for a genuinely empty, readable directory | `node.children` becomes `nil`, not `[]` — traced to the empty-collapse behavior described above |
| FSM-015 | node-load-children-if-needed-safe-publish | Tear down a node (drop the last reference to it) after starting the lazy children-load operation but before its background read completes | The later publish of the read result is skipped with no crash and no effect |
| FSM-016 | node-should-ignore-glob-match, node-load-children-ds-store-exclusion, node-load-children-hidden-files-included | Run the one-level directory read operation with no ignore patterns on a directory containing `.DS_Store`, `.gitignore`, and `a.txt` | Result excludes `.DS_Store` but includes `.gitignore` and `a.txt` |
| FSM-017 | node-should-ignore-glob-match | Run the one-level directory read operation with the ignore pattern `"*.log"` on a directory containing `a.txt` and `debug.log` | Result excludes `debug.log`, includes `a.txt` |
| FSM-018 | node-load-children-read-failure-empty | Run the one-level directory read operation on a directory the caller has no read permission for | Result is `[]` — indistinguishable in the return value from a genuinely empty, readable directory |
| FSM-019 | node-load-children-directory-detection-fallback | Run the one-level directory read operation where one entry's directory-type resource value cannot be read (for example a symlink to a nonexistent target) | That entry's node is constructed with `isDirectory: false` |
| FSM-020 | node-load-children-recursion-depth | Run the one-level directory read operation on a root containing one subdirectory that itself contains a file | The returned subdirectory node's own `children == []` (unopened) — the file one level further down is absent from the result |
| FSM-021 | node-load-children-sort-order | Run the one-level directory read operation on a directory containing files `"b.txt"`, `"A.txt"` and subdirectory `"Zdir"` | Result orders `["Zdir", "A.txt", "b.txt"]` — directories first, then case-insensitive alphabetical |
| FSM-022 | node-merge-identity-preservation, node-merge-order-follows-fresh | Run the merge operation with a fresh set that lists the same `id`s as the current `children` but in reverse order | Result order matches the fresh set's order, and each element is the same instance as the corresponding pre-existing one |
| FSM-023 | node-merge-addition, node-merge-deletion | Run the merge operation with a fresh set that adds one `id` absent from the current `children` and omits one `id` that is present | Result contains the new `id`'s fresh instance and drops the omitted `id` entirely |
| FSM-024 | node-equality-by-id-only, node-hash-by-id-only | Compare two nodes constructed for the same location but with different `gitStatus`/`fileSize` values | Equal, and both hash to the same value |
| FSM-025 | node-git-status-external | Read a node's `gitStatus` immediately after construction, having exercised only this model's own code paths | Always `nil`, since none of this model's own operations ever assigns it |
| FSM-026 | node-icon-package, node-icon-directory-special-names, node-icon-directory-dotfile-default | Resolve the icon identifier for a `.catnip-proj` package, a `.claude` directory, a `.git` directory, a `Sources` directory, a `Tests` directory, a `.env` directory, and a plain `Notes` directory | The package icon, the AI-assistant-directory icon, the version-control-directory icon, the source-directory icon, the test-directory icon, the hidden-configuration-directory icon, and the generic directory icon respectively |
| FSM-027 | node-icon-file-custom-mapping-priority, node-icon-file-builtin-fallback | Resolve the icon identifier for a file whose extension has a custom mapping entry, one whose extension only the built-in icon lookup recognizes, and one with an unrecognized extension | The custom mapping's own icon identifier, the built-in icon identifier, and the generic document icon respectively |
| FSM-028 | node-max-display-width-formula, node-max-display-width-recursion | Run the maximum-display-width calculation on a leaf node named `"a.txt"` at depth 0 with default parameters | `70.0 + 0 + (5 * 7.5) == 107.5` |
| FSM-029 | node-max-display-width-recursion, node-max-display-width-unmaterialized-children | Run the maximum-display-width calculation on a directory whose one loaded child has a longer name than the directory itself, compared against the same directory before that child was ever loaded (`children == []`) | Loaded case returns the child's larger width; unloaded case returns only the directory's own width |
| FSM-030 | watcher-caller-must-serialize-access | Pass a watcher instance across a concurrent-context boundary requiring safe cross-context sharing | Compiles, because the watcher declares itself safe for that sharing — a genuinely unsafe type would fail to compile there |
| FSM-031 | watcher-exclusion-prefix-match | Run the exclusion check for `"/root/.git"` against the prefix list `["/root/.git"]`, and separately for `"/root/.gitignore"` against the same list | First returns `true` (exact match); second returns `false` — `.gitignore` is not inside `.git/` — traced to the source's own documented example |
| FSM-032 | watcher-start-idempotent | Call start twice in succession on the same watcher | Only the first call creates a stream; the second is a no-op because a stream is already live |
| FSM-033 | watcher-create-failure-retryable | Cause native stream creation to fail (for example an invalid path), then call start again | First call logs an error and leaves no live stream; second call attempts creation again |
| FSM-034 | watcher-callback-path-filtering, watcher-callback-main-thread-dispatch | A change-notification callback fires with every reported path inside an excluded prefix; a second fires with at least one surviving path | First: the handler is never invoked. Second: the handler runs on the UI thread |
| FSM-035 | watcher-stream-configuration | Inspect the arguments passed to native stream creation | Configured for future events only, a latency of `0.5` seconds, and per-file-level event granularity (see Platform Notes for the exact flags used on Apple platforms) |
| FSM-036 | watcher-stop-teardown, watcher-deinit-safety-net | Call stop on a started watcher; separately, let a started watcher be discarded without calling stop | Both paths tear down the stream (stop, invalidate, release) and leave no live stream |
| FSM-037 | coordinator-fixed-construction-config, coordinator-ignore-patterns-mutable | Construct a coordinator, then set `ignorePatterns = ["*.log"]` after construction | `rootURL`/`excludedPrefixes`/`config` are unchanged and have no setter; `ignorePatterns` accepts the new value |
| FSM-038 | coordinator-full-sync-one-level, node-load-children-sort-order | Run a full sync on a fresh directory containing one subdirectory `"nested"` (itself containing `"file.swift"`) | The root node's location matches the synced directory; its children map to `["nested"]` only — confirmed by the coordinator's own test suite |
| FSM-039 | coordinator-full-sync-background-io | Call a full sync and read `isSyncing` synchronously right after the call returns, before the background read completes | `isSyncing == true` — matches the precondition the coordinator's own test suite's wait-for-completion helper relies on |
| FSM-040 | coordinator-full-sync-merge-vs-replace | Call a full sync twice on the same coordinator/root with no filesystem change between calls | The root node is the same instance as the first sync's, and its first child is the same instance as the first sync's — confirmed by the coordinator's own test suite |
| FSM-041 | coordinator-full-sync-merge-vs-replace, node-merge-identity-preservation | After a first sync, run the lazy children-load operation on the `"nested"` child (reading its `"file.swift"` entry), then call a full sync again | `"nested"`'s children still map to `["file.swift"]` after the second sync — confirmed by the coordinator's own test suite |
| FSM-042 | coordinator-full-sync-merge-vs-replace | Set the coordinator's root node to a node for a different location (`"elsewhere"`) before calling a full sync | The root node's location matches the coordinator's own `rootURL`, not `"elsewhere"` — confirmed by the coordinator's own test suite |
| FSM-043 | coordinator-full-sync-completion-signal | Register a change callback via start watching, then call a full sync directly | The callback fires exactly once, after `isSyncing` has already returned to `false` |
| FSM-044 | coordinator-start-watching-registration, coordinator-stop-watching-teardown | Call start watching then stop watching | A watcher is created and started, then stopped and released; a later filesystem change produces no callback |
| FSM-045 | coordinator-handle-changes-pre-sync-guard | Construct a coordinator, start watching, and trigger a filesystem change before ever calling a full sync | The change-handling routine returns immediately; `isSyncing` remains `false`; no attempt is made to index a `nil` root node |
| FSM-046 | coordinator-handle-changes-affected-directories, coordinator-handle-changes-index-scope | After a full sync, a change is reported for `"nested/inner/new.txt"` where `"nested/inner"` was never opened | No update is applied to the tree — `"nested/inner"` has no node in the path-to-node index — and no error is raised |
| FSM-047 | coordinator-handle-changes-per-directory-reload, coordinator-handle-changes-completion-signal | After a full sync and opening `"nested"` (via the lazy children-load operation), a change is reported for a new file added directly inside `"nested"` | `"nested"`'s children gains the new file via the merge operation, and the registered change callback fires once `isSyncing` returns to `false` |

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
- **Directory with a very large number of entries.** The one-level
  directory read operation MUST read and materialize an entire directory
  level in one call, with no pagination, batching, or entry-count limit; a
  directory with tens of thousands of entries is read in full on first
  expansion.
- **Very deep, fully-loaded tree.** The maximum-display-width calculation's
  recursion has no explicit depth cap; it MUST complete via one recursive
  step per already-loaded tree level, so its safety against unbounded
  recursion depends entirely on how many levels a caller has actually
  opened, not on any limit the source imposes
  (`node-max-display-width-recursion`).
- **Concurrent expansion requests on the same node.** Two near-simultaneous
  calls to the lazy children-load operation on the same directory node MUST
  result in exactly one background read, because `childrenLoaded` is set to
  `true` synchronously before the first call ever dispatches
  (`node-load-children-if-needed-flag-before-read`).
- **Overlapping syncs or change batches.** A full sync and the
  change-handling routine MUST NOT be assumed serialized against themselves
  or each other — see the open question on `concurrent-sync-reentrancy` in
  Behavioral Requirements.
- **Changes coalesced within the watcher's latency window.** Multiple
  filesystem changes occurring within the watcher's configured
  `0.5`-second latency MUST be delivered to the coordinator as a single
  batch of changed paths, not as separate callbacks
  (`watcher-stream-configuration`).
- **Native stream-creation failure.** Start MUST log an error and leave
  the coordinator with no live watcher rather than crashing; the root
  directory continues to be sync-able via a full sync, and a later call to
  start MUST retry creation (`watcher-create-failure-retryable`).
- **Permission-denied directory.** A directory whose contents cannot be
  read (for example, permission denied) MUST be rendered identically to a
  genuinely empty directory, because the one-level directory read operation
  swallows a read failure into an empty array before it is visible to any
  caller — the same swallowing this model's own consumer, the file tree
  view, already treats as a fact rather than a distinct error state
  (`node-load-children-read-failure-empty`).
- **File deleted between listing and attribute read.** A best-effort
  attribute lookup failing on a since-deleted file MUST result in
  `fileSize == nil` and `modificationDate == nil` for that node, with no
  error raised (`node-attribute-read-tolerant`).
- **Change reported for a directory deleted before its reload runs.** When
  the change-handling routine's background reload targets a directory that
  has since been deleted, the one-level directory read operation MUST
  return `[]` for it (the same swallowed-failure path above), and the
  subsequent merge with an empty fresh set MUST drop every one of that
  node's previously-tracked children — the node itself is not removed from
  its own parent until that parent's own next reload notices it is gone.
- **No cancellation or timeout.** None of the full sync's, the
  change-handling routine's, or the lazy children-load operation's
  dispatched background work exposes a cancellation token or timeout; once
  a background read has started, that read MUST run to completion.
- **Offline or disconnected state.** Not applicable: this model operates on
  the local file system and local change notifications only; none of it
  makes a network call, so there is no connectivity-loss behavior to
  define.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | file location | required, set at construction | The directory this coordinator syncs and watches. |
| `config` | configuration value | required; caller may pass the well-known default | Opaque-package extensions/display names and the storage key for custom file-type mappings — threaded through but not read by this model beyond `packageExtensions`. |
| `excludedPrefixes` | list of path prefixes | required, set at construction | Absolute path prefixes; change notifications at or under any of them are dropped by the exclusion check before the change-handling routine ever runs. |
| `ignorePatterns` | list of glob patterns | `[]` | Wildcard filename patterns filtered out of every directory listing; settable at any time through the coordinator's public property. |
| `packageExtensions` | set of extensions | `[]` (via the configuration value) | Extensions whose matching directories are treated as opaque, single-item packages. |
| `packageDisplayNames` | mapping of extension to display name | `[:]` (via the configuration value) | Passed through the configuration value; not read by this model itself. |
| `customMappingsDefaultsKey` | string | `"AgenticFileBrowser.customMappings"` (via the configuration value) | Storage key naming; not read by this model itself — owned by the custom file-type mapping table. |
| `onChange` (start watching) | optional no-argument callback | `nil` | Callback the coordinator invokes after every applied sync or watched change. |
| `url` / `isDirectory` / eager-load flag (node construction) | file location / boolean / boolean | eager-load flag defaults to `false` | Per-node construction arguments the coordinator and the one-level directory read operation supply. |

## Deep Linking

Not applicable: this model defines no URL route, no inbound app-URL scheme,
and no navigable destination — every location it touches (a node's `url`,
the coordinator's `rootURL`) is a plain filesystem path, not a link into
the app.

## Localization

Not applicable: this model contains no user-facing string literal. Its
only string-valued output is a node's icon identifier (a symbolic name, not
displayed text) and log messages, neither of which is localized text shown
to a user.

## Accessibility Options

Not applicable: this model renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — there is no UI here to adapt.

## Feature Flags

Not applicable: this model contains no feature-flag or remote-config check
of any kind; behavior is governed entirely by constructor arguments and the
caller-supplied `ignorePatterns`/`excludedPrefixes`.

## Analytics

Not applicable: this model emits no analytics or event-tracking call of any
kind.

## Privacy

- **Data collected**: File and directory paths, names, extensions, sizes,
  and modification dates read from the local file system under `rootURL`,
  plus whatever `gitStatus` an external caller assigns
  (`node-git-status-external`). Nothing is collected beyond what already
  exists on the user's own disk.
- **Storage**: This model persists nothing itself; the tree is held only in
  memory for the lifetime of the coordinator and its nodes. The
  configuration value's `customMappingsDefaultsKey` names a storage key,
  but reading or writing that key is owned by a different component (the
  custom file-type mapping table), not this model.
- **Transmission**: None. This model makes no network call.
- **Retention**: In-memory only, for as long as the coordinator/node objects
  live; nothing is written to disk by this model.
- **Log visibility**: The watcher logs its root path with an explicit
  visibility override that keeps it un-redacted, rather than the platform
  logger's default redaction for interpolated values — a deliberate choice
  to keep the watched root's path visible in log output rather than
  redacted (see Design Decisions; see Platform Notes for the exact
  mechanism used on Apple platforms).

## Logging

Subsystem: the host app's own bundle identifier | Category: the
coordinator or the watcher, one category per logging type, derived from the
type's own name.

| Event | Level | Message | Category |
|-------|-------|---------|----------|
| Sync applied | info | `Sync complete for <rootURL.lastPathComponent>` | coordinator |
| Change batch received | debug | `FS changes: <count> path(s) in <rootURL.lastPathComponent>` | coordinator |
| Watcher started | info | `Started file system watcher for <rootPath>` (path logged with visibility override) | watcher |
| Watcher stopped | info | `Stopped file system watcher` | watcher |
| Stream creation failed | error | `Failed to create FSEvent stream for <rootPath>` | watcher |

## Platform Notes

- **SwiftUI**: None of these four files imports SwiftUI, but
  `DirectoryWatchCoordinator` and `FileTreeNode`'s `ObservableObject` +
  `@Published` conformances are consumable directly by a SwiftUI view via
  `@StateObject`/`@ObservedObject` with no adapter layer. A SwiftUI port
  would keep this model layer unchanged and bind a `List` or `OutlineGroup`
  to `rootNode`'s `children`, calling `loadChildrenIfNeeded()` from
  `.onAppear` or the row's disclosure action, in place of the AppKit
  `NSOutlineView` consumer described in
  [File Tree View](agentictoolkit://cookbook/workspace/files/file-tree-view).
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
  (see [File Tree View](agentictoolkit://cookbook/workspace/files/file-tree-view)).
  An iOS port needs a different watch mechanism entirely — a
  `DispatchSource` file-descriptor watch or a polling timer — since
  `FSEventStreamCreate` is unavailable there.
  Swift/AppKit mechanism detail folded in from the normative text above:
  `FileTreeConfig` is declared a `Sendable struct` with three `let` stored
  properties, so its immutability is compiler-enforced rather than merely
  documented. `loadChildrenIfNeeded()` is declared `@MainActor`, its
  background read runs on `DispatchQueue.global(qos: .userInitiated)`, and
  its result is published back via `DispatchQueue.main.async` with a
  `self?.children = ...` guard that no-ops if the node has already been
  deallocated; `DirectoryWatchCoordinator` itself is declared `@MainActor`,
  with `rootURL`/`excludedPrefixes`/`config` as `let` properties fixed at
  `init`. `FileSystemWatcher` is declared
  `final class FileSystemWatcher: @unchecked Sendable`, so the compiler does
  not independently verify its internal thread safety — callers are trusted
  to serialize their own access to `start()`/`stop()`. The ignore-pattern
  check (`shouldIgnore(_:patterns:)`) is implemented with POSIX `fnmatch`
  called with flags `0`. Icon identifiers are SF Symbol names:
  `"shippingbox.fill"` (package), `"brain"` (`.claude`),
  `"arrow.triangle.branch"` (`.git`), `"folder.fill.badge.gearshape"`
  (`Sources`/`Source`/`src`), `"folder.fill.badge.questionmark"`
  (`Tests`/`test`/`tests`), `"folder.badge.gearshape"` (other dotfile
  directories), `"folder.fill"` (generic directory), `"doc"` (generic
  document fallback), sourced from `CustomFileTypeMappings.mapping(for:)`
  and `FileTypeIcons.builtInIcon(for:)`. The watcher creates its FSEvents
  stream with `kFSEventStreamEventIdSinceNow`, a latency of `0.5` seconds,
  and flags `kFSEventStreamCreateFlagFileEvents |
  kFSEventStreamCreateFlagUseCFTypes`; its callback dispatches to the
  handler via `DispatchQueue.main.async` and force-casts `eventPaths` via
  `unsafeBitCast(eventPaths, to: NSArray.self) as! [String]` (with an inline
  `swiftlint:disable:this force_cast` comment — see Design Decisions), a
  cast whose safety depends entirely on `kFSEventStreamCreateFlagUseCFTypes`
  having been passed to `FSEventStreamCreate`. `handleChanges(_:)` computes
  affected directories via `(path as NSString).deletingLastPathComponent`.
  Logging goes through the `Loggable` protocol, whose `category` is derived
  from the conforming type's own name and whose subsystem is
  `Bundle.main.bundleIdentifier`; `FileSystemWatcher.start()` logs its root
  path with an explicit `privacy: .public` annotation
  (`logger.info("Started file system watcher for \(self.rootPath, privacy: .public)")`),
  overriding `os.log`'s default private-by-default redaction for
  string-interpolated values.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileSystem/` |

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
- **Decision**: On Apple platforms, the FSEvents callback force-casts
  `eventPaths` via `unsafeBitCast(eventPaths, to: NSArray.self) as!
  [String]`, with an inline `swiftlint:disable:this force_cast` comment.
  **Rationale**: Not stated beyond the disable comment itself; the cast's
  safety depends entirely on `kFSEventStreamCreateFlagUseCFTypes` being
  passed to `FSEventStreamCreate` (`watcher-stream-configuration`), which
  guarantees `eventPaths` really is a `CFArray` of `CFString`s bridgeable to
  `NSArray`/`String`. This is accepted technical debt: if that flag were
  ever removed, the cast would crash rather than fail gracefully.
  **Approved**: pending
- **Decision**: On Apple platforms, `FileSystemWatcher.start()` logs the
  watched root path with an explicit `privacy: .public` annotation rather
  than `os.log`'s private-by-default redaction for interpolated values.
  **Rationale**: Not stated in a source comment. A locally-mounted project
  path is treated here as safe to surface in log output, which is a
  deliberate choice given `os.log` otherwise redacts interpolated strings by
  default.
  **Approved**: pending
- The open question on `concurrent-sync-reentrancy` (Behavioral
  Requirements) is a source-fidelity gap, not a resolved design decision:
  no rationale for the current last-completion-wins behavior exists in the
  given sources.

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [lazy-loading](agenticdevelopercookbook://compliance/performance#lazy-loading) | passed | Performance |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |

separation-of-concerns passes because these four files are pure model/logic
— `FileTreeConfig` a passive value, `FileTreeNode` a tree node, `FileSystemWatcher`
an FSEvents wrapper, `DirectoryWatchCoordinator` the orchestrator — with no
view or presentation code of any kind. unit-test-coverage is partial:
`FileTreeNodeTests` covers only package-extension detection, and
`DirectoryWatchCoordinatorTests` covers only the sync/merge-identity
lifecycle; neither `FileSystemWatcher` nor `FileTreeConfig` has a test file,
and `loadChildren`'s sorting, ignore-pattern filtering, and
`handleChanges`'s per-directory reload path are exercised by no given test.
explicit-error-handling is partial because `attributesOfItem`,
`contentsOfDirectory`, and `resourceValues` failures are all discarded via
`try?` with no propagated error and no distinguishing signal between "empty"
and "failed to read" (`node-load-children-read-failure-empty`,
`node-attribute-read-tolerant`). main-thread-freedom passes because every
filesystem read in `fullSync()`, `handleChanges(_:)`, and
`loadChildrenIfNeeded()` is explicitly dispatched to
`DispatchQueue.global(qos: .userInitiated)`, with only pointer-swap
assignments happening back on the main queue. lazy-loading passes because
`loadChildren` reads exactly one directory level per call by design, and
`loadChildrenIfNeeded()`/`childrenLoaded` gate every deeper read until a
caller actually asks for it. graceful-degradation passes because a failed
`FSEventStreamCreate` call is logged and left retryable rather than crashing
the coordinator, and an unreadable directory degrades to an empty listing
rather than propagating a fatal error.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/files/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
