---
id: 779ac6ea-9ef5-4fb0-8ed9-dc6b9d617344
title: Git Client
domain: agentictoolkit://cookbook/foundation/git/git-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A git subprocess client: status/branch/worktree/global-config verbs through
  one bottleneck, with total error mapping, redacted logging and a timeout.'
platforms:
- swift
- macos
tags:
- git
- version-control
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

The git client is the toolkit's single door to git: a component that spawns
every git process the toolkit or an agent driving it will ever run, through
one bottleneck. It exposes four read-only verbs (status, current branch,
branches, worktrees) and three global-configuration verbs (read global
config, set global config, unset global config), resolves its own
configuration from three persisted settings on every call, records every
attempt — success or failure — in a redacted command log, and maps every
failure onto a closed four-case error outcome. It has no visual surface of
its own; every UI element that shows git state (a status badge, a branch
picker) is a consumer of this contract, not part of it.

## Behavioral Requirements

### The bottleneck and its verbs

- **single-spawn-point**: The git client MUST be the only path by which the
  toolkit spawns a git process; every public verb routes through one
  private execution step, which is the sole place a git process is spawned
  in this component.
- **concurrent-calls-not-serialized**: The git client's verbs MUST each
  suspend for the whole lifetime of the child process without blocking
  other callers, so concurrent callers run concurrent git processes rather
  than being serialized behind one another — the bottleneck is for
  accounting, not for execution order.
- **status-command-construction**: The status verb MUST invoke `git status`
  with arguments `["--porcelain=v1", "-z", "-uall"]`, and MUST append
  `"--ignore-submodules"` when the submodule-handling configuration is set
  to ignore.
- **current-branch-detached-head**: The current-branch verb MUST invoke
  `git rev-parse --abbrev-ref HEAD` and MUST return nothing when the
  trimmed output is empty or equal to the literal string `"HEAD"`.
- **branches-format-string**: The branches verb MUST invoke `git
  for-each-ref` against `refs/heads` with a `--format=<value>` argument,
  where the value is exactly `%(refname:short)%09%(HEAD)%09%(upstream:short)`.
- **worktrees-listing**: The worktrees verb MUST invoke `git worktree list
  --porcelain` and MUST return every worktree of the repository containing
  the given directory, main worktree first.
- **global-config-directory**: The three global-configuration verbs (read,
  set, unset) MUST run with the current user's home directory as the child
  process's working directory, never a repository directory, because `git
  config --global` neither discovers nor reads a repository.
- **global-config-list**: The read-global-config verb MUST invoke `git
  config --global --list --null` and MUST parse the result using the
  config-entry parsing rule below.
- **set-global-config**: The set-global-config verb MUST invoke `git
  config --global <key> <value>` and MUST discard the process's captured
  output.
- **unset-global-config-exit-5**: The unset-global-config verb MUST invoke
  `git config --global --unset <key>` and MUST surface git's exit status 5
  (key was not set) as an ordinary command-failed outcome, not as a
  distinct outcome.

### Execution, configuration and attribution

- **executable-preflight**: The execution step MUST check that the
  configured executable path is actually executable before spawning, and
  MUST throw an executable-not-found outcome (carrying the path) without
  spawning a process when that check fails.
- **environment-terminal-prompt-disabled**: The execution step MUST set
  `GIT_TERMINAL_PROMPT=0` in the spawned child's environment (so a
  credential prompt cannot hang the child behind an unwatched terminal) and
  MUST merge a caller-supplied extra-environment configuration over that
  default, with the caller-supplied values winning on key collision.
- **total-failure-mapping**: The execution step MUST map every error the
  underlying process-launch mechanism throws onto exactly one of a
  timed-out outcome (for exceeding the configured wall-clock budget) or a
  launch-failed outcome (for every other error) — no error type outside
  the git client's own error outcome can leave the execution step, except
  the one deliberate exception below.
- **cancellation-error-passthrough**: The execution step MUST record the
  attempt and then propagate a cancellation signal unchanged rather than
  wrapping it in the git client's own error outcome, so cooperative
  cancellation and any cleanup tied to it keep working for the caller;
  this is the one way a verb can throw something that is not the git
  client's own error outcome.
- **non-zero-exit-mapping**: The execution step MUST throw a
  command-failed outcome, carrying the verb, exit status, and
  standard-error text, when the child's exit status is non-zero, carrying
  the raw standard-error capture for the caller to show.
- **output-decode-fallback**: The execution step MUST decode the child's
  captured standard output as UTF-8 first, MUST fall back to ISO Latin-1
  when UTF-8 decoding fails, and MUST return an empty string when both
  fail.
- **invocation-recorded-before-return**: The execution step MUST record the
  attempt in the command log on every exit path — executable-not-found,
  timed-out, cancelled, launch-failed, and completed (successfully or
  not) — before returning a value or throwing.
- **caller-capture-at-call-site**: The caller-attribution value's file and
  function fields MUST be captured from the calling context at the point a
  verb is invoked, not from inside the git client itself, so a verb records
  who invoked it with no extra effort from the caller.
- **config-default**: The default configuration MUST set the executable
  path to `/usr/bin/git`, the timeout to `5` seconds, and submodule
  handling to ignore.
- **config-from-settings-timeout-clamp**: Deriving configuration from
  persisted settings MUST read the git executable path, the status
  timeout, and the status-includes-submodules settings, and MUST clamp the
  timeout setting's value to a minimum of `1`. This clamp applies only
  when deriving configuration from settings; constructing a configuration
  directly accepts any timeout value, including zero or a negative value,
  with no clamp of its own.
- **config-provider-resolved-per-call**: The git client MUST resolve its
  configuration afresh on every verb call rather than capturing it once at
  construction, so a shared client instance follows a settings change on
  the very next invocation.
- **value-types-thread-safe**: Every value type this component returns — a
  branch entry, the caller-attribution value, the client configuration, a
  config entry, a file status, the status result, and a worktree entry —
  MUST be safe to share across concurrent callers with no additional
  synchronization, so every value that crosses the client's asynchronous
  boundary is safe to use from any calling context.

### Errors and security-relevant logging

- **error-taxonomy**: The git client's error outcome MUST be exactly four
  cases — command-failed, timed-out, launch-failed, executable-not-found —
  and MUST NOT include a cancellation signal as one of its cases.
- **error-description-vs-log-description**: The error outcome's
  user-facing description MAY interpolate git's own standard-error text
  into a message for the command-failed case. The error outcome's
  log-facing description MUST NOT include the standard-error text, the
  launch failure's reason, or the configured executable path in any case,
  returning only the case name plus non-sensitive structured fields (verb,
  exit status).
- **command-log-fields**: The command log MUST record the verb, its
  redacted arguments, the working directory, the calling file and
  function, the duration in milliseconds, and the exit status (or the
  literal string `"unfinished"` when no exit status is available), and
  MUST NOT log the process's standard output or standard error.
- **redaction-scope-and-positional-rule**: The command log's argument
  redaction MUST return arguments unchanged for every verb except config.
  For config, it MUST redact every argument at and after the first
  non-flag (non-`-`-prefixed) argument position — replacing each with
  `<redacted:<byte length>>` — regardless of whether that argument is
  shaped like a well-formed key; the config-entry key validator (below) is
  used only to decide whether to *keep* the argument found at that
  position, never to relocate the position itself.
- **config-entry-key-validator**: The config-entry key validator MUST
  return true only for a non-empty string that contains at least one `.`,
  does not begin with `-`, and contains no whitespace character.
- **config-entry-parse-split-rule**: Parsing a NUL-separated config listing
  MUST split records on NUL, and within each record MUST split the key
  from the value at the *first* newline only, yielding an empty value for
  a record with no newline at all.

### Parsing (file status, status, worktree, branch)

- **file-status-priority-merge**: Merging file statuses MUST return the
  status with the highest priority among the input — conflicted (7) down
  to ignored (0) — or nothing for empty input.
- **status-porcelain-record-shape**: Parsing status MUST split the
  `-z`-terminated porcelain output on NUL, MUST treat each record's first
  two bytes as the index and work-tree status columns, and MUST consume a
  second NUL-terminated field as the origin path whenever either status
  column is `R` or `C`, ahead of every other classification.
- **status-conflict-pair-detection**: Parsing status MUST classify a
  record as conflicted when its two-character status pair is exactly one
  of `DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`, ahead of the
  modified/added/deleted ladder.
- **status-byte-accurate-path-decode**: Parsing status MUST slice and
  count each record in UTF-8 bytes rather than by character, and MUST drop
  a record whose remaining bytes fail to decode as UTF-8 or decode to an
  empty string, costing only that one record.
- **status-directory-rollup**: Parsing status MUST derive directory
  statuses by assigning, to every ancestor path component of every file
  entry, the highest-priority file status among that ancestor's
  descendants.
- **worktree-parse-flush-on-new-record**: Parsing worktrees MUST flush the
  in-progress record whenever a new line beginning with `"worktree "`
  starts, not only on a blank line, and MUST flush once more after the
  input ends to capture a record with no trailing blank line.
- **worktree-branch-shortening**: Parsing worktrees MUST shorten a branch
  line's `refs/heads/<name>` value to `<name>`, and MUST leave a branch
  ref not beginning with `refs/heads/` unshortened.
- **worktree-main-is-first**: Parsing worktrees MUST mark the first flushed
  record as the main worktree and every subsequent record as not the main
  worktree, per the listing's own contract that the main worktree is
  always listed first.
- **branch-parse-tab-separated**: Parsing branches MUST split each line on
  tab, treat a second field of `"*"` as the current branch, and treat a
  third field that is empty as no upstream — the third field for a real
  listing is a single space, not an empty string, for every non-current
  branch.

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
| git-client-001 | status-porcelain-record-shape | Parse an empty status output. | Returns an empty status result. |
| git-client-002 | status-porcelain-record-shape | Parse status output ` M foo.txt` (NUL-terminated). | `foo.txt` has status modified. |
| git-client-003 | status-porcelain-record-shape, status-directory-rollup | Parse status output `?? untracked/new.txt`. | `untracked/new.txt` is untracked; the `untracked` directory rolls up to untracked. |
| git-client-004 | status-directory-rollup | Parse status output ` M a/b/c.txt`. | Directories `a` and `a/b` both roll up to modified. |
| git-client-005 | status-porcelain-record-shape | Parse status output `R  new.txt` followed by NUL-terminated origin path `old.txt`. | `new.txt` is renamed; `old.txt` has no separate entry. |
| git-client-006 | status-porcelain-record-shape | Parse status output `RM new.txt` followed by origin path `old.txt`. | `new.txt` is renamed; no entry is recorded for the combined `old.txt -> new.txt` label. |
| git-client-007 | status-porcelain-record-shape | Parse status output ` R App/Sources/Foo.swift` (origin `App/Sources/Bar.swift`) followed by ` M README.md`. | `Foo.swift` is renamed, `Bar.swift` has no separate entry, `README.md` is modified, and exactly two entries total are recorded. |
| git-client-008 | status-porcelain-record-shape | Parse status output `C  copy.txt` (origin `original.txt`) followed by ` M kept.txt`. | `copy.txt` is recorded as copied under the new path, `original.txt` has no separate entry, `kept.txt` is modified. |
| git-client-009 | status-conflict-pair-detection | Parse status output `AA a/both-added.txt` and `DD b/both-deleted.txt`. | Both are conflicted; directories `a` and `b` both roll up to conflicted. |
| git-client-010 | status-conflict-pair-detection | Parse status output `A  added.txt` and `D  deleted.txt`. | `added.txt` is added; `deleted.txt` is deleted — the conflict rule does not apply to ordinary add/delete pairs. |
| git-client-011 | status-byte-accurate-path-decode | Parse status output ` M café.txt` (non-ASCII, no shell quoting). | `café.txt` is keyed exactly, byte for byte. |
| git-client-012 | status-byte-accurate-path-decode | Parse status output for a path beginning with a standalone combining accent mark. | The path keeps its leading combining mark rather than being truncated; no empty-path entry is recorded. |
| git-client-013 | status-byte-accurate-path-decode | Parse status output with an empty path record (` M ` followed immediately by NUL) followed by ` M kept.txt`. | `kept.txt` is modified; no entry is recorded for the empty path. |
| git-client-014 | status-directory-rollup | Parse status output for a path consisting only of separators (` M ///`). | No directory rollup entries are produced. |
| git-client-015 | worktree-main-is-first, worktree-branch-shortening | Parse a 4-record worktree listing. | The first record is marked as the main worktree, at the repository's own root path, on branch `main`. |
| git-client-016 | worktree-branch-shortening | The same 4-record listing. | The second record's branch is shortened to `tabs`. |
| git-client-017 | worktree-parse-flush-on-new-record | The same 4-record listing. | The third record is detached with no branch; the fourth record is bare. |
| git-client-018 | worktree-parse-flush-on-new-record | Parse an empty worktree listing. | Returns an empty list. |
| git-client-019 | worktree-parse-flush-on-new-record | Parse a worktree listing with one record and no trailing blank line (`worktree /solo`, `HEAD abc`, `branch refs/heads/solo`). | One entry is recorded, marked main, with branch `solo`. |
| git-client-020 | branch-parse-tab-separated | Parse branch listing `main<TAB>*<TAB>origin/main`, `feature<TAB><TAB>`, `tabs<TAB><TAB>origin/tabs`. | Three branch entries: `main` (current, tracking `origin/main`), `feature` (not current, no upstream), `tabs` (not current, tracking `origin/tabs`). |
| git-client-021 | branch-parse-tab-separated | Parse a branch listing consisting only of blank lines. | Returns an empty list. |
| git-client-022 | branch-parse-tab-separated | Parse branch listing `main<TAB> <TAB>origin/main`, `feature<TAB> <TAB>` (a single-space HEAD field, as a real listing produces for a non-current branch). | `main` is recorded as not current. |
| git-client-023 | config-entry-parse-split-rule | Parse a NUL-separated config listing: `user.name`/`Mike`, `user.email`/`mike@example.com`, and `core.editor`/`vim -f` followed by a literal `extra` with no value. | Three entries are recorded; the `core.editor` entry's value includes the embedded newline verbatim. |
| git-client-024 | config-entry-parse-split-rule | Parse a NUL-separated config listing consisting of the single key `alias.st` with no value. | One entry, `alias.st`, with an empty value. |
| git-client-025 | config-entry-parse-split-rule | Parse an empty NUL-separated config listing. | Returns an empty list. |
| git-client-026 | redaction-scope-and-positional-rule | Redact arguments for verb `status` with args `["status", "--porcelain=v1", "-uall", "--ignore-submodules"]`. | Unchanged. |
| git-client-027 | redaction-scope-and-positional-rule | Redact arguments for verb `config` with args `["--global", "--list", "--null"]` and separately `["--global", "--unset", "user.email"]`. | Both unchanged — nothing follows the key position in either case. |
| git-client-028 | redaction-scope-and-positional-rule | Redact arguments for verb `config` with args `["--global", "user.email", "someone@example.com"]`. | `["--global", "user.email", "<redacted:19>"]`. |
| git-client-029 | redaction-scope-and-positional-rule | Redact arguments for verb `config` with args `["--global", "core.pager", "--dash-leading-value", "trailing"]`. | `["--global", "core.pager", "<redacted:20>", "<redacted:8>"]`. |
| git-client-030 | redaction-scope-and-positional-rule | Redact arguments for verb `config` with args `["--global", "-x.token", "s3cr3t"]`. | `["--global", "-x.token", "<redacted:6>"]` — the dash-leading key never leaks its value. |
| git-client-031 | redaction-scope-and-positional-rule | Redact arguments for verb `config` with args `["--global", "email", "someone@example.com"]`. | `["--global", "<redacted:5>", "<redacted:19>"]` — a non-key-shaped word is redacted too. |
| git-client-032 | redaction-scope-and-positional-rule | Redact an empty argument list for verb `config`. | Returns an empty list. |
| git-client-033 | config-default | Read the default configuration. | Executable path `/usr/bin/git`; timeout `5`; submodule handling set to ignore. |
| git-client-034 | config-from-settings-timeout-clamp | Derive configuration from settings: path `/opt/homebrew/bin/git`, timeout `12`, submodules `true`. | The derived configuration reflects all three exactly. |
| git-client-035 | config-from-settings-timeout-clamp | Derive configuration from settings with a timeout setting of `0`. | The derived timeout is `1`. |
| git-client-036 | config-from-settings-timeout-clamp | Derive configuration from settings with a timeout setting of `-5`. | The derived timeout is `1`. |
| git-client-037 | executable-preflight | Configure the executable path as `/nonexistent/git` and call the current-branch verb. | Throws an executable-not-found outcome naming `/nonexistent/git`, before any process is spawned. |
| git-client-038 | non-zero-exit-mapping | Call the status verb against a nonexistent directory. | Throws a command-failed outcome. |
| git-client-039 | total-failure-mapping | Configure a timeout of `0.001` seconds and call the status verb against a real repository. | Throws a timed-out outcome naming the `status` verb. |
| git-client-040 | global-config-directory, set-global-config | Call set-global-config with key `atkgitclienttest.added`, value `added-value`, against a redirected global-config location. | The redirected file, not the real user-wide config, gains the entry. |
| git-client-041 | unset-global-config-exit-5, global-config-directory | Call unset-global-config on a previously seeded key, then read global config. | The key is gone; the listing is empty; the real user-wide config is untouched. |
| git-client-042 | status-command-construction | Call the status verb against a real one-commit fixture repository with one modified file. | `a.txt` has status modified. |
| git-client-043 | current-branch-detached-head | Call the current-branch verb against a fixture's root checkout and its `feature` worktree. | Returns `"main"` and `"feature"` respectively. |
| git-client-044 | branches-format-string | Call the branches verb against a fixture with `main` and `feature` branches. | Both names are present; `main` is marked current. |
| git-client-045 | worktree-main-is-first | Call the worktrees verb against a fixture's root plus one added worktree. | Two entries; the first is main on branch `main`, the second is on branch `feature`. |
| git-client-046 | error-description-vs-log-description | Produce the log-facing description of a command-failed outcome carrying verb `status`, exit status `128`, and standard-error text `"fatal: ... '/Users/secret/repo'"`. | Excludes `"secret"`; includes `"status"` and `"128"`. |
| git-client-047 | error-description-vs-log-description | Produce the log-facing description of a launch-failed outcome carrying reason `"secret-path-in-the-reason"`. | Excludes `"secret"`. |
| git-client-048 | error-description-vs-log-description | Produce the log-facing description of an executable-not-found outcome carrying path `"/Users/secret/bin/git"`. | Excludes `"secret"`. |

## Edge Cases

- **Null/empty input**: Parsing an empty status output MUST return an
  empty status result (git-client-001). Parsing a branch listing of only
  blank lines MUST return an empty list (git-client-021). Parsing an empty
  NUL-separated config listing MUST return an empty list (git-client-025).
  Parsing an empty worktree listing MUST return an empty list
  (git-client-018). The current-branch verb on a detached HEAD MUST return
  nothing, never the literal string `"HEAD"`.
- **Boundary/malformed values**: A porcelain record with no path at all
  (`" M \0"`) or a path that is only separators (`" M ///\0"`) MUST cost
  only that one record, never trap the parser (git-client-013,
  git-client-014). A path beginning with a Unicode combining mark MUST keep
  every byte rather than being truncated by a character-based slice
  (git-client-012). A `git config` argument list whose key position holds
  a dash-leading flag-shaped string (`-x.token`) MUST redact the value that
  follows it rather than mistaking the flag for the key and logging the
  secret in clear text (git-client-030). A `git config` argument list whose
  key position holds a bare, non-key-shaped word (`"email"`) MUST redact
  both it and the value that follows (git-client-031).
- **Concurrent access**: The git client's verbs each suspend for the whole
  lifetime of the child process, so ten concurrent callers run ten
  concurrent git processes rather than being queued behind one another — a
  deliberate accounting-only bottleneck, not a serialization guarantee. A
  call cancelled while a verb is in flight MUST see the cancellation
  signal propagate unchanged, never wrapped in the git client's own error
  outcome, so cooperative cancellation and any cleanup tied to it keep
  working for the caller.
- **Error states**: A configured executable path with nothing executable
  there MUST throw an executable-not-found outcome before any process is
  spawned, and the attempt MUST still be recorded (git-client-037). A
  command that runs to completion and exits non-zero MUST throw a
  command-failed outcome carrying the real exit status and standard-error
  text, with that standard-error text never reaching the command log
  (git-client-038, git-client-046). The unset-global-config verb on a key
  that was never set MUST surface git's exit status 5 as an ordinary
  command-failed outcome, with no dedicated outcome for it.
- **Timeout (this component's offline-equivalent state)**: This component
  has no network path of its own; its analog of an unreachable server is a
  git process that exceeds the configured timeout. That MUST throw a
  timed-out outcome, with the child terminated before the throw, and the
  attempt recorded with no exit status (git-client-039). A launch failure
  (for example, a working directory that does not exist) and any other
  failure from the underlying process-launch mechanism are collapsed by
  the execution step's total mapping into a launch-failed outcome — no
  error type outside the git client's own error outcome, aside from a
  cancellation signal, can escape it.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| executable path | string (file path) | `/usr/bin/git` | Path to the git binary the client spawns. |
| timeout | number (seconds) | `5` | Wall-clock budget for one invocation. |
| submodule handling | enumeration (ignore / include) | ignore | When set to ignore, the status verb appends `--ignore-submodules`. |
| extra environment | key-value map of strings | empty | Merged over the `GIT_TERMINAL_PROMPT=0` default in the spawned child's environment; lets a caller (a test, in particular) redirect something like `GIT_CONFIG_GLOBAL` without mutating process-wide state. |
| caller attribution | captured at the call site | captured automatically | Identifies the calling file and function that invoked a verb, with no effort required from the caller. |
| git executable path setting | string | `"/usr/bin/git"` | Read when deriving configuration from settings, into the executable path. |
| git status timeout setting | integer (seconds) | `5` | Read when deriving configuration from settings, into the timeout, clamped to a minimum of `1`. |
| git status includes submodules setting | boolean | `false` | Read when deriving configuration from settings; `true` maps to include, `false` to ignore. |

## Deep Linking

Not applicable: the git client is a subprocess-spawning component with no
app URL scheme, intent filter, or platform deep-link registration of its
own; nothing in it references a URL scheme or system activity-handoff
mechanism.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| command-failed detail | `"git \(verb) exited with status \(exitStatus)."` (or with git's own detail appended) | The command-failed outcome's user-facing description |
| timed-out | `"git \(verb) did not finish within the configured timeout."` | The timed-out outcome |
| launch-failed | `"git \(verb) could not be run: \(reason)"` | The launch-failed outcome |
| executable-not-found | `"No git executable at \(path). Change it in Settings > Git."` | The executable-not-found outcome |

Every string above is hardcoded English with no lookup table, ICU message,
or locale parameter anywhere in this component — there is no localization
mechanism here. This is a plain fact about the design, not a gap: a port to
a platform with an internationalization layer MUST decide, as a design
choice outside this contract, whether and how to route these four strings
through it.

## Accessibility Options

Not applicable: the git client renders no UI and defines no reduced-motion,
increased-contrast, or color-differentiation behavior of its own; nothing
in it references any such display option.

## Feature Flags

Not applicable: no part of this component defines or reads a feature-flag
key. Submodule handling is caller-configured state, not a flag, and every
conditional path (the executable check, the submodule setting, an exit
status) is derived from configuration or from git's own output, never from
a flag this component owns.

## Analytics

Not applicable: no part of this component emits a client-side analytics or
telemetry event. The command log (see Logging) records operational call
metadata for debugging and audit, not product-analytics events.

## Privacy

- **Data collected**: This component persists no user content of its own;
  the client configuration and the three settings it reads hold only an
  executable path, a timeout integer, and a boolean. The one
  privacy-relevant surface is the *value* argument of the
  set-global-config verb, which may carry an email address, a signing key,
  or a URL containing a token.
- **Redaction lives at the funnel, not at call sites**: The command log's
  argument redaction is scoped to the config verb and redacts every
  argument at and after the first non-flag position, so a caller-supplied
  value never reaches log output in clear text; standard-error text —
  which may itself echo a repository path — MUST NEVER reach the log at
  all.
- **Nothing leaves the device through this component**: every verb spawns
  a local git subprocess; nothing in this component performs network I/O
  itself, though the git binary it spawns may contact a remote if a future
  verb passes arguments that do (none of the seven given verbs do).

## Logging

Subsystem/category are whatever this component's own logging
configuration assigns.

| Event | Level | Message shape |
|-------|-------|---------------|
| Every invocation attempt, regardless of outcome | info | `` `git <verb> <redacted-arguments> cwd=<path> from=<file>:<function> <ms>ms status=<exitStatus-or-"unfinished">` `` |

The command log MUST NOT log the process's standard output or standard
error — only that a call happened and where it came from, so git usage can
be counted, attributed, and audited without the log becoming a copy of the
repository. Arguments are logged at public visibility after passing through
the redaction rule (see Behavioral Requirements and Privacy above), never
collapsed as a whole, because that would hide the entire interpolation for
every verb rather than redacting the one argument position that needs it.
The redaction rule today covers only the config verb; a future addition is
expected to add coverage for a commit-message argument and any remote URL,
once those verbs exist.

## Platform Notes

- **SwiftUI**: The git client is Foundation-only and framework-agnostic,
  but its own documentation calls out a SwiftUI caller by name: a `.task`
  that drives the status verb and is torn down mid-flight is the reason
  the execution step rethrows a cancellation signal unchanged rather than
  wrapping it. A SwiftUI port keeps that contract by driving every verb
  from a cancellable task and never catching a cancellation signal as if
  it were one of the git client's own error outcomes.
- **AppKit / UIKit**: The nine source files (`GitBranch.swift`,
  `GitCaller.swift`, `GitClient.swift`, `GitClientConfiguration.swift`,
  `GitClientError.swift`, `GitCommandLog.swift`, `GitConfigEntry.swift`,
  `GitFileStatus.swift`, `GitStatus.swift`, `GitWorktree.swift`) live in
  the shared `AgenticToolkitCore` framework (`Core/Git/`) and import only
  `Foundation` and `OSLog` — no `AppKit`/`UIKit` dependency at all.
  `GitClient` is declared as a Swift `actor`, whose verbs each suspend at
  the `await SubprocessChannel.run` point, releasing the actor for the
  whole lifetime of the child process (**concurrent-calls-not-serialized**);
  its private `execute` method is the sole call site of
  `SubprocessChannel.run` in this component (**single-spawn-point**).
  `GitBranch`, `GitCaller`, `GitClientConfiguration`, `GitConfigEntry`,
  `GitFileStatus`, `GitStatus`, and `GitWorktree` each declare `Sendable`
  conformance to satisfy **value-types-thread-safe** across the actor's
  async boundary. `execute` checks
  `FileManager.default.isExecutableFile(atPath:)` before spawning
  (**executable-preflight**); its total catch chain maps
  `WallClockBudgetExceeded` to `GitClientError.timedOut` and every other
  error to `.launchFailed`, with a `CancellationError`-specific catch ahead
  of both that rethrows unchanged (**total-failure-mapping**,
  **cancellation-error-passthrough**). `GitCaller`'s `file` and `function`
  properties are captured via `#fileID`/`#function` default arguments
  evaluated in the calling context (**caller-capture-at-call-site**).
  `execute` decodes captured standard output as UTF-8 first, falling back
  to ISO Latin-1, never to `String(decoding:as:)`'s lossy-replacement
  decoding (**output-decode-fallback**).
  `GitClientConfiguration.fromSettings()` reads `UserSettings
  .gitExecutablePath`, `.gitStatusTimeoutSeconds`, and
  `.gitStatusIncludesSubmodules` (`UserSettings+Git.swift`).
  `GitCommandLog`'s subsystem/category come from its `Loggable`
  conformance's `makeLogger()`; arguments are logged at `.public` `OSLog`
  privacy after redaction, never through `OSLogPrivacy.private`, because
  that would collapse the whole interpolation for every verb rather than
  redacting the one argument position that needs it. An AppKit or UIKit
  caller consumes the same actor and the same four-case error outcome
  through ordinary `async`/`await`, with no framework-specific adaptation
  needed.
- **Compose (Kotlin/Android)**: The actor's bottleneck-for-accounting model
  maps to a Kotlin object exposing `suspend fun`s backed by
  `ProcessBuilder`/`Process`, run on `Dispatchers.IO`; `withTimeout` stands
  in for the wall-clock budget, a sealed class with the same four variants
  stands in for the git client's error outcome, and
  `kotlinx.coroutines.CancellationException` is the analog that MUST
  likewise be left to propagate unchanged rather than wrapped.
- **React/Web**: There is no browser-side equivalent of spawning a native
  git process; a web port MUST run the equivalent of this component in a
  Node.js backend (`child_process.spawn`/`execa`) behind an API the page
  calls, with an `AbortController`/`AbortSignal.timeout` standing in for
  the configured timeout and a discriminated union mirroring the four
  error-outcome cases returned as the API's error shape.
- **WinUI 3**: This is a process-spawning wrapper, not an HTTP client, so
  `HttpClient`/`System.Text.Json` do not apply. The port is
  `System.Diagnostics.Process` (`ProcessStartInfo` with
  `RedirectStandardOutput`/`RedirectStandardError` and an environment
  dictionary carrying `GIT_TERMINAL_PROMPT=0`) driven by `Task`/`async`-
  `await` in place of the actor — a single static class or service, never
  a `SemaphoreSlim(1)`, since serialized execution would contradict the
  concurrent-processes contract above. `CancellationTokenSource` with a
  `TimeSpan` timeout replaces the wall-clock budget and
  `OperationCanceledException` replaces the cancellation signal as the one
  type that MUST propagate unchanged. `Windows.Storage
  .ApplicationDataContainer` is the analog of the three settings
  `fromSettings()` reads. `ObservableCollection`/`INotifyPropertyChanged`
  have no direct analog here — this component has no bindable, mutable
  collection of its own — but would back a WinUI view model that exposes a
  status snapshot to XAML.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Git/` |

## Design Decisions

**Decision**: The git client is a Swift `actor` whose bottleneck is for
accounting (one identifiable door, one command log, one place to add a
future limit), not for serializing execution — every verb suspends at
`SubprocessChannel.run`, so concurrent callers get concurrent child
processes.
**Rationale** (Swift actor implementation): A `status` on one repository
has no reason to wait behind a `worktree list` on another; a struct with a
shared queue would have serialized them for no benefit.
**Approved**: pending

**Decision**: The execution step records and then rethrows a cancellation
signal unchanged instead of wrapping it in the git client's own error
outcome.
**Rationale** (Swift implementation): Wrapping it would break cooperative
cancellation propagation and structured-concurrency cleanup for every
caller, starting with a SwiftUI `.task` torn down while a `status` call is
in flight.
**Approved**: pending

**Decision**: The command log's argument redaction redacts by argument
*position* (everything at and after the first non-flag position, once that
position is spent) rather than by the *shape* of what is found there.
**Rationale**: The earlier, shape-based scan took the first argument not
beginning with `-` to be the key; a key beginning with `-` (`-x.token`) is
not a well-formed key, so that scan walked past it and logged the *secret*
that followed in clear text. Spending the position exactly once means a
shape this rule does not model costs a redacted argument, never a leaked
one.
**Approved**: pending

**Decision**: The execution step decodes captured standard output as UTF-8
first and falls back to ISO Latin-1, never to a lossy-replacement decoding.
**Rationale** (Swift implementation): Swift's lossy `String(decoding:)`
would substitute U+FFFD for any byte git could not express in UTF-8 and
hand the parser a path matching nothing on disk, while a Latin-1 fallback
re-reads the whole capture losslessly, at the cost of mojibake only on the
rare capture that is not valid UTF-8.
**Approved**: pending

**Decision**: Parsing status slices and counts each porcelain record in
UTF-8 bytes, never by character.
**Rationale** (Swift implementation): A path beginning with a combining
mark merges with the preceding separator into one grapheme cluster under
Swift's `Character`-based counting, which previously consumed a byte of
the path along with the separator and yielded an empty path that trapped
the directory roll-up.
**Approved**: pending

**Decision**: The execution step sets `GIT_TERMINAL_PROMPT=0`
unconditionally in the child's environment, merged under any
caller-supplied extra environment.
**Rationale**: Without it, a credential prompt would hang the child behind
a terminal nobody is watching, turning a network-auth failure into an
indefinite hang instead of a command-failed/timed-out outcome the caller
can act on.
**Approved**: pending

**Decision**: The `max(1, ...)` timeout clamp lives only in the
settings-derived configuration path, not in the plain constructor.
**Rationale** (Swift implementation): The settings-derived path
(`fromSettings()`) is where a user-editable settings value reaches, where
zero or a negative number is a user-entry mistake that must not produce an
instantly-expiring budget; a directly-constructed configuration (as tests
build) is a programmatic value the caller is responsible for, so the plain
constructor imposes no clamp of its own.
**Approved**: pending

**Decision**: The three global-configuration verbs run with the user's
home directory as the child's working directory, never a repository
directory.
**Rationale**: `git config --global` neither discovers nor reads a
repository, so home is used only as somewhere legible for the child to
stand — never a location this client actually reads from or writes to as a
repository.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to foundation/git/. |
