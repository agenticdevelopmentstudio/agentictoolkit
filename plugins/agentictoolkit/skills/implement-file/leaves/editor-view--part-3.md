<!-- leaf: implement-file/editor-view--part-3 · source: file-editor-view.md -->

# FileEditorView — continued (part 3)

## Design Decisions

**Decision**: `body` mounts one always-live content view (`FileEditorContentView`/`CachedEditorStack`) rather than switching between conditional SwiftUI branches per display state.
**Rationale**: A conditional SwiftUI branch is destroyed by SwiftUI the moment the condition it depends on no longer holds; selecting a directory used to switch such a branch and tore down every cached `SourceEditor` — and its undo stack — at once. Keeping one container mounted for the life of the view and only toggling visibility inside it is what lets a document's undo history survive switching away from and back to it.
**Approved**: pending

**Decision**: Cached editors are hidden with AppKit's `isHidden`, never with opacity or `alphaValue`.
**Rationale**: `alphaValue == 0` does not exclude a view from `hitTest(_:)` or from `canBecomeKeyView`, so a transparent "hidden" editor still took clicks and still answered Tab — putting keystrokes into a document the user could not see, which the autosave scheduler would then dutifully write to disk. `isHidden` is AppKit's documented exclusion from both.
**Approved**: pending

**Decision**: A file whose bytes fail UTF-8 decoding is routed to QuickLook, while a file whose bytes cannot be read at all is marked unavailable.
**Rationale**: `FilePreviewLoader.read(_:)` treats a successful disk read of non-UTF-8 bytes as a QuickLook candidate — the same bucket as images, PDFs, and movies — and reserves `.unavailable` for the disk read itself failing. These are two different failure points in the same function, and the recipe preserves that distinction rather than collapsing both into one "can't open" outcome.
**Approved**: pending

**Decision**: A failed autosave write is retried in the background with no user-facing error, alert, or retry control.
**Rationale**: `TextDocumentSaveScheduler` keeps a failed write's document pending and dirty rather than discarding it, so the edit is never lost even though the user is never told a write failed. An alert on every transient failure (a sleeping external disk, a momentarily full volume) was judged worse than a silent, safe retry.
**Approved**: pending

**Decision**: Focus moves to a newly shown editor only when this pane already held focus or nothing did; it is never taken unconditionally.
**Rationale**: The file tree changes `selectedNode` on every arrow-key press. Taking first responder unconditionally on every selection change would steal focus from the tree after its very first keypress, making the tree impossible to navigate from the keyboard.
**Approved**: pending
