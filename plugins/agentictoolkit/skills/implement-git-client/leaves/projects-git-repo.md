<!-- leaf: implement-git-client/projects-git-repo · source: git-client-projects-git-repo.md -->

**Rules** (cite as `implement-git-client/projects-git-repo#<slug>`):

- `git-repo-stored-shape` MUST
- `git-repo-id-immutable` MUST
- `git-repo-default-id-generation` MUST
- `git-repo-mutable-tracking-fields` MUST
- `git-repo-default-timestamps` MUST
- `git-repo-path-and-name-required` MUST
- `git-repo-url-is-directory` MUST
- `git-repo-default-name-from-path` MUST
- `git-repo-name-seeding-convention` SHOULD
- `git-repo-structural-equatable` MUST
- `scanned-git-repo-no-identity` MUST
- `scanned-git-repo-remote-required` MUST
- `scanned-git-repo-leaf-name` MUST
- `scan-summary-default-zero-counts` MUST
- `scan-summary-fields-unvalidated` MUST
- `scan-summary-found-excludes-removed` MUST
- `scan-summary-text-headline-pluralization` MUST
- `scan-summary-text-part-selection` MUST
- `scan-summary-text-joining` MUST
- `sendable-value-semantics` MUST
- `git-repo-last-opened-may-remain-nil` MAY

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

