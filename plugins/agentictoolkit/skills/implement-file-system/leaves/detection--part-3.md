<!-- leaf: implement-file-system/detection--part-3 · source: file-system-detection.md -->

# File System Detection — continued (part 3)

**Rules** (cite as `implement-file-system/detection--part-3#<slug>`):

- `lsp-language-id-default-passthrough` MUST
- `lsp-language-id-single-authority` SHOULD

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
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | `URL` | — (required) | The directory `IDEDetector.scan(rootURL:)` scans and `open(project: rootURL:)` resolves `project.path` against; fixed for the life of an `IDEDetector` instance via `init(rootURL:)`. |
| `project` | `IDEProject` | — (required) | The marker `IDEDetector.open(project: rootURL:)` opens. |
| `url` | `URL` | — (required) | The file `LanguageDetection.language(for:)` resolves a `CodeLanguage` for. |
| `language` | `CodeLanguage` | — (required) | The value `LanguageDetection.lspLanguageId(for:)` remaps to an LSP `languageId`. |
| `CustomFileTypeMappings.activeDefaultsKey` | `String` | `FileTreeConfig.default.customMappingsDefaultsKey` | UserDefaults key `language(for:)` indirectly reads through `mapping(for:)`; host apps override it at startup so per-window/per-project custom mappings can be kept separate. |
| `CustomFileTypeMappings.contributedProvider` | `(@Sendable (String) -> CustomFileTypeMapping?)?` | `nil` | Optional extension-contributed mapping source `mapping(for:)` falls back to when the user's own saved mappings do not claim an extension; set once by the host, not read directly by `LanguageDetection.swift`. |

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

