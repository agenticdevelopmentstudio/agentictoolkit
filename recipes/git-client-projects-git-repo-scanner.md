---
id: 3bec9b27-a9e3-4716-b516-688cc7f5a1c5
title: GitRepoScanner
domain: agentictoolkit://recipes/git-client-projects-git-repo-scanner
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
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

# GitRepoScanner

## Overview

`GitRepoScanner` walks one or more directory trees looking for git working
trees ("projects"). It skips hidden dot-directories and known build or
dependency folders at every depth, skips symbolic links at every depth, and
skips caller-supplied glob patterns only directly under a scan root. A
directory holding a working `.git` directory (one with a `HEAD` file) is
reported as a `ScannedGitRepo` and is not descended into; a `.git` that is a
file rather than a directory (an absorbed submodule or a linked worktree) is
skipped entirely; a `.git` directory with no `HEAD` (a hook-only folder) is
ignored and the walk continues underneath it. Each found repository's origin
remote is read directly out of `.git/config`, never by invoking the `git`
executable. `scan()` runs synchronously off the main actor, checks
cancellation and reports progress once per visited directory, and returns
results sorted by path so repeated scans of an unchanged tree are
byte-identical.

## Behavioral Requirements

- **default-scan-root**: `init(roots:rootSkipPatterns:)` MUST default `roots`
  to `[FileManager.default.homeDirectoryForCurrentUser]` when the caller
  passes `nil` (`GitRepoScanner.swift`).
- **default-skip-patterns**: `init(roots:rootSkipPatterns:)` MUST default
  `rootSkipPatterns` to `GitRepoScanner.defaultRootSkipPatterns`
  (`["Library", "Music", "Pictures", "Movies", "Dropbox", "* Dropbox",
  "Google Drive"]`) when the caller supplies no value (`GitRepoScanner.swift`).
- **hidden-directories-excluded**: `shouldDescend(into:atDepth:)` MUST return
  `false` for any child whose name begins with `.`, at every depth
  (`GitRepoScanner.swift`).
- **pruned-directories-excluded**: `shouldDescend(into:atDepth:)` MUST return
  `false` for any child whose name is exactly `node_modules`, `venv`,
  `__pycache__`, `build`, `dist`, `target`, `Pods`, or `Carthage`
  (`GitRepoScanner.prunedDirectoryNames`), at every depth
  (`GitRepoScanner.swift`).
- **root-level-skip-patterns**: `shouldDescend(into:atDepth:)` MUST return
  `false` for a child at depth exactly 1 whose name matches any pattern in
  `rootSkipPatterns`, and MUST NOT apply `rootSkipPatterns` at depth 0 or at
  any depth greater than 1 (`GitRepoScanner.swift`).
- **case-insensitive-pattern-matching**: `GitRepoScanner.name(_:matches:)`
  MUST compare a folder name against a pattern using `fnmatch` with
  `FNM_CASEFOLD`, so pattern matching MUST be case-insensitive
  (`GitRepoScanner.swift`).
- **symbolic-links-excluded**: `shouldDescend(into:atDepth:)` MUST return
  `false` for any child that is a symbolic link, at every depth, regardless
  of whether it also matches a skip pattern or is a directory
  (`GitRepoScanner.swift`).
- **git-directory-repository-detection**: A child directory MUST be treated
  as a repository only when it directly contains an entry named `.git` that
  is itself a directory and that directory contains a file named `HEAD`;
  `GitRepoScanner.isGitDirectory(_:)` MUST determine this by checking
  `FileManager.default.fileExists(atPath:)` for `HEAD` inside the candidate
  `.git` directory (`GitRepoScanner.swift`).
- **hook-only-git-folder-not-a-repository**: A `.git` directory that exists
  but contains no `HEAD` file MUST NOT be treated as a repository, and
  `scan()` MUST continue the walk into that directory's own children
  (`GitRepoScanner.swift`).
- **git-file-skipped-entirely**: When a child directory contains a `.git`
  entry that is not itself a directory (a submodule gitlink or a linked
  worktree's `.git` file), `scan()` MUST skip that directory and MUST NOT
  descend into its subtree (`GitRepoScanner.swift`).
- **repository-not-descended-into**: Once a directory is recognized as a
  repository under `git-directory-repository-detection`, `scan()` MUST NOT
  descend into that directory's children (`GitRepoScanner.swift`).
- **single-scanned-git-repo-per-repository**: For each directory recognized
  as a repository, `scan()` MUST append exactly one `ScannedGitRepo` whose
  `path` is `entry.url.path` and whose `remote` is the result of
  `originRemote(inGitDirectory:)` on that directory's `.git` directory
  (`GitRepoScanner.swift`).
- **origin-remote-extraction**: `GitRepoScanner.originRemote(inGitDirectory:)`
  MUST parse the `.git/config` file as line-oriented INI text, MUST locate
  the section whose trimmed, space-stripped line equals the literal string
  `[remote"origin"]`, and within that section MUST return the trimmed value
  after the first `=` on the first line whose trimmed key equals `url`
  (`GitRepoScanner.swift`).
- **origin-remote-absent-cases**: `originRemote(inGitDirectory:)` MUST
  return `nil` when the `config` file cannot be read as UTF-8 text, when no
  `[remote "origin"]` section is present, or when that section's `url` value
  is empty after trimming whitespace (`GitRepoScanner.swift`).
- **sorted-idempotent-results**: `scan()` MUST return its accumulated
  results sorted ascending by `path` string comparison, both when it
  completes normally and when it stops early due to cancellation
  (`GitRepoScanner.swift`).
- **progress-reported-per-visited-directory**: For every directory popped
  from the walk's stack, `scan()` MUST invoke the supplied `onProgress`
  closure exactly once, before reading that directory's children, with a
  `Progress` value carrying the running `directoriesVisited` count, the
  `reposFound` count so far, and the directory's `currentPath`
  (`GitRepoScanner.swift`).
- **cancellation-checked-per-directory**: Before processing each directory
  popped from the walk's stack, `scan()` MUST call `isCancelled()`; when it
  returns `true`, `scan()` MUST stop immediately and return the results
  accumulated so far, sorted per `sorted-idempotent-results`
  (`GitRepoScanner.swift`).
- **default-callbacks-are-no-ops**: `scan(isCancelled:onProgress:)` MUST
  default `isCancelled` to a closure returning `false` and MUST default
  `onProgress` to `nil` when the caller supplies neither
  (`GitRepoScanner.swift`).
- **depth-first-stack-traversal**: `scan()` MUST traverse using a LIFO stack
  of `(url, depth)` pairs seeded with each root at depth `0`, popping the
  most recently pushed entry and pushing each descended child at `depth + 1`
  (`GitRepoScanner.swift`).
- **multiple-roots-scanned-independently**: When `roots` contains more than
  one URL, `scan()` MUST walk each root in the order given, accumulating
  every root's results into one combined array before the final sort
  (`GitRepoScanner.swift`).
- **sendable-value-type-with-local-mutable-state**: `GitRepoScanner` MUST be
  declared `Sendable`, and `scan()` MUST hold all of its mutable traversal
  state (`found`, `visited`, `stack`) as local variables rather than in any
  property of `self`; `Progress` MUST likewise be declared `Sendable`
  (`GitRepoScanner.swift`).
- **unreadable-directory-error-visibility**: NEEDS REVIEW: Not implemented in source. When `fileManager.contentsOfDirectory(at:includingPropertiesForKeys:options:)` throws for a directory — permission denied, or a root that does not exist on disk — `scan()` catches the error and calls `continue` with no log call, no distinct field on `Progress`, and no entry in the returned array or any other value `scan()` produces; the failure is not surfaced to the caller in any observable form (`GitRepoScanner.swift`). What is missing: whether "skip silently" is the intended contract for every unreadable directory including a wholly missing scan root, or whether such directories should be counted, logged, or otherwise distinguished from a directory that was simply empty. What would settle it: a doc-comment statement of the intended observability, or evidence from a caller (`ProjectsCoordinator.swift`) that a missing or unreadable root is surfaced to the user through some other path.

## Appearance

Not applicable — this is a directory-tree scanner, not a visual component.

## States

Not applicable — this is a directory-tree scanner, not a visual component.

## Accessibility

Not applicable — this is a directory-tree scanner, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-projects-git-repo-scanner-001 | single-scanned-git-repo-per-repository, origin-remote-extraction | `testAPlainRepositoryIsFoundWithItsOriginRemote`: one repo at `dev/alpha` with origin `git@example.com:someone/alpha.git` (`GitRepoScannerTests.swift`). | `scan()` returns one `ScannedGitRepo` for `dev/alpha` whose `remote` equals `git@example.com:someone/alpha.git` and whose `leafName` equals `alpha`. |
| git-client-projects-git-repo-scanner-002 | repository-not-descended-into | `testARepositoryInsideARepositoryIsNotAProject`: a repo at `dev/alpha` containing another repo at `dev/alpha/external/toolkit`. | `scan()` returns exactly one result, `dev/alpha`; the nested repo is never reported. |
| git-client-projects-git-repo-scanner-003 | git-file-skipped-entirely | `testADirectoryWhoseGitIsAFileIsSkippedEntirely`: `dev/worktree/.git` is a file containing `gitdir: ...`; `dev/alpha` is a real repo. | `scan()` returns only `dev/alpha`; `dev/worktree` is absent. |
| git-client-projects-git-repo-scanner-004 | hook-only-git-folder-not-a-repository | `testAGitFolderThatGitWouldNotOpenIsNotAProject`: `dev/container/.git/hooks/` exists with no `HEAD`. | `scan()` returns an empty array. |
| git-client-projects-git-repo-scanner-005 | hook-only-git-folder-not-a-repository | `testRepositoriesUnderSuchAFolderAreStillFound`: same hook-only `dev/container/.git`, plus real repos at `dev/container/alpha` and `dev/container/beta`. | `scan()` returns both `dev/container/alpha` and `dev/container/beta`. |
| git-client-projects-git-repo-scanner-006 | hidden-directories-excluded | `testHiddenDirectoriesAreNeverDescendedInto`: a repo at `.claude/worktrees/feature` and one at `dev/alpha`. | `scan()` returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-007 | root-level-skip-patterns, default-skip-patterns | `testTheDefaultSkipPatternsKeepTheHomeFoldersOutOfTheWalk`: repos under `Library/`, `Music/`, `Pictures/`, `Movies/`, `Dropbox/`, `Google Drive/`, plus `dev/alpha`, scanned with default patterns. | `scan()` returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-008 | root-level-skip-patterns, case-insensitive-pattern-matching | `testAPatternWithAWildcardMatchesATeamFolder`: a repo at `Acme Dropbox/shared/checkout`, plus `dev/alpha`. | `scan()` returns only `dev/alpha`; the `* Dropbox` pattern excludes `Acme Dropbox`. |
| git-client-projects-git-repo-scanner-009 | case-insensitive-pattern-matching | `testPatternsMatchWithoutRegardToCase`: a repo at `google drive/checkout` (lowercase), default patterns include `Google Drive`. | `scan()` returns an empty array. |
| git-client-projects-git-repo-scanner-010 | root-level-skip-patterns | `testTheSkipListIsWhateverTheCallerPassesIn`: repos under `Music/`, `Archive/beta`, `dev/alpha`, scanned with `rootSkipPatterns: ["Arch*"]`. | `scan()` returns `Music/somebody-elses-checkout` and `dev/alpha`, but not `Archive/beta`. |
| git-client-projects-git-repo-scanner-011 | root-level-skip-patterns | `testAnEmptySkipListSkipsNothing`: a repo under `Library/`, scanned with `rootSkipPatterns: []`. | `scan()` returns `Library/somebody-elses-checkout`. |
| git-client-projects-git-repo-scanner-012 | root-level-skip-patterns | `testThoseSameNamesFurtherDownAreStillScanned`: repos at `dev/Library/gamma`, `dev/Pictures/delta`, `dev/Acme Dropbox/epsilon`, scanned with default patterns. | `scan()` returns all three, because the matched names are at depth 2, not depth 1. |
| git-client-projects-git-repo-scanner-013 | pruned-directories-excluded | `testBuildAndDependencyDirectoriesArePruned`: a repo under `dev/<pruned>/vendored` for every name in `prunedDirectoryNames`, plus `dev/alpha`. | `scan()` returns only `dev/alpha`. |
| git-client-projects-git-repo-scanner-014 | symbolic-links-excluded | `testSymlinkedDirectoriesAreNotFollowed`: a repo at `dev/alpha`, plus a symlink `mirror` pointing at `dev`. | `scan()` returns only `dev/alpha`; the symlink is not followed. |
| git-client-projects-git-repo-scanner-015 | sorted-idempotent-results | `testResultsAreSortedByPathAndStableAcrossRuns`: repos at `dev/zeta`, `dev/alpha`, `work/beta`. | `scan()` returns them in path order (`dev/alpha`, `dev/zeta`, `work/beta`); calling `scan()` again on the same scanner returns an equal array. |
| git-client-projects-git-repo-scanner-016 | multiple-roots-scanned-independently, sorted-idempotent-results | `testAnEmptyTreeFindsNothingRatherThanFailing`: an empty temporary directory as the sole root. | `scan()` returns an empty array without throwing. |
| git-client-projects-git-repo-scanner-017 | progress-reported-per-visited-directory | `testProgressIsReportedAsTheWalkGoes`: one repo at `dev/alpha`; `onProgress` appends every reported `directoriesVisited` value. | At least one progress report is recorded, and the last recorded `directoriesVisited` equals the total number of reports (every visited directory is reported exactly once). |
| git-client-projects-git-repo-scanner-018 | cancellation-checked-per-directory | `testCancellationStopsTheWalk`: repos at `dev/alpha` and `work/beta`; `isCancelled` always returns `true`. | `scan()` returns an empty array. |
| git-client-projects-git-repo-scanner-019 | origin-remote-extraction | `testOriginIsReadOutOfTheConfigWithoutShellingOutToGit`: a `.git/config` with both `[remote "upstream"]` and `[remote "origin"]` sections, each with a different `url`. | `GitRepoScanner.originRemote(inGitDirectory:)` returns the `origin` section's URL, `git@example.com:someone/alpha.git`, not the `upstream` URL. |
| git-client-projects-git-repo-scanner-020 | origin-remote-absent-cases | `testARepositoryWithNoOriginHasNoRemote`: a `.git/config` containing only `[core]\n\tbare = false`. | `GitRepoScanner.originRemote(inGitDirectory:)` returns `nil`. |
| git-client-projects-git-repo-scanner-021 | origin-remote-absent-cases | `testAMissingConfigIsNotAnError`: a `.git` directory with no `config` file at all. | `GitRepoScanner.originRemote(inGitDirectory:)` returns `nil` without throwing. |
| git-client-projects-git-repo-scanner-022 | default-scan-root | Construct `GitRepoScanner()` with no arguments. | The instance's `roots` property equals `[FileManager.default.homeDirectoryForCurrentUser]`. |
| git-client-projects-git-repo-scanner-023 | default-skip-patterns | Construct `GitRepoScanner()` with no arguments. | The instance's `rootSkipPatterns` property equals `GitRepoScanner.defaultRootSkipPatterns`. |
| git-client-projects-git-repo-scanner-024 | git-directory-repository-detection | Call `GitRepoScanner.isGitDirectory(_:)` on a `.git` directory containing a `HEAD` file, and separately on one containing only `hooks/`. | The first call returns `true`; the second returns `false`. |
| git-client-projects-git-repo-scanner-025 | sendable-value-type-with-local-mutable-state | From two concurrent tasks, call `scan()` on the same `GitRepoScanner` instance over a tree containing several repos. | Both calls complete without a crash or data race and each returns the identical, correctly sorted full result set, since each call's mutable state (`found`, `visited`, `stack`) is local to that call. |
| git-client-projects-git-repo-scanner-026 | unreadable-directory-error-visibility | Construct a scan root directory, then remove read permission from one of its subdirectories before calling `scan()` on a tree that also contains a real repo elsewhere. | Current, undefined-contract behavior: `scan()` completes normally, omits the unreadable subdirectory's contents from the result, and produces no log output, no error, and no distinguishing field on any `Progress` report for that directory. |

## Edge Cases

- **Null and empty input**: An empty `roots` array (`GitRepoScanner(roots: [])`) MUST cause `scan()` to return an empty array immediately, since the outer `for root in roots` loop has nothing to iterate (`GitRepoScanner.swift`). An empty `rootSkipPatterns` array MUST skip nothing by name at any depth, per `root-level-skip-patterns` (verified by `testAnEmptySkipListSkipsNothing`).
- **Boundary values**: `rootSkipPatterns` is applied only when `depth == 1` exactly; at depth `0` (a scan root itself) and at any depth `2` or greater it is never consulted, per `root-level-skip-patterns` (`GitRepoScanner.swift`, verified by `testThoseSameNamesFurtherDownAreStillScanned`). MUST.
- **Concurrent access**: `GitRepoScanner` is `Sendable` and `scan()` keeps every piece of mutable traversal state local to the call (`found`, `visited`, `stack`); the only state shared across concurrent calls on one instance is the immutable `roots` and `rootSkipPatterns` `let` properties, so multiple threads MAY call `scan()` on the same instance concurrently with no synchronization and no shared-state hazard (`GitRepoScanner.swift`). MUST.
- **Error states**: `fileManager.contentsOfDirectory` throwing for any reason — permission denied, the directory disappearing mid-walk — is caught and skipped identically via `continue`, with no distinction made between error causes and no signal returned to the caller; see the open question on `unreadable-directory-error-visibility` (`GitRepoScanner.swift`). A malformed or non-UTF-8 `.git/config` is handled the same way as a config with no origin section: `originRemote(inGitDirectory:)` returns `nil` in both cases via `try?`, with no way for a caller to distinguish "corrupt" from "absent" (`GitRepoScanner.swift`). MUST.
- **Offline or disconnected state**: Not applicable — `GitRepoScanner.swift` makes no network call of any kind; its only I/O is local filesystem access through `FileManager` and local file reads through `String(contentsOf:)` (`GitRepoScanner.swift`).
- **Missing file or unreachable root**: A root URL that does not exist on disk is not special-cased; `contentsOfDirectory` throws for it exactly as it would for a permission-denied directory, and that root is silently skipped with the walk continuing to any remaining roots — see the open question on `unreadable-directory-error-visibility` (`GitRepoScanner.swift`). MUST.
- **Malformed config line endings**: `originRemote(inGitDirectory:)` splits `.git/config` text on `"\n"` and trims each line with `.whitespaces`, which strips spaces and tabs but not a trailing carriage return; a `config` file using CRLF line endings MUST retain a trailing `\r` on the section-header comparison string and on any parsed `url` value, since `CharacterSet.whitespaces` does not include `\r` (`GitRepoScanner.swift`). This can cause the `[remote"origin"]` comparison to fail to match, or the returned remote string to carry a trailing `\r`, on a CRLF-encoded config. MUST (describes the actual, deterministic behavior; not a marker, since the source never declares an intent to normalize line endings).
- **Cancellation**: `isCancelled()` is consulted once per directory popped from the stack, before that directory's children are read; a cancellation observed partway through a multi-root scan MUST return only the repositories found before cancellation was observed, sorted (`GitRepoScanner.swift`, verified by `testCancellationStopsTheWalk`). MUST.
- **Symlink cycles**: Because `shouldDescend(into:atDepth:)` excludes every symbolic link before it is ever pushed onto the stack, a symlink that would otherwise create a cycle (e.g. pointing at an ancestor directory) MUST NOT be traversed and therefore MUST NOT cause an infinite loop (`GitRepoScanner.swift`, verified by `testSymlinkedDirectoriesAreNotFollowed`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `roots` (init parameter) | `[URL]?` | `nil` → `[FileManager.default.homeDirectoryForCurrentUser]` | Directories to scan; each is walked independently and results are combined. |
| `rootSkipPatterns` (init parameter) | `[String]` | `GitRepoScanner.defaultRootSkipPatterns` | `fnmatch` glob patterns, matched case-insensitively, applied only to folder names found directly under a scan root. |
| `isCancelled` (`scan()` parameter) | `@Sendable () -> Bool` | `{ false }` | Consulted once before each directory is processed; returning `true` stops the walk and returns results found so far. |
| `onProgress` (`scan()` parameter) | `(@Sendable (Progress) -> Void)?` | `nil` | Invoked once per visited directory with a running visited count, found count, and current path. |

`GitRepoScanner.swift` itself reads no environment variable and no settings
key. `UserSettings+Projects.swift` is the caller-side configuration point:
`UserSettings.projectScanSkipPatterns` is a persisted `[String]` setting
defaulting to `GitRepoScanner.defaultRootSkipPatterns`, and
`ProjectsCoordinator.swift` reads that setting's current value and passes it
as the `rootSkipPatterns` argument when it constructs a `GitRepoScanner` —
but that wiring lives outside this component's own file and is not part of
its contract.

## Deep Linking

Not applicable: `GitRepoScanner.swift` defines no URL scheme, route, or
navigation destination.

## Localization

Not applicable: `GitRepoScanner.swift` produces no user-facing string. Its
only outputs are `path` (a filesystem path) and `remote` (a raw value copied
from `.git/config`), both data values passed through unchanged, not
localized UI text.

## Accessibility Options

Not applicable: `GitRepoScanner.swift` renders nothing; Reduce Motion,
Increase Contrast, and Differentiate Without Color have no surface here to
apply to.

## Feature Flags

Not applicable: `GitRepoScanner.swift` contains no feature-flag or
build-configuration check of any kind.

## Analytics

Not applicable: `GitRepoScanner.swift` makes no analytics or event-tracking
call.

## Privacy

- **Data collected**: `scan()` returns each found repository's local
  filesystem `path` and its `remote` value read verbatim from
  `.git/config`'s `[remote "origin"]` `url` (`GitRepoScanner.swift`). A remote URL MAY embed credentials if the user's own
  git configuration does (for example a URL of the form
  `https://user:token@host/repo.git`); `GitRepoScanner.swift` does not
  inspect, redact, or otherwise transform this value before returning it.
- **Storage**: None — `GitRepoScanner.swift` does not persist its results;
  it only returns them to the caller of `scan()`.
- **Transmission**: None — `GitRepoScanner.swift` makes no network call and
  transmits nothing.
- **Retention**: Not applicable — `GitRepoScanner.swift` holds no results
  beyond the single `scan()` call's return value; retention of the returned
  array is entirely the caller's responsibility.

## Logging

Not applicable: `GitRepoScanner.swift` makes no logging call of any kind;
its only failure path (`contentsOfDirectory` throwing) is caught and
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
