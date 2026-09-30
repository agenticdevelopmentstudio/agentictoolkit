<!-- leaf: implement-language/services-editor--logging · source: language-services-editor.md -->

# LanguageServicesEditor

## Logging

Four of the twelve types conform to `Loggable`, each using the shared pattern of a `static nonisolated let logger` whose subsystem is the host app's bundle identifier and whose category is the conforming type's own name:

- `LSPCompletionDelegate` logs, via `logger.error`, a discarded `additionalTextEdits` conflict.
- `SemanticTokenHighlightProvider` logs, via `Self.logger.error`, a ragged (non-multiple-of-five) token response and a dropped-overlap token.
- `OpenDocumentReloader` logs, via `Self.logger.notice`, a dirty-buffer conflict between a local edit and a disk change.
- `TextDocumentCoordinator` logs, via `Self.logger.error`, the count and identifiers of documents `terminate()` could not flush.

`LSPHoverController` and `LSPJumpToDefinitionDelegate` conform to `Loggable` nowhere in either file; see the `lsp-request-failure-unsignaled` requirement for what this leaves unsignaled.
