<!-- leaf: implement-file-system/detection · source: file-system-detection.md -->

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
