---
id: 9b1b54d5-e514-479f-b9f9-0a03cf4ebbc9
title: FileEditorView
domain: agentictoolkit://recipes/file-editor-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Shows the file browser's selection — cached, syntax-highlighted text with
  per-document undo, QuickLook for other files, placeholders otherwise.
platforms:
- swift
- macos
tags:
- file-browser
- editor
- quicklook
- autosave
- macos
depends-on: []
related:
- agentictoolkit://recipes/document-editor-view-controller
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

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

## States

| State | Appearance change |
|-------|------------------|
| Empty (`selectedNode == nil`, or a directory/package is selected) | Shows the placeholder: 48pt `doc.text` icon in `tertiaryText`, "Select a file to view its contents" in `theme.font(.heading)` / `secondaryText` |
| Loading (a not-yet-cached file is being read) | Shows a centered `ProgressView`, filling the available space |
| Text (a cached document is active) | The active document's own cached `SourceEditor` is shown; every other cached editor is mounted but hidden |
| QuickLook (oversized or non-UTF-8 file) | Shows `QuickLookPreview`, Finder's own renderer for that file; a format QuickLook has no generator for draws its own "no preview available" (out of scope — QuickLook's own behavior) |
| Unavailable (the file could not be read) | Shows the placeholder: 48pt `doc.text` icon in `tertiaryText`, "Cannot open this file" in `theme.font(.heading)` / `secondaryText` |
| Pressed | Not applicable: `FileEditorView` itself defines no button or tappable control; a mounted `SourceEditor`'s own pressed/click appearance is out of scope. |
| Disabled | Not applicable: the component has no enabled/disabled concept of its own; nothing it directly renders is conditionally interactive. |
| Focused | This component moves AppKit's first responder to the newly shown editor's text view when this pane already held focus or held none (see **focus-follows-shown-editor**, **focus-not-stolen-from-elsewhere**, **focus-released-when-empty**); the focus ring itself is drawn by the hosted editor, out of scope. |

## Accessibility

- **Role/trait**: `FileEditorView.swift` sets no explicit accessibility role, trait, or identifier anywhere in this file. The placeholder's `Text` and `Image(systemName: "doc.text")` carry SwiftUI's automatic default behavior (a spoken static-text element, and a label derived from the SF Symbol's name) — neither is overridden or suppressed. The mounted `SourceEditor`'s and `QuickLookPreview`'s own accessibility behavior is out of scope for this recipe.
- **Label requirements**: No `.accessibilityLabel`, `.accessibilityValue`, or `.accessibilityHint` modifier appears anywhere in `FileEditorView.swift`; the placeholder relies entirely on SwiftUI's automatic labels for its `Text` and `Image`.
- **Announce state changes**: Switching `display` between empty, loading, text, QuickLook, and unavailable replaces the content shown inside the one always-mounted `FileEditorContentView`, but neither `FileEditorView.swift` nor `FileEditorState.swift` posts any explicit accessibility notification (e.g., a layout-changed or screen-changed post) when that switch happens; a VoiceOver user is told about the new content only if SwiftUI/AppKit's own automatic change detection picks it up on its own.
- **Minimum tap target**: Not applicable: `FileEditorView` targets macOS pointer and keyboard input and defines no tappable or clickable control of its own; the mounted editor's and QuickLook's own hit targets are out of scope.

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

## Edge Cases

- **Null/empty input**: `selectedNode == nil` unloads the editor and shows the empty placeholder (see **non-openable-selection-clears-editor**). MUST.
- **Boundary — exact size threshold**: A file of exactly 8,388,608 bytes (`FilePreviewLoader.maximumTextSize`) is at the threshold, not over it (`size > maximumTextSize`), so it is still a text-editor candidate, decoded as UTF-8 or, failing that, routed to QuickLook like any other file; only a file strictly larger than the threshold is forced to QuickLook regardless of its content. MUST (see **oversize-file-uses-quicklook**).
- **Boundary — cache exactly at its bound**: With 8 documents already cached, opening a 9th distinct file evicts exactly one (the least-recently-selected), never more and never fewer, keeping the cache at 8. MUST (see **cache-bound-is-eight**, **eviction-is-least-recently-selected**).
- **Boundary — zero-byte file**: A file of 0 bytes has a size under the threshold; `Data(contentsOf:)` succeeds and decodes as an empty UTF-8 string, so it opens as an empty text document rather than being treated as unreadable or oversized. MUST.
- **Concurrent access**: `FileEditorState` is `@MainActor`, so `load(from:)`, `unload()`, and every cache mutation are serialized on the main actor; a same-URL re-entrant call while a read is already in flight is a documented no-op rather than a race (see **same-url-reselection-is-noop** and the source comment on why the cancel is ordered after, not before, that guard). A slow read superseded by a newer selection is cancelled and its result discarded via a `Task.isCancelled`/current-URL check before it is applied. MUST.
- **Error states**: A disk read that throws or returns no data is shown as `.unavailable` and logged at error level; a UTF-8 decode failure on successfully-read bytes is routed to QuickLook instead (see **unreadable-file-is-unavailable**, **undecodable-utf8-uses-quicklook**) — these are two distinct, deliberately different outcomes for two different failure points in the same read, not one collapsed "can't open" state. An autosave write failure leaves the document dirty and pending, retried in the background by the injected `TextDocumentSaveScheduler`, with no error surfaced by this component (see **autosave-failure-has-no-visible-indicator**). Both are documented exactly as the source implements them, not idealized with error UI the source does not have. MUST.
- **Offline or disconnected state**: Not applicable. All I/O this component performs — reading and writing file content, and communicating with project language servers — is local (disk access and local language-server processes); no networking call appears anywhere in `FileEditorView.swift` or `FileEditorState.swift`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `selectedNode` | `FileTreeNode?` | required, supplied by the caller on every render | The file-tree node to show; `nil`, a directory, or a package clears the editor. |
| `documentStore` | `TextDocumentStore` | required at init | The app-wide, reference-counted open-document registry; shared across every editor pane in the app. |
| `saveScheduler` | `TextDocumentSaveScheduler` | required at init | The app-wide debounced autosave scheduler; shared across every editor pane. |
| `languageServices` | `ProjectLanguageServices?` | required at init (may be `nil`) | This project's language servers; `nil` disables completion, jump-to-definition, semantic highlighting, and diagnostic annotations for every document this pane opens. |
| `options` | `EditorOptionsOverride` | required at init | This pane's resolved line-numbers/minimap ("overview")/invisible-characters display settings; a later change reaches every mounted editor live. |
| `openFile` | `(@MainActor (URL) -> Void)?` | required at init (may be `nil`) | Callback for showing a cross-file go-to-definition target; `nil` disables jump-to-definition for every document this pane opens. |

## Deep Linking

Not applicable: `FileEditorView` has no URL scheme, route, or deep-link entry point in source. It displays a `selectedNode` already chosen and supplied by its owner (a file tree/browser), and any URL it cannot open itself is reported outward through the caller-supplied `openFile` callback rather than being navigated to directly.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — hardcoded literal, `String`, not `LocalizedStringKey`) | "Select a file to view its contents" | Placeholder shown when nothing openable is selected |
| (none — hardcoded literal, `String`, not `LocalizedStringKey`) | "Cannot open this file" | Placeholder shown when the selected file could not be read |

Both placeholder strings are passed as a Swift `String` (`EditorPlaceholderView.message: String`), not a `LocalizedStringKey`, so `Text(message)` renders each verbatim with no bundle lookup, unlike a string literal passed directly to `Text(_:)` at a call site typed to accept a `LocalizedStringKey`. Neither string is routed through `String(localized:)` or a strings catalog anywhere in `FileEditorView.swift`.

## Accessibility Options

Document which accessibility display options (see agenticdevelopercookbook://guidelines/implementing/accessibility/accessibility#respect-accessibility-display-options) this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or `withAnimation` call appears anywhere in `FileEditorView.swift` or `FileEditorState.swift`; the switch between the empty, loading, text, QuickLook, and unavailable states, and the switch between cached editors, is an instantaneous state/`isHidden` change, not an animated one, so there is no motion for this setting to reduce. |
| Increase Contrast | Not observed in this file: every color this component sets directly (`tertiaryText`, `secondaryText`) and every color the mounted editor uses (`palette.editorTheme`) is resolved through the semantic theme system; any contrast adaptation is that system's responsibility, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: none of this component's own states (empty, loading, text, QuickLook, unavailable) are distinguished from one another by color alone — each is a structurally distinct view or a distinct placeholder message. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in `FileEditorView.swift` or `FileEditorState.swift`. The line-numbers/minimap/invisibles toggles are user-configurable display preferences (`EditorOptionsOverride`/`UserSettings`), not feature flags gating this component's existence.

## Analytics

Not applicable: no analytics event is emitted anywhere in `FileEditorView.swift` or `FileEditorState.swift`.

## Privacy

- **Data collected**: None of its own beyond the file the user has already selected in the file browser. The component reads that file's bytes into memory to display and, for text, into an editable buffer; it collects nothing else.
- **Storage**: Local disk only. Edits are written back to the same file the user opened, through the injected `TextDocumentSaveScheduler`'s debounced autosave; the in-memory cache (up to 8 documents, plus their undo history) lives only as long as this view does and is not itself persisted.
- **Transmission**: None from this component. Project language-server communication (completion, jump-to-definition, diagnostics), when `languageServices` is supplied, is a local inter-process exchange with a language server, not a network call.
- **Retention**: A file's content on disk persists per the file system's own guarantees, subject to the debounce window stated under Autosave & Persistence and the retry behavior described in Design Decisions. The in-memory cache retains a document only until it is evicted (least-recently-selected, past 8 documents) or this pane is deallocated, at which point its pending autosave is flushed and its reference released — nothing is retained beyond that.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` | Category: varies by emitting type — see table

| Event | Level | Message | Category |
|-------|-------|---------|----------|
| File loaded successfully | info | `Loaded file: <lastPathComponent>` | `FileEditorState` |
| File could not be read | error | `Cannot read <lastPathComponent>` | `FilePreviewLoader` |

An autosave write failure is logged at error level (`Auto-save failed for <uri>: <reason> — still pending, will retry`) by the injected `TextDocumentSaveScheduler`, not by `FileEditorView.swift` or `FileEditorState.swift` directly; it is included here because this component is what triggers every autosave this log line can report.

## Platform Notes

- **SwiftUI**: This is the source implementation: `FileEditorView.swift`, `FileEditorState.swift`, and `FilePreviewLoader.swift` (all in `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/FileBrowser/Views/`). `FileEditorView` is a thin SwiftUI shell around a `@StateObject` `FileEditorState`; the actual multi-document cache is a file-private `CachedEditorStack` (`NSViewRepresentable`) backed by `CachedEditorStackView`, a plain `NSView` holding one `NSHostingView<AnyView>` per cached document, each wrapping a `CodeEditSourceEditor.SourceEditor`. Non-text content is shown through `QuickLookPreview.swift`, a separate `NSViewRepresentable` around `QLPreviewView` (out of scope for this recipe).
- **Compose**: There is no Compose analogue to a persistently-mounted native view tree kept alive independent of the composition — Compose recomposes and can discard a composable's UI entirely when it leaves the tree. Reproduce the "undo survives switching files" requirement by keeping each open document's text buffer and undo state in a `ViewModel` (or `rememberSaveable`-backed holder) keyed by URI, scoped to the pane rather than to the composable, and drive visibility with `Modifier` (not adding/removing the composable from the tree) so an inactive editor's Compose state is preserved rather than torn down and rebuilt — the closest available parallel to `isHidden` never destroying the AppKit host.
- **React/Web**: Mount one code-editor instance (e.g., CodeMirror or Monaco) per open document in the DOM, and toggle the inactive ones with `display: none` — the CSS property that, like `isHidden`, also excludes the element from hit-testing and (paired with `inert` or `tabindex="-1"`) from the tab order — rather than mounting/unmounting per selection, which would recreate the editor and lose its undo history exactly as an `.id()`-forced SwiftUI remount did here. Reproduce the 8-MiB/UTF-8 classification and the QuickLook fallback with a browser file-type/size check that routes to an `<img>`/`<video>`/`<iframe>`(PDF) preview, or a "no preview available" placeholder, in place of QuickLook.
- **AppKit / UIKit**: This recipe's macOS implementation already is the AppKit/SwiftUI-hybrid pattern to follow (`CachedEditorStackView`); a UIKit (iOS) port would replace it with a `UIViewController`-containment stack — one child view controller per cached document, added via `addChild(_:)` and shown/hidden with `UIView.isHidden` (which, like AppKit's, excludes a view from both hit-testing and first-responder eligibility) — and would present non-text content with `QLPreviewController` (embedded via containment, or presented modally) in place of the macOS-only `QLPreviewView`.
- **WinUI 3**: There is no single WinUI 3 control that is this whole component's analogue; compose it from a `Grid` or `Frame` holding one child `UIElement` per cached document in a dictionary keyed by URI (mirroring `hostsByURI`), each hosting either a native text control (e.g., a syntax-highlighting `TextBox`/`RichEditBox`, or a `WebView2` hosting Monaco) or a preview surface for non-text content, since WinUI has no built-in QuickLook equivalent (a Shell preview-handler COM interop, or a `WebView2` navigated to the file, is the closest available substitute). Toggle which child is shown with `UIElement.Visibility = Visible`/`Collapsed`, never `Opacity = 0` — `Opacity` in WinUI, like `alphaValue` in AppKit, does not remove an element from hit-testing or from the tab-focus chain, which is exactly the bug `isHidden` exists here to avoid (see Design Decisions). Drive the placeholder/loading/text/preview/unavailable branches from a view-model enum mirroring `FileEditorState.Display`, bound to each branch's `Visibility`, and implement the 1-second-debounced autosave with a `DispatcherTimer` restarted on every text-changed event, matching `TextDocumentSaveScheduler`'s per-key debounce.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | partial | Internationalization |

`screen-reader-support` is partial because no accessibility notification accompanies a display-state change in this component itself (see **Announce state changes**). `dynamic-type-support` is partial because the placeholder message scales with the theme's own text-size preference while the placeholder icon's literal 48pt size does not. `contrast-ratio` is partial because every color is a semantic theme token resolved at render time, so actual contrast depends on the active theme, which this component does not control. `no-hardcoded-strings` failed because both placeholder strings (see Localization) are unlocalized `String` literals. `rtl-layout-support` is partial because every string in this file is plain Unicode text with no directional layout assumptions, but that is no evidence of mirrored-layout or bidi handling, and the editor itself — where either would actually be exercised — is out of scope for this recipe.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Claude | Initial creation from source code |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved a cookbook reference from `references` to `related`, trimmed tags to five, fixed an invalid compliance status and bolded Design Decision labels, downgraded an unsupported RTL compliance claim, stated the autosave debounce interval once and repointed its other mentions, reworded a misleading Localization marker, fixed a requirement/state contradiction over editor visibility, removed a duplicate States row, tightened two imprecise test vectors, scoped the autosave-failure requirement and its vector to this component's own behavior, replaced a bare "Rule 15" citation with a full guideline reference, fixed a WinUI 3 typo, and reconciled the Compliance table against the catalog |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
