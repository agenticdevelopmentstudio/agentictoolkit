---
id: ef4d83d7-ce2c-4868-9763-62a4513ad7c6
title: File System Detection
domain: agentictoolkit://cookbook/workspace/files/project-detection
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: IDE-marker directory scanning and file-extension language resolution for
  the file browser's model layer.
platforms:
- swift
- macos
tags:
- file-browser
- detection
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

Two logic components in the file browser's detection model, neither with a
visual surface of its own, that inspect the local file system on behalf of
the file browser: an IDE/tool-marker detector that scans a project root for
IDE/tool project markers (`.xcodeproj`, `.xcworkspace`, `Package.swift`,
`.vscode`, `.idea`) up to one directory level deep and publishes the sorted,
deduplicated result on the UI thread; and a language-detection component, a
stateless set of functions that resolves a file URL to a code-language
value — consulting the user's own extension overrides before the built-in
table — and separately remaps that language to the identifier the Language
Server Protocol expects. The IDE/tool-marker detector is consumed today by
the file tree's root manager (one instance per project root); the
language-detection component is consumed by the file editor's state and is
the toolkit's one place that derives an LSP `languageId` from a
code-language value.

## Behavioral Requirements

- **ide-type-cases**: The IDE-type value MUST be a string-backed value type
  with exactly six cases — `xcode`, `xcodeWorkspace`, `swiftPackage`,
  `vscode`, `intellij`, `androidStudio` — MUST support equality comparison,
  hashing, enumerating all cases, and encoding/decoding, and MUST be safe to
  share across concurrent code; each case's underlying string value MUST
  equal its case name exactly (no case assigns a different explicit
  string).
- **ide-type-display-names**: The display-name lookup MUST return
  `"Xcode"`, `"Xcode Workspace"`, `"Swift Package"`, `"VS Code"`,
  `"IntelliJ IDEA"`, and `"Android Studio"` for the six cases respectively.
- **ide-type-system-images**: The icon-key lookup MUST resolve to a fixed
  icon key for each of the six cases (see Platform Notes for the exact
  icon identifiers used on Apple platforms).
- **ide-type-bundle-identifiers**: The associated-application-identifier
  lookup MUST return `"com.apple.dt.Xcode"` for `.xcode`,
  `.xcodeWorkspace`, and `.swiftPackage`; `"com.microsoft.VSCode"` for
  `.vscode`; `"com.jetbrains.intellij"` for `.intellij`; and
  `"com.google.android.studio"` for `.androidStudio` — the value is
  optional but the current six-case mapping never actually returns none
  (see Design Decisions).
- **ide-project-identity**: Each detected project's identity MUST equal its
  type's underlying string value joined to its path with a colon
  (`"<type>:<path>"`), computed on every access rather than stored.
- **ide-project-value-semantics**: A detected project value MUST be an
  immutable value type holding exactly a `type` (the IDE-type value), a
  `path` (the marker's path relative to the scanned root), and a
  `displayName`, all set once at construction; it MUST support equality
  comparison, hashing, identity lookup by its own id, encoding/decoding,
  and MUST be safe to share across concurrent code.
- **detector-published-state**: The IDE-marker detector MUST expose an
  observable `detectedIDEs` list (initially empty) and an observable
  `isDetecting` flag (initially `false`), and MUST be constructed with a
  fixed root location (see Platform Notes for the exact mechanism used on
  Apple platforms).
- **detect-guards-reentrancy**: The detect operation MUST return
  immediately without starting a scan when `isDetecting` is already
  `true`; only one scan MAY be in flight per detector instance at a time.
- **detect-offloads-scan-to-background-queue**: The detect operation MUST
  set `isDetecting` to `true` synchronously and run the scan operation off
  the UI thread, never on it (see Platform Notes for the exact mechanism
  used on Apple platforms).
- **detect-publishes-on-main-queue**: The detect operation MUST assign the
  scan's result to `detectedIDEs` and set `isDetecting` to `false` back on
  the UI thread, and MUST do nothing if the detector instance no longer
  exists by the time the scan finishes (see Platform Notes for the exact
  mechanism used on Apple platforms).
- **detect-logs-completion-summary**: On completion, the detect operation
  MUST log one info-level message reporting the result count and the
  root's last path component, then one debug-level message per detected
  project reporting its display name and path.
- **scan-visible-top-level-entries**: The scan operation MUST list the
  root's immediate visible children and pass every result to the
  marker-matching step.
- **scan-hidden-top-level-entries**: The scan operation MUST additionally
  list the root's children with no hidden-file filter, keep only entries
  whose name starts with `"."`, drop any whose path already appeared in
  the visible listing, and pass the remainder to the marker-matching step
  as well.
- **scan-recurses-one-level**: For every top-level entry that is a
  directory and is not itself an IDE marker directory, the scan operation
  MUST list that directory's contents (hidden entries included, in one
  unfiltered listing call) and pass every entry found to the
  marker-matching step. The scan operation MUST NOT descend further than
  this one level.
- **scan-excludes-marker-directories-from-recursion**: The scan operation
  MUST NOT treat a directory as a recursion target when its extension is
  `xcodeproj` or `xcworkspace`, or its name is `.vscode`, `.idea`, or
  `.git`.
- **scan-deduplicates-and-sorts-results**: The scan operation MUST remove
  any detected project whose id already appeared earlier in the
  accumulated results, then sort what remains by display name using a
  locale-aware, case-insensitive comparison in ascending order.
- **scan-top-level-read-failure-yields-empty**: When the visible top-level
  listing fails, the scan operation MUST return an empty result
  immediately — no hidden-entry listing, no depth-one recursion, and no
  error is thrown, logged, or otherwise surfaced by the scan operation
  itself.
- **scan-hidden-listing-failure-degrades**: When the second, hidden-entries
  listing fails, the scan operation MUST treat it as an empty
  hidden-entries list and continue with whatever the visible listing
  already produced, rather than aborting.
- **scan-depth-one-failure-skips-directory**: When the depth-one listing
  fails for one top-level directory, the scan operation MUST skip only
  that directory and still process the remaining top-level directories.
- **match-xcodeproj-by-extension**: The marker-matching step MUST match any
  entry whose extension (case-insensitively) is `xcodeproj` as the `xcode`
  type, with display name equal to the entry's name minus that extension,
  based solely on the extension — it MUST NOT check whether the entry is
  actually a directory.
- **match-xcworkspace-by-extension**: The marker-matching step MUST match
  any entry whose extension (case-insensitively) is `xcworkspace` as the
  `xcodeWorkspace` type, with display name equal to the entry's name minus
  that extension, UNLESS the entry's immediate parent directory's
  extension (case-insensitively) contains `"xcodeproj"` — a guard that,
  given `scan-excludes-marker-directories-from-recursion`, can never
  actually be triggered by any path the scan operation visits (see Design
  Decisions).
- **match-package-swift-file**: The marker-matching step MUST match an
  entry named exactly `Package.swift` that is not a directory as the
  `swiftPackage` type, with display name equal to that entry's parent
  directory's name.
- **match-vscode-directory**: The marker-matching step MUST match an entry
  named exactly `.vscode` that is a directory as the `vscode` type, with
  display name hardcoded to `"VS Code"`.
- **match-idea-directory-resolves-jetbrains-type**: The marker-matching
  step MUST match an entry named exactly `.idea` that is a directory by
  running the JetBrains-type heuristic and using its result both as the
  detected project's type and, via that type's display name, as the
  display name.
- **jetbrains-type-heuristic**: The JetBrains-type heuristic MUST return
  the `androidStudio` type if any entry inside `.idea` has a lowercased
  name containing the substring `"android"`, and MUST otherwise return the
  `intellij` type — including when the `.idea` directory's own contents
  cannot be listed.
- **relative-path-computation**: The relative-path computation MUST return
  the child path with the root path plus a trailing `"/"` stripped when
  the child path starts with the root path, and MUST return the child's
  full path unchanged when it does not.
- **open-logs-target-before-opening**: The open operation MUST compute the
  target location as the root joined with the project's path, and MUST log
  one info-level message naming the project's type display name and the
  target's path before attempting to open anything.
- **open-prefers-resolved-application**: The open operation MUST open the
  target location with the specific installed application that resolves
  for the project type's associated-application identifier, whenever that
  identifier is present and an installed application resolves for it (see
  Platform Notes for the exact mechanism used on Apple platforms).
- **open-falls-back-to-default-handler**: The open operation MUST fall back
  to the system's default handler for the target location whenever the
  associated-application identifier is absent or no installed application
  resolves for it (see Platform Notes for the exact mechanism used on
  Apple platforms).
- **open-bundle-path-failure-logged-only**: When the specific-application
  open path's completion callback receives an error, the open operation
  MUST log it at error level with the error's full description, and MUST
  NOT retry the open, throw, or surface the failure to a caller or the
  user by any other means.
- **language-consults-custom-mapping-first**: The language-resolution
  operation MUST skip the custom-mapping lookup entirely when the file's
  extension is empty, and otherwise MUST look up a custom mapping for the
  lowercased extension before consulting built-in detection.
- **language-resolves-mapping-by-name-or-extension**: When a custom mapping
  is found for the extension, the language-resolution operation MUST
  return the first language value in the built-in language table (in that
  table's own order) whose canonical name equals the mapping's language
  name, case-insensitively, OR whose extension list contains the mapping's
  language name, case-insensitively.
- **language-falls-back-to-builtin-detection**: The language-resolution
  operation MUST fall through to built-in detection whenever there is no
  extension, no custom mapping for the extension, or the custom mapping's
  language name matches no language value by either canonical name or
  extension list.
- **builtin-detection-is-extension-only**: The language-resolution
  operation MUST call built-in detection with no file-content sample, so
  only its filename-extension matching path can run — its shebang- and
  modeline-based matching paths, which require a content sample, are
  unreachable from this call site — and MUST return the default language
  value when even that lookup finds no match.
- **lsp-language-id-fixed-remap**: The LSP-language-id remap MUST return
  `"shellscript"` for `bash`, `"csharp"` for `cSharp`,
  `"javascriptreact"` for `jsx`, `"typescriptreact"` for `tsx`,
  `"objective-c"` for `objc`, `"plaintext"` for `plainText`, `"go.mod"` for
  `goMod`, `"ocaml.interface"` for `ocamlInterface`, and `"markdown"` for
  `markdownInline`.
- **lsp-language-id-default-passthrough**: For every language identifier
  not listed in `lsp-language-id-fixed-remap`, the LSP-language-id remap
  MUST return the language identifier's own underlying string value
  unchanged; the operation MUST be total (no throw, no absent result) over
  every language identifier.
- **lsp-language-id-single-authority**: No other code in the toolkit
  SHOULD derive an LSP `languageId` from a file extension or a
  code-language value independently of the LSP-language-id remap — per the
  operation's own documentation, it is "the single place that mapping is
  made" (see Design Decisions for why the language-server configuration
  component cannot simply call it).
- **detect-scan-failure-unsignaled**: NEEDS REVIEW: Not implemented in source. `scan-top-level-read-failure-yields-empty` and an ordinary empty, marker-free directory both produce an empty `detectedIDEs` and `isDetecting == false` with no other observable difference — the detect operation has no way to tell a caller "the scan failed" apart from "the scan found nothing." Settling this requires deciding whether the IDE-marker detector should expose a distinct failure/error state, which the source does not do.
- **open-fallback-result-unchecked**: NEEDS REVIEW: Not implemented in source. The system default-handler open in the fallback branch of the open operation returns a success indicator, but that return value is never read, logged, or otherwise acted on — a failed fallback open is completely silent, unlike the specific-application path's logged failure. Settling this requires deciding what, if anything, the fallback path should report on failure.
- **language-unresolvable-mapping-unsignaled**: NEEDS REVIEW: Not implemented in source. The settings UI collects a custom mapping's language name from free text with only a non-empty check (no validation against the built-in language table); when that text matches no canonical name or extension entry, `language-falls-back-to-builtin-detection` silently ignores the user's mapping with no error, log, or other signal that it never took effect. Settling this requires deciding whether the language-resolution operation, the mapping lookup, or the settings UI itself should validate or report an unresolvable language name.
- **custom-mapping-cache-race**: NEEDS REVIEW: Not implemented in source. The custom-mapping store's cache and active-defaults-key are mutable shared state with no lock or other serialization discipline; the language-resolution operation can run on any thread, and a concurrent save (which clears the cache) racing a concurrent mapping-lookup read has no defined ordering. Settling this requires deciding what synchronization, if any, the custom-mapping store should adopt.

## Appearance

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component.

## States

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component. The
IDE-marker detector's one runtime state distinction, "idle" versus "scan in
flight," is captured under Behavioral Requirements
(`detector-published-state`, `detect-guards-reentrancy`), not as a
visual-state table.

## Accessibility

Not applicable — this is a directory-scanning detector and a
file-extension-to-language resolver, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| FSD-001 | ide-type-cases | Enumerate all IDE-type cases; construct an IDE-type value from the string `"xcodeWorkspace"`. | The enumeration yields exactly the six listed cases in declaration order; the value constructed from `"xcodeWorkspace"` equals the `xcodeWorkspace` case — traced to the IDE-type declaration (no dedicated test in the given suite) |
| FSD-002 | ide-type-display-names | Evaluate the display-name lookup on the `vscode` and `androidStudio` cases. | `"VS Code"`; `"Android Studio"` — traced to the display-name lookup (no dedicated test in the given suite) |
| FSD-003 | ide-type-system-images | Evaluate the icon-key lookup on the `swiftPackage` case. | Resolves to the icon key mapped to that case (`"shippingbox"` on Apple platforms; see Platform Notes) — traced to the icon-key lookup (no dedicated test in the given suite) |
| FSD-004 | ide-type-bundle-identifiers | Evaluate the associated-application-identifier lookup on the `xcodeWorkspace` and `intellij` cases. | `"com.apple.dt.Xcode"`; `"com.jetbrains.intellij"` — traced to the associated-application-identifier lookup (no dedicated test in the given suite) |
| FSD-005 | ide-project-identity | Construct a detected-project value with type `vscode`, path `"tools/.vscode"`, display name `"VS Code"`, and evaluate its identity. | `"vscode:tools/.vscode"` — traced to the identity computation (no dedicated test in the given suite) |
| FSD-006 | ide-project-value-semantics | Encode a detected-project value then decode it back. | Round-trips to an equal value — traced to the value type's encode/decode and equality support (no dedicated test in the given suite) |
| FSD-007 | detector-published-state, detect-guards-reentrancy | Construct an IDE-marker detector on a root location; trigger the detect operation twice back to back before the first completes. | Second call returns immediately (`isDetecting` was already `true`), so only one background scan runs — traced to the reentrancy guard (no dedicated test in the given suite) |
| FSD-008 | detect-offloads-scan-to-background-queue, detect-publishes-on-main-queue | Trigger the detect operation from the UI thread on a root containing one `.xcodeproj`. | `isDetecting` becomes `true` synchronously, then (after the background hop) `detectedIDEs` contains the matching detected project and `isDetecting` becomes `false`, all mutations observed on the UI thread — traced to the background/UI-thread handoff (no dedicated test in the given suite) |
| FSD-009 | detect-logs-completion-summary | The detect operation completes with 2 detected IDEs. | One info-level log line reporting `2` and the root's last path component, plus 2 debug-level lines, one per detected project — traced to the completion-logging step (no dedicated test in the given suite) |
| FSD-010 | scan-visible-top-level-entries, match-xcodeproj-by-extension | Root containing `MyApp.xcodeproj/` | Result includes a detected project with type `xcode`, path `"MyApp.xcodeproj"`, display name `"MyApp"` — traced to the visible-listing call feeding the marker-matching step (no dedicated test in the given suite) |
| FSD-011 | scan-hidden-top-level-entries, match-vscode-directory | Root containing only a hidden `.vscode/` directory (no visible entries) | Result includes a detected project with type `vscode`, path `".vscode"`, display name `"VS Code"`, found via the hidden-entries listing since `.vscode` is excluded from the hidden-file-filtered visible listing — traced to the hidden-content union logic (no dedicated test in the given suite) |
| FSD-012 | scan-recurses-one-level, match-package-swift-file | Root containing `Packages/Foo/Package.swift` | Result includes a detected project with type `swiftPackage`, path `"Packages/Foo/Package.swift"`, display name `"Foo"`, found via the depth-one recursion into `Packages/` — traced to the depth-one recursion loop (no dedicated test in the given suite) |
| FSD-013 | scan-excludes-marker-directories-from-recursion | Root containing `MyApp.xcodeproj/project.pbxproj` | Result does not include any entry derived from inside `MyApp.xcodeproj/` — traced to the marker-directory exclusion from the recursion set (no dedicated test in the given suite) |
| FSD-014 | scan-deduplicates-and-sorts-results | Root whose visible and hidden top-level listings could otherwise yield the same `.git`-adjacent entry twice, plus `Zeta.xcodeproj` and `Alpha.xcodeproj` at top level | No duplicate detected-project id in the result; `Alpha` sorts before `Zeta` — traced to the deduplication filter and the case-insensitive sort (no dedicated test in the given suite) |
| FSD-015 | scan-top-level-read-failure-yields-empty | A root location pointing at a path with no read permission | The scan operation returns an empty result, no error thrown — traced to the visible-listing failure guard (no dedicated test in the given suite) |
| FSD-016 | scan-hidden-listing-failure-degrades | A root where the hidden-entries listing fails after the visible one already succeeded | Result still reflects matches from the visible entries; no hidden-only markers are found, and the scan does not abort — traced to the hidden-listing failure fallback (no dedicated test in the given suite) |
| FSD-017 | scan-depth-one-failure-skips-directory | Root with two top-level directories, one unreadable at depth one and one containing `Package.swift` | Result still includes the `Package.swift` match from the readable directory; the unreadable one contributes nothing and does not stop the other from being scanned — traced to the depth-one failure skip (no dedicated test in the given suite) |
| FSD-018 | match-xcodeproj-by-extension | A regular *file* (not a directory) literally named `Fake.xcodeproj` | Still matched as the `xcode` type — the extension check performs no directory test — traced to the absence of a directory guard in the marker-matching step's `.xcodeproj` branch (no dedicated test in the given suite) |
| FSD-019 | match-xcworkspace-by-extension | Top-level entry `Shared.xcworkspace` whose parent is the scanned root (extension `""`) | Matched as the `xcodeWorkspace` type, path `"Shared.xcworkspace"`, display name `"Shared"` since the root's extension does not contain `"xcodeproj"` — traced to the parent-extension guard (no dedicated test in the given suite) |
| FSD-020 | match-package-swift-file | An entry named `Package.swift` that is itself a directory (unusual, but not excluded by name alone) | Not matched as the `swiftPackage` type — the not-a-directory check in that branch rejects it — traced to the marker-matching step's directory check (no dedicated test in the given suite) |
| FSD-021 | match-idea-directory-resolves-jetbrains-type, jetbrains-type-heuristic | `.idea/` containing a file named `MyApp.iml` with no "android" substring | Matched as the `intellij` type, path `.idea`, display name `"IntelliJ IDEA"` — traced to the JetBrains-type heuristic returning the `intellij` type when no entry name contains `"android"` (no dedicated test in the given suite) |
| FSD-022 | jetbrains-type-heuristic | `.idea/` containing `android.iml` (mixed case: `Android.iml`) | The JetBrains-type heuristic returns the `androidStudio` type — the match is on the lowercased name — traced to the substring match after lowercasing (no dedicated test in the given suite) |
| FSD-023 | relative-path-computation | Compute the relative path from `/a/b` to `/a/b/c/d.txt`. | `"c/d.txt"` — traced to the root-prefix-match branch (no dedicated test in the given suite) |
| FSD-024 | relative-path-computation | Compute the relative path from `/a/b` to `/x/y.txt` (child not under root). | `"/x/y.txt"` (the child's unmodified full path) — traced to the fallback branch (no dedicated test in the given suite) |
| FSD-025 | open-logs-target-before-opening, open-prefers-resolved-application | Trigger the open operation for a detected project with type `xcode`, path `"MyApp.xcodeproj"`, display name `"MyApp"`, with Xcode installed. | One info-level log naming `"Xcode"` and the joined target path is emitted, then the target is opened with Xcode specifically (see Platform Notes for the exact mechanism used on Apple platforms) — traced to the resolved-application branch (no dedicated test in the given suite) |
| FSD-026 | open-falls-back-to-default-handler | Trigger the open operation where the associated application is not installed. | The system's default handler is invoked instead (see Platform Notes for the exact mechanism used on Apple platforms) — traced to the fallback branch (no dedicated test in the given suite) |
| FSD-027 | open-bundle-path-failure-logged-only | The specific-application open's completion callback is invoked with an error. | One error-level log line containing the error's full description is emitted; no exception propagates and no retry occurs — traced to the completion-error logging branch (no dedicated test in the given suite) |
| FSD-028 | language-consults-custom-mapping-first, language-resolves-mapping-by-name-or-extension | Save a custom mapping (extension `swift`, language name `json`, icon name `curlybraces`); resolve the language for a file named `/tmp/x.swift`. | The resolved language's identifier equals the `json` language's identifier — confirmed by the language-detection test suite |
| FSD-029 | builtin-detection-is-extension-only | Resolve the language for a file named `/tmp/x.swift` with no custom mapping saved. | The resolved language's identifier equals the `swift` language's identifier — confirmed by the language-detection test suite |
| FSD-030 | builtin-detection-is-extension-only | Resolve the language for a file named `/tmp/x.json` with no custom mapping saved. | The resolved language's identifier equals the `json` language's identifier — confirmed by the language-detection test suite |
| FSD-031 | language-falls-back-to-builtin-detection | A custom mapping for extension `"foo"` whose language name is `"not-a-real-language"` | The language-resolution operation returns whatever built-in detection yields for a `.foo` file (typically the default language value), not a crash or a partial match — traced to the by-name-or-extension lookup finding nothing and falling through (no dedicated test in the given suite) |
| FSD-032 | lsp-language-id-fixed-remap | Evaluate the LSP-language-id remap on the `objc` language. | `"objective-c"` — traced to the fixed-remap branch (no dedicated test in the given suite) |
| FSD-033 | lsp-language-id-default-passthrough | Evaluate the LSP-language-id remap on the `swift` language. | `"swift"` (the language identifier's own underlying string value, unchanged, via the passthrough branch) — traced to the default passthrough branch (no dedicated test in the given suite) |
| FSD-034 | lsp-language-id-single-authority | Repository-wide search for a second file-extension-to-LSP-`languageId` mapping outside the language-detection component. | None found in the given sources; the language-server configuration component takes caller-supplied strings precisely so it need not duplicate this table — traced to that component's own documentation (no automated test; enforced by code review per the SHOULD) |

## Edge Cases

- **Null/empty input — empty root directory.** The scan operation on a root
  with zero entries MUST return an empty result without error, via the
  same path as any other empty result. MUST.
- **Null/empty input — empty file extension.** The language-resolution
  operation on a URL whose extension is empty MUST skip the custom-mapping
  lookup entirely and go straight to built-in detection. MUST.
- **Null/empty input — empty project path.** The open operation with an
  empty project path MUST resolve the target location to the root location
  itself (appending an empty path component is a no-op) and proceed
  exactly as with any other path. MUST.
- **Boundary values — recursion depth.** A marker two or more directories
  below the root (e.g. `a/b/Package.swift`) MUST NOT be found —
  `scan-recurses-one-level` bounds recursion to exactly one level. MUST.
  There is no other numeric or length boundary in either component: path
  and extension strings are unbounded.
- **Concurrent access — within one detector instance.** Overlapping
  detect-operation calls on the same instance MUST be serialized to at
  most one in-flight scan by the `isDetecting` guard
  (`detect-guards-reentrancy`). MUST.
- **Concurrent access — across detector instances.** The scan operation
  and its helpers touch only their own arguments and the file system, so
  concurrent scans on different roots from different instances MUST be
  safe with no shared mutable state between them. MUST.
- **Concurrent access — language detection and the custom-mapping store.**
  Unlike the IDE-marker detector, this path has no defined ordering: see
  the `custom-mapping-cache-race` marker above.
- **Error states — unreadable directory at any scanned level.** Every
  directory-listing call in the scan operation, the marker-matching step,
  and the JetBrains-type heuristic tolerates a failure without throwing
  out to the caller. The observable degradation differs by call site —
  whole-scan abort, hidden-entries-only drop, single-directory skip, or an
  `intellij` default — as detailed in the three `scan-*-failure-*`
  requirements and `jetbrains-type-heuristic`. MUST.
- **Error states — application-open failure.** The specific-application
  path logs and swallows the error (`open-bundle-path-failure-logged-only`,
  MUST); the fallback path swallows it with no signal at all
  (`open-fallback-result-unchecked` marker).
- **Offline/disconnected: not applicable.** Neither the IDE-marker
  detector nor the language-detection component performs any network
  I/O — every operation is a local file-system read or a local
  application-launch call.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | a file-system location | — (required) | The directory the scan operation scans and the open operation resolves `project.path` against; fixed for the life of a detector instance. |
| `project` | a detected-project value | — (required) | The marker the open operation opens. |
| `url` | a file-system location | — (required) | The file the language-resolution operation resolves a code-language value for. |
| `language` | a code-language value | — (required) | The value the LSP-language-id remap remaps to an LSP `languageId`. |
| `CustomFileTypeMappings.activeDefaultsKey` | a settings-key string | the host-configured default mappings key | Settings key the language-resolution operation indirectly reads through the mapping lookup; host apps override it at startup so per-window/per-project custom mappings can be kept separate. |
| `CustomFileTypeMappings.contributedProvider` | an optional callback taking an extension string and returning a mapping, or none | none | Optional extension-contributed mapping source the mapping lookup falls back to when the user's own saved mappings do not claim an extension; set once by the host, not read directly by the language-detection component. |

## Deep Linking

Not applicable: neither the IDE-marker detector nor the language-detection
component defines a URL scheme, route, or navigable destination.

## Localization

The display-name lookup, the icon-key lookup, and the `"VS Code"` literal
in the marker-matching step are hardcoded English-only string literals
returned directly from fixed mappings, with no localization-API call and no
localized-strings-table entry in either component. These strings are
user-facing per the IDE-type value's own documentation ("Provides display
names ... for UI presentation").

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — no string-key mechanism) | `"Xcode"` / `"Xcode Workspace"` / `"Swift Package"` / `"VS Code"` / `"IntelliJ IDEA"` / `"Android Studio"` | The display-name lookup: label for a detected project marker |
| (none — no string-key mechanism) | `"VS Code"` | Hardcoded display-name literal assigned directly in the marker-matching step's `.vscode` branch |

## Accessibility Options

Not applicable: neither component renders anything or reads any
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color) — both only produce data (detected-project
values, a code-language value, a `languageId` string) for a caller's view
to display later.

## Feature Flags

Not applicable: neither the IDE-marker detector nor the language-detection
component contains a feature-flag or remote-config check of any kind.

## Analytics

Not applicable: neither component emits an analytics event or telemetry
call of any kind.

## Privacy

Not applicable: both components read only local file and directory names
and paths already visible to the user inside their own project directory
(IDE marker files, source file extensions); neither reads, stores, nor
transmits any credential, token, or personal data, and neither performs
any network transmission.

## Logging

Subsystem: the host application's bundle identifier (see Platform Notes
for the exact mechanism used on Apple platforms) | Category: `IDEDetector`
(the IDE-marker detector is the only one of the two components that logs
at all).

| Event | Level | Message |
|-------|-------|---------|
| Detection scan completes | info | `IDE detection complete: <count> IDE(s) found in <root's last path component>` |
| Each detected IDE, per scan | debug | `  Detected <type display name>: <path>` |
| The open operation begins | info | `Opening <project type display name> project at <target path>` |
| The specific-application open fails | error | `Failed to open <project type display name>: <error's full description>` |

The language-detection component contains no logging call of any kind.

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
- **AppKit / UIKit**: `IDEDetector` is declared `@MainActor` and conforms
  to `ObservableObject`, publishing `detectedIDEs` and `isDetecting` as
  `@Published` properties; `detect()` dispatches the scan onto
  `DispatchQueue.global(qos: .userInitiated)` and publishes the result back
  on `DispatchQueue.main`, guarding against a deallocated instance with a
  weak-self check. `systemImageName` returns the SF Symbol name for each
  of the six cases — `"hammer.fill"` (Xcode), `"hammer"` (Xcode Workspace),
  `"shippingbox"` (Swift Package), `"chevron.left.forwardslash.chevron.right"`
  (VS Code), `"lightbulb.fill"` (IntelliJ IDEA), `"apps.iphone"` (Android
  Studio) — for use as `Image(systemName:)`/
  `NSImage(systemSymbolName:accessibilityDescription:)`. `IDEDetector.open`
  is AppKit-specific today: it resolves the associated application via
  `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and opens
  it with `NSWorkspace.shared.open(_:withApplicationAt:configuration:)`,
  falling back to the parameterless `NSWorkspace.shared.open(targetURL)`
  when no bundle identifier resolves or that call fails; a failure from the
  bundle-application path is logged with `error.localizedDescription`. A
  UIKit port has no equivalent concept of "open an external IDE
  application" and would drop that function entirely, while the
  marker-scanning half of `IDEDetector` (`scan`, `matchMarkers`,
  `isMarkerDirectory`, `detectJetBrainsType`, `relativePathString`) is
  plain Foundation and UI-framework-agnostic. Logging uses `os.Logger` via
  the shared `Loggable` protocol, with `Bundle.main.bundleIdentifier` as
  the subsystem and `IDEDetector` as the category — `LanguageDetection`
  conforms to neither `Loggable` nor any AppKit or UIKit protocol, and has
  no AppKit or UIKit dependency at all.
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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Model/Detection/` |

## Design Decisions

- **Decision**: The associated-application-identifier lookup keeps an
  optional return type even though every one of the current six cases
  returns a value.
  **Rationale**: the property's own documentation states it "Returns none
  for types that don't have a dedicated app," and the open operation
  already has a fallback branch for an absent identifier — the optional
  return type anticipates a future IDE-type case with no dedicated
  application, even though no such case exists in the source given here.
  **Approved**: pending
- **Decision**: The marker-matching step's `.xcworkspace` branch guards
  against the entry's parent directory having extension `"xcodeproj"`,
  even though the scan operation's own marker-directory exclusion already
  prevents recursing into any `.xcodeproj` directory, making that guard
  unreachable for any path the scan operation currently visits.
  **Rationale**: not explained in the source; documented here as an
  observed quirk (defensive code for a case the traversal design already
  rules out) rather than silently corrected or removed, per source
  fidelity.
  **Approved**: pending
- **Decision**: The LSP-language-id remap SHOULD remain the toolkit's one
  place that derives an LSP `languageId`, rather than every caller
  deriving it independently.
  **Rationale**: the language-server configuration component's own
  documentation explains that it sits in a lower dependency tier than the
  language-detection component's own module, and "dependencies point
  downward only," so it takes a caller-supplied plain string instead of
  importing this function — duplicating the remap table elsewhere risks
  reintroducing the `cSharp`/`csharp`-style mismatches this function
  exists to fix.
  **Approved**: pending
- **Decision**: The scan operation's two top-level listing calls fail
  differently — a failed visible-entries call aborts the whole scan
  (returns an empty result), while a failed hidden-entries call only drops
  hidden entries and continues.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/files/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
