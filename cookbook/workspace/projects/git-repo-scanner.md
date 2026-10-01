---
id: 3bec9b27-a9e3-4716-b516-688cc7f5a1c5
title: Git Repository Scanner
domain: agentictoolkit://cookbook/workspace/projects/git-repo-scanner
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Walks directory trees for git working trees, skipping hidden, pruned, symlinked,
  and user-configured folders, and reports each repository's path and origin remote.
platforms:
- swift
- macos
tags:
- git
- projects
- file-system
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepo.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Projects/UserSettings+Projects.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Projects/GitRepoScannerTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Git Repository Scanner

## Overview

The git repository scanner walks one or more directory trees looking for
git working trees ("projects"). It skips hidden dot-directories and known
build or dependency folders at every depth, skips symbolic links at every
depth, and skips caller-supplied glob patterns only directly under a scan
root. A directory holding a working `.git` directory (one with a `HEAD`
file) is reported as a scanned repository and is not descended into; a
`.git` that is a file rather than a directory (an absorbed submodule or a
linked worktree) is skipped entirely; a `.git` directory with no `HEAD` (a
hook-only folder) is ignored and the walk continues underneath it. Each
found repository's origin remote is read directly out of `.git/config`,
never by invoking the `git` executable. Scanning runs synchronously off the
main execution context, checks cancellation and reports progress once per
visited directory, and returns results sorted by path so repeated scans of
an unchanged tree are byte-identical.

## Behavioral Requirements

- **default-scan-root**: Construction MUST default `roots` to the current
  user's home directory when the caller passes no value.
- **default-skip-patterns**: Construction MUST default `rootSkipPatterns`
  to the built-in default skip patterns (`["Library", "Music", "Pictures",
  "Movies", "Dropbox", "* Dropbox", "Google Drive"]`) when the caller
  supplies no value.
- **hidden-directories-excluded**: The descend decision MUST return false
  for any child whose name begins with `.`, at every depth.
- **pruned-directories-excluded**: The descend decision MUST return false
  for any child whose name is exactly `node_modules`, `venv`,
  `__pycache__`, `build`, `dist`, `target`, `Pods`, or `Carthage`, at every
  depth.
- **root-level-skip-patterns**: The descend decision MUST return false for
  a child at depth exactly 1 whose name matches any pattern in
  `rootSkipPatterns`, and MUST NOT apply `rootSkipPatterns` at depth 0 or at
  any depth greater than 1.
- **case-insensitive-pattern-matching**: Comparing a folder name against a
  pattern MUST be case-insensitive.
- **symbolic-links-excluded**: The descend decision MUST return false for
  any child that is a symbolic link, at every depth, regardless of whether
  it also matches a skip pattern or is a directory.
- **git-directory-repository-detection**: A child directory MUST be treated
  as a repository only when it directly contains an entry named `.git`
  that is itself a directory and that directory contains a file named
  `HEAD`; detection MUST check for that `HEAD` file's existence inside the
  candidate `.git` directory.
- **hook-only-git-folder-not-a-repository**: A `.git` directory that exists
  but contains no `HEAD` file MUST NOT be treated as a repository, and the
  walk MUST continue into that directory's own children.
- **git-file-skipped-entirely**: When a child directory contains a `.git`
  entry that is not itself a directory (a submodule gitlink or a linked
  worktree's `.git` file), the walk MUST skip that directory and MUST NOT
  descend into its subtree.
- **repository-not-descended-into**: Once a directory is recognized as a
  repository under `git-directory-repository-detection`, the walk MUST NOT
  descend into that directory's children.
- **single-scanned-git-repo-per-repository**: For each directory recognized
  as a repository, the walk MUST append exactly one scanned-repository
  result whose `path` is that directory's path and whose `remote` is the
  origin remote read from that directory's `.git` directory.
- **origin-remote-extraction**: Reading the origin remote MUST parse the
  `.git/config` file as line-oriented INI text, MUST locate the section
  whose trimmed, space-stripped line equals the literal string
  `[remote"origin"]`, and within that section MUST return the trimmed
  value after the first `=` on the first line whose trimmed key equals
  `url`.
- **origin-remote-absent-cases**: Reading the origin remote MUST return no
  value when the `config` file cannot be read as UTF-8 text, when no
  `[remote "origin"]` section is present, or when that section's `url`
  value is empty after trimming whitespace.
- **sorted-idempotent-results**: A scan MUST return its accumulated results
  sorted ascending by `path` string comparison, both when it completes
  normally and when it stops early due to cancellation.
- **progress-reported-per-visited-directory**: For every directory popped
  from the walk's stack, a scan MUST report progress exactly once, before
  reading that directory's children, carrying the running count of
  directories visited, the count of repositories found so far, and the
  directory's current path.
- **cancellation-checked-per-directory**: Before processing each directory
  popped from the walk's stack, a scan MUST check for cancellation; when
  cancellation is signaled, the scan MUST stop immediately and return the
  results accumulated so far, sorted per `sorted-idempotent-results`.
- **default-callbacks-are-no-ops**: Scanning MUST default the cancellation
  check to one that always reports "not cancelled" and MUST default
  progress reporting to none when the caller supplies neither.
- **depth-first-stack-traversal**: A scan MUST traverse using a
  last-in-first-out stack of (location, depth) pairs seeded with each root
  at depth `0`, popping the most recently pushed entry and pushing each
  descended child at `depth + 1`.
- **multiple-roots-scanned-independently**: When `roots` contains more than
  one location, a scan MUST walk each root in the order given, accumulating
  every root's results into one combined array before the final sort.
- **concurrent-scans-are-independent**: The scanner MUST be safely usable
  across concurrent contexts, and a scan MUST hold all of its mutable
  traversal state (the results found so far, the visited set, the
  traversal stack) local to that one call rather than in any shared state
  of the scanner itself; the reported progress value MUST likewise be
  safely usable across concurrent contexts.
- **unreadable-directory-error-visibility**: NEEDS REVIEW: Not implemented.
  When reading a directory's contents fails — permission denied, or a root
  that does not exist on disk — the scan catches the error and moves on
  with no log call, no distinct field on the reported progress, and no
  entry in the returned array or any other value the scan produces; the
  failure is not surfaced to the caller in any observable form. What is
  missing: whether "skip silently" is the intended contract for every
  unreadable directory including a wholly missing scan root, or whether
  such directories should be counted, logged, or otherwise distinguished
  from a directory that was simply empty. What would settle it: a
  doc-comment statement of the intended observability, or evidence from a
  caller that a missing or unreadable root is surfaced to the user through
  some other path.

## Appearance

Not applicable — this is a directory-tree scanner, not a visual component.

## States

Not applicable — this is a directory-tree scanner, not a visual component.

## Accessibility

Not applicable — this is a directory-tree scanner, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-git-repo-scanner-001 | single-scanned-git-repo-per-repository, origin-remote-extraction | Scan a tree containing one repo at `dev/alpha` with origin `git@example.com:someone/alpha.git`. | Returns one scanned repository for `dev/alpha` whose remote equals `git@example.com:someone/alpha.git` and whose leaf name equals `alpha`. |
| git-client-projects-git-repo-scanner-002 | repository-not-descended-into | Scan a tree with a repo at `dev/alpha` containing another repo at `dev/alpha/external/toolkit`. | Returns exactly one result, `dev/alpha`; the nested repo is never reported. |
| git-client-projects-git-repo-scanner-003 | git-file-skipped-entirely | Scan a tree where `dev/worktree/.git` is a file containing `gitdir: ...`, and `dev/alpha` is a real repo. | Returns only `dev/alpha`; `dev/worktree` is absent. |
| git-client-projects-git-repo-scanner-004 | hook-only-git-folder-not-a-repository | Scan a tree where `dev/container/.git/hooks/` exists with no `HEAD`. | Returns an empty array. |
| git-client-projects-git-repo-scanner-005 | hook-only-git-folder-not-a-repository | Scan the same hook-only `dev/container/.git`, plus real repos at `dev/container/alpha` and `dev/container/beta`. | Returns both `dev/container/alpha` and `dev/container/beta`. |
| git-client-projects-git-repo-scanner-006 | hidden-directories-excluded | Scan a tree with a repo at `.claude/worktrees/feature` and one at `dev/alpha`. | Returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-007 | root-level-skip-patterns, default-skip-patterns | Scan, with default patterns, a tree with repos under `Library/`, `Music/`, `Pictures/`, `Movies/`, `Dropbox/`, `Google Drive/`, plus `dev/alpha`. | Returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-008 | root-level-skip-patterns, case-insensitive-pattern-matching | Scan a tree with a repo at `Acme Dropbox/shared/checkout`, plus `dev/alpha`. | Returns only `dev/alpha`; the `* Dropbox` pattern excludes `Acme Dropbox`. |
| git-client-projects-git-repo-scanner-009 | case-insensitive-pattern-matching | Scan, with default patterns (which include `Google Drive`), a tree with a repo at `google drive/checkout` (lowercase). | Returns an empty array. |
| git-client-projects-git-repo-scanner-010 | root-level-skip-patterns | Scan, with `rootSkipPatterns: ["Arch*"]`, a tree with repos under `Music/`, `Archive/beta`, `dev/alpha`. | Returns `Music/somebody-elses-checkout` and `dev/alpha`, but not `Archive/beta`. |
| git-client-projects-git-repo-scanner-011 | root-level-skip-patterns | Scan, with `rootSkipPatterns: []`, a tree with a repo under `Library/`. | Returns `Library/somebody-elses-checkout`. |
| git-client-projects-git-repo-scanner-012 | root-level-skip-patterns | Scan, with default patterns, a tree with repos at `dev/Library/gamma`, `dev/Pictures/delta`, `dev/Acme Dropbox/epsilon`. | Returns all three, because the matched names are at depth 2, not depth 1. |
| git-client-projects-git-repo-scanner-013 | pruned-directories-excluded | Scan a tree with a repo under `dev/<pruned>/vendored` for every one of the pruned directory names, plus `dev/alpha`. | Returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-014 | symbolic-links-excluded | Scan a tree with a repo at `dev/alpha`, plus a symlink `mirror` pointing at `dev`. | Returns only `dev/alpha`; the symlink is not followed. |
| git-client-projects-git-repo-scanner-015 | sorted-idempotent-results | Scan a tree with repos at `dev/zeta`, `dev/alpha`, `work/beta`. | Returns them in path order (`dev/alpha`, `dev/zeta`, `work/beta`); scanning again on the same scanner returns an equal array. |
| git-client-projects-git-repo-scanner-016 | multiple-roots-scanned-independently, sorted-idempotent-results | Scan an empty temporary directory as the sole root. | Returns an empty array without failing. |
| git-client-projects-git-repo-scanner-017 | progress-reported-per-visited-directory | Scan a tree with one repo at `dev/alpha`, recording every reported "directories visited" value. | At least one progress report is recorded, and the last recorded value equals the total number of reports (every visited directory is reported exactly once). |
| git-client-projects-git-repo-scanner-018 | cancellation-checked-per-directory | Scan a tree with repos at `dev/alpha` and `work/beta`, with the cancellation check always reporting "cancelled". | Returns an empty array. |
| git-client-projects-git-repo-scanner-019 | origin-remote-extraction | Read the origin remote from a `.git/config` with both `[remote "upstream"]` and `[remote "origin"]` sections, each with a different `url`. | Returns the `origin` section's URL, `git@example.com:someone/alpha.git`, not the `upstream` URL. |
| git-client-projects-git-repo-scanner-020 | origin-remote-absent-cases | Read the origin remote from a `.git/config` containing only `[core]\n\tbare = false`. | Returns no value. |
| git-client-projects-git-repo-scanner-021 | origin-remote-absent-cases | Read the origin remote from a `.git` directory with no `config` file at all. | Returns no value without failing. |
| git-client-projects-git-repo-scanner-022 | default-scan-root | Construct a scanner with no arguments. | Its `roots` equal the current user's home directory. |
| git-client-projects-git-repo-scanner-023 | default-skip-patterns | Construct a scanner with no arguments. | Its `rootSkipPatterns` equal the built-in default skip patterns. |
| git-client-projects-git-repo-scanner-024 | git-directory-repository-detection | Check repository detection on a `.git` directory containing a `HEAD` file, and separately on one containing only `hooks/`. | The first check returns true; the second returns false. |
| git-client-projects-git-repo-scanner-025 | concurrent-scans-are-independent | From two concurrent calls, scan the same scanner instance over a tree containing several repos. | Both calls complete without a crash or data race and each returns the identical, correctly sorted full result set, since each call's mutable traversal state is local to that call. |
| git-client-projects-git-repo-scanner-026 | unreadable-directory-error-visibility | Construct a scan root directory, then remove read permission from one of its subdirectories before scanning a tree that also contains a real repo elsewhere. | Current, undefined-contract behavior: the scan completes normally, omits the unreadable subdirectory's contents from the result, and produces no log output, no error, and no distinguishing field on any progress report for that directory. |

## Edge Cases

- **Null and empty input**: An empty `roots` list MUST cause a scan to
  return an empty array immediately, since there is nothing to iterate. An
  empty `rootSkipPatterns` list MUST skip nothing by name at any depth, per
  `root-level-skip-patterns`.
- **Boundary values**: `rootSkipPatterns` is applied only when `depth == 1`
  exactly; at depth `0` (a scan root itself) and at any depth `2` or
  greater it is never consulted, per `root-level-skip-patterns`. MUST.
- **Concurrent access**: The scanner is safely usable across concurrent
  contexts and a scan keeps every piece of mutable traversal state local to
  the call (the results found so far, the visited set, the traversal
  stack); the only state shared across concurrent calls on one instance is
  the fixed `roots` and `rootSkipPatterns`, so multiple concurrent scans on
  the same instance MAY run with no synchronization and no shared-state
  hazard. MUST.
- **Error states**: Reading a directory's contents failing for any reason —
  permission denied, the directory disappearing mid-walk — is caught and
  skipped identically, with no distinction made between error causes and
  no signal returned to the caller; see the open question on
  `unreadable-directory-error-visibility`. A malformed or non-UTF-8
  `.git/config` is handled the same way as a config with no origin
  section: reading the origin remote returns no value in both cases, with
  no way for a caller to distinguish "corrupt" from "absent". MUST.
- **Offline or disconnected state**: Not applicable — this component makes
  no network call of any kind; its only I/O is local filesystem access and
  local file reads.
- **Missing file or unreachable root**: A root location that does not
  exist on disk is not special-cased; reading its contents fails exactly
  as it would for a permission-denied directory, and that root is silently
  skipped with the walk continuing to any remaining roots — see the open
  question on `unreadable-directory-error-visibility`. MUST.
- **Malformed config line endings**: Reading the origin remote splits
  `.git/config` text on newlines and trims each line of ordinary
  whitespace, which strips spaces and tabs but not a trailing carriage
  return; a `config` file using CRLF line endings MUST retain a trailing
  carriage return on the section-header comparison string and on any
  parsed `url` value, since ordinary whitespace trimming does not include
  it. This can cause the `[remote"origin"]` comparison to fail to match, or
  the returned remote string to carry a trailing carriage return, on a
  CRLF-encoded config. MUST (describes the actual, deterministic behavior;
  not a marker, since the source never declares an intent to normalize
  line endings).
- **Cancellation**: The cancellation check is consulted once per directory
  popped from the stack, before that directory's children are read; a
  cancellation observed partway through a multi-root scan MUST return only
  the repositories found before cancellation was observed, sorted. MUST.
- **Symlink cycles**: Because the descend decision excludes every symbolic
  link before it is ever pushed onto the stack, a symlink that would
  otherwise create a cycle (e.g. pointing at an ancestor directory) MUST
  NOT be traversed and therefore MUST NOT cause an infinite loop.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `roots` (construction parameter) | list of directory locations, optional | none given → the current user's home directory | Directories to scan; each is walked independently and results are combined. |
| `rootSkipPatterns` (construction parameter) | list of strings | the built-in default skip patterns | Glob patterns, matched case-insensitively, applied only to folder names found directly under a scan root. |
| `isCancelled` (scan parameter) | cancellation check | one that always reports "not cancelled" | Consulted once before each directory is processed; reporting "cancelled" stops the walk and returns results found so far. |
| `onProgress` (scan parameter) | progress callback, optional | none | Invoked once per visited directory with a running visited count, found count, and current path. |

This component itself reads no environment variable and no settings key.
The caller-side configuration point is a persisted skip-patterns setting
defaulting to the same built-in default skip patterns; a coordinating
component reads that setting's current value and passes it as the
`rootSkipPatterns` argument when it constructs a scanner — but that wiring
lives outside this component and is not part of its contract.

## Deep Linking

Not applicable: this component defines no URL scheme, route, or navigation
destination.

## Localization

Not applicable: this component produces no user-facing string. Its only
outputs are `path` (a filesystem path) and `remote` (a raw value copied
from `.git/config`), both data values passed through unchanged, not
localized UI text.

## Accessibility Options

Not applicable: this component renders nothing; Reduce Motion, Increase
Contrast, and Differentiate Without Color have no surface here to apply
to.

## Feature Flags

Not applicable: this component contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: this component makes no analytics or event-tracking call.

## Privacy

- **Data collected**: A scan returns each found repository's local
  filesystem `path` and its `remote` value read verbatim from
  `.git/config`'s `[remote "origin"]` `url`. A remote URL MAY embed
  credentials if the user's own git configuration does (for example a URL
  of the form `https://user:token@host/repo.git`); this component does not
  inspect, redact, or otherwise transform this value before returning it.
- **Storage**: None — this component does not persist its results; it only
  returns them to the caller of a scan.
- **Transmission**: None — this component makes no network call and
  transmits nothing.
- **Retention**: Not applicable — this component holds no results beyond
  the single scan call's return value; retention of the returned array is
  entirely the caller's responsibility.

## Logging

Not applicable: this component makes no logging call of any kind; its only
failure path (reading a directory's contents failing) is caught and
discarded with no log output — see the open question on
`unreadable-directory-error-visibility`.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift`,
  using Foundation's `FileManager`, `URL`, `URLResourceKey`, and the C
  `fnmatch`/`FNM_CASEFOLD` functions; its companion type `ScannedGitRepo`
  lives in `GitRepo.swift` in the same directory. Nothing here is
  SwiftUI-specific — the type has no view, no `@Observable`/`@Published`
  state, and touches no UI framework at all.
- **Compose**: Port `roots` and `rootSkipPatterns` as plain constructor
  parameters of a Kotlin class. Walk with `java.io.File.listFiles()` or
  `java.nio.file.Files.newDirectoryStream`, using an explicit
  `ArrayDeque<Pair<File, Int>>` as the LIFO stack in place of the Swift
  `stack` array. Java/Kotlin glob matching (`PathMatcher` via
  `FileSystems.getDefault().getPathMatcher("glob:...")`) is case-sensitive by
  default, so case-fold each name and pattern manually before comparing, in
  place of `FNM_CASEFOLD`. Parse `.git/config` with the same manual
  line-by-line scan rather than pulling in a full INI library, to preserve
  the "reads exactly the one section that matters" behavior.
- **React/Web**: A browser cannot walk a filesystem or read `.git/config` at
  all; a faithful port only exists in a Node-hosted process, using
  `fs.readdirSync`/`fs.promises.readdir` with `withFileTypes: true` (in
  place of the `URLResourceKey` lookups) and `fs.lstatSync().isSymbolicLink()`
  to exclude symlinks. Use `minimatch` with its `nocase: true` option in
  place of `fnmatch`+`FNM_CASEFOLD`. Read `.git/config` with
  `fs.readFileSync(configPath, 'utf8')` and reuse the same manual
  `[remote "origin"]` line scan.
- **AppKit / UIKit**: Identical to the SwiftUI note — `GitRepoScanner.swift`
  is UI-framework-independent. An iOS port faces a different constraint than
  a porting concern: the App Sandbox does not grant arbitrary access to a
  user's home directory the way this macOS-only file assumes, so an iOS port
  would need a user-picked folder (`UIDocumentPickerViewController`) or a
  security-scoped bookmark rather than defaulting to
  `FileManager.default.homeDirectoryForCurrentUser`.
- **WinUI 3**: Port the walk with
  `System.IO.Directory.EnumerateFileSystemEntries` (or
  `DirectoryInfo.EnumerateDirectories`/`EnumerateFiles`), wrapping each call
  in a `try`/`catch` over `UnauthorizedAccessException` and `IOException` the
  same way `contentsOfDirectory`'s `throws` is caught. Represent
  `rootSkipPatterns` as a `List<string>` matched case-insensitively with
  `System.IO.Enumeration.FileSystemName.MatchesSimpleExpression` (.NET has no
  direct `fnmatch` equivalent) rather than `Windows.Storage`, since nothing
  here is packaged-app storage. Read `.git\config` with
  `System.IO.File.ReadAllText` and reuse the same manual `[remote "origin"]`
  line scan rather than `System.Text.Json` or a full INI parser, since the
  format is not JSON. Represent `ScannedGitRepo` as a C# `record`, drive
  progress through an `IProgress<Progress>` callback in place of the
  `onProgress` closure, and check a `CancellationToken`'s
  `IsCancellationRequested` at the same per-directory granularity as
  `isCancelled()`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Projects/GitRepoScanner.swift` |

## Design Decisions

**Decision**: A `.git` directory that contains no `HEAD` file is not treated
as a repository, and the walk continues underneath it rather than stopping.
**Rationale**: The doc comment states the check is for a `.git` "one git
would actually open," since a hook-only `.git` folder "invents a project and
hides the real repositories underneath it" (`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: A `.git` entry that is a file rather than a directory causes
the whole containing directory to be skipped entirely, rather than being
treated as an empty repository or descended into.
**Rationale**: The doc comment explains that such a `.git` "is an absorbed
submodule or a linked worktree, neither of which is a project in its own
right" (`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: `rootSkipPatterns` is applied only at depth 1, never at any
other depth.
**Rationale**: The doc comment gives the reason directly: a folder named
`Music` eight levels down "is just a folder someone named that — quite
possibly a project's asset directory," unlike `~/Music`, which is a media
library (`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: A repository's origin remote is read by parsing
`.git/config` directly rather than by shelling out to `git config
--get remote.origin.url`.
**Rationale**: The type-level doc comment states the reasoning as a measured
cost: "200-odd `git config` subprocesses cost more than the whole walk"
(`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: `scan()` always returns its results sorted by path, including
when it stops early due to cancellation, rather than returning them in
discovery order.
**Rationale**: The doc comment ties the sort directly to test reliability:
results are "sorted by path so two scans of an unchanged tree produce
identical output" (`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: `defaultRootSkipPatterns` lists `"Dropbox"` and `"* Dropbox"`
as two separate entries rather than a single glob covering both.
**Rationale**: The doc comment explains the naming split directly: "Dropbox
appears twice because it names its folder two ways: `Dropbox` for a personal
account, `<Company> Dropbox` for a team one. A glob is the only way to cover
the second, and the first is not a glob" (`GitRepoScanner.swift`).
**Approved**: pending

**Decision**: An unreadable directory (a thrown `contentsOfDirectory` call)
is caught and skipped via `continue`, letting the walk proceed to the
remaining directories rather than aborting the whole scan.
**Rationale**: The inline comment states the reasoning directly: "An
unreadable directory is not a reason to abandon the walk — `~` has plenty of
them" (`GitRepoScanner.swift`). This decision explains why the
walk continues; it does not settle whether the resulting silence about
*which* directories were skipped is also intended — that is the open
question on `unreadable-directory-error-visibility`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | failed | Best Practices |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

Notes: separation-of-concerns passes because `GitRepoScanner.swift` does
exactly one thing — walk the filesystem and classify directories — and
delegates no UI or presentation concern to itself; policy above it
(reconciling scan results against known projects, presenting a settings
panel) lives in other files entirely. unit-test-coverage passes because
`GitRepoScannerTests.swift` exercises repository detection, every skip rule
(hidden, pruned, root-level pattern, symlink), pattern case-folding,
multi-root and empty-tree scans, cancellation, progress reporting, result
ordering, and all three `originRemote` branches. explicit-error-handling
fails because the `contentsOfDirectory` catch block
discards the thrown error completely — no log, no return value, no
`Progress` field — which is exactly the "silently swallowed" case the check
prohibits; this is the same gap recorded as
`unreadable-directory-error-visibility`. fault-tolerance passes because
every other form of unpredictable filesystem state this file encounters —
missing `HEAD`, a `.git` file instead of a directory, an unparseable or
missing `config`, a symlink cycle — is handled without a crash, via `try?`
and explicit case checks rather than by assuming well-formed input.
data-integrity is partial because a `.git/config` that is present but
corrupt (invalid UTF-8, or malformed INI text past the point the manual
parser expects) is treated identically to a config with no origin
configured — both yield `nil` from `originRemote(inGitDirectory:)` — so
corrupt data is never detected as corrupt or reported as such, only ever
observed as "no remote."

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/projects/. |
