<!-- leaf: implement-git-client/projects-git-repo-scanner--part-2 · source: git-client-projects-git-repo-scanner.md -->

# GitRepoScanner — continued (part 2)

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
