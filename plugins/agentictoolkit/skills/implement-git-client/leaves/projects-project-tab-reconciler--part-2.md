<!-- leaf: implement-git-client/projects-project-tab-reconciler--part-2 · source: git-client-projects-project-tab-reconciler.md -->

# ProjectTabReconciler — continued (part 2)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stored` (`plan` parameter) | `[TabRecord]` | none — required | The tabs the caller already persisted for this project. |
| `checkouts` (`plan` parameter) | `[ProjectCheckout]` | none — required | The checkouts a fresh `git worktree list` read just reported. |
| `projectDirectory` (`plan` parameter) | `URL` | none — required | The project's own directory; a stored record with `workingDirectory == nil` is matched against this directory. |
| `existsOnDisk` (`plan` parameter) | `(URL) -> Bool` | `FileManager.default.fileExists(atPath:)` | Consulted once per stored record not already matched by a checkout, to tell "not reported" apart from "genuinely gone." |
| `volumeIsMounted` (`plan` parameter) | `((URL) -> Bool)?` | `ProjectTabReconciler.volumeIsMounted(for:projectDirectory:)` | Consulted once per record whose directory is gone, to decide whether dropping it is safe. |
| `directory` (`volumeIsMounted` parameter) | `URL` | none — required | The candidate directory whose mounted volume is in question. |
| `projectDirectory` (`volumeIsMounted` parameter) | `URL` | none — required | The project's directory, used as the volume of comparison. |
| `tabs` (`arrangement` parameter) | `[TabRecord]` | none — required | The tabs to pick a representative layout from. |
| `activeTabID` (`arrangement` parameter) | `UUID?` | none — required | The id of the tab whose layout should be preferred. |
| `checkout` (`makeRecords` parameter) | `ProjectCheckout` | none — required | The checkout every returned record's `title` and `workingDirectory` are derived from. |
| `enabledEdges` (`makeRecords` parameter) | `[Edge]` | none — required | One returned `TabRecord` per element, in the same order. |
| `blueprint` (`makeRecords` parameter) | `() -> LayoutNode` | none — required | Called once per enabled edge so every returned record's `root` carries a distinct `LayoutNode.id`. |

No function in this file reads an environment variable or a settings key;
every input arrives as an explicit parameter.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift`,
  which imports only `AgenticToolkitCore` and `Foundation` — no SwiftUI,
  AppKit, or UIKit dependency. A port needs its sibling value types alongside
  it: `TabRecord` and `Edge` from
  `macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift` and
  `macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift`, and
  `ProjectCheckout` from `macOS/Features/Projects/ProjectCheckout.swift`.
- **Compose**: Model `plan`, `volumeIsMounted`, `arrangement`, and
  `makeRecords` as top-level functions or methods on a Kotlin `object` with
  no instance state. Port `URL` to `java.nio.file.Path`, the `Set<URL>`
  lookups to `mutableSetOf<Path>()`, and `resolvingSymlinksInPath()` to
  `Path.toRealPath()`. `existsOnDisk` becomes `(Path) -> Boolean` backed by
  `Files.exists(path)`; `volumeIsMounted` has no direct Android equivalent —
  the closest analog is `Environment.getExternalStorageState(file)` or
  `StorageManager.getStorageVolume(file)` reporting whether removable media
  is currently mounted, walked up the same way `deepestExistingAncestor`
  does.
- **React/Web**: Port `plan`, `arrangement`, and `makeRecords` as pure
  functions over plain arrays, a `Set`, and a `Map`, taking a path `string`
  in place of `URL`; `existsOnDisk` maps to `fs.existsSync(path)`. A browser
  or Electron renderer has no concept of a removable-volume mount point to
  match `volumeIsMounted` against, so a faithful port either restricts to a
  Node/Electron main-process context where `fs.statfs`-style mount
  inspection is available, or documents that the unmounted-volume protection
  this file provides has no equivalent and every gone directory is treated
  as deletable.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file is
  tied to a UI framework, so it ports unchanged to either. An iOS host would
  still need its own `existsOnDisk` and `volumeIsMounted` that respect the
  App Sandbox rather than calling `FileManager`/`resourceValues` against an
  arbitrary path, since iOS has no user-visible `/Volumes` mount point to
  walk up to.
- **WinUI 3**: Port `plan`, `volumeIsMounted`, `arrangement`, and
  `makeRecords` as static methods on a static class, taking
  `IReadOnlyList<TabRecord>`, `IReadOnlyList<ProjectCheckout>`, and a
  `Func<string, bool>` in place of each closure parameter — no `Task`/`async`
  is needed anywhere in this port, matching the source's fully synchronous
  signatures. Build the directory set with `HashSet<string>` keyed on a
  normalized, case-preserving full path, and use
  `System.IO.Directory.Exists`/`File.Exists` for `existsOnDisk`. Port
  `resolvingSymlinksInPath()` with `FileSystemInfo.ResolveLinkTarget(true)`
  (.NET 6+) rather than `Windows.Storage`, since this is ordinary local-disk
  access, not packaged-app storage. Port `volumeIsMounted` by walking
  `Directory.GetParent(...)` until a directory exists, exactly like
  `deepestExistingAncestor`, then comparing `new DriveInfo(Path.GetPathRoot(...))`
  for both sides and checking `DriveInfo.IsReady` in place of the `/Volumes`
  special case. Port `TabRecord` and `ProjectCheckout` as C# records; because
  `TabRecord`'s `edge`, `title`, `root`, `focusedNodeID`, and
  `workingDirectory` are mutable (`var`) in the source, decide explicitly
  whether the port keeps them mutable or moves to `with`-expression-based
  immutability, since C# has no `Sendable` to make that choice visible in
  the type system the way the source's absence of `Sendable` on `TabRecord`
  does. Port `Plan` as a record with `Keep`, `Add`, and `Drop` collection
  properties and an `IsUnchanged` computed property, and treat it, like the
  source, as not inherently safe to hand across threads without the
  caller's own synchronization.

## Design Decisions

**Decision**: A stored record is dropped only when its directory is both
gone (not a checkout, not present on disk) and its volume is currently
mounted.
**Rationale**: The doc comment on `plan(...)` states the cost of getting this
wrong directly: dropping a record "deletes the tab, its layout tree and its
remembered pane state for good," so "an unplugged drive or a dismounted
share must not cost the user a tab they can never get back"
(`ProjectTabReconciler.swift`).
**Approved**: pending

**Decision**: `projectDirectory` and each stored record's effective
directory are resolved with `resolvingSymlinksInPath()`, not merely
standardized, before any comparison.
**Rationale**: The doc comment gives the concrete failure this prevents: a
checkout's directory comes from `git worktree list` (already resolved) while
a stored record's comes from whatever the window was originally opened
with, so an unresolved symlink on either side turns a real match into a
miss and adds a duplicate tab group for a checkout that already has one
(`ProjectTabReconciler.swift`; verified by
`testARecordReachingACheckoutThroughASymlinkIsStillTheSameTab`).
**Approved**: pending

**Decision**: `makeRecords(...)` takes `blueprint` as a factory
(`() -> LayoutNode`), invoked once per enabled edge, rather than a single
`LayoutNode` value shared across every returned record.
**Rationale**: The doc comment ties this directly to a database constraint:
`layout_nodes.id` is a `TEXT PRIMARY KEY`, and `saveTabs` inserts one
member's `root` per call inside a single transaction, so members sharing one
`LayoutNode` value would share one node id, the second insert would violate
the primary key, and the whole save would roll back
(`ProjectTabReconciler.swift`; verified by
`testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID`).
**Approved**: pending

**Decision**: `arrangement(of:activeTabID:)` falls back to `tabs.first` when
`activeTabID` names no element of `tabs`, rather than returning `nil`
whenever the id lookup misses.
**Rationale**: The doc comment states why the fallback must be deterministic
rather than absent: "a reconcile and the window that follows it" must
"decide the same way twice, or [they] disagree about the shape a new tab
should have" — the fallback covers a tab dropped along with its directory,
or a project that never recorded an active tab at all
(`ProjectTabReconciler.swift`).
**Approved**: pending

**Decision**: `volumeIsMounted(for:projectDirectory:)` treats `/Volumes`
itself as never mounted, and otherwise compares the volume of `directory`'s
deepest existing ancestor against the volume of `projectDirectory`'s.
**Rationale**: The doc comment explains what walking to the deepest existing
ancestor distinguishes: a mount point with nothing mounted on it, a
directory on a different but still-reachable volume, and a directory on the
same volume the project lives on — and walking `projectDirectory` the same
way keeps the comparison meaningful even when the project's own directory no
longer exists (`ProjectTabReconciler.swift`).
**Approved**: pending
