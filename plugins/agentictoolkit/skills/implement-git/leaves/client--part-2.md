<!-- leaf: implement-git/client--part-2 · source: git-client.md -->

# Git Client — continued (part 2)

**Rules** (cite as `implement-git/client--part-2#<slug>`):

- `file-status-priority-merge` MUST
- `status-porcelain-record-shape` MUST
- `status-conflict-pair-detection` MUST
- `status-byte-accurate-path-decode` MUST
- `status-directory-rollup` MUST
- `worktree-parse-flush-on-new-record` MUST
- `worktree-branch-shortening` MUST
- `worktree-main-is-first` MUST
- `branch-parse-tab-separated` MUST
- `platform-i18n-layer-decide-design-choice-outside` MUST — Every string above is hardcoded English with no lookup table, ICU message, or locale parameter anywhere in these files …
- `redaction-lives-at-the-funnel-not-at-call-sites` MUST — GitCommandLog .redactedArguments is scoped to the config verb and redacts every argument at and after the first …
- `compose` MUST — The actor's bottleneck-for-accounting model maps to a Kotlin object exposing suspend funs backed by …
- `react-web` MUST — There is no browser-side equivalent of spawning a native git process; a web port MUST run the equivalent of this …
- `winui-3` MUST — This is a process-spawning wrapper, not an HTTP client, so HttpClient/System.Text.Json do not apply. The port is …

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

