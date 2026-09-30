<!-- leaf: implement-file-system/model-file-system · source: file-system-model-file-system.md -->

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
File Tree Outline View Controller
and
File Browser View Controller
for how this model's `nil`-vs-empty-array `children` distinction and its
swallowed directory-read failures are consumed one layer up.

