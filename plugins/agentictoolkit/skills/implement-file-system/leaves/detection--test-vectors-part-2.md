<!-- leaf: implement-file-system/detection--test-vectors-part-2 · source: file-system-detection.md -->

# File System Detection — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| FSD-031 | language-falls-back-to-builtin-detection | A custom mapping for extension `"foo"` whose `languageName` is `"not-a-real-language"` | `language(for:)` returns whatever `CodeLanguage.detectLanguageFrom(url:)` yields for a `.foo` file (typically `.default`), not a crash or a partial match — traced to `.first(where:)` returning `nil` and falling through (no dedicated test in the given suite) |
| FSD-032 | lsp-language-id-fixed-remap | `LanguageDetection.lspLanguageId(for: CodeLanguage.objc)` | `"objective-c"` — traced to the `case .objc: return "objective-c"` branch (no dedicated test in the given suite) |
| FSD-033 | lsp-language-id-default-passthrough | `LanguageDetection.lspLanguageId(for: CodeLanguage.swift)` | `"swift"` (`language.id.rawValue`, unchanged, via the `default` branch) — traced to the `default: return language.id.rawValue` branch (no dedicated test in the given suite) |
| FSD-034 | lsp-language-id-single-authority | Repository-wide search for a second file-extension-to-LSP-`languageId` switch/table outside `LanguageDetection.swift` | None found in the given sources; `LanguageServerConfiguration.languageIds` takes caller-supplied `String`s precisely so it need not duplicate this table — traced to `LanguageServerConfiguration.swift`'s comment (no automated test; enforced by code review per the SHOULD) |
