<!-- leaf: implement-file/editor-view--edge-cases · source: file-editor-view.md -->

# FileEditorView

**Rules** (cite as `implement-file/editor-view--edge-cases#<slug>`):

- `null-empty-input` MUST — selectedNode == nil unloads the editor and shows the empty placeholder (see non-openable-selection-clears-editor). MUST.
- `boundary-exact-size-threshold` MUST — A file of exactly 8,388,608 bytes (FilePreviewLoader.maximumTextSize) is at the threshold, not over it (size > …
- `boundary-cache-exactly-at-its-bound` MUST — With 8 documents already cached, opening a 9th distinct file evicts exactly one (the least-recently-selected), never …
- `boundary-zero-byte-file` MUST — A file of 0 bytes has a size under the threshold; Data(contentsOf:) succeeds and decodes as an empty UTF-8 string, so …
- `concurrent-access` MUST — FileEditorState is @MainActor, so load(from:), unload(), and every cache mutation are serialized on the main actor; a …
- `error-states` MUST — A disk read that throws or returns no data is shown as .unavailable and logged at error level; a UTF-8 decode failure …

## Edge Cases

- **Null/empty input**: `selectedNode == nil` unloads the editor and shows the empty placeholder (see **non-openable-selection-clears-editor**). MUST.
- **Boundary — exact size threshold**: A file of exactly 8,388,608 bytes (`FilePreviewLoader.maximumTextSize`) is at the threshold, not over it (`size > maximumTextSize`), so it is still a text-editor candidate, decoded as UTF-8 or, failing that, routed to QuickLook like any other file; only a file strictly larger than the threshold is forced to QuickLook regardless of its content. MUST (see **oversize-file-uses-quicklook**).
- **Boundary — cache exactly at its bound**: With 8 documents already cached, opening a 9th distinct file evicts exactly one (the least-recently-selected), never more and never fewer, keeping the cache at 8. MUST (see **cache-bound-is-eight**, **eviction-is-least-recently-selected**).
- **Boundary — zero-byte file**: A file of 0 bytes has a size under the threshold; `Data(contentsOf:)` succeeds and decodes as an empty UTF-8 string, so it opens as an empty text document rather than being treated as unreadable or oversized. MUST.
- **Concurrent access**: `FileEditorState` is `@MainActor`, so `load(from:)`, `unload()`, and every cache mutation are serialized on the main actor; a same-URL re-entrant call while a read is already in flight is a documented no-op rather than a race (see **same-url-reselection-is-noop** and the source comment on why the cancel is ordered after, not before, that guard). A slow read superseded by a newer selection is cancelled and its result discarded via a `Task.isCancelled`/current-URL check before it is applied. MUST.
- **Error states**: A disk read that throws or returns no data is shown as `.unavailable` and logged at error level; a UTF-8 decode failure on successfully-read bytes is routed to QuickLook instead (see **unreadable-file-is-unavailable**, **undecodable-utf8-uses-quicklook**) — these are two distinct, deliberately different outcomes for two different failure points in the same read, not one collapsed "can't open" state. An autosave write failure leaves the document dirty and pending, retried in the background by the injected `TextDocumentSaveScheduler`, with no error surfaced by this component (see **autosave-failure-has-no-visible-indicator**). Both are documented exactly as the source implements them, not idealized with error UI the source does not have. MUST.
- **Offline or disconnected state**: Not applicable. All I/O this component performs — reading and writing file content, and communicating with project language servers — is local (disk access and local language-server processes); no networking call appears anywhere in `FileEditorView.swift` or `FileEditorState.swift`.
