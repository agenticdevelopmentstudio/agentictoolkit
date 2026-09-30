<!-- leaf: implement-git-client/projects-git-repo-scanner · source: git-client-projects-git-repo-scanner.md -->

**Rules** (cite as `implement-git-client/projects-git-repo-scanner#<slug>`):

- `default-scan-root` MUST
- `default-skip-patterns` MUST
- `hidden-directories-excluded` MUST
- `pruned-directories-excluded` MUST
- `root-level-skip-patterns` MUST
- `case-insensitive-pattern-matching` MUST
- `symbolic-links-excluded` MUST
- `git-directory-repository-detection` MUST
- `hook-only-git-folder-not-a-repository` MUST
- `git-file-skipped-entirely` MUST
- `repository-not-descended-into` MUST
- `single-scanned-git-repo-per-repository` MUST
- `origin-remote-extraction` MUST
- `origin-remote-absent-cases` MUST
- `sorted-idempotent-results` MUST
- `progress-reported-per-visited-directory` MUST
- `cancellation-checked-per-directory` MUST
- `default-callbacks-are-no-ops` MUST
- `depth-first-stack-traversal` MUST
- `multiple-roots-scanned-independently` MUST
- `sendable-value-type-with-local-mutable-state` MUST
- `data-collected` MAY — scan() returns each found repository's local filesystem path and its remote value read verbatim from .git/config's …

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

