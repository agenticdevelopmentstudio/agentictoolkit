<!-- leaf: implement-file-system/detection--edge-cases · source: file-system-detection.md -->

# File System Detection

**Rules** (cite as `implement-file-system/detection--edge-cases#<slug>`):

- `null-empty-input-empty-root-directory` MUST — scan(rootURL:) on a root with zero entries MUST return [] without error, via the same path as any other empty result. …
- `null-empty-input-empty-file-extension` MUST — language(for:) on a URL whose pathExtension is "" MUST skip the custom-mapping lookup entirely (per !ext.isEmpty) and …
- `null-empty-input-empty-project-path` MUST — open(project: rootURL:) with project.path == "" MUST resolve targetURL to rootURL itself (appendingPathComponent("") is …
- `boundary-values-recursion-depth` MUST — A marker two or more directories below the root (e.g. a/b/Package.swift) MUST NOT be found — scan-recurses-one-level …
- `concurrent-access-within-one-idedetector` MUST — Overlapping detect() calls on the same instance MUST be serialized to at most one in-flight scan by the isDetecting …
- `concurrent-access-across-idedetector-instances` MUST — scan(rootURL:) and its helpers touch only their own arguments and the file system, so concurrent scans on different …
- `error-states-unreadable-directory-at-any-scanned-level` MUST — Every contentsOfDirectory call in scan, matchMarkers, and detectJetBrainsType is wrapped in try?; none of them throw …
- `error-states-nsworkspace-open-failure` MUST — The bundle-application path logs and swallows the error (open-bundle-path-failure-logged-only, MUST); the fallback path …

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
