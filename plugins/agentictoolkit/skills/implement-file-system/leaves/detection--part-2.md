<!-- leaf: implement-file-system/detection--part-2 · source: file-system-detection.md -->

# File System Detection — continued (part 2)

**Rules** (cite as `implement-file-system/detection--part-2#<slug>`):

- `ide-type-cases` MUST
- `ide-type-display-names` MUST
- `ide-type-system-images` MUST
- `ide-type-bundle-identifiers` MUST
- `ide-project-identity` MUST
- `ide-project-value-semantics` MUST
- `detector-published-state` MUST
- `detect-guards-reentrancy` MUST
- `detect-offloads-scan-to-background-queue` MUST
- `detect-publishes-on-main-queue` MUST
- `detect-logs-completion-summary` MUST
- `scan-visible-top-level-entries` MUST
- `scan-hidden-top-level-entries` MUST
- `scan-recurses-one-level` MUST
- `scan-excludes-marker-directories-from-recursion` MUST
- `scan-deduplicates-and-sorts-results` MUST
- `scan-top-level-read-failure-yields-empty` MUST
- `scan-hidden-listing-failure-degrades` MUST
- `scan-depth-one-failure-skips-directory` MUST
- `match-xcodeproj-by-extension` MUST
- `match-xcworkspace-by-extension` MUST
- `match-package-swift-file` MUST
- `match-vscode-directory` MUST
- `match-idea-directory-resolves-jetbrains-type` MUST
- `jetbrains-type-heuristic` MUST
- `relative-path-computation` MUST
- `open-logs-target-before-opening` MUST
- `open-prefers-resolved-application` MUST
- `open-falls-back-to-default-handler` MUST
- `open-bundle-path-failure-logged-only` MUST
- `language-consults-custom-mapping-first` MUST
- `language-resolves-mapping-by-name-or-extension` MUST
- `language-falls-back-to-builtin-detection` MUST
- `builtin-detection-is-extension-only` MUST
- `lsp-language-id-fixed-remap` MUST

- **ide-type-cases**: `IDEType` MUST be a `String`-backed, `Codable`,
  `Equatable`, `Hashable`, `CaseIterable`, `Sendable` enum with exactly six
  cases — `xcode`, `xcodeWorkspace`, `swiftPackage`, `vscode`, `intellij`,
  `androidStudio` — whose raw values equal their case names (Swift's
  default synthesis; no case assigns an explicit string).
- **ide-type-display-names**: `displayName` MUST return `"Xcode"`,
  `"Xcode Workspace"`, `"Swift Package"`, `"VS Code"`, `"IntelliJ IDEA"`,
  and `"Android Studio"` for the six cases respectively.
- **ide-type-system-images**: `systemImageName` MUST return
  `"hammer.fill"`, `"hammer"`, `"shippingbox"`,
  `"chevron.left.forwardslash.chevron.right"`, `"lightbulb.fill"`, and
  `"apps.iphone"` for the six cases respectively.
- **ide-type-bundle-identifiers**: `bundleIdentifier` MUST return
  `"com.apple.dt.Xcode"` for `.xcode`, `.xcodeWorkspace`, and
  `.swiftPackage`; `"com.microsoft.VSCode"` for `.vscode`;
  `"com.jetbrains.intellij"` for `.intellij`; and
  `"com.google.android.studio"` for `.androidStudio` — the property's type
  is `String?` but the current six-case switch never actually returns
  `nil` (see Design Decisions).
- **ide-project-identity**: `IDEProject.id` MUST equal
  `"\(type.rawValue):\(path)"`, composed on every access rather than
  stored.
- **ide-project-value-semantics**: `IDEProject` MUST be a `Codable`,
  `Equatable`, `Hashable`, `Identifiable`, `Sendable` struct holding
  exactly `type: IDEType`, `path: String` (the marker's path relative to
  the scanned root), and `displayName: String`, all set once through
  `init(type:path:displayName:)`.
- **detector-published-state**: `IDEDetector` MUST be a `@MainActor`
  `final class` conforming to `ObservableObject`, exposing `@Published var
  detectedIDEs: [IDEProject]` (initially `[]`) and `@Published var
  isDetecting: Bool` (initially `false`), constructed with a fixed
  `rootURL` via `init(rootURL:)`.
- **detect-guards-reentrancy**: `detect()` MUST return immediately without
  starting a scan when `isDetecting` is already `true`; only one scan MAY
  be in flight per `IDEDetector` instance at a time.
- **detect-offloads-scan-to-background-queue**: `detect()` MUST set
  `isDetecting = true` and dispatch `IDEDetector.scan(rootURL:)` onto
  `DispatchQueue.global(qos: .userInitiated)`, never running the scan on
  the main actor.
- **detect-publishes-on-main-queue**: `detect()` MUST assign the scan's
  result to `detectedIDEs` and set `isDetecting = false` back on
  `DispatchQueue.main`, and MUST do nothing (via `guard let self`) if the
  `IDEDetector` has been deallocated by the time the scan finishes.
- **detect-logs-completion-summary**: On completion, `detect()` MUST log
  one info-level message reporting `results.count` and the root's
  `lastPathComponent`, then one debug-level message per detected
  `IDEProject` reporting its `type.displayName` and `path`.
- **scan-visible-top-level-entries**: `scan(rootURL:)` MUST list the
  root's immediate children with `contentsOfDirectory(at:
  includingPropertiesForKeys: [.isDirectoryKey], options:
  [.skipsHiddenFiles])` and pass every result to `matchMarkers`.
- **scan-hidden-top-level-entries**: `scan(rootURL:)` MUST additionally
  list the root's children with no hidden-file filter, keep only entries
  whose name starts with `"."`, drop any whose path already appeared in
  the visible listing, and pass the remainder to `matchMarkers` as well.
- **scan-recurses-one-level**: For every top-level entry that is a
  directory and is not itself an IDE marker directory, `scan(rootURL:)`
  MUST list that directory's contents (hidden entries included, one
  unfiltered `contentsOfDirectory` call) and pass every entry found to
  `matchMarkers`. `scan(rootURL:)` MUST NOT descend further than this one
  level.
- **scan-excludes-marker-directories-from-recursion**: `scan(rootURL:)`
  MUST NOT treat a directory as a recursion target when its extension is
  `xcodeproj` or `xcworkspace`, or its name is `.vscode`, `.idea`, or
  `.git` (`isMarkerDirectory`).
- **scan-deduplicates-and-sorts-results**: `scan(rootURL:)` MUST remove
  any `IDEProject` whose `id` already appeared earlier in the accumulated
  results, then sort what remains by `displayName` using
  `localizedCaseInsensitiveCompare` in ascending order.
- **scan-top-level-read-failure-yields-empty**: When the visible top-level
  `contentsOfDirectory` call fails (throws), `scan(rootURL:)` MUST return
  `[]` immediately — no hidden-entry listing, no depth-one recursion, and
  no error is thrown, logged, or otherwise surfaced by `scan` itself.
- **scan-hidden-listing-failure-degrades**: When the second,
  hidden-entries `contentsOfDirectory` call fails, `scan(rootURL:)` MUST
  treat it as an empty hidden-entries list (`?? []`) and continue with
  whatever the visible listing already produced, rather than aborting.
- **scan-depth-one-failure-skips-directory**: When the depth-one
  `contentsOfDirectory` call fails for one top-level directory,
  `scan(rootURL:)` MUST skip only that directory (`continue`) and still
  process the remaining top-level directories.
- **match-xcodeproj-by-extension**: `matchMarkers` MUST match any entry
  whose `pathExtension` (case-insensitively) is `xcodeproj` as `.xcode`,
  with `displayName` equal to the entry's name minus that extension, based
  solely on the extension — it MUST NOT check whether the entry is
  actually a directory.
- **match-xcworkspace-by-extension**: `matchMarkers` MUST match any entry
  whose `pathExtension` (case-insensitively) is `xcworkspace` as
  `.xcodeWorkspace`, with `displayName` equal to the entry's name minus
  that extension, UNLESS the entry's immediate parent directory's
  extension (case-insensitively) contains `"xcodeproj"` — a guard that,
  given `scan-excludes-marker-directories-from-recursion`, can never
  actually be triggered by any path `scan` visits (see Design Decisions).
- **match-package-swift-file**: `matchMarkers` MUST match an entry named
  exactly `Package.swift` that is not a directory as `.swiftPackage`, with
  `displayName` equal to that entry's parent directory's name.
- **match-vscode-directory**: `matchMarkers` MUST match an entry named
  exactly `.vscode` that is a directory as `.vscode`, with `displayName`
  hardcoded to `"VS Code"`.
- **match-idea-directory-resolves-jetbrains-type**: `matchMarkers` MUST
  match an entry named exactly `.idea` that is a directory by calling
  `detectJetBrainsType(ideaURL:)` and using its result both as the
  `IDEProject.type` and, via `ideType.displayName`, as the `displayName`.
- **jetbrains-type-heuristic**: `detectJetBrainsType(ideaURL:)` MUST
  return `.androidStudio` if any entry inside `.idea` has a lowercased
  name containing the substring `"android"`, and MUST otherwise return
  `.intellij` — including when the `.idea` directory's own contents
  cannot be listed.
- **relative-path-computation**: `relativePathString(from:to:)` MUST
  return the child path with the root path plus a trailing `"/"` stripped
  when the child path starts with the root path, and MUST return the
  child's full path unchanged when it does not.
- **open-logs-target-before-opening**: `IDEDetector.open(project:
  rootURL:)` MUST compute `targetURL` as `rootURL` plus `project.path` and
  MUST log one info-level message naming `project.type.displayName` and
  `targetURL.path` before attempting to open anything.
- **open-prefers-resolved-application**: `open(project: rootURL:)` MUST
  open `targetURL` via `NSWorkspace.shared.open(_:withApplicationAt:
  configuration:)` targeting the application `NSWorkspace.shared
  .urlForApplication(withBundleIdentifier:)` resolves for
  `project.type.bundleIdentifier`, whenever that identifier is non-`nil`
  and an installed application resolves for it.
- **open-falls-back-to-default-handler**: `open(project: rootURL:)` MUST
  fall back to the parameterless `NSWorkspace.shared.open(targetURL)` —
  the system's default handler for `targetURL` — whenever
  `bundleIdentifier` is `nil` or no installed application resolves for it.
- **open-bundle-path-failure-logged-only**: When the bundle-application
  open path's asynchronous completion handler receives a non-`nil` error,
  `open(project: rootURL:)` MUST log it at error level with
  `error.localizedDescription`, and MUST NOT retry the open, throw, or
  surface the failure to a caller or the user by any other means.
- **language-consults-custom-mapping-first**: `LanguageDetection.language
  (for:)` MUST skip the custom-mapping lookup entirely when
  `url.pathExtension` is empty, and otherwise MUST call
  `CustomFileTypeMappings.mapping(for:)` with the lowercased extension
  before consulting built-in detection.
- **language-resolves-mapping-by-name-or-extension**: When
  `CustomFileTypeMappings.mapping(for:)` returns a mapping,
  `language(for:)` MUST return the first `CodeLanguage` in
  `CodeLanguage.allLanguages` (in that array's own order) whose `tsName`
  equals the mapping's `languageName`, case-insensitively, OR whose
  `extensions` list contains the mapping's `languageName`,
  case-insensitively.
- **language-falls-back-to-builtin-detection**: `language(for:)` MUST fall
  through to `CodeLanguage.detectLanguageFrom(url:)` whenever there is no
  extension, no custom mapping for the extension, or the custom mapping's
  `languageName` matches no `CodeLanguage` by either `tsName` or
  `extensions`.
- **builtin-detection-is-extension-only**: `language(for:)` MUST call
  `CodeLanguage.detectLanguageFrom(url:)` with no `prefixBuffer` or
  `suffixBuffer` argument, so only its URL/filename-extension matching
  path can run — its shebang- and modeline-based matching paths, which
  require a non-`nil` `prefixBuffer`, are unreachable from this call site
  — and MUST return `CodeLanguage.default` when even that lookup finds no
  match.
- **lsp-language-id-fixed-remap**: `lspLanguageId(for:)` MUST return
  `"shellscript"` for `.bash`, `"csharp"` for `.cSharp`,
  `"javascriptreact"` for `.jsx`, `"typescriptreact"` for `.tsx`,
  `"objective-c"` for `.objc`, `"plaintext"` for `.plainText`, `"go.mod"`
  for `.goMod`, `"ocaml.interface"` for `.ocamlInterface`, and
  `"markdown"` for `.markdownInline`.
