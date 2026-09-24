---
id: 1463e7a2-e290-4b8c-8643-df9462a758e6
title: GitRepo
domain: agentictoolkit://recipes/git-client-projects-git-repo
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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
- sendable
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

# GitRepo

## Overview

`GitRepo.swift` defines three related value types the project browser's scan
pipeline passes between its stages. `GitRepo` is the registry's row for a
repository the app already knows about — identified by a `UUID` rather than
its path, "because a repository that moves keeps its settings, its layout and
its name" once some other component re-points the row. `ScannedGitRepo`
is what a directory walk finds on disk before anything decides whether that
finding is new, moved, or already known — deliberately not a `GitRepo`,
because a scan result "has no identity yet". `ProjectScanSummary`
tallies what a scan changed (added/moved/removed/unchanged/skipped) and
renders that tally into the one line a log statement or a progress window's
closing message uses. None of the three performs any I/O, networking, or
persistence itself; they are the shapes other components (a scanner, a
reconciler, a database) pass to and from each other.

## Behavioral Requirements

- **git-repo-stored-shape**: `GitRepo` MUST store exactly seven properties —
  `id: UUID`, `path: String`, `name: String`, `remote: String?`,
  `firstSeen: Date`, `lastSeen: Date`, and `lastOpened: Date?` — and MUST
  conform to `Sendable`, `Identifiable`, and `Equatable`.
- **git-repo-id-immutable**: `GitRepo.id` MUST be a `let` constant set only at
  construction; no method or property on `GitRepo` MUST mutate it after
  `init` returns.
- **git-repo-default-id-generation**: `init` MUST generate a fresh, distinct
  `UUID` for `id` via `UUID()` when the caller supplies none.
- **git-repo-mutable-tracking-fields**: `path`, `name`, `remote`, `firstSeen`,
  `lastSeen`, and `lastOpened` MUST all be declared `var`, so a caller holding
  a `GitRepo` value MAY reassign any of them after construction without
  constructing a new value.
- **git-repo-default-timestamps**: `init` MUST default both `firstSeen` and
  `lastSeen` to `Date()` evaluated at construction time when the caller
  supplies no explicit value, and MUST default `remote` to `nil` and
  `lastOpened` to `nil`.
- **git-repo-path-and-name-required**: `init` MUST NOT provide a default
  value for `path` or `name`; every call site MUST supply both explicitly.
- **git-repo-url-is-directory**: `GitRepo.url` MUST construct
  `URL(fileURLWithPath: path, isDirectory: true)`, always passing `true` for
  `isDirectory` regardless of whether `path` currently exists on disk or is
  actually a directory, "because a repository's path is one" and because the
  resulting `URL` "is compared for equality against checkout directories
  built elsewhere".
- **git-repo-default-name-from-path**: `GitRepo.defaultName(forPath:)` MUST
  return `URL(fileURLWithPath: path).lastPathComponent` — the final path
  segment of the supplied string — and MUST NOT consult the filesystem to
  confirm that path exists or is a directory.
- **git-repo-name-seeding-convention**: Per the doc comment on `name` ("Seeded
  from the directory name, then the user's to change,"), a caller
  constructing a brand-new `GitRepo` SHOULD pass
  `GitRepo.defaultName(forPath:)` as the initial `name` and treat every
  subsequent value as the user's to rename; `init` itself enforces nothing
  here and MAY be called with any `name` string, including one unrelated to
  `path`.
- **git-repo-structural-equatable**: `GitRepo`'s `Equatable` conformance MUST
  be evaluated over every stored property, including `id`, `firstSeen`,
  `lastSeen`, and `lastOpened` — not `id` alone — so two values that name the
  "same" repository by `id` but disagree on any other field, including a
  timestamp, MUST compare unequal (synthesized memberwise
  conformance over the source).
- **git-repo-path-absoluteness**: The doc comment on `path` declares it "Absolute path to the working tree," a caller precondition: neither `init` nor `url`/`defaultName(forPath:)` validates that a supplied string is non-empty or absolute, so a relative path, an empty string, or a path containing `~` is stored and used unchanged.
- **scanned-git-repo-no-identity**: `ScannedGitRepo` MUST NOT declare an `id`
  or any other identity-bearing property; it MUST store only `path: String`
  and `remote: String?`, both `let`, and MUST conform to `Sendable` and
  `Equatable` but MUST NOT conform to `Identifiable` — per the doc comment,
  "a scan result has no identity yet: deciding whether it is a new
  repository, a moved one, or one already known is the reconciler's job".
- **scanned-git-repo-remote-required**: `ScannedGitRepo.init` MUST NOT
  provide a default value for `remote`; every call site MUST pass `nil`
  explicitly when the scanned repository has no remote, unlike
  `GitRepo.init`, which defaults `remote` to `nil`.
- **scanned-git-repo-leaf-name**: `ScannedGitRepo.leafName` MUST return
  `URL(fileURLWithPath: path).lastPathComponent` — the same computation
  `GitRepo.defaultName(forPath:)` performs, implemented separately on the
  scan-result type rather than shared — and MUST NOT consult the filesystem.
- **scan-summary-default-zero-counts**: `ProjectScanSummary.init()` MUST take
  no parameters and MUST leave `added`, `moved`, `removed`, `unchanged`, and
  `skipped` at their declared default of `0`.
- **scan-summary-fields-unvalidated**: `added`, `moved`, `removed`,
  `unchanged`, and `skipped` MUST all be declared `var` with no invariant
  enforced by `ProjectScanSummary` itself; any caller holding a value MAY set
  any of the five to a negative number or to a value inconsistent with the
  others, and no property on this type MUST detect or reject that.
- **scan-summary-found-excludes-removed**: `ProjectScanSummary.found` MUST
  return exactly `added + moved + unchanged + skipped`, and MUST NOT include
  `removed` in that sum — a repository the scan deleted is not counted among
  "every project in the registry once the scan has been applied".
- **scan-summary-text-headline-pluralization**: `summaryText`'s headline MUST
  read `"\(found) project"` when `found == 1` and `"\(found) projects"` for
  every other value of `found`, including `0`.
- **scan-summary-text-part-selection**: `summaryText` MUST append `"<n> new"`,
  `"<n> moved"`, `"<n> removed"`, and `"<n> not scanned"` to its parts list,
  in that fixed order, only for whichever of `added`, `moved`, `removed`, and
  `skipped` is strictly greater than `0`; `unchanged` MUST NOT appear in the
  parts list under any circumstance, regardless of its value.
- **scan-summary-text-joining**: When at least one part is selected,
  `summaryText` MUST join the headline and the parts with `" — "` (an em
  dash between spaces) and MUST join multiple parts with `", "`; when no part
  is selected, `summaryText` MUST instead append the literal suffix
  `", no changes"` to the headline.
- **sendable-value-semantics**: `GitRepo`, `ScannedGitRepo`, and
  `ProjectScanSummary` MUST each be safely usable across concurrency domains
  with no additional synchronization, on the strength of their `Sendable`
  conformance and their composition entirely from
  `Sendable` value types (`UUID`, `String`, `String?`, `Date`, `Date?`,
  `Int`); none declares an `actor` or `@MainActor` isolation, and none needs
  to, because every property access operates on the caller's own copy.
- **git-repo-last-opened-may-remain-nil**: `lastOpened` MAY remain `nil` for
  the entire lifetime of a `GitRepo` value; no property or method in this
  file ever sets or reads it — per the doc comment it exists so that
  whichever component opens a project window "sorts by" it, a responsibility
  outside this file.

## Appearance

Not applicable — this is a data model, not a visual component.

## States

Not applicable — this is a data model, not a visual component.

## Accessibility

Not applicable — this is a data model, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-git-repo-001 | git-repo-url-is-directory | `GitRepo(path: "/tmp/example", name: "example").url` | A file URL whose `path` is `/tmp/example` and whose `hasDirectoryPath` is `true`, regardless of whether `/tmp/example` exists. |
| git-client-projects-git-repo-002 | git-repo-default-name-from-path | `GitRepo.defaultName(forPath: "/Users/x/Projects/myrepo")` | Returns `"myrepo"`. |
| git-client-projects-git-repo-003 | scanned-git-repo-leaf-name | `GitRepoScannerTests.swift`: scan a directory named `alpha` containing a valid `.git`, then read `found.first?.leafName`. | Returns `"alpha"`. |
| git-client-projects-git-repo-004 | scan-summary-text-headline-pluralization, scan-summary-text-joining | `ProjectReconcilerTests.swift` (`testAQuietScanSaysSo`): a plan whose summary has `unchanged: 1` and every other count `0`. | `plan.summary.summaryText == "1 project, no changes"`. |
| git-client-projects-git-repo-005 | scan-summary-text-part-selection, scan-summary-text-joining | `ProjectReconcilerTests.swift` (`testTheSummaryCountsEveryRepoExactlyOnce`): a plan whose summary has `added: 1`, `moved: 1`, `removed: 1`, `unchanged: 1`. | `plan.summary.summaryText == "3 projects — 1 new, 1 moved, 1 removed"` (the one `unchanged` project is counted in `found` but never named). |
| git-client-projects-git-repo-006 | scan-summary-found-excludes-removed, scan-summary-text-part-selection | A `ProjectScanSummary` with `removed = 5` and every other count `0`. | `found == 0` and `summaryText == "0 projects — 5 removed"`. |
| git-client-projects-git-repo-007 | git-repo-structural-equatable | Two `GitRepo` values built with the same `id`, `path`, and `name`, but `firstSeen`/`lastSeen` passed as two different `Date` values. | The two values compare unequal with `==`. |
| git-client-projects-git-repo-008 | git-repo-default-id-generation, git-repo-default-timestamps | `GitRepo(path: "/tmp/a", name: "a")` constructed twice in immediate succession. | Each call produces a distinct `id`; the two values are unequal even though `path` and `name` match. |
| git-client-projects-git-repo-009 | scanned-git-repo-remote-required | Attempt to write `ScannedGitRepo(path: "/tmp/a")` with no `remote` argument. | Does not compile — `remote` has no default value, unlike `GitRepo.remote`. |

## Edge Cases

- **Null and empty input**: `path = ""` is accepted unchanged by every
  initializer that takes it and is forwarded verbatim
  into `url`, `defaultName(forPath:)`, and `leafName`,
  each of which builds `URL(fileURLWithPath:)` from it; Foundation resolves
  an empty or relative string relative to the process's current working
  directory rather than throwing or returning `nil`, so an empty `path`
  never fails construction but the resulting `url`/name describe wherever
  the process happens to be running, not a repository (MUST — see
  `git-repo-path-absoluteness`).
  `remote = ""` is a distinct `Optional.some("")` value from `remote = nil`;
  neither type normalizes the two together (MUST).
- **Boundary values**: A `ProjectScanSummary` with only `removed` set above
  zero reports `found == 0` while `summaryText` still lists the removals, so
  a project count of zero can appear alongside a non-empty list of changes
  (MUST, see `scan-summary-found-excludes-removed`,
  git-client-projects-git-repo-006). `summaryText`'s singular/plural boundary
  is exactly `found == 1`; both `0` and every value `2` and above pluralize
  to "projects" (MUST, `scan-summary-text-headline-pluralization`).
- **Concurrent access**: All three types are `Sendable` value types with no
  shared mutable reference state, no lock, and no actor isolation; every read or write operates on the caller's own copy, so
  concurrent access to independently-held instances from multiple threads
  cannot race (MUST, see `sendable-value-semantics`). This file defines no
  singleton, static `var`, or other ambiently-shared instance for concurrent
  callers to contend over.
- **Error states**: No initializer, and no computed property (`url`,
  `defaultName(forPath:)`, `leafName`, `found`, `summaryText`), can throw or
  signal failure through an `Optional`; this file calls no network,
  database, or file-system API of its own, so it has no error path to
  define (MUST NOT be conflated with `GitClient`'s or `ProjectDatabase`'s
  error handling, which are separate components with their own sources).
- **Offline or disconnected state**: Not applicable — no type in this file
  makes a network call or depends on connectivity; `remote` only stores a
  URL string another component already read out of `.git/config`.
- **Missing file or unreachable directory**: A `path` naming a directory
  that no longer exists on disk, or that never held a `.git` directory, is
  not detected by anything in this file — `url`, `defaultName(forPath:)`,
  and `leafName` derive their result from the string alone, and none calls
  `FileManager` to check existence (MUST).
- **Cancellation and timeouts**: Not applicable — every operation in this
  file (`init`, `url`, `defaultName(forPath:)`, `leafName`, `found`,
  `summaryText`) is a synchronous, non-blocking computation over in-memory
  values; none is `async`, none spawns a subprocess, and none has anything
  to cancel or time out.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `id` (`GitRepo.init`) | `UUID` | fresh `UUID()` | The row's stable identity; a caller reconstructing a known repository passes its existing `id` instead. |
| `path` (`GitRepo.init`) | `String` | none — required | The working tree's absolute path, per the doc comment; not validated as absolute (see `git-repo-path-absoluteness`). |
| `name` (`GitRepo.init`) | `String` | none — required | Display name; conventionally seeded from `GitRepo.defaultName(forPath:)` (see `git-repo-name-seeding-convention`). |
| `remote` (`GitRepo.init`) | `String?` | `nil` | `origin`'s URL as another component read it from `.git/config`; `nil` means no remote. |
| `firstSeen` (`GitRepo.init`) | `Date` | `Date()` at construction | When this row was first added to the registry. |
| `lastSeen` (`GitRepo.init`) | `Date` | `Date()` at construction | When a scan most recently confirmed this repository still exists. |
| `lastOpened` (`GitRepo.init`) | `Date?` | `nil` | When a project window was last opened for it; never set by this file. |
| `path` (`ScannedGitRepo.init`) | `String` | none — required | The path a directory walk found. |
| `remote` (`ScannedGitRepo.init`) | `String?` | none — required (no default; `nil` must be passed explicitly) | `origin`'s URL read from the found repository's `.git/config`, or `nil`. |
| (`ProjectScanSummary.init`) | — | all five counts `0` | Takes no parameters; a caller mutates the public `var` counts afterward. |

No type in this file reads an environment variable, a settings key, or any
injected dependency; the only "configuration" is the arguments passed to
each initializer.

## Deep Linking

Not applicable: no type in `GitRepo.swift` defines a URL scheme, route, or
navigation destination.

## Localization

`ProjectScanSummary.summaryText` builds a hardcoded English
sentence with no `String(localized:)` call, no `NSLocalizedString`, and no
localization key of any kind. Every fragment below is a literal in the
source, not a lookup:

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

Not applicable: no type in `GitRepo.swift` renders anything, so Reduce
Motion, Increase Contrast, and Differentiate Without Color have nothing to
apply to.

## Feature Flags

Not applicable: `GitRepo.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `GitRepo.swift` makes no analytics or event-tracking call.

## Privacy

- **Data collected**: `GitRepo.path` (an absolute filesystem path, which on a
  typical macOS home directory includes the user's account name) and
  `GitRepo.remote`/`ScannedGitRepo.remote` (a git remote URL another
  component read out of `.git/config`, stored verbatim). Neither type in
  this file inspects, validates, or redacts the `remote` string, so if that
  URL happens to embed user-info credentials (as a bare `https://` remote
  URL sometimes does), this file stores that string exactly as given, with
  no special handling.
- **Storage**: None performed by this file — `GitRepo`, `ScannedGitRepo`,
  and `ProjectScanSummary` are plain in-memory value types with no
  persistence code of their own; whatever writes them to disk (e.g. a
  database component) is a separate source not given here.
- **Transmission**: None — this file makes no network call.
- **Retention**: Not defined here; a value's lifetime is entirely up to its
  caller.

## Logging

Not applicable: `GitRepo.swift` contains no `Logger`, `os.log`, `print`, or
any other logging call.

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
