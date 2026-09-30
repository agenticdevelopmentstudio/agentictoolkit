<!-- leaf: implement-git-client/projects-project-reconciler--part-3 · source: git-client-projects-project-reconciler.md -->

# ProjectReconciler — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `existing` (`plan` parameter) | `[GitRepo]` | none — required | The registry's current rows, as read by the caller (a `ProjectDatabase`) before scanning. |
| `scanned` (`plan` parameter) | `[ScannedGitRepo]` | none — required | What a directory walk (`GitRepoScanner`) just found. |
| `now` (`plan` parameter) | `Date` | `Date()` at the call | The timestamp written into every touched row's `lastSeen`, and into `firstSeen`/`lastSeen` for a new insert. |
| `isStillARepository` (`plan` parameter) | `(String) -> Bool` | `ProjectReconciler.repositoryExists` | Consulted once per missing row to decide skip-versus-delete; injected so `plan` itself never touches the filesystem. |
| `path` (`repositoryExists` parameter) | `String` | none — required | The candidate directory to check for a `.git` entry. |
| `path` (`uniqueName` parameter) | `String` | none — required | The scanned repository's path to derive a display name from. |
| `taken` (`uniqueName` parameter) | `Set<String>` | none — required | Names already in use; the caller seeds it from every existing row's `name` and grows it across one `plan` call's insert pass. |

No function in this file reads an environment variable or a settings key;
every input arrives as an explicit parameter.

## Privacy

- **Data collected**: `plan(...)` reads and returns `GitRepo.path` (an
  absolute filesystem path) and `remote`/`ScannedGitRepo.remote` (a git
  remote URL read elsewhere and passed through) exactly as its inputs
  supply them, with no inspection, redaction, or transformation
  (`ProjectReconciler.swift`).
- **Storage**: None — this file returns a `Plan` value to its caller and
  persists nothing itself; writing the plan's rows to a database is a
  separate component's responsibility.
- **Transmission**: None — this file makes no network call.
- **Retention**: Not applicable — a `Plan` value's lifetime is entirely the
  caller's responsibility once `plan(...)` returns.

## Platform Notes

- **SwiftUI**: The source is
  `packages/apple/AgenticToolkit/macOS/Features/Projects/ProjectReconciler.swift`,
  a plain Foundation file (`import Foundation` only) with no dependency on
  SwiftUI, AppKit, or UIKit; it ports unchanged into any Swift target that
  also has `GitRepo.swift`.
- **Compose**: Model `plan` as a top-level function or a Kotlin `object`
  with no instance state, taking `List<GitRepo>`, `List<ScannedGitRepo>`,
  and an `Instant` in place of `Date`. Build the path lookup with a
  `mutableMapOf<String, GitRepo>()`, the seen-ids and claimed-paths sets
  with `mutableSetOf()`, and port the LIFO-free, single-pass loops directly;
  `uniqueName` becomes a function over `java.io.File(path).toPath().nameCount`
  or a manual split on `File.separator`.
- **React/Web**: Port `plan` as a pure function over plain arrays and a
  `Map`/`Set`, taking `number` (epoch millis) in place of `Date`; there is
  no filesystem distinction to preserve since a Node-hosted port of
  `repositoryExists` would use `fs.existsSync(path.join(p, ".git"))`, matching
  the "existence is the whole test" contract exactly. `uniqueName` ports as
  a function over `path.sep`-split segments with the same escalating-suffix
  loop.
- **AppKit / UIKit**: Identical to the SwiftUI note — nothing in this file
  is tied to a UI framework; it ports unchanged to either. An iOS host would
  still need its own, separately-contracted `isStillARepository` that
  respects the App Sandbox rather than calling `FileManager` against an
  arbitrary path.
- **WinUI 3**: Port `plan` as a static method on a static class, taking
  `IReadOnlyList<GitRepo>`, `IReadOnlyList<ScannedGitRepo>`, a
  `DateTimeOffset`, and a `Func<string, bool>` in place of the closure
  parameter. Build the path lookup with a `Dictionary<string, GitRepo>`, the
  seen-ids and claimed-paths sets with `HashSet<Guid>`/`HashSet<string>`, and
  keep the same three-pass order (exact match, then moves, then inserts,
  then whatever remains is deleted) rather than reordering it into LINQ
  joins, since the ordering itself (moves claiming a path before inserts
  run) is part of the contract. Port `repositoryExists` with
  `System.IO.Directory.Exists`/`File.Exists` against `System.IO.Path.Combine(path, ".git")`
  rather than `Windows.Storage`, since this is ordinary local-disk access,
  not packaged-app storage. Port `uniqueName` with
  `System.IO.Path.GetFileName`/manual splitting on `System.IO.Path.DirectorySeparatorChar`
  and the same escalating-suffix loop; no `Task`/`async` is needed anywhere
  in this port, since every operation here is synchronous in the source.

## Design Decisions

**Decision**: A `.git` entry's mere existence — not its being a directory,
not its containing `HEAD` — is `repositoryExists(atPath:)`'s whole test,
even though the file's own scanner sibling (`GitRepoScanner.isGitDirectory(_:)`)
applies both of those stricter checks.
**Rationale**: The doc comment states it directly: "`.git` is a directory in
an ordinary checkout and a file in a worktree or a submodule, so its
existence is the whole test" (`ProjectReconciler.swift`) —
`repositoryExists` only needs to tell "still something here" from "gone,"
not to classify what kind of git artifact is present the way the scanner's
stricter detection does when deciding whether to report a new project.
**Approved**: pending

**Decision**: `isStillARepository` is a parameter injected into `plan(...)`
with a default of `ProjectReconciler.repositoryExists`, rather than `plan`
calling `repositoryExists` directly by name.
**Rationale**: The doc comment ties this to `dependency-injection`
explicitly: it keeps "the reconciler ... pure and testable without a
filesystem" (`ProjectReconciler.swift`), which is exactly how
every test in `ProjectReconcilerTests.swift` exercises the skip-versus-delete
boundary without touching disk.
**Approved**: pending

**Decision**: The move pass matches by remote first and only falls back to
directory-name equality when both sides have no remote to compare.
**Rationale**: The doc comment gives the reasoning for the ordering (two
checkouts of the same remote are "the same project moved, in the
overwhelming case," `ProjectReconciler.swift`) and for the name
fallback's narrower condition: "a name is only evidence when there is no
remote on either side to disagree about," since two unrelated directories
can share a leaf name and re-pointing one at the other would hand its
settings to a stranger (`ProjectReconciler.swift`).
**Approved**: pending

**Decision**: A move candidate must be unique or the row is deleted instead
of guessed at.
**Rationale**: The doc comment states the cost of guessing wrong directly:
"a guess here silently re-points a project's settings at the wrong folder"
(`ProjectReconciler.swift`), which the ambiguous-match test
confirms produces two fresh inserts and one deletion rather than one lucky
guess.
**Approved**: pending

**Decision**: A row whose path the scan did not report, but which
`isStillARepository` says is still a repository, is left in place — neither
moved nor deleted — rather than treated as absent.
**Rationale**: The doc comment distinguishes "not reported" from "lost":
such a row might be missing only because "the user added a skip pattern, a
parent directory turned unreadable, [or] a scan root moved," and deleting on
that evidence "cascades the project's settings, layout, tabs, pane state and
window frame away with no undo" (`ProjectReconciler.swift`). The
same comment accepts the opposite cost for a genuinely absent path — "a
project on an unmounted volume is forgotten and comes back as new" — as a deliberate, asymmetric trade-off rather than an oversight.
**Approved**: pending

**Decision**: The move pass runs, and claims its matched paths, before the
insert pass considers any scanned repository new.
**Rationale**: The doc comment states the ordering constraint plainly: "a
moved repository must claim its new path before the adoption pass below
turns that same path into a brand-new project" (`ProjectReconciler.swift`) — reversing the order would let a legitimately moved
repository lose its identity, settings, and layout to a fresh row.
**Approved**: pending

**Decision**: `summary.unchanged` is incremented for every exact-path match,
even one that also produced a write to `updates` for a changed remote.
**Rationale**: Not stated directly in a doc comment; reading the code path,
`summary.unchanged` answers "was this row still the same repository at the
same path" while `updates` answers "did any field on it need correcting" —
two different questions the source keeps separate rather than conflating,
matching the same pattern the `git-client-projects-git-repo` recipe records
for `ProjectScanSummary`'s other counts (`unchanged` never appearing in
`summaryText`'s parts list, `skipped` displayed as "not scanned").
**Approved**: pending
