---
id: 1b64553a-ab58-4154-b9d5-30f34eb33caf
title: File Browser FileSystem Model
domain: agentictoolkit://recipes/file-system-model-file-system
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AgenticToolkit macOS's file-tree model layer — lazy directory reads, identity-preserving
  merges, and an FSEvents watcher behind DirectoryWatchCoordinator.
platforms:
- swift
- macos
tags:
- file-browser
- file-system
- model
- concurrency
- macos
depends-on:
- agenticdevelopercookbook://guidelines/implementing/concurrency/concurrency
related:
- agentictoolkit://recipes/file-tree-outline-view-controller
- agentictoolkit://recipes/file-browser-view-controller
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

# File Browser FileSystem Model

## Overview

This is a **logic** component — no visual surface — the `Model/FileSystem`
layer beneath AgenticToolkit macOS's file browser feature, made up of four
Swift files: `FileTreeConfig` (a passive configuration value), `FileTreeNode`
(a tree node representing one file or directory), `FileSystemWatcher` (a thin
`FSEvents` wrapper), and `DirectoryWatchCoordinator` (the `@MainActor`
`ObservableObject` that owns the tree and drives the watcher). The
coordinator's own doc comment states its purpose directly: it "encapsulates
the sync -> watch -> surgical-update lifecycle. All filesystem I/O runs on
background queues to avoid blocking the UI, and a sync reads one level: the
root's own entries. Everything below that is read when it is shown." Concretely:
`fullSync()` reads only the root directory's immediate entries and either
replaces or merges them into whatever tree is already published;
`startWatching(onChange:)` opens an `FSEventStreamRef` scoped to the root
and, on every batch of changes, re-reads just the affected directories and
merges the results in; `FileTreeNode.loadChildrenIfNeeded()` gives any node
the same one-level, read-on-demand behavior when a caller (typically an
outline view) expands it. `merge(children:)` is the mechanism every one of
these paths funnels through to keep already-materialized node objects (and
therefore their own already-read children, and anything an outline view is
holding a reference to) alive across a re-sync rather than being silently
replaced by structurally-equal-but-distinct objects. The direct consumer of
this model is `FileTreeManager` (out of scope for this recipe), which in
turn feeds `FileTreeOutlineViewController` — see
[File Tree Outline View Controller](agentictoolkit://recipes/file-tree-outline-view-controller)
and
[File Browser View Controller](agentictoolkit://recipes/file-browser-view-controller)
for how this model's `nil`-vs-empty-array `children` distinction and its
swallowed directory-read failures are consumed one layer up.

## Behavioral Requirements

- **config-value-type**: `FileTreeConfig` MUST be declared as a `Sendable`
  `struct`, and all three of its stored properties (`packageExtensions`,
  `packageDisplayNames`, `customMappingsDefaultsKey`) MUST be declared `let`,
  so a `FileTreeConfig` value MUST NOT be mutated after construction — a
  caller that needs different values MUST construct a new `FileTreeConfig`.
- **config-package-extensions-default**: `FileTreeConfig.init`'s
  `packageExtensions` parameter MUST default to an empty `Set<String>` when
  the caller supplies none.
- **config-package-display-names-default**: `FileTreeConfig.init`'s
  `packageDisplayNames` parameter MUST default to an empty
  `[String: String]` when the caller supplies none.
- **config-custom-mappings-key-default**: `FileTreeConfig.init`'s
  `customMappingsDefaultsKey` parameter MUST default to the literal
  `"AgenticFileBrowser.customMappings"` when the caller supplies none.
- **config-default-static-instance**: `FileTreeConfig.default` MUST be a
  `static let` equal to `FileTreeConfig()` constructed with all three
  defaults above.
- **node-identity-by-path**: `FileTreeNode.id` MUST be set to `url.path`,
  the node's full filesystem path — never a generated UUID or any other
  derived value.
- **node-display-name**: `FileTreeNode.name` MUST be set to
  `url.lastPathComponent`.
- **node-directory-flag-trusted**: `FileTreeNode.init` MUST accept the
  `isDirectory` flag exactly as the caller supplies it and MUST NOT verify
  it against the file system at construction time; a caller-supplied
  `isDirectory` value that disagrees with what is actually on disk is not
  detected or corrected.
- **node-package-detection**: `FileTreeNode.isPackage` MUST be `true` if and
  only if `packageExtensions` contains `url.pathExtension` (a case-sensitive
  set membership test), regardless of the node's `isDirectory` value.
- **node-attribute-read-tolerant**: `FileTreeNode.init` MUST read `fileSize`
  and `modificationDate` via `try? FileManager.default.attributesOfItem(atPath:)`,
  and MUST set both to `nil` — raising no error and logging nothing — when
  that call throws (for example a permission-denied or already-deleted
  file) or when the corresponding attribute key is absent or not typed as
  expected.
- **node-file-size-directories-nil**: `FileTreeNode.fileSize` MUST always be
  `nil` for a node whose `isDirectory` is `true`, independent of whether
  directory size attributes could be read.
- **node-children-shape-file-or-package**: `FileTreeNode.children` MUST be
  `nil` for any node whose `isDirectory` is `false` or whose `isPackage` is
  `true`.
- **node-children-shape-unopened-directory**: `FileTreeNode.init` MUST set
  `children` to an empty array — not `nil` — for a directory node (not a
  package) constructed with `loadChildren: false`, so that an unopened,
  expandable directory is distinguishable from a leaf.
- **node-children-shape-eager-directory**: `FileTreeNode.init` MUST set
  `children` directly to the result of
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` for a
  directory node (not a package) constructed with `loadChildren: true`,
  including leaving `children` as an empty array — not `nil` — when that
  directory turns out to have no visible entries; this diverges from
  `loadChildrenIfNeeded()`'s empty-to-`nil` conversion (see
  `node-load-children-if-needed-empty-collapse`).
- **node-children-loaded-flag-eager**: `FileTreeNode.childrenLoaded` MUST be
  `true` immediately when `init` is called with `loadChildren: true`, and
  MUST remain `false` when `init` is called with `loadChildren: false`.
- **node-load-children-if-needed-guard**: `loadChildrenIfNeeded()` MUST
  return immediately, performing no file-system access, when `isDirectory`
  is `false`, when `isPackage` is `true`, or when `childrenLoaded` is
  already `true`.
- **node-load-children-if-needed-flag-before-read**:
  `loadChildrenIfNeeded()` MUST set `childrenLoaded = true` before
  dispatching its background read, not after the read completes, so that
  two calls to `loadChildrenIfNeeded()` on the same node in quick
  succession MUST result in at most one background read of that directory.
- **node-load-children-if-needed-background-queue**:
  `loadChildrenIfNeeded()` MUST perform its directory read via
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` on
  `DispatchQueue.global(qos: .userInitiated)`, never on the calling thread.
- **node-load-children-if-needed-empty-collapse**: `loadChildrenIfNeeded()`
  MUST assign the freshly-read result to `children` as `nil` when the read
  returns an empty array, and as the array itself otherwise — it MUST NOT
  leave `children` as a non-nil empty array.
- **node-load-children-if-needed-main-actor-publish**:
  `loadChildrenIfNeeded()` MUST publish the updated `children` value back
  via `DispatchQueue.main.async`, and MUST silently skip that assignment
  (through `self?.children = ...`) if the node has been deallocated before
  the background read completes.
- **node-load-children-if-needed-mainactor-declaration**:
  `loadChildrenIfNeeded()` MUST be declared `@MainActor`, so every call to
  it MUST originate on Swift's main actor.
- **node-should-ignore-glob-match**: `FileTreeNode.shouldIgnore(_:patterns:)`
  MUST return `true` if and only if the filename matches at least one
  pattern in `patterns` via POSIX `fnmatch` called with flags `0`, and MUST
  return `false` when `patterns` is empty.
- **node-load-children-ds-store-exclusion**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  unconditionally exclude any entry named exactly `.DS_Store`, independent
  of `ignorePatterns`.
- **node-load-children-hidden-files-included**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  call `contentsOfDirectory` with no `options` (not `.skipsHiddenFiles`), so
  dotfiles other than `.DS_Store` (for example `.claude`, `.git`,
  `.gitignore`) MUST be included unless a caller-supplied `ignorePatterns`
  entry matches them.
- **node-load-children-read-failure-empty**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  return an empty array, raising or logging no error, when
  `FileManager.default.contentsOfDirectory(at:includingPropertiesForKeys:options:)`
  throws.
- **node-load-children-directory-detection-fallback**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  treat a child whose `.isDirectoryKey` resource value cannot be read as a
  file (`isDirectory: false`), never as a directory.
- **node-load-children-recursion-depth**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  construct every child with `loadChildren: false`, so one call MUST read
  exactly one directory level and MUST NOT recurse into subdirectories.
- **node-load-children-sort-order**:
  `FileTreeNode.loadChildren(for:ignorePatterns:packageExtensions:)` MUST
  sort its result with every directory node before every file node, and
  MUST sort nodes of the same kind by `name` using
  `localizedCaseInsensitiveCompare` in ascending order.
- **node-merge-identity-preservation**: `merge(children:)` MUST, for every
  node in the `fresh` array whose `id` also appears among the node's
  current `children`, keep the pre-existing `FileTreeNode` instance (by
  reference) in the result rather than the corresponding instance from
  `fresh`.
- **node-merge-addition**: `merge(children:)` MUST include, as the `fresh`
  instance itself, any node in `fresh` whose `id` does not appear in the
  current `children`.
- **node-merge-deletion**: `merge(children:)` MUST drop from the result any
  existing child whose `id` does not appear in `fresh`.
- **node-merge-order-follows-fresh**: `merge(children:)` MUST order its
  result according to `fresh`'s order, not the previous `children`'s order.
- **node-equality-by-id-only**: `FileTreeNode.==` MUST compare only `id`
  (the URL path); it MUST NOT consider `children`, `gitStatus`, `fileSize`,
  `modificationDate`, or any other stored property.
- **node-hash-by-id-only**: `FileTreeNode.hash(into:)` MUST combine only
  `id` into the hasher.
- **node-git-status-external**: `FileTreeNode.gitStatus` MUST be a public,
  settable, `@Published` property that none of `FileTreeConfig.swift`,
  `FileTreeNode.swift`, `FileSystemWatcher.swift`, or
  `DirectoryWatchCoordinator.swift` itself ever assigns; it exists purely as
  a hook a caller outside these four files sets.
- **node-icon-package**: `systemImageName` MUST return `"shippingbox.fill"`
  whenever `isPackage` is `true`, regardless of `isDirectory`.
- **node-icon-directory-special-names**: `systemImageName` MUST return
  `"brain"` for a directory named exactly `.claude`, `"arrow.triangle.branch"`
  for one named exactly `.git`, `"folder.fill.badge.gearshape"` for one named
  `Sources`, `Source`, or `src`, and `"folder.fill.badge.questionmark"` for
  one named `Tests`, `test`, or `tests`.
- **node-icon-directory-dotfile-default**: `systemImageName` MUST return
  `"folder.badge.gearshape"` for any other directory whose name starts with
  `"."`, and `"folder.fill"` for every remaining directory.
- **node-icon-file-custom-mapping-priority**: `systemImageName` for a file
  MUST consult `CustomFileTypeMappings.mapping(for:)`, keyed on the
  lowercased path extension, before any other icon source, and MUST use
  that mapping's `iconName` when one is found for a non-empty extension.
- **node-icon-file-builtin-fallback**: `systemImageName` for a file with no
  custom mapping MUST use `FileTypeIcons.builtInIcon(for:)`, keyed on the
  lowercased path extension, and MUST fall back to the literal `"doc"` when
  that also returns `nil`.
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
| FSM-001 | config-package-extensions-default, config-package-display-names-default, config-custom-mappings-key-default, config-default-static-instance | `FileTreeConfig()` and `FileTreeConfig.default` | Both produce `packageExtensions == []`, `packageDisplayNames == [:]`, `customMappingsDefaultsKey == "AgenticFileBrowser.customMappings"` — traced directly to source; not exercised by a given test |
| FSM-002 | config-value-type | Attempt `config.packageExtensions.insert("x")` on a `let config: FileTreeConfig` binding | Fails to compile — `packageExtensions` is a `let` stored property on a value type |
| FSM-003 | node-identity-by-path, node-display-name | `FileTreeNode(url: URL(fileURLWithPath: "/tmp/a/b.txt"), isDirectory: false)` | `node.id == "/tmp/a/b.txt"`, `node.name == "b.txt"` — traced directly to source; not exercised by a given test |
| FSM-004 | node-directory-flag-trusted | `FileTreeNode(url: <url of an actual plain file>, isDirectory: true, loadChildren: false)` | `node.isDirectory == true` and `node.children == []`, exactly as if the URL really were a directory — `init` performs no on-disk verification |
| FSM-005 | node-package-detection | `FileTreeNode(url: URL(fileURLWithPath: "/tmp/some.catnip-proj"), isDirectory: true, loadChildren: false, packageExtensions: [])` | `node.isPackage == false` — `FileTreeNodeTests.testNoPackageExtensions` |
| FSM-006 | node-package-detection | `FileTreeNode(url: URL(fileURLWithPath: "/tmp/some.catnip-proj"), isDirectory: true, loadChildren: false, packageExtensions: ["catnip-proj"])` | `node.isPackage == true` — `FileTreeNodeTests.testMatchingPackageExtension` |
| FSM-007 | node-package-detection | `FileTreeNode(url: URL(fileURLWithPath: "/tmp/some.txt"), isDirectory: false, loadChildren: false, packageExtensions: ["catnip-proj"])` | `node.isPackage == false` — `FileTreeNodeTests.testNonMatchingPackageExtension` |
| FSM-008 | node-attribute-read-tolerant, node-file-size-directories-nil | `FileTreeNode(url: <an actual directory>, isDirectory: true)` and `FileTreeNode(url: <path to a file that does not exist>, isDirectory: false)` | Directory node's `fileSize == nil`; nonexistent-file node's `fileSize == nil` and `modificationDate == nil`, with no thrown error surfaced |
| FSM-009 | node-children-shape-file-or-package | `FileTreeNode` for a `.catnip-proj` package directory and `FileTreeNode` for a plain file | Both have `children == nil` |
| FSM-010 | node-children-shape-unopened-directory, node-children-loaded-flag-eager | `FileTreeNode(url: <a directory>, isDirectory: true, loadChildren: false)` | `children == []` and `childrenLoaded == false` |
| FSM-011 | node-children-shape-eager-directory, node-children-loaded-flag-eager | `FileTreeNode(url: <an empty, readable directory>, isDirectory: true, loadChildren: true)` | `children == []` (not `nil`) and `childrenLoaded == true` — diverges from the lazy path's nil-collapse |
| FSM-012 | node-load-children-if-needed-guard | Call `loadChildrenIfNeeded()` on a file node, on a package node, and again on a directory node whose `childrenLoaded` is already `true` | No background read starts in any of the three cases |
| FSM-013 | node-load-children-if-needed-flag-before-read, node-load-children-if-needed-background-queue, node-load-children-if-needed-mainactor-declaration | Call `loadChildrenIfNeeded()` twice, synchronously back-to-back on the main actor, on the same unopened directory node | `childrenLoaded` is already `true` when the second call is made, so only one background `DispatchQueue.global` read is issued — the precondition `DirectoryWatchCoordinatorTests`'s `openFolder` helper relies on |
| FSM-014 | node-load-children-if-needed-empty-collapse | `loadChildrenIfNeeded()` on a directory node for a genuinely empty, readable directory | `node.children` becomes `nil`, not `[]` — traced to the `loaded.isEmpty ? nil : loaded` line |
| FSM-015 | node-load-children-if-needed-main-actor-publish | Deallocate a `FileTreeNode` (drop the last strong reference) after calling `loadChildrenIfNeeded()` but before its background read completes | The later `self?.children = ...` assignment is skipped with no crash and no effect |
| FSM-016 | node-should-ignore-glob-match, node-load-children-ds-store-exclusion, node-load-children-hidden-files-included | `loadChildren(for: url, ignorePatterns: [])` on a directory containing `.DS_Store`, `.gitignore`, and `a.txt` | Result excludes `.DS_Store` but includes `.gitignore` and `a.txt` |
| FSM-017 | node-should-ignore-glob-match | `loadChildren(for: url, ignorePatterns: ["*.log"])` on a directory containing `a.txt` and `debug.log` | Result excludes `debug.log`, includes `a.txt` |
| FSM-018 | node-load-children-read-failure-empty | `loadChildren(for: url)` on a directory the caller has no read permission for | Result is `[]` — indistinguishable in the return value from a genuinely empty, readable directory |
| FSM-019 | node-load-children-directory-detection-fallback | `loadChildren(for:)` where one entry's `.isDirectoryKey` resource value cannot be read (for example a symlink to a nonexistent target) | That entry's node is constructed with `isDirectory: false` |
| FSM-020 | node-load-children-recursion-depth | `loadChildren(for: root)` on a root containing one subdirectory that itself contains a file | The returned subdirectory node's own `children == []` (unopened) — the file one level further down is absent from the result |
| FSM-021 | node-load-children-sort-order | `loadChildren(for: url)` on a directory containing files `"b.txt"`, `"A.txt"` and subdirectory `"Zdir"` | Result orders `["Zdir", "A.txt", "b.txt"]` — directories first, then case-insensitive alphabetical |
| FSM-022 | node-merge-identity-preservation, node-merge-order-follows-fresh | `parent.merge(children: freshArray)` where `freshArray` lists the same `id`s as `parent.children` but in reverse order | Result order matches `freshArray`'s order, and each element is `===` the corresponding pre-existing instance |
| FSM-023 | node-merge-addition, node-merge-deletion | `parent.merge(children: freshArray)` where `freshArray` adds one `id` absent from `parent.children` and omits one `id` that is present in `parent.children` | Result contains the new `id`'s `fresh` instance and drops the omitted `id` entirely |
| FSM-024 | node-equality-by-id-only, node-hash-by-id-only | Two `FileTreeNode` instances constructed for the same `url` but with different `gitStatus`/`fileSize` values | `lhs == rhs` is `true`, and both hash to the same value |
| FSM-025 | node-git-status-external | Read `FileTreeNode.gitStatus` immediately after construction, having exercised only these four files' code paths | Always `nil`, since none of the four ever assigns it |
| FSM-026 | node-icon-package, node-icon-directory-special-names, node-icon-directory-dotfile-default | `systemImageName` for a `.catnip-proj` package, a `.claude` directory, a `.git` directory, a `Sources` directory, a `Tests` directory, a `.env` directory, and a plain `Notes` directory | `"shippingbox.fill"`, `"brain"`, `"arrow.triangle.branch"`, `"folder.fill.badge.gearshape"`, `"folder.fill.badge.questionmark"`, `"folder.badge.gearshape"`, `"folder.fill"` respectively |
| FSM-027 | node-icon-file-custom-mapping-priority, node-icon-file-builtin-fallback | `systemImageName` for a file whose extension has a `CustomFileTypeMappings` entry, one whose extension only `FileTypeIcons.builtInIcon` recognizes, and one with an unrecognized extension | The custom mapping's `iconName`, the built-in icon name, and `"doc"` respectively |
| FSM-028 | node-max-display-width-formula, node-max-display-width-recursion | `maximumDisplayWidth()` on a leaf node named `"a.txt"` at `depth: 0` with default parameters | `70.0 + 0 + (5 * 7.5) == 107.5` |
| FSM-029 | node-max-display-width-recursion, node-max-display-width-unmaterialized-children | `maximumDisplayWidth()` on a directory whose one loaded child has a longer name than the directory itself, compared against the same directory before that child was ever loaded (`children == []`) | Loaded case returns the child's larger width; unloaded case returns only the directory's own width |
| FSM-030 | watcher-unchecked-sendable-declaration | Pass a `FileSystemWatcher` instance across an actor boundary into a context requiring `Sendable` | Compiles, because of the `@unchecked Sendable` conformance — a genuinely non-`Sendable` class would fail to compile there |
| FSM-031 | watcher-exclusion-prefix-match | `FileSystemWatcher.isExcluded("/root/.git", by: ["/root/.git"])` and `isExcluded("/root/.gitignore", by: ["/root/.git"])` | First returns `true` (exact match); second returns `false` — `.gitignore` is not inside `.git/` — traced to the source's own doc comment example |
| FSM-032 | watcher-start-idempotent | Call `start()` twice in succession on the same `FileSystemWatcher` | Only the first call creates a stream; the second is a no-op because `streamRef` is already non-`nil` |
| FSM-033 | watcher-create-failure-retryable | Cause `FSEventStreamCreate` to return `nil` (for example an invalid path), then call `start()` again | First call logs an error and leaves `streamRef == nil`; second call attempts creation again |
| FSM-034 | watcher-callback-path-filtering, watcher-callback-main-thread-dispatch | An FSEvents callback fires with `eventPaths` entirely inside an excluded prefix; a second fires with at least one surviving path | First: `handler` is never invoked. Second: `handler` runs on `DispatchQueue.main` |
| FSM-035 | watcher-stream-configuration | Inspect the arguments `start()` passes to `FSEventStreamCreate` | `sinceWhen == kFSEventStreamEventIdSinceNow`, `latency == 0.5`, `flags == kFSEventStreamCreateFlagFileEvents \| kFSEventStreamCreateFlagUseCFTypes` |
| FSM-036 | watcher-stop-teardown, watcher-deinit-safety-net | Call `stop()` on a started watcher; separately, let a started watcher fall out of scope without calling `stop()` | Both paths call `FSEventStreamStop`/`Invalidate`/`Release` and leave `streamRef == nil` |
| FSM-037 | coordinator-mainactor-declaration, coordinator-ignore-patterns-mutable | Construct a `DirectoryWatchCoordinator`, then set `coordinator.ignorePatterns = ["*.log"]` after construction | `rootURL`/`excludedPrefixes`/`config` are unchanged and have no setter; `ignorePatterns` accepts the new value |
| FSM-038 | coordinator-full-sync-one-level, node-load-children-sort-order | `fullSync()` on a fresh directory containing one subdirectory `"nested"` (itself containing `"file.swift"`) | `rootNode.url == directory`; `rootNode.children` maps to `["nested"]` only — `DirectoryWatchCoordinatorTests.testTheFirstSyncPublishesTheRoot` |
| FSM-039 | coordinator-full-sync-background-io | Call `fullSync()` and read `isSyncing` synchronously right after the call returns, before the background read completes | `isSyncing == true` — matches the precondition `DirectoryWatchCoordinatorTests.sync`'s wait-for-`false` helper relies on |
| FSM-040 | coordinator-full-sync-merge-vs-replace | Call `fullSync()` twice on the same coordinator/root with no filesystem change between calls | `coordinator.rootNode === ` the first sync's root, and `rootNode.children?.first === ` the first sync's child — `DirectoryWatchCoordinatorTests.testASecondSyncKeepsTheSameNodeObjects` |
| FSM-041 | coordinator-full-sync-merge-vs-replace, node-merge-identity-preservation | After a first sync, call `loadChildrenIfNeeded()` on the `"nested"` child (reading its `"file.swift"` entry), then call `fullSync()` again | `"nested"`'s children still map to `["file.swift"]` after the second sync — `DirectoryWatchCoordinatorTests.testASecondSyncKeepsChildrenThatWereAlreadyRead` |
| FSM-042 | coordinator-full-sync-merge-vs-replace | Set `coordinator.rootNode` to a `FileTreeNode` for a different URL (`"elsewhere"`) before calling `fullSync()` | `coordinator.rootNode.url == ` the coordinator's own `rootURL`, not `"elsewhere"` — `DirectoryWatchCoordinatorTests.testASyncOfADifferentRootReplacesTheTree` |
| FSM-043 | coordinator-full-sync-completion-signal | Register a closure via `startWatching(onChange:)`, then call `fullSync()` directly | The closure fires exactly once, after `isSyncing` has already returned to `false` |
| FSM-044 | coordinator-start-watching-registration, coordinator-stop-watching-teardown | Call `startWatching(onChange:)` then `stopWatching()` | A `FileSystemWatcher` is created and started, then stopped and released; a later filesystem change produces no callback |
| FSM-045 | coordinator-handle-changes-pre-sync-guard | Construct a coordinator, call `startWatching`, and trigger a filesystem change before ever calling `fullSync()` | `handleChanges(_:)` returns immediately; `isSyncing` remains `false`; no attempt is made to index a `nil` `rootNode` |
| FSM-046 | coordinator-handle-changes-affected-directories, coordinator-handle-changes-index-scope | After a `fullSync()`, a change is reported for `"nested/inner/new.txt"` where `"nested/inner"` was never opened | No update is applied to the tree — `"nested/inner"` has no node in `buildIndex`'s result — and no error is raised |
| FSM-047 | coordinator-handle-changes-per-directory-reload, coordinator-handle-changes-completion-signal | After a `fullSync()` and opening `"nested"` (via `loadChildrenIfNeeded()`), a change is reported for a new file added directly inside `"nested"` | `"nested"`'s `children` gains the new file via `merge(children:)`, and the registered `onChange` callback fires once `isSyncing` returns to `false` |

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

## Deep Linking

Not applicable: none of `FileTreeConfig.swift`, `FileTreeNode.swift`,
`FileSystemWatcher.swift`, or `DirectoryWatchCoordinator.swift` defines a
URL route, an inbound app-URL scheme, or any navigable destination — every
`URL` these files touch (`FileTreeNode.url`, `DirectoryWatchCoordinator.rootURL`)
is a plain filesystem path, not a link into the app.

## Localization

Not applicable: none of these four files contains a user-facing string
literal. Their only string-valued output is `FileTreeNode.systemImageName`
(an SF Symbol *name*, not displayed text) and log messages, neither of
which is localized text shown to a user.

## Accessibility Options

Not applicable: none of these four files renders anything or reads an
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — there is no UI here to adapt.

## Feature Flags

Not applicable: none of these four files contains a feature-flag or
remote-config check of any kind; behavior is governed entirely by
constructor arguments and the caller-supplied `ignorePatterns`/`excludedPrefixes`.

## Analytics

Not applicable: none of these four files emits an analytics or
event-tracking call of any kind.

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

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol) |
Category: `DirectoryWatchCoordinator` or `FileSystemWatcher`, one category
per conforming type — `Loggable.category` derives it from the type name.

| Event | Level | Message | Category |
|-------|-------|---------|----------|
| Sync applied | info | `Sync complete for <rootURL.lastPathComponent>` | `DirectoryWatchCoordinator` |
| Change batch received | debug | `FS changes: <count> path(s) in <rootURL.lastPathComponent>` | `DirectoryWatchCoordinator` |
| Watcher started | info | `Started file system watcher for <rootPath>` (path logged with `privacy: .public`) | `FileSystemWatcher` |
| Watcher stopped | info | `Stopped file system watcher` | `FileSystemWatcher` |
| Stream creation failed | error | `Failed to create FSEvent stream for <rootPath>` | `FileSystemWatcher` |

## Platform Notes

- **SwiftUI**: None of these four files imports SwiftUI, but
  `DirectoryWatchCoordinator` and `FileTreeNode`'s `ObservableObject` +
  `@Published` conformances are consumable directly by a SwiftUI view via
  `@StateObject`/`@ObservedObject` with no adapter layer. A SwiftUI port
  would keep this model layer unchanged and bind a `List` or `OutlineGroup`
  to `rootNode`'s `children`, calling `loadChildrenIfNeeded()` from
  `.onAppear` or the row's disclosure action, in place of the AppKit
  `NSOutlineView` consumer described in
  [File Tree Outline View Controller](agentictoolkit://recipes/file-tree-outline-view-controller).
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
  (see [File Tree Outline View Controller](agentictoolkit://recipes/file-tree-outline-view-controller)).
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
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
