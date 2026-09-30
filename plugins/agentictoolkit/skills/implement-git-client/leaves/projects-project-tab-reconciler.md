<!-- leaf: implement-git-client/projects-project-tab-reconciler · source: git-client-projects-project-tab-reconciler.md -->

**Rules** (cite as `implement-git-client/projects-project-tab-reconciler#<slug>`):

- `plan-struct-shape` MUST
- `plan-is-unchanged` MUST
- `plan-resolves-project-directory` MUST
- `plan-checkout-directory-set` MUST
- `plan-record-directory-resolution` MUST
- `plan-gone-determination` MUST
- `plan-drop-requires-mounted-volume` MUST
- `plan-keep-default` MUST
- `plan-add-derivation` MUST
- `plan-exists-on-disk-default` MUST
- `plan-volume-is-mounted-default` MUST
- `volume-is-mounted-contract` MUST
- `deepest-existing-ancestor-walk` MUST
- `volume-url-lookup-failure` MUST
- `arrangement-selection` MUST
- `arrangement-empty-tabs` MUST
- `make-records-shared-group` MUST
- `make-records-one-per-edge` MUST
- `make-records-shared-fields` MUST
- `make-records-fresh-blueprint-per-edge` MUST
- `reconciler-no-mutation-of-inputs` MUST
- `reconciler-synchronous-non-throwing` MUST
- `reconciler-isolation-free` MUST
- `plan-and-record-non-sendable` MUST

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

