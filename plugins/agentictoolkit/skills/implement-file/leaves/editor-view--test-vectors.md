<!-- leaf: implement-file/editor-view--test-vectors · source: file-editor-view.md -->

# FileEditorView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| file-editor-view-001 | onappear-shows-selection | Mount the view with `selectedNode` already set to an openable file | The file's content is loaded and shown without waiting for a selection change |
| file-editor-view-002 | selection-change-shows-selection | Change `selectedNode` from one openable file to another | The newly selected file's content is loaded and shown |
| file-editor-view-003 | openable-node-excludes-directories | `selectedNode.isDirectory == true`, `isPackage == false` | The editor clears/unloads; the empty placeholder is shown |
| file-editor-view-004 | openable-node-excludes-packages | `selectedNode.isPackage == true`, `isDirectory == true` | The editor clears/unloads; the empty placeholder is shown, not the package's contents |
| file-editor-view-005 | openable-node-loads | `selectedNode` is a regular, readable text file | `FileEditorState.load(from:)` is invoked with that node's `url` |
| file-editor-view-006 | non-openable-selection-clears-editor | `selectedNode` transitions from an openable file to `nil` | The editor unloads; display becomes empty |
| file-editor-view-007 | same-url-reselection-is-noop | Call `load(from:)` twice in a row with the same URL | No new read task starts; the display and cached editors are unchanged after the second call |
| file-editor-view-008 | cached-uri-shown-without-reread | Select file A, then file B, then re-select file A (still cached) | File A displays immediately with no `.loading` state and no new disk read |
| file-editor-view-009 | new-uri-shows-loading | Select a file at or under the size threshold, not yet in the cache, whose read is slowed/stubbed | Display becomes `.loading` before the read completes |
| file-editor-view-010 | oversize-file-uses-quicklook | A file of size 8,388,609 bytes (one over the threshold), valid UTF-8 | Display becomes `.quickLook`, not `.text` |
| file-editor-view-011 | undecodable-utf8-uses-quicklook | A file at 100 bytes containing invalid UTF-8 byte sequences | Display becomes `.quickLook`, not `.unavailable` |
| file-editor-view-012 | unreadable-file-is-unavailable | A file whose path no longer exists on disk at read time | Display becomes `.unavailable`; an error is logged |
| file-editor-view-013 | text-file-opens-editor | A 1 KB file of valid UTF-8 text | Display becomes `.text(uri:)`; the file's `SourceEditor` is mounted |
| file-editor-view-014 | cache-bound-is-eight | Open 9 distinct files in sequence, never revisiting one | After the 9th open, exactly 8 documents remain in the cache |
| file-editor-view-015 | eviction-is-least-recently-selected | Open files A..H (filling the cache), re-select A, then open file I | File B (the least recently selected, not A) is evicted, not A |
| file-editor-view-016 | evicted-document-flushes-and-closes | Evict a document with an unsaved edit pending | Its pending autosave is written before its store reference is closed |
| file-editor-view-017 | editor-never-rebuilt-while-cached | Select file A, select file B, re-select file A | The `SourceEditor`/host instance for file A is the same object instance across both selections of A |
| file-editor-view-018 | exactly-one-editor-visible | Two documents are cached, one active | The active document's host has `isHidden == false`; the other has `isHidden == true` |
| file-editor-view-019 | container-hides-when-nothing-visible | `display` is `.empty` (no active document) | The cached-editor container's `isHidden == true` |
| file-editor-view-020 | focus-follows-shown-editor | This pane holds first responder; switch the active document | First responder moves to the newly shown editor's text view |
| file-editor-view-021 | focus-not-stolen-from-elsewhere | A view outside this pane holds first responder; switch the active document | First responder is unchanged; it does not move to the editor |
| file-editor-view-022 | focus-released-when-empty | This pane holds first responder; selection changes to `nil` | First responder becomes `nil` |
| file-editor-view-023 | dirty-edit-schedules-save | Type a character into the active document | The document is scheduled with the autosave scheduler |
| file-editor-view-024 | clean-document-not-scheduled | The document's change handler fires while `isDirty == false` | No autosave is scheduled |
| file-editor-view-025 | outgoing-edits-precede-incoming-read | Edit file A (dirty), then select not-yet-cached file B | File A's pending write completes before file B's bytes are read from disk |
| file-editor-view-026 | teardown-flushes-every-cached-document | Deallocate the pane with 3 cached documents, one dirty | All 3 are flushed and closed on the shared store before teardown completes |
| file-editor-view-027 | language-features-require-services | Construct the view with `languageServices == nil`; open a Swift file | The cached document has no completion delegate, jump-to-definition delegate, annotation coordinator, or semantic highlight provider |
| file-editor-view-028 | jump-to-definition-requires-openfile-callback | `languageServices` is non-nil, `openFile == nil` | The cached document's jump-to-definition delegate is `nil` |
| file-editor-view-029 | semantic-highlight-takes-priority | A document with both a semantic provider and tree-sitter, with overlapping styled ranges | The semantic provider's style wins the overlap |
| file-editor-view-030 | trigger-characters-reresolved-on-session-change | A language server session starts after a document is already open | The document's trigger-character set is re-resolved and, if changed, republished |
| file-editor-view-031 | editor-follows-environment-theme | Switch the active app theme while a document is open | The mounted editor's colors update to the new theme without reopening the file |
| file-editor-view-032 | editor-config-reflects-live-options | Toggle "show line numbers" while a document is open | The mounted editor's gutter visibility changes without reopening the file |
| file-editor-view-033 | wrap-lines-disabled | Inspect the `SourceEditorConfiguration.appearance` passed to any mounted editor | `wrapLines == false` |
| file-editor-view-034 | read-failure-shows-placeholder-only | Select a file with no read permission | The "Cannot open this file" placeholder is shown; no alert or dialog appears |
| file-editor-view-035 | autosave-failure-has-no-visible-indicator | Force the injected write function to throw for a dirty document | No error UI appears in this component; the document remains marked dirty and is not discarded |
