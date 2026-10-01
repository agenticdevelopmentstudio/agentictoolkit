---
id: 1463e7a2-e290-4b8c-8643-df9462a758e6
title: Git Repository Record
domain: agentictoolkit://cookbook/workspace/projects/git-repo
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The identity-bearing git repository record, its pre-identity scan result,
  and the scan summary a directory walk produces.
platforms:
- swift
- macos
tags:
- git
- projects
- value-type
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/GitRepoScannerTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/ProjectReconcilerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Git Repository Record

## Overview

This defines three related value types the project browser's scan pipeline
passes between its stages. The repository record is the registry's row for
a repository the app already knows about — identified by a unique id
rather than its path, "because a repository that moves keeps its settings,
its layout and its name" once some other component re-points the row. The
scanned repository is what a directory walk finds on disk before anything
decides whether that finding is new, moved, or already known — deliberately
a distinct shape from the repository record, because a scan result "has no
identity yet". The scan summary tallies what a scan changed
(added/moved/removed/unchanged/skipped) and renders that tally into the one
line a log statement or a progress window's closing message uses. None of
the three performs any I/O, networking, or persistence itself; they are the
shapes other components (a scanner, a reconciler, a database) pass to and
from each other.

## Behavioral Requirements

- **git-repo-stored-shape**: The repository record MUST store exactly
  seven fields — `id`, `path`, `name`, `remote`, `firstSeen`, `lastSeen`,
  and `lastOpened` — MUST be safely usable across concurrent contexts, MUST
  expose `id` as its stable identity, and MUST support equality comparison.
- **git-repo-id-immutable**: `id` MUST be fixed at construction; nothing on
  the repository record MUST mutate it afterward.
- **git-repo-default-id-generation**: Construction MUST generate a fresh,
  distinct unique identifier for `id` when the caller supplies none.
- **git-repo-mutable-tracking-fields**: `path`, `name`, `remote`,
  `firstSeen`, `lastSeen`, and `lastOpened` MUST all be mutable, so a caller
  holding a repository record MAY reassign any of them after construction
  without constructing a new value.
- **git-repo-default-timestamps**: Construction MUST default both
  `firstSeen` and `lastSeen` to the current time evaluated at construction
  when the caller supplies no explicit value, and MUST default `remote` and
  `lastOpened` to no value.
- **git-repo-path-and-name-required**: Construction MUST NOT provide a
  default value for `path` or `name`; every call site MUST supply both
  explicitly.
- **git-repo-url-is-directory**: The repository record's directory URL
  MUST always be built as a directory URL, regardless of whether `path`
  currently exists on disk or is actually a directory, "because a
  repository's path is one" and because the resulting URL "is compared for
  equality against checkout directories built elsewhere".
- **git-repo-default-name-from-path**: Deriving a default name from a path
  MUST return that path's final path segment, and MUST NOT consult the
  filesystem to confirm that path exists or is a directory.
- **git-repo-name-seeding-convention**: Per the doc comment on `name`
  ("Seeded from the directory name, then the user's to change,"), a caller
  constructing a brand-new repository record SHOULD seed `name` from the
  path's final path segment and treat every subsequent value as the
  user's to rename; construction itself enforces nothing here and MAY be
  called with any `name` string, including one unrelated to `path`.
- **git-repo-structural-equatable**: The repository record's equality MUST
  be evaluated over every stored field, including `id`, `firstSeen`,
  `lastSeen`, and `lastOpened` — not `id` alone — so two values that name
  the "same" repository by `id` but disagree on any other field, including
  a timestamp, MUST compare unequal (memberwise comparison over every
  field).
- **git-repo-path-absoluteness**: The doc comment on `path` declares it
  "Absolute path to the working tree," a caller precondition: nothing in
  this component validates that a supplied string is non-empty or
  absolute, so a relative path, an empty string, or a path containing `~`
  is stored and used unchanged.
- **scanned-git-repo-no-identity**: The scanned repository MUST NOT declare
  an `id` or any other identity-bearing field; it MUST store only `path`
  and `remote`, both fixed at construction, and MUST support safe
  concurrent use and equality comparison but MUST NOT be identifiable by a
  stable id — per the doc comment, "a scan result has no identity yet:
  deciding whether it is a new repository, a moved one, or one already
  known is the reconciler's job".
- **scanned-git-repo-remote-required**: Constructing a scanned repository
  MUST NOT provide a default value for `remote`; every call site MUST pass
  no value explicitly when the scanned repository has no remote, unlike the
  repository record's construction, which defaults `remote` to no value.
- **scanned-git-repo-leaf-name**: The scanned repository's leaf name MUST
  return `path`'s final path segment — the same computation the repository
  record's default-name derivation performs, implemented separately on the
  scan-result type rather than shared — and MUST NOT consult the
  filesystem.
- **scan-summary-default-zero-counts**: Constructing a scan summary with no
  arguments MUST leave `added`, `moved`, `removed`, `unchanged`, and
  `skipped` at their declared default of `0`.
- **scan-summary-fields-unvalidated**: `added`, `moved`, `removed`,
  `unchanged`, and `skipped` MUST all be mutable with no invariant enforced
  by the scan summary itself; any caller holding a value MAY set any of
  the five to a negative number or to a value inconsistent with the
  others, and nothing on this type MUST detect or reject that.
- **scan-summary-found-excludes-removed**: `found` MUST return exactly
  `added + moved + unchanged + skipped`, and MUST NOT include `removed` in
  that sum — a repository the scan deleted is not counted among "every
  project in the registry once the scan has been applied".
- **scan-summary-text-headline-pluralization**: The summary text's headline
  MUST read `"<found> project"` when `found == 1` and `"<found> projects"`
  for every other value of `found`, including `0`.
- **scan-summary-text-part-selection**: The summary text MUST append
  `"<n> new"`, `"<n> moved"`, `"<n> removed"`, and `"<n> not scanned"` to
  its parts list, in that fixed order, only for whichever of `added`,
  `moved`, `removed`, and `skipped` is strictly greater than `0`;
  `unchanged` MUST NOT appear in the parts list under any circumstance,
  regardless of its value.
- **scan-summary-text-joining**: When at least one part is selected, the
  summary text MUST join the headline and the parts with `" — "` (an em
  dash between spaces) and MUST join multiple parts with `", "`; when no
  part is selected, the summary text MUST instead append the literal
  suffix `", no changes"` to the headline.
- **value-type-concurrency-safety**: The repository record, the scanned
  repository, and the scan summary MUST each be safely usable across
  concurrent contexts with no additional synchronization, on the strength
  of being composed entirely of plain value data (identifiers, strings,
  optional strings, timestamps, optional timestamps, whole numbers); none
  declares any thread- or task-based isolation of its own, and none needs
  to, because every access operates on the caller's own copy.
- **git-repo-last-opened-may-remain-nil**: `lastOpened` MAY remain unset for
  the entire lifetime of a repository record; nothing in this component
  ever sets or reads it — per the doc comment it exists so that whichever
  component opens a project window "sorts by" it, a responsibility outside
  this component.

## Appearance

Not applicable — this is a data model, not a visual component.

## States

Not applicable — this is a data model, not a visual component.

## Accessibility

Not applicable — this is a data model, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-git-repo-001 | git-repo-url-is-directory | The directory URL of a repository record built with `path` `/tmp/example` and `name` `example`. | A file URL whose path is `/tmp/example` and whose directory flag is set, regardless of whether `/tmp/example` exists. |
| git-client-projects-git-repo-002 | git-repo-default-name-from-path | Derive a default name from the path `/Users/x/Projects/myrepo`. | Returns `myrepo`. |
| git-client-projects-git-repo-003 | scanned-git-repo-leaf-name | Scan a directory named `alpha` containing a valid git metadata directory, then read the first found result's leaf name. | Returns `alpha`. |
| git-client-projects-git-repo-004 | scan-summary-text-headline-pluralization, scan-summary-text-joining | A scan plan whose summary has `unchanged: 1` and every other count `0`; read its summary text. | Reads `"1 project, no changes"`. |
| git-client-projects-git-repo-005 | scan-summary-text-part-selection, scan-summary-text-joining | A scan plan whose summary has `added: 1`, `moved: 1`, `removed: 1`, `unchanged: 1`; read its summary text. | Reads `"3 projects — 1 new, 1 moved, 1 removed"` (the one `unchanged` project is counted in `found` but never named). |
| git-client-projects-git-repo-006 | scan-summary-found-excludes-removed, scan-summary-text-part-selection | A scan summary with `removed = 5` and every other count `0`. | `found == 0` and the summary text reads `"0 projects — 5 removed"`. |
| git-client-projects-git-repo-007 | git-repo-structural-equatable | Two repository records built with the same `id`, `path`, and `name`, but `firstSeen`/`lastSeen` given two different timestamps. | The two values compare unequal. |
| git-client-projects-git-repo-008 | git-repo-default-id-generation, git-repo-default-timestamps | A repository record with `path` `/tmp/a` and `name` `a`, constructed twice in immediate succession. | Each construction produces a distinct `id`; the two values are unequal even though `path` and `name` match. |
| git-client-projects-git-repo-009 | scanned-git-repo-remote-required | Attempt to construct a scanned repository with `path` `/tmp/a` and no `remote` argument. | Fails to build — `remote` has no default value, unlike the repository record's `remote` field, so omitting it is not accepted. |

## Edge Cases

- **Null and empty input**: An empty `path` is accepted unchanged by every
  constructor that takes it and is forwarded verbatim into the directory
  URL, the default-name derivation, and the leaf-name derivation, each of
  which builds a file URL from it; an empty or relative string resolves
  relative to the process's current working directory rather than failing
  construction, so an empty `path` never fails construction but the
  resulting URL/name describe wherever the process happens to be running,
  not a repository (MUST — see `git-repo-path-absoluteness`). An empty
  string for `remote` is a distinct value from no value at all; neither
  type normalizes the two together (MUST).
- **Boundary values**: A scan summary with only `removed` set above zero
  reports `found == 0` while the summary text still lists the removals, so
  a project count of zero can appear alongside a non-empty list of changes
  (MUST, see `scan-summary-found-excludes-removed`,
  git-client-projects-git-repo-006). The summary text's singular/plural
  boundary is exactly `found == 1`; both `0` and every value `2` and above
  pluralize to "projects" (MUST, `scan-summary-text-headline-pluralization`).
- **Concurrent access**: All three types are plain value types with no
  shared mutable reference state, no lock, and no thread- or task-based
  isolation of their own; every read or write operates on the caller's own
  copy, so concurrent access to independently-held instances from multiple
  threads cannot race (MUST, see `value-type-concurrency-safety`). This
  component defines no singleton, shared mutable global, or other
  ambiently-shared instance for concurrent callers to contend over.
- **Error states**: No constructor, and no derived value (the directory
  URL, the default-name derivation, the leaf-name derivation, `found`, the
  summary text), can fail or signal an error; this component calls no
  network, database, or file-system operation of its own, so it has no
  error path to define (MUST NOT be conflated with the git client's or the
  project database's error handling, which are separate components with
  their own sources).
- **Offline or disconnected state**: Not applicable — nothing in this
  component makes a network call or depends on connectivity; `remote` only
  stores a URL string another component already read out of
  `.git/config`.
- **Missing file or unreachable directory**: A `path` naming a directory
  that no longer exists on disk, or that never held a `.git` directory, is
  not detected by anything in this component — the directory URL, the
  default-name derivation, and the leaf-name derivation derive their
  result from the string alone, and none checks the filesystem for
  existence (MUST).
- **Cancellation and timeouts**: Not applicable — every operation in this
  component (construction, the directory URL, the default-name
  derivation, the leaf-name derivation, `found`, the summary text) is a
  synchronous, non-blocking computation over in-memory values; none is
  asynchronous, none spawns a subprocess, and none has anything to cancel
  or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` (repository record construction) | unique identifier | freshly generated | The row's stable identity; a caller reconstructing a known repository passes its existing `id` instead. |
| `path` (repository record construction) | string | none — required | The working tree's absolute path, per the doc comment; not validated as absolute (see `git-repo-path-absoluteness`). |
| `name` (repository record construction) | string | none — required | Display name; conventionally seeded from the path's final segment (see `git-repo-name-seeding-convention`). |
| `remote` (repository record construction) | string, optional | no value | `origin`'s URL as another component read it from `.git/config`; no value means no remote. |
| `firstSeen` (repository record construction) | timestamp | current time at construction | When this row was first added to the registry. |
| `lastSeen` (repository record construction) | timestamp | current time at construction | When a scan most recently confirmed this repository still exists. |
| `lastOpened` (repository record construction) | timestamp, optional | no value | When a project window was last opened for it; never set by this component. |
| `path` (scanned repository construction) | string | none — required | The path a directory walk found. |
| `remote` (scanned repository construction) | string, optional | none — required (no default; a no-value must be passed explicitly) | `origin`'s URL read from the found repository's `.git/config`, or no value. |
| (scan summary construction) | — | all five counts `0` | Takes no parameters; a caller mutates the counts afterward. |

Nothing in this component reads an environment variable, a settings key,
or any injected dependency; the only "configuration" is the arguments
passed to each constructor.

## Deep Linking

Not applicable: nothing in this component defines a URL scheme, route, or
navigation destination.

## Localization

The scan summary's summary text builds a hardcoded English sentence with
no localization key or lookup mechanism of any kind. Every fragment below
is a literal, not a lookup:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| none — literal in source | `"<n> project"` / `"<n> projects"` | Headline noun, singular when `found == 1`. |
| none — literal in source | `", no changes"` | Appended to the headline when no part is selected. |
| none — literal in source | `" — "` | Separator between the headline and the joined parts. |
| none — literal in source | `"<n> new"` | Appended when `added > 0`. |
| none — literal in source | `"<n> moved"` | Appended when `moved > 0`. |
| none — literal in source | `"<n> removed"` | Appended when `removed > 0`. |
| none — literal in source | `"<n> not scanned"` | Appended when `skipped > 0` — note the field is named `skipped` but the displayed word is "not scanned". |
| none — literal in source | `", "` | Joiner between multiple selected parts. |

## Accessibility Options

Not applicable: nothing in this component renders anything, so Reduce
Motion, Increase Contrast, and Differentiate Without Color have nothing to
apply to.

## Feature Flags

Not applicable: this component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: this component makes no analytics or event-tracking call.

## Privacy

- **Data collected**: `path` (an absolute filesystem path, which on a
  typical desktop home directory includes the user's account name) and
  `remote` (a git remote URL another component read out of `.git/config`,
  stored verbatim). Nothing in this component inspects, validates, or
  redacts the `remote` string, so if that URL happens to embed user-info
  credentials (as a bare `https://` remote URL sometimes does), it is
  stored exactly as given, with no special handling.
- **Storage**: None performed by this component — the repository record,
  the scanned repository, and the scan summary are plain in-memory value
  types with no persistence code of their own; whatever writes them to
  disk (e.g. a database component) is a separate source not given here.
- **Transmission**: None — this component makes no network call.
- **Retention**: Not defined here; a value's lifetime is entirely up to its
  caller.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift`, a
  plain Foundation file with no import beyond `Foundation` and no dependency
  on SwiftUI, AppKit, or UIKit at all — the three types are UI-framework-free
  and port unchanged into any Swift target.
- **Compose**: Model `GitRepo` as a Kotlin `data class` with a `UUID`
  (`java.util.UUID`) `id`, `String path`, `String name`, `String? remote`,
  and `java.time.Instant firstSeen`/`lastSeen`/`lastOpened?`; Kotlin's
  synthesized `equals`/`hashCode` on a `data class` already produce the same
  structural (not identity-only) equality this file's synthesized
  `Equatable` produces, so no extra work is needed to preserve that
  behavior. `ScannedGitRepo` and `ProjectScanSummary` port the same way,
  each as its own `data class`; `URL(fileURLWithPath:).lastPathComponent`
  becomes `java.io.File(path).name` (or `Path.of(path).fileName`).
- **React/Web**: A browser has no filesystem, so `path`/`url` have no direct
  analogue; if this pattern is ported into a Node-hosted process, represent
  `GitRepo` as a plain object or a small class with the same seven fields, an
  `id: string` (a UUID string or `crypto.randomUUID()`), and derive
  `defaultName`/`leafName` with `path.basename(p)` instead of
  `URL(fileURLWithPath:).lastPathComponent`. `summaryText`'s formatting logic
  ports as a pure function taking a plain `{added, moved, removed, unchanged,
  skipped}` object.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file
  is tied to a UI framework; it ports unchanged to either.
- **WinUI 3**: Port `GitRepo` as an immutable-`Id` C# `record` (or a class
  with a `readonly Guid Id`) with mutable `string Path`, `string Name`,
  `string? Remote`, `DateTimeOffset FirstSeen`, `LastSeen`, and
  `DateTimeOffset? LastOpened` — a C# `record`'s synthesized value equality
  already compares every property, matching this file's synthesized
  `Equatable` (including timestamps) with no extra code. Default `Id` to
  `Guid.NewGuid()` and `FirstSeen`/`LastSeen` to `DateTimeOffset.Now` in the
  constructor, mirroring `init`'s defaults. Port `url` as a computed
  `System.IO.DirectoryInfo`/`Uri` built from `Path`, and
  `defaultName(forPath:)`/`leafName` as
  `System.IO.Path.GetFileName(path.TrimEnd('\\', '/'))` — note that
  `Path.GetFileName` behaves differently from `URL.lastPathComponent` on a
  path ending in a separator, so a faithful port trims the trailing
  separator first. Port `ProjectScanSummary` as a small mutable class or
  `record struct` with five `int` properties and a computed `Found`/
  `SummaryText`, using `ObservableCollection`/`INotifyPropertyChanged` only
  if a bound UI needs to react to the counts changing — nothing in this
  file requires that on its own.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift` |

## Design Decisions

**Decision**: `GitRepo`'s `Equatable` conformance is the compiler-synthesized
one over every stored property, including `firstSeen`, `lastSeen`, and
`lastOpened` — not a hand-written conformance that compares `id` alone.
**Rationale**: The type's header doc comment states "the identity is the
`id`, not the path" to justify using a `UUID` as the primary key rather than
the path, but that statement is about which field a *database row* is keyed
on; it does not extend to `==`. Because `firstSeen`/`lastSeen` default to
`Date()` at construction time, two values built independently for what a
caller considers "the same" repository will almost always compare unequal —
a quirk a port must preserve deliberately rather than "fix" into
identity-based equality, or callers that rely on `==` (e.g. `Set` membership,
diffing) will behave differently than the source.
**Approved**: pending

**Decision**: `ProjectScanSummary` declares an explicit, parameterless
`public init() {}` even though every stored property already has a default
value.
**Rationale**: Swift only synthesizes a memberwise (or default,
parameterless) initializer at the same access level as the type when the
type is not `public`; for a `public` struct, the compiler-synthesized
initializer is `internal`, so a caller outside this module could not
construct a `ProjectScanSummary` at all without this explicit `public init()`
— the same reason `GitRepo.init` and `ScannedGitRepo.init` are both written out explicitly rather than relied upon as
synthesized.
**Approved**: pending

**Decision**: `ProjectScanSummary.found` sums `added + moved + unchanged +
skipped` but excludes `removed`.
**Rationale**: The doc comment on `found` calls it "every project in the
registry once the scan has been applied" — a repository the scan
determined to be `removed` is, by definition, no longer in the registry, so
counting it in `found` would overstate what is actually there. `summaryText`
still names removals in its parts list because reporting "what changed"
and reporting "what remains" are different facts, matching this file's
general pattern of not conflating adjacent-but-distinct counts (see also
`unchanged` never appearing in `summaryText`'s parts, and `skipped` field
name vs. its "not scanned" wording).
**Approved**: pending

**Decision**: `ScannedGitRepo` is a distinct type from `GitRepo` rather than
`GitRepo` with an optional `id`, and its `remote` parameter has no default
(unlike `GitRepo.remote`, which defaults to `nil`).
**Rationale**: The doc comment states directly that "a scan result has no
identity yet: deciding whether it is a new repository, a moved one, or one
already known is the reconciler's job" — giving `ScannedGitRepo`
an `id` field (even an optional one) would let a caller construct a
scan result that already claims an identity, which is exactly the ambiguity
this type is designed to prevent until reconciliation happens elsewhere.
Requiring `remote` explicitly (rather than defaulting it to `nil` the way
`GitRepo` does) keeps every scan-result construction site stating plainly
whether a remote was found, since omitting the argument by habit is easy to
do at a `GitRepo` call site but is not possible here.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |

Notes: separation-of-concerns passes because `GitRepo.swift` holds only data
shape and trivial, filesystem-free derived accessors (`url`, `defaultName`,
`leafName`, `found`, `summaryText`); scanning the disk lives in
`GitRepoScanner`, matching found results against known rows lives in
`ProjectReconciler`, and persisting rows lives in `ProjectDatabase` — none of
that infrastructure or business logic leaks into this file. unit-test-coverage
is partial because `GitRepo.swift` has no dedicated test file of its own;
`GitRepoScannerTests.swift` exercises `ScannedGitRepo.leafName` incidentally and `ProjectReconcilerTests.swift` exercises
`ProjectScanSummary.summaryText` through two scenarios, but
`GitRepo.url`, `GitRepo.defaultName(forPath:)`, both types' `Equatable`
conformance, and the `removed`-excluded-from-`found` behavior have no test
anywhere in the given sources.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation; documents the path-absoluteness open question. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
