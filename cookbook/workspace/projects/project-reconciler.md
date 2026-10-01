---
id: fcff7387-19aa-49ab-b75d-f0c7bfcdf27c
title: Project Reconciler
domain: agentictoolkit://cookbook/workspace/projects/project-reconciler
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
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

# Project Reconciler

## Overview

The reconciler is a stateless matching algorithm that turns "what a directory
scan just found" plus "what the registry already knew" into the records a
caller should write. Its one operation, the plan operation, matches each
scanned repository entry against the repository records already known, in a
fixed order: exact path matches first, then unresolved records are checked
against disk to tell "not reported" apart from "genuinely gone," then a move
pass matches a relocated repository by remote and, failing that, by
directory name, then whatever is still unclaimed becomes a new insert, and
whatever is still unaccounted for becomes a delete. The algorithm is pure and
side-effect-free so that "the interesting half of scanning" can be tested
without a database, a filesystem, or any particular execution context.
Nothing here performs I/O beyond the injectable repository-existence check;
reading the scan results off disk is the directory scanner's job (see the
`git-client-projects-git-repo-scanner` recipe), and writing the resulting
plan to a database is a separate caller's job.

## Behavioral Requirements

- **plan-struct-shape**: the plan result MUST carry four fields —
  `inserts`, `updates`, and `deletes`, each a list of repository records
  defaulting to empty, and `summary`, a scan-summary value defaulting to a
  freshly constructed instance.
- **exact-path-match-lookup**: the plan operation MUST build a lookup keyed
  by every existing record's `path` before considering any scanned
  repository, so a scanned repository's fate is decided by an exact string
  match against that lookup.
- **unmatched-scan-collection**: every scanned repository whose `path` is
  not a key in that lookup MUST be added to the set of scans available to
  the later move and insert passes, in the order the scanned list was
  given.
- **exact-path-match-remote-update**: when a scanned repository's `path`
  exactly matches a known record and that record's stored `remote` differs
  from the scanned `remote`, the plan operation MUST overwrite the record's
  `remote` with the scanned value, MUST set its `lastSeen` to the current
  time, and MUST append the mutated record to `updates`; when the two
  `remote` values are equal, the plan operation MUST NOT append anything to
  `updates` for that record.
- **exact-path-match-increments-unchanged**: the plan operation MUST
  increment `summary.unchanged` by exactly one for every scanned repository
  whose path exactly matches a known record, regardless of whether that
  same record was also just appended to `updates` for a remote change — a
  record can count toward `unchanged` and appear in `updates` in the same
  call.
- **missing-rows-exclude-seen**: after the exact-path pass, the plan
  operation MUST narrow the candidates for the skip, move, and delete
  passes to existing records whose `id` was not marked seen during that
  pass.
- **unreachable-path-skipped-not-deleted**: a missing record for which the
  repository-existence check returns `true` for that record's `path` MUST
  be excluded from both the move pass and the delete pass, and the count of
  such records MUST be added to `summary.skipped` rather than
  `summary.removed`.
- **move-by-remote-priority**: for a missing record whose `remote` is
  present and non-empty, the plan operation MUST consider only unclaimed
  scanned repositories whose `remote` equals that exact string as move
  candidates before ever consulting directory-name equality.
- **move-by-remote-requires-uniqueness**: the plan operation MUST use a
  remote-based candidate as the match only when exactly one unclaimed
  scanned repository shares the missing record's `remote`; when zero or
  more than one share it, the plan operation MUST fall back to the
  directory-name comparison instead.
- **move-by-name-fallback**: the plan operation MUST match a missing record
  to an unclaimed scanned repository by directory-name equality — the
  scanned repository's leaf directory name equal to the default name
  derived from the missing record's path — only when both the missing
  record's `remote` and the candidate's `remote` are absent or the empty
  string, and only when exactly one such candidate exists.
- **unmatched-move-becomes-delete**: a missing record for which neither the
  remote pass nor the name pass yields a unique candidate MUST remain
  unresolved after the move pass and MUST end up in `deletes`.
- **move-preserves-identity-and-name**: when a missing record is matched,
  the plan operation MUST keep that record's `id` and `name` unchanged,
  MUST overwrite its `path` and `remote` with the matched scan's values,
  MUST set its `lastSeen` to the current time, MUST append it to `updates`,
  and MUST NOT also append it to `inserts`.
- **move-claims-target-path**: the plan operation MUST record a matched
  scan's `path` as claimed at the moment the match is made, so that no
  later iteration of the move pass, and no later evaluation of the insert
  pass, can match that same scanned path a second time.
- **move-precedes-insert**: the plan operation MUST resolve every possible
  move before evaluating any scanned repository for insertion, so a
  repository's destination path after a move is never also treated as a
  brand-new project.
- **insert-unique-name**: for every scanned repository left unclaimed after
  the move pass, the plan operation MUST derive its name with a
  uniqueness-escalation rule (see `unique-name-escalation`), seeding the
  taken-names set from every existing record's current `name` and adding
  each newly assigned name to that set before processing the next unclaimed
  scan in the same call, so two repositories inserted by one call MUST NOT
  receive the same name.
- **insert-fresh-fields**: each newly inserted repository record MUST take
  its `path` and `remote` from the unmatched scan and MUST set both
  `firstSeen` and `lastSeen` to the current time, leaving `id` to default
  to a freshly generated unique identifier.
- **delete-whatever-remains**: the plan operation MUST place every missing
  record that the skip pass and the move pass left unresolved into
  `deletes`, and MUST set `summary.removed` to the count of that final
  list.
- **plan-defaults**: the plan operation MUST default the current time to
  the moment of the call and MUST default the repository-existence check to
  its own built-in filesystem check when the caller supplies neither.
- **repository-exists-check**: the repository-existence check MUST return
  whether an entry named `.git` exists directly under the given path, and —
  since existence alone is the whole test — MUST NOT additionally check
  whether that entry is a directory or contains a `HEAD` file.
- **unique-name-escalation**: the naming rule MUST split a path into its
  non-separator path components and MUST try, in order, the shortest
  trailing run of one component, then two, and so on, each joined with
  `/`, returning the first such candidate that is not a member of the
  taken-names set.
- **unique-name-empty-path**: the naming rule MUST return the path
  unchanged when it has no non-separator components.
- **unique-name-exhausted-fallback**: when every candidate through the
  full path, including the full path itself, is already present in the
  taken-names set, the naming rule MUST return the path unchanged, exactly
  as it was passed in, rather than appending a disambiguating suffix of any
  kind.
- **plan-pure-and-side-effect-free**: the plan operation, the
  repository-existence check, and the naming rule MUST each be synchronous
  and non-throwing, and none MUST perform network access, read or write a
  database, or store any state of its own between calls.
- **duplicate-existing-path-handling**: the plan operation does not
  validate that the existing records hold at most one entry per `path`; it
  relies on its caller, and the registry's storage layer enforces a
  uniqueness constraint on `path`, so stored records never repeat a path. A
  caller that passes hand-built records with a repeated path gets the
  path-keyed lookup's last-wins behavior: the earlier record can never be
  matched by the exact-path pass and, if its own path still exists on disk,
  never appears in `inserts`, `updates`, or `deletes`.
- **duplicate-scanned-path-handling**: NEEDS REVIEW: Not implemented in
  source. The plan operation never validates that the scanned entries hold
  at most one entry per `path`; two scanned entries sharing one path —
  plausible when a caller configures overlapping scan roots — are each
  processed independently through the exact-path pass and the
  unmatched-scan pass, so they can produce two separate `updates` entries
  carrying the same existing record's `id`, or two separate `inserts` for
  what is really one directory. What is missing: whether the directory
  scanner guarantees unique paths across a whole multi-root scan, or
  whether the plan operation is expected to deduplicate its own input
  before matching. What would settle it: a documented precondition on the
  scanned input, or evidence that overlapping roots are never a supported
  configuration.

## Appearance

Not applicable — this is a matching algorithm, not a visual component.

## States

Not applicable — this is a matching algorithm, not a visual component.

## Accessibility

Not applicable — this is a matching algorithm, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-project-reconciler-001 | insert-unique-name, insert-fresh-fields | No existing records; one scanned repository at `/Users/someone/dev/whippet` with a remote. | One insert with `path`/`name`/`remote`/`firstSeen`/`lastSeen` matching the scan and the current time; `plan.summary.added == 1` — ProjectReconcilerTests.swift › testAnUnknownPathBecomesAnInsert |
| git-client-projects-project-reconciler-002 | insert-unique-name | An existing record named `api` at `work/api`, plus scans of `work/api` (matches) and `oss/api` (new, same leaf directory name). | The new insert's `name` is `"oss/api"`, not `"api"`; `plan.summary.added == 1`, `plan.summary.unchanged == 1` — ProjectReconcilerTests.swift › testASecondRepoWithTheSameLeafNameIsQualifiedByItsParent |
| git-client-projects-project-reconciler-003 | unique-name-escalation | Path `/a/b/c`; no names taken. | Returns `"c"` — ProjectReconcilerTests.swift › testUniqueNameWalksUpUntilItIsFree |
| git-client-projects-project-reconciler-004 | unique-name-escalation | Path `/a/b/c`; name `c` already taken. | Returns `"b/c"` — ProjectReconcilerTests.swift › testUniqueNameWalksUpUntilItIsFree |
| git-client-projects-project-reconciler-005 | unique-name-escalation, unique-name-exhausted-fallback | Path `/a/b/c`; names `c` and `b/c` already taken. | Returns `"a/b/c"` — the full path is still short of the exhausted-fallback boundary, since the leading separator is stripped by the component filter — ProjectReconcilerTests.swift › testUniqueNameWalksUpUntilItIsFree |
| git-client-projects-project-reconciler-006 | exact-path-match-remote-update | An existing record and a scan at the same path with the same remote. | `inserts` and `updates` are both empty; `plan.summary.unchanged == 1` — ProjectReconcilerTests.swift › testAnUnchangedRepoProducesNoWrite |
| git-client-projects-project-reconciler-007 | exact-path-match-remote-update, exact-path-match-increments-unchanged | Same path; remote changes from `old-url` to `new-url`. | The one `updates` entry has `remote == "new-url"` and `name` unchanged; `plan.summary.unchanged == 1` even though this record also produced a write — ProjectReconcilerTests.swift › testARepointedRemoteIsWrittenBack |
| git-client-projects-project-reconciler-008 | move-by-remote-priority, move-preserves-identity-and-name | An existing record at `old/alpha` named `My Alpha` with a remote; a scan at `new/renamed-folder` with the same remote. | `inserts` is empty; the one `updates` entry has the original `id`, `path == "new/renamed-folder"`, and `name == "My Alpha"`; `plan.summary.moved == 1`; `deletes` is empty — ProjectReconcilerTests.swift › testAMovedRepoIsMatchedByItsRemote |
| git-client-projects-project-reconciler-009 | move-by-name-fallback | An existing record at `old/alpha` with no remote; a scan at `new/alpha` with no remote. | The one `updates` entry has `path == "new/alpha"`; `plan.summary.moved == 1`; `inserts` is empty — ProjectReconcilerTests.swift › testARepoWithNoRemoteIsMatchedByItsDirectoryName |
| git-client-projects-project-reconciler-010 | move-by-remote-requires-uniqueness, unmatched-move-becomes-delete | An existing record with a remote; two scans at different paths sharing that same remote. | `plan.summary.moved == 0`; `plan.summary.removed == 1`; `inserts` has both scans as two new records; `deletes` holds the original record's `id` — ProjectReconcilerTests.swift › testAnAmbiguousMoveDeletesTheRow |
| git-client-projects-project-reconciler-011 | move-precedes-insert, move-claims-target-path | An existing record at `old/alpha` with a remote; one scan at `new/alpha` with the same remote. | `inserts` is empty; `updates` has exactly one entry (the move), not a move plus a separate insert of the same destination path — ProjectReconcilerTests.swift › testAMoveIsResolvedBeforeTheNewPathIsAdopted |
| git-client-projects-project-reconciler-012 | delete-whatever-remains | One existing record; no scans at all. | `inserts` and `updates` are both empty; `deletes` holds the record's `id`; `plan.summary.removed == 1` — ProjectReconcilerTests.swift › testAVanishedRepoIsDeleted |
| git-client-projects-project-reconciler-013 | exact-path-match-increments-unchanged, move-by-remote-priority, delete-whatever-remains, insert-unique-name | Three existing records (one stays, one moves, one vanishes) plus a fourth brand-new scan. | `plan.summary.unchanged == 1`, `moved == 1`, `removed == 1`, `added == 1` — ProjectReconcilerTests.swift › testTheSummaryCountsEveryRepoExactlyOnce |
| git-client-projects-project-reconciler-014 | unreachable-path-skipped-not-deleted | A missing record whose repository-existence check returns `true` for its path, with no scan reporting that path. | The record appears in none of `inserts`, `updates`, or `deletes`; `plan.summary.skipped == 1` and `plan.summary.removed == 0` |
| git-client-projects-project-reconciler-015 | repository-exists-check | The repository-existence check called on a directory whose `.git` entry exists as an empty regular file (no `HEAD`, not a directory). | Returns `true` — existence alone is checked, unlike the directory scanner's own stricter check, which additionally requires a directory containing `HEAD` |
| git-client-projects-project-reconciler-016 | plan-defaults | The plan operation called with no explicit current time and no repository-existence-check override. | Every timestamp written into `inserts`/`updates` reflects the moment of the call, and any missing record's disk check runs through the real filesystem-backed repository-existence check |
| git-client-projects-project-reconciler-017 | duplicate-existing-path-handling | Two existing records share one `path`; one scan reports that same path with no remote change. | Cannot arise from the registry's storage layer (`path` is enforced unique); for hand-built input, only the record that happens to occupy the path-keyed lookup last is matched and counted toward `unchanged`; the other record is silently absent from `inserts`, `updates`, and `deletes` |
| git-client-projects-project-reconciler-018 | duplicate-scanned-path-handling | Existing records are empty; two scans share one `path` with two different remotes. | Current, undefined-contract behavior: the plan operation produces two separate `inserts`, each a distinct new record with a distinct fresh `id`, for what is one directory on disk |

## Edge Cases

- **Null and empty input**: An existing list and a scanned list that are
  both empty MUST cause the plan operation to return a plan value whose
  `inserts`, `updates`, and `deletes` are all empty and whose `summary` has
  every count at its default of zero, since none of the four passes has
  anything to iterate. MUST.
  A scanned or existing `remote` of the empty string is treated as
  equivalent to an absent value for the purposes of `move-by-remote-priority`
  (the non-empty check rejects it) and for `move-by-name-fallback`'s
  eligibility check, even though the repository record and the scanned
  entry themselves store an absent value and an empty string as distinct
  values. MUST.
- **Boundary values**: A single-component relative path such as `"alpha"`
  (no leading separator) produces exactly one path component, so the
  naming rule's loop runs exactly once and either returns `"alpha"` or
  falls through to the exhausted-fallback return of the same string. MUST.
  When every possible suffix candidate — including the full path — is
  already in the taken-names set, the naming rule returns the original
  path string verbatim rather than producing a numbered or otherwise
  disambiguated name, so two calls in the same plan-operation run can only
  collide if the caller populates the taken-names set with every level of
  one candidate's own ancestry in advance; ordinary use (seeding the set
  from existing record names) does not reach this boundary in the given
  tests. MUST.
- **Concurrent access**: the plan operation, the repository-existence
  check, and the naming rule hold all of their mutable state in local
  variables, and their parameter and return types are safe to share across
  concurrent calls, so multiple concurrent calls with independent inputs
  cannot race against each other or against any state owned by the
  reconciler itself, which holds none. MUST. The repository-existence-check
  parameter carries no guarantee that a caller-supplied check is safe to
  invoke from a different execution context than the one that constructed
  it (see Platform Notes for the detail); the default
  built-in check captures nothing and is safe to call from anywhere. MUST.
- **Error states**: No part of this algorithm can throw. The
  repository-existence check's only failure surface never throws either; a
  permission-denied ancestor directory, a `.git` path that never existed,
  and a path on an unmounted volume all collapse to the same `false`
  result, which the plan operation then treats identically to "genuinely
  gone." This collapsing is exactly the intended, sole test ("its existence
  is the whole test"), not a swallowed error. MUST.
- **Offline or disconnected state**: Not applicable — nothing here makes a
  network call; its only I/O is the local filesystem existence check
  inside the repository-existence check.
- **Missing file or unreachable directory**: A missing record's `path`
  that no longer exists at all on disk (the ordinary "vanished repository"
  case) causes the repository-existence check to return `false`, so the
  record proceeds normally into the move pass and, absent a match, into
  `deletes`. MUST.
- **Cancellation and timeouts**: Not applicable — the plan operation, the
  repository-existence check, and the naming rule are all synchronous
  computations with nothing to cancel and no operation that can run long
  enough to time out.
- **Duplicate paths in the inputs**: See `duplicate-existing-path-handling`
  (a caller precondition the registry's storage layer enforces) and the
  open question on `duplicate-scanned-path-handling`; nothing here rejects
  or normalizes either.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `existing` (plan input) | list of repository records | none — required | The registry's current records, as read by the caller before scanning. |
| `scanned` (plan input) | list of scanned repository entries | none — required | What a directory walk just found. |
| `now` (plan input) | point in time | current time at the call | The timestamp written into every touched record's `lastSeen`, and into `firstSeen`/`lastSeen` for a new insert. |
| `isStillARepository` (plan input) | path-to-boolean check | the built-in repository-existence check | Consulted once per missing record to decide skip-versus-delete; injected so the plan operation itself never touches the filesystem. |
| `path` (repository-existence check input) | string | none — required | The candidate directory to check for a `.git` entry. |
| `path` (naming rule input) | string | none — required | The scanned repository's path to derive a display name from. |
| `taken` (naming rule input) | set of strings | none — required | Names already in use; the caller seeds it from every existing record's `name` and grows it across one plan call's insert pass. |

Nothing here reads an environment variable or a settings key; every input
arrives as an explicit parameter.

## Deep Linking

Not applicable: the reconciler defines no URL scheme, route, or navigation
destination.

## Localization

Not applicable: the reconciler produces no user-facing string — its only
outputs are repository records and scan-summary counts, both data, not text
for display. (The English sentence the scan summary renders from those
counts is a separate component's contract; see the
`git-client-projects-git-repo` recipe's Localization section.)

## Accessibility Options

Not applicable: the reconciler renders nothing, so Reduce Motion, Increase
Contrast, and Differentiate Without Color have no surface here to apply to.

## Feature Flags

Not applicable: the reconciler contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: the reconciler makes no analytics or event-tracking call.

## Privacy

- **Data collected**: the plan operation reads and returns each record's
  `path` (an absolute filesystem path) and `remote` (a git remote URL read
  elsewhere and passed through) exactly as its inputs supply them, with no
  inspection, redaction, or transformation.
- **Storage**: None — the plan operation returns a plan value to its caller
  and persists nothing itself; writing the plan's records to a database is
  a separate component's responsibility.
- **Transmission**: None — the reconciler makes no network call.
- **Retention**: Not applicable — a plan value's lifetime is entirely the
  caller's responsibility once the plan operation returns.

## Logging

Not applicable: the reconciler contains no logging call of any kind; the
caller (the projects coordinator) is the one that logs a per-record write
failure after applying the plan this component produces.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift`,
  a plain Foundation file (`import Foundation` only) with no dependency on
  SwiftUI, AppKit, or UIKit; it ports unchanged into any Swift target that
  also has `GitRepo.swift`. The `Plan` value conforms to `Sendable`, and the
  type declares no `actor` or `@MainActor` isolation on itself or on any of
  its three static functions, matching the type's own doc comment, which
  states it is "Pure and `nonisolated`" so it can be tested without a
  database, a filesystem, or a main actor. The `isStillARepository` closure
  parameter's type carries no `@Sendable` annotation — unlike
  `GitRepoScanner`'s `isCancelled` and `onProgress` parameters — so nothing
  in this file's own signature obliges a caller-supplied closure to be safe
  to invoke from a different concurrency domain than the one that
  constructed it; the default `ProjectReconciler.repositoryExists` captures
  nothing and is safe to call from anywhere.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift` |

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
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
