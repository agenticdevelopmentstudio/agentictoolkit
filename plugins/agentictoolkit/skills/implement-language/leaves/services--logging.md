<!-- leaf: implement-language/services--logging · source: language-services.md -->

# LanguageServices

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: `TextDocumentSaveScheduler`

| Event | Level | Message |
|-------|-------|---------|
| An autosave write throws | error | `Auto-save failed for <uri>: <reason> — still pending, will retry` |

`TextDocument.swift`, `TextDocumentStore.swift`, and `URL+DocumentUri.swift` make no logging call of their own; only `TextDocumentSaveScheduler` logs, through its `Loggable` conformance, and only on a failed write.
