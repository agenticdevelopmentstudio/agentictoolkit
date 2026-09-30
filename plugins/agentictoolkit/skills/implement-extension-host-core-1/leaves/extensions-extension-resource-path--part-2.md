<!-- leaf: implement-extension-host-core-1/extensions-extension-resource-path--part-2 · source: extension-host-core-extensions-extension-resource-path.md -->

# ExtensionResourcePath — continued (part 2)

## Privacy

- **Data collected**: none in the sense of device- or user-identifying
  telemetry. However, the `resolved` value carried by a thrown
  `escapesExtensionDirectory` error, and every `URL` that
  `InstalledContentLocation.homeDotDirectory`/`applicationSupport` derive,
  is an absolute local file-system path that necessarily embeds the local
  account's home-directory name — traced to the use of the process's home
  directory and the user-domain Application Support directory as the base
  of every derived location.
- **Storage**: none. Every value this component produces is held only in
  the caller's own variables for as long as the caller keeps it; this file
  writes nothing to disk.
- **Transmission**: none performed directly by this component — it does no
  networking. Downstream, `SnippetFileFailure.reason` and
  `ThemeImportFailure.message` carry a resolved path (and the account name
  it embeds) into structures a settings panel may display to the extension
  author; how far that display surface propagates is outside this file.
- **Retention**: for the lifetime of whichever value — a `URL`, a thrown
  error, or a search-path array — the caller holds; this component itself
  retains nothing once a call returns.

## Platform Notes

- **SwiftUI**: the source (`ExtensionResourcePath.swift`) is plain
  Foundation — `URL` and, transitively through `NSHomeDirectory()` and
  `FileManager.default.urls(for:in:)`, `FileManager` — with zero dependency
  on SwiftUI or any view-layer framework. It sits in `AgenticToolkitCore`,
  the tier reachable from both `Language/` (the snippet store) and `macOS/`
  (the theme, host, and plugin-manager call sites). A port that keeps this
  component in Swift needs nothing beyond `Foundation`.
- **Compose**: there is no single JVM/Android API that reproduces this
  file's exact resolve-then-contain guarantee out of the box. Model
  `ExtensionResourcePathError` as a Kotlin `sealed class`/`data class` and
  `ExtensionResourcePath` as a Kotlin `object` namespace (the case-less-enum
  equivalent); build the candidate with `java.nio.file.Path.resolve` against
  a `Path.toRealPath()`-canonicalized base. `java.nio.file.Path.startsWith(Path)`
  is already component-aware, unlike a naive string check, so
  `component-wise-comparison` is largely free on this platform — the
  containment test becomes `candidate.startsWith(root) && candidate != root`.
  Compose the plugin/extension search directories from
  `System.getProperty("user.home")` plus a literal dot-prefixed name, and
  `Context.getExternalFilesDir`/`getFilesDir` in place of the Application
  Support directory.
- **React/Web**: for a Node-hosted extension runtime, use
  `path.resolve`/`path.normalize` for the candidate and `fs.realpathSync`
  (or its promise form) to resolve symlinks on both the base and the
  candidate before comparing. Node's `path` module has no built-in
  "is contained in" predicate, so the same component-wise comparison the
  source hand-rolls — never `String.prototype.startsWith`, which reproduces
  the exact sibling-directory bug `component-wise-comparison` guards
  against — has to be hand-rolled again here, typically via
  `path.relative(root, candidate)` checked for neither being absolute nor
  starting with a parent-directory segment. There is no direct Node
  equivalent of `~/Library/Application Support`; the nearest per-OS
  analogues are the platform's own config-directory environment variables,
  commonly wrapped by a small package that already normalizes across
  operating systems.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS or iOS host consumes the same
  `AgenticToolkitCore` type directly with no translation needed.
- **WinUI 3**: there is no .NET or Windows App SDK type that performs this
  exact resolve-then-contain check. `Path.GetFullPath` alone does not
  resolve symlinks or junctions the way symlink resolution does in the
  source, so a port needs an explicit link-resolution step chained with
  `Path.GetFullPath` before the containment comparison. Compare with
  `Path.GetRelativePath(root, candidate)` and reject a result that is
  rooted or begins with a parent-directory segment, rather than
  `string.StartsWith`, for the same component-versus-string-prefix reason
  `component-wise-comparison` exists for in the source. `InstalledContentLocation`'s
  two locations map to `Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)`
  (the Application Support analogue) and, for the hand-filled dotfolder, a
  subfolder of `Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)`
  — Windows has no hidden-by-leading-dot convention, so hiding that folder
  needs an explicit hidden-attribute flag rather than relying on a leading
  dot the way macOS does. `HttpClient`, `System.Text.Json`, `Task`/`async`,
  `ObservableCollection`, and `INotifyPropertyChanged` all have no role
  here: every operation in the source is synchronous, non-networked,
  non-serializing, and returns a value rather than raising a change
  notification.

## Design Decisions

- **Decision**: a single `resolve` function is shared by all four
  extension-declared-path call sites — snippets, a theme's `path`, a
  theme's `include`, and the host's `browser` entry point — rather than
  each contribution point re-deriving its own containment check.
  **Rationale**: the source's own header comment states that three of the
  four call sites were missing the escape half of the check before this
  type existed, each having re-derived the base URL "in its own words,"
  which let the same `../../../.ssh/config` traversal escape through any of
  them except the one that already checked for it.
  **Approved**: pending
- **Decision**: both sides of a containment comparison are canonicalized
  identically — symlinks resolved, then standardized — rather than
  canonicalizing only the untrusted candidate.
  **Rationale**: the source's comment on `canonicalDirectory` gives both
  failure directions concretely: on macOS the temporary directory alone is
  a symlink (`/var` mapping to `/private/var`), so canonicalizing only one
  side would either refuse every legitimate path under a symlinked root or
  accept an escape through a symlink planted inside the extension,
  depending on which side went uncanonicalized.
  **Approved**: pending
- **Decision**: `canonicalChild(_:of:)` canonicalizes only the parent
  directory and appends the component, rather than building the full child
  path first and canonicalizing that.
  **Rationale**: symlink resolution only drops a leading `/private` when
  the remaining path still names something that exists on disk, so
  canonicalizing a not-yet-created child — as an install-directory guard
  needs to, before the directory it is about to create exists — yields a
  different root than canonicalizing its already-existing parent. The
  source's comment states this literally refused every install into a
  macOS temporary directory, or a home on another volume, by name, before
  `canonicalChild` existed to canonicalize only the part that is actually
  there.
  **Approved**: pending
- **Decision**: `url(_:isContainedIn:)` treats the base directory itself as
  not contained in itself, rather than allowing the candidate to equal the
  base.
  **Rationale**: the source's own comment states the consequence of
  allowing equality directly: a declared path of `"."` resolves to the
  directory itself, and treating that as "contained" would hand a caller
  the directory to open as if it were a file.
  **Approved**: pending
- **Decision**: `InstalledContentLocation` derives locations but never
  validates its own string inputs (`appName`, `subdirectory`, `name`) for
  emptiness or shape, leaving that entirely to callers.
  **Rationale**: per `application-support-appname-validation`, the source's
  own doc comment makes a non-empty `appName` a caller precondition rather
  than a guard in the function, and no
  test in `InstalledContentLocationTests.swift` exercises an empty
  `appName`. Documented here rather than silently left as an assumption,
  per the source's own naming of the risk.
  **Approved**: pending
