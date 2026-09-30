<!-- leaf: implement-file/editor-view · source: file-editor-view.md -->

**Rules** (cite as `implement-file/editor-view#<slug>`):

- `onappear-shows-selection` MUST
- `selection-change-shows-selection` MUST
- `openable-node-excludes-directories` MUST
- `openable-node-excludes-packages` MUST
- `openable-node-loads` MUST
- `non-openable-selection-clears-editor` MUST
- `same-url-reselection-is-noop` MUST
- `cached-uri-shown-without-reread` MUST
- `new-uri-shows-loading` MUST
- `oversize-file-uses-quicklook` MUST
- `undecodable-utf8-uses-quicklook` MUST
- `unreadable-file-is-unavailable` MUST
- `text-file-opens-editor` MUST
- `cache-bound-is-eight` MUST
- `eviction-is-least-recently-selected` MUST
- `evicted-document-flushes-and-closes` MUST
- `editor-never-rebuilt-while-cached` MUST
- `exactly-one-editor-visible` MUST
- `container-hides-when-nothing-visible` MUST
- `focus-follows-shown-editor` MUST
- `focus-not-stolen-from-elsewhere` MUST
- `focus-released-when-empty` MUST
- `dirty-edit-schedules-save` MUST
- `clean-document-not-scheduled` MUST
- `outgoing-edits-precede-incoming-read` MUST
- `teardown-flushes-every-cached-document` MUST
- `language-features-require-services` MUST
- `jump-to-definition-requires-openfile-callback` MUST
- `semantic-highlight-takes-priority` MUST
- `trigger-characters-reresolved-on-session-change` MUST
- `editor-follows-environment-theme` MUST
- `editor-config-reflects-live-options` MUST
- `wrap-lines-disabled` MUST
- `read-failure-shows-placeholder-only` MUST
- `autosave-failure-has-no-visible-indicator` MUST

# FileEditorView

## Overview

`FileEditorView` (`packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/FileEditorView.swift`) is the content pane of a file browser: given the file tree's currently `selectedNode`, it shows that file's contents — an editable, syntax-highlighted source editor for text, QuickLook for everything else (images, PDFs, movies, oversized or non-UTF-8 files) — or a placeholder when nothing openable is selected. It owns a private `FileEditorState` (`FileEditorState.swift`, in the same directory), created once at `init` via `@StateObject`, which does all of the actual work: reading the file, classifying it (via `FilePreviewLoader.swift`), keeping up to 8 recently-viewed documents live in a bounded, undo-preserving cache, wiring each to autosave and to this project's language services, and deciding what `display` state the view renders. This recipe covers `FileEditorView`, `FileEditorState`, `FilePreviewLoader`, and the file-private `EditorPlaceholderView`/`FileEditorContentView`/`CachedEditorStack`/`CachedEditorStackView` types declared alongside them — together, one component, since none of them is meaningful in isolation. `QuickLookPreview.swift` (a thin `NSViewRepresentable` wrapper around `QLPreviewView`) and `CodeEditSourceEditor`'s `SourceEditor` are out of scope: this recipe documents how and when they are shown, not their own internal rendering or accessibility. Colors and font come from the app theme in the environment (`SemanticPalette`/`themePalette`), so the editor follows a theme switch like the rest of the UI.

## Behavioral Requirements

### Selection & Display Routing

- **onappear-shows-selection**: The component MUST show the current selection's content when the view first appears.
- **selection-change-shows-selection**: The component MUST re-evaluate and show the selection's content whenever `selectedNode` changes.
- **openable-node-excludes-directories**: A `selectedNode` whose `isDirectory` is `true` MUST NOT be treated as an openable file.
- **openable-node-excludes-packages**: A `selectedNode` whose `isPackage` is `true` MUST NOT be treated as an openable file, even when `isDirectory` is also `true`.
- **openable-node-loads**: An openable `selectedNode` MUST be loaded from its `url`.
- **non-openable-selection-clears-editor**: A `nil` `selectedNode`, or one that is not openable, MUST clear the currently displayed file.
- **same-url-reselection-is-noop**: Loading a URL that is already the one currently shown MUST leave the display and every cached editor unchanged — it MUST NOT cancel or restart the current read.

### Content Classification

- **cached-uri-shown-without-reread**: A URI already present in the document cache MUST be shown immediately, without re-reading the file from disk and without rebuilding its editor.
- **new-uri-shows-loading**: A URI not yet cached MUST show a loading indicator while its content is being read from disk.
- **oversize-file-uses-quicklook**: A file larger than 8,388,608 bytes (8 MiB) MUST be shown via QuickLook rather than opened in the text editor.
- **undecodable-utf8-uses-quicklook**: A file at or under that size threshold whose bytes cannot be decoded as UTF-8 MUST be shown via QuickLook, not marked unavailable.
- **unreadable-file-is-unavailable**: A file whose bytes cannot be read at all (permission denied, the file no longer exists, or any other read failure) MUST be shown as unavailable, not passed to QuickLook.
- **text-file-opens-editor**: A file at or under the size threshold whose bytes decode as UTF-8 MUST be opened as a cached document in the text editor.

### Caching, Eviction, and Undo Preservation

- **cache-bound-is-eight**: The component MUST keep at most 8 documents live in its cache at one time.
- **eviction-is-least-recently-selected**: When opening a document would exceed the cache bound, the least-recently-selected cached document other than the one just opened MUST be evicted.
- **evicted-document-flushes-and-closes**: Evicting a cached document MUST flush its pending autosave and release its reference on the shared document store.
- **editor-never-rebuilt-while-cached**: A document's text editor MUST NOT be rebuilt or remounted for as long as that document's URI remains in the cache.
- **exactly-one-editor-visible**: Of every mounted cached editor, at most one — the active document's, when one is active — MUST be visible at a time, and exactly one MUST be visible when a text document is active; every other mounted editor MUST be hidden by removing it from hit-testing and keyboard-focus eligibility (`isHidden`), not by making it transparent.
- **container-hides-when-nothing-visible**: The editor container itself MUST be hidden when no cached editor is currently the active one, so it does not intercept clicks or scrolling meant for whatever is drawn beneath it (e.g., a QuickLook preview).
- **focus-follows-shown-editor**: When the active document changes and this pane, or nothing, already held keyboard focus, focus MUST move to the newly shown editor.
- **focus-not-stolen-from-elsewhere**: Focus MUST NOT be moved to the newly shown editor when a view outside this pane currently holds keyboard focus.
- **focus-released-when-empty**: When no document is being shown and this pane held keyboard focus, that focus MUST be given up rather than left on a hidden editor.

### Autosave & Persistence

The debounce window is the injected `TextDocumentSaveScheduler`'s own setting (`TextDocumentSaveScheduler.init(debounce:)`), 1 second by default; this component neither sets nor reads that value, it only calls `schedule(_:)`.

- **dirty-edit-schedules-save**: Every edit to a cached document MUST schedule that document for a debounced autosave.
- **clean-document-not-scheduled**: A document with no unsaved changes MUST NOT be scheduled for autosave when its change notification fires.
- **outgoing-edits-precede-incoming-read**: Switching away from a document to a different, not-yet-cached document MUST cause the outgoing document's pending autosave to be written before the new document's bytes are read from disk.
- **teardown-flushes-every-cached-document**: When this component is deallocated, every document still in its cache MUST have its pending autosave flushed and be closed on the shared document store.

### Language Services

- **language-features-require-services**: Code completion, jump-to-definition, semantic highlighting, and diagnostic annotations for a cached document MUST all be absent when no project language services were supplied.
- **jump-to-definition-requires-openfile-callback**: The jump-to-definition feature for a cached document MUST be absent when no callback for opening another file was supplied, even when project language services are present.
- **semantic-highlight-takes-priority**: When a cached document has a semantic highlight provider, it MUST take priority over the tree-sitter provider for any overlapping styled range.
- **trigger-characters-reresolved-on-session-change**: A cached document's code-completion trigger characters MUST be re-resolved whenever the language-server registry's set of sessions or any session's state changes.

### Theming & Live Configuration

- **editor-follows-environment-theme**: The text editor's chrome and syntax colors MUST be derived from the semantic theme palette in the environment, not from a fixed, hardcoded palette.
- **editor-config-reflects-live-options**: A change to the pane's line-numbers, minimap ("overview"), or invisible-characters display option MUST reach an already-mounted editor without reopening the file.
- **wrap-lines-disabled**: The text editor MUST be configured with line wrapping disabled.

### Error Handling

- **read-failure-shows-placeholder-only**: A file the component cannot read MUST show the "Cannot open this file" placeholder; the component MUST NOT present any additional error dialog, alert, or retry control.
- **autosave-failure-has-no-visible-indicator**: A failed autosave write MUST NOT be surfaced to the user by this component; the affected document remains marked dirty and MUST NOT be discarded. Retrying the write is the injected `TextDocumentSaveScheduler`'s own responsibility, not this component's — see that type's own documentation for its retry behavior.

## Appearance

- **Corner radius**: None. No corner radius is set anywhere in `FileEditorView.swift`.
- **Padding**: None set directly. Every top-level view (`FileEditorView.body`, `FileEditorContentView.body`, the placeholder, loading, QuickLook, and unavailable branches) is given `.frame(maxWidth: .infinity, maxHeight: .infinity)` with no additional inset; the sole internal spacing is the placeholder's own `VStack(spacing: 12)` between its icon and message.
- **Font**: The text editor's font is `palette.font(.code)`, resolved from the environment theme (see `editorConfiguration(for:palette:)`). The placeholder message uses `theme.font(.heading)`. The placeholder icon is a literal 48pt system-image size (`Image(systemName: "doc.text").font(.system(size: 48))`), not a theme font role, so unlike the message it does not scale with the theme's text-size preference.
- **Background**: No background is set directly by `FileEditorView.swift` on any of its own views; the mounted editors and QuickLook preview paint their own backgrounds (the editor's from `palette.editorTheme.background`, derived from the theme's `windowBackground`).
- **Foreground/Text**: Placeholder icon — theme `tertiaryText`. Placeholder message — theme `secondaryText`. The editor's text, cursor, selection, and syntax colors all come from `palette.editorTheme` (see Design Decisions and Platform Notes).
- **Border**: None specified in source.
- **Shadow**: None specified in source.
- **Min/Max size**: `.frame(maxWidth: .infinity, maxHeight: .infinity)` is applied at every level (the root view, the content view, each display-state branch, and the cached-editor container), so the pane always expands to fill its container; no minimum width or height is set anywhere.

