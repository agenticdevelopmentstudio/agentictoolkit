<!-- leaf: implement-git/client · source: git-client.md -->

**Rules** (cite as `implement-git/client#<slug>`):

- `single-spawn-point` MUST
- `actor-isolation-non-serializing` MUST
- `status-command-construction` MUST
- `current-branch-detached-head` MUST
- `branches-format-string` MUST
- `worktrees-listing` MUST
- `global-config-directory` MUST
- `global-config-list` MUST
- `set-global-config` MUST
- `unset-global-config-exit-5` MUST
- `executable-preflight` MUST
- `environment-terminal-prompt-disabled` MUST
- `total-failure-mapping` MUST
- `cancellation-error-passthrough` MUST
- `non-zero-exit-mapping` MUST
- `output-decode-fallback` MUST
- `invocation-recorded-before-return` MUST
- `caller-capture-at-call-site` MUST
- `config-default` MUST
- `config-from-settings-timeout-clamp` MUST
- `config-provider-resolved-per-call` MUST
- `value-types-sendable` MUST
- `error-taxonomy` MUST
- `error-description-vs-log-description` MUST
- `command-log-fields` MUST
- `redaction-scope-and-positional-rule` MUST
- `config-entry-key-validator` MUST
- `config-entry-parse-split-rule` MUST

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

