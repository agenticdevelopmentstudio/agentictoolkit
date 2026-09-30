<!-- leaf: implement-file/editor-view--logging · source: file-editor-view.md -->

# FileEditorView

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: varies by emitting type — see table

| Event | Level | Message | Category |
|-------|-------|---------|----------|
| File loaded successfully | info | `Loaded file: <lastPathComponent>` | `FileEditorState` |
| File could not be read | error | `Cannot read <lastPathComponent>` | `FilePreviewLoader` |

An autosave write failure is logged at error level (`Auto-save failed for <uri>: <reason> — still pending, will retry`) by the injected `TextDocumentSaveScheduler`, not by `FileEditorView.swift` or `FileEditorState.swift` directly; it is included here because this component is what triggers every autosave this log line can report.
