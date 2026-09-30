<!-- leaf: implement-file-system/detection--part-4 · source: file-system-detection.md -->

# File System Detection — continued (part 4)

**Rules** (cite as `implement-file-system/detection--part-4#<slug>`):

- `decision` SHOULD — lspLanguageId(for:) SHOULD remain the toolkit's one place that derives an LSP languageId, rather than every caller …

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
