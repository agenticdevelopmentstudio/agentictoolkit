---
id: d7171e41-4638-4243-9821-7a46cecf15c2
title: Project Tab Reconciler
domain: agentictoolkit://cookbook/workspace/projects/project-tab-reconciler
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Turns a project's stored tabs and current checkouts into a plan of tabs to
  keep, checkouts needing new tabs, and tabs whose directory is truly gone.
platforms:
- swift
- macos
tags:
- git
- projects
- tabs
- reconciliation
- pure-function
depends-on: []
related:
- agentictoolkit://cookbook/workspace/projects/project-controller
- agentictoolkit://cookbook/workspace/projects/project-checkout
- agentictoolkit://cookbook/workspace/projects/project-database-layout
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectTabReconcilerTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectCheckout.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectDatabase+Layout.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Project Tab Reconciler

## Overview

This is a stateless collection of pure functions that turns "what tabs are
already stored" plus "what checkouts a fresh worktree listing just
reported" into the changes a caller should make: which stored tabs to keep
as-is, which checkouts need a brand-new tab group, and which stored tabs
point at a directory that is truly gone rather than merely unreachable.
Its own documentation states it is pure — no disk access except through an
injected existence check — so it is testable and the project controller
stays the only thing that acts on the answer. Its sole caller reads the
stored tabs and the current checkouts, builds a plan, then picks a
starting layout for any new checkout and builds that checkout's tab
records, before persisting the combined result. This file performs no
persistence itself and reads no other stored state; every answer is a pure
function of its arguments.

## Behavioral Requirements

- **plan-struct-shape**: the plan value MUST declare exactly three stored
  fields — `keep` (a list of tab records), `add` (a list of checkouts),
  and `drop` (a list of ids) — with no default values, so every plan value
  MUST be built from all three.
- **plan-is-unchanged**: the plan's `isUnchanged` MUST return `true`
  exactly when both `add` and `drop` are empty, regardless of how many
  records `keep` holds.
- **plan-resolves-project-directory**: building a plan MUST resolve the
  project directory by following symlinks once, before evaluating any
  stored record or any checkout, and MUST use that resolved value for
  every later comparison.
- **plan-checkout-directory-set**: building a plan MUST build the set of
  every checkout's directory before evaluating any stored record, so a
  record's fate depends on the whole checkout list, not on the order the
  stored records were given.
- **plan-record-directory-resolution**: for each stored record, building a
  plan MUST resolve that record's working directory (falling back to the
  project directory when the record has none) by following symlinks, to
  obtain the directory used for every later comparison for that record.
- **plan-gone-determination**: building a plan MUST treat a record's
  resolved directory as gone only when that directory is neither a member
  of the checkout-directory set nor reported present by the existence
  check.
- **plan-drop-requires-mounted-volume**: building a plan MUST add a
  record's id to `drop` only when the record's directory is gone and the
  mount check for that directory also returns `true`; a record whose
  directory is gone but whose volume is not mounted MUST NOT be added to
  `drop`.
- **plan-keep-default**: building a plan MUST add a record to `keep`, and
  MUST mark its resolved directory as covered, for every stored record
  that is not added to `drop` — whether because its directory is not gone,
  or because it is gone but its volume is not mounted.
- **plan-add-derivation**: building a plan MUST populate `add` with every
  checkout whose directory is not covered after every stored record has
  been processed.
- **plan-exists-on-disk-default**: building a plan MUST default the
  existence check to a function that reports whether a path exists on the
  local filesystem, when the caller supplies no existence check.
- **plan-volume-is-mounted-default**: building a plan MUST default the
  mount check to the mount-lookup function described in
  **volume-is-mounted-contract**, evaluated against the already-resolved
  project directory, when the caller supplies no mount-check argument.
- **volume-is-mounted-contract**: the mount-lookup function MUST return
  `false` when the deepest existing ancestor of the candidate directory is
  exactly the removable-volumes mount point, and otherwise MUST return
  whether that ancestor's volume matches the volume of the deepest
  existing ancestor of the project directory.
- **deepest-existing-ancestor-walk**: the deepest-existing-ancestor walk
  MUST resolve symlinks in the given directory, MUST then repeatedly move
  up one path component until the candidate is reported present on the
  local filesystem, and MUST return the candidate unchanged, even if it
  does not exist, once moving up stops changing it — the filesystem root.
- **volume-url-lookup-failure**: the volume lookup MUST return no result,
  rather than throwing or crashing, whenever the underlying volume-identity
  query fails for the given directory.
- **arrangement-selection**: selecting a layout MUST return the layout
  root of the tab whose id equals the active-tab id when such a tab
  exists, and otherwise MUST return the layout root of the first tab.
- **arrangement-empty-tabs**: selecting a layout MUST return no result
  when the tab list is empty, since both the id lookup and the
  first-tab fallback are empty for an empty list.
- **make-records-shared-group**: building tab records for a checkout MUST
  generate exactly one fresh group id per call and MUST assign that same
  group id to every tab record it returns.
- **make-records-one-per-edge**: building tab records for a checkout MUST
  return exactly one tab record for every enabled edge, in the same order,
  with each returned record's `edge` set to that edge.
- **make-records-shared-fields**: every tab record this operation returns
  MUST set `title` to the checkout's display name and `workingDirectory`
  to the checkout's directory.
- **make-records-fresh-blueprint-per-edge**: building tab records for a
  checkout MUST invoke the layout-blueprint factory once for every enabled
  edge and MUST NOT reuse one layout value across more than one returned
  record's `root`, so that every returned record's `root` carries a
  distinct layout-node id (verified by
  `testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID`).
- **reconciler-no-mutation-of-inputs**: building a plan, selecting a
  layout, and building tab records MUST NOT mutate the stored records, the
  checkouts, or the tab list passed to them; each builds its result from
  local values and returns a new value.
- **reconciler-synchronous-non-throwing**: building a plan, the
  mount-lookup function, selecting a layout, and building tab records MUST
  each be synchronous and non-throwing.
- **duplicate-checkout-directory-handling**: Unique checkout directories
  are a caller precondition. Building a plan derives `add` by filtering
  the checkouts against the covered-directory set in one pass that does
  not update that set as it goes, so it does not deduplicate the checkouts
  itself; its input comes from resolving the current checkouts over a
  fresh worktree listing, and git registers each worktree at a distinct
  path. A caller that passes two checkouts sharing one uncovered directory
  gets both in `add`.
- **volume-lookup-failure-handling**: NEEDS REVIEW: Not implemented in
  source. The volume lookup collapses every failure of the underlying
  volume-identity query — a thrown error and a successful call whose
  volume is empty — into the same no-result outcome, so the mount-lookup
  function's equality check cannot distinguish "both sides are on the same
  mounted volume" from "neither side's volume could be determined at all";
  when both volume lookups fail identically, the equality check evaluates
  to true, the mount-lookup function reports the directory mounted, and
  building a plan then drops — permanently, per the documentation — a
  record whose real mount status was never actually established. What is
  missing: whether the volume-identity query can fail for an existing
  local directory on the filesystems this app supports, and if so what the
  mount-lookup function should return instead of treating that failure as
  "mounted." What would settle it: a documented statement of the intended
  fallback for that case, or evidence that the volume-identity query never
  fails for a path the deepest-existing-ancestor walk has already
  confirmed exists.

## Appearance

Not applicable — this is a pure tab-reconciliation algorithm, not a visual
component.

## States

Not applicable — this is a pure tab-reconciliation algorithm, not a visual
component.

## Accessibility

Not applicable — this is a pure tab-reconciliation algorithm, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-tab-reconciler-001 | plan-add-derivation, plan-checkout-directory-set, plan-is-unchanged | Start with no stored tabs and two checkouts (`main`, `tabs`); every existence check reports present. | `keep` is empty; `add` equals the two checkouts; `drop` is empty; `isUnchanged` is `false` — ProjectTabReconcilerTests.swift › testAFreshProjectAddsEveryCheckout |
| git-client-projects-project-tab-reconciler-002 | plan-gone-determination, plan-keep-default, plan-is-unchanged | Two stored tab records (one with no working directory of its own, one pointing at a worktree) against the same two checkouts; every existence check reports present. | `keep`'s ids equal the stored records' ids, in order; `add` is empty; `isUnchanged` is `true` — ProjectTabReconcilerTests.swift › testStoredTabsForKnownCheckoutsAreKeptNotDuplicated |
| git-client-projects-project-tab-reconciler-003 | plan-gone-determination, plan-drop-requires-mounted-volume, volume-is-mounted-contract | One stored record pointing at a directory that has vanished, one checkout (`main`); the existence check reports absent for that directory, and the (default) mount check reports the record's volume as mounted. | `drop` equals the stored record's id; `add` equals the one checkout — ProjectTabReconcilerTests.swift › testATabWhoseDirectoryVanishedIsDropped |
| git-client-projects-project-tab-reconciler-004 | plan-drop-requires-mounted-volume, volume-is-mounted-contract, deepest-existing-ancestor-walk | One stored record pointing at a directory under an unmounted volume, one checkout (`main`); the existence check reports absent, and the deepest existing ancestor of the record's directory is the removable-volumes mount point itself. | `keep`'s ids equal the stored record's id; `drop` is empty — ProjectTabReconcilerTests.swift › testATabOnAnUnmountedVolumeIsKeptNotDropped |
| git-client-projects-project-tab-reconciler-005 | plan-drop-requires-mounted-volume | A missing directory, with the existence check reporting absent and the mount check reporting mounted. | `drop` equals the stored record's id — ProjectTabReconcilerTests.swift › testAMissingDirectoryIsDroppedOnlyWhenItsVolumeIsMounted (first call) |
| git-client-projects-project-tab-reconciler-006 | plan-drop-requires-mounted-volume, plan-keep-default | The same setup as above, but the mount check reports not mounted. | `keep`'s ids equal the stored record's id; `drop` is empty — ProjectTabReconcilerTests.swift › testAMissingDirectoryIsDroppedOnlyWhenItsVolumeIsMounted (second call) |
| git-client-projects-project-tab-reconciler-007 | plan-gone-determination, plan-keep-default | One stored record pointing at an existing directory elsewhere, one checkout (`main`); every existence check reports present. | `keep`'s ids equal the stored record's id; `drop` is empty — ProjectTabReconcilerTests.swift › testAUserTabInAnotherExistingFolderSurvives |
| git-client-projects-project-tab-reconciler-008 | plan-record-directory-resolution | A stored record whose working directory is a symlink to the checkout's real, resolved directory. | `keep`'s ids equal the stored record's id; `add` and `drop` are both empty; `isUnchanged` is `true` — ProjectTabReconcilerTests.swift › testARecordReachingACheckoutThroughASymlinkIsStillTheSameTab |
| git-client-projects-project-tab-reconciler-009 | make-records-shared-group, make-records-one-per-edge, make-records-shared-fields | Build tab records for one checkout, enabling two edges (`left`, `top`). | Two records are returned; both share one group id; the edges read `left`, `top` in order; both titles read the checkout's name; both working directories equal the checkout's directory — ProjectTabReconcilerTests.swift › testMakeRecordsProducesOneMemberPerEdgeSharingAGroup |
| git-client-projects-project-tab-reconciler-010 | make-records-fresh-blueprint-per-edge | The same call as above. | The two returned records' layout roots carry two distinct ids — ProjectTabReconcilerTests.swift › testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID |
| git-client-projects-project-tab-reconciler-011 | arrangement-selection | Two tabs (`tabA`, `tabB`); select a layout with the active-tab id set to `tabB`'s id. | Returns `tabB`'s layout root. |
| git-client-projects-project-tab-reconciler-012 | arrangement-selection | The same two tabs; select a layout with the active-tab id set to an id that names neither tab. | Returns the first tab's layout root (`tabA`'s). |
| git-client-projects-project-tab-reconciler-013 | arrangement-empty-tabs | An empty tab list; select a layout with no active-tab id. | Returns no result. |
| git-client-projects-project-tab-reconciler-014 | reconciler-no-mutation-of-inputs, reconciler-synchronous-non-throwing | Build a plan twice in a row with the same stored records, checkouts, project directory, and existence check. | Both calls return plans with identical `keep`, `add`, and `drop` (same ids, same order); the stored records and checkouts are unchanged after either call. |
| git-client-projects-project-tab-reconciler-015 | plan-exists-on-disk-default, plan-volume-is-mounted-default | Build a plan with no stored records, no checkouts, a real project directory, and no existence check or mount check supplied. | Returns a plan with `keep`, `add`, and `drop` all empty and `isUnchanged` true, without crashing, regardless of what is actually mounted on the machine running it — there is nothing in the stored records or checkouts for the real filesystem- and volume-backed defaults to evaluate. |
| git-client-projects-project-tab-reconciler-016 | duplicate-checkout-directory-handling | The checkouts list contains two entries with the same directory but different branches, and that directory is not covered by any stored record. | Precondition violated: both checkout entries appear in `add`, so the caller's per-checkout tab-building call produces two independent tab groups rooted at the same directory. |
| git-client-projects-project-tab-reconciler-017 | volume-lookup-failure-handling | The mount-lookup function is called where the underlying volume-identity query fails on both the candidate directory's side and the project directory's side. | Current, undefined-contract behavior: the volume lookup returns no result for both sides, the equality check treats that as a match, and the mount-lookup function reports the directory mounted even though neither side's volume was actually determined. |

## Edge Cases

- **Null and empty input**: both the stored-record list and the checkout
  list being empty MUST cause building a plan to return a plan whose
  `keep`, `add`, and `drop` are all empty and whose `isUnchanged` is
  `true`, since neither the stored-record loop nor the `add` filter has
  anything to iterate. MUST. An empty enabled-edges list passed to
  building tab records for a checkout MUST cause it to return an empty
  list without invoking the layout-blueprint factory at all, since mapping
  over an empty list never calls its function. MUST.
- **Boundary values**: a stored record whose id equals the active-tab id
  MUST be preferred by layout selection over the first tab even when it is
  not the first element of the tab list; when no element matches, the
  boundary collapses to the first tab, and when the tab list itself is
  empty it collapses further to no result. MUST. A single stored
  tab-record group with more than one enabled edge — several records
  sharing one working directory — is evaluated independently per record by
  the plan-building loop, but since gone-ness and mounted-ness depend only
  on the shared directory, not on which record is being examined, every
  member of that group MUST reach the same keep-or-drop outcome; they can
  never be split between `keep` and `drop`. MUST.
- **Concurrent access**: building a plan, the mount-lookup function,
  selecting a layout, and building tab records hold all of their mutable
  state in local values, and this component itself declares no stored
  property of any kind, so independent concurrent calls with independent
  inputs cannot race against each other or against any state this file
  owns. MUST. The result they hand back is a different matter: neither
  the plan value nor the tab record is safe-to-share-across-concurrency-domains
  by declaration (see the concurrency note in Platform Notes), so a
  caller that shares one plan value, or the closures passed as the
  existence check or mount check, across concurrency domains without its
  own synchronization is not protected by this file's own guarantees.
  MUST.
- **Error states**: no operation in this file can throw. The volume
  lookup's only failure surface is swallowed internally, so a thrown error
  there always becomes a no-result rather than propagating; see
  **volume-lookup-failure-handling** for the case this swallowing makes
  ambiguous. MUST.
- **Offline or disconnected state**: not applicable — nothing in this file
  makes a network call; its only I/O is local filesystem existence and
  volume-identity lookups through the existence check and the default
  filesystem- and volume-backed implementations.
- **Missing file or unreachable directory**: a stored record's directory
  that no longer exists anywhere on a mounted volume causes it to be
  considered gone and its volume considered mounted, so the record
  proceeds into `drop` (verified by the vanished-directory test vector).
  MUST. The same missing directory on an unmounted or unreachable volume
  causes the volume to be considered not mounted, so the record is kept
  instead, deliberately trading a possibly stale tab for never silently
  deleting one the user can no longer get back (verified by the
  unmounted-volume test vector). MUST.
- **Cancellation and timeouts**: not applicable — building a plan, the
  mount-lookup function, selecting a layout, and building tab records are
  all synchronous computations with nothing to cancel and no operation
  that can run long enough to time out.
- **Duplicate checkout directories**: see
  **duplicate-checkout-directory-handling** above; the source neither
  rejects nor deduplicates two checkout entries that name the same
  directory.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stored` (plan input) | list of tab records | none — required | The tabs the caller already persisted for this project. |
| `checkouts` (plan input) | list of checkouts | none — required | The checkouts a fresh worktree listing just reported. |
| `projectDirectory` (plan input) | directory reference | none — required | The project's own directory; a stored record with no working directory of its own is matched against this directory. |
| `existsOnDisk` (plan input) | directory-to-boolean function | the local filesystem's own existence check | Consulted once per stored record not already matched by a checkout, to tell "not reported" apart from "genuinely gone." |
| `volumeIsMounted` (plan input) | directory-to-boolean function, optional | the mount-lookup function described in **volume-is-mounted-contract** | Consulted once per record whose directory is gone, to decide whether dropping it is safe. |
| `directory` (mount-lookup input) | directory reference | none — required | The candidate directory whose mounted volume is in question. |
| `projectDirectory` (mount-lookup input) | directory reference | none — required | The project's directory, used as the volume of comparison. |
| `tabs` (layout-selection input) | list of tab records | none — required | The tabs to pick a representative layout from. |
| `activeTabID` (layout-selection input) | id, optional | none — required | The id of the tab whose layout should be preferred. |
| `checkout` (record-building input) | checkout | none — required | The checkout every returned record's `title` and `workingDirectory` are derived from. |
| `enabledEdges` (record-building input) | list of edges | none — required | One returned tab record per element, in the same order. |
| `blueprint` (record-building input) | layout factory | none — required | Called once per enabled edge so every returned record's `root` carries a distinct layout-node id. |

No function in this file reads an environment variable or a settings key;
every input arrives as an explicit parameter.

## Deep Linking

Not applicable: this file defines no URL scheme, route, or navigation
destination; the directory references it receives and compares are local
filesystem directories, not app routes.

## Localization

Not applicable: this file contains no user-facing string literal of its
own. Building tab records copies the checkout's display name verbatim
into a record's `title`; translating that string, if it needs
translation, is the checkout's own concern (see the project-checkout
recipe), not this file's.

## Accessibility Options

Not applicable: this file renders nothing, so Reduce Motion, Increase
Contrast, and Differentiate Without Color have no surface here to apply
to.

## Feature Flags

Not applicable: this file contains no feature-flag or build-configuration
check of any kind.

## Analytics

Not applicable: this file makes no analytics or event-tracking call.

## Privacy

Not applicable: this file handles no token, credential, or other secret;
the only data it touches — directory paths, checkout branch names, and
record identifiers — is already held by its caller, and this file makes
no network call and persists nothing itself.

## Logging

Not applicable: this file contains no logging call of any kind; its
caller is the one that acts on the plan this file returns.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift`,
  which imports only `AgenticToolkitCore` and `Foundation` — no SwiftUI,
  AppKit, or UIKit dependency. A port needs its sibling value types
  alongside it: `TabRecord` and `Edge` from
  `macOS/UI/ViewControllers/ComposableTabs/LayoutNode.swift` and
  `macOS/UI/ViewControllers/MultiTabbedViewController/Edge.swift`, and
  `ProjectCheckout` from `macOS/Features/Projects/ProjectCheckout.swift`.
  Neither `ProjectTabReconciler` itself nor any of its four static
  functions (`plan`, `volumeIsMounted`, `arrangement`, `makeRecords`)
  declares an `actor` or `@MainActor` isolation, so every one of them is
  callable synchronously from any concurrency domain. Its `Plan` and
  `TabRecord` types both declare no explicit `Sendable` conformance, so
  neither type should be assumed safe to carry across an actor or `Task`
  boundary without explicit synchronization; `ProjectCheckout`, `UUID`,
  and `LayoutNode` — the other types this file's public signatures
  traffic in — are `Sendable`. The `existsOnDisk` and `volumeIsMounted`
  closure parameters of `plan(...)` are plain function values with no
  `@Sendable` annotation, so nothing in this file's own signature obliges
  a caller-supplied closure to be safe to invoke from a different
  concurrency domain than the one that constructed it.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectTabReconciler.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectTabReconciler.swift`
does exactly one thing — decide keep/add/drop from given state — and
delegates walking the filesystem to the injected `existsOnDisk` closure,
persisting the result to `ProjectDatabase`, and presenting the reconciled
window to `ProjectController`, none of which leaks into this file.
unit-test-coverage is partial: `ProjectTabReconcilerTests.swift` exercises
`plan(...)`'s add/keep/drop branches, the mounted-versus-unmounted boundary,
the symlink-resolution case, and both `makeRecords` invariants directly, but
`arrangement(of:activeTabID:)` has no dedicated test in this file at all,
and no test exercises the real, non-overridden
`volumeIsMounted(for:projectDirectory:)` against an actual resource-value
failure. explicit-error-handling is partial because of the open question on
volume-lookup-failure-handling: `volumeURL(of:)`'s `try?` turns a thrown
resource-value error into the same `nil` that a legitimately absent volume
URL produces, and that ambiguity feeds directly into a permanent-deletion
decision. idempotent-operations passes: every function in this file is a
pure, synchronous computation over its arguments with no stored state, so
calling `plan(...)` again with the same stored tabs, checkouts, and
filesystem state MUST reproduce the same `Plan` (see
`reconciler-no-mutation-of-inputs`, `reconciler-synchronous-non-throwing`).
data-integrity is partial: the open question on
volume-lookup-failure-handling can permanently drop a record whose mount
status was never established, while duplicate checkout directories rest on
the caller precondition in **duplicate-checkout-directory-handling**.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
