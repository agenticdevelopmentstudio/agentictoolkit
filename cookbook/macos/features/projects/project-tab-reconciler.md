---
id: d7171e41-4638-4243-9821-7a46cecf15c2
title: ProjectTabReconciler
domain: agentictoolkit://cookbook/macos/features/projects/project-tab-reconciler
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
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
- agentictoolkit://cookbook/macos/features/projects/project-controller
- agentictoolkit://cookbook/macos/features/projects/project-checkout
- agentictoolkit://cookbook/macos/features/projects/project-database-layout
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

# ProjectTabReconciler

## Overview

`ProjectTabReconciler` is a stateless namespace of static functions that turns
"what tabs are already stored" plus "what checkouts a fresh `git worktree
list` just reported" into the changes a caller should make: which stored tabs
to keep as-is, which checkouts need a brand-new tab group, and which stored
tabs point at a directory that is truly gone rather than merely unreachable.
The type's own doc comment states it is "Pure: no disk access except through
`existsOnDisk`, so it is testable and the project controller stays the only
thing that acts on the answer" (`ProjectTabReconciler.swift`). Its
sole caller, `ProjectController.reconcile()`, reads the stored tabs and the
current checkouts, calls `plan(...)`, then calls `arrangement(of:activeTabID:)`
to pick a starting layout for any new checkout and `makeRecords(...)` to build
that checkout's tab records, before persisting the combined result through
`ProjectDatabase.saveTabs(...)` (`ProjectController.swift`). This
file performs no persistence itself and reads no other stored state; every
answer is a pure function of its arguments.

## Behavioral Requirements

- **plan-struct-shape**: `ProjectTabReconciler.Plan` MUST declare exactly
  three stored properties — `keep` (`[TabRecord]`), `add`
  (`[ProjectCheckout]`), and `drop` (`[UUID]`) — with no default values, so
  every `Plan` value MUST be built from all three (`ProjectTabReconciler.swift`).
- **plan-is-unchanged**: `Plan.isUnchanged` MUST return `true` exactly when
  both `add` and `drop` are empty, regardless of how many records `keep`
  holds (`ProjectTabReconciler.swift`).
- **plan-resolves-project-directory**: `plan(...)` MUST resolve
  `projectDirectory` with `resolvingSymlinksInPath()` once, before evaluating
  any stored record or any checkout, and MUST use that resolved value for
  every later comparison (`ProjectTabReconciler.swift`).
- **plan-checkout-directory-set**: `plan(...)` MUST build `checkoutDirectories`
  as the set of every element of `checkouts`' `directory` before evaluating
  any stored record, so a record's fate depends on the whole checkout list,
  not on the order `stored` was given (`ProjectTabReconciler.swift`).
- **plan-record-directory-resolution**: For each element of `stored`,
  `plan(...)` MUST resolve `(record.workingDirectory ?? projectDirectory)`
  with `resolvingSymlinksInPath()` to obtain the directory used for every
  later comparison for that record (`ProjectTabReconciler.swift`).
- **plan-gone-determination**: `plan(...)` MUST treat a record's resolved
  directory as gone only when that directory is neither a member of
  `checkoutDirectories` nor reported present by `existsOnDisk(directory)`
  (`ProjectTabReconciler.swift`).
- **plan-drop-requires-mounted-volume**: `plan(...)` MUST append `record.id`
  to `drop` only when the record's directory is gone and `isMounted(directory)`
  also returns `true`; a record whose directory is gone but whose volume is
  not mounted MUST NOT be added to `drop` (`ProjectTabReconciler.swift`).
- **plan-keep-default**: `plan(...)` MUST append `record` to `keep`, and MUST
  insert its resolved directory into `coveredDirectories`, for every element
  of `stored` that is not added to `drop` — whether because its directory is
  not gone, or because it is gone but its volume is not mounted
  (`ProjectTabReconciler.swift`).
- **plan-add-derivation**: `plan(...)` MUST populate `add` with every element
  of `checkouts` whose `directory` is not a member of `coveredDirectories`
  after every element of `stored` has been processed
  (`ProjectTabReconciler.swift`).
- **plan-exists-on-disk-default**: `plan(...)` MUST default `existsOnDisk` to
  a closure that returns `FileManager.default.fileExists(atPath:)` for the
  given `URL`'s `path` when the caller supplies no argument
  (`ProjectTabReconciler.swift`).
- **plan-volume-is-mounted-default**: `plan(...)` MUST default `isMounted` to
  `ProjectTabReconciler.volumeIsMounted(for:projectDirectory:)`, evaluated
  against the already-resolved `projectDirectory`, when the caller supplies
  no `volumeIsMounted` argument (`ProjectTabReconciler.swift`).
- **volume-is-mounted-contract**: `volumeIsMounted(for:projectDirectory:)`
  MUST return `false` when the deepest existing ancestor of `directory` is
  exactly `/Volumes`, and otherwise MUST return whether that ancestor's
  volume URL equals the volume URL of the deepest existing ancestor of
  `projectDirectory` (`ProjectTabReconciler.swift`).
- **deepest-existing-ancestor-walk**: `deepestExistingAncestor(of:)` MUST
  resolve symlinks in `directory`, MUST then repeatedly call
  `deletingLastPathComponent()` until `FileManager.default.fileExists(atPath:)`
  reports `true` for the candidate, and MUST return the candidate unchanged,
  even if it does not exist, once `deletingLastPathComponent()` stops
  changing it — the filesystem root (`ProjectTabReconciler.swift`).
- **volume-url-lookup-failure**: `volumeURL(of:)` MUST return `nil`, rather
  than throwing or crashing, whenever `resourceValues(forKeys:
  [.volumeURLKey])` throws for the given directory
  (`ProjectTabReconciler.swift`).
- **arrangement-selection**: `arrangement(of:activeTabID:)` MUST return the
  `root` of the element of `tabs` whose `id` equals `activeTabID` when such
  an element exists, and otherwise MUST return the `root` of `tabs.first`
  (`ProjectTabReconciler.swift`).
- **arrangement-empty-tabs**: `arrangement(of:activeTabID:)` MUST return `nil`
  when `tabs` is empty, since both `tabs.first { ... }` and the `tabs.first`
  fallback are `nil` for an empty array (`ProjectTabReconciler.swift`).
- **make-records-shared-group**: `makeRecords(for:enabledEdges:blueprint:)`
  MUST generate exactly one fresh `groupID` per call and MUST assign that
  same `groupID` to every `TabRecord` it returns
  (`ProjectTabReconciler.swift`).
- **make-records-one-per-edge**: `makeRecords(...)` MUST return exactly one
  `TabRecord` for every element of `enabledEdges`, in the same order, with
  each returned record's `edge` set to that element
  (`ProjectTabReconciler.swift`).
- **make-records-shared-fields**: Every `TabRecord` `makeRecords(...)`
  returns MUST set `title` to `checkout.displayName` and `workingDirectory`
  to `checkout.directory` (`ProjectTabReconciler.swift`).
- **make-records-fresh-blueprint-per-edge**: `makeRecords(...)` MUST invoke
  `blueprint()` once for every element of `enabledEdges` and MUST NOT reuse
  one `LayoutNode` value across more than one returned record's `root`, so
  that every returned record's `root` carries a distinct `LayoutNode.id`
  (`ProjectTabReconciler.swift`; verified by
  `testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID`).
- **reconciler-no-mutation-of-inputs**: `plan(...)`, `arrangement(...)`, and
  `makeRecords(...)` MUST NOT mutate `stored`, `checkouts`, or `tabs`; each
  builds its result from local variables and returns a new value
  (`ProjectTabReconciler.swift`).
- **reconciler-synchronous-non-throwing**: `plan(...)`,
  `volumeIsMounted(for:projectDirectory:)`, `arrangement(...)`, and
  `makeRecords(...)` MUST each be synchronous and non-throwing
  (`ProjectTabReconciler.swift`, no `async` or `throws` on any
  signature).
- **reconciler-isolation-free**: `ProjectTabReconciler` MUST declare no
  `actor` or `@MainActor` isolation on itself or on any of its four static
  functions, so every one of them MUST be callable synchronously from any
  concurrency domain (`ProjectTabReconciler.swift`, no isolation
  attribute present on the type or on `plan`, `volumeIsMounted`,
  `arrangement`, or `makeRecords`).
- **plan-and-record-non-sendable**: `ProjectTabReconciler.Plan` and
  `TabRecord` both declare no explicit `Sendable` conformance, so neither
  type MUST be assumed safe to carry across an actor or `Task` boundary
  without explicit synchronization; `ProjectCheckout`, `UUID`, and
  `LayoutNode` — the other types this file's public signatures traffic in —
  are `Sendable` (`ProjectTabReconciler.swift`; contrast
  `ProjectCheckout.swift` and `LayoutNode.swift`, both of which
  declare `Sendable` explicitly, with `TabRecord`'s declaration at
  `LayoutNode.swift`, which does not).
- **plan-injection-closures-not-sendable-annotated**: The `existsOnDisk` and
  `volumeIsMounted` parameters of `plan(...)` are plain function values with
  no `@Sendable` annotation, so nothing in this file's own signature obliges
  a caller-supplied closure to be safe to invoke from a different
  concurrency domain than the one that constructed it
  (`ProjectTabReconciler.swift`).
- **duplicate-checkout-directory-handling**: Unique checkout directories are a caller precondition. `plan(stored:checkouts:projectDirectory:existsOnDisk:volumeIsMounted:)` derives `add` by filtering `checkouts` against `coveredDirectories` in one pass that does not update `coveredDirectories` as it goes, so it does not deduplicate `checkouts` itself; its input comes from `ProjectCheckout.checkouts(from:)` over `git worktree list`, and git registers each worktree at a distinct path. A caller that passes two checkouts sharing one uncovered directory gets both in `add`.
- **volume-lookup-failure-handling**: NEEDS REVIEW: Not implemented in source. `volumeURL(of:)` collapses every failure of `resourceValues(forKeys: [.volumeURLKey])` — a thrown error and a successful call whose `.volume` is `nil` — into the same `nil` result, so `volumeIsMounted(for:projectDirectory:)`'s equality check cannot distinguish "both sides are on the same mounted volume" from "neither side's volume could be determined at all"; when both `volumeURL` calls fail identically, `nil == nil` evaluates to `true`, `volumeIsMounted` reports the directory mounted, and `plan(...)` then drops — permanently, per the doc comment — a record whose real mount status was never actually established. What is missing: whether `resourceValues(forKeys:)` can fail for an existing local directory on the filesystems this app supports, and if so what `volumeIsMounted` should return instead of treating that failure as "mounted." What would settle it: a doc-comment statement of the intended fallback for that case, or evidence that `.volumeURLKey` never fails for a path `deepestExistingAncestor` has already confirmed exists.

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
| git-client-projects-project-tab-reconciler-001 | plan-add-derivation, plan-checkout-directory-set, plan-is-unchanged | `testAFreshProjectAddsEveryCheckout`: `stored: []`, `checkouts: [main, tabs]`, `existsOnDisk: { _ in true }`. | `plan.keep` is empty; `plan.add == [main, tabs]`; `plan.drop` is empty; `plan.isUnchanged == false`. |
| git-client-projects-project-tab-reconciler-002 | plan-gone-determination, plan-keep-default, plan-is-unchanged | `testStoredTabsForKnownCheckoutsAreKeptNotDuplicated`: two stored `TabRecord`s (one with `workingDirectory: nil`, one with `workingDirectory: worktree`) against `checkouts: [main, tabs]`, `existsOnDisk: { _ in true }`. | `plan.keep.map(\id)` equals the stored records' ids in order; `plan.add` is empty; `plan.isUnchanged == true`. |
| git-client-projects-project-tab-reconciler-003 | plan-gone-determination, plan-drop-requires-mounted-volume, volume-is-mounted-contract | `testATabWhoseDirectoryVanishedIsDropped`: one stored record at `/repo/.claude/worktrees/gone`, `checkouts: [main]`, `existsOnDisk: { $0 != gone }` (default `volumeIsMounted`, and `/repo` is on the boot volume). | `plan.drop` equals the stored record's id; `plan.add == [main]`. |
| git-client-projects-project-tab-reconciler-004 | plan-drop-requires-mounted-volume, volume-is-mounted-contract, deepest-existing-ancestor-walk | `testATabOnAnUnmountedVolumeIsKeptNotDropped`: one stored record at `/Volumes/absent-<uuid>/notes`, `checkouts: [main]`, `existsOnDisk: { _ in false }` (default `volumeIsMounted`, deepest existing ancestor is `/Volumes` itself). | `plan.keep.map(\id)` equals the stored record's id; `plan.drop` is empty. |
| git-client-projects-project-tab-reconciler-005 | plan-drop-requires-mounted-volume | `testAMissingDirectoryIsDroppedOnlyWhenItsVolumeIsMounted` (first call): missing directory, `existsOnDisk: { _ in false }`, `volumeIsMounted: { _ in true }`. | `plan.drop` equals the stored record's id. |
| git-client-projects-project-tab-reconciler-006 | plan-drop-requires-mounted-volume, plan-keep-default | `testAMissingDirectoryIsDroppedOnlyWhenItsVolumeIsMounted` (second call): same setup, `volumeIsMounted: { _ in false }`. | `plan.keep.map(\id)` equals the stored record's id; `plan.drop` is empty. |
| git-client-projects-project-tab-reconciler-007 | plan-gone-determination, plan-keep-default | `testAUserTabInAnotherExistingFolderSurvives`: one stored record at `/somewhere/else`, `checkouts: [main]`, `existsOnDisk: { _ in true }`. | `plan.keep.map(\id)` equals the stored record's id; `plan.drop` is empty. |
| git-client-projects-project-tab-reconciler-008 | plan-record-directory-resolution | `testARecordReachingACheckoutThroughASymlinkIsStillTheSameTab`: stored record's `workingDirectory` is a symlink to the checkout's real, resolved `directory`. | `plan.keep.map(\id)` equals the stored record's id; `plan.add` and `plan.drop` are both empty; `plan.isUnchanged == true`. |
| git-client-projects-project-tab-reconciler-009 | make-records-shared-group, make-records-one-per-edge, make-records-shared-fields | `testMakeRecordsProducesOneMemberPerEdgeSharingAGroup`: `makeRecords(for: tabs, enabledEdges: [.left, .top], blueprint: makeBlueprint)`. | `records.count == 2`; `Set(records.map(\groupID)).count == 1`; `records.map(\edge) == [.left, .top]`; `records.map(\title) == ["tabs", "tabs"]`; `records.compactMap(\workingDirectory) == [worktree, worktree]`. |
| git-client-projects-project-tab-reconciler-010 | make-records-fresh-blueprint-per-edge | `testMakeRecordsGivesEachEdgeMemberADistinctRootNodeID`: same call as above. | `Set(records.map(\.root.id)).count == 2`. |
| git-client-projects-project-tab-reconciler-011 | arrangement-selection | Direct trace of `ProjectTabReconciler.swift`: `tabs = [tabA(id: A), tabB(id: B)]`, `arrangement(of: tabs, activeTabID: B)`. | Returns `tabB.root`. |
| git-client-projects-project-tab-reconciler-012 | arrangement-selection | Same trace: `arrangement(of: tabs, activeTabID: someOtherID)` where `someOtherID` names no element of `tabs`. | Returns `tabs.first!.root` (`tabA.root`). |
| git-client-projects-project-tab-reconciler-013 | arrangement-empty-tabs | Same trace: `arrangement(of: [], activeTabID: nil)`. | Returns `nil`. |
| git-client-projects-project-tab-reconciler-014 | reconciler-no-mutation-of-inputs, reconciler-synchronous-non-throwing | Call `plan(stored: s, checkouts: c, projectDirectory: d, existsOnDisk: e)` twice in a row with the same `s`, `c`, `d`, `e`. | Both calls return `Plan` values with identical `keep`, `add`, and `drop` (same ids, same order); `s` and `c` are unchanged after either call. |
| git-client-projects-project-tab-reconciler-015 | plan-exists-on-disk-default, plan-volume-is-mounted-default | `plan(stored: [], checkouts: [], projectDirectory: someRealDirectory)` called with no `existsOnDisk` and no `volumeIsMounted` argument. | Returns a `Plan` with `keep`, `add`, and `drop` all empty and `isUnchanged == true`, without crashing, regardless of what is actually mounted on the machine running it — there is nothing in `stored` or `checkouts` for the real `FileManager`- and volume-backed defaults to evaluate. |
| git-client-projects-project-tab-reconciler-016 | duplicate-checkout-directory-handling | `checkouts` contains two `ProjectCheckout` values with the same `directory` but different `branch`, and that directory is not covered by any element of `stored`. | Precondition violated: both checkout values appear in `plan.add`, so the caller's per-checkout `makeRecords` call produces two independent tab groups rooted at the same directory. |
| git-client-projects-project-tab-reconciler-017 | volume-lookup-failure-handling | `volumeIsMounted(for:projectDirectory:)` called where the deepest existing ancestor's `resourceValues(forKeys: [.volumeURLKey])` throws on both `directory`'s side and `projectDirectory`'s side. | Current, undefined-contract behavior: `volumeURL(of:)` returns `nil` for both sides, the equality check treats `nil == nil` as a match, and `volumeIsMounted` reports the directory mounted even though neither side's volume was actually determined. |

## Edge Cases

- **Null and empty input**: `stored` and `checkouts` both empty MUST cause
  `plan(...)` to return a `Plan` whose `keep`, `add`, and `drop` are all
  empty and whose `isUnchanged` is `true`, since neither the stored-record
  loop nor the `add` filter has anything to iterate
  (`ProjectTabReconciler.swift`). MUST. `enabledEdges` empty in a
  call to `makeRecords(...)` MUST cause it to return an empty array without
  invoking `blueprint()` at all, since `enabledEdges.map { ... }` over an
  empty array never calls its closure (`ProjectTabReconciler.swift`). MUST.
- **Boundary values**: A stored record whose `id` equals `activeTabID` MUST
  be preferred by `arrangement(...)` over `tabs.first` even when it is not
  the first element of `tabs`; when no element matches, the boundary
  collapses to `tabs.first`, and when `tabs` itself is empty it collapses
  further to `nil` (`ProjectTabReconciler.swift`). MUST. A single
  stored `TabRecord` group with more than one enabled edge — several records
  sharing one `workingDirectory` — is evaluated independently per record by
  `plan(...)`'s loop, but since `isGone` and `isMounted` depend only on the
  shared directory, not on which record is being examined, every member of
  that group MUST reach the same keep-or-drop outcome; they can never be
  split between `keep` and `drop` (`ProjectTabReconciler.swift`).
  MUST.
- **Concurrent access**: `plan(...)`, `volumeIsMounted(...)`,
  `arrangement(...)`, and `makeRecords(...)` hold all of their mutable state
  in local variables, and `ProjectTabReconciler` itself declares no stored
  property of any kind, so independent concurrent calls with independent
  inputs cannot race against each other or against any state this file owns
  (`ProjectTabReconciler.swift`). MUST. The result they hand
  back is a different matter: neither `Plan` nor `TabRecord` is `Sendable`
  (see `plan-and-record-non-sendable`), so a caller that shares one `Plan`
  value, or the closures passed as `existsOnDisk`/`volumeIsMounted`, across
  concurrency domains without its own synchronization is not protected by
  this file's type signatures. MUST.
- **Error states**: No function in this file can throw. `volumeURL(of:)`'s
  only failure surface — `resourceValues(forKeys: [.volumeURLKey])` — is
  wrapped in `try?`, so a thrown error there always becomes `nil` rather
  than propagating; see `volume-lookup-failure-handling` for the case this
  swallowing makes ambiguous. MUST.
- **Offline or disconnected state**: Not applicable — nothing in this file
  makes a network call; its only I/O is local filesystem existence and
  volume-URL lookups through `existsOnDisk` and the default
  `FileManager`/`resourceValues` calls.
- **Missing file or unreachable directory**: A stored record's directory
  that no longer exists anywhere on a mounted volume causes `isGone` to be
  `true` and `isMounted` to be `true`, so the record proceeds into `drop`
  (`ProjectTabReconciler.swift`; verified by
  `testATabWhoseDirectoryVanishedIsDropped`). MUST. The same missing
  directory on an unmounted or unreachable volume causes `isMounted` to be
  `false`, so the record is kept instead, deliberately trading a possibly
  stale tab for never silently deleting one the user can no longer get back
  (`ProjectTabReconciler.swift`; verified by
  `testATabOnAnUnmountedVolumeIsKeptNotDropped`). MUST.
- **Cancellation and timeouts**: Not applicable — `plan(...)`,
  `volumeIsMounted(...)`, `arrangement(...)`, and `makeRecords(...)` are all
  synchronous, non-`async` computations with nothing to cancel and no
  operation that can run long enough to time out.
- **Duplicate checkout directories**: See `duplicate-checkout-directory-handling`
  above; the source neither rejects nor deduplicates two `checkouts` entries
  that name the same directory.

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

## Deep Linking

Not applicable: `ProjectTabReconciler.swift` defines no URL scheme, route, or
navigation destination; the `URL` values it receives and compares are local
filesystem directories, not app routes (`ProjectTabReconciler.swift`).

## Localization

Not applicable: `ProjectTabReconciler.swift` contains no user-facing string
literal of its own. `makeRecords(...)` copies `checkout.displayName` verbatim
into `TabRecord.title` (`ProjectTabReconciler.swift`); translating
that string, if it needs translation, is `ProjectCheckout`'s concern (see the
`git-client-projects-project-checkout` recipe), not this file's.

## Accessibility Options

Not applicable: `ProjectTabReconciler.swift` renders nothing, so Reduce
Motion, Increase Contrast, and Differentiate Without Color have no surface
here to apply to.

## Feature Flags

Not applicable: `ProjectTabReconciler.swift` contains no feature-flag or
build-configuration check of any kind (`ProjectTabReconciler.swift`).

## Analytics

Not applicable: `ProjectTabReconciler.swift` makes no analytics or
event-tracking call (`ProjectTabReconciler.swift`).

## Privacy

Not applicable: `ProjectTabReconciler.swift` handles no token, credential, or
other secret; the only data it touches — directory paths, checkout branch
names, and record identifiers — is already held by its caller,
`ProjectController`, and this file makes no network call and persists nothing
itself (`ProjectTabReconciler.swift`).

## Logging

Not applicable: `ProjectTabReconciler.swift` contains no `Logger`, `os.log`,
`print`, or other logging call (`ProjectTabReconciler.swift`);
`ProjectController` is the caller that acts on the `Plan` this file returns.

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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
