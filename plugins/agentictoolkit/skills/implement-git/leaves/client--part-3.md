<!-- leaf: implement-git/client--part-3 · source: git-client.md -->

# Git Client — continued (part 3)

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
