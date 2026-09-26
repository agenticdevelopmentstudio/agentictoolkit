---
id: 779ac6ea-9ef5-4fb0-8ed9-dc6b9d617344
title: Git Client
domain: agentictoolkit://cookbook/core/git
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'Actor-based git subprocess client: status/branch/worktree/global-config
  verbs through one bottleneck, with total error mapping, redacted logging and a timeout.'
platforms:
- swift
- macos
tags:
- git
- version-control
- actor
- subprocess
- logging
- redaction
- settings
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Git/GitBranch.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitCaller.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClient.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClientConfiguration.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitClientError.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitCommandLog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitConfigEntry.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitFileStatus.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitStatus.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Git/GitWorktree.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/SettingStorage/UserSettings+Git.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitClientTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitCommandLogTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitStatusParserTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitBranchParserTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitWorktreeParserTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitConfigEntryParserTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Git/GitClientConfigurationTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Git Client

## Overview

The `git-client` ingredient is the toolkit's single door to git: nine Swift
files under `packages/apple/AgenticToolkit/Core/Git/` (`GitBranch.swift`,
`GitCaller.swift`, `GitClient.swift`, `GitClientConfiguration.swift`,
`GitClientError.swift`, `GitCommandLog.swift`, `GitConfigEntry.swift`,
`GitFileStatus.swift`, `GitStatus.swift`, `GitWorktree.swift`) that together
spawn every git process the toolkit or an agent driving it will ever run,
through one `actor` bottleneck (`GitClient`). It exposes four read-only verbs
(`status`, `currentBranch`, `branches`, `worktrees`) and three
global-configuration verbs (`globalConfig`, `setGlobalConfig`,
`unsetGlobalConfig`), resolves its own configuration from three
`UserSettings` keys on every call (`UserSettings+Git.swift`), records every
attempt — success or failure — in a redacted, `OSLog`-backed command log, and
maps every failure onto a closed four-case error type. It has no visual
surface of its own; every UI element that shows git state (a status badge, a
branch picker) is a consumer of this contract, not part of it.

## Behavioral Requirements

### The bottleneck and its verbs

- **single-spawn-point**: `GitClient` MUST be the only path by which the
  toolkit spawns a git process; every public verb routes through the private
  `execute` method, which is the sole call site of `SubprocessChannel.run` in
  this component (`GitClient.swift`).
- **actor-isolation-non-serializing**: `GitClient` MUST be declared as a
  Swift `actor` whose verbs each suspend at the `await SubprocessChannel.run`
  point, releasing the actor for the whole lifetime of the child process, so
  concurrent callers run concurrent git processes rather than being
  serialized by the actor — the actor is a bottleneck for accounting, not for
  execution order (`GitClient.swift`).
- **status-command-construction**: `status(in:caller:)` MUST invoke `git
  status` with arguments `["--porcelain=v1", "-z", "-uall"]`, and MUST append
  `"--ignore-submodules"` when `configuration.submoduleHandling == .ignore`
  (`GitClient.swift`).
- **current-branch-detached-head**: `currentBranch(in:caller:)` MUST invoke
  `git rev-parse --abbrev-ref HEAD` and MUST return `nil` when the trimmed
  output is empty or equal to the literal string `"HEAD"` (`GitClient.swift`).
- **branches-format-string**: `branches(in:caller:)` MUST invoke `git
  for-each-ref` against `refs/heads` with `--format=<value>`, where the value
  is exactly `GitBranch.forEachRefFormat`,
  `%(refname:short)%09%(HEAD)%09%(upstream:short)` (`GitClient.swift`; `GitBranch.swift`).
- **worktrees-listing**: `worktrees(in:caller:)` MUST invoke `git worktree
  list --porcelain` and MUST return every worktree of the repository
  containing `directory`, main worktree first, per `GitWorktree.parse`'s
  contract (`GitClient.swift`).
- **global-config-directory**: The three global-config verbs
  (`globalConfig`, `setGlobalConfig(key:value:)`, `unsetGlobalConfig(key:)`)
  MUST run with the current user's home directory as the child's working
  directory, never a repository directory, because `git config --global`
  neither discovers nor reads a repository (`GitClient.swift`).
- **global-config-list**: `globalConfig(caller:)` MUST invoke `git config
  --global --list --null` and MUST parse the result with
  `GitConfigEntry.parse(nullSeparated:)` (`GitClient.swift`).
- **set-global-config**: `setGlobalConfig(key:value:caller:)` MUST invoke
  `git config --global <key> <value>` and MUST discard the process's
  captured output (`GitClient.swift`).
- **unset-global-config-exit-5**: `unsetGlobalConfig(key:caller:)` MUST
  invoke `git config --global --unset <key>` and MUST surface git's exit
  status 5 (key was not set) as an ordinary `GitClientError.commandFailed`,
  not as a distinct case (`GitClient.swift`).

### Execution, configuration and attribution

- **executable-preflight**: `execute` MUST check
  `FileManager.default.isExecutableFile(atPath:)` on the configured
  executable path before spawning, and MUST throw
  `GitClientError.executableNotFound(path:)` without spawning a process when
  the check fails (`GitClient.swift`).
- **environment-terminal-prompt-disabled**: `execute` MUST set
  `GIT_TERMINAL_PROMPT=0` in the spawned child's environment (so a credential
  prompt cannot hang the child behind an unwatched terminal) and MUST merge
  `configuration.extraEnvironment` over that default, with `extraEnvironment`
  winning on key collision, using `SubprocessChannel`'s `.mergeOverParent`
  environment policy (`GitClient.swift`).
- **total-failure-mapping**: `execute` MUST map every error thrown by
  `SubprocessChannel.run` onto exactly one of `GitClientError.timedOut` (for
  `WallClockBudgetExceeded`) or `.launchFailed` (for every other error), via
  an unqualified `catch` that follows a `WallClockBudgetExceeded`-specific
  catch and a `CancellationError`-specific catch — no error type outside
  `GitClientError` can leave `execute`, except the one deliberate exception
  below (`GitClient.swift`).
- **cancellation-error-passthrough**: `execute` MUST record the attempt and
  then rethrow `CancellationError` unchanged, MUST NOT wrap it in
  `GitClientError`, so `Task.isCancelled` propagation and structured-
  concurrency cleanup keep working for the caller; this is the one way a
  `GitClient` verb can throw something that is not a `GitClientError`
  (`GitClient.swift`).
- **non-zero-exit-mapping**: `execute` MUST throw
  `GitClientError.commandFailed(verb:exitStatus:standardError:)` when the
  child's exit status is non-zero, carrying the raw `standardError` capture
  for the caller to show (`GitClient.swift`).
- **output-decode-fallback**: `execute` MUST decode the child's captured
  standard output as UTF-8 first, MUST fall back to ISO Latin-1 when UTF-8
  decoding fails, and MUST return an empty string when both fail
  (`GitClient.swift`).
- **invocation-recorded-before-return**: `execute` MUST call
  `GitCommandLog.record` on every exit path — executable-not-found, timed
  out, cancelled, launch-failed, and completed (successfully or not) — before
  returning a value or throwing (`GitClient.swift`).
- **caller-capture-at-call-site**: `GitCaller`'s `file` and `function`
  properties MUST be captured via `#fileID`/`#function` default arguments
  evaluated in the calling context, not `GitClient`'s own, so a verb declared
  `caller: GitCaller = GitCaller()` records who invoked it without the caller
  doing anything extra (`GitCaller.swift`).
- **config-default**: `GitClientConfiguration.default` MUST equal
  `GitClientConfiguration()` with `executableURL` `/usr/bin/git`, `timeout`
  `5` seconds, and `submoduleHandling` `.ignore` (`GitClientConfiguration.swift`).
- **config-from-settings-timeout-clamp**: `GitClientConfiguration.fromSettings()`
  MUST read `UserSettings.gitExecutablePath`, `.gitStatusTimeoutSeconds`, and
  `.gitStatusIncludesSubmodules`, and MUST clamp the timeout setting's value
  to a minimum of `1` via `max(1, ...)`. This clamp applies only through
  `fromSettings()`; `GitClientConfiguration`'s plain initializer accepts any
  `TimeInterval` for `timeout`, including zero or a negative value, with no
  clamp of its own (`GitClientConfiguration.swift`).
- **config-provider-resolved-per-call**: `GitClient` MUST resolve its
  configuration by invoking `configurationProvider` on every verb call
  rather than capturing it once at initialization, so `GitClient.shared`
  follows a `UserSettings` change on the very next invocation
  (`GitClient.swift`).
- **value-types-sendable**: `GitBranch`, `GitCaller`,
  `GitClientConfiguration`, `GitConfigEntry`, `GitFileStatus`, `GitStatus`,
  and `GitWorktree` MUST each declare `Sendable` conformance, and `GitClient`
  MUST be declared as an `actor`, so every type that crosses the client's
  async boundary is safe to share across concurrency domains
  (`GitBranch.swift`; `GitCaller.swift`;
  `GitClientConfiguration.swift`; `GitConfigEntry.swift`;
  `GitFileStatus.swift`; `GitStatus.swift`; `GitWorktree.swift`; `GitClient.swift`).

### Errors and security-relevant logging

- **error-taxonomy**: `GitClientError` MUST be exactly four cases —
  `commandFailed`, `timedOut`, `launchFailed`, `executableNotFound` — and
  MUST NOT include `CancellationError` as a case (`GitClientError.swift`).
- **error-description-vs-log-description**: `GitClientError.errorDescription`
  MAY interpolate git's own `standardError` text into a user-facing message
  for `.commandFailed`. `GitClientError.logDescription` MUST NOT include
  `standardError`, the launch `reason`, or the configured executable `path`
  in any case, returning only the case name plus non-sensitive structured
  fields (verb, exit status) (`GitClientError.swift`).
- **command-log-fields**: `GitCommandLog.record` MUST log the verb, its
  redacted arguments, the working directory, the calling file and function,
  the duration in milliseconds, and the exit status (or the literal string
  `"unfinished"` when `exitStatus` is `nil`), and MUST NOT log the process's
  standard output or standard error (`GitCommandLog.swift`).
- **redaction-scope-and-positional-rule**: `GitCommandLog.redactedArguments`
  MUST return arguments unchanged for every verb except `config`. For
  `config`, it MUST redact every argument at and after the first non-flag
  (non-`-`-prefixed) argument position — replacing each with
  `<redacted:<byte length>>` — regardless of whether that argument is shaped
  like a well-formed key; `GitConfigEntry.isWellFormedKey` is used only to
  decide whether to *keep* the argument found at that position, never to
  relocate the position itself (`GitCommandLog.swift`).
- **config-entry-key-validator**: `GitConfigEntry.isWellFormedKey` MUST
  return `true` only for a non-empty string that contains at least one `.`,
  does not begin with `-`, and contains no whitespace character
  (`GitConfigEntry.swift`).
- **config-entry-parse-split-rule**: `GitConfigEntry.parse(nullSeparated:)`
  MUST split records on NUL, and within each record MUST split the key from
  the value at the *first* newline only, yielding an empty value for a
  record with no newline at all (`GitConfigEntry.swift`).

### Parsing (GitFileStatus, GitStatus, GitWorktree, GitBranch)

- **file-status-priority-merge**: `GitFileStatus.merge` MUST return the
  status with the highest `priority` among its input — `conflicted` (7)
  down to `ignored` (0) — or `nil` for empty input (`GitFileStatus.swift`).
- **status-porcelain-record-shape**: `GitStatus.parse` MUST split the
  `-z`-terminated porcelain output on NUL, MUST treat each record's first
  two bytes as the index and work-tree status columns, and MUST consume a
  second NUL-terminated field as the origin path whenever either status
  column is `R` or `C`, ahead of every other classification (`GitStatus.swift`).
- **status-conflict-pair-detection**: `GitStatus.parse` MUST classify a
  record as `.conflicted` when its two-character status pair is exactly one
  of `DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`, ahead of the modified/added/
  deleted ladder (`GitStatus.swift`).
- **status-byte-accurate-path-decode**: `GitStatus.parse` MUST slice and
  count each record in UTF-8 bytes rather than `Character`s, and MUST drop a
  record whose remaining bytes fail to decode as UTF-8 or decode to an empty
  string, costing only that one record (`GitStatus.swift`).
- **status-directory-rollup**: `GitStatus.parse` MUST derive `directories`
  by assigning, to every ancestor path component of every entry in `files`,
  the highest-priority `GitFileStatus` among that ancestor's descendants
  (`GitStatus.swift`).
- **worktree-parse-flush-on-new-record**: `GitWorktree.parse` MUST flush the
  in-progress record whenever a new line beginning with `"worktree "`
  starts, not only on a blank line, and MUST flush once more after the loop
  ends to capture a record with no trailing blank line (`GitWorktree.swift`).
- **worktree-branch-shortening**: `GitWorktree.parse` MUST shorten a
  `branch` line's `refs/heads/<name>` value to `<name>`, and MUST leave a
  branch ref not beginning with `refs/heads/` unshortened (`GitWorktree.swift`).
- **worktree-main-is-first**: `GitWorktree.parse` MUST mark the first
  flushed record's `isMain` `true` and every subsequent record's `isMain`
  `false`, per porcelain's contract that the main worktree is always listed
  first (`GitWorktree.swift`).
- **branch-parse-tab-separated**: `GitBranch.parse(forEachRef:)` MUST split
  each line on tab, treat a second field of `"*"` as the current branch, and
  treat a third field that is empty as no upstream — the third field for a
  real `for-each-ref` invocation is a single space, not an empty string, for
  every non-current branch (`GitBranch.swift`).

## Appearance

Not applicable — this is a headless git subprocess client, not a visual
component.

## States

Not applicable — this is a headless git subprocess client, not a visual
component.

## Accessibility

Not applicable — this is a headless git subprocess client, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| git-client-001 | status-porcelain-record-shape | `GitStatus.parse(porcelain: "")` | `.empty` (`GitStatusParserTests.emptyOutput`) |
| git-client-002 | status-porcelain-record-shape | `" M foo.txt\0"` | `files["foo.txt"] == .modified` (`modifiedFile`) |
| git-client-003 | status-porcelain-record-shape, status-directory-rollup | `"?? untracked/new.txt\0"` | `files["untracked/new.txt"] == .untracked`; `directories["untracked"] == .untracked` (`untrackedFile`) |
| git-client-004 | status-directory-rollup | `" M a/b/c.txt\0"` | `directories["a"] == .modified`; `directories["a/b"] == .modified` (`directoryPropagation`) |
| git-client-005 | status-porcelain-record-shape | `"R  new.txt\0old.txt\0"` | `files["new.txt"] == .renamed`; `files["old.txt"] == nil` (`renamedFileUsesNewPath`) |
| git-client-006 | status-porcelain-record-shape | `"RM new.txt\0old.txt\0"` | `files["new.txt"] == .renamed`; `files["old.txt -> new.txt"] == nil` (`renameAndModifyIsRecordedAsRenamed`) |
| git-client-007 | status-porcelain-record-shape | `" R App/Sources/Foo.swift\0App/Sources/Bar.swift\0 M README.md\0"` | `Foo.swift` renamed, `Bar.swift` absent, `README.md` modified, `files.count == 2` (`workTreeRenameConsumesItsOriginField`) |
| git-client-008 | status-porcelain-record-shape | `"C  copy.txt\0original.txt\0 M kept.txt\0"` | `copy.txt` copied, `original.txt` absent, `kept.txt` modified (`copyIsRecordedUnderTheNewPath`) |
| git-client-009 | status-conflict-pair-detection | `"AA a/both-added.txt\0DD b/both-deleted.txt\0"` | both `.conflicted`; `directories["a"]`/`directories["b"]` both `.conflicted` (`bothAddedAndBothDeletedAreConflicts`) |
| git-client-010 | status-conflict-pair-detection | `"A  added.txt\0D  deleted.txt\0"` | `added.txt == .added`; `deleted.txt == .deleted` (`ordinaryAddAndDeleteAreUnaffected`) |
| git-client-011 | status-byte-accurate-path-decode | `" M café.txt\0"` (non-ASCII, no C-quoting) | `files["café.txt"] == .modified` (`nonASCIIPathIsKeyedExactly`) |
| git-client-012 | status-byte-accurate-path-decode | `" M \u{301}.txt\0"` (leading combining mark) | `files["\u{301}.txt"] == .modified`; `files[""] == nil` (`pathBeginningWithACombiningMarkIsNotTruncated`) |
| git-client-013 | status-byte-accurate-path-decode | `" M \0 M kept.txt\0"` (empty path record) | `files["kept.txt"] == .modified`; `files[""] == nil` (`recordWithNoPathIsSkipped`) |
| git-client-014 | status-directory-rollup | `" M ///\0"` (path of only separators) | `directories.isEmpty` (`pathOfSeparatorsOnlyIsSkipped`) |
| git-client-015 | worktree-main-is-first, worktree-branch-shortening | 4-record `worktree list --porcelain` sample | `trees[0].isMain`; `trees[0].directory == URL(fileURLWithPath: "/repo", isDirectory: true)`; `trees[0].branch == "main"` (`firstIsMain`) |
| git-client-016 | worktree-branch-shortening | same sample | `trees[1].branch == "tabs"` (`shortBranchNames`) |
| git-client-017 | worktree-parse-flush-on-new-record | same sample | `trees[2].isDetached`, `trees[2].branch == nil`; `trees[3].isBare` (`detachedAndBare`) |
| git-client-018 | worktree-parse-flush-on-new-record | `""` | `[]` (`empty`) |
| git-client-019 | worktree-parse-flush-on-new-record | `"worktree /solo\nHEAD abc\nbranch refs/heads/solo"` (no trailing blank line) | one entry, `isMain`, `branch == "solo"` (`noTrailingBlankLine`) |
| git-client-020 | branch-parse-tab-separated | `"main\t*\torigin/main\nfeature\t\t\ntabs\t\torigin/tabs\n"` | `[GitBranch("main", true, "origin/main"), GitBranch("feature", false, nil), GitBranch("tabs", false, "origin/tabs")]` (`parsesFields`) |
| git-client-021 | branch-parse-tab-separated | `"\n\n"` | `[]` (`ignoresBlankLines`) |
| git-client-022 | branch-parse-tab-separated | `"main\t \torigin/main\nfeature\t \t\n"` (single-space HEAD field) | `main.isCurrent == false` (`realisticNonCurrentHeadField`) |
| git-client-023 | config-entry-parse-split-rule | `"user.name\nMike\0user.email\nmike@example.com\0core.editor\nvim -f\nextra\0"` | 3 entries, `core.editor`'s value includes the embedded newline (`splits`) |
| git-client-024 | config-entry-parse-split-rule | `"alias.st\0"` | `[GitConfigEntry(key: "alias.st", value: "")]` (`missingValue`) |
| git-client-025 | config-entry-parse-split-rule | `""` | `[]` (`empty`) |
| git-client-026 | redaction-scope-and-positional-rule | verb `"status"`, args `["status", "--porcelain=v1", "-uall", "--ignore-submodules"]` | unchanged (`nonConfigVerbUntouched`) |
| git-client-027 | redaction-scope-and-positional-rule | verb `"config"`, args `["--global", "--list", "--null"]` and `["--global", "--unset", "user.email"]` | both unchanged — nothing follows the key (`configReadsKeepTheirArguments`) |
| git-client-028 | redaction-scope-and-positional-rule | verb `"config"`, `["--global", "user.email", "someone@example.com"]` | `["--global", "user.email", "<redacted:19>"]` (`configWriteRedactsTheValue`) |
| git-client-029 | redaction-scope-and-positional-rule | verb `"config"`, `["--global", "core.pager", "--dash-leading-value", "trailing"]` | `["--global", "core.pager", "<redacted:20>", "<redacted:8>"]` (`redactionIsPositionalNotShapeBased`) |
| git-client-030 | redaction-scope-and-positional-rule | verb `"config"`, `["--global", "-x.token", "s3cr3t"]` | `["--global", "-x.token", "<redacted:6>"]` — the dash-leading key never leaks its value (`aDashLeadingKeyDoesNotLeakItsValue`) |
| git-client-031 | redaction-scope-and-positional-rule | verb `"config"`, `["--global", "email", "someone@example.com"]` | `["--global", "<redacted:5>", "<redacted:19>"]` — a non-key-shaped word is redacted too (`anUnrecognisedArgumentIsRedacted`) |
| git-client-032 | redaction-scope-and-positional-rule | verb `"config"`, `[]` | `[]` (`emptyArguments`) |
| git-client-033 | config-default | `GitClientConfiguration.default` | `executableURL == /usr/bin/git`; `timeout == 5`; `submoduleHandling == .ignore` (`defaults`) |
| git-client-034 | config-from-settings-timeout-clamp | settings: path `/opt/homebrew/bin/git`, timeout `12`, submodules `true` | `fromSettings()` reflects all three exactly (`fromSettings`) |
| git-client-035 | config-from-settings-timeout-clamp | `gitStatusTimeoutSeconds = 0` | `fromSettings().timeout == 1` (`timeoutClampsZeroToOne`) |
| git-client-036 | config-from-settings-timeout-clamp | `gitStatusTimeoutSeconds = -5` | `fromSettings().timeout == 1` (`timeoutClampsNegativeToOne`) |
| git-client-037 | executable-preflight | `executableURL = /nonexistent/git`; call `currentBranch(in:)` | throws `GitClientError.executableNotFound(path: "/nonexistent/git")` before any spawn (`missingExecutable`) |
| git-client-038 | non-zero-exit-mapping | `status(in:)` a nonexistent directory | throws a `GitClientError` (`commandFailed`) |
| git-client-039 | total-failure-mapping | `timeout = 0.001`; call `status(in:)` on a real repository | throws `GitClientError.timedOut(verb: "status")` (`timesOut`) |
| git-client-040 | global-config-directory, set-global-config | `setGlobalConfig(key: "atkgitclienttest.added", value: "added-value")` against a redirected `GIT_CONFIG_GLOBAL` | the redirected file, not the developer's real `~/.gitconfig`, gains the entry (`setGlobalConfig`) |
| git-client-041 | unset-global-config-exit-5, global-config-directory | `unsetGlobalConfig(key: seededKey)` then `globalConfig()` | the key is gone; `globalConfig()` is empty; the real `~/.gitconfig` is untouched (`unsetGlobalConfig`) |
| git-client-042 | status-command-construction | real one-commit fixture with one modified file | `status(in:).files["a.txt"] == .modified` (`status`) |
| git-client-043 | current-branch-detached-head | fixture's root checkout and its `feature` worktree | `currentBranch` returns `"main"` and `"feature"` respectively (`currentBranch`) |
| git-client-044 | branches-format-string | fixture with `main` and `feature` branches | both names present; `main.isCurrent == true` (`branches`) |
| git-client-045 | worktree-main-is-first | fixture's root plus one added worktree | `count == 2`; `[0].isMain`, `[0].branch == "main"`; `[1].branch == "feature"` (`worktrees`) |
| git-client-046 | error-description-vs-log-description | `.commandFailed(verb: "status", exitStatus: 128, standardError: "fatal: ... '/Users/secret/repo'")` | `logDescription` excludes `"secret"`, includes `"status"` and `"128"` (`commandFailedNeverLeaksStandardError`) |
| git-client-047 | error-description-vs-log-description | `.launchFailed(verb: "status", reason: "secret-path-in-the-reason")` | `logDescription` excludes `"secret"` (`launchFailedNeverLeaksReason`) |
| git-client-048 | error-description-vs-log-description | `.executableNotFound(path: "/Users/secret/bin/git")` | `logDescription` excludes `"secret"` (`executableNotFoundNeverLeaksPath`) |

## Edge Cases

- **Null/empty input**: `GitStatus.parse(porcelain: "")` MUST return
  `.empty` (git-client-001). `GitBranch.parse(forEachRef: "\n\n")` MUST
  return an empty array (git-client-021). `GitConfigEntry.parse(nullSeparated:
  "")` MUST return an empty array (git-client-025). `GitWorktree.parse
  (porcelain: "")` MUST return an empty array (git-client-018).
  `currentBranch(in:)` on a detached HEAD MUST return `nil`, never the
  literal string `"HEAD"`.
- **Boundary/malformed values**: A porcelain record with no path at all
  (`" M \0"`) or a path that is only separators (`" M ///\0"`) MUST cost
  only that one record, never trap the parser (git-client-013,
  git-client-014). A path beginning with a Unicode combining mark MUST keep
  every byte rather than being truncated by a `Character`-based slice
  (git-client-012). A `git config` argument list whose key position holds a
  dash-leading flag-shaped string (`-x.token`) MUST redact the value that
  follows it rather than mistaking the flag for the key and logging the
  secret in clear text (git-client-030). A `git config` argument list whose
  key position holds a bare, non-key-shaped word (`"email"`) MUST redact
  both it and the value that follows (git-client-031).
- **Concurrent access**: `GitClient` is an actor whose verbs each suspend
  for the whole lifetime of the child process, so ten concurrent callers run
  ten concurrent git processes rather than being queued behind one another —
  a deliberate accounting-only bottleneck, not a serialization guarantee
  (`GitClient.swift`). A task cancelled while a verb is in
  flight MUST see `CancellationError` propagate unchanged, never wrapped in
  `GitClientError`, so `Task.isCancelled` and structured-concurrency cleanup
  keep working for the caller (`GitClient.swift`).
- **Error states**: A configured executable path with nothing executable
  there MUST throw `executableNotFound` before any process is spawned, and
  the attempt MUST still be recorded (git-client-037). A command that runs
  to completion and exits non-zero MUST throw `commandFailed` carrying the
  real exit status and `standardError`, with `standardError` never reaching
  `GitCommandLog` (git-client-038, git-client-046). `unsetGlobalConfig` on a
  key that was never set MUST surface git's exit status 5 as an ordinary
  `commandFailed`, with no dedicated case.
- **Timeout (this component's offline-equivalent state)**: This component
  has no network path of its own; its analog of an unreachable server is a
  git process that exceeds `configuration.timeout`. That MUST throw
  `timedOut(verb:)`, with the child terminated before the throw
  (`GitClientError.swift`) and the attempt recorded with a `nil`
  exit status (git-client-039). A launch failure (for example, a working
  directory that does not exist) and any other channel failure are
  collapsed by `execute`'s total, unqualified catch into `launchFailed` — no
  error type outside `GitClientError`, aside from `CancellationError`, can
  escape `execute`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `executableURL` | `URL` | `file:///usr/bin/git` | Path to the git binary `GitClient` spawns (`GitClientConfiguration.swift`) |
| `timeout` | `TimeInterval` | `5` | Wall-clock budget in seconds for one invocation, passed to `SubprocessChannel.run` as its budget |
| `submoduleHandling` | `SubmoduleHandling` (`.ignore` / `.include`) | `.ignore` | When `.ignore`, `status(in:)` appends `--ignore-submodules` (`GitClient.swift`) |
| `extraEnvironment` | `[String: String]` | `[:]` | Merged over the `GIT_TERMINAL_PROMPT=0` default in the spawned child's environment; lets a caller (a test, in particular) redirect something like `GIT_CONFIG_GLOBAL` without mutating process-wide state (`GitClient.swift`) |
| `caller` | `GitCaller` | `GitCaller()` captured at the call site | `#fileID`/`#function` default arguments identifying who invoked a verb (`GitCaller.swift`) |
| `git.executable_path` (`UserSettings` key) | `String` | `"/usr/bin/git"` | Read by `GitClientConfiguration.fromSettings()` into `executableURL` (`UserSettings+Git.swift`) |
| `git.status_timeout_seconds` (`UserSettings` key) | `Int` | `5` | Read by `fromSettings()` into `timeout`, clamped to a minimum of `1` (`GitClientConfiguration.swift`) |
| `git.status_includes_submodules` (`UserSettings` key) | `Bool` | `false` | Read by `fromSettings()`; `true` maps to `.include`, `false` to `.ignore` (`GitClientConfiguration.swift`) |

## Deep Linking

Not applicable: `git-client` is a subprocess-spawning actor with no app URL
scheme, Android intent filter, or platform deep-link registration of its
own; none of its source files reference a URL scheme, Handoff activity, or
`NSUserActivity`.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `commandFailed` detail | `"git \(verb) exited with status \(exitStatus)."` (or with git's own detail appended) | `GitClientError.errorDescription`, `.commandFailed` case (`GitClientError.swift`) |
| `timedOut` | `"git \(verb) did not finish within the configured timeout."` | `.timedOut` case |
| `launchFailed` | `"git \(verb) could not be run: \(reason)"` | `.launchFailed` case |
| `executableNotFound` | `"No git executable at \(path). Change it in Settings > Git."` | `.executableNotFound` case |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in these files — there is no localization
mechanism in this component. This is a plain fact about the source, not a
gap: a port to a platform with an i18n layer MUST decide, as a design choice
outside this contract, whether and how to route these four strings through
it.

## Accessibility Options

Not applicable: `git-client` renders no UI and defines no Reduce Motion,
Increase Contrast, or Differentiate-Without-Color behavior of its own; none
of its source files reference any such display option.

## Feature Flags

Not applicable: no file in this component defines or reads a feature-flag
key. `submoduleHandling` is caller-configured state, not a flag, and every
conditional path (the executable check, the submodule flag, an exit status)
is derived from configuration or from git's own output, never from a flag
this component owns.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event. `GitCommandLog` (see Logging) records operational call
metadata for debugging and audit, not product-analytics events.

## Privacy

- **Data collected**: This component persists no user content of its own;
  `GitClientConfiguration` and the three `UserSettings` keys it reads hold
  only an executable path, a timeout integer, and a boolean. The one
  privacy-relevant surface is the *value* argument of
  `setGlobalConfig(key:value:)`, which may carry an email address, a signing
  key, or a URL containing a token (`GitCommandLog.swift`).
- **Redaction lives at the funnel, not at call sites**: `GitCommandLog
  .redactedArguments` is scoped to the `config` verb and redacts every
  argument at and after the first non-flag position, so a caller-supplied
  value never reaches `.public` `OSLog` output in clear text; `standardError`
  — which may itself echo a repository path — MUST NEVER reach the log at
  all (`GitCommandLog.swift`).
- **Nothing leaves the device through this component**: every verb spawns a
  local git subprocess; none of these source files perform network I/O
  themselves, though the git binary they spawn may contact a remote if a
  future verb passes arguments that do (none of the seven given verbs do).

## Logging

Subsystem/category are whatever `GitCommandLog`'s `Loggable` conformance
configures via `makeLogger()` (`GitCommandLog.swift`).

| Event | Level | Message shape |
|-------|-------|---------------|
| Every invocation attempt, regardless of outcome | info | `` `git <verb> <redacted-arguments> cwd=<path> from=<file>:<function> <ms>ms status=<exitStatus-or-"unfinished">` `` (`GitCommandLog.swift`) |

`GitCommandLog.record` MUST NOT log the process's standard output or
standard error — only that a call happened and where it came from, so git
usage can be counted, attributed, and audited without the log becoming a
copy of the repository (`GitCommandLog.swift`). Arguments are
logged at `.public` privacy after passing through `redactedArguments`
(see Behavioral Requirements and Privacy above), never through
`OSLogPrivacy.private`, because that would collapse the whole interpolation
for every verb rather than redacting the one argument position that needs
it (`GitCommandLog.swift`). The redaction rule today covers only
the `config` verb; the source's own comment names `commit -m <message>` and
any remote URL as expected future additions once those verbs exist
(`GitCommandLog.swift`).

## Platform Notes

- **SwiftUI**: `GitClient` is Foundation-only and framework-agnostic, but its
  own doc comment calls out a SwiftUI caller by name: a `.task` that drives
  `status(in:)` and is torn down mid-flight is the reason `execute` rethrows
  `CancellationError` unchanged rather than wrapping it (`GitClient.swift`). A SwiftUI port keeps that contract by driving every verb
  from a cancellable `Task`/`.task` and never catching `CancellationError`
  as if it were a `GitClientError`.
- **AppKit / UIKit**: The nine source files live in the shared
  `AgenticToolkitCore` framework (`Core/Git/`) and import only `Foundation`
  and `OSLog` — no `AppKit`/`UIKit` dependency at all. An AppKit or UIKit
  caller consumes the same `actor` and the same four-case error type through
  ordinary `async`/`await`, with no framework-specific adaptation needed.
- **Compose (Kotlin/Android)**: The actor's bottleneck-for-accounting model
  maps to a Kotlin object exposing `suspend fun`s backed by
  `ProcessBuilder`/`Process`, run on `Dispatchers.IO`; `withTimeout` stands
  in for the wall-clock budget, a sealed class with the same four variants
  stands in for `GitClientError`, and `kotlinx.coroutines.CancellationException`
  is the analog that MUST likewise be left to propagate unchanged rather than
  wrapped.
- **React/Web**: There is no browser-side equivalent of spawning a native
  git process; a web port MUST run the equivalent of this component in a
  Node.js backend (`child_process.spawn`/`execa`) behind an API the page
  calls, with an `AbortController`/`AbortSignal.timeout` standing in for
  `configuration.timeout` and a discriminated union mirroring the four
  `GitClientError` cases returned as the API's error shape.
- **WinUI 3**: This is a process-spawning wrapper, not an HTTP client, so
  `HttpClient`/`System.Text.Json` do not apply. The port is
  `System.Diagnostics.Process` (`ProcessStartInfo` with
  `RedirectStandardOutput`/`RedirectStandardError` and an environment
  dictionary carrying `GIT_TERMINAL_PROMPT=0`) driven by `Task`/`async`-
  `await` in place of the actor — a single static class or service, never a
  `SemaphoreSlim(1)`, since serialized execution would contradict the
  concurrent-processes contract above. `CancellationTokenSource` with a
  `TimeSpan` timeout replaces the wall-clock budget and `OperationCanceledException`
  replaces `CancellationError` as the one type that MUST propagate unchanged.
  `Windows.Storage.ApplicationDataContainer` is the analog of the three
  `UserSettings` keys `fromSettings()` reads. `ObservableCollection`/
  `INotifyPropertyChanged` have no direct analog here — this component has no
  bindable, mutable collection of its own — but would back a WinUI view model
  that exposes a `GitStatus` snapshot to XAML.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Git/` |

## Design Decisions

**Decision**: `GitClient` is an `actor` whose bottleneck is for accounting
(one identifiable door, one command log, one place to add a future limit),
not for serializing execution — every verb suspends at
`SubprocessChannel.run`, so concurrent callers get concurrent child
processes.
**Rationale**: A `status` on one repository has no reason to wait behind a
`worktree list` on another; a struct with a shared queue would have
serialized them for no benefit (`GitClient.swift`).
**Approved**: pending

**Decision**: `execute` records and then rethrows `CancellationError`
unchanged instead of wrapping it in `GitClientError`.
**Rationale**: Wrapping it would break `Task.isCancelled` propagation and
structured-concurrency cleanup for every caller, starting with a SwiftUI
`.task` torn down while a `status` call is in flight (`GitClient.swift`).
**Approved**: pending

**Decision**: `GitCommandLog.redactedArguments` redacts by argument
*position* (everything at and after the first non-flag position, once that
position is spent) rather than by the *shape* of what is found there.
**Rationale**: The earlier, shape-based scan took the first argument not
beginning with `-` to be the key; a key beginning with `-` (`-x.token`) is
not a well-formed key, so that scan walked past it and logged the *secret*
that followed at `.public`. Spending the position exactly once means a shape
this rule does not model costs a redacted argument, never a leaked one
(`GitCommandLog.swift`).
**Approved**: pending

**Decision**: `execute` decodes captured standard output as UTF-8 first and
falls back to ISO Latin-1, never to `String(decoding:as:)`'s
lossy-replacement decoding.
**Rationale**: `String(decoding:)` would substitute U+FFFD for any byte git
could not express in UTF-8 and hand the parser a path matching nothing on
disk, while a Latin-1 fallback re-reads the whole capture losslessly, at the
cost of mojibake only on the rare capture that is not valid UTF-8
(`GitClient.swift`).
**Approved**: pending

**Decision**: `GitStatus.parse` slices and counts each porcelain record in
UTF-8 bytes, never in `Character`s.
**Rationale**: A path beginning with a combining mark merges with the
preceding separator into one grapheme cluster under `Character` counting,
which previously consumed a byte of the path along with the separator and
yielded an empty path that trapped the directory roll-up (`GitStatus.swift`).
**Approved**: pending

**Decision**: `execute` sets `GIT_TERMINAL_PROMPT=0` unconditionally in the
child's environment, merged under any caller-supplied `extraEnvironment`.
**Rationale**: Without it, a credential prompt would hang the child behind a
terminal nobody is watching, turning a network-auth failure into an
indefinite hang instead of a `commandFailed`/`timedOut` the caller can act on
(`GitClient.swift`).
**Approved**: pending

**Decision**: The `max(1, ...)` timeout clamp lives only in
`GitClientConfiguration.fromSettings()`, not in the plain initializer.
**Rationale**: `fromSettings()` is the path a user-editable settings value
reaches, where zero or a negative number is a user-entry mistake that must
not produce an instantly-expiring budget; a directly-constructed
`GitClientConfiguration` (as tests build) is a programmatic value the caller
is responsible for, so the plain initializer imposes no clamp of its own
(`GitClientConfiguration.swift`).
**Approved**: pending

**Decision**: The three global-configuration verbs run with the user's home
directory as the child's working directory, never a repository directory.
**Rationale**: `git config --global` neither discovers nor reads a
repository, so home is used only as somewhere legible for the child to
stand — never a location this client actually reads from or writes to as a
repository (`GitClient.swift`).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [timeout-handling](agenticdevelopercookbook://compliance/reliability#timeout-handling) | passed | Reliability |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` **passed**: process-spawning and accounting
(`GitClient.execute`) is separate from parsing (`GitStatus`, `GitBranch`,
`GitWorktree`, `GitConfigEntry`, each its own type), from configuration
(`GitClientConfiguration`), and from logging (`GitCommandLog`) — no layer
does another layer's job. `unit-test-coverage` **passed**: seven test files
cover every parser, the redaction rule, the configuration clamp, and the
client's real-process error paths with meaningful assertions, not
placeholders. `explicit-error-handling` **passed**: `execute`'s catch chain
is total by construction — every error becomes a `GitClientError` case
except the one documented, deliberate exception (`CancellationError`
rethrown unchanged); nothing is silently swallowed. `timeout-handling`
**passed**: a `WallClockBudgetExceeded` is mapped to `timedOut`, and the
child is terminated before the error is thrown, per `GitClientError`'s own
doc comment, leaving no orphaned process behind. `fault-tolerance`
**passed**: `GitStatus.parse` and `GitWorktree.parse` are written to cost a
malformed record exactly one dropped entry rather than trapping the process
— demonstrated directly by `recordWithNoPathIsSkipped` and
`pathOfSeparatorsOnlyIsSkipped`. `secure-log-output` **passed**:
`GitCommandLog` never logs standard output or standard error, and
`redactedArguments` keeps a `config` value out of the `.public` log line
entirely. `input-sanitization` **partial**: `GitConfigEntry.isWellFormedKey`
classifies a key shape for *redaction* purposes, but neither
`setGlobalConfig` nor `unsetGlobalConfig` validates `key` or `value` before
handing them to git — an invalid key is left for git itself to reject with a
non-zero exit, which `execute` then surfaces as `commandFailed` rather than
as a pre-flight validation error. `no-pii-in-logs` **passed**: the only
argument position capable of carrying personal data (a `config` value) is
redacted before it reaches the log, and `GitClientError.logDescription`
withholds `standardError`, the launch `reason`, and the configured
executable `path` from ever reaching `OSLog`. `no-hardcoded-strings`
**failed**: all four `GitClientError.errorDescription` strings are hardcoded
English with no lookup table or locale parameter anywhere in this component
(see Localization) — an honestly-reported gap in the source, not a hidden
one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
