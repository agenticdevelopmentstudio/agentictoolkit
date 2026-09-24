---
id: ef4d83d7-ce2c-4868-9763-62a4513ad7c6
title: File System Detection
domain: agentictoolkit://recipes/file-system-detection
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: IDE-marker directory scanning and file-extension language resolution for
  the macOS file browser's model layer.
platforms:
- swift
- macos
tags:
- file-browser
- detection
- macos
- foundation
- mainactor
- sendable
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Detection/IDEDetector.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Detection/LanguageDetection.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/FileBrowser/LanguageDetectionTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/FileTypesSettingsView.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/FileTreeManager.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Language/LSP/LanguageServerConfiguration.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# File System Detection

## Overview

Two logic components under `.../FileBrowser/Model/Detection/`, no visual
surface of their own, that inspect the local file system on behalf of the
file browser: `IDEDetector` (`IDEDetector.swift`), a `@MainActor`
`ObservableObject` that scans a project root for IDE/tool project markers
(`.xcodeproj`, `.xcworkspace`, `Package.swift`, `.vscode`, `.idea`) up to one
directory level deep and publishes the sorted, deduplicated result; and
`LanguageDetection` (`LanguageDetection.swift`), a stateless namespace that
resolves a file URL to a `CodeEditLanguages.CodeLanguage` — consulting the
user's own extension overrides (`CustomFileTypeMappings`) before the
built-in table — and separately remaps that language to the identifier the
Language Server Protocol expects. `IDEDetector` is consumed today by
`FileTreeManager` (one instance per project root); `LanguageDetection` is
consumed by `FileEditorState` and described by
`LanguageServerConfiguration.swift` as the toolkit's one place that derives
an LSP `languageId` from a `CodeLanguage`.

## Behavioral Requirements

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
- **lsp-language-id-default-passthrough**: For every `CodeLanguage.id`
  case not listed in `lsp-language-id-fixed-remap`, `lspLanguageId(for:)`
  MUST return `language.id.rawValue` unchanged; the function MUST be
  total (no throw, no `nil`) over every case of `CodeLanguage.id`.
- **lsp-language-id-single-authority**: No other code in the toolkit
  SHOULD derive an LSP `languageId` from a file extension or a
  `CodeLanguage` independently of `lspLanguageId(for:)` — per the
  function's own doc comment, it is "the single place that mapping is
  made" (see Design Decisions for why `LanguageServerConfiguration`
  cannot simply call it).
- **detect-scan-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. `scan-top-level-read-failure-yields-empty` and an ordinary empty, marker-free directory both produce `detectedIDEs == []` and `isDetecting == false` with no other observable difference — `detect()` has no way to tell a caller "the scan failed" apart from "the scan found nothing." Settling this requires deciding whether `IDEDetector` should expose a distinct failure/error state, which the source does not do.
- **open-fallback-result-unchecked**: NEEDS REVIEW: Not implemented in source. `NSWorkspace.shared.open(targetURL)` in the fallback branch of `open(project: rootURL:)` returns a `Bool` indicating success, but that return value is never read, logged, or otherwise acted on — a failed fallback open is completely silent, unlike the bundle-application path's logged failure. Settling this requires deciding what, if anything, the fallback path should report on failure.
- **language-unresolvable-mapping-unsignaled**: NEEDS REVIEW: Not implemented in source. `FileTypesSettingsView.swift` collects a custom mapping's `languageName` from a free-text `TextField` with only a non-empty check (no validation against `CodeLanguage.allLanguages`); when that text matches no `tsName` or `extensions` entry, `language-falls-back-to-builtin-detection` silently ignores the user's mapping with no error, log, or other signal that it never took effect. Settling this requires deciding whether `language(for:)`, `mapping(for:)`, or the settings UI itself should validate or report an unresolvable `languageName`.
- **custom-mapping-cache-race**: NEEDS REVIEW: Not implemented in source. `CustomFileTypeMappings.cache` and `.activeDefaultsKey` are `nonisolated(unsafe)` mutable statics with no lock or actor isolation; `language(for:)` can run on any thread, and a concurrent `save()` (which sets `cache = nil`) racing a concurrent `mapping(for:)` read has no defined ordering. Settling this requires deciding what synchronization, if any, `CustomFileTypeMappings` should adopt.

## Appearance

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component.

## States

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component. `IDEDetector`'s
one runtime state distinction, "idle" versus "scan in flight," is captured
under Behavioral Requirements (`detector-published-state`,
`detect-guards-reentrancy`), not as a visual-state table.

## Accessibility

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| FSD-001 | ide-type-cases | `IDEType.allCases`; `IDEType(rawValue: "xcodeWorkspace")` | `allCases` has exactly the six listed cases in declaration order; `IDEType(rawValue: "xcodeWorkspace") == .xcodeWorkspace` — traced to `enum IDEType: String, ... CaseIterable` (no dedicated test in the given suite) |
| FSD-002 | ide-type-display-names | `IDEType.vscode.displayName`; `IDEType.androidStudio.displayName` | `"VS Code"`; `"Android Studio"` — traced to the `displayName` switch (no dedicated test in the given suite) |
| FSD-003 | ide-type-system-images | `IDEType.swiftPackage.systemImageName` | `"shippingbox"` — traced to the `systemImageName` switch (no dedicated test in the given suite) |
| FSD-004 | ide-type-bundle-identifiers | `IDEType.xcodeWorkspace.bundleIdentifier`; `IDEType.intellij.bundleIdentifier` | `"com.apple.dt.Xcode"`; `"com.jetbrains.intellij"` — traced to the `bundleIdentifier` switch (no dedicated test in the given suite) |
| FSD-005 | ide-project-identity | `IDEProject(type: .vscode, path: "tools/.vscode", displayName: "VS Code").id` | `"vscode:tools/.vscode"` — traced to `var id: String { "\(type.rawValue):\(path)" }` (no dedicated test in the given suite) |
| FSD-006 | ide-project-value-semantics | Encode an `IDEProject` with `JSONEncoder` then decode it with `JSONDecoder` | Round-trips to an equal value — traced to `Codable, Equatable` conformance (no dedicated test in the given suite) |
| FSD-007 | detector-published-state, detect-guards-reentrancy | `let d = IDEDetector(rootURL: someURL)`; call `d.detect()` twice back to back before the first completes | Second call returns immediately (`isDetecting` was already `true`), so only one background scan runs — traced to `guard !isDetecting else { return }` (no dedicated test in the given suite) |
| FSD-008 | detect-offloads-scan-to-background-queue, detect-publishes-on-main-queue | Call `d.detect()` from the main actor on a root containing one `.xcodeproj` | `d.isDetecting` becomes `true` synchronously, then (after the background hop) `d.detectedIDEs` contains the matching `IDEProject` and `d.isDetecting` becomes `false`, all mutations observed on the main actor — traced to the `DispatchQueue.global` / `DispatchQueue.main` pair (no dedicated test in the given suite) |
| FSD-009 | detect-logs-completion-summary | `detect()` completes with 2 detected IDEs | One info-level log line reporting `2` and the root's last path component, plus 2 debug-level lines, one per `IDEProject` — traced to the `logger.info`/`logger.debug` calls in `detect()`'s completion block (no dedicated test in the given suite) |
| FSD-010 | scan-visible-top-level-entries, match-xcodeproj-by-extension | Root containing `MyApp.xcodeproj/` | Result includes `IDEProject(type: .xcode, path: "MyApp.xcodeproj", displayName: "MyApp")` — traced to the visible `contentsOfDirectory` call feeding `matchMarkers` (no dedicated test in the given suite) |
| FSD-011 | scan-hidden-top-level-entries, match-vscode-directory | Root containing only a hidden `.vscode/` directory (no visible entries) | Result includes `IDEProject(type: .vscode, path: ".vscode", displayName: "VS Code")`, found via the hidden-entries listing since `.vscode` is excluded from the `.skipsHiddenFiles` visible listing — traced to the hidden-content union logic (no dedicated test in the given suite) |
| FSD-012 | scan-recurses-one-level, match-package-swift-file | Root containing `Packages/Foo/Package.swift` | Result includes `IDEProject(type: .swiftPackage, path: "Packages/Foo/Package.swift", displayName: "Foo")`, found via the depth-one recursion into `Packages/` — traced to the `topLevelDirs`/`subContents` loop (no dedicated test in the given suite) |
| FSD-013 | scan-excludes-marker-directories-from-recursion | Root containing `MyApp.xcodeproj/project.pbxproj` | Result does not include any entry derived from inside `MyApp.xcodeproj/` — traced to `isMarkerDirectory` excluding `.xcodeproj` from `topLevelDirs` (no dedicated test in the given suite) |
| FSD-014 | scan-deduplicates-and-sorts-results | Root whose visible and hidden top-level listings could otherwise yield the same `.git`-adjacent entry twice, plus `Zeta.xcodeproj` and `Alpha.xcodeproj` at top level | No duplicate `IDEProject.id` in the result; `Alpha` sorts before `Zeta` — traced to the `seen.insert(...).inserted` filter and the `localizedCaseInsensitiveCompare` sort (no dedicated test in the given suite) |
| FSD-015 | scan-top-level-read-failure-yields-empty | `rootURL` pointing at a path with no read permission | `IDEDetector.scan(rootURL:)` returns `[]`, no error thrown — traced to `guard let topLevelContents = try? ... else { return [] }` (no dedicated test in the given suite) |
| FSD-016 | scan-hidden-listing-failure-degrades | A root where the hidden-entries `contentsOfDirectory` call fails after the visible one already succeeded | Result still reflects matches from the visible entries; no hidden-only markers are found, and the scan does not abort — traced to `?? []` on the hidden-contents lookup (no dedicated test in the given suite) |
| FSD-017 | scan-depth-one-failure-skips-directory | Root with two top-level directories, one unreadable at depth one and one containing `Package.swift` | Result still includes the `Package.swift` match from the readable directory; the unreadable one contributes nothing and does not stop the other from being scanned — traced to `continue` inside the depth-one loop (no dedicated test in the given suite) |
| FSD-018 | match-xcodeproj-by-extension | A regular *file* (not a directory) literally named `Fake.xcodeproj` | Still matched as `IDEProject(type: .xcode, ...)` — the extension check performs no `isDirectory` test — traced to the absence of an `isDirectory` guard in the `.xcodeproj` branch of `matchMarkers` (no dedicated test in the given suite) |
| FSD-019 | match-xcworkspace-by-extension | Top-level entry `Shared.xcworkspace` whose parent is the scanned root (extension `""`) | Matched as `IDEProject(type: .xcodeWorkspace, path: "Shared.xcworkspace", displayName: "Shared")` since the root's extension does not contain `"xcodeproj"` — traced to the `!... .contains("xcodeproj")` guard (no dedicated test in the given suite) |
| FSD-020 | match-package-swift-file | An entry named `Package.swift` that is itself a directory (unusual, but not excluded by name alone) | Not matched as `.swiftPackage` — the `!isDir` check in the `Package.swift` branch rejects it — traced to `if !isDir { ... }` (no dedicated test in the given suite) |
| FSD-021 | match-idea-directory-resolves-jetbrains-type, jetbrains-type-heuristic | `.idea/` containing a file named `MyApp.iml` with no "android" substring | Matched as `IDEProject(type: .intellij, path: ".idea", displayName: "IntelliJ IDEA")` — traced to `detectJetBrainsType` returning `.intellij` when no entry name contains `"android"` (no dedicated test in the given suite) |
| FSD-022 | jetbrains-type-heuristic | `.idea/` containing `android.iml` (mixed case: `Android.iml`) | `detectJetBrainsType` returns `.androidStudio` — the match is on the lowercased name — traced to `name.contains("android")` after `.lowercased()` (no dedicated test in the given suite) |
| FSD-023 | relative-path-computation | `relativePathString(from: URL(fileURLWithPath: "/a/b"), to: URL(fileURLWithPath: "/a/b/c/d.txt"))` | `"c/d.txt"` — traced to the `hasPrefix(rootPath + "/")` branch (no dedicated test in the given suite) |
| FSD-024 | relative-path-computation | `relativePathString(from: URL(fileURLWithPath: "/a/b"), to: URL(fileURLWithPath: "/x/y.txt"))` (child not under root) | `"/x/y.txt"` (the child's unmodified full path) — traced to the fallback `return childPath` (no dedicated test in the given suite) |
| FSD-025 | open-logs-target-before-opening, open-prefers-resolved-application | `IDEDetector.open(project: IDEProject(type: .xcode, path: "MyApp.xcodeproj", displayName: "MyApp"), rootURL: root)` with Xcode installed | One info-level log naming `"Xcode"` and the joined target path is emitted, then `NSWorkspace.shared.open(_:withApplicationAt:configuration:)` is called targeting Xcode's app URL — traced to the `bundleID`/`appURL` branch (no dedicated test in the given suite) |
| FSD-026 | open-falls-back-to-default-handler | `open(project:rootURL:)` where `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` returns `nil` (associated app not installed) | `NSWorkspace.shared.open(targetURL)` (the parameterless overload) is called instead — traced to the `else` branch (no dedicated test in the given suite) |
| FSD-027 | open-bundle-path-failure-logged-only | The bundle-application open's completion handler is invoked with a non-`nil` `error` | One error-level log line containing `error.localizedDescription` is emitted; no exception propagates and no retry occurs — traced to the `if let error = error { logger.error(...) }` block (no dedicated test in the given suite) |
| FSD-028 | language-consults-custom-mapping-first, language-resolves-mapping-by-name-or-extension | `CustomFileTypeMappings.save([CustomFileTypeMapping(fileExtension: "swift", languageName: "json", iconName: "curlybraces")])`; `LanguageDetection.language(for: URL(fileURLWithPath: "/tmp/x.swift"))` | `lang.id == CodeLanguage.json.id` — `LanguageDetectionTests.testCustomOverride` |
| FSD-029 | builtin-detection-is-extension-only | `LanguageDetection.language(for: URL(fileURLWithPath: "/tmp/x.swift"))` with no custom mapping saved | `lang.id == CodeLanguage.swift.id` — `LanguageDetectionTests.testBuiltinSwift` |
| FSD-030 | builtin-detection-is-extension-only | `LanguageDetection.language(for: URL(fileURLWithPath: "/tmp/x.json"))` with no custom mapping saved | `lang.id == CodeLanguage.json.id` — `LanguageDetectionTests.testBuiltinJSON` |
| FSD-031 | language-falls-back-to-builtin-detection | A custom mapping for extension `"foo"` whose `languageName` is `"not-a-real-language"` | `language(for:)` returns whatever `CodeLanguage.detectLanguageFrom(url:)` yields for a `.foo` file (typically `.default`), not a crash or a partial match — traced to `.first(where:)` returning `nil` and falling through (no dedicated test in the given suite) |
| FSD-032 | lsp-language-id-fixed-remap | `LanguageDetection.lspLanguageId(for: CodeLanguage.objc)` | `"objective-c"` — traced to the `case .objc: return "objective-c"` branch (no dedicated test in the given suite) |
| FSD-033 | lsp-language-id-default-passthrough | `LanguageDetection.lspLanguageId(for: CodeLanguage.swift)` | `"swift"` (`language.id.rawValue`, unchanged, via the `default` branch) — traced to the `default: return language.id.rawValue` branch (no dedicated test in the given suite) |
| FSD-034 | lsp-language-id-single-authority | Repository-wide search for a second file-extension-to-LSP-`languageId` switch/table outside `LanguageDetection.swift` | None found in the given sources; `LanguageServerConfiguration.languageIds` takes caller-supplied `String`s precisely so it need not duplicate this table — traced to `LanguageServerConfiguration.swift`'s comment (no automated test; enforced by code review per the SHOULD) |

## Edge Cases

- **Null/empty input — empty root directory.** `scan(rootURL:)` on a root
  with zero entries MUST return `[]` without error, via the same path as
  any other empty result. MUST.
- **Null/empty input — empty file extension.** `language(for:)` on a URL
  whose `pathExtension` is `""` MUST skip the custom-mapping lookup
  entirely (per `!ext.isEmpty`) and go straight to
  `CodeLanguage.detectLanguageFrom(url:)`. MUST.
- **Null/empty input — empty `project.path`.** `open(project: rootURL:)`
  with `project.path == ""` MUST resolve `targetURL` to `rootURL` itself
  (`appendingPathComponent("")` is a no-op) and proceed exactly as with any
  other path. MUST.
- **Boundary values — recursion depth.** A marker two or more directories
  below the root (e.g. `a/b/Package.swift`) MUST NOT be found —
  `scan-recurses-one-level` bounds recursion to exactly one level. MUST.
  There is no other numeric or length boundary in either source file: path
  and extension strings are unbounded.
- **Concurrent access — within one `IDEDetector`.** Overlapping `detect()`
  calls on the same instance MUST be serialized to at most one in-flight
  scan by the `isDetecting` guard (`detect-guards-reentrancy`). MUST.
- **Concurrent access — across `IDEDetector` instances.** `scan(rootURL:)`
  and its helpers touch only their own arguments and the file system, so
  concurrent scans on different roots from different instances MUST be
  safe with no shared mutable state between them. MUST.
- **Concurrent access — `LanguageDetection`/`CustomFileTypeMappings`.**
  Unlike `IDEDetector`, this path has no defined ordering: see the
  `custom-mapping-cache-race` marker above.
- **Error states — unreadable directory at any scanned level.** Every
  `contentsOfDirectory` call in `scan`, `matchMarkers`, and
  `detectJetBrainsType` is wrapped in `try?`; none of them throw out to
  the caller. The observable degradation differs by call site — whole-scan
  abort, hidden-entries-only drop, single-directory skip, or a
  `.intellij` default — as detailed in the three `scan-*-failure-*`
  requirements and `jetbrains-type-heuristic`. MUST.
- **Error states — `NSWorkspace` open failure.** The bundle-application
  path logs and swallows the error (`open-bundle-path-failure-logged-only`,
  MUST); the fallback path swallows it with no signal at all
  (`open-fallback-result-unchecked` marker).
- **Offline/disconnected: not applicable.** Neither `IDEDetector.swift`
  nor `LanguageDetection.swift` performs any network I/O — every operation
  is a local file-system read or a local `NSWorkspace` call.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | `URL` | — (required) | The directory `IDEDetector.scan(rootURL:)` scans and `open(project: rootURL:)` resolves `project.path` against; fixed for the life of an `IDEDetector` instance via `init(rootURL:)`. |
| `project` | `IDEProject` | — (required) | The marker `IDEDetector.open(project: rootURL:)` opens. |
| `url` | `URL` | — (required) | The file `LanguageDetection.language(for:)` resolves a `CodeLanguage` for. |
| `language` | `CodeLanguage` | — (required) | The value `LanguageDetection.lspLanguageId(for:)` remaps to an LSP `languageId`. |
| `CustomFileTypeMappings.activeDefaultsKey` | `String` | `FileTreeConfig.default.customMappingsDefaultsKey` | UserDefaults key `language(for:)` indirectly reads through `mapping(for:)`; host apps override it at startup so per-window/per-project custom mappings can be kept separate. |
| `CustomFileTypeMappings.contributedProvider` | `(@Sendable (String) -> CustomFileTypeMapping?)?` | `nil` | Optional extension-contributed mapping source `mapping(for:)` falls back to when the user's own saved mappings do not claim an extension; set once by the host, not read directly by `LanguageDetection.swift`. |

## Deep Linking

Not applicable: neither `IDEDetector.swift` nor `LanguageDetection.swift`
defines a URL scheme, route, or navigable destination.

## Localization

`IDEType.displayName`/`systemImageName` and the `"VS Code"` literal in
`matchMarkers` are hardcoded English-only string literals returned
directly from `switch` statements, with no `NSLocalizedString`/
`String(localized:)` call and no `.strings`/`.xcstrings` entry in either
source file. These strings are user-facing per `IDEType`'s own doc comment
("Provides display names ... for UI presentation").

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no string-key mechanism) | `"Xcode"` / `"Xcode Workspace"` / `"Swift Package"` / `"VS Code"` / `"IntelliJ IDEA"` / `"Android Studio"` | `IDEType.displayName`: label for a detected project marker |
| (none — no string-key mechanism) | `"VS Code"` | Hardcoded `displayName` literal assigned directly in `matchMarkers`'s `.vscode` branch |

## Accessibility Options

Not applicable: neither source file renders anything or reads any
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — both only produce data (`IDEProject` values,
a `CodeLanguage`, a `languageId` string) for a caller's view to display
later.

## Feature Flags

Not applicable: neither `IDEDetector.swift` nor `LanguageDetection.swift`
contains a feature-flag or remote-config check of any kind.

## Analytics

Not applicable: neither source file emits an analytics event or telemetry
call of any kind.

## Privacy

Not applicable: both files read only local file and directory names and
paths already visible to the user inside their own project directory (IDE
marker files, source file extensions); neither reads, stores, nor
transmits any credential, token, or personal data, and neither performs
any network transmission.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `IDEDetector`
(per `Loggable`'s `subsystem`/`category` defaults, since `IDEDetector` is
the only one of the two types that conforms to `Loggable`).

| Event | Level | Message |
|-------|-------|---------|
| Detection scan completes | info | `IDE detection complete: \(results.count) IDE(s) found in \(rootURL.lastPathComponent)` |
| Each detected IDE, per scan | debug | `  Detected \(ide.type.displayName): \(ide.path)` |
| `open(project:rootURL:)` begins | info | `Opening \(project.type.displayName) project at \(targetURL.path)` |
| `NSWorkspace` open-with-application fails | error | `Failed to open \(project.type.displayName): \(error.localizedDescription)` |

`LanguageDetection.swift` contains no `Logger`/`os_log`/`print` call of any
kind.

## Platform Notes

- **SwiftUI**: Both types (`IDEDetector.swift`, `LanguageDetection.swift`,
  test `Tests/AgenticToolkitMacOSTests/FileBrowser/LanguageDetectionTests.swift`)
  are consumed by SwiftUI-adjacent AppKit code today (`FileTreeManager`,
  `FileEditorState`) but have no SwiftUI import of their own. A SwiftUI
  consumer would drive `IDEDetector` as an `@ObservedObject`/
  `@StateObject`, calling `detect()` in `.task`/`.onAppear` and rendering
  `detectedIDEs` with `systemImageName` as an `Image(systemName:)`.
- **Compose**: Model `IDEType` as a Kotlin `enum class IDEType(val
  rawValue: String)` with `displayName`/`bundleIdentifier` as computed
  properties mirroring the `switch` statements, and `IDEProject` as a
  `data class` (Kotlin's structural `equals`/`hashCode` give
  `Equatable`/`Hashable` for free). Run the scan on
  `Dispatchers.IO` inside a `ViewModel`'s `viewModelScope`, exposing
  `detectedIDEs` as a `StateFlow<List<IDEProject>>` in place of `@Published`.
  `LanguageDetection` becomes a Kotlin `object` with the same two pure
  functions, backed by whatever tree-sitter/language-table equivalent
  Compose's editor stack uses in place of `CodeEditLanguages`.
- **React/Web**: There is no local file system to scan in a browser
  context, so `IDEDetector`'s marker-scanning has no direct web
  equivalent; a server-side or Electron-hosted port would run the same
  directory-walk logic in Node's `fs` module. `LanguageDetection.language`
  ports directly as a pure function over a filename string, keyed off a
  `Record<string, LanguageId>` extension table (the web equivalent of
  `CodeLanguage.allLanguages`), with the custom-override check as a
  user-settings lookup consulted first.
- **AppKit / UIKit**: `IDEDetector.open` is AppKit-specific today
  (`NSWorkspace`); a UIKit port has no equivalent concept of "open an
  external IDE application" and would drop that function entirely, while
  the marker-scanning half of `IDEDetector` (`scan`, `matchMarkers`,
  `isMarkerDirectory`, `detectJetBrainsType`, `relativePathString`) is
  plain Foundation and UI-framework-agnostic. `LanguageDetection` has no
  AppKit or UIKit dependency at all.
- **WinUI 3**: This is the platform this recipe exists to steer. Model
  `IDEType` as a C# `enum IDEType { Xcode, XcodeWorkspace, SwiftPackage,
  VSCode, IntelliJ, AndroidStudio }` with `DisplayName`/`SystemImageName`/
  `BundleIdentifier`-equivalent `string`-returning `switch` expressions
  mirroring the Swift computed properties exactly (Windows has no SF
  Symbol or bundle-identifier equivalent, so `SystemImageName` becomes a
  `Segoe Fluent Icons` glyph key and `BundleIdentifier` becomes an
  `AppUserModelId`/registered-file-association lookup via
  `Windows.System.Launcher.FindUriSchemeHandlersAsync` or
  `Windows.Storage.StorageFile` association APIs, used the same way
  `NSWorkspace.urlForApplication(withBundleIdentifier:)` is used here).
  Model `IDEProject` as a C# `record` for value semantics. Implement
  `scan`/`matchMarkers`/`isMarkerDirectory`/`detectJetBrainsType` with
  `System.IO.Directory.EnumerateFileSystemEntries` wrapped in `try`/`catch`
  in place of Swift's `try?`, preserving the same per-call-site failure
  granularity (whole-scan abort vs. single-directory skip vs. default
  fallback) documented in the `scan-*-failure-*` requirements. Run
  `Scan` on `Task.Run` (in place of `DispatchQueue.global`) and marshal
  the result back with the UI-thread dispatcher (in place of
  `DispatchQueue.main`), guarding re-entrancy with the same `IsDetecting`
  boolean check. Implement `Open` with
  `Windows.System.Launcher.LaunchUriAsync`/`LaunchFileAsync`, trying a
  resolved handler first and falling back to the OS default the same way
  the two-branch Swift `open` does, and log failures with whatever
  logging abstraction the WinUI host uses in place of `os.Logger`.
  For `LanguageDetection`, port `language(for:)` and
  `lspLanguageId(for:)` as static methods on a C# `static class`, with
  `CodeLanguage.allLanguages`'s Windows-side editor-language table
  substituted for `CodeEditLanguages`, and the same
  fixed-remap-then-passthrough `switch` for `LspLanguageId`.

## Design Decisions

- **Decision**: `IDEType.bundleIdentifier` keeps its `String?` return type
  even though every one of the current six cases returns a non-`nil`
  value.
  **Rationale**: the property's own doc comment states it "Returns `nil`
  for types that don't have a dedicated app," and `IDEDetector.open`
  already has a fallback branch for a `nil` identifier — the optional
  type anticipates a future `IDEType` case with no dedicated application,
  even though no such case exists in the source given here.
  **Approved**: pending
- **Decision**: `matchMarkers`'s `.xcworkspace` branch guards against the
  entry's parent directory having extension `"xcodeproj"`, even though
  `scan`'s own `isMarkerDirectory` exclusion already prevents recursing
  into any `.xcodeproj` directory, making that guard unreachable for any
  path `scan` currently visits.
  **Rationale**: not explained in the source; documented here as an
  observed quirk (defensive code for a case the traversal design already
  rules out) rather than silently corrected or removed, per source
  fidelity.
  **Approved**: pending
- **Decision**: `lspLanguageId(for:)` SHOULD remain the toolkit's one
  place that derives an LSP `languageId`, rather than every caller
  deriving it independently.
  **Rationale**: `LanguageServerConfiguration.swift`'s own comment
  explains that `LanguageServerConfiguration` sits in a lower dependency
  tier than `AgenticToolkitMacOS` (where `LanguageDetection` lives) and
  "dependencies point downward only," so it takes a caller-supplied plain
  `String` instead of importing this function — duplicating the remap
  table elsewhere risks reintroducing the `cSharp`/`csharp`-style
  mismatches this function exists to fix.
  **Approved**: pending
- **Decision**: `scan`'s two top-level listing calls fail differently — a
  failed visible-entries call aborts the whole scan (`return []`), while a
  failed hidden-entries call only drops hidden entries and continues.
  **Rationale**: not explained in source comments; documented here as an
  observed asymmetry rather than smoothed into a single uniform failure
  behavior, per source fidelity.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [fault-tolerance](agenticdevelopercookbook://compliance/reliability#fault-tolerance) | passed | Reliability |

Notes: unit-test-coverage is partial because `LanguageDetectionTests.swift`
covers `LanguageDetection.language(for:)`'s built-in and custom-override
paths (three tests) but not `lspLanguageId(for:)`, while `IDEDetector.swift`
— `IDEType`, `IDEProject`, and every function on `IDEDetector` — has no
test file anywhere in the repository (only compiled build artifacts were
found, no source test). separation-of-concerns passes because
`IDEDetector.swift` and `LanguageDetection.swift` are two independently
named files under `.../Model/Detection/`, each with one detection
responsibility, and `LanguageDetection` itself keeps "consult the user's
override" and "fall back to the built-in table" as two distinct steps
rather than one entangled one. no-hardcoded-strings fails because
`IDEType.displayName`/`systemImageName` and the `"VS Code"` literal are
English-only literals with no localization mechanism (see Localization).
fault-tolerance passes because every file-system read in `scan`,
`matchMarkers`, and `detectJetBrainsType` is wrapped in `try?`, so an
unreadable directory or unexpected entry degrades to an empty or partial
result rather than throwing or crashing (see Edge Cases).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
