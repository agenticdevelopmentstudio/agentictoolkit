<!-- leaf: implement-git/client--edge-cases · source: git-client.md -->

# Git Client

**Rules** (cite as `implement-git/client--edge-cases#<slug>`):

- `null-empty-input` MUST — GitStatus.parse(porcelain: "") MUST return .empty (git-client-001). GitBranch.parse(forEachRef: "\n\n") MUST return an …
- `boundary-malformed-values` MUST — A porcelain record with no path at all (" M \0") or a path that is only separators (" M ///\0") MUST cost only that one …
- `concurrent-access` MUST — GitClient is an actor whose verbs each suspend for the whole lifetime of the child process, so ten concurrent callers …
- `error-states` MUST — A configured executable path with nothing executable there MUST throw executableNotFound before any process is spawned, …
- `timeout` MUST — This component has no network path of its own; its analog of an unreachable server is a git process that exceeds …

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
