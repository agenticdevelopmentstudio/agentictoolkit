<!-- leaf: implement-git/client--test-vectors · source: git-client.md -->

# Git Client

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
