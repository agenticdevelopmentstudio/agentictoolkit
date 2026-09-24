---
id: fcff7387-19aa-49ab-b75d-f0c7bfcdf27c
title: ProjectReconciler
domain: agentictoolkit://recipes/git-client-projects-project-reconciler
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Matches a directory scan against known repositories and turns the difference
  into a plan of inserts, moved-and-updated rows, and deletes.
platforms:
- swift
- macos
tags:
- git
- projects
- reconciliation
- sendable
- pure-function
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectReconcilerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# ProjectReconciler

## Overview

`ProjectReconciler` is a stateless namespace of static functions that turns
"what a directory scan just found" plus "what the registry already knew"
into the rows a caller should write. Its one entry point, `plan(existing:scanned:now:isStillARepository:)`,
matches each `ScannedGitRepo` a scan produced against the `GitRepo` rows
already known, in a fixed order: exact path matches first, then unresolved
rows are checked against disk to tell "not reported" apart from "genuinely
gone," then a move pass matches a relocated repository by remote and, failing
that, by directory name, then whatever is still unclaimed becomes a new
insert, and whatever is still unaccounted for becomes a delete. The doc
comment on the type states it is "Pure and `nonisolated`" so that "the
interesting half of scanning" can be tested without a database, a filesystem,
or a main actor (`ProjectReconciler.swift`). Nothing in this file
performs I/O beyond the injectable `isStillARepository` check; reading the
scan results off disk is `GitRepoScanner`'s job (see the
`git-client-projects-git-repo-scanner` recipe), and writing the resulting
`Plan` to a database is a separate caller's job.

## Behavioral Requirements

- **plan-struct-shape**: `ProjectReconciler.Plan` MUST conform to `Sendable`
  and MUST store four properties — `inserts`, `updates`, and `deletes`, each
  an array of `GitRepo` values defaulting to empty, and `summary`, a
  `ProjectScanSummary` defaulting to a freshly constructed instance
  (`ProjectReconciler.swift`).
- **exact-path-match-lookup**: `plan(existing:scanned:now:isStillARepository:)`
  MUST build a lookup keyed by every existing row's `path` before considering
  any scanned repository, so a scanned repository's fate is decided by an
  exact string match against that lookup (`ProjectReconciler.swift`).
- **unmatched-scan-collection**: Every scanned repository whose `path` is not
  a key in that lookup MUST be added to the set of scans available to the
  later move and insert passes, in the order `scanned` was given
  (`ProjectReconciler.swift`).
- **exact-path-match-remote-update**: When a scanned repository's `path`
  exactly matches a known row and that row's stored `remote` differs from
  the scanned `remote`, `plan(...)` MUST overwrite the row's `remote` with
  the scanned value, MUST set its `lastSeen` to `now`, and MUST append the
  mutated row to `updates`; when the two `remote` values are equal,
  `plan(...)` MUST NOT append anything to `updates` for that row
  (`ProjectReconciler.swift`).
- **exact-path-match-increments-unchanged**: `plan(...)` MUST increment
  `summary.unchanged` by exactly one for every scanned repository whose path
  exactly matches a known row, regardless of whether that same row was also
  just appended to `updates` for a remote change — a row can count toward
  `unchanged` and appear in `updates` in the same call
  (`ProjectReconciler.swift`; verified by
  `testARepointedRemoteIsWrittenBack`).
- **missing-rows-exclude-seen**: After the exact-path pass, `plan(...)` MUST
  narrow the candidates for the skip, move, and delete passes to existing
  rows whose `id` was not marked seen during that pass
  (`ProjectReconciler.swift`).
- **unreachable-path-skipped-not-deleted**: A missing row for which
  `isStillARepository` returns `true` for that row's `path` MUST be excluded
  from both the move pass and the delete pass, and the count of such rows
  MUST be added to `summary.skipped` rather than `summary.removed`
  (`ProjectReconciler.swift`).
- **move-by-remote-priority**: For a missing row whose `remote` is present
  and non-empty, `plan(...)` MUST consider only unclaimed scanned
  repositories whose `remote` equals that exact string as move candidates
  before ever consulting directory-name equality
  (`ProjectReconciler.swift`).
- **move-by-remote-requires-uniqueness**: `plan(...)` MUST use a remote-based
  candidate as the match only when exactly one unclaimed scanned repository
  shares the missing row's `remote`; when zero or more than one share it,
  `plan(...)` MUST fall back to the directory-name comparison instead
  (`ProjectReconciler.swift`).
- **move-by-name-fallback**: `plan(...)` MUST match a missing row to an
  unclaimed scanned repository by directory-name equality — the scanned
  repository's `leafName` equal to `GitRepo.defaultName(forPath:)` of the
  missing row's path — only when both the missing row's `remote` and the
  candidate's `remote` are `nil` or the empty string, and only when exactly
  one such candidate exists (`ProjectReconciler.swift`).
- **unmatched-move-becomes-delete**: A missing row for which neither the
  remote pass nor the name pass yields a unique candidate MUST remain
  unresolved after the move pass and MUST end up in `deletes`
  (`ProjectReconciler.swift`; verified by
  `testAnAmbiguousMoveDeletesTheRow`).
- **move-preserves-identity-and-name**: When a missing row is matched,
  `plan(...)` MUST keep that row's `id` and `name` unchanged, MUST overwrite
  its `path` and `remote` with the matched scan's values, MUST set its
  `lastSeen` to `now`, MUST append it to `updates`, and MUST NOT also append
  it to `inserts` (`ProjectReconciler.swift`).
- **move-claims-target-path**: `plan(...)` MUST record a matched scan's
  `path` as claimed at the moment the match is made, so that no later
  iteration of the move pass, and no later evaluation of the insert pass,
  can match that same scanned path a second time
  (`ProjectReconciler.swift`).
- **move-precedes-insert**: `plan(...)` MUST resolve every possible move
  before evaluating any scanned repository for insertion, so a repository's
  destination path after a move is never also treated as a brand-new project
  (`ProjectReconciler.swift`; verified by
  `testAMoveIsResolvedBeforeTheNewPathIsAdopted`).
- **insert-unique-name**: For every scanned repository left unclaimed after
  the move pass, `plan(...)` MUST derive its name by calling
  `uniqueName(forPath:taken:)`, seeding `taken` from every existing row's
  current `name` and adding each newly assigned name to `taken` before
  processing the next unclaimed scan in the same call, so two repositories
  inserted by one `plan(...)` call MUST NOT receive the same name
  (`ProjectReconciler.swift`; verified by
  `testASecondRepoWithTheSameLeafNameIsQualifiedByItsParent`).
- **insert-fresh-fields**: Each newly inserted `GitRepo` MUST take its `path`
  and `remote` from the unmatched scan and MUST set both `firstSeen` and
  `lastSeen` to `now`, leaving `id` to `GitRepo.init`'s default of a freshly
  generated `UUID` (`ProjectReconciler.swift`).
- **delete-whatever-remains**: `plan(...)` MUST place every missing row that
  the skip pass and the move pass left unresolved into `deletes`, and MUST
  set `summary.removed` to the count of that final list
  (`ProjectReconciler.swift`).
- **plan-defaults**: `plan(existing:scanned:now:isStillARepository:)` MUST
  default `now` to `Date()` evaluated at the moment of the call and MUST
  default `isStillARepository` to `ProjectReconciler.repositoryExists` when
  the caller supplies neither (`ProjectReconciler.swift`).
- **repository-exists-check**: `repositoryExists(atPath:)` MUST return
  whether `FileManager.default` reports an entry named `.git` directly under
  `path`, and per its own doc comment — "its existence is the whole test" —
  MUST NOT additionally check whether that entry is a directory or contains
  a `HEAD` file (`ProjectReconciler.swift`).
- **unique-name-escalation**: `uniqueName(forPath:taken:)` MUST split `path`
  into its non-separator path components and MUST try, in order, the
  shortest trailing run of one component, then two, and so on, each joined
  with `/`, returning the first such candidate that is not a member of
  `taken` (`ProjectReconciler.swift`; verified by
  `testUniqueNameWalksUpUntilItIsFree`).
- **unique-name-empty-path**: `uniqueName(forPath:taken:)` MUST return
  `path` unchanged when `path` has no non-separator components
  (`ProjectReconciler.swift`).
- **unique-name-exhausted-fallback**: When every candidate through the full
  path, including the full path itself, is already present in `taken`,
  `uniqueName(forPath:taken:)` MUST return `path` unchanged, exactly as it
  was passed in, rather than appending a disambiguating suffix of any kind
  (`ProjectReconciler.swift`).
- **plan-pure-and-side-effect-free**: `plan(...)`, `repositoryExists(atPath:)`,
  and `uniqueName(forPath:taken:)` MUST each be synchronous and non-throwing,
  and none MUST perform network access, read or write a database, or store
  anything on `ProjectReconciler` itself, which declares no stored property
  of any kind (`ProjectReconciler.swift`).
- **reconciler-isolation-free**: `ProjectReconciler` MUST declare no `actor`
  or `@MainActor` isolation on itself or on any of its three static
  functions, so all three MUST be callable synchronously from any
  concurrency domain, matching the type doc comment's stated "Pure and
  `nonisolated`" intent (`ProjectReconciler.swift`).
- **plan-injection-closure-not-sendable-annotated**: The type of
  `isStillARepository` is a plain function value taking a `String` and
  returning a `Bool`; unlike `GitRepoScanner`'s `isCancelled` and
  `onProgress` parameters, it carries no `@Sendable` annotation, so nothing
  in this file's own signature obliges a caller-supplied closure to be safe
  to invoke from a different concurrency domain than the one that
  constructed it (`ProjectReconciler.swift`, contrast
  `GitRepoScanner.swift`).
- **duplicate-existing-path-handling**: `plan(existing:scanned:now:isStillARepository:)` does not validate that `existing` holds at most one row per `path`; it relies on its caller, and the `git_repo` table that `ProjectDatabase` reads `existing` from declares `path TEXT NOT NULL UNIQUE`, so database-supplied rows never repeat a path. A caller that passes hand-built rows with a repeated path gets the path-keyed lookup's last-wins behavior: the earlier row can never be matched by the exact-path pass and, if its own path still exists on disk, never appears in `inserts`, `updates`, or `deletes`.
- **duplicate-scanned-path-handling**: NEEDS REVIEW: Not implemented in source. `plan(existing:scanned:now:isStillARepository:)` never validates that `scanned` holds at most one entry per `path`; two `ScannedGitRepo` values sharing one path — plausible when a caller configures overlapping scan roots — are each processed independently through the exact-path pass and the unmatched-scan pass, so they can produce two separate `updates` entries carrying the same existing row's `id`, or two separate `inserts` for what is really one directory. What is missing: whether `GitRepoScanner` guarantees unique paths across a whole multi-root scan, or whether `plan` is expected to deduplicate its own input before matching. What would settle it: a doc-comment statement of that precondition on `scanned`, or evidence that overlapping roots are never a supported configuration.

## Appearance

Not applicable — this is a matching algorithm, not a visual component.

## States

Not applicable — this is a matching algorithm, not a visual component.

## Accessibility

Not applicable — this is a matching algorithm, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-reconciler-001 | insert-unique-name, insert-fresh-fields | `testAnUnknownPathBecomesAnInsert`: `existing` empty, one scan at `/Users/someone/dev/whippet` with a remote. | One insert with `path`/`name`/`remote`/`firstSeen`/`lastSeen` matching the scan and `now`; `plan.summary.added == 1`. |
| git-client-projects-project-reconciler-002 | insert-unique-name | `testASecondRepoWithTheSameLeafNameIsQualifiedByItsParent`: an existing row named `api` at `work/api`, plus scans of `work/api` (matches) and `oss/api` (new, same leaf name). | The new insert's `name` is `"oss/api"`, not `"api"`; `plan.summary.added == 1`, `plan.summary.unchanged == 1`. |
| git-client-projects-project-reconciler-003 | unique-name-escalation | `testUniqueNameWalksUpUntilItIsFree`: `uniqueName(forPath: "/a/b/c", taken: [])`. | Returns `"c"`. |
| git-client-projects-project-reconciler-004 | unique-name-escalation | Same test: `uniqueName(forPath: "/a/b/c", taken: ["c"])`. | Returns `"b/c"`. |
| git-client-projects-project-reconciler-005 | unique-name-escalation, unique-name-exhausted-fallback | Same test: `uniqueName(forPath: "/a/b/c", taken: ["c", "b/c"])`. | Returns `"a/b/c"` — the full path is still short of the exhausted-fallback boundary, since the leading separator is stripped by the component filter. |
| git-client-projects-project-reconciler-006 | exact-path-match-remote-update | `testAnUnchangedRepoProducesNoWrite`: an existing row and a scan at the same path with the same remote. | `inserts` and `updates` are both empty; `plan.summary.unchanged == 1`. |
| git-client-projects-project-reconciler-007 | exact-path-match-remote-update, exact-path-match-increments-unchanged | `testARepointedRemoteIsWrittenBack`: same path, remote changes from `"old-url"` to `"new-url"`. | The one `updates` entry has `remote == "new-url"` and `name` unchanged; `plan.summary.unchanged == 1` even though this row also produced a write. |
| git-client-projects-project-reconciler-008 | move-by-remote-priority, move-preserves-identity-and-name | `testAMovedRepoIsMatchedByItsRemote`: existing row at `old/alpha` named `"My Alpha"` with a remote; scan at `new/renamed-folder` with the same remote. | `inserts` is empty; the one `updates` entry has the original `id`, `path == "new/renamed-folder"`, and `name == "My Alpha"`; `plan.summary.moved == 1`; `deletes` is empty. |
| git-client-projects-project-reconciler-009 | move-by-name-fallback | `testARepoWithNoRemoteIsMatchedByItsDirectoryName`: existing row at `old/alpha` with no remote; scan at `new/alpha` with no remote. | The one `updates` entry has `path == "new/alpha"`; `plan.summary.moved == 1`; `inserts` is empty. |
| git-client-projects-project-reconciler-010 | move-by-remote-requires-uniqueness, unmatched-move-becomes-delete | `testAnAmbiguousMoveDeletesTheRow`: existing row with a remote; two scans at different paths sharing that same remote. | `plan.summary.moved == 0`; `plan.summary.removed == 1`; `inserts` has both scans as two new rows; `deletes` holds the original row's `id`. |
| git-client-projects-project-reconciler-011 | move-precedes-insert, move-claims-target-path | `testAMoveIsResolvedBeforeTheNewPathIsAdopted`: existing row at `old/alpha` with a remote; one scan at `new/alpha` with the same remote. | `inserts` is empty; `updates` has exactly one entry (the move), not a move plus a separate insert of the same destination path. |
| git-client-projects-project-reconciler-012 | delete-whatever-remains | `testAVanishedRepoIsDeleted`: one existing row; no scans at all. | `inserts` and `updates` are both empty; `deletes` holds the row's `id`; `plan.summary.removed == 1`. |
| git-client-projects-project-reconciler-013 | exact-path-match-increments-unchanged, move-by-remote-priority, delete-whatever-remains, insert-unique-name | `testTheSummaryCountsEveryRepoExactlyOnce`: three existing rows (one stays, one moves, one vanishes) plus a fourth brand-new scan. | `plan.summary.unchanged == 1`, `moved == 1`, `removed == 1`, `added == 1`. |
| git-client-projects-project-reconciler-014 | unreachable-path-skipped-not-deleted | A missing row whose `isStillARepository` override returns `true` for its path, with no scan reporting that path. | The row appears in none of `inserts`, `updates`, or `deletes`; `plan.summary.skipped == 1` and `plan.summary.removed == 0`. |
| git-client-projects-project-reconciler-015 | repository-exists-check | `repositoryExists(atPath:)` called on a directory whose `.git` entry exists as an empty regular file (no `HEAD`, not a directory). | Returns `true` — existence alone is checked, unlike `GitRepoScanner.isGitDirectory(_:)`, which additionally requires a directory containing `HEAD`. |
| git-client-projects-project-reconciler-016 | plan-defaults | `plan(existing: existingRows, scanned: scannedRows)` called with no `now` and no `isStillARepository` argument. | Every timestamp written into `inserts`/`updates` reflects the moment of the call, and any missing row's disk check runs through the real `FileManager`-backed `repositoryExists(atPath:)`. |
| git-client-projects-project-reconciler-017 | duplicate-existing-path-handling | Two existing rows share one `path`; one scan reports that same path with no remote change. | Cannot arise from `ProjectDatabase` (`path` is `UNIQUE`); for hand-built input, only the row that happens to occupy the path-keyed lookup last is matched and counted toward `unchanged`; the other row is silently absent from `inserts`, `updates`, and `deletes`. |
| git-client-projects-project-reconciler-018 | duplicate-scanned-path-handling | `existing` is empty; two scans share one `path` with two different remotes. | Current, undefined-contract behavior: `plan(...)` produces two separate `inserts`, each a distinct new `GitRepo` with a distinct fresh `id`, for what is one directory on disk. |

## Edge Cases

- **Null and empty input**: An `existing` array and a `scanned` array that are
  both empty MUST cause `plan(...)` to return a `Plan` whose `inserts`,
  `updates`, and `deletes` are all empty and whose `summary` has every count
  at its default of zero, since none of the four passes has anything to
  iterate (`ProjectReconciler.swift`). MUST.
  A scanned or existing `remote` of the empty string is treated as
  equivalent to `nil` for the purposes of `move-by-remote-priority` (the
  `!remote.isEmpty` guard rejects it) and for `move-by-name-fallback`'s
  eligibility check (`(remote ?? "").isEmpty`), even though `GitRepo` and
  `ScannedGitRepo` themselves store `nil` and `""` as distinct values
  (`ProjectReconciler.swift`). MUST.
- **Boundary values**: A single-component relative path such as `"alpha"`
  (no leading separator) produces exactly one path component from
  `URL(fileURLWithPath:).pathComponents`, so `uniqueName(forPath:taken:)`'s
  loop runs exactly once and either returns `"alpha"` or falls through to
  the exhausted-fallback return of the same string
  (`ProjectReconciler.swift`). MUST. When every possible
  suffix candidate — including the full path — is already in `taken`,
  `uniqueName(forPath:taken:)` returns the original `path` string verbatim
  rather than producing a numbered or otherwise disambiguated name, so two
  calls in the same `plan(...)` run can only collide if the caller
  populates `taken` with every level of one candidate's own ancestry in
  advance; ordinary use (seeding `taken` from existing row names) does not
  reach this boundary in the given tests (`ProjectReconciler.swift`). MUST.
- **Concurrent access**: `plan(...)`, `repositoryExists(atPath:)`, and
  `uniqueName(forPath:taken:)` hold all of their mutable state in local
  variables, and their parameter and return types (`GitRepo`,
  `ScannedGitRepo`, `ProjectReconciler.Plan`) are all `Sendable`, so multiple
  concurrent calls with independent inputs cannot race against each other
  or against any state owned by `ProjectReconciler` itself, which declares
  none (`ProjectReconciler.swift`). MUST. The
  `isStillARepository` closure parameter's type carries no `@Sendable`
  annotation (see `plan-injection-closure-not-sendable-annotated`), so a
  caller that hands `plan(...)` a closure capturing mutable state shared
  with another concurrency domain is not protected by this file's type
  signature; the default `ProjectReconciler.repositoryExists` captures
  nothing and is safe to call from anywhere. MUST.
- **Error states**: No function in this file can throw. `repositoryExists`'s
  only failure surface — `FileManager.default.fileExists(atPath:)` — never
  throws either; a permission-denied ancestor directory, a `.git` path that
  never existed, and a path on an unmounted volume all collapse to the same
  `false` result, which `plan(...)` then treats identically to "genuinely
  gone" (`ProjectReconciler.swift`). This collapsing is
  exactly what the doc comment on `repositoryExists` describes as the
  intended, sole test ("its existence is the whole test,"),
  not a swallowed error. MUST.
- **Offline or disconnected state**: Not applicable — nothing in this file
  makes a network call; its only I/O is the local filesystem existence
  check inside `repositoryExists(atPath:)`.
- **Missing file or unreachable directory**: A missing row's `path` that no
  longer exists at all on disk (the ordinary "vanished repository" case)
  causes `isStillARepository` to return `false`, so the row proceeds
  normally into the move pass and, absent a match, into `deletes`
  (`ProjectReconciler.swift`; verified by
  `testAVanishedRepoIsDeleted`). MUST.
- **Cancellation and timeouts**: Not applicable — `plan(...)`,
  `repositoryExists(atPath:)`, and `uniqueName(forPath:taken:)` are all
  synchronous, non-`async` computations with nothing to cancel and no
  operation that can run long enough to time out.
- **Duplicate paths in the inputs**: See `duplicate-existing-path-handling`
  (a caller precondition the database schema enforces) and the open question
  on duplicate-scanned-path-handling; the source neither rejects nor
  normalizes either.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `existing` (`plan` parameter) | `[GitRepo]` | none — required | The registry's current rows, as read by the caller (a `ProjectDatabase`) before scanning. |
| `scanned` (`plan` parameter) | `[ScannedGitRepo]` | none — required | What a directory walk (`GitRepoScanner`) just found. |
| `now` (`plan` parameter) | `Date` | `Date()` at the call | The timestamp written into every touched row's `lastSeen`, and into `firstSeen`/`lastSeen` for a new insert. |
| `isStillARepository` (`plan` parameter) | `(String) -> Bool` | `ProjectReconciler.repositoryExists` | Consulted once per missing row to decide skip-versus-delete; injected so `plan` itself never touches the filesystem. |
| `path` (`repositoryExists` parameter) | `String` | none — required | The candidate directory to check for a `.git` entry. |
| `path` (`uniqueName` parameter) | `String` | none — required | The scanned repository's path to derive a display name from. |
| `taken` (`uniqueName` parameter) | `Set<String>` | none — required | Names already in use; the caller seeds it from every existing row's `name` and grows it across one `plan` call's insert pass. |

No function in this file reads an environment variable or a settings key;
every input arrives as an explicit parameter.

## Deep Linking

Not applicable: `ProjectReconciler.swift` defines no URL scheme, route, or
navigation destination.

## Localization

Not applicable: `ProjectReconciler.swift` produces no user-facing string —
its only outputs are `GitRepo` values and `ProjectScanSummary` counts, both
data, not text for display. (The English sentence `ProjectScanSummary`
renders from those counts is a separate file's contract; see the
`git-client-projects-git-repo` recipe's Localization section.)

## Accessibility Options

Not applicable: `ProjectReconciler.swift` renders nothing, so Reduce Motion,
Increase Contrast, and Differentiate Without Color have no surface here to
apply to.

## Feature Flags

Not applicable: `ProjectReconciler.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `ProjectReconciler.swift` makes no analytics or
event-tracking call.

## Privacy

- **Data collected**: `plan(...)` reads and returns `GitRepo.path` (an
  absolute filesystem path) and `remote`/`ScannedGitRepo.remote` (a git
  remote URL read elsewhere and passed through) exactly as its inputs
  supply them, with no inspection, redaction, or transformation
  (`ProjectReconciler.swift`).
- **Storage**: None — this file returns a `Plan` value to its caller and
  persists nothing itself; writing the plan's rows to a database is a
  separate component's responsibility.
- **Transmission**: None — this file makes no network call.
- **Retention**: Not applicable — a `Plan` value's lifetime is entirely the
  caller's responsibility once `plan(...)` returns.

## Logging

Not applicable: `ProjectReconciler.swift` contains no `Logger`, `os.log`,
`print`, or any other logging call; the caller (`ProjectsCoordinator`) is
the one that logs a per-row write failure after applying the plan this file
produces.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift`,
  a plain Foundation file (`import Foundation` only) with no dependency on
  SwiftUI, AppKit, or UIKit; it ports unchanged into any Swift target that
  also has `GitRepo.swift`.
- **Compose**: Model `plan` as a top-level function or a Kotlin `object`
  with no instance state, taking `List<GitRepo>`, `List<ScannedGitRepo>`,
  and an `Instant` in place of `Date`. Build the path lookup with a
  `mutableMapOf<String, GitRepo>()`, the seen-ids and claimed-paths sets
  with `mutableSetOf()`, and port the LIFO-free, single-pass loops directly;
  `uniqueName` becomes a function over `java.io.File(path).toPath().nameCount`
  or a manual split on `File.separator`.
- **React/Web**: Port `plan` as a pure function over plain arrays and a
  `Map`/`Set`, taking `number` (epoch millis) in place of `Date`; there is
  no filesystem distinction to preserve since a Node-hosted port of
  `repositoryExists` would use `fs.existsSync(path.join(p, ".git"))`, matching
  the "existence is the whole test" contract exactly. `uniqueName` ports as
  a function over `path.sep`-split segments with the same escalating-suffix
  loop.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file
  is tied to a UI framework; it ports unchanged to either. An iOS host would
  still need its own, separately-contracted `isStillARepository` that
  respects the App Sandbox rather than calling `FileManager` against an
  arbitrary path.
- **WinUI 3**: Port `plan` as a static method on a static class, taking
  `IReadOnlyList<GitRepo>`, `IReadOnlyList<ScannedGitRepo>`, a
  `DateTimeOffset`, and a `Func<string, bool>` in place of the closure
  parameter. Build the path lookup with a `Dictionary<string, GitRepo>`, the
  seen-ids and claimed-paths sets with `HashSet<Guid>`/`HashSet<string>`, and
  keep the same three-pass order (exact match, then moves, then inserts,
  then whatever remains is deleted) rather than reordering it into LINQ
  joins, since the ordering itself (moves claiming a path before inserts
  run) is part of the contract. Port `repositoryExists` with
  `System.IO.Directory.Exists`/`File.Exists` against `System.IO.Path.Combine(path, ".git")`
  rather than `Windows.Storage`, since this is ordinary local-disk access,
  not packaged-app storage. Port `uniqueName` with
  `System.IO.Path.GetFileName`/manual splitting on `System.IO.Path.DirectorySeparatorChar`
  and the same escalating-suffix loop; no `Task`/`async` is needed anywhere
  in this port, since every operation here is synchronous in the source.

## Design Decisions

**Decision**: A `.git` entry's mere existence — not its being a directory,
not its containing `HEAD` — is `repositoryExists(atPath:)`'s whole test,
even though the file's own scanner sibling (`GitRepoScanner.isGitDirectory(_:)`)
applies both of those stricter checks.
**Rationale**: The doc comment states it directly: "`.git` is a directory in
an ordinary checkout and a file in a worktree or a submodule, so its
existence is the whole test" (`ProjectReconciler.swift`) —
`repositoryExists` only needs to tell "still something here" from "gone,"
not to classify what kind of git artifact is present the way the scanner's
stricter detection does when deciding whether to report a new project.
**Approved**: pending

**Decision**: `isStillARepository` is a parameter injected into `plan(...)`
with a default of `ProjectReconciler.repositoryExists`, rather than `plan`
calling `repositoryExists` directly by name.
**Rationale**: The doc comment ties this to `dependency-injection`
explicitly: it keeps "the reconciler ... pure and testable without a
filesystem" (`ProjectReconciler.swift`), which is exactly how
every test in `ProjectReconcilerTests.swift` exercises the skip-versus-delete
boundary without touching disk.
**Approved**: pending

**Decision**: The move pass matches by remote first and only falls back to
directory-name equality when both sides have no remote to compare.
**Rationale**: The doc comment gives the reasoning for the ordering (two
checkouts of the same remote are "the same project moved, in the
overwhelming case," `ProjectReconciler.swift`) and for the name
fallback's narrower condition: "a name is only evidence when there is no
remote on either side to disagree about," since two unrelated directories
can share a leaf name and re-pointing one at the other would hand its
settings to a stranger (`ProjectReconciler.swift`).
**Approved**: pending

**Decision**: A move candidate must be unique or the row is deleted instead
of guessed at.
**Rationale**: The doc comment states the cost of guessing wrong directly:
"a guess here silently re-points a project's settings at the wrong folder"
(`ProjectReconciler.swift`), which the ambiguous-match test
confirms produces two fresh inserts and one deletion rather than one lucky
guess.
**Approved**: pending

**Decision**: A row whose path the scan did not report, but which
`isStillARepository` says is still a repository, is left in place — neither
moved nor deleted — rather than treated as absent.
**Rationale**: The doc comment distinguishes "not reported" from "lost":
such a row might be missing only because "the user added a skip pattern, a
parent directory turned unreadable, [or] a scan root moved," and deleting on
that evidence "cascades the project's settings, layout, tabs, pane state and
window frame away with no undo" (`ProjectReconciler.swift`). The
same comment accepts the opposite cost for a genuinely absent path — "a
project on an unmounted volume is forgotten and comes back as new" — as a deliberate, asymmetric trade-off rather than an oversight.
**Approved**: pending

**Decision**: The move pass runs, and claims its matched paths, before the
insert pass considers any scanned repository new.
**Rationale**: The doc comment states the ordering constraint plainly: "a
moved repository must claim its new path before the adoption pass below
turns that same path into a brand-new project" (`ProjectReconciler.swift`) — reversing the order would let a legitimately moved
repository lose its identity, settings, and layout to a fresh row.
**Approved**: pending

**Decision**: `summary.unchanged` is incremented for every exact-path match,
even one that also produced a write to `updates` for a changed remote.
**Rationale**: Not stated directly in a doc comment; reading the code path,
`summary.unchanged` answers "was this row still the same repository at the
same path" while `updates` answers "did any field on it need correcting" —
two different questions the source keeps separate rather than conflating,
matching the same pattern the `git-client-projects-git-repo` recipe records
for `ProjectScanSummary`'s other counts (`unchanged` never appearing in
`summaryText`'s parts list, `skipped` displayed as "not scanned").
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `ProjectReconciler.swift` does
exactly one thing — match scan results against known rows — and delegates
walking the filesystem to `GitRepoScanner`, persisting rows to
`ProjectDatabase`, and presenting progress to `ProjectsCoordinator` and its
progress window, none of which leaks into this file. unit-test-coverage is
partial: `ProjectReconcilerTests.swift` exercises every branch of `plan(...)`
directly (inserts, unchanged, remote updates, remote-based moves,
name-based moves, ambiguous moves, move-before-insert ordering, deletes, and
the summary counts) and `uniqueName(forPath:taken:)`'s escalation directly,
but `repositoryExists(atPath:)` is only ever exercised incidentally, as the
default `isStillARepository` argument hitting the real filesystem at
ephemeral test paths, never by a dedicated test asserting its true/false
contract against a constructed `.git` entry, and `uniqueName`'s
exhausted-fallback branch has no test at all. idempotent-operations
passes: the doc comment and `testAnUnchangedRepoProducesNoWrite`'s own name
tie the exact-path pass's "no update when nothing changed" behavior directly
to re-running a scan over an unchanged tree producing no database write.
data-integrity is partial because of the open question on
duplicate-scanned-path-handling: overlapping scan roots can report one
directory twice and silently produce two rows for it, with nothing in this
file detecting it. Duplicate `existing` rows are excluded by the `git_repo`
table's `UNIQUE` path constraint rather than by this file.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
